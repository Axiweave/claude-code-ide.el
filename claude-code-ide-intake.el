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
(require 'url-parse)
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

(defcustom claude-code-ide-intake-command nil
  "Program and arguments that start the Intake on this machine, or nil.
Emacs runs them in the home directory, for example
  (\"/path/to/bun\" \"run\" \"/path/to/cci-intake/src/main.ts\").
When nil, Emacs never starts the Intake."
  :type '(choice (const :tag "Off" nil) (repeat string)))

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
    (when (and claude-code-ide-intake-command
               (claude-code-ide-intake--loopback-p claude-code-ide-intake-url))
      (claude-code-ide-intake--start t))
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

;;; The Intake process

(defconst claude-code-ide-intake--buffer "*claude-code-ide-intake*"
  "The output buffer of the Intake that this Emacs started.")

(defvar claude-code-ide-intake--managed nil
  "The Intake process that this Emacs started, or nil.")

(defvar claude-code-ide-intake--stopping nil
  "Non-nil while `claude-code-ide-intake-stop' ends the managed Intake.")

(defvar claude-code-ide-intake--wait-timer nil
  "The timer of the next start-wait step.")

(defun claude-code-ide-intake--loopback-p (url)
  "Return non-nil when the host of URL is this machine."
  (when-let* ((host (url-host (url-generic-parse-url url))))
    (or (member host '("localhost" "[::1]"))
        (string-match-p "\\`127\\.[0-9]+\\.[0-9]+\\.[0-9]+\\'" host))))

(defun claude-code-ide-intake--answers (callback)
  "Call CALLBACK with t when the Intake URL accepts a connection, else nil.
The check does not block and needs no token."
  (let* ((url (url-generic-parse-url claude-code-ide-intake-url))
         (called nil)
         (done (lambda (process answers)
                 (unless called
                   (setq called t)
                   (when process (delete-process process))
                   (funcall callback answers)))))
    (condition-case nil
        (make-network-process
         :name "claude-code-ide-intake-check"
         :host (string-trim (url-host url) "\\[" "\\]")
         :service (url-port url)
         :nowait t
         :noquery t
         :sentinel (lambda (process event)
                     (funcall done process (equal event "open\n"))))
      (error (funcall done nil nil)))))

(defun claude-code-ide-intake--start (quiet)
  "Start the Intake unless the managed Intake runs or an Intake answers.
With QUIET, show no message for those two cases."
  (let ((runs (lambda ()
                (when (process-live-p claude-code-ide-intake--managed)
                  (unless quiet
                    (message "The Intake that Emacs started already runs"))
                  t))))
    (unless (funcall runs)
      (claude-code-ide-intake--answers
       (lambda (answers)
         ;; Check again: another start step can have started it meanwhile.
         (cond
          ((funcall runs))
          (answers
           (unless quiet
             (message "An Intake already answers at %s; Emacs starts no second one"
                      claude-code-ide-intake-url)))
          (t (claude-code-ide-intake--spawn))))))))

(defun claude-code-ide-intake--spawn ()
  "Run `claude-code-ide-intake-command' in the home directory, then wait."
  (let ((buffer (get-buffer-create claude-code-ide-intake--buffer))
        (default-directory (expand-file-name "~/")))
    (with-current-buffer buffer
      (erase-buffer)
      (setq mode-line-process '(":%s")))
    (condition-case err
        (progn
          (setq claude-code-ide-intake--managed
                (make-process :name "cci-intake"
                              :buffer buffer
                              :command claude-code-ide-intake-command
                              :connection-type 'pipe
                              :coding 'utf-8
                              :noquery t
                              :sentinel #'claude-code-ide-intake--sentinel))
          (claude-code-ide-intake--wait claude-code-ide-intake--managed 1))
      (error (message "Intake start failed: %s" (error-message-string err))))))

(defun claude-code-ide-intake--wait (process checks)
  "Check after 0.5 seconds whether the Intake of PROCESS answers.
CHECKS counts the checks, up to 20.  A step for a PROCESS that is no
longer the managed Intake does nothing."
  (setq claude-code-ide-intake--wait-timer
        (run-at-time
         0.5 nil
         (lambda ()
           (when (eq process claude-code-ide-intake--managed)
             (claude-code-ide-intake--answers
              (lambda (answers)
                (when (eq process claude-code-ide-intake--managed)
                  (cond
                   (answers
                    (message "Intake answers at %s" claude-code-ide-intake-url))
                   ((< checks 20)
                    (claude-code-ide-intake--wait process (1+ checks)))
                   (t
                    (message "Intake started but does not answer yet; see %s"
                             claude-code-ide-intake--buffer)))))))))))

(defun claude-code-ide-intake--cancel-wait ()
  "Cancel the next start-wait step."
  (when claude-code-ide-intake--wait-timer
    (cancel-timer claude-code-ide-intake--wait-timer)
    (setq claude-code-ide-intake--wait-timer nil)))

(defun claude-code-ide-intake--error-line (text)
  "Return the last line of TEXT that starts with \"error:\".
Without one, return the last non-blank line, or \"\"."
  (let (error-line last-line)
    (dolist (line (split-string text "\n"))
      (setq line (string-trim line))
      (unless (string-empty-p line)
        (setq last-line line)
        (when (string-prefix-p "error:" line)
          (setq error-line line))))
    (or error-line last-line "")))

(defun claude-code-ide-intake--sentinel (process event)
  "Forget the managed PROCESS when it ends, and report an unasked end.
EVENT is the process event text, which holds the exit code."
  (when (and (not (process-live-p process))
             (eq process claude-code-ide-intake--managed))
    (setq claude-code-ide-intake--managed nil)
    (claude-code-ide-intake--cancel-wait)
    (unless claude-code-ide-intake--stopping
      (message "Intake ended (%s): %s"
               (cond ((string-match "exited abnormally with code \\([0-9]+\\)" event)
                      (concat "exit " (match-string 1 event)))
                     ((string-prefix-p "finished" event) "exit 0")
                     (t (string-trim event)))
               (claude-code-ide-intake--error-line
                (if-let* ((buffer (get-buffer claude-code-ide-intake--buffer)))
                    (with-current-buffer buffer (buffer-string))
                  ""))))))

(defun claude-code-ide-intake--end (process)
  "Send SIGTERM to PROCESS, then SIGKILL after about 5 seconds, and wait.
The wait counts steps, not clock time."
  (setq claude-code-ide-intake--stopping t)
  (unwind-protect
      (let ((steps 0))
        (signal-process process 'SIGTERM)
        (while (and (process-live-p process) (< steps 50))
          (accept-process-output process 0.1)
          (setq steps (1+ steps)))
        (when (process-live-p process)
          (signal-process process 'SIGKILL)
          (while (process-live-p process)
            (accept-process-output process 0.1))))
    (claude-code-ide-intake--cancel-wait)
    (setq claude-code-ide-intake--managed nil
          claude-code-ide-intake--stopping nil)))

;;;###autoload
(defun claude-code-ide-intake-start ()
  "Start the Intake with `claude-code-ide-intake-command'.
Emacs starts nothing when its Intake already runs or when an Intake
answers at `claude-code-ide-intake-url', and starts it only when that
URL names this machine."
  (interactive)
  (unless claude-code-ide-intake-command
    (user-error "Set `claude-code-ide-intake-command' to start the Intake from Emacs"))
  (unless claude-code-ide-intake-url
    (user-error "Set `claude-code-ide-intake-url' to use the Intake"))
  (unless (claude-code-ide-intake--loopback-p claude-code-ide-intake-url)
    (user-error "Emacs starts the Intake only on this machine; %s is not a loopback address"
                claude-code-ide-intake-url))
  (claude-code-ide-intake--start nil))

;;;###autoload
(defun claude-code-ide-intake-stop ()
  "Stop the Intake that this Emacs started.
Emacs never stops an Intake that it did not start."
  (interactive)
  (if (process-live-p claude-code-ide-intake--managed)
      (progn
        (claude-code-ide-intake--end claude-code-ide-intake--managed)
        (message "Intake stopped"))
    (setq claude-code-ide-intake--managed nil)
    (if (not claude-code-ide-intake-url)
        (message "No Intake runs")
      (claude-code-ide-intake--answers
       (lambda (answers)
         (message (if answers
                      "Emacs did not start the running Intake; stop it where it was started"
                    "No Intake runs")))))))

;;;###autoload
(defun claude-code-ide-intake-restart ()
  "Stop the Intake that this Emacs started, then start it again."
  (interactive)
  (when (process-live-p claude-code-ide-intake--managed)
    (claude-code-ide-intake--end claude-code-ide-intake--managed))
  (claude-code-ide-intake-start))

;;;###autoload
(defun claude-code-ide-intake-log ()
  "Show the output of the Intake that this Emacs started."
  (interactive)
  (if-let* ((buffer (get-buffer claude-code-ide-intake--buffer)))
      (display-buffer buffer)
    (message "Emacs has not started the Intake")))

(provide 'claude-code-ide-intake)
;;; claude-code-ide-intake.el ends here
