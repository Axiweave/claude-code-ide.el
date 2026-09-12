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
;;
;; `claude-code-ide-remote-project-open-target' prepares the same kind
;; of view for an explicit host and directory with no Session.  It
;; shares every guard above and never fabricates a Session or enables
;; automatic display.

;;; Code:

(require 'cl-lib)
(require 'warnings)
(require 'claude-code-ide-zmx)

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
(declare-function claude-code-ide-manager--remote-project-enabled-p
                  "claude-code-ide-manager"
                  (session-key &optional expected-host))
(declare-function claude-code-ide-manager--display-remote-project-view
                  "claude-code-ide-manager"
                  (session-id attachment frame view-buffer &optional request))
(declare-function claude-code-ide-manager--remote-layout-request-current-p
                  "claude-code-ide-manager"
                  (session-id attachment frame request))
(declare-function claude-code-ide-manager--owned-companion-shell
                  "claude-code-ide-manager" (session-id))
(declare-function claude-code-ide-session--create-companion-shell
                  "claude-code-ide-session" (directory name))
(declare-function dired-find-buffer-nocreate "dired" (dirname &optional mode))
(declare-function magit-get-mode-buffer "magit-mode"
                  (mode &optional value frame))
(declare-function magit-refresh-buffer "magit-mode"
                  (&optional created &key initial-section select-section))


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
  suppressed attempt outcome layout-request)

(cl-defstruct (claude-code-ide-remote-project--attempt
               (:constructor claude-code-ide-remote-project--make-attempt))
  "One asynchronous Project-view preparation attempt.
CALLBACK is non-nil only for an explicit no-Session target attempt
from `claude-code-ide-remote-project-open-target'.  REQUESTED-DIRECTORY
then holds its exact requested directory for the callback result.
EXPLICIT-PROVIDER holds that same attempt's captured Git provider,
used only to build its shared view key."
  id session-id attachment host admitted-host directory frame reason
  state worker connecting timer route-key view-key candidate
  candidate-origin abandon-reason callback requested-directory on-close
  layout-request explicit-provider)

(cl-defstruct (claude-code-ide-remote-project--view
               (:constructor claude-code-ide-remote-project--make-view))
  "One shared Project view."
  key buffer origin creator writer sessions close-callbacks)

(cl-defstruct
    (claude-code-ide-remote-project--cleanup-snapshot
     (:constructor
      claude-code-ide-remote-project--make-cleanup-snapshot))
  "Local ownership evidence captured before explicit detach."
  session-id attachment host intent candidates siblings)

(defun claude-code-ide-remote-project--view-key-equal (a b)
  "Return non-nil when view keys A and B identify the same view.
Two distinct interpreted or compiled closures can be `equal' without
being `eq'.  Compare each key's provider function by identity so two
such closures never collapse into the same registered view."
  (and (equal (nth 0 a) (nth 0 b))
       (equal (nth 1 a) (nth 1 b))
       (equal (nth 2 a) (nth 2 b))
       (let ((descriptor-a (nth 3 a))
             (descriptor-b (nth 3 b)))
         (and (equal (car descriptor-a) (car descriptor-b))
              (eq (cadr descriptor-a) (cadr descriptor-b))
              (equal (nth 2 descriptor-a) (nth 2 descriptor-b))))))

(defun claude-code-ide-remote-project--view-key-hash (key)
  "Hash KEY consistently with `claude-code-ide-remote-project--view-key-equal'.
Combine each field's own hash with `logxor' so combining never
allocates a throwaway list just to compute one shared hash."
  (let ((descriptor (nth 3 key)))
    (logxor
     (sxhash-equal (nth 0 key))
     (sxhash-equal (nth 1 key))
     (sxhash-equal (nth 2 key))
     (sxhash-equal (car descriptor))
     (sxhash-eq (cadr descriptor))
     (sxhash-equal (nth 2 descriptor)))))

