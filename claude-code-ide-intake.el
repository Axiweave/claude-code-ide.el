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

;;; Code:

(require 'subr-x)
(require 'url-util)

(declare-function claude-code-ide-adopt-session "claude-code-ide" (host name))

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

(defun claude-code-ide-intake--curl (path callback &optional filter)
  "Run curl on PATH under `claude-code-ide-intake-url' and return the process.
FILTER, when non-nil, gets each output chunk as a process filter.
When curl ends, call CALLBACK with the collected output, or with nil
when curl failed.  With FILTER, the collected output is empty."
  (let* ((token (with-temp-buffer
                  (insert-file-contents claude-code-ide-intake-token-file)
                  (string-trim (buffer-string))))
         (chunks nil)
         (process
          (make-process
           :name "claude-code-ide-intake"
           :command '("curl" "-sN" "--fail" "--config" "-")
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
               (funcall callback (and (equal event "finished\n")
                                      (apply #'concat (nreverse chunks)))))))))
    (push process claude-code-ide-intake--processes)
    ;; `%S' quotes and escapes both values as curl config strings.
    (process-send-string
     process (format "header = %S\nurl = %S\n"
                     (concat "Authorization: Bearer " token)
                     (concat (string-remove-suffix "/" claude-code-ide-intake-url) path)))
    (process-send-eof process)
    process))

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
      (claude-code-ide-intake--adopt launch))))

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

(provide 'claude-code-ide-intake)
;;; claude-code-ide-intake.el ends here
