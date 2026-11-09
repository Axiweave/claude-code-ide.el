;;; claude-code-ide-intake.el --- Pull Launches from a Session Intake -*- lexical-binding: t; -*-

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

;; Optional pull path for Sessions that a Session Intake launched.
;; `claude-code-ide-intake-mode' opens the Intake event stream, then
;; reads the running Launches once, and calls
;; `claude-code-ide-adopt-session' for each running Launch that names
;; a host for this Emacs.  Both requests run the outside program
;; `curl', which reads the bearer token on stdin, so no process
;; argument holds the token.  A lost stream reconnects after 1, 2, 4
;; ... up to 60 seconds, and each reconnect reads the list again.
;;
;; `claude-code-ide-master' starts or shows the Master Session through
;; the Intake.  `claude-code-ide-intake-confirm' answers a Launch that
;; the Intake holds until the user confirms it.

;;; Code:

(require 'subr-x)
(require 'url-util)

(declare-function claude-code-ide-adopt-session "claude-code-ide" (host name))
(declare-function claude-code-ide--live-session-for-target "claude-code-ide" (host zmx-name))
(declare-function claude-code-ide-session-id "claude-code-ide" (session))
(declare-function claude-code-ide-manager-switch-to-session "claude-code-ide-manager"
                  (session-key &optional keep-manager-focus scope))

(defvar claude-code-ide--master-open-pending)
(defvar claude-code-ide--pending-adoptions)
(defvar claude-code-ide--adopted-sessions)

(defgroup claude-code-ide-intake nil
  "Pull Sessions that a Session Intake launched."
  :group 'claude-code-ide
  :prefix "claude-code-ide-intake-")

(defcustom claude-code-ide-intake-url nil
  "Base URL of the Session Intake, for example \"http://127.0.0.1:7311\".
When nil, pull is off and Emacs never contacts the Intake."
  :type '(choice (const :tag "Off" nil) string))

(defcustom claude-code-ide-intake-token-file "~/.config/cci-intake/token"
  "File that holds the Intake bearer token.  Emacs reads it at each connect."
  :type 'file)

(defcustom claude-code-ide-intake-client (system-name)
  "The `[[emacs]]' name that the Intake knows this Emacs by."
  :type 'string)

(defvar claude-code-ide-intake-mode)

(defvar claude-code-ide-intake--processes nil
  "The live curl processes of `claude-code-ide-intake-mode'.")

(defvar claude-code-ide-intake--timer nil
  "The timer that reconnects the event stream.")

(defvar claude-code-ide-intake--retry-delay 1
  "Seconds before the next reconnect of the event stream.")

(defvar claude-code-ide-intake--partial ""
  "Stream text after the last complete event.")

(defun claude-code-ide-intake--config-string (text)
  "Return TEXT as a quoted value for a curl configuration line."
  (concat "\""
          (replace-regexp-in-string
           "[\"\\\n\r\t]"
           (lambda (char)
             (pcase char
               ("\n" "\\n")
               ("\r" "\\r")
               ("\t" "\\t")
               (_ (concat "\\" char))))
           text t t)
          "\""))

