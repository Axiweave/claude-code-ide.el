;;; claude-code-ide-mcp-sse-server.el --- Legacy MCP HTTP+SSE server for omp  -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Yu-Fu Fu

;; Author: Yu-Fu Fu <yufu@yfu.tw>
;; Maintainer: Yu-Fu Fu <yufu@yfu.tw>
;; Keywords: ai, mcp, sse, omp

;; This file is not part of GNU Emacs.

;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <https://www.gnu.org/licenses/>.

;;; Commentary:

;; This module lets oh-my-pi (omp) receive the user's active Emacs
;; selection, using the legacy MCP HTTP+SSE transport (protocol
;; revision 2024-11-05).  omp has no WebSocket MCP transport, so the
;; existing `claude-code-ide-mcp.el' WebSocket server cannot serve it.
;; stdio is impossible: omp spawns the lockfile `command' and owns its
;; stdin/stdout, and a live Emacs cannot be that child.  This server
;; therefore speaks `transport: "sse"', the same transport omp already
;; uses against the real VS Code Claude Code extension.
;;
;; It advertises itself through a lockfile in ~/.omp/ide/, accepts a
;; GET /sse connection per omp client, and pushes `selection_changed'
;; notifications to every session whose `roots/list' answer contains
;; the selected file.  It exposes no MCP tools; the empty `capabilities'
;; object returned from `initialize' is what keeps omp from calling
;; `tools/list', `resources/list', and `prompts/list'.
;;
;; Known ceiling: omp attaches to the *first* supported lockfile it
;; finds in sorted order, so with two Emacs instances running
;; simultaneously an omp client may attach to the other one.  The pid
;; sweep in `claude-code-ide-mcp-sse--sweep-stale-lockfiles' only
;; removes lockfiles left behind by a dead Emacs.

;;; Code:

