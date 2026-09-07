;;; claude-code-ide-remote-project.el --- Remote project views -*- lexical-binding: t; -*-

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

;; Optional remote Project views for managed zmx Sessions.  This module
;; owns asynchronous preparation and view lifetime.  The manager owns
;; window layout.  The optional RPC client loads only for an admitted
;; preparation attempt.

;;; Code:

(require 'cl-lib)

(defgroup claude-code-ide-remote-project nil
  "Remote Project views for managed Sessions."
  :group 'claude-code-ide)

(defvar tramp-error-show-message-timeout)
(defvar tramp-rpc-deploy-binary-name)
(defvar tramp-rpc-deploy-never-deploy)
(defvar tramp-rpc-deploy-remote-binary-path)
(defvar tramp-rpc-ssh-args)
(defvar claude-code-ide-manager-status-buffer-function)
(defvar magit-display-buffer-function)
(defvar magit-display-buffer-noselect)
(defvar magit-inhibit-save-previous-winconf)
(defvar tramp-temp-buffer-file-name)
(defvar claude-code-ide-remote-project-cleanup-hosts)

(declare-function claude-code-ide-manager--open-status-buffer
                  "claude-code-ide-manager" (directory))
(declare-function claude-code-ide-manager--session-directory
                  "claude-code-ide-manager" (session-or-key))
(declare-function claude-code-ide-manager--remote-project-enabled-p
                  "claude-code-ide-manager"
                  (session-key &optional expected-host))
(declare-function claude-code-ide-manager--display-remote-project-view
                  "claude-code-ide-manager"
                  (session-id attachment frame view-buffer))
(declare-function dired-find-buffer-nocreate "dired" (dirname &optional mode))
(declare-function magit-get-mode-buffer "magit-mode"
                  (mode &optional value frame))


(declare-function tramp-dissect-file-name "tramp" (name))
(declare-function tramp-rpc--connect "tramp-rpc-transport" (vec))
(declare-function tramp-rpc--establish-controlmaster
                  "tramp-rpc-transport" (vec))
(declare-function tramp-rpc--start-server-process
                  "tramp-rpc-transport"
                  (vec binary-path &optional sudo-password))
(declare-function tramp-rpc--connection-key "tramp-rpc-transport" (vec))
(declare-function tramp-rpc--get-connection "tramp-rpc-transport" (vec))
(declare-function tramp-rpc-connection-process "tramp-rpc-connection" (connection))
(declare-function tramp-rpc-connection-stderr-buffer
                  "tramp-rpc-connection" (connection))
(declare-function tramp-rpc-deploy-expected-binary-localname
                  "tramp-rpc-deploy" ())

(cl-defstruct (claude-code-ide-remote-project--intent
               (:constructor claude-code-ide-remote-project--make-intent))
  "Remembered Project-view state for one Session."
  session-id host attachment view-key view-buffer captured-view-name
  suppressed attempt outcome)

(cl-defstruct (claude-code-ide-remote-project--attempt
               (:constructor claude-code-ide-remote-project--make-attempt))
  "One asynchronous Project-view preparation attempt."
  id session-id attachment host admitted-host directory frame reason
  state worker connecting timer route-key view-key candidate
  candidate-origin abandon-reason)

(cl-defstruct (claude-code-ide-remote-project--view
               (:constructor claude-code-ide-remote-project--make-view))
  "One shared Project view."
  key buffer origin creator writer sessions)

(cl-defstruct
    (claude-code-ide-remote-project--cleanup-snapshot
     (:constructor
      claude-code-ide-remote-project--make-cleanup-snapshot))
  "Local ownership evidence captured before explicit detach."
  session-id attachment host intent candidates siblings)

(defvar claude-code-ide-remote-project--intents
  (make-hash-table :test #'equal)
  "Session ID to Project-view intent.")

(defvar claude-code-ide-remote-project--views
  (make-hash-table :test #'equal)
  "View identity to published Project view.")

(defvar claude-code-ide-remote-project--view-writers
  (make-hash-table :test #'equal)
  "View identity to the feature attempt creating it.")

(defvar claude-code-ide-remote-project--incomplete-candidates
  (make-hash-table :test #'eq)
  "Unpublished buffers that cannot qualify for native reuse.")

(defvar-local claude-code-ide-remote-project--candidate-attempt nil
  "Attempt that owns this unpublished candidate buffer.")

(defvar claude-code-ide-remote-project--worker-attempt nil
  "Dynamically bound attempt owned by the current feature worker.")

(defvar claude-code-ide-remote-project--client-advised nil
  "Non-nil after the installed RPC client has feature guards.")

(defvar claude-code-ide-remote-project--candidate-creation-log nil
  "Dynamically bound buffers created through known native view paths.")

(put 'claude-code-ide-remote-project-abandoned
     'error-conditions '(claude-code-ide-remote-project-abandoned))
(put 'claude-code-ide-remote-project-abandoned
     'error-message "Remote Project-view preparation abandoned")

(defun claude-code-ide-remote-project--reset-state ()
  "Clear feature runtime state without remote work."
  (maphash
   (lambda (_session-id intent)
     (when-let* ((attempt
                  (claude-code-ide-remote-project--intent-attempt intent))
                 (timer (claude-code-ide-remote-project--attempt-timer attempt)))
       (cancel-timer timer)))
   claude-code-ide-remote-project--intents)
  (setq claude-code-ide-remote-project--intents
        (make-hash-table :test #'equal)
        claude-code-ide-remote-project--views
        (make-hash-table :test #'equal)
        claude-code-ide-remote-project--view-writers
        (make-hash-table :test #'equal)
        claude-code-ide-remote-project--incomplete-candidates
        (make-hash-table :test #'eq)))

(defun claude-code-ide-remote-project--intent-for
    (session-id host attachment)
  "Return the intent for SESSION-ID, updated for HOST and ATTACHMENT."
  (let ((intent (gethash session-id
                         claude-code-ide-remote-project--intents)))
    (if intent
        (let ((host-changed
               (not
                (equal
                 host
                 (claude-code-ide-remote-project--intent-host
                  intent))))
              (attachment-changed
               (not
                (eq
                 attachment
                 (claude-code-ide-remote-project--intent-attachment
                  intent)))))
          (when
              (and
               (or host-changed attachment-changed)
               (claude-code-ide-remote-project--intent-attempt
                intent))
            (claude-code-ide-remote-project--abandon-attempt
             (claude-code-ide-remote-project--intent-attempt intent)
             (if host-changed
                 'host-changed
               'attachment-replaced)))
          (when host-changed
            (setf
             (claude-code-ide-remote-project--intent-view-key intent)
             nil
             (claude-code-ide-remote-project--intent-view-buffer intent)
             nil
             (claude-code-ide-remote-project--intent-captured-view-name
              intent)
             nil
             (claude-code-ide-remote-project--intent-outcome intent)
             nil))
          (setf
           (claude-code-ide-remote-project--intent-host intent) host
           (claude-code-ide-remote-project--intent-attachment intent)
           attachment))
      (setq intent
            (claude-code-ide-remote-project--make-intent
             :session-id session-id
             :host host
             :attachment attachment))
      (puthash session-id intent
               claude-code-ide-remote-project--intents))
    intent))

(defun claude-code-ide-remote-project--attempt-admission-current-p
    (attempt)
  "Return non-nil when ATTEMPT retains its original host admission."
  (or
   (null
    (claude-code-ide-remote-project--attempt-admitted-host attempt))
   (claude-code-ide-manager--remote-project-enabled-p
    (claude-code-ide-remote-project--attempt-session-id attempt)
    (claude-code-ide-remote-project--attempt-admitted-host attempt))))

(defun claude-code-ide-remote-project--attempt-current-p (attempt)
  "Return non-nil when ATTEMPT retains Session, attachment, and admission."
  (when-let* ((intent
               (and attempt
                    (gethash
                     (claude-code-ide-remote-project--attempt-session-id attempt)
                     claude-code-ide-remote-project--intents))))
    (and
     (eq attempt
         (claude-code-ide-remote-project--intent-attempt intent))
     (eq (claude-code-ide-remote-project--attempt-attachment attempt)
         (claude-code-ide-remote-project--intent-attachment intent))
     (equal (claude-code-ide-remote-project--attempt-host attempt)
            (claude-code-ide-remote-project--intent-host intent))
     (claude-code-ide-remote-project--attempt-admission-current-p
      attempt))))

(defun claude-code-ide-remote-project--invalidate-lost-admission
    (attempt)
  "Invalidate ATTEMPT and return non-nil when its host admission changed."
  (when
      (and
       (claude-code-ide-remote-project--attempt-admitted-host attempt)
       (not
        (claude-code-ide-remote-project--attempt-admission-current-p
         attempt)))
    (claude-code-ide-remote-project--abandon-attempt
     attempt 'host-admission-lost)))

(defun claude-code-ide-remote-project--cancel-timer (attempt)
  "Cancel ATTEMPT's feature deadline timer."
  (when-let* ((timer
               (claude-code-ide-remote-project--attempt-timer attempt)))
    (cancel-timer timer)
    (setf (claude-code-ide-remote-project--attempt-timer attempt) nil)))

(defun claude-code-ide-remote-project--abandon-attempt (attempt reason)
  "Invalidate ATTEMPT for REASON without touching its remote connection."
  (when attempt
    (when-let* ((intent
                 (gethash
                  (claude-code-ide-remote-project--attempt-session-id attempt)
                  claude-code-ide-remote-project--intents)))
      (when (eq attempt
                (claude-code-ide-remote-project--intent-attempt intent))
        (setf (claude-code-ide-remote-project--intent-attempt intent) nil
              (claude-code-ide-remote-project--intent-outcome intent)
              (if (eq reason 'cancel) 'canceled 'failed))))
    (setf (claude-code-ide-remote-project--attempt-state attempt) 'abandoned
          (claude-code-ide-remote-project--attempt-abandon-reason attempt)
          reason)
    (claude-code-ide-remote-project--cancel-timer attempt)
    (claude-code-ide-remote-project--abandon-candidate attempt)
    (claude-code-ide-remote-project--release-view attempt)
    (when-let* ((worker
                 (claude-code-ide-remote-project--attempt-worker attempt)))
      (when (and (thread-live-p worker)
                 (not
                  (claude-code-ide-remote-project--attempt-connecting
                   attempt)))
        (thread-signal
         worker 'claude-code-ide-remote-project-abandoned (list reason))))
    t))

(defun claude-code-ide-remote-project-cancel
    (session-id attachment)
  "Cancel SESSION-ID's current attempt for exact ATTACHMENT."
  (when-let* ((intent
               (gethash
                session-id claude-code-ide-remote-project--intents))
              ((eq
                attachment
                (claude-code-ide-remote-project--intent-attachment
                 intent)))
              (attempt
               (claude-code-ide-remote-project--intent-attempt
                intent)))
    (claude-code-ide-remote-project--abandon-attempt
     attempt 'cancel)))

(defun claude-code-ide-remote-project-invalidate
    (session-id &optional attachment reason)
  "Invalidate SESSION-ID for ATTACHMENT without remote work."
  (when-let* ((intent
               (gethash
                session-id claude-code-ide-remote-project--intents))
              ((or
                (null attachment)
                (eq
                 attachment
                 (claude-code-ide-remote-project--intent-attachment
                  intent)))))
    (when-let* ((attempt
                 (claude-code-ide-remote-project--intent-attempt
                  intent)))
      (claude-code-ide-remote-project--abandon-attempt
       attempt (or reason 'invalidated)))
    (if (eq reason 'session-ended)
        (setf
         (claude-code-ide-remote-project--intent-attachment intent)
         nil)
      (when-let* ((key
                   (claude-code-ide-remote-project--intent-view-key
                    intent))
                  (view
                   (gethash key
                            claude-code-ide-remote-project--views)))
        (setf
         (claude-code-ide-remote-project--view-sessions view)
         (delete
          session-id
          (claude-code-ide-remote-project--view-sessions view))))
      (remhash session-id
               claude-code-ide-remote-project--intents))
    t))

(defun claude-code-ide-remote-project--begin-attempt
    (intent directory frame reason &optional admitted-host)
  "Replace INTENT's attempt for DIRECTORY, FRAME, REASON, and ADMITTED-HOST."
  (when-let* ((old
               (claude-code-ide-remote-project--intent-attempt intent)))
    (claude-code-ide-remote-project--abandon-attempt old 'superseded))
  (let ((attempt
         (claude-code-ide-remote-project--make-attempt
          :id (make-symbol "remote-project-attempt")
          :session-id
          (claude-code-ide-remote-project--intent-session-id intent)
          :attachment
          (claude-code-ide-remote-project--intent-attachment intent)
          :host (claude-code-ide-remote-project--intent-host intent)
          :admitted-host admitted-host
          :directory directory
          :frame frame
          :reason reason
          :state 'checking-client)))
    (setf (claude-code-ide-remote-project--intent-attempt intent) attempt
          (claude-code-ide-remote-project--intent-outcome intent) nil)
    attempt))

(defun claude-code-ide-remote-project--checkpoint (attempt)
  "Signal private abandonment unless ATTEMPT is current."
  (unless (claude-code-ide-remote-project--attempt-current-p attempt)
    (claude-code-ide-remote-project--invalidate-lost-admission attempt)
    (signal 'claude-code-ide-remote-project-abandoned
            (list
             (or
              (claude-code-ide-remote-project--attempt-abandon-reason attempt)
              'stale))))
  attempt)

(defun claude-code-ide-remote-project--claim-view (attempt key)
  "Let current ATTEMPT create missing view KEY."
  (claude-code-ide-remote-project--checkpoint attempt)
  (let ((writer
         (gethash key claude-code-ide-remote-project--view-writers)))
    (when (or (null writer) (eq writer attempt))
      (puthash key attempt
               claude-code-ide-remote-project--view-writers)
      (setf (claude-code-ide-remote-project--attempt-view-key attempt)
            key)
      t)))

(defun claude-code-ide-remote-project--release-view (attempt)
  "Release ATTEMPT's feature creation slot."
  (when-let* ((key
               (claude-code-ide-remote-project--attempt-view-key attempt)))
    (when (eq attempt
              (gethash key
                       claude-code-ide-remote-project--view-writers))
      (remhash key claude-code-ide-remote-project--view-writers))))

(defun claude-code-ide-remote-project--candidate-killed ()
  "Invalidate the attempt that owns the current unpublished candidate."
  (let ((attempt claude-code-ide-remote-project--candidate-attempt))
    (remhash
     (current-buffer)
     claude-code-ide-remote-project--incomplete-candidates)
    (setq claude-code-ide-remote-project--candidate-attempt nil)
    (when
        (and
         attempt
         (eq
          (current-buffer)
          (claude-code-ide-remote-project--attempt-candidate attempt)))
      (setf
       (claude-code-ide-remote-project--attempt-candidate attempt) nil
       (claude-code-ide-remote-project--attempt-candidate-origin attempt)
       nil)
      (claude-code-ide-remote-project--abandon-attempt
       attempt 'candidate-killed))))

(defun claude-code-ide-remote-project--track-candidate
    (attempt buffer origin)
  "Track BUFFER with ORIGIN as ATTEMPT's unpublished candidate."
  (when
      (gethash
       buffer claude-code-ide-remote-project--incomplete-candidates)
    (error
     "The previous incomplete Project-view buffer %s must be resolved"
     (buffer-name buffer)))
  (setf
   (claude-code-ide-remote-project--attempt-candidate attempt) buffer
   (claude-code-ide-remote-project--attempt-candidate-origin attempt)
   origin)
  (puthash
   buffer t claude-code-ide-remote-project--incomplete-candidates)
  (with-current-buffer buffer
    (setq claude-code-ide-remote-project--candidate-attempt attempt)
    (add-hook
     'kill-buffer-hook
     #'claude-code-ide-remote-project--candidate-killed nil t)))

(defun claude-code-ide-remote-project--untrack-candidate (attempt)
  "Stop tracking and return ATTEMPT's candidate and origin."
  (let ((buffer
         (claude-code-ide-remote-project--attempt-candidate attempt))
        (origin
         (claude-code-ide-remote-project--attempt-candidate-origin
          attempt)))
    (setf
     (claude-code-ide-remote-project--attempt-candidate attempt) nil
     (claude-code-ide-remote-project--attempt-candidate-origin attempt)
     nil)
    (when buffer
      (remhash
       buffer claude-code-ide-remote-project--incomplete-candidates)
      (when (buffer-live-p buffer)
        (with-current-buffer buffer
          (remove-hook
           'kill-buffer-hook
           #'claude-code-ide-remote-project--candidate-killed t)
          (kill-local-variable
           'claude-code-ide-remote-project--candidate-attempt))))
    (and buffer (cons buffer origin))))

(defun claude-code-ide-remote-project--abandon-candidate (attempt)
  "Dispose or quarantine ATTEMPT's unpublished candidate."
  (when-let* ((candidate
               (claude-code-ide-remote-project--untrack-candidate attempt))
              (buffer (car candidate))
              ((buffer-live-p buffer)))
    (if
        (eq (cdr candidate) 'created-by-feature)
        (with-current-buffer buffer
          (let ((kill-buffer-query-functions nil))
            (kill-buffer buffer)))
      (puthash
       buffer t claude-code-ide-remote-project--incomplete-candidates)
      (with-current-buffer buffer
        (add-hook
         'kill-buffer-hook
         #'claude-code-ide-remote-project--candidate-killed nil t)))))

(defun claude-code-ide-remote-project--publish-candidate (attempt)
  "Remove unpublished tracking from ATTEMPT's published candidate."
  (claude-code-ide-remote-project--untrack-candidate attempt))

(defun claude-code-ide-remote-project--client-capable-p ()
  "Return non-nil when the installed RPC client has required safety seams."
  (and
   (cl-every #'fboundp
             '(tramp-rpc--connect
               tramp-rpc--establish-controlmaster
               tramp-rpc--start-server-process
               tramp-rpc--connection-key
               tramp-rpc--get-connection
               tramp-rpc-connection-process
               tramp-rpc-connection-stderr-buffer
               tramp-rpc-deploy-expected-binary-localname
               process-thread
               set-process-thread))
   (cl-every #'boundp
             '(tramp-rpc-deploy-never-deploy
               tramp-rpc-deploy-remote-binary-path
               tramp-rpc-deploy-binary-name
               tramp-rpc-ssh-args))))

(defun claude-code-ide-remote-project--owned-call-p (vec)
  "Return non-nil when VEC belongs to the current feature worker."
  (let ((attempt claude-code-ide-remote-project--worker-attempt))
    (and
     attempt
     (or
      (null
       (claude-code-ide-remote-project--attempt-worker attempt))
      (eq
       (claude-code-ide-remote-project--attempt-worker attempt)
       (current-thread)))
     (equal
      (claude-code-ide-remote-project--attempt-route-key attempt)
      (tramp-rpc--connection-key vec)))))

(defun claude-code-ide-remote-project--unlock-process (process)
  "Remove this worker's lock from PROCESS."
  (when (and (processp process)
             (eq (process-thread process) (current-thread)))
    (set-process-thread process nil)))

(defun claude-code-ide-remote-project--unlock-transport (vec)
  "Unlock owned stdout and stderr transport processes for VEC."
  (when-let* ((connection (tramp-rpc--get-connection vec)))
    (claude-code-ide-remote-project--unlock-process
     (tramp-rpc-connection-process connection))
    (when-let* ((stderr-buffer
                 (tramp-rpc-connection-stderr-buffer connection)))
      (claude-code-ide-remote-project--unlock-process
       (get-buffer-process stderr-buffer)))))


(defun claude-code-ide-remote-project--call-connect
    (original vec &rest arguments)
  "Call ORIGINAL connection function for VEC with feature safety guards."
  (if (not (claude-code-ide-remote-project--owned-call-p vec))
      (apply original vec arguments)
    (let* ((attempt claude-code-ide-remote-project--worker-attempt)
           (selected-binary
            (if tramp-rpc-deploy-never-deploy
                (or tramp-rpc-deploy-remote-binary-path
                    tramp-rpc-deploy-binary-name)
              (tramp-rpc-deploy-expected-binary-localname)))
           result failure)
      (claude-code-ide-remote-project--checkpoint attempt)
      (setf
       (claude-code-ide-remote-project--attempt-state attempt)
       'connecting)
      (setf
       (claude-code-ide-remote-project--attempt-connecting attempt) t)
      (unwind-protect
          (condition-case error-data
              (setq result
                    (let
                        ((tramp-rpc-deploy-never-deploy t)
                         (tramp-rpc-deploy-remote-binary-path
                          selected-binary)
                         (tramp-rpc-ssh-args
                          (append
                           '("-o" "BatchMode=yes"
                             "-o" "StrictHostKeyChecking=yes")
                           tramp-rpc-ssh-args))
                         (tramp-error-show-message-timeout nil))
                      (apply original vec arguments)))
            (error
             (setq failure error-data)))
        (setf
         (claude-code-ide-remote-project--attempt-connecting attempt)
         nil))
      (if failure
          (if
              (claude-code-ide-remote-project--attempt-current-p
               attempt)
              (signal (car failure) (cdr failure))
            (signal 'claude-code-ide-remote-project-abandoned
                    '(native-connection-failed-after-abandonment)))
        (claude-code-ide-remote-project--unlock-transport vec)
        (claude-code-ide-remote-project--checkpoint attempt)
        result))))

(defun claude-code-ide-remote-project--call-auth
    (original vec &rest arguments)
  "Call ORIGINAL authentication function for owned VEC."
  (if (not (claude-code-ide-remote-project--owned-call-p vec))
      (apply original vec arguments)
    (claude-code-ide-remote-project--checkpoint
     claude-code-ide-remote-project--worker-attempt)
    (let ((result
           (let ((timer-list nil)
                 (timer-idle-list nil))
             (apply original vec arguments))))
      (claude-code-ide-remote-project--checkpoint
       claude-code-ide-remote-project--worker-attempt)
      result)))

(defun claude-code-ide-remote-project--call-server-start
    (original vec &rest arguments)
  "Call ORIGINAL native server start for owned VEC."
  (if (not (claude-code-ide-remote-project--owned-call-p vec))
      (apply original vec arguments)
    (let ((attempt claude-code-ide-remote-project--worker-attempt)
          result failure)
      (claude-code-ide-remote-project--checkpoint attempt)
      (setf
       (claude-code-ide-remote-project--attempt-state attempt)
       'server)
      (condition-case error-data
          (setq result (apply original vec arguments))
        (error
         (setq failure error-data)))
      (if failure
          (if
              (claude-code-ide-remote-project--attempt-current-p
               attempt)
              (signal (car failure) (cdr failure))
            (signal 'claude-code-ide-remote-project-abandoned
                    '(native-start-failed-after-abandonment)))
        (claude-code-ide-remote-project--unlock-transport vec)
        (claude-code-ide-remote-project--checkpoint attempt)
        result))))

(defun claude-code-ide-remote-project--install-client-guards ()
  "Install scoped guards on the compatible RPC client."
  (unless claude-code-ide-remote-project--client-advised
    (advice-add 'tramp-rpc--connect :around
                #'claude-code-ide-remote-project--call-connect)
    (advice-add 'tramp-rpc--establish-controlmaster :around
                #'claude-code-ide-remote-project--call-auth)
    (advice-add 'tramp-rpc--start-server-process :around
                #'claude-code-ide-remote-project--call-server-start)
    (setq claude-code-ide-remote-project--client-advised t)))

(defun claude-code-ide-remote-project--load-client ()
  "Load and guard the optional RPC client, or return nil."
  (when (and (require 'tramp-rpc nil t)
             (claude-code-ide-remote-project--client-capable-p))
    (claude-code-ide-remote-project--install-client-guards)
    t))

(defun claude-code-ide-remote-project--health-check (attempt)
  "Return non-nil after a current health response for ATTEMPT."
  (claude-code-ide-remote-project--checkpoint attempt)
  (setf (claude-code-ide-remote-project--attempt-state attempt)
        'health)
  (let ((default-directory
         (claude-code-ide-remote-project--attempt-directory attempt))
        (process-file-side-effects nil))
    (prog1 (eq 0 (process-file "true" nil nil nil))
      (claude-code-ide-remote-project--checkpoint attempt))))

(defun claude-code-ide-remote-project--failure-message
    (attempt error-data)
  "Return host-scoped guidance for ATTEMPT and ERROR-DATA."
  (let*
      ((state
        (claude-code-ide-remote-project--attempt-state attempt))
       (phase-and-action
        (pcase state
          ('checking-client
           '("RPC client"
             "Install or update a compatible tramp-rpc client"))
          ((or 'connecting 'authentication)
           '("authentication"
             "Configure noninteractive SSH credentials and the host key"))
          ('server
           '("server"
             "Install the configured server binary on the remote host"))
          ('health
           '("health"
             "Check the server path and remote reachability"))
          ('resolving-view
           '("directory"
             "Check the remote directory and its permissions"))
          ((or 'waiting-for-view 'preparing)
           '("provider"
             "Check Magit or Dired for the remote directory"))
          (_
           '("preparation"
             "Check the remote Project-view configuration")))))
    (format
     "Remote Project view on %s failed during %s: %s. %s, then use R"
     (claude-code-ide-remote-project--attempt-host attempt)
     (car phase-and-action)
     (error-message-string error-data)
     (cadr phase-and-action))))

(defun claude-code-ide-remote-project--health-deadline (attempt)
  "Report and abandon current ATTEMPT at its health deadline."
  (unless
      (claude-code-ide-remote-project--invalidate-lost-admission
       attempt)
    (when (claude-code-ide-remote-project--attempt-current-p attempt)
      (setf
       (claude-code-ide-remote-project--attempt-state attempt)
       'health)
      (claude-code-ide-remote-project--finish-failure
       attempt '(error "No current response within 30 seconds"))
      (claude-code-ide-remote-project--abandon-attempt
       attempt 'health-deadline))))

(defun claude-code-ide-remote-project--start-health-deadline (attempt)
  "Start ATTEMPT's 30-second health deadline."
  (setf
   (claude-code-ide-remote-project--attempt-timer attempt)
   (run-at-time
    30 nil #'claude-code-ide-remote-project--health-deadline attempt)))

(defun claude-code-ide-remote-project--trim-directory (directory)
  "Remove DIRECTORY's trailing slash without invoking a file handler."
  (if (string-suffix-p "/" directory)
      (substring directory 0 -1)
    directory))

(defun claude-code-ide-remote-project--as-directory (directory)
  "Add DIRECTORY's trailing slash without invoking a file handler."
  (if (string-suffix-p "/" directory)
      directory
    (concat directory "/")))

(defun claude-code-ide-remote-project--resolve-view-key (attempt)
  "Return ATTEMPT's exact host and remote Worktree or directory identity."
  (claude-code-ide-remote-project--checkpoint attempt)
  (setf (claude-code-ide-remote-project--attempt-state attempt)
        'resolving-view)
  (let* ((directory
          (claude-code-ide-remote-project--attempt-directory attempt))
         (root (locate-dominating-file directory ".git")))
    (claude-code-ide-remote-project--checkpoint attempt)
    (list
     (claude-code-ide-remote-project--attempt-host attempt)
     (if root 'git 'directory)
     (claude-code-ide-remote-project--trim-directory
      (if root (file-truename root) directory)))))

(defun claude-code-ide-remote-project--rpc-directory (host directory)
  "Return an RPC file name for exact HOST and remote DIRECTORY."
  (claude-code-ide-remote-project--as-directory
   (format "/rpc:%s:%s" host
           (if (string-prefix-p "/" directory)
               directory
             (concat "/" directory)))))

(defun claude-code-ide-remote-project-rpc-directory (host directory)
  "Return an RPC file name for DIRECTORY on HOST.
Callers outside this package must use this name instead of building
the transport encoding themselves."
  (claude-code-ide-remote-project--rpc-directory host directory))


(defun claude-code-ide-remote-project--registered-view (key)
  "Return KEY's live registered view, or remove its dead buffer record."
  (when-let* ((view
               (gethash key claude-code-ide-remote-project--views)))
    (if (buffer-live-p
         (claude-code-ide-remote-project--view-buffer view))
        view
      (remhash key claude-code-ide-remote-project--views)
      nil)))

(defun claude-code-ide-remote-project--dired-view-p
    (buffer directory)
  "Return non-nil when BUFFER is Dired for exact DIRECTORY."
  (and
   (buffer-live-p buffer)
   (with-current-buffer buffer
     (and
      (eq major-mode 'dired-mode)
      (equal
       (claude-code-ide-remote-project--trim-directory
        default-directory)
       (claude-code-ide-remote-project--trim-directory
        directory))))))

(defun claude-code-ide-remote-project--lookup-native-view (key)
  "Return a surviving native buffer for view KEY without refreshing it."
  (let* ((kind (nth 1 key))
         (directory (nth 2 key))
         (magit-buffer
          (when
              (and
               (eq kind 'git)
               (fboundp 'magit-get-mode-buffer))
            (let ((default-directory
                   (claude-code-ide-remote-project--as-directory
                    directory)))
              (ignore-errors
                (magit-get-mode-buffer 'magit-status-mode))))))
    (or
     (and
      (buffer-live-p magit-buffer)
      (not
       (gethash
        magit-buffer
        claude-code-ide-remote-project--incomplete-candidates))
      (with-current-buffer magit-buffer
        (and (eq major-mode 'magit-status-mode) magit-buffer)))
     (when (fboundp 'dired-find-buffer-nocreate)
       (let ((buffer
              (ignore-errors
                (dired-find-buffer-nocreate
                 (claude-code-ide-remote-project--as-directory
                  directory)))))
         (and
          (not
           (gethash
            buffer
            claude-code-ide-remote-project--incomplete-candidates))
          (claude-code-ide-remote-project--dired-view-p
           buffer directory)
          buffer))))))

(defun claude-code-ide-remote-project--find-view (key)
  "Return KEY's registered or native Project view without refreshing."
  (or
   (claude-code-ide-remote-project--registered-view key)
   (when-let* ((buffer
                (claude-code-ide-remote-project--lookup-native-view key)))
     (let ((view
            (claude-code-ide-remote-project--make-view
             :key key :buffer buffer :origin 'preexisting)))
       (puthash key view claude-code-ide-remote-project--views)
       view))))

(defun claude-code-ide-remote-project--view-result (view)
  "Return a worker result for published VIEW."
  (list
   :key (claude-code-ide-remote-project--view-key view)
   :buffer (claude-code-ide-remote-project--view-buffer view)
   :origin (claude-code-ide-remote-project--view-origin view)
   :creator (claude-code-ide-remote-project--view-creator view)))

(defun claude-code-ide-remote-project--record-created-candidate
    (original &rest arguments)
  "Record a buffer allocated during the default provider call."
  (let ((buffer (apply original arguments)))
    (when
        (and
         claude-code-ide-remote-project--candidate-creation-log
         (buffer-live-p buffer))
      (cl-pushnew
       buffer
       claude-code-ide-remote-project--candidate-creation-log))
    buffer))

(defun claude-code-ide-remote-project--install-candidate-observers ()
  "Observe exact buffer allocation during a default provider call."
  (unless
      (advice-member-p
       #'claude-code-ide-remote-project--record-created-candidate
       'generate-new-buffer)
    (advice-add
     'generate-new-buffer :around
     #'claude-code-ide-remote-project--record-created-candidate)))

(defun claude-code-ide-remote-project--candidate-origin (buffer)
  "Return conservative origin and creator data for BUFFER."
  (let ((provider claude-code-ide-manager-status-buffer-function))
    (if
        (and
         (memq
          provider
          '(claude-code-ide-manager-magit-status-buffer
            dired-noselect))
         (memq
          buffer
          claude-code-ide-remote-project--candidate-creation-log)
         (with-current-buffer buffer
           (memq major-mode '(magit-status-mode dired-mode))))
        (list
         'created-by-feature
         (with-current-buffer buffer
           (if (eq major-mode 'magit-status-mode) 'magit 'dired)))
      (list
       (if
           (memq
            provider
            '(claude-code-ide-manager-magit-status-buffer
              dired-noselect))
           'preexisting
         'uncertain-custom)
       nil))))

(defun claude-code-ide-remote-project--prepare-view (attempt key)
  "Return an unpublished Project-view result for ATTEMPT and KEY."
  (claude-code-ide-remote-project--checkpoint attempt)
  (if-let* ((view
             (claude-code-ide-remote-project--find-view key)))
      (claude-code-ide-remote-project--view-result view)
    (if
        (not
         (claude-code-ide-remote-project--claim-view attempt key))
        (progn
          (setf
           (claude-code-ide-remote-project--attempt-state attempt)
           'waiting-for-view)
          (while
              (gethash
               key claude-code-ide-remote-project--view-writers)
            (sleep-for 0.01)
            (claude-code-ide-remote-project--checkpoint attempt))
          (claude-code-ide-remote-project--prepare-view attempt key))
      (unwind-protect
          (if-let* ((view
                     (claude-code-ide-remote-project--find-view key)))
              (claude-code-ide-remote-project--view-result view)
            (setf
             (claude-code-ide-remote-project--attempt-state attempt)
             'preparing)
            (claude-code-ide-remote-project--install-candidate-observers)
            (let* ((magit-display-buffer-function #'ignore)
                   (magit-display-buffer-noselect t)
                   (magit-inhibit-save-previous-winconf 'unset)
                   (warning-minimum-level :emergency)
                   (inhibit-interaction t)
                   (claude-code-ide-remote-project--candidate-creation-log
                    (list 'active))
                   (candidate
                    (claude-code-ide-manager--open-status-buffer
                     (claude-code-ide-remote-project--as-directory
                      (nth 2 key))))
                   (origin
                    (and
                     (buffer-live-p candidate)
                     (claude-code-ide-remote-project--candidate-origin
                      candidate))))
              (unless (buffer-live-p candidate)
                (error "The Project-view provider returned no live buffer"))
              (claude-code-ide-remote-project--track-candidate
               attempt candidate (car origin))
              (claude-code-ide-remote-project--checkpoint attempt)
              (let ((other
                     (claude-code-ide-remote-project--lookup-native-view
                      key)))
                (if (and other (not (eq other candidate)))
                    (progn
                      (claude-code-ide-remote-project--abandon-candidate
                       attempt)
                      (list
                       :key key :buffer other
                       :origin 'preexisting :creator nil))
                  (list
                   :key key :buffer candidate
                   :origin (car origin)
                   :creator (cadr origin))))))
        (claude-code-ide-remote-project--release-view attempt)))))

(defun claude-code-ide-remote-project--finish-success
    (attempt result)
  "Publish ATTEMPT's current RESULT and notify the manager."
  (unless
      (claude-code-ide-remote-project--invalidate-lost-admission
       attempt)
    (when
        (and
         (claude-code-ide-remote-project--attempt-current-p attempt)
         (buffer-live-p (plist-get result :buffer)))
      (let* ((key (plist-get result :key))
             (buffer (plist-get result :buffer))
             (view
              (or
               (claude-code-ide-remote-project--registered-view key)
               (let ((new
                      (claude-code-ide-remote-project--make-view
                       :key key
                       :buffer buffer
                       :origin (plist-get result :origin)
                       :creator (plist-get result :creator))))
                 (puthash key new
                          claude-code-ide-remote-project--views)
                 new)))
             (intent
              (gethash
               (claude-code-ide-remote-project--attempt-session-id
                attempt)
               claude-code-ide-remote-project--intents))
             (published
              (claude-code-ide-remote-project--view-buffer view)))
        (if (eq buffer published)
            (claude-code-ide-remote-project--publish-candidate
             attempt)
          (claude-code-ide-remote-project--abandon-candidate
           attempt))
        (when
            (eq
             (claude-code-ide-remote-project--view-origin view)
             'created-by-feature)
          (with-current-buffer published
            (add-hook
             'kill-buffer-hook
             #'claude-code-ide-remote-project--view-killed nil t)))
        (cl-pushnew
         (claude-code-ide-remote-project--attempt-session-id attempt)
         (claude-code-ide-remote-project--view-sessions view)
         :test #'equal)
        (setf
         (claude-code-ide-remote-project--intent-view-key intent) key
         (claude-code-ide-remote-project--intent-view-buffer intent)
         published
         (claude-code-ide-remote-project--intent-captured-view-name
          intent)
         (buffer-name published)
         (claude-code-ide-remote-project--intent-outcome intent) 'ready
         (claude-code-ide-remote-project--intent-attempt intent) nil
         (claude-code-ide-remote-project--attempt-state attempt) 'ready)
        (claude-code-ide-manager--display-remote-project-view
         (claude-code-ide-remote-project--attempt-session-id attempt)
         (claude-code-ide-remote-project--attempt-attachment attempt)
         (claude-code-ide-remote-project--attempt-frame attempt)
         published)))))

(defun claude-code-ide-remote-project--finish-failure
    (attempt error-data)
  "Record and report ERROR-DATA when ATTEMPT still owns its Session."
  (unless
      (claude-code-ide-remote-project--invalidate-lost-admission
       attempt)
    (when
        (claude-code-ide-remote-project--attempt-current-p attempt)
      (let ((failure-message
             (claude-code-ide-remote-project--failure-message
              attempt error-data)))
        (claude-code-ide-remote-project--cancel-timer attempt)
        (claude-code-ide-remote-project--abandon-candidate attempt)
        (when-let* ((intent
                     (gethash
                      (claude-code-ide-remote-project--attempt-session-id
                       attempt)
                      claude-code-ide-remote-project--intents)))
          (setf
           (claude-code-ide-remote-project--intent-outcome intent)
           'failed
           (claude-code-ide-remote-project--intent-attempt intent) nil
           (claude-code-ide-remote-project--attempt-state attempt)
           'failed))
        (message "%s" failure-message)))))

(defun claude-code-ide-remote-project--worker (attempt)
  "Run remote preparation for ATTEMPT."
  (setf
   (claude-code-ide-remote-project--attempt-worker attempt)
   (current-thread))
  (let ((claude-code-ide-remote-project--worker-attempt attempt)
        (tramp-error-show-message-timeout nil)
        (inhibit-interaction t))
    (condition-case error-data
        (progn
          (unless
              (claude-code-ide-remote-project--load-client)
            (error "The installed RPC client is missing or unsupported"))
          (let ((vec
                 (tramp-dissect-file-name
                  (claude-code-ide-remote-project--attempt-directory
                   attempt))))
            (setf
             (claude-code-ide-remote-project--attempt-route-key
              attempt)
             (tramp-rpc--connection-key vec))
            (unless
                (claude-code-ide-remote-project--health-check attempt)
              (error "The current RPC health request failed"))
            (claude-code-ide-remote-project--cancel-timer attempt)
            (let* ((key
                    (claude-code-ide-remote-project--resolve-view-key
                     attempt))
                   (result
                    (claude-code-ide-remote-project--prepare-view
                     attempt key)))
              (claude-code-ide-remote-project--checkpoint attempt)
              (run-at-time
               0 nil
               #'claude-code-ide-remote-project--finish-success
               attempt result))))
      (claude-code-ide-remote-project-abandoned nil)
      (error
       (run-at-time
        0 nil
        #'claude-code-ide-remote-project--finish-failure
        attempt error-data)))))

(defun claude-code-ide-remote-project-prepare
    (session-id host attachment frame reason)
  "Prepare SESSION-ID's remote Project view without blocking its terminal.
HOST is the exact admitted destination.  ATTACHMENT and FRAME establish
display ownership.  REASON identifies first display, reattach, or reset."
  (when
      (claude-code-ide-manager--remote-project-enabled-p
       session-id host)
    (let ((intent
           (claude-code-ide-remote-project--intent-for
            session-id host attachment)))
      (when (or
             (not
              (claude-code-ide-remote-project--intent-suppressed intent))
             (eq reason 'reset))
        (when (eq reason 'reset)
          (setf
           (claude-code-ide-remote-project--intent-suppressed intent)
           nil))
        (let* ((attempt
                (claude-code-ide-remote-project--begin-attempt
                 intent
                 (claude-code-ide-remote-project--rpc-directory
                  host
                  (claude-code-ide-manager--session-directory
                   session-id))
                 frame reason host))
               ;; The NS event loop can hold the Lisp lock while idle.
               ;; Yield on the main thread until this worker exits.
               (yield-timer
                (when (featurep 'ns)
                  (run-at-time 0 0.05 #'thread-yield)))
               worker)
          (unwind-protect
              (progn
                (claude-code-ide-remote-project--start-health-deadline
                 attempt)
                (setq worker
                      (make-thread
                       (lambda ()
                         (unwind-protect
                             (claude-code-ide-remote-project--worker attempt)
                           (when yield-timer
                             (cancel-timer yield-timer))))
                       (format "remote-project-%s" session-id)))
                (setf
                 (claude-code-ide-remote-project--attempt-worker attempt)
                 worker)
                attempt)
            (unless worker
              (claude-code-ide-remote-project--abandon-attempt
               attempt 'worker-unavailable)
              (when yield-timer
                (cancel-timer yield-timer)))))))))

(defun claude-code-ide-remote-project-record-display
    (session-id attachment view-buffer)
  "Record that SESSION-ID displayed VIEW-BUFFER for ATTACHMENT."
  (when-let* ((intent
               (gethash session-id
                        claude-code-ide-remote-project--intents)))
    (when
        (and
         (eq attachment
             (claude-code-ide-remote-project--intent-attachment intent))
         (buffer-live-p view-buffer))
      (setf
       (claude-code-ide-remote-project--intent-view-buffer intent)
       view-buffer
       (claude-code-ide-remote-project--intent-captured-view-name
        intent)
       (buffer-name view-buffer))
      t)))

(defun claude-code-ide-remote-project-surviving-view
    (session-id attachment)
  "Return SESSION-ID's exact surviving view for ATTACHMENT."
  (when-let* ((intent
               (gethash session-id
                        claude-code-ide-remote-project--intents))
              ((eq attachment
                   (claude-code-ide-remote-project--intent-attachment
                    intent)))
              (buffer
               (claude-code-ide-remote-project--intent-view-buffer
                intent)))
    (if (buffer-live-p buffer)
        buffer
      (when-let* ((key
                   (claude-code-ide-remote-project--intent-view-key
                    intent))
                  (view
                   (gethash
                    key claude-code-ide-remote-project--views))
                  ((eq
                    buffer
                    (claude-code-ide-remote-project--view-buffer
                     view))))
        (remhash key claude-code-ide-remote-project--views))
      (setf
       (claude-code-ide-remote-project--intent-view-buffer intent)
       nil)
      nil)))

(defun claude-code-ide-remote-project-display-allowed-p
    (session-id attachment)
  "Return non-nil when SESSION-ID may display a view for ATTACHMENT."
  (when-let* ((intent
               (gethash session-id
                        claude-code-ide-remote-project--intents)))
    (and
     (eq attachment
         (claude-code-ide-remote-project--intent-attachment intent))
     (not
      (claude-code-ide-remote-project--intent-suppressed intent)))))

(defun claude-code-ide-remote-project-suppress
    (session-id attachment)
  "Suppress automatic display for SESSION-ID's exact ATTACHMENT."
  (when-let* ((intent
               (gethash session-id
                        claude-code-ide-remote-project--intents)))
    (when
        (eq attachment
            (claude-code-ide-remote-project--intent-attachment intent))
      (setf
       (claude-code-ide-remote-project--intent-suppressed intent) t)
      t)))

(defun claude-code-ide-remote-project-needs-replacement-p
    (session-id attachment)
  "Return non-nil when SESSION-ID needs its missing requested view."
  (when-let* ((intent
               (gethash session-id
                        claude-code-ide-remote-project--intents)))
    (and
     (eq attachment
         (claude-code-ide-remote-project--intent-attachment intent))
     (not
      (claude-code-ide-remote-project--intent-suppressed intent))
     (claude-code-ide-remote-project--intent-view-key intent)
     (not
      (buffer-live-p
       (claude-code-ide-remote-project--intent-view-buffer intent)))
     (null
      (claude-code-ide-remote-project--intent-attempt intent)))))

(defun claude-code-ide-remote-project--view-killed ()
  "Remove the current dead Project view from local feature records."
  (let ((buffer (current-buffer))
        dead-keys)
    (maphash
     (lambda (key view)
       (when
           (eq
            buffer
            (claude-code-ide-remote-project--view-buffer view))
         (push key dead-keys)))
     claude-code-ide-remote-project--views)
    (dolist (key dead-keys)
      (remhash key claude-code-ide-remote-project--views))
    (maphash
     (lambda (_session-id intent)
       (when
           (eq
            buffer
            (claude-code-ide-remote-project--intent-view-buffer
             intent))
         (setf
          (claude-code-ide-remote-project--intent-view-buffer intent)
          nil)))
     claude-code-ide-remote-project--intents)))

(defun claude-code-ide-remote-project-cleanup-snapshot
    (session-id attachment host siblings)
  "Capture local cleanup evidence for SESSION-ID before explicit detach."
  (let* ((intent
          (gethash
           session-id claude-code-ide-remote-project--intents))
         (key
          (and
           intent
           (or
            (eq
             attachment
             (claude-code-ide-remote-project--intent-attachment
              intent))
            (and
             (null attachment)
             (null
              (claude-code-ide-remote-project--intent-attachment
               intent))))
           (claude-code-ide-remote-project--intent-view-key intent)))
         (view
          (and key
               (gethash key
                        claude-code-ide-remote-project--views)))
         (buffer
          (and view
               (claude-code-ide-remote-project--view-buffer view))))
    (claude-code-ide-remote-project--make-cleanup-snapshot
     :session-id session-id
     :attachment attachment
     :host host
     :intent intent
     :candidates
     (and
      (buffer-live-p buffer)
      (eq
       buffer
       (claude-code-ide-remote-project--intent-view-buffer intent))
      (with-current-buffer buffer
        (null buffer-file-name))
      (list view))
     :siblings siblings)))

(defun claude-code-ide-remote-project--unknown-local-hook-p
    (buffer hook allowed)
  "Return non-nil when BUFFER has an unknown local HOOK entry."
  (when (local-variable-p hook buffer)
    (let ((value (buffer-local-value hook buffer)))
      (cl-some
       (lambda (entry)
         (not
          (or
           (eq entry t)
           (memq entry allowed))))
       (if (listp value) value (list value))))))

(defun claude-code-ide-remote-project--local-view-path
    (host path)
  "Return PATH without its exact RPC HOST prefix."
  (let ((prefix (format "/rpc:%s:" host)))
    (claude-code-ide-remote-project--trim-directory
     (if (string-prefix-p prefix path)
         (substring path (length prefix))
       path))))

(defun claude-code-ide-remote-project--sharing-reason
    (snapshot view)
  "Return a sharing retention reason for VIEW in SNAPSHOT."
  (let* ((session-id
          (claude-code-ide-remote-project--cleanup-snapshot-session-id
           snapshot))
         (host
          (claude-code-ide-remote-project--cleanup-snapshot-host
           snapshot))
         (key
          (claude-code-ide-remote-project--view-key view))
         (path
          (claude-code-ide-remote-project--local-view-path
           host (nth 2 key)))
         reason)
    (dolist
        (sibling
         (claude-code-ide-remote-project--cleanup-snapshot-siblings
          snapshot))
      (when
          (and
           (not
            (equal session-id
                   (plist-get sibling :session-id)))
           (plist-get sibling :live-p)
           (equal host (plist-get sibling :host)))
        (let* ((sibling-intent
                (gethash
                 (plist-get sibling :session-id)
                 claude-code-ide-remote-project--intents))
               (sibling-key
                (and
                 sibling-intent
                 (claude-code-ide-remote-project--intent-view-key
                  sibling-intent)))
               (worktree
                (plist-get sibling :worktree-path)))
          (cond
           ((equal key sibling-key)
            (setq reason 'shared))
           (sibling-key nil)
           ((null worktree)
            (unless reason
              (setq reason 'unknown-sharing)))
           ((equal
             path
             (claude-code-ide-remote-project--trim-directory
              worktree))
            (setq reason 'shared))))))
    reason))

(defun claude-code-ide-remote-project--cleanup-token-current-p
    (snapshot)
  "Return non-nil when SNAPSHOT still refers to its detached attachment."
  (let* ((intent
          (claude-code-ide-remote-project--cleanup-snapshot-intent
           snapshot))
         (attachment
          (claude-code-ide-remote-project--cleanup-snapshot-attachment
           snapshot))
         (current
          (and
           intent
           (claude-code-ide-remote-project--intent-attachment
            intent))))
    (and
     (eq
      intent
      (gethash
       (claude-code-ide-remote-project--cleanup-snapshot-session-id
        snapshot)
       claude-code-ide-remote-project--intents))
     (or
      (eq attachment current)
      (and
       (null current)
       (or
        (null attachment)
        (not (buffer-live-p attachment))))))))

(defun claude-code-ide-remote-project--cleanup-retention-reason
    (snapshot view)
  "Return why SNAPSHOT must retain VIEW, or nil when it may kill it."
  (let ((buffer
         (claude-code-ide-remote-project--view-buffer view)))
    (cond
     ((not
       (claude-code-ide-remote-project--cleanup-token-current-p
        snapshot))
      'newer-attachment)
     ((not (buffer-live-p buffer)) 'dead)
     ((not
       (eq
        view
        (gethash
         (claude-code-ide-remote-project--view-key view)
         claude-code-ide-remote-project--views)))
      'replaced)
     ((not
       (eq
        (claude-code-ide-remote-project--view-origin view)
        'created-by-feature))
      'reused)
     ((not
       (memq
        (claude-code-ide-remote-project--view-creator view)
        '(magit dired)))
      'custom)
     ((with-current-buffer buffer
        (not
         (eq
          major-mode
          (if
              (eq
               (claude-code-ide-remote-project--view-creator view)
               'magit)
              'magit-status-mode
            'dired-mode))))
      'mode-changed)
     ((buffer-modified-p buffer) 'modified)
     ((buffer-local-value 'buffer-file-name buffer) 'source-file)
     ((get-buffer-process buffer) 'process)
     ((and
       (local-variable-p
        'tramp-temp-buffer-file-name buffer)
       (buffer-local-value
        'tramp-temp-buffer-file-name buffer))
      'temporary)
     ((claude-code-ide-remote-project--unknown-local-hook-p
       buffer 'kill-buffer-hook
       '(claude-code-ide-remote-project--view-killed))
      'kill-hook)
     ((claude-code-ide-remote-project--unknown-local-hook-p
       buffer 'kill-buffer-query-functions nil)
      'query-hook)
     ((claude-code-ide-remote-project--sharing-reason
       snapshot view))
     (nil))))

(defun claude-code-ide-remote-project-cleanup (snapshot)
  "Apply SNAPSHOT's conservative local-only explicit-detach cleanup."
  (when
      (member
       (claude-code-ide-remote-project--cleanup-snapshot-host snapshot)
       claude-code-ide-remote-project-cleanup-hosts)
    (let (killed retained)
      (dolist
          (view
           (claude-code-ide-remote-project--cleanup-snapshot-candidates
            snapshot))
        (let* ((buffer
                (claude-code-ide-remote-project--view-buffer view))
               (reason
                (claude-code-ide-remote-project--cleanup-retention-reason
                 snapshot view)))
          (if reason
              (push (cons buffer reason) retained)
            (let ((kill-buffer-query-functions nil))
              (if (kill-buffer buffer)
                  (push buffer killed)
                (push (cons buffer 'kill-veto) retained))))))
      (dolist (entry retained)
        (message
         "Remote Project cleanup retained %s (%s)"
         (buffer-name (car entry))
         (cdr entry)))
      (list
       :killed (nreverse killed)
       :retained (nreverse retained)))))
(provide 'claude-code-ide-remote-project)
;;; claude-code-ide-remote-project.el ends here