(defun claude-code-ide-intake--curl (path callback &optional filter method body)
  "Run curl on PATH under `claude-code-ide-intake-url' and return the process.
FILTER, when non-nil, gets each output chunk as a process filter.
Without METHOD, call CALLBACK when curl ends with the collected output,
or with nil when curl failed.  With FILTER, the collected output is
empty.
With METHOD, such as \"GET\" or \"POST\", send BODY, when non-nil, as
JSON, and call CALLBACK with (STATUS TEXT), the HTTP status number and
the answer text, or with nil when curl cannot connect.
The token, the method, and the body go to curl on stdin, never in a
process argument."
  (let* ((token (with-temp-buffer
                  (insert-file-contents claude-code-ide-intake-token-file)
                  (string-trim (buffer-string))))
         (chunks nil)
         (process
          (make-process
           :name "claude-code-ide-intake"
           :command (if method
                        '("curl" "-s" "--config" "-")
                      '("curl" "-sN" "--fail" "--config" "-"))
           :connection-type 'pipe
           :coding 'utf-8
           :noquery t
           :filter (or filter (lambda (_process chunk) (push chunk chunks)))
           :sentinel
           (lambda (process event)
             (unless (process-live-p process)
               (setq claude-code-ide-intake--processes
                     (delq process claude-code-ide-intake--processes))
               ;; With --fail, curl exits 22 on an HTTP error status: a bad
               ;; token or a client name with no `[[emacs]]' entry.
               (when (string-match-p "exited abnormally with code 22" event)
                 (message "Intake refused %s: check `claude-code-ide-intake-client' and `claude-code-ide-intake-token-file'"
                          path))
               (let ((output (and (equal event "finished\n")
                                  (apply #'concat (nreverse chunks)))))
                 (funcall callback
                          (if (and method output)
                              (claude-code-ide-intake--status-reply output)
                            output))))))))
    (push process claude-code-ide-intake--processes)
    (process-send-string
     process
     (mapconcat
      (lambda (line)
        (format "%s = %s\n" (car line) (claude-code-ide-intake--config-string (cdr line))))
      `(("header" . ,(concat "Authorization: Bearer " token))
        ("url" . ,(concat (string-remove-suffix "/" claude-code-ide-intake-url) path))
        ,@(when method
            `(("request" . ,method)
              ("write-out" . "\n%{http_code}")))
        ,@(when body
            `(("header" . "Content-Type: application/json")
              ("data-binary" . ,body))))
      ""))
    (process-send-eof process)
    process))

(defun claude-code-ide-intake--status-reply (output)
  "Return (STATUS TEXT) from OUTPUT, an answer text that ends with its status.
Return nil when OUTPUT has no status line."
  (when (string-match "\n\\([0-9]+\\)\\'" output)
    (list (string-to-number (match-string 1 output))
          (substring output 0 (match-beginning 0)))))

(defun claude-code-ide-intake--adopt (launch)
  "Adopt LAUNCH, a parsed Launch alist, when it is running and names a host."
  (when-let* (((equal (alist-get 'state launch) "running"))
              (host (assq 'emacs_host launch)))
    (claude-code-ide-adopt-session (unless (eq (cdr host) :null) (cdr host))
                                   (alist-get 'name launch))))

(defun claude-code-ide-intake--parse (text)
  "Return TEXT parsed as a JSON object alist, or nil when it is not JSON."
  (condition-case nil
      (json-parse-string text :object-type 'alist)
    (json-error nil)))

(defun claude-code-ide-intake--event (block)
  "Handle BLOCK, the text of one stream event without its blank line."
  (let (event data)
    (dolist (line (split-string block "\n"))
      (cond ((string-prefix-p "event:" line)
             (setq event (string-trim (substring line 6))))
            ((string-prefix-p "data:" line)
             (setq data (concat data (string-trim-left (substring line 5)))))))
    (when-let* (((equal event "launch"))
                (data)
                (launch (claude-code-ide-intake--parse data)))
      (if (equal (alist-get 'state launch) "held")
          (message "Launch %s for %s waits: M-x claude-code-ide-intake-confirm"
                   (alist-get 'id launch) (claude-code-ide-intake--place launch))
        (claude-code-ide-intake--adopt launch)))))

(defun claude-code-ide-intake--place (launch)
  "Return \"PROJECT@HOST\" for LAUNCH."
  (format "%s@%s" (alist-get 'project launch) (alist-get 'host launch)))

(defun claude-code-ide-intake--filter (_process chunk)
  "Add CHUNK to the stream text and handle each complete event."
  (setq claude-code-ide-intake--partial (concat claude-code-ide-intake--partial chunk))
  (while (string-match "\n\n" claude-code-ide-intake--partial)
    (let ((block (substring claude-code-ide-intake--partial 0 (match-beginning 0))))
      (setq claude-code-ide-intake--partial
            (substring claude-code-ide-intake--partial (match-end 0))
            claude-code-ide-intake--retry-delay 1)
      (claude-code-ide-intake--event block))))

(defun claude-code-ide-intake--catch-up (output)
  "Adopt each running Launch in OUTPUT, a `GET /v1/launches' body."
  (when-let* ((claude-code-ide-intake-mode)
              (output)
              (body (claude-code-ide-intake--parse output)))
    (mapc #'claude-code-ide-intake--adopt (alist-get 'launches body))))

(defun claude-code-ide-intake--stream-ended (_output)
  "Reconnect after the current delay, then double the delay up to 60."
  (when claude-code-ide-intake-mode
    (setq claude-code-ide-intake--timer
          (run-at-time claude-code-ide-intake--retry-delay nil
                       #'claude-code-ide-intake--connect)
          claude-code-ide-intake--retry-delay
          (min 60 (* 2 claude-code-ide-intake--retry-delay)))))

(defun claude-code-ide-intake--connect ()
  "Open the event stream, then read the running Launches once."
  (setq claude-code-ide-intake--timer nil
        claude-code-ide-intake--partial "")
  (let ((client (url-hexify-string claude-code-ide-intake-client)))
    (condition-case err
        (progn
          (claude-code-ide-intake--curl (concat "/v1/events?client=" client)
                                        #'claude-code-ide-intake--stream-ended
                                        #'claude-code-ide-intake--filter)
          (claude-code-ide-intake--curl
           (concat "/v1/launches?state=running&client=" client)
           #'claude-code-ide-intake--catch-up))
      (error
       (message "Intake connect failed: %s" (error-message-string err))
       (claude-code-ide-intake--stream-ended nil)))))

(defun claude-code-ide-intake--stop ()
  "Delete the curl processes and cancel the reconnect timer."
  (when claude-code-ide-intake--timer
    (cancel-timer claude-code-ide-intake--timer)
    (setq claude-code-ide-intake--timer nil))
  (dolist (process claude-code-ide-intake--processes)
    (set-process-sentinel process #'ignore)
    (delete-process process))
  (setq claude-code-ide-intake--processes nil))

;;;###autoload
(define-minor-mode claude-code-ide-intake-mode
  "Adopt the Sessions that a Session Intake launches for this Emacs.
The mode follows the Intake at `claude-code-ide-intake-url' with
`curl' and calls `claude-code-ide-adopt-session' for each running
Launch."
  :global t
  :group 'claude-code-ide-intake
  (claude-code-ide-intake--stop)
  (when claude-code-ide-intake-mode
    (unless (and claude-code-ide-intake-url (executable-find "curl"))
      (setq claude-code-ide-intake-mode nil)
      (user-error (if claude-code-ide-intake-url
                      "Intake pull needs `curl'"
                    "Set `claude-code-ide-intake-url' to turn on Intake pull")))
    (require 'claude-code-ide)
    (setq claude-code-ide-intake--retry-delay 1)
    (claude-code-ide-intake--connect)))

(defun claude-code-ide-intake--check ()
  "Signal a `user-error' unless the URL, curl, and the token file are ready."
  (unless claude-code-ide-intake-url
    (user-error "Set `claude-code-ide-intake-url' to use the Intake"))
  (unless (executable-find "curl")
    (user-error "The Intake commands need `curl'"))
  (unless (file-readable-p claude-code-ide-intake-token-file)
    (user-error "Cannot read %s: check `claude-code-ide-intake-token-file'"
                claude-code-ide-intake-token-file)))

(defun claude-code-ide-intake--answer (reply)
  "Return the parsed body of REPLY, a (STATUS TEXT) list, for a 2xx STATUS.
For nil, the result of a failed connection, or for another STATUS, show
one message and return nil."
  (pcase reply
    ('nil
     (message "Intake at %s is not reachable" claude-code-ide-intake-url)
     nil)
    (`(,status ,text)
     (let ((body (claude-code-ide-intake--parse text)))
       (if (and (<= 200 status 299) (consp body))
           body
         (let ((error-text (and (consp body) (alist-get 'error body))))
           (message "Intake at %s answered HTTP %d%s" claude-code-ide-intake-url status
                    (if (stringp error-text) (concat ": " error-text) "")))
         nil)))))

(defun claude-code-ide-intake--client-query ()
  "Return the `client' query for `claude-code-ide-intake-client'."
  (concat "client=" (url-hexify-string claude-code-ide-intake-client)))

;;;###autoload
(defun claude-code-ide-master ()
  "Start the Master Session through the Intake, or show it when it runs.
The Intake configuration names the master directory, prompt, and
command.  Emacs asks the Intake once, then checks the Launch every
second for up to 45 seconds, and shows the Session when it runs."
  (interactive)
  (claude-code-ide-intake--check)
  (require 'claude-code-ide)
  (claude-code-ide-intake--curl
   (concat "/v1/master?" (claude-code-ide-intake--client-query))
   (lambda (reply) (claude-code-ide-intake--master-reply reply 0))
   nil "POST"))

(defun claude-code-ide-intake--master-reply (reply polls)
  "Handle REPLY, the answer about the master Launch after POLLS checks.
Show a running master.  Check a queued or starting master again after
one second, up to 45 checks."
  (when-let* ((launch (claude-code-ide-intake--answer reply)))
    (let ((state (alist-get 'state launch))
          (reason (alist-get 'reason launch)))
      (cond
       ((equal state "running")
        (claude-code-ide-intake--master-show launch))
       ((and (member state '("queued" "starting")) (< polls 45))
        (run-at-time
         1 nil
         (lambda ()
           (claude-code-ide-intake--curl
            (format "/v1/launches/%s?%s" (url-hexify-string (alist-get 'id launch))
                    (claude-code-ide-intake--client-query))
            (lambda (reply) (claude-code-ide-intake--master-reply reply (1+ polls)))
            nil "GET"))))
       (t
        (setq claude-code-ide--master-open-pending nil)
        (message "Master Session state: %s%s%s" state
                 (if (member state '("queued" "starting")) " after 45 seconds" "")
                 (if (stringp reason) (concat ": " reason) "")))))))

(defun claude-code-ide-intake--master-show (launch)
  "Show the running master LAUNCH, and attach it first when needed."
  (if-let* ((host (assq 'emacs_host launch)))
      (let* ((pair (cons (unless (eq (cdr host) :null) (cdr host))
                         (alist-get 'name launch)))
             (live (claude-code-ide--live-session-for-target (car pair) (cdr pair))))
        ;; The switch rule shows the Session when its attach ends.
        (setq claude-code-ide--master-open-pending pair)
        (cond
         (live
          (setq claude-code-ide--master-open-pending nil)
          (claude-code-ide-manager-switch-to-session (claude-code-ide-session-id live)))
         ;; The push or the pull of the Intake attaches it now.
         ((member pair claude-code-ide--pending-adoptions))
         (t
          ;; Attach again a master that the user disconnected.
          (setq claude-code-ide--adopted-sessions
                (delete pair claude-code-ide--adopted-sessions))
          (unless (eq (claude-code-ide-intake--adopt launch) 'adopting)
            (setq claude-code-ide--master-open-pending nil)))))
    (message "No `[[emacs]]' target in the Intake config maps host %s of the Master Session"
             (alist-get 'host launch))))

;;;###autoload
(defun claude-code-ide-intake-confirm ()
  "Confirm or decline a Launch that waits for the user.
The Intake holds a Launch of the Master Session when its `[master]'
table sets `confirm'.  Choose a held Launch, read its prompt, and
answer yes to start it or no to refuse it."
  (interactive)
  (claude-code-ide-intake--check)
  (claude-code-ide-intake--curl "/v1/launches?state=held"
                                #'claude-code-ide-intake--confirm-list nil "GET"))

(defun claude-code-ide-intake--confirm-list (reply)
  "Ask about one held Launch from REPLY, the answer to the held list."
  (when-let* ((body (claude-code-ide-intake--answer reply)))
    (let* ((choices (mapcar (lambda (launch)
                              (cons (format "%s %s" (alist-get 'id launch)
                                            (claude-code-ide-intake--place launch))
                                    launch))
                            (alist-get 'launches body)))
           (launch (if (cdr choices)
                       (cdr (assoc (completing-read "Held Launch: " choices nil t)
                                   choices))
                     (cdar choices))))
      (if (not launch)
          (message "No Launch waits for confirmation")
        (let ((id (alist-get 'id launch)))
          (claude-code-ide-intake--curl
           (format "/v1/launches/%s/%s" (url-hexify-string id)
                   (if (yes-or-no-p
                        (format "Start Launch %s for %s with this prompt?\n%s\n"
                                id (claude-code-ide-intake--place launch)
                                (alist-get 'prompt launch)))
                       "confirm"
                     "decline"))
           (lambda (reply)
             (when-let* ((answer (claude-code-ide-intake--answer reply)))
               (message "Launch %s is %s" id (alist-get 'state answer))))
           nil "POST"))))))

(provide 'claude-code-ide-intake)
;;; claude-code-ide-intake.el ends here