(require 'json)
(require 'cl-lib)
(require 'eieio)
(require 'url-util)
(require 'claude-code-ide-debug)
(require 'claude-code-ide-mcp)

;; Require web-server at runtime to avoid batch mode issues
(unless (featurep 'web-server)
  (condition-case err
      (require 'web-server)
    (error
     (claude-code-ide-debug "Failed to load web-server package: %s" (error-message-string err)))))

;; Web-server declarations
(declare-function ws-start "web-server" (handlers port &optional log-buffer &rest network-args))
(declare-function ws-stop "web-server" (server))
(declare-function ws-process "web-server" (object))
(declare-function ws-requests "web-server" (server))
(declare-function ws-headers "web-server" (request))
(declare-function ws-body "web-server" (request))
(declare-function ws-response-header "web-server" (proc code &rest headers))
(declare-function ws-send-404 "web-server" (proc &rest msg-and-args))

;;; Constants

(defconst claude-code-ide-mcp-sse-lockfile-directory (expand-file-name "~/.omp/ide/")
  "Directory where omp discovers IDE MCP lockfiles.
This is omp's own fixed home-relative convention; it is not routed
through XDG.")

;;; State

(defvar claude-code-ide-mcp-sse--server nil
  "The `ws-start' server object, or nil when not running.")

(defvar claude-code-ide-mcp-sse--port nil
  "The port the SSE server is actually listening on, or nil.")

(defvar claude-code-ide-mcp-sse--sessions (make-hash-table :test 'equal)
  "Hash table mapping session-id strings to plists.
Each plist has the shape (:process PROC :root DIR-OR-NIL).")

(defvar claude-code-ide-mcp-sse--session-counter 0
  "Counter used to mint unique session ids.")

(defvar claude-code-ide-mcp-sse--selection-timer nil
  "Debounce timer for selection tracking, or nil.")

(defvar claude-code-ide-mcp-sse--last-state nil
  "Identity of the last selection state that was flushed, or nil.")

(defvar claude-code-ide-mcp-sse--last-payload nil
  "The last `selection_changed' payload alist that was sent, or nil.")

(defvar claude-code-ide-mcp-sse--last-file nil
  "Absolute file name the last selection payload was computed from, or nil.")

;;; Frame + write primitives

(defun claude-code-ide-mcp-sse--frame (event data)
  "Format an SSE frame for EVENT and DATA.
EVENT may be nil to omit the `event:' line.  DATA must not contain a
newline."
  (if event
      (format "event: %s\ndata: %s\n\n" event data)
    (format "data: %s\n\n" data)))

(defun claude-code-ide-mcp-sse--write (proc string)
  "Send STRING to PROC if PROC is still a live process.
The web-server listener is created with `:coding \\='no-conversion', so
STRING is explicitly encoded as UTF-8 before sending."
  (when (process-live-p proc)
    (process-send-string proc (encode-coding-string string 'utf-8))))

(defun claude-code-ide-mcp-sse--send (session-id message)
  "Encode MESSAGE as JSON and write it to the SSE stream for SESSION-ID.
No-op, with a debug log, when the session is unknown or its process
has died."
  (let ((session (gethash session-id claude-code-ide-mcp-sse--sessions)))
    (if (and session (process-live-p (plist-get session :process)))
        (let* ((json-encoding-pretty-print nil)
               (json (json-encode message)))
          (claude-code-ide-mcp-sse--write
           (plist-get session :process)
           (claude-code-ide-mcp-sse--frame nil json)))
      (claude-code-ide-debug "SSE session %s is gone; dropping message" session-id))))

;;; Lockfile helpers

(defun claude-code-ide-mcp-sse--lockfile-path ()
  "Return this Emacs' own SSE lockfile path."
  (format "%semacs-%d.json" claude-code-ide-mcp-sse-lockfile-directory (emacs-pid)))

(defun claude-code-ide-mcp-sse--lockfile-content (port)
  "Return the lockfile content alist for PORT."
  `((pid . ,(emacs-pid))
    (ideName . "Emacs")
    (transport . "sse")
    (url . ,(format "http://127.0.0.1:%d/sse" port))))

(defun claude-code-ide-mcp-sse--write-lockfile (port)
  "Write this Emacs' lockfile advertising PORT."
  (make-directory claude-code-ide-mcp-sse-lockfile-directory t)
  (with-temp-file (claude-code-ide-mcp-sse--lockfile-path)
    (insert (json-encode (claude-code-ide-mcp-sse--lockfile-content port)))))

(defun claude-code-ide-mcp-sse--remove-lockfile ()
  "Remove this Emacs' SSE lockfile, if present."
  (let ((path (claude-code-ide-mcp-sse--lockfile-path)))
    (if (file-exists-p path)
        (progn
          (delete-file path)
          (claude-code-ide-debug "SSE lockfile deleted: %s" path))
      (claude-code-ide-debug "SSE lockfile not found: %s" path))))

(defun claude-code-ide-mcp-sse--sweep-stale-lockfiles ()
  "Delete `emacs-*.json' lockfiles in the omp IDE directory left by dead Emacsen.
Only files matching the `emacs-' prefix this module owns are ever
touched; other IDEs' lockfiles in the same directory are left alone.
A lockfile that cannot be read or parsed is treated as stale too."
  (let ((dir claude-code-ide-mcp-sse-lockfile-directory))
    (when (file-directory-p dir)
      (dolist (file (directory-files dir t "\\`emacs-.*\\.json\\'"))
        (condition-case err
            (let* ((content (with-temp-buffer
                              (insert-file-contents file)
                              (json-parse-string (buffer-string) :object-type 'alist)))
                   (pid (alist-get 'pid content)))
              (unless (and pid
                           (or (eql pid (emacs-pid))
                               (memq pid (list-system-processes))))
                (delete-file file)
                (claude-code-ide-debug "Swept stale SSE lockfile: %s" file)))
          (error
           (claude-code-ide-debug "Swept unreadable SSE lockfile %s: %s" file err)
           (ignore-errors (delete-file file))))))))

;;; Session containment

(defun claude-code-ide-mcp-sse--session-wants-file-p (session file)
  "Return non-nil when SESSION's root should receive selections from FILE.
A nil root means unfiltered (fail open)."
  (let ((root (plist-get session :root)))
    (or (null root)
        (string-prefix-p (expand-file-name root) (expand-file-name file)))))

;;; JSON-RPC dispatch

(defun claude-code-ide-mcp-sse--initialize-result ()
  "Return the `initialize' result alist.
The empty `capabilities' object suppresses omp's `tools/list',
`resources/list', and `prompts/list' calls."
  `((protocolVersion . ,claude-code-ide-mcp-version)
    (capabilities . ,(make-hash-table :test 'equal))
    (serverInfo . ((name . "claude-code-ide-emacs") (version . "0.1.0")))))

(defun claude-code-ide-mcp-sse--apply-roots (session-id result)
  "Apply the `roots/list' RESULT to SESSION-ID's stored root.
Leaves the root nil (fail open) when RESULT is missing, empty, or
malformed.  Then replays the cached selection to this session alone,
so a region selected before the client connected is not lost."
  (let* ((roots (alist-get 'roots result))
         (first-root (and (vectorp roots) (> (length roots) 0) (aref roots 0)))
         (uri (and first-root (alist-get 'uri first-root)))
         (root (and uri
                    (string-prefix-p "file://" uri)
                    (let ((path (substring uri (length "file://"))))
                      (file-name-as-directory
                       (expand-file-name
                        (decode-coding-string (url-unhex-string path) 'utf-8)))))))
    (let ((session (gethash session-id claude-code-ide-mcp-sse--sessions)))
      (when session
        (puthash session-id (plist-put session :root root) claude-code-ide-mcp-sse--sessions)))
    (when (and claude-code-ide-mcp-sse--last-payload
               claude-code-ide-mcp-sse--last-file
               (claude-code-ide-mcp-sse--session-wants-file-p
                (list :root root) claude-code-ide-mcp-sse--last-file))
      (claude-code-ide-mcp-sse--send
       session-id
       `((jsonrpc . "2.0")
         (method . "selection_changed")
         (params . ,claude-code-ide-mcp-sse--last-payload))))))

(defun claude-code-ide-mcp-sse--dispatch (session-id message)
  "Dispatch a decoded JSON-RPC MESSAGE received for SESSION-ID."
  (let ((method (alist-get 'method message))
        (id (alist-get 'id message)))
    (cond
     ((equal method "initialize")
      (claude-code-ide-mcp-sse--send
       session-id
       `((jsonrpc . "2.0") (id . ,id) (result . ,(claude-code-ide-mcp-sse--initialize-result)))))
     ((equal method "notifications/initialized")
      (claude-code-ide-mcp-sse--send
       session-id
       `((jsonrpc . "2.0")
         (id . ,(format "emacs-roots-%s" session-id))
         (method . "roots/list")
         (params . ,(make-hash-table :test 'equal)))))
     (method
      (if id
          (claude-code-ide-mcp-sse--send
           session-id
           `((jsonrpc . "2.0")
             (id . ,id)
             (error . ((code . -32601) (message . ,(format "Method not found: %s" method))))))
        (claude-code-ide-debug "Ignoring notification with unknown method: %s" method)))
     ((and (stringp id) (string-prefix-p "emacs-roots-" id))
      (claude-code-ide-mcp-sse--apply-roots session-id (alist-get 'result message)))
     (t
      (claude-code-ide-debug "Ignoring unrecognized SSE message: %S" message)))))

;;; Selection tracking

(defun claude-code-ide-mcp-sse--broadcast-selection ()
  "Send the cached selection payload to every session whose root wants it."
  (when (and claude-code-ide-mcp-sse--last-payload claude-code-ide-mcp-sse--last-file)
    (maphash
     (lambda (session-id session)
       (when (claude-code-ide-mcp-sse--session-wants-file-p session claude-code-ide-mcp-sse--last-file)
         (claude-code-ide-mcp-sse--send
          session-id
          `((jsonrpc . "2.0")
            (method . "selection_changed")
            (params . ,claude-code-ide-mcp-sse--last-payload)))))
     claude-code-ide-mcp-sse--sessions)))

(defun claude-code-ide-mcp-sse--flush-selection (buffer)
  "Compute and, if changed, broadcast the current selection state in BUFFER."
  (setq claude-code-ide-mcp-sse--selection-timer nil)
  (when (buffer-live-p buffer)
    (with-current-buffer buffer
      (when (buffer-file-name)
        (let* ((start-end
                (cond
                 ((and (fboundp 'evil-visual-state-p)
                       (evil-visual-state-p)
                       (memq (evil-visual-type) '(line screen-line)))
                  (let ((range (evil-contract-range (evil-visual-range))))
                    (list (nth 0 range) (nth 1 range))))
                 ((use-region-p)
                  (list (region-beginning) (region-end)))
                 (t (list (point) (point)))))
               (state (list (buffer-file-name) (point) (nth 0 start-end) (nth 1 start-end))))
          (unless (equal state claude-code-ide-mcp-sse--last-state)
            (setq claude-code-ide-mcp-sse--last-state state
                  claude-code-ide-mcp-sse--last-file (buffer-file-name)
                  claude-code-ide-mcp-sse--last-payload
                  (claude-code-ide-mcp--get-current-selection-in-buffer nil))
            (claude-code-ide-mcp-sse--broadcast-selection)))))))

(defun claude-code-ide-mcp-sse--track-selection ()
  "`post-command-hook' entry that debounces a selection flush.
Deliberately not gated on there being connected sessions: the cache
must stay current so a client that connects later gets a fresh reply,
and so the user can move point into a non-file buffer (e.g. the omp
terminal) without losing the last real selection."
  (when (buffer-file-name)
    (when claude-code-ide-mcp-sse--selection-timer
      (cancel-timer claude-code-ide-mcp-sse--selection-timer))
    (setq claude-code-ide-mcp-sse--selection-timer
          (run-with-timer claude-code-ide-mcp-selection-delay nil
                           #'claude-code-ide-mcp-sse--flush-selection (current-buffer)))))

;;; Request handlers

(defun claude-code-ide-mcp-sse--handle-get (request)
  "Handle a GET /sse REQUEST, keeping the connection open as an SSE stream."
  (with-slots (process) request
    (let ((session-id (format "%d-%d" (emacs-pid) (cl-incf claude-code-ide-mcp-sse--session-counter))))
      (ws-response-header process 200
                           '("Content-Type" . "text/event-stream")
                           '("Cache-Control" . "no-cache"))
      (puthash session-id (list :process process :root nil) claude-code-ide-mcp-sse--sessions)
      (claude-code-ide-mcp-sse--write
       process
       (claude-code-ide-mcp-sse--frame "endpoint" (format "/messages/%s" session-id)))
      (set-process-sentinel
       process
       (lambda (proc _event)
         (unless (process-live-p proc)
           (remhash session-id claude-code-ide-mcp-sse--sessions)
           (let ((server (plist-get (process-plist proc) :server)))
             (when server
               (setf (ws-requests server)
                     (cl-remove-if (lambda (r) (eq proc (ws-process r))) (ws-requests server))))))))
      (throw 'close-connection :keep-alive))))

(defun claude-code-ide-mcp-sse--handle-post (request)
  "Handle a POST /messages/SESSION-ID REQUEST carrying a JSON-RPC message."
  (with-slots (process) request
    (let* ((headers (ws-headers request))
           (body (ws-body request))
           (url (cdr (assoc :POST headers)))
           (session-id (and url
                            (string-match "^/messages/\\([^/]+\\)" url)
                            (match-string 1 url))))
      (if (or (null session-id) (not (gethash session-id claude-code-ide-mcp-sse--sessions)))
          (ws-send-404 process)
        (condition-case err
            (let ((message (json-parse-string body :object-type 'alist)))
              (claude-code-ide-mcp-sse--dispatch session-id message)
              (ws-response-header process 202 '("Content-Length" . "0")))
          (error
           (claude-code-ide-debug "SSE POST body failed to parse: %s (%S)" body err)
           (ws-response-header process 400 '("Content-Length" . "0"))))))))

;;; Lifecycle

;;;###autoload
(defun claude-code-ide-mcp-sse-ensure-server ()
  "Ensure the SSE server is running and return its port, or nil on failure."
  (interactive)
  (if (and claude-code-ide-mcp-sse--server
           (process-live-p (ws-process claude-code-ide-mcp-sse--server)))
      claude-code-ide-mcp-sse--port
    (condition-case err
        (progn
          (require 'web-server)
          (unless (featurep 'web-server)
            (error "The web-server package is required for omp selection sync. Please install it with: M-x package-install RET web-server RET"))
          (claude-code-ide-mcp-sse--sweep-stale-lockfiles)
          (let* ((server (ws-start
                          `(((:GET . "^/sse$") . ,#'claude-code-ide-mcp-sse--handle-get)
                            ((:POST . "^/messages/") . ,#'claude-code-ide-mcp-sse--handle-post))
                          0
                          nil
                          :host "127.0.0.1"))
                 (port (process-contact (ws-process server) :service)))
            (setq claude-code-ide-mcp-sse--server server
                  claude-code-ide-mcp-sse--port port)
            (claude-code-ide-mcp-sse--write-lockfile port)
            (add-hook 'post-command-hook #'claude-code-ide-mcp-sse--track-selection)
            (claude-code-ide-debug "SSE server started on port %d" port)
            port))
      (error
       (claude-code-ide-debug "Failed to start SSE server: %s" (error-message-string err))
       (message "Warning: Failed to start omp selection-sync SSE server: %s" (error-message-string err))
       nil))))

;;;###autoload
(defun claude-code-ide-mcp-sse-stop ()
  "Stop the SSE server and clean up all of its state."
  (interactive)
  (claude-code-ide-mcp-sse--remove-lockfile)
  (clrhash claude-code-ide-mcp-sse--sessions)
  (when claude-code-ide-mcp-sse--selection-timer
    (cancel-timer claude-code-ide-mcp-sse--selection-timer)
    (setq claude-code-ide-mcp-sse--selection-timer nil))
  (remove-hook 'post-command-hook #'claude-code-ide-mcp-sse--track-selection)
  (when claude-code-ide-mcp-sse--server
    (ws-stop claude-code-ide-mcp-sse--server)
    (setq claude-code-ide-mcp-sse--server nil
          claude-code-ide-mcp-sse--port nil
          claude-code-ide-mcp-sse--last-state nil
          claude-code-ide-mcp-sse--last-payload nil
          claude-code-ide-mcp-sse--last-file nil)))

(add-hook 'kill-emacs-hook #'claude-code-ide-mcp-sse-stop)

(provide 'claude-code-ide-mcp-sse-server)

;;; claude-code-ide-mcp-sse-server.el ends here