(define-hash-table-test 'claude-code-ide-remote-project--view-key-test
                        #'claude-code-ide-remote-project--view-key-equal
                        #'claude-code-ide-remote-project--view-key-hash)

(defvar claude-code-ide-remote-project--intents
  (make-hash-table :test #'equal)
  "Session ID to Project-view intent.")

(defvar claude-code-ide-remote-project--views
  (make-hash-table :test 'claude-code-ide-remote-project--view-key-test)
  "View identity to published Project view.")

(defvar claude-code-ide-remote-project--view-writers
  (make-hash-table :test 'claude-code-ide-remote-project--view-key-test)
  "View identity to the feature attempt creating it.")

(defvar claude-code-ide-remote-project--incomplete-candidates
  (make-hash-table :test #'eq)
  "Unpublished buffers that cannot qualify for native reuse.")

(defvar-local claude-code-ide-remote-project--candidate-attempt nil
  "Attempt that owns this unpublished candidate buffer.")

(defvar-local claude-code-ide-remote-project--unavailable-header nil
  "Original and unavailable header formats for an invalidated Project view.")

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
        (make-hash-table :test 'claude-code-ide-remote-project--view-key-test)
        claude-code-ide-remote-project--view-writers
        (make-hash-table :test 'claude-code-ide-remote-project--view-key-test)
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

(defun claude-code-ide-remote-project--attempt-admission-current-p (attempt)
  "Return non-nil when ATTEMPT retains its original host admission."
  (let ((host (claude-code-ide-remote-project--attempt-admitted-host attempt)))
    (if (claude-code-ide-remote-project--attempt-callback attempt)
        (and (equal host (claude-code-ide-remote-project--attempt-host attempt))
             (member host claude-code-ide-remote-hosts))
      (or (null host)
          (claude-code-ide-manager--remote-project-enabled-p
           (claude-code-ide-remote-project--attempt-session-id attempt) host)))))

(defun claude-code-ide-remote-project--attempt-current-p (attempt)
  "Return non-nil when ATTEMPT retains its owner and host admission."
  (and
   attempt
   (not (eq (claude-code-ide-remote-project--attempt-state attempt) 'abandoned))
   (claude-code-ide-remote-project--attempt-admission-current-p attempt)
   (if (claude-code-ide-remote-project--attempt-callback attempt)
       (not (memq (claude-code-ide-remote-project--attempt-state attempt)
                  '(abandoned ready failed)))
     (when-let* ((intent
                  (gethash
                   (claude-code-ide-remote-project--attempt-session-id attempt)
                   claude-code-ide-remote-project--intents)))
       (and
        (eq attempt (claude-code-ide-remote-project--intent-attempt intent))
        (eq (claude-code-ide-remote-project--attempt-attachment attempt)
            (claude-code-ide-remote-project--intent-attachment intent))
        (equal (claude-code-ide-remote-project--attempt-host attempt)
               (claude-code-ide-remote-project--intent-host intent)))))))

(defun claude-code-ide-remote-project--invalidate-lost-admission (attempt)
  "Invalidate ATTEMPT and return non-nil when its host admission changed."
  (when (and (not (memq (claude-code-ide-remote-project--attempt-state attempt)
                        '(abandoned ready failed)))
             (claude-code-ide-remote-project--attempt-admitted-host attempt)
             (not (claude-code-ide-remote-project--attempt-admission-current-p attempt)))
    (when-let* ((callback (claude-code-ide-remote-project--attempt-callback attempt)))
      (run-at-time
       0 nil
       (lambda ()
         (when (and (eq callback
                        (claude-code-ide-remote-project--attempt-callback attempt))
                    (eq 'host-admission-lost
                        (claude-code-ide-remote-project--attempt-abandon-reason attempt)))
           (setf (claude-code-ide-remote-project--attempt-callback attempt) nil)
           (funcall callback
                    (list :status 'failed :error "Host approval was removed"
                          :host (claude-code-ide-remote-project--attempt-host attempt)
                          :directory
                          (claude-code-ide-remote-project--attempt-requested-directory
                           attempt)))))))
    (claude-code-ide-remote-project--abandon-attempt attempt 'host-admission-lost)))

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
    (setf (claude-code-ide-remote-project--attempt-on-close attempt) nil)
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
      (when-let* ((on-close (claude-code-ide-remote-project--attempt-on-close attempt)))
        (setf (claude-code-ide-remote-project--attempt-on-close attempt) nil)
        (run-at-time 0 nil on-close))
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
             "Check the requested companion and its remote directory"))
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

(defun claude-code-ide-remote-project--attempt-provider-descriptor (attempt)
  "Return ATTEMPT's provider descriptor for a shared view key.
Use its captured LAYOUT-REQUEST when Session-managed, or the Git-only
provider captured at `claude-code-ide-remote-project-open-target' entry."
  (if-let* ((request (claude-code-ide-remote-project--attempt-layout-request attempt)))
      (list (plist-get request :companion-kind)
            (plist-get request :provider)
            (plist-get request :directory))
    (list 'git
          (claude-code-ide-remote-project--attempt-explicit-provider attempt)
          (claude-code-ide-remote-project--attempt-directory attempt))))

(defun claude-code-ide-remote-project--resolve-view-key (attempt)
  "Return ATTEMPT's exact host, Worktree identity, and provider descriptor."
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
      (if root (file-truename root) directory))
     (claude-code-ide-remote-project--attempt-provider-descriptor attempt))))

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

(defun claude-code-ide-remote-project--key-directory (key)
  "Return the exact directory KEY's registered buffer should show.
Only the default Magit provider normalizes to the repository root,
KEY's canonical location.  Every other provider, including a Dired
buffer or a custom Git provider, shows KEY's exact requested
directory."
  (let ((descriptor (nth 3 key)))
    (if (and (eq (car descriptor) 'git)
             (eq (cadr descriptor)
                 'claude-code-ide-manager-magit-status-buffer))
        (nth 2 key)
      (claude-code-ide-remote-project--trim-directory (nth 2 descriptor)))))


(defun claude-code-ide-remote-project--registered-view (key)
  "Return KEY's reusable view.
Keep unavailable owners, but discard records for dead buffers."
  (when-let* ((view
               (gethash key claude-code-ide-remote-project--views)))
    (let ((buffer (claude-code-ide-remote-project--view-buffer view)))
      (if (buffer-live-p buffer)
          (unless (buffer-local-value
                   'claude-code-ide-remote-project--unavailable-header buffer)
            view)
        (remhash key claude-code-ide-remote-project--views)
        nil))))

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

(defun claude-code-ide-remote-project--lookup-native-view (key &optional include-unavailable)
  "Return KEY's native buffer without refresh.
INCLUDE-UNAVAILABLE permits inspection before fresh provider preparation.
Only KEY's exact companion kind, provider, and requested directory
qualify a native buffer.  A Dired request never reuses a Magit buffer,
a Git request never reuses a Dired buffer, and a custom Git provider
never reuses an unrelated Magit buffer."
  (let* ((descriptor (nth 3 key))
         (companion-kind (car descriptor))
         (provider (nth 1 descriptor))
         (requested-directory
          (claude-code-ide-remote-project--as-directory (nth 2 descriptor)))
         (magit-buffer
          (when
              (and
               (eq companion-kind 'git)
               (eq provider 'claude-code-ide-manager-magit-status-buffer)
               (fboundp 'magit-get-mode-buffer))
            (let ((default-directory requested-directory))
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
        (and (eq major-mode 'magit-status-mode)
             (or include-unavailable
                 (not claude-code-ide-remote-project--unavailable-header))
             magit-buffer)))
     (when (and (eq companion-kind 'dired) (fboundp 'dired-find-buffer-nocreate))
       (let ((buffer
              (ignore-errors
                (dired-find-buffer-nocreate requested-directory))))
         (and
          buffer
          (not
           (gethash
            buffer
            claude-code-ide-remote-project--incomplete-candidates))
          (claude-code-ide-remote-project--dired-view-p
           buffer requested-directory)
          (or include-unavailable
              (not (buffer-local-value
                    'claude-code-ide-remote-project--unavailable-header buffer)))
          buffer))))))

(defun claude-code-ide-remote-project--find-view (key &optional check-unavailable)
  "Return KEY's reusable Project view without refreshing.
CHECK-UNAVAILABLE rejects unsafe native reuse before provider preparation."
  (or
   (claude-code-ide-remote-project--registered-view key)
   (when-let* ((buffer
                (claude-code-ide-remote-project--lookup-native-view key check-unavailable)))
     (let* ((registered (gethash key claude-code-ide-remote-project--views))
            (view (if (and registered
                           (eq buffer (claude-code-ide-remote-project--view-buffer registered)))
                      registered
                    (claude-code-ide-remote-project--make-view
                     :key key :buffer buffer :origin 'preexisting))))
       (if (buffer-local-value 'claude-code-ide-remote-project--unavailable-header buffer)
           (unless (and (equal (claude-code-ide-remote-project--trim-directory
                                (buffer-local-value 'default-directory buffer))
                               (claude-code-ide-remote-project--key-directory key))
                        (claude-code-ide-remote-project--view-refreshable-p view))
             (error "The unavailable Project view has edits, shared ownership, or uncertain state"))
         (puthash key view claude-code-ide-remote-project--views)
         view)))))

(defun claude-code-ide-remote-project--view-refreshable-p (view)
  "Return non-nil when VIEW's current ownership and buffer state permit refresh."
  (with-current-buffer (claude-code-ide-remote-project--view-buffer view)
    (and (memq major-mode '(magit-status-mode dired-mode))
         (pcase (claude-code-ide-remote-project--view-origin view)
           ('preexisting t)
           ('created-by-feature
            (eq major-mode
                (pcase (claude-code-ide-remote-project--view-creator view)
                  ('magit 'magit-status-mode)
                  ('dired 'dired-mode)))))
         (not (cdr (claude-code-ide-remote-project--reconcile-live-sessions
                    (claude-code-ide-remote-project--view-key view) view)))
         (not (buffer-modified-p))
         (not buffer-file-name)
         (not (get-buffer-process (current-buffer)))
         (not (and (local-variable-p 'tramp-temp-buffer-file-name)
                   tramp-temp-buffer-file-name))
         (not (claude-code-ide-remote-project--unknown-local-hook-p
               (current-buffer) 'kill-buffer-hook '(claude-code-ide-remote-project--view-killed)))
         (not (claude-code-ide-remote-project--unknown-local-hook-p
               (current-buffer) 'kill-buffer-query-functions nil)))))

(defun claude-code-ide-remote-project--view-result (view &optional attempt)
  "Return VIEW's worker result, honoring ATTEMPT's explicit recovery."
  (when (and attempt
             (eq (claude-code-ide-remote-project--attempt-reason attempt)
                 'worktree-recovery))
    (with-current-buffer (claude-code-ide-remote-project--view-buffer view)
      (when (and (memq major-mode '(magit-status-mode dired-mode))
                 (not (equal (claude-code-ide-remote-project--trim-directory default-directory)
                             (claude-code-ide-remote-project--key-directory
                              (claude-code-ide-remote-project--view-key view)))))
        (error "The Project view no longer matches the requested directory"))
      (when (claude-code-ide-remote-project--view-refreshable-p view)
        (let ((inhibit-interaction t))
          (if (eq major-mode 'magit-status-mode)
              (magit-refresh-buffer)
            (revert-buffer nil t))))))
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

(defun claude-code-ide-remote-project--candidate-origin (buffer provider)
  "Return conservative origin and creator data for BUFFER and PROVIDER."
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
     nil)))

(defun claude-code-ide-remote-project--prepare-view (attempt key)
  "Return an unpublished Project-view result for ATTEMPT and KEY."
  (claude-code-ide-remote-project--checkpoint attempt)
  (if-let* ((view
             (claude-code-ide-remote-project--find-view key t)))
      (claude-code-ide-remote-project--view-result view attempt)
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
                     (claude-code-ide-remote-project--find-view key t)))
              (claude-code-ide-remote-project--view-result view attempt)
            (setf
             (claude-code-ide-remote-project--attempt-state attempt)
             'preparing)
            (claude-code-ide-remote-project--install-candidate-observers)
            (let* ((descriptor (nth 3 key))
                   (companion-kind (car descriptor))
                   (provider (nth 1 descriptor))
                   (magit-display-buffer-function #'ignore)
                   (magit-display-buffer-noselect t)
                   (magit-inhibit-save-previous-winconf 'unset)
                   (warning-minimum-level :emergency)
                   (inhibit-interaction t)
                   (claude-code-ide-remote-project--candidate-creation-log
                    (list 'active))
                   (candidate
                    (let ((target-directory
                           (claude-code-ide-remote-project--as-directory
                            (nth 2 descriptor))))
                      (if (eq companion-kind 'dired)
                          (dired-noselect target-directory)
                        (let ((claude-code-ide-manager-status-buffer-function
                               provider))
                          (claude-code-ide-manager--open-status-buffer
                           target-directory)))))
                   (origin
                    (and
                     (buffer-live-p candidate)
                     (claude-code-ide-remote-project--candidate-origin
                      candidate provider))))
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
  "Publish ATTEMPT's current RESULT and notify its owner."
  (let ((admission-lost
         (claude-code-ide-remote-project--invalidate-lost-admission attempt))
        (shell-p (eq (plist-get result :companion-kind) 'shell))
        (buffer (plist-get result :buffer)))
    (if (and (not admission-lost)
             (claude-code-ide-remote-project--attempt-current-p attempt)
             (buffer-live-p buffer))
        (if shell-p
            (claude-code-ide-remote-project--finish-shell-success attempt buffer)
          (if (or (claude-code-ide-remote-project--attempt-callback attempt)
                  (claude-code-ide-manager--remote-layout-request-current-p
                   (claude-code-ide-remote-project--attempt-session-id attempt)
                   (claude-code-ide-remote-project--attempt-attachment attempt)
                   (claude-code-ide-remote-project--attempt-frame attempt)
                   (claude-code-ide-remote-project--attempt-layout-request attempt)))
              (claude-code-ide-remote-project--finish-view-success attempt result)
            (claude-code-ide-remote-project--abandon-attempt
             attempt 'layout-request-stale)))
      (when (and shell-p (buffer-live-p buffer))
        (message "Layout changed. The ordinary shell remains in %s"
                 (buffer-name buffer))))))

(defun claude-code-ide-remote-project--finish-shell-success (attempt buffer)
  "Publish ATTEMPT's freshly owned companion shell BUFFER.
Report and retain BUFFER unpublished when its layout request no longer
owns the Session's display."
  (setf (claude-code-ide-remote-project--attempt-state attempt) 'ready)
  (when-let* ((intent
               (gethash
                (claude-code-ide-remote-project--attempt-session-id attempt)
                claude-code-ide-remote-project--intents)))
    (setf (claude-code-ide-remote-project--intent-attempt intent) nil
          (claude-code-ide-remote-project--intent-outcome intent) 'ready))
  (let ((session-id (claude-code-ide-remote-project--attempt-session-id attempt))
        (attachment (claude-code-ide-remote-project--attempt-attachment attempt))
        (frame (claude-code-ide-remote-project--attempt-frame attempt))
        (request (claude-code-ide-remote-project--attempt-layout-request attempt)))
    (if (claude-code-ide-manager--remote-layout-request-current-p
         session-id attachment frame request)
        (claude-code-ide-manager--display-remote-project-view
         session-id attachment frame buffer request)
      (message "Layout changed. The ordinary shell remains in %s"
               (buffer-name buffer)))))

(defun claude-code-ide-remote-project--finish-view-success
    (attempt result)
  "Publish ATTEMPT's current Git/Dired view RESULT and notify its owner."
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
         (published
          (claude-code-ide-remote-project--view-buffer view))
         (callback
          (claude-code-ide-remote-project--attempt-callback attempt))
         (on-close
          (claude-code-ide-remote-project--attempt-on-close attempt)))
    (with-current-buffer published
      (when claude-code-ide-remote-project--unavailable-header
        (when (eq header-line-format
                  (cdr claude-code-ide-remote-project--unavailable-header))
          (setq header-line-format
                (car claude-code-ide-remote-project--unavailable-header)))
        (setq claude-code-ide-remote-project--unavailable-header nil)))
    (if (eq buffer published)
        (claude-code-ide-remote-project--publish-candidate
         attempt)
      (claude-code-ide-remote-project--abandon-candidate
       attempt))
    (when on-close
      (push on-close (claude-code-ide-remote-project--view-close-callbacks view))
      (setf (claude-code-ide-remote-project--attempt-on-close attempt) nil))
    (when (or on-close
              (eq (claude-code-ide-remote-project--view-origin view)
                  'created-by-feature))
      (with-current-buffer published
        (add-hook
         'kill-buffer-hook
         #'claude-code-ide-remote-project--view-killed nil t)))
    (setf
     (claude-code-ide-remote-project--attempt-state attempt) 'ready)
    (if callback
        (funcall
         callback
         (list
          :status 'completed
          :buffer published
          :host (claude-code-ide-remote-project--attempt-host
                 attempt)
          :directory
          (claude-code-ide-remote-project--attempt-requested-directory
           attempt)))
      (cl-pushnew
       (claude-code-ide-remote-project--attempt-session-id attempt)
       (claude-code-ide-remote-project--view-sessions view)
       :test #'equal)
      (let ((intent
             (gethash
              (claude-code-ide-remote-project--attempt-session-id
               attempt)
              claude-code-ide-remote-project--intents)))
        (setf
         (claude-code-ide-remote-project--intent-view-key intent)
         key
         (claude-code-ide-remote-project--intent-view-buffer intent)
         published
         (claude-code-ide-remote-project--intent-captured-view-name
          intent)
         (buffer-name published)
         (claude-code-ide-remote-project--intent-outcome intent)
         'ready
         (claude-code-ide-remote-project--intent-attempt intent)
         nil))
      (claude-code-ide-manager--display-remote-project-view
       (claude-code-ide-remote-project--attempt-session-id attempt)
       (claude-code-ide-remote-project--attempt-attachment attempt)
       (claude-code-ide-remote-project--attempt-frame attempt)
       published
       (claude-code-ide-remote-project--attempt-layout-request attempt)))))

(defun claude-code-ide-remote-project--finish-failure
    (attempt error-data)
  "Record and report ERROR-DATA when ATTEMPT still owns its Session or target."
  (unless
      (claude-code-ide-remote-project--invalidate-lost-admission
       attempt)
    (when
        (claude-code-ide-remote-project--attempt-current-p attempt)
      (let* ((callback
              (claude-code-ide-remote-project--attempt-callback attempt))
             (failure-message
              (if callback
                  (error-message-string error-data)
                (claude-code-ide-remote-project--failure-message
                 attempt error-data))))
        (claude-code-ide-remote-project--cancel-timer attempt)
        (claude-code-ide-remote-project--abandon-candidate attempt)
        (setf
         (claude-code-ide-remote-project--attempt-state attempt) 'failed)
        (if callback
            (funcall
             callback
             (list
              :status 'failed
              :error failure-message
              :host (claude-code-ide-remote-project--attempt-host
                     attempt)
              :directory
              (claude-code-ide-remote-project--attempt-requested-directory
               attempt)))
          (when-let* ((intent
                       (gethash
                        (claude-code-ide-remote-project--attempt-session-id
                         attempt)
                        claude-code-ide-remote-project--intents)))
            (setf
             (claude-code-ide-remote-project--intent-outcome intent)
             'failed
             (claude-code-ide-remote-project--intent-attempt intent)
             nil))
          (message "%s" failure-message))))))

(defun claude-code-ide-remote-project--prepare-shell (attempt)
  "Return ATTEMPT's freshly created companion shell result.
Refuse before creating a shell for ATTEMPT whose layout request no
longer owns its Session's display."
  (claude-code-ide-remote-project--checkpoint attempt)
  (unless (claude-code-ide-manager--remote-layout-request-current-p
           (claude-code-ide-remote-project--attempt-session-id attempt)
           (claude-code-ide-remote-project--attempt-attachment attempt)
           (claude-code-ide-remote-project--attempt-frame attempt)
           (claude-code-ide-remote-project--attempt-layout-request attempt))
    (signal 'claude-code-ide-remote-project-abandoned '(layout-request-stale)))
  (setf (claude-code-ide-remote-project--attempt-state attempt) 'preparing)
  (let ((buffer
         (claude-code-ide-session--create-companion-shell
          (claude-code-ide-remote-project--attempt-directory attempt)
          (format "*cc-shell:%s*"
                  (claude-code-ide-remote-project--attempt-session-id attempt)))))
    (list :companion-kind 'shell :buffer buffer)))

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
            (let* ((shell-p
                    (eq (plist-get
                         (claude-code-ide-remote-project--attempt-layout-request
                          attempt)
                         :companion-kind)
                        'shell))
                   (result
                    (if shell-p
                        (claude-code-ide-remote-project--prepare-shell attempt)
                      (claude-code-ide-remote-project--prepare-view
                       attempt
                       (claude-code-ide-remote-project--resolve-view-key
                        attempt)))))
              (unless shell-p
                (claude-code-ide-remote-project--checkpoint attempt))
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

(defun claude-code-ide-remote-project--spawn-worker (attempt label)
  "Start ATTEMPT's worker thread named LABEL.
Return ATTEMPT, or abandon it when the thread cannot start."
  (let (;; The NS event loop can hold the Lisp lock while idle.
        ;; Yield on the main thread until this worker exits.
        (yield-timer
         (when (featurep 'ns)
           (run-at-time 0 0.05 #'thread-yield)))
        worker)
    (unwind-protect
        (progn
          (claude-code-ide-remote-project--start-health-deadline attempt)
          (setq worker
                (make-thread
                 (lambda ()
                   (unwind-protect
                       (claude-code-ide-remote-project--worker attempt)
                     (when yield-timer
                       (cancel-timer yield-timer))))
                 label))
          (setf (claude-code-ide-remote-project--attempt-worker attempt)
                worker)
          attempt)
      (unless worker
        (claude-code-ide-remote-project--abandon-attempt
         attempt 'worker-unavailable)
        (when yield-timer
          (cancel-timer yield-timer))))))

(defun claude-code-ide-remote-project-resume-layout-request
    (session-id attachment frame preset)
  "Rebind SESSION-ID's pending PRESET to ATTACHMENT's restored FRAME.
Keep the admitted request's provider and creation permission.  Return
a fresh snapshot only for the same current attempt and Session directory."
  (when-let* ((intent (gethash session-id claude-code-ide-remote-project--intents))
              (attempt (claude-code-ide-remote-project--intent-attempt intent))
              (request (claude-code-ide-remote-project--attempt-layout-request attempt))
              ((frame-live-p frame))
              ((eq frame (claude-code-ide-remote-project--attempt-frame attempt)))
              ((eq attachment (claude-code-ide-remote-project--attempt-attachment attempt)))
              ((eq attachment (claude-code-ide-manager--session-buffer session-id)))
              ((eq request (claude-code-ide-remote-project--intent-layout-request intent)))
              ((eq preset (plist-get request :preset)))
              ((claude-code-ide-remote-project--attempt-current-p attempt))
              ((claude-code-ide-remote-project-display-allowed-p session-id attachment))
              ((equal (plist-get request :directory)
                      (claude-code-ide-remote-project-rpc-directory
                       (claude-code-ide-remote-project--attempt-host attempt)
                       (claude-code-ide-manager--session-directory session-id)))))
    (let ((restored (plist-put
                     (copy-sequence request) :epoch
                     (or (frame-parameter frame 'claude-code-ide-manager-remote-project-epoch) 0))))
      (setf (claude-code-ide-remote-project--attempt-layout-request attempt) restored
            (claude-code-ide-remote-project--intent-layout-request intent) restored)
      restored)))

(defun claude-code-ide-remote-project-prepare
    (session-id host attachment frame reason layout-request)
  "Prepare SESSION-ID's companion using its captured LAYOUT-REQUEST.
HOST is the exact admitted destination.  ATTACHMENT and FRAME establish
display ownership.  REASON identifies first display, reattach, or reset.

A shell request that already owns a live buffer publishes it directly,
without a worker or a new RPC connection.  A shell request with no
live owned buffer and no creation permission does nothing."
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
        (let* ((shell-p (eq (plist-get layout-request :companion-kind) 'shell))
               (owned-shell
                (and shell-p
                     (claude-code-ide-manager--owned-companion-shell session-id))))
          (unless (and shell-p (not owned-shell)
                       (not (plist-get layout-request :allow-create)))
            (let ((attempt
                   (claude-code-ide-remote-project--begin-attempt
                    intent (plist-get layout-request :directory)
                    frame reason host)))
              (setf (claude-code-ide-remote-project--attempt-layout-request attempt)
                    layout-request
                    (claude-code-ide-remote-project--intent-layout-request intent)
                    layout-request)
              (if owned-shell
                  (claude-code-ide-remote-project--finish-success
                   attempt (list :companion-kind 'shell :buffer owned-shell))
                (claude-code-ide-remote-project--spawn-worker
                 attempt (format "remote-project-%s" session-id))))))))))

(defconst claude-code-ide-remote-project--minimum-emacs-version "30.1"
  "Earliest Emacs version the optional RPC client supports.")

(defun claude-code-ide-remote-project-target-available-p ()
  "Return non-nil when this Emacs can prepare an explicit remote target.
Check the Emacs version and the optional RPC client's safety seams.
Never connect, prompt for credentials, or start remote work."
  (and
   (version<=
    claude-code-ide-remote-project--minimum-emacs-version
    emacs-version)
   (claude-code-ide-remote-project--load-client)))

(defun claude-code-ide-remote-project-open-target
    (host directory callback &optional reason on-close)
  "Prepare an explicit remote Project view for DIRECTORY on HOST.
Reject an unapproved HOST or a non-absolute DIRECTORY before any
remote work.  Never attach an existing Session and never enable
automatic display for HOST.

This shares every guard `claude-code-ide-remote-project-prepare' uses:
the RPC client gate, the health check, the 30-second deadline, and the
shared view registry that lets a matching Session-owned view reuse the
same native buffer.  It never fabricates a Session.

Call CALLBACK exactly once, on the main thread, with a plist:
:status `completed' or `failed', :host, :directory, and either
:buffer (on success) or :error (on failure).  REASON identifies why
this attempt started, for example a create-only view or a
user-requested mutation refresh; it defaults to `explicit-target'.
ON-CLOSE, when supplied, runs on the main thread after its candidate
or published view closes.  It does not own the shared connection.

Return the owned attempt.  Cancel it with
`claude-code-ide-remote-project-cancel-target'."
  (claude-code-ide-zmx--validate-host host)
  (unless (claude-code-ide-zmx--valid-directory-p directory)
    (user-error "Host %s requires an absolute remote directory" host))
  (unless (functionp callback)
    (user-error "The remote Project view callback must be a function"))
  (unless (or (null on-close) (functionp on-close))
    (user-error "The Project-view close callback must be a function"))
  (unless (claude-code-ide-remote-project-target-available-p)
    (user-error "Remote Project views require Emacs 30.1 and a compatible RPC client"))
  (let ((attempt
         (claude-code-ide-remote-project--make-attempt
          :id (make-symbol "remote-project-target-attempt")
          :host (copy-sequence host)
          :admitted-host (copy-sequence host)
          :requested-directory (copy-sequence directory)
          :directory
          (claude-code-ide-remote-project--rpc-directory host directory)
          :callback callback
          :on-close on-close
          :explicit-provider claude-code-ide-manager-status-buffer-function
          :reason (or reason 'explicit-target)
          :state 'checking-client)))
    (claude-code-ide-remote-project--spawn-worker
     attempt (format "remote-project-target-%s" host))))

(defun claude-code-ide-remote-project-cancel-target (attempt)
  "Cancel explicit ATTEMPT from `claude-code-ide-remote-project-open-target'.
Before dispatch this prevents any remote work.  After dispatch this
only stops local observation: ATTEMPT's callback never runs, and a
remote read or Project-view provider call already started still
finishes on its own."
  (claude-code-ide-remote-project--abandon-attempt attempt 'cancel))

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
  "Return SESSION-ID's exact surviving view for ATTACHMENT.
When ATTACHMENT is a freshly reattached buffer and the intent's old
attachment is no longer live, rebind the intent to ATTACHMENT first,
using the same transition `claude-code-ide-remote-project-prepare'
uses, but only when the Session's original host still admits Project
views.  Never reconnect or invoke a provider here."
  (when-let* ((intent
               (gethash session-id
                        claude-code-ide-remote-project--intents)))
    (unless (eq attachment
                (claude-code-ide-remote-project--intent-attachment intent))
      (when (and (not (buffer-live-p
                       (claude-code-ide-remote-project--intent-attachment intent)))
                 (claude-code-ide-manager--remote-project-enabled-p
                  session-id (claude-code-ide-remote-project--intent-host intent)))
        (claude-code-ide-remote-project--intent-for
         session-id (claude-code-ide-remote-project--intent-host intent)
         attachment)))
    (when-let* (((eq attachment
                     (claude-code-ide-remote-project--intent-attachment intent)))
                (host (claude-code-ide-manager--session-host session-id))
                (directory (claude-code-ide-manager--session-directory session-id))
                (request (claude-code-ide-remote-project--intent-layout-request intent))
                ((equal
                  (plist-get request :directory)
                  (claude-code-ide-remote-project-rpc-directory host directory)))
                ((or (eq (plist-get request :companion-kind) 'shell)
                     (let ((descriptor
                            (nth 3 (claude-code-ide-remote-project--intent-view-key intent))))
                       (and (eq (car descriptor) (plist-get request :companion-kind))
                            (eq (cadr descriptor) (plist-get request :provider))
                            (equal (nth 2 descriptor) (plist-get request :directory))))))
                ((not
                  (eq
                   (claude-code-ide-remote-project--intent-outcome intent)
                   'unavailable)))
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
        nil))))

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
     (not (eq (claude-code-ide-remote-project--intent-outcome intent) 'unavailable))
     (not (claude-code-ide-remote-project-surviving-view session-id attachment))
     (let ((attempt (claude-code-ide-remote-project--intent-attempt intent)))
       (and (or attempt (claude-code-ide-remote-project--intent-view-key intent))
            (or (null attempt)
                (not (claude-code-ide-manager--remote-layout-request-current-p
                      session-id attachment
                      (claude-code-ide-remote-project--attempt-frame attempt)
                      (claude-code-ide-remote-project--attempt-layout-request attempt)))))))))

(defun claude-code-ide-remote-project--view-killed ()
  "Remove the current dead Project view from local feature records."
  (let ((buffer (current-buffer))
        dead-keys close-callbacks)
    (maphash
     (lambda (key view)
       (when
           (eq
            buffer
            (claude-code-ide-remote-project--view-buffer view))
         (push key dead-keys)
         (setq close-callbacks
               (nconc (claude-code-ide-remote-project--view-close-callbacks view) close-callbacks))
         (setf (claude-code-ide-remote-project--view-close-callbacks view) nil)))
     claude-code-ide-remote-project--views)
    (dolist (key dead-keys)
      (remhash key claude-code-ide-remote-project--views))
    (dolist (callback close-callbacks)
      (run-at-time 0 nil callback))
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
         (reason
          (and (cl-loop for other being the hash-values of claude-code-ide-remote-project--views
                        thereis (and (not (eq other view))
                                     (eq (claude-code-ide-remote-project--view-buffer other)
                                         (claude-code-ide-remote-project--view-buffer view))))
               'shared)))
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
           ((claude-code-ide-remote-project--view-key-equal key sibling-key)
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

(defun claude-code-ide-remote-project--view-retention-reason (view)
  "Return why VIEW's own buffer state blocks reclaiming it, or nil."
  (let ((buffer
         (claude-code-ide-remote-project--view-buffer view)))
    (cond
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
      'query-hook))))

(defun claude-code-ide-remote-project--cleanup-retention-reason
    (snapshot view)
  "Return why SNAPSHOT must retain VIEW, or nil when it may kill it."
  (if (not
       (claude-code-ide-remote-project--cleanup-token-current-p
        snapshot))
      'newer-attachment
    (or
     (claude-code-ide-remote-project--view-retention-reason view)
     (claude-code-ide-remote-project--sharing-reason snapshot view))))

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

(defun claude-code-ide-remote-project--reconcile-live-sessions (key view)
  "Return VIEW's sessions whose intent still owns exact KEY."
  (cl-remove-if-not
   (lambda (session-id)
     (when-let*
         ((intent
           (gethash
            session-id claude-code-ide-remote-project--intents)))
       (claude-code-ide-remote-project--view-key-equal
        (claude-code-ide-remote-project--intent-view-key intent)
        key)))
   (claude-code-ide-remote-project--view-sessions view)))

(defun claude-code-ide-remote-project--reconcile-reason
    (view live-sessions)
  "Return why VIEW must survive reconciliation among LIVE-SESSIONS."
  (if (cdr live-sessions)
      'shared
    (pcase (claude-code-ide-remote-project--view-retention-reason view)
      ('modified 'modified)
      ('source-file 'source-file)
      ((or 'nil 'dead 'replaced) nil)
      (_ 'uncertain))))

(defun claude-code-ide-remote-project--reconcile-destination
    (surviving moved-to)
  "Return the best surviving Worktree plist for MOVED-TO in SURVIVING."
  (let ((target
         (and
          moved-to
          (claude-code-ide-remote-project--trim-directory moved-to))))
    (or
     (and
      target
      (cl-find-if
       (lambda (worktree)
         (and
          (plist-get worktree :exists)
          (equal
           (claude-code-ide-remote-project--trim-directory
            (plist-get worktree :path))
           target)))
       surviving))
     (cl-find-if
      (lambda (worktree) (plist-get worktree :exists)) surviving))))

(defun claude-code-ide-remote-project--affected-path-p (path affected)
  "Return non-nil for a known PATH at or below an AFFECTED Worktree."
  (and (claude-code-ide-zmx--valid-directory-p path)
       (not (string-match-p "/\\.\\.?\\(?:/\\|\\'\\)\\|//" path))
       (seq-some (lambda (root)
                   (or (equal path root) (string-prefix-p (concat root "/") path)))
                 affected)))

(defun claude-code-ide-remote-project--mark-unavailable (buffer host path)
  "Mark safe native BUFFER unavailable for exact HOST and PATH."
  (when (buffer-live-p buffer)
    (with-current-buffer buffer
      (when (and (memq major-mode '(magit-status-mode dired-mode))
                 (not buffer-file-name)
                 (not (buffer-modified-p))
                 (not (get-buffer-process buffer))
                 (not (claude-code-ide-remote-project--unknown-local-hook-p
                       buffer 'kill-buffer-hook '(claude-code-ide-remote-project--view-killed)))
                 (not (claude-code-ide-remote-project--unknown-local-hook-p
                       buffer 'kill-buffer-query-functions nil))
                 (string-prefix-p (format "/rpc:%s:" host) default-directory)
                 (equal path (claude-code-ide-remote-project--local-view-path
                              host default-directory)))
        (unless claude-code-ide-remote-project--unavailable-header
          (let ((label (format "Worktree unavailable on %s: %s" host path)))
            (setq claude-code-ide-remote-project--unavailable-header
                  (cons header-line-format label)
                  header-line-format label)))
        t))))

(defun claude-code-ide-remote-project-reconcile-worktrees
    (host affected surviving &optional moved-to)
  "Reconcile HOST's Project views after a Worktree change.
AFFECTED lists the exact canonical paths a Worktree mutation removed
or moved.  SURVIVING lists fresh validated Git worktree plists for
HOST.  MOVED-TO is the mutation's verified destination path, or nil.

Invalidate only a View whose exact HOST and known canonical path lie at
or below an AFFECTED entry and whose owners and buffer state permit it.
Require at most one owning Session and an unmodified, feature-created
Magit or Dired buffer with a matching mode and no file, process, or
custom hook of its own.  Clear only the intents of the sessions that
still own an invalidated View; an intent already pointing elsewhere is
left untouched.

Retain every other matching View's contents and owning intents'
view-key, view-buffer, and captured-view-name.  Never retarget such a
buffer.  Mark each retained intent unavailable so
`claude-code-ide-remote-project-surviving-view' stops returning it.

Mark unmodified matching Magit and Dired buffers with a host-qualified
unavailable header.  Fresh explicit preparation clears that header.
Do not contact a host, edit or save buffer contents, or select a window.

Return a plist:
:invalidated and :retained are lists of plists with :path, :buffer,
and :sessions (its live owning session IDs).  A :retained entry also
has :reason, one of `modified', `source-file', `shared', or
`uncertain'.
:destination is MOVED-TO's SURVIVING plist when verified, otherwise
the first surviving Worktree plist, or nil when none survives."
  (let ((affected
         (mapcar
          #'claude-code-ide-remote-project--trim-directory affected))
        invalidated retained dead-keys registered-buffers)
    (maphash
     (lambda (key view)
       (push (claude-code-ide-remote-project--view-buffer view) registered-buffers)
       (when
           (and
            (equal (nth 0 key) host)
            (claude-code-ide-remote-project--affected-path-p
             (claude-code-ide-remote-project--local-view-path
              host (nth 2 key))
             affected))
         (let*
             ((path
               (claude-code-ide-remote-project--local-view-path
                host (claude-code-ide-remote-project--key-directory key)))
              (live-sessions
               (claude-code-ide-remote-project--reconcile-live-sessions
                key view))
              (reason
               (claude-code-ide-remote-project--reconcile-reason
                view live-sessions)))
           (claude-code-ide-remote-project--mark-unavailable
            (claude-code-ide-remote-project--view-buffer view) host path)
           (if reason
               (progn
                 (dolist (session-id live-sessions)
                   (when-let*
                       ((intent
                         (gethash
                          session-id
                          claude-code-ide-remote-project--intents)))
                     (setf
                      (claude-code-ide-remote-project--intent-outcome
                       intent)
                      'unavailable)))
                 (push
                  (list
                   :path path
                   :buffer
                   (claude-code-ide-remote-project--view-buffer view)
                   :sessions live-sessions
                   :reason reason)
                  retained))
             (dolist (session-id live-sessions)
               (when-let*
                   ((intent
                     (gethash
                      session-id
                      claude-code-ide-remote-project--intents)))
                 (setf
                  (claude-code-ide-remote-project--intent-view-key
                   intent)
                  nil
                  (claude-code-ide-remote-project--intent-view-buffer
                   intent)
                  nil
                  (claude-code-ide-remote-project--intent-captured-view-name
                   intent)
                  nil
                  (claude-code-ide-remote-project--intent-outcome
                   intent)
                  nil)))
             (push key dead-keys)
             (push
              (list
               :path path
               :buffer (claude-code-ide-remote-project--view-buffer view)
               :sessions live-sessions)
              invalidated)))))
     claude-code-ide-remote-project--views)
    (dolist (key dead-keys)
      (remhash key claude-code-ide-remote-project--views))
    (dolist (buffer (buffer-list))
      (unless (memq buffer registered-buffers)
        (let ((path (claude-code-ide-remote-project--local-view-path
                     host (buffer-local-value 'default-directory buffer))))
          (when (and (claude-code-ide-remote-project--affected-path-p path affected)
                     (claude-code-ide-remote-project--mark-unavailable
                      buffer host path))
            (push (list :path path :buffer buffer :sessions nil :reason 'uncertain)
                  retained)))))
    (list
     :invalidated (nreverse invalidated)
     :retained (nreverse retained)
     :destination
     (claude-code-ide-remote-project--reconcile-destination
      surviving moved-to))))
(provide 'claude-code-ide-remote-project)
;;; claude-code-ide-remote-project.el ends here
