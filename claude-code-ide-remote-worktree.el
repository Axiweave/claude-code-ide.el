;;; claude-code-ide-remote-worktree.el --- Remote Worktree operations -*- lexical-binding: t; -*-

;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;;; Commentary:

;; An operation keeps its exact host and targets independently of a view.
;; Remote execution and local observation have separate lifetimes.

;;; Code:

(require 'cl-lib)
(require 'map)
(require 'subr-x)
(require 'ansi-color)
(require 'button)
(require 'claude-code-ide-zmx)

(declare-function claude-code-ide--cli-type-for-command "claude-code-ide" (command))
(declare-function claude-code-ide-remote-project-target-available-p
                  "claude-code-ide-remote-project" ())
(declare-function claude-code-ide-remote-project-open-target
                  "claude-code-ide-remote-project" (host directory callback &optional reason on-close))
(declare-function claude-code-ide-remote-project-cancel-target
                  "claude-code-ide-remote-project" (attempt))
(declare-function claude-code-ide-remote-project-reconcile-worktrees
                  "claude-code-ide-remote-project" (host affected surviving &optional moved-to))
(declare-function magit-lane-core-operation-plan "magit-lane-core" (snapshot action options))
(declare-function magit-worktrunk-core-operation-plan "magit-worktrunk-core" (snapshot action options))
(declare-function magit-lane-core--parse-list-json "magit-lane-core" (stdout stderr))
(declare-function magit-lane-core-normalize-entries "magit-lane-core" (entries trees-root identities))
(declare-function magit-worktrunk-core-normalize-entries "magit-worktrunk-core" (entries identities))
(defvar magit-lane-core-landed-marker-relpath)
(declare-function claude-code-ide--preferred-session "claude-code-ide" (directory &optional host))
(declare-function claude-code-ide--attach-zmx-entry "claude-code-ide" (entry directory cli-path &optional session-id intent-valid))
(declare-function claude-code-ide-session-id "claude-code-ide" (session))
(declare-function claude-code-ide-session-zmx-name "claude-code-ide" (session))
(declare-function claude-code-ide-session-cli-type "claude-code-ide" (session))
(declare-function claude-code-ide-manager--all-items "claude-code-ide-manager" ())
(declare-function claude-code-ide-manager--scope-state-entry "claude-code-ide-manager" (scope))
(declare-function claude-code-ide-manager--load-state "claude-code-ide-manager" ())
(declare-function claude-code-ide-manager-item-host "claude-code-ide-manager" (item))
(declare-function claude-code-ide-manager-item-directory "claude-code-ide-manager" (item))
(declare-function claude-code-ide-manager-item-zmx-name "claude-code-ide-manager" (item))
(declare-function claude-code-ide-manager-item-cli-type "claude-code-ide-manager" (item))
(declare-function claude-code-ide-manager-item-session-key "claude-code-ide-manager" (item))
(declare-function claude-code-ide-manager-switch-to-session "claude-code-ide-manager" (session-key &optional preserve-sidebar-focus scope))
(declare-function evil-set-initial-state "evil-core" (mode state))
(defvar read-eval)


(cl-defstruct (claude-code-ide-remote-worktree--operation
               (:constructor claude-code-ide-remote-worktree--make-operation))
  "One Worktree operation and its current remote attempt."
  id attempt-id parent-attempt kind target options snapshot steps approval
  receipt-directory (state 'preparing) (observation 'stopped) results
  (lane-initialization (bound-and-true-p claude-code-ide-lane-init-protocol))
  display-context error (generation 0) request timer launch-selection)

(defvar claude-code-ide-remote-worktree--operations
  (make-hash-table :test #'equal)
  "Operation IDs mapped to records for this Emacs session.")

(defvar claude-code-ide-remote-worktree--snapshots (make-hash-table :test #'equal)
  "Explicit listing snapshots keyed by exact host, directory, and backend.")

(defvar claude-code-ide-remote-worktree--sequence 0
  "Counter that separates operation tokens within this Emacs process.")

(defvar claude-code-ide-remote-worktree--results-buffer nil
  "The one feature-owned results buffer.")

(defvar-local claude-code-ide-remote-worktree--selected-operation nil
  "Operation ID displayed in the current results buffer.")

(defvar-local claude-code-ide-remote-worktree--results-visible nil
  "Non-nil after the results buffer owns a visible window.")


(defcustom claude-code-ide-remote-launch-config nil
  "Remote Agent overrides keyed by exact configured host.
Each value is a property list with optional `:executable' and `:args'.
The default executable is the globally selected Agent's standard command.
Remote arguments default to an empty list, without local CLI or MCP flags."
  :type '(alist :key-type string :value-type plist)
  :group 'claude-code-ide)
(defconst claude-code-ide-remote-worktree--option-keys
  '((list :backend :refresh)
    (open :backend :sibling :select :view-only :name :main)
    (create :backend :name :base :create-only :initialize :dirty)
    (remove :backend :name :force :force-delete :keep-branch)
    (move :backend :destination :native-argv)
    (merge :backend :name :base :keep :squash :no-squash :no-commit :no-rebase
           :no-ff :stage)
    (push :backend :name :base :native-argv)
    (prune :backend :dry-run))
  "Supported actions and their literal option keys.")

(defconst claude-code-ide-remote-worktree--transitions
  '((preparing awaiting-confirmation refused canceled-before-dispatch
               completed failed unknown)
    (awaiting-confirmation dispatching refused canceled-before-dispatch)
    (dispatching observing observation-stopped unknown failed)
    (observing completed partial failed unknown observation-stopped)
    (observation-stopped checking)
    (completed checking)
    (failed checking)
    (partial checking)
    (unknown checking)
    (checking completed still-running confirmed-unfinished partial unknown
              observation-stopped)
    (still-running checking observing observation-stopped unknown)
    (confirmed-unfinished awaiting-confirmation checking))
  "Permitted operation state transitions.")

(defun claude-code-ide-remote-worktree--literal-p (value)
  "Return non-nil if VALUE is a string without control characters."
  (and (stringp value)
       (not (string-match-p "[[:cntrl:]\177-\237]" value))))

(defun claude-code-ide-remote-worktree--token ()
  "Return a fresh 32-character hexadecimal operation token."
  (md5 (format "%s:%s:%s:%s"
               (emacs-pid) (current-time)
               (cl-incf claude-code-ide-remote-worktree--sequence)
               (random most-positive-fixnum))))

(defun claude-code-ide-remote-worktree--copy-options (action options)
  "Validate and copy literal OPTIONS for ACTION."
  (let ((entry (assq action claude-code-ide-remote-worktree--option-keys))
        seen result)
    (unless entry
      (user-error "Unsupported remote Worktree action: %S" action))
    (unless (and (proper-list-p options) (zerop (% (length options) 2)))
      (user-error "Remote Worktree options must be a property list"))
    (while options
      (let* ((key (pop options))
             (value (pop options))
             (copy
              (cond
               ((eq key :backend)
                (unless (memq value '(lane wt))
                  (user-error "Unsupported Worktree backend: %S" value))
                value)
               ((memq key '(:name :base :destination))
                (unless (and (claude-code-ide-remote-worktree--literal-p value)
                             (not (string-empty-p value)))
                  (user-error "Invalid remote Worktree option: %S" key))
                (copy-sequence value))
               ((eq key :native-argv)
                (unless (and (consp value) (proper-list-p value)
                             (cl-every #'claude-code-ide-remote-worktree--literal-p
                                       value))
                  (user-error "Native Git arguments must be literal strings"))
                (mapcar #'copy-sequence value))
               ((eq key :stage)
                (unless (memq value '(all tracked none))
                  (user-error "Unsupported Worktrunk staging mode: %S" value))
                value)
               (t
                (unless (memq value '(nil t))
                  (user-error "Remote Worktree flag must be boolean: %S" key))
                value))))
        (unless (and (memq key (cdr entry)) (not (memq key seen)))
          (user-error "Unsupported or duplicate Worktree option: %S" key))
        (push key seen)
        (push key result)
        (push copy result)))
    (nreverse result)))

;;;###autoload
(defun claude-code-ide-remote-worktree-target-for-file (filename)
  "Decode FILENAME's exact approved RPC target without remote I/O.
Return nil for a local filename.  Reject unsupported remote routes."
  (cond
   ((string-prefix-p "/rpc:" filename)
    (let (targets)
      (dolist (host claude-code-ide-remote-hosts)
        (let ((prefix (format "/rpc:%s:" host)))
          (when (string-prefix-p prefix filename)
            (let ((directory (substring filename (length prefix))))
              (when (claude-code-ide-zmx--valid-directory-p directory)
                (claude-code-ide-zmx--validate-host host)
                (push (list :host host :directory directory) targets))))))
      (unless (= (length targets) 1)
        (user-error "The RPC filename has no unique configured host and absolute directory: %s" filename))
      (car targets)))
   ((file-remote-p filename)
    (user-error "Remote Worktree actions require an approved RPC filename: %s" filename))))

(defun claude-code-ide-remote-worktree-snapshot-for-file (filename backend)
  "Return FILENAME's exact cached BACKEND snapshot without I/O."
  (when-let* ((target (claude-code-ide-remote-worktree-target-for-file filename)))
    (gethash (list (plist-get target :host)
                   (directory-file-name (plist-get target :directory)) backend)
             claude-code-ide-remote-worktree--snapshots)))

;;;###autoload
(defun claude-code-ide-remote-worktree-refresh (&optional backend directory)
  "Request a fresh BACKEND listing for RPC DIRECTORY, or the current directory."
  (interactive)
  (let* ((filename (or directory default-directory))
         (target (claude-code-ide-remote-worktree-target-for-file filename)))
    (unless target (user-error "Remote refresh requires an approved RPC directory"))
    (claude-code-ide-remote-worktree-request
     'list (plist-get target :host) (plist-get target :directory)
     (append (and backend (list :backend backend)) '(:refresh t)))))

(defun claude-code-ide-remote-worktree--publish-snapshot (operation &optional snapshot)
  "Publish SNAPSHOT or OPERATION's listing under its exact directory identities."
  (let* ((snapshot (copy-tree (or snapshot (claude-code-ide-remote-worktree--operation-snapshot operation))))
         (host (plist-get snapshot :host))
         (backend (plist-get snapshot :backend)))
    (dolist (directory (delete-dups
                        (append (list (plist-get snapshot :directory)
                                      (plist-get snapshot :worktree)
                                      (plist-get snapshot :main-worktree))
                                (mapcar (lambda (entry) (plist-get entry :path))
                                        (plist-get snapshot :worktrees)))))
      (when directory
        (puthash (list host (directory-file-name directory) backend) snapshot
                 claude-code-ide-remote-worktree--snapshots)))))

(defun claude-code-ide-remote-worktree--launch-selection (host)
  "Return an immutable description of HOST's selected Agent settings."
  (require 'claude-code-ide)
  (let ((print-length nil) (print-level nil) (print-circle t))
    (prin1-to-string
     (list (claude-code-ide--cli-type-for-command
            (default-value 'claude-code-ide-cli-path))
           (cdr (assoc host (default-value 'claude-code-ide-remote-launch-config)))))))

(defun claude-code-ide-remote-worktree--launch-current-p (operation)
  "Return non-nil when OPERATION's planned launch still has its captured settings."
  (or (not (seq-some (lambda (step) (eq (plist-get step :kind) 'bootstrap))
                     (claude-code-ide-remote-worktree--operation-steps operation)))
      (equal (claude-code-ide-remote-worktree--operation-launch-selection operation)
             (claude-code-ide-remote-worktree--launch-selection
              (plist-get (claude-code-ide-remote-worktree--operation-target operation) :host)))))

(defun claude-code-ide-remote-worktree--new-operation
    (action host directory options)
  "Capture validated ACTION, HOST, DIRECTORY, and OPTIONS without I/O."
  (claude-code-ide-zmx--validate-host host)
  (unless (claude-code-ide-zmx--valid-directory-p directory)
    (user-error "Host %s requires an absolute Worktree directory" host))
  (let* ((copied-options
          (claude-code-ide-remote-worktree--copy-options action options))
         (id (claude-code-ide-remote-worktree--token))
         (operation
          (claude-code-ide-remote-worktree--make-operation
           :id id :attempt-id (claude-code-ide-remote-worktree--token)
           :kind action
           :target (list :host (copy-sequence host)
                         :directory (copy-sequence directory))
           :options copied-options
           :launch-selection
           (when (and (memq action '(open create))
                      (not (plist-get copied-options :create-only))
                      (not (plist-get copied-options :view-only)))
             (claude-code-ide-remote-worktree--launch-selection host))
           :display-context (list :frame (selected-frame)
                                  :window (selected-window)
                                  :directory (copy-sequence default-directory)
                                  :buffer (current-buffer)))))
    (puthash id operation claude-code-ide-remote-worktree--operations)
    operation))

(defun claude-code-ide-remote-worktree--transition (operation next)
  "Move OPERATION to NEXT when its lifecycle permits that transition."
  (let ((current (claude-code-ide-remote-worktree--operation-state operation)))
    (unless (memq next
                  (cdr (assq current claude-code-ide-remote-worktree--transitions)))
      (error "Invalid Worktree operation transition: %S to %S" current next))
    (setf (claude-code-ide-remote-worktree--operation-state operation) next)
    (claude-code-ide-remote-worktree--present-results operation (not (eq current next)))
    next))

(defun claude-code-ide-remote-worktree--current-p (operation attempt generation)
  "Return non-nil when OPERATION still owns ATTEMPT and GENERATION."
  (and (eq operation
           (gethash (claude-code-ide-remote-worktree--operation-id operation)
                    claude-code-ide-remote-worktree--operations))
       (equal attempt
              (claude-code-ide-remote-worktree--operation-attempt-id operation))
       (= generation
          (claude-code-ide-remote-worktree--operation-generation operation))))

(defun claude-code-ide-remote-worktree--fail (operation diagnostic)
  "Record DIAGNOSTIC without treating uncertain execution as non-execution."
  (when-let* ((timer (claude-code-ide-remote-worktree--operation-timer operation)))
    (cancel-timer timer)
    (setf (claude-code-ide-remote-worktree--operation-timer operation) nil))
  (let* ((state (claude-code-ide-remote-worktree--operation-state operation))
         (next (if (memq state '(preparing awaiting-confirmation))
                   'refused
                 'unknown)))
    (setf (claude-code-ide-remote-worktree--operation-error operation)
          (format "Host %s: %s"
                  (plist-get (claude-code-ide-remote-worktree--operation-target
                              operation) :host)
                  diagnostic)
          (claude-code-ide-remote-worktree--operation-observation operation)
          'disconnected)
    (claude-code-ide-remote-worktree--transition operation next)))

(defun claude-code-ide-remote-worktree--control
    (operation purpose program argv callback &optional directory output-limit failure)
  "Run one bounded control request for OPERATION and PURPOSE."
  (let ((attempt (claude-code-ide-remote-worktree--operation-attempt-id operation))
        (generation (claude-code-ide-remote-worktree--operation-generation operation))
        (target (claude-code-ide-remote-worktree--operation-target operation))
        (fail (lambda (diagnostic)
                (if failure (funcall failure diagnostic)
                  (claude-code-ide-remote-worktree--fail operation diagnostic)))))
    (setf (claude-code-ide-remote-worktree--operation-request operation)
          (claude-code-ide-zmx-remote-exec
           (plist-get target :host) purpose "sh"
           (append
            '("-c" "unset GIT_DIR GIT_WORK_TREE GIT_COMMON_DIR CDPATH; exec \"$@\""
              "cci-worktree-control")
            (list program) argv)
           (lambda (result)
             (when (claude-code-ide-remote-worktree--current-p
                    operation attempt generation)
               (setf (claude-code-ide-remote-worktree--operation-request operation) nil)
               (if (and (claude-code-ide-zmx--remote-request-ok-p result)
                        (not (plist-get result :overflow)))
                   (condition-case error-data
                       (funcall callback (plist-get result :stdout))
                     (error
                      (funcall fail (error-message-string error-data))))
                 (funcall
                  fail
                  (cond ((plist-get result :timeout) "The control request exceeded 30 seconds")
                        ((plist-get result :overflow) "The control request exceeded its output limit")
                        ((plist-get result :cancelled) "The control request was canceled")
                        (t (format "The control request failed with status %s: %s"
                                   (plist-get result :status)
                                   (string-trim (plist-get result :stderr)))))))))
           (or directory (plist-get target :directory))
           (format "cci-worktree-control-%s"
                   (claude-code-ide-remote-worktree--operation-id operation))
           (or output-limit 1048576)))))

(defun claude-code-ide-remote-worktree--metadata (operation directories callback &optional failure)
  "Resolve DIRECTORIES, then call CALLBACK.  Report read errors through FAILURE."
  (let ((attempt (claude-code-ide-remote-worktree--operation-attempt-id operation))
        (generation (claude-code-ide-remote-worktree--operation-generation operation))
        (host (plist-get
               (claude-code-ide-remote-worktree--operation-target operation) :host))
        (batches (seq-partition directories claude-code-ide-zmx--metadata-max-directories))
        records)
    (cl-labels
        ((fail (diagnostic)
           (if failure (funcall failure diagnostic)
             (claude-code-ide-remote-worktree--fail operation diagnostic)))
         (next ()
           (if (null batches)
               (funcall callback (apply #'append (nreverse records)))
             (setf (claude-code-ide-remote-worktree--operation-request operation)
                   (claude-code-ide-zmx--query-remote-metadata
                    host (pop batches)
                    (lambda (result)
                      (when (claude-code-ide-remote-worktree--current-p
                             operation attempt generation)
                        (setf (claude-code-ide-remote-worktree--operation-request
                               operation) nil)
                        (if (plist-get result :error)
                            (fail (plist-get result :error))
                          (condition-case error-data
                              (progn
                                (push (plist-get result :records) records)
                                (next))
                            (error
                             (fail (error-message-string error-data))))))))))))
      (next))))

(defconst claude-code-ide-remote-worktree--preparation-script
  (mapconcat
   #'identity
   '("set -eu"
     "export LC_ALL=C"
     "printf '%s\\000' cci-preparation-1"
     "for program in \"$2\" \"$3\" \"$4\" \"$5\"; do path=$(command -v \"$program\") || path=; printf '%s\\000' \"$path\"; done"
     "if [ -d \"$1/.lane\" ]; then printf 'yes\\000'; else printf 'no\\000'; fi"
     "preference=$(\"$2\" config --get claude-code-ide.worktree-backend) || { status=$?; [ \"$status\" = 1 ] || exit \"$status\"; }"
     "printf '%s\\000' \"$preference\""
     "settings_dir=$1"
     "while [ ! -f \"$settings_dir/.dir-locals.el\" ] && [ ! -f \"$settings_dir/.dir-locals-2.el\" ] && [ \"$settings_dir\" != / ]; do settings_dir=${settings_dir%/*}; [ -n \"$settings_dir\" ] || settings_dir=/; done"
     "printf '%s\\000' \"$settings_dir\""
     "for file in .dir-locals.el .dir-locals-2.el; do if [ -f \"$settings_dir/$file\" ]; then [ \"$(wc -c < \"$settings_dir/$file\")\" -le 65536 ] || exit 80; cat \"$settings_dir/$file\"; fi; printf '\\000'; done"
     "refs=$(\"$2\" for-each-ref '--format=%(refname) %(objectname)' 2>&1) || exit"
     "printf '%s\\000' \"$refs\""
     "\"$2\" worktree list --porcelain -z")
   "; ")
  "Fixed read-only snapshot probe.  Positional arguments carry remote values.")

(defun claude-code-ide-remote-worktree--safe-preference (sources root directory)
  "Collect the literal backend value from SOURCES under ROOT for DIRECTORY."
  (unless (and (claude-code-ide-zmx--valid-directory-p root)
               (string-prefix-p (file-name-as-directory root)
                                (file-name-as-directory directory)))
    (user-error "The directory-local settings have an invalid root"))
  (condition-case error-data
      (with-temp-buffer
        (let ((file-name-handler-alist nil)
              (default-directory (file-name-as-directory directory))
              variables)
          (dolist (source sources)
            (unless (string-empty-p source)
              (let ((value (let ((read-circle nil)
                                 (read-eval nil))
                             (car (read-from-string source)))))
                (unless (proper-list-p value)
                  (user-error "The directory-local settings must be a list"))
                (setq variables
                      (map-merge-with
                       'list (lambda (left right) (map-merge 'list left right))
                       variables value)))))
          ;; Collect data only.  Never apply mode, eval, or other local variables.
          (let ((preference
                 (cdr (assq 'claude-code-ide-worktree-backend
                            (dir-locals-collect-variables
                             (dir-locals--sort-variables variables)
                             (file-name-as-directory root) nil)))))
            (and (memq preference '(lane wt)) preference))))
    (error (user-error "Cannot read the repository directory-local settings: %s"
                       (error-message-string error-data)))))

(defun claude-code-ide-remote-worktree--parse-worktrees (fields)
  "Parse NUL-delimited Git porcelain FIELDS without local filesystem access."
  (let (entry entries)
    (dolist (field fields)
      (cond
       ((string-empty-p field)
        (when entry (push entry entries) (setq entry nil)))
       ((string-prefix-p "worktree " field)
        (when entry (user-error "The Worktree listing has no record delimiter"))
        (let ((path (substring field 9)))
          (unless (claude-code-ide-zmx--valid-directory-p path)
            (user-error "The Worktree listing contains an invalid path"))
          (setq entry (list :path path))))
       ((null entry) (user-error "The Worktree listing has no path"))
       ((string-prefix-p "HEAD " field)
        (let ((oid (substring field 5)))
          (unless (string-match-p "\\`[0-9a-f]\\{40\\}\\(?:[0-9a-f]\\{24\\}\\)?\\'" oid)
            (user-error "The Worktree listing contains an invalid object ID"))
          (setq entry (plist-put entry :head oid))))
       ((string-prefix-p "branch refs/heads/" field)
        (setq entry (plist-put entry :branch (substring field 18))))
       ((equal field "detached") (setq entry (plist-put entry :detached t)))
       ((equal field "bare") (setq entry (plist-put entry :bare t)))
       ((or (equal field "locked") (string-prefix-p "locked " field))
        (setq entry (plist-put entry :locked t)))
       ((or (equal field "prunable") (string-prefix-p "prunable " field))
        (setq entry (plist-put entry :prunable t)))
       (t (user-error "The Worktree listing contains an unsupported field"))))
    (when entry (user-error "The Worktree listing has no final delimiter"))
    (unless entries (user-error "The repository has no Worktree registration"))
    (nreverse entries)))

(defun claude-code-ide-remote-worktree--prepare (operation callback)
  "Build OPERATION's read-only snapshot and pass it to CALLBACK."
  (let* ((target (claude-code-ide-remote-worktree--operation-target operation))
         (directory (plist-get target :directory))
         (host (plist-get target :host))
         (origin-target
          (and (memq (claude-code-ide-remote-worktree--operation-kind operation)
                     '(remove move merge prune))
               (condition-case nil
                   (claude-code-ide-remote-worktree-target-for-file
                    (or (plist-get (claude-code-ide-remote-worktree--operation-display-context operation)
                                   :directory) ""))
                 (user-error nil))))
         (origin-directory (and (equal host (plist-get origin-target :host))
                                (plist-get origin-target :directory)))
         (directories (delete-dups (delq nil (list directory origin-directory)))))
    (claude-code-ide-remote-worktree--metadata
     operation directories
     (lambda (records)
       (let* ((identity (car records))
              (origin-identity (and origin-directory
                                    (nth (cl-position origin-directory directories :test #'equal) records)))
              (repository (plist-get identity :common-dir))
              (main (plist-get identity :project-path))
              (tool-names
               (list "git" claude-code-ide-zmx-program
                     (if (boundp 'magit-lane-executable) magit-lane-executable "lane")
                     (if (boundp 'magit-worktrunk-wt-executable)
                         magit-worktrunk-wt-executable "wt"))))
         (unless (eq (plist-get identity :kind) 'git)
           (user-error "The selected path does not identify an accessible Git repository"))
         (dolist (tool tool-names)
           (unless (and (claude-code-ide-remote-worktree--literal-p tool)
                        (not (string-empty-p tool))
                        (not (string-prefix-p "-" tool)))
             (user-error "A remote tool setting is invalid")))
         (claude-code-ide-remote-worktree--control
          operation "worktree-preparation" "sh"
          (append (list "-c" claude-code-ide-remote-worktree--preparation-script
                        "cci-preparation" main) tool-names)
          (lambda (stdout)
            (unless (string-suffix-p (string 0) stdout)
              (user-error "The preparation response has no final delimiter"))
            (let* ((fields (split-string (substring stdout 0 -1) (string 0)))
                   (tools (cl-mapcar
                           (lambda (name path)
                             (cons name
                                   (and (claude-code-ide-zmx--valid-directory-p path)
                                        path)))
                           '(git zmx lane wt) (seq-subseq fields 1 5)))
                   (store (equal (nth 5 fields) "yes"))
                   (preference
                    (or (and store 'lane)
                        (claude-code-ide-remote-worktree--safe-preference
                         (seq-subseq fields 8 10) (nth 7 fields) main)
                        (cdr (assoc (nth 6 fields) '(("lane" . lane) ("wt" . wt))))
                        (and (boundp 'claude-code-ide-worktree-backend)
                             claude-code-ide-worktree-backend)
                        'lane))
                   (entries (claude-code-ide-remote-worktree--parse-worktrees
                             (nthcdr 11 fields)))
                   (snapshot
                    (list :host host :repository repository
                          :directory directory :worktree (plist-get identity :worktree-path)
                          :main-worktree main :branch (plist-get identity :branch)
                          :origin-worktree (and (eq (plist-get origin-identity :kind) 'git)
                                                (plist-get origin-identity :worktree-path))
                          :tools tools :lane-store store
                          :settings (list :backend preference)
                          :refs (claude-code-ide-remote-worktree--parse-refs (nth 10 fields)))))
              (unless (equal (car fields) "cci-preparation-1")
                (user-error "The preparation response has an unsupported version"))
              (claude-code-ide-remote-worktree--metadata
               operation (mapcar (lambda (entry) (plist-get entry :path)) entries)
               (lambda (resolved)
                 (setq entries (cl-mapcar
                                (lambda (entry record)
                                  (cond
                                   ((eq (plist-get record :kind) 'git)
                                    (unless (and (equal repository (plist-get record :common-dir))
                                                 (or (plist-get entry :bare)
                                                     (equal (plist-get entry :branch)
                                                            (plist-get record :branch))))
                                      (user-error "A Worktree identity changed during preparation"))
                                    (setf (plist-get entry :path)
                                          (or (plist-get record :worktree-path)
                                              (plist-get record :project-path))
                                          (plist-get entry :exists) t))
                                   ((plist-get entry :prunable)
                                    (setf (plist-get entry :exists) 'unknown))
                                   (t (user-error "Cannot resolve a registered Worktree")))
                                  entry)
                                entries resolved))
                 (setq snapshot (plist-put snapshot :worktrees entries))
                 (setf (claude-code-ide-remote-worktree--operation-snapshot operation)
                       snapshot)
                 (funcall callback snapshot)))))))))))

(defun claude-code-ide-remote-worktree--check-backend-options (backend options)
  "Reject OPTIONS that belong to the other BACKEND before any mutation."
  (dolist (key (if (eq backend 'lane)
                   '(:force-delete :keep-branch :no-squash :no-commit :no-rebase :no-ff :stage)
                 '(:initialize :dirty)))
    (when (plist-member options key)
      (user-error "The %s backend does not support the %s option" backend key))))

(defun claude-code-ide-remote-worktree--prepare-backend
    (operation callback &optional view-snapshot failure)
  "Read OPERATION's backend listing, then call CALLBACK.
With VIEW-SNAPSHOT, publish display data without changing the admitted plan.
Report view-read errors through FAILURE."
  (let* ((snapshot (or view-snapshot (claude-code-ide-remote-worktree--operation-snapshot operation)))
         (options (if view-snapshot (list :backend (plist-get snapshot :backend))
                    (claude-code-ide-remote-worktree--operation-options operation)))
         (backend (or (plist-get options :backend)
                      (and (eq (claude-code-ide-remote-worktree--operation-kind operation) 'remove)
                           (not (plist-get options :name)) (not (plist-get snapshot :lane-store)) 'wt)
                      (plist-get (plist-get snapshot :settings) :backend)))
         (feature (cdr (assq backend '((lane . magit-lane-core) (wt . magit-worktrunk-core)))))
         (program (alist-get backend (plist-get snapshot :tools))))
    (claude-code-ide-remote-worktree--check-backend-options backend options)
    (unless (and feature (require feature nil t))
      (user-error "The selected Worktree backend package is unavailable: %s" backend))
    (setf (plist-get snapshot :backend) backend)
    (cl-labels
        ((finish (rows root identities)
           (setf (plist-get snapshot :backend-entries)
                 (if (eq backend 'lane)
                     (magit-lane-core-normalize-entries rows root identities)
                   (magit-worktrunk-core-normalize-entries rows identities))
                 (plist-get snapshot :lane-trees-root) root)
           (unless view-snapshot
             (setf (claude-code-ide-remote-worktree--operation-snapshot operation) snapshot))
           (if (and (not view-snapshot) (eq backend 'lane)
                    (eq (claude-code-ide-remote-worktree--operation-kind operation) 'remove)
                    (not (plist-get options :backend)) (not (plist-get options :name))
                    (not (seq-some
                          (lambda (entry) (equal (alist-get 'path entry) (plist-get snapshot :worktree)))
                          (plist-get snapshot :backend-entries))))
               (progn
                 (setf (claude-code-ide-remote-worktree--operation-options operation)
                       (plist-put options :backend 'wt))
                 (claude-code-ide-remote-worktree--prepare-backend operation callback))
             (unless view-snapshot
               (setf (claude-code-ide-remote-worktree--operation-options operation)
                     (plist-put options :backend backend)))
             (claude-code-ide-remote-worktree--publish-snapshot operation snapshot)
             (funcall callback operation))))
      (cond
       ((eq backend 'wt)
        ;; `wt list' can write Git caches.  These verified Git records already
        ;; contain every Worktrunk column this interface displays.
        (let (rows identities)
          (dolist (entry (plist-get snapshot :worktrees))
            (when (and (eq (plist-get entry :exists) t) (not (plist-get entry :bare)))
              (let ((path (plist-get entry :path)))
                (push (list '(kind . "worktree") (cons 'path path)
                            (cons 'branch (plist-get entry :branch))
                            (cons 'is_main (equal path (plist-get snapshot :main-worktree)))
                            (cons 'is_current (equal path (plist-get snapshot :worktree))))
                      rows)
                (push (cons path path) identities))))
          (finish (nreverse rows) "" identities)))
       ((not (plist-get snapshot :lane-store))
        (finish nil (concat (plist-get snapshot :main-worktree) "/.lane/trees") nil))
       (t
        (unless (claude-code-ide-zmx--valid-directory-p program)
          (user-error "The required remote tool is unavailable: %s" backend))
        (claude-code-ide-remote-worktree--control
         operation "worktree-backend-list" "/bin/sh"
         (list "-c"
               "set -eu; root=\"$1/.lane/trees\"; if [ -d \"$root\" ]; then root=$(cd \"$root\" && pwd -P); fi; printf '%s\\000' \"$root\"; exec \"$2\" ls --json"
               "cci-backend-list" (plist-get snapshot :main-worktree) program)
         (lambda (stdout)
           (unless (string-match (string 0) stdout)
             (user-error "The backend listing has no identity delimiter"))
           (let* ((root (substring stdout 0 (match-beginning 0)))
                  (json (substring stdout (match-end 0)))
                  (rows (magit-lane-core--parse-list-json json ""))
                  (paths (delq nil (mapcar (lambda (row) (alist-get 'path row)) rows))))
             (claude-code-ide-remote-worktree--metadata
              operation paths
              (lambda (records)
                (finish
                 rows root
                 (cl-mapcar
                  (lambda (path record)
                    (cons path (and (eq (plist-get record :kind) 'git)
                                    (equal (plist-get record :common-dir) (plist-get snapshot :repository))
                                    (plist-get record :worktree-path))))
                  paths records)))
              failure)))
         (plist-get snapshot :main-worktree) nil failure))))))

(defun claude-code-ide-remote-worktree--agent-directory (session)
  "Return SESSION's reported start directory when it is safe to resolve.
Return nil for a missing, non-string, or non-absolute value instead of
sending it through the remote Git metadata probe."
  (let ((directory (plist-get session :start_dir)))
    (and (claude-code-ide-zmx--valid-directory-p directory) directory)))

(defun claude-code-ide-remote-worktree--owned-cli-type (host session)
  "Return trusted Agent metadata for SESSION's verified identity on HOST."
  (let ((identity (mapcar (lambda (key) (plist-get session key))
                          '(:name :pid :created :cmd :start_dir)))
        cli-type)
    (maphash
     (lambda (_id operation)
       (dolist (attempt (cons operation
                              (plist-get (claude-code-ide-remote-worktree--operation-results operation) :attempts)))
         (let ((result (claude-code-ide-remote-worktree--operation-results attempt)))
           (when (and (equal host (plist-get (claude-code-ide-remote-worktree--operation-target attempt) :host))
                      (plist-get (plist-get result :evidence) :bootstrap)
                      (equal identity (plist-get result :bootstrap-identity)))
             (setq cli-type
                   (plist-get (plist-get (claude-code-ide-remote-worktree--operation-snapshot attempt) :launch)
                              :cli-type))))))
     claude-code-ide-remote-worktree--operations)
    cli-type))

(defun claude-code-ide-remote-worktree--resolve-agent (host session record)
  "Resolve SESSION on HOST from Git RECORD, or retain an unresolved error."
  (let* ((name (plist-get session :name))
         (command (claude-code-ide-zmx-infer-cli-command (plist-get session :cmd)))
         (cli-type (or (and command (claude-code-ide--cli-type-for-command command))
                       (claude-code-ide-remote-worktree--owned-cli-type host session)))
         (error
          (or (plist-get session :error)
              (cond
               ((null record) "The Agent has no resolvable start directory")
               ((eq (plist-get record :kind) 'error)
                (or (plist-get record :diagnostic) "The Agent metadata query failed"))
               ((not (and (eq (plist-get record :kind) 'git)
                          (claude-code-ide-zmx--valid-directory-p
                           (plist-get record :worktree-path))
                          (claude-code-ide-zmx--valid-directory-p
                           (plist-get record :common-dir))))
                "The Agent has no resolvable Worktree identity")
               ((not cli-type) "The Agent command wrapper is unresolved")))))
    (if error
        (list :host host :name name :error error
              :directory (or (plist-get record :worktree-path)
                             (and (eq (plist-get record :kind) 'non-git)
                                  (plist-get record :project-path)))
              :worktree (plist-get record :worktree-path)
              :repository (plist-get record :common-dir))
      (list :host host :name name
            :directory (plist-get session :start_dir)
            :worktree (plist-get record :worktree-path)
            :repository (plist-get record :common-dir)
            :cli-type cli-type :pid (plist-get session :pid)
            :created (plist-get session :created)
            :clients (plist-get session :clients)))))

(defun claude-code-ide-remote-worktree--resolve-agents
    (operation sessions inventory-text callback)
  "Resolve raw zmx SESSIONS for OPERATION, then call CALLBACK with OPERATION.
Query batched remote Git metadata for every SESSION with a directory
worth resolving, then set the snapshot's `:agents' \(one
`claude-code-ide-remote-worktree--resolve-agent' plist per SESSION, in
order\) and `:agent-inventory' to INVENTORY-TEXT -- the exact zmx list
text a later runner admission check can compare against -- before
calling CALLBACK.  Route any resolution failure through
`claude-code-ide-remote-worktree--fail' instead of signaling, so a
broken batch still fails OPERATION closed."
  (let* ((host (plist-get (claude-code-ide-remote-worktree--operation-target operation) :host))
         (resolvable (seq-filter #'claude-code-ide-remote-worktree--agent-directory sessions))
         (directories (mapcar #'claude-code-ide-remote-worktree--agent-directory resolvable)))
    (claude-code-ide-remote-worktree--metadata
     operation directories
     (lambda (records)
       (condition-case error-data
           (let ((remaining records))
             (setf (claude-code-ide-remote-worktree--operation-snapshot operation)
                   (plist-put
                    (plist-put
                     (claude-code-ide-remote-worktree--operation-snapshot operation)
                     :agent-inventory inventory-text)
                    :agents
                    (mapcar
                     (lambda (session)
                       (claude-code-ide-remote-worktree--resolve-agent
                        host session
                        (and (claude-code-ide-remote-worktree--agent-directory session)
                             (pop remaining))))
                     sessions)))
             (funcall callback operation))
         (error
          (claude-code-ide-remote-worktree--fail
           operation (error-message-string error-data))))))))

(defun claude-code-ide-remote-worktree--inventory (operation callback)
  "Refresh OPERATION's Agent inventory, then call CALLBACK with OPERATION.
Query the exact host through the existing bounded zmx transport
\(`claude-code-ide-zmx-discover-remote'\), then resolve every reported
session through the existing batched remote Git metadata query
\(`claude-code-ide-remote-worktree--metadata'\) -- never a local
filesystem probe or a cached `claude-code-ide--sessions' row.  The
result covers every Agent the host reports: attached or not, started
by this Emacs or externally, in any Worktree of the host.

On success the snapshot carries `:agents' \(see
`claude-code-ide-remote-worktree--resolve-agent' for its plist shape\)
and `:agent-inventory', the zmx rows or a canonical empty diagnostic
for the runner's admission check.  A host with no sessions still
sets `:agents' to an empty list, distinct from a snapshot whose
inventory was never refreshed.

Any zmx, parsing, or metadata failure instead calls
`claude-code-ide-remote-worktree--fail' and never calls CALLBACK, so a
broken refresh can never leave a stale `:agents' looking current."
  (let* ((attempt (claude-code-ide-remote-worktree--operation-attempt-id operation))
         (generation (claude-code-ide-remote-worktree--operation-generation operation))
         (host (plist-get (claude-code-ide-remote-worktree--operation-target operation) :host)))
    (setf (claude-code-ide-remote-worktree--operation-request operation)
          (claude-code-ide-zmx-discover-remote
           host
           (lambda (result)
             (when (claude-code-ide-remote-worktree--current-p operation attempt generation)
               (setf (claude-code-ide-remote-worktree--operation-request operation) nil)
               (if (plist-get result :error)
                   (claude-code-ide-remote-worktree--fail operation (plist-get result :error))
                 (claude-code-ide-remote-worktree--resolve-agents
                  operation (plist-get result :sessions)
                  (if (plist-get result :sessions)
                      (plist-get result :stdout)
                    "no sessions found\n")
                  callback))))))))

(defun claude-code-ide-remote-worktree--protected-targets (operation)
  "Return every `:protected-targets' entry across OPERATION's current steps."
  (apply #'append
         (mapcar (lambda (step) (plist-get step :protected-targets))
                 (claude-code-ide-remote-worktree--operation-steps operation))))

(defun claude-code-ide-remote-worktree--assert-unprotected (operation)
  "Signal a `user-error' unless OPERATION's protected Worktrees are clear.
Return OPERATION when every pending step is safe to arm.  Do nothing
when no step requires protection.  Otherwise require a snapshot
`:agents' key that
`claude-code-ide-remote-worktree--inventory' already refreshed: a
never-queried snapshot, or any row this Emacs process could not
resolve, blocks every protected step in OPERATION.  A resolved Agent
whose canonical `:worktree' lies inside a protected target also blocks,
including nested repositories, idle, detached, and externally started Agents.
It never stops an Agent or reads a force option.  Only clear fresh inventory
can arm a protected step."
  (when (claude-code-ide-remote-worktree--protection-required-p operation)
    (let* ((targets (claude-code-ide-remote-worktree--protected-targets operation))
           (snapshot (claude-code-ide-remote-worktree--operation-snapshot operation))
           (host (plist-get (claude-code-ide-remote-worktree--operation-target operation) :host))
           (agents-cell (and snapshot (plist-member snapshot :agents))))
      (unless agents-cell
        (user-error "Host %s: refresh the Agent inventory before this Worktree step" host))
      (dolist (agent (cadr agents-cell))
        (cond
         ((plist-get agent :error)
          (user-error "Host %s: Agent %s has an unresolved identity: %s"
                      host (or (plist-get agent :name) "an Agent")
                      (plist-get agent :error)))
         ((seq-some
           (lambda (target)
             (string-prefix-p (file-name-as-directory target)
                              (file-name-as-directory (plist-get agent :worktree))))
           targets)
          (user-error "Host %s: Agent %s is active in a protected Worktree: %s"
                      host (or (plist-get agent :name) "an Agent")
                      (plist-get agent :worktree)))))))
  operation)

(defconst claude-code-ide-remote-worktree--runner-file
  (expand-file-name
   "scripts/remote-worktree-runner.sh"
   (file-name-directory (or load-file-name buffer-file-name)))
  "Package-owned runner source, independent of the current buffer.")

(defconst claude-code-ide-remote-worktree--step-kinds
  '(backend-setup backend-create record-result bootstrap backend-merge
                  named-remove native-move native-push backend-push native-prune)
  "Fixed command kinds accepted by the trusted plan renderer.")

(defconst claude-code-ide-remote-worktree--protected-kinds
  '(backend-merge named-remove native-move native-prune backend-push native-push)
  "Step kinds that cannot run without final Agent admission.")

(defun claude-code-ide-remote-worktree--protection-required-p (operation)
  "Return non-nil when OPERATION requires Agent admission.
This includes registration pruning."
  (seq-some (lambda (step)
              (or (plist-get step :protected-targets)
                  (memq (plist-get step :kind) claude-code-ide-remote-worktree--protected-kinds)))
            (claude-code-ide-remote-worktree--operation-steps operation)))

(defun claude-code-ide-remote-worktree--render-protection (operation step)
  "Render STEP's exact final Agent and Git identity check for OPERATION."
  (let* ((snapshot (claude-code-ide-remote-worktree--operation-snapshot operation))
         (targets (plist-get step :protected-targets))
         (tools (plist-get snapshot :tools))
         (arguments (list (number-to-string (plist-get step :step-id))
                          (alist-get 'zmx tools) (alist-get 'git tools)
                          (plist-get snapshot :repository))))
    (unless (and (or (consp targets) (eq (plist-get step :kind) 'native-prune)) (proper-list-p targets)
                 (cl-every #'claude-code-ide-zmx--valid-directory-p targets)
                 (cl-every #'claude-code-ide-zmx--valid-directory-p (cdr arguments)))
      (user-error "A protected step requires exact targets and remote Git/zmx paths"))
    (unless (and (plist-member snapshot :agents)
                 (stringp (plist-get snapshot :agent-inventory)))
      (user-error "A protected step requires a fresh validated Agent inventory"))
    (claude-code-ide-remote-worktree--assert-unprotected operation)
    (dolist (target targets)
      (let* ((entry (seq-find (lambda (item) (equal (plist-get item :path) target))
                              (plist-get snapshot :worktrees)))
             (head (plist-get entry :head))
             (branch (or (plist-get entry :branch) "")))
        (unless (and (eq (plist-get entry :exists) t)
                     (stringp head)
                     (string-match-p "\\`[0-9a-f]\\{40\\}\\(?:[0-9a-f]\\{24\\}\\)?\\'" head)
                     (claude-code-ide-remote-worktree--literal-p branch))
          (user-error "The protected Worktree has no verified Git identity: %s" target))
        (setq arguments (append arguments (list target branch head)))))
    (concat "  cci_protect "
            (mapconcat #'claude-code-ide-zmx--quote arguments " ")
            " || return \"$?\"")))

(defun claude-code-ide-remote-worktree--render-value (operation value)
  "Quote literal VALUE or a fixed owned-resource reference for OPERATION."
  (let ((root (claude-code-ide-remote-worktree--operation-receipt-directory operation)))
    (claude-code-ide-zmx--quote
     (pcase value
       (:resource root)
       (:runner (concat root "/runner.sh"))
       (:creation-helper (concat root "/created.sh"))
       (:attempt (claude-code-ide-remote-worktree--operation-attempt-id operation))
       (_ (unless (claude-code-ide-remote-worktree--literal-p value)
            (user-error "A Worktree step argument is not a literal string"))
          value)))))

(defun claude-code-ide-remote-worktree--render-ref-preconditions (operation step)
  "Render STEP's captured ref checks as one bounded read for OPERATION."
  (let* ((snapshot (claude-code-ide-remote-worktree--operation-snapshot operation))
         (conditions (seq-filter (lambda (condition) (eq (plist-get condition :kind) 'ref))
                                 (plist-get step :preconditions)))
         (command (when conditions
                    (mapconcat #'claude-code-ide-zmx--quote
                               (list (alist-get 'git (plist-get snapshot :tools))
                                     "--git-dir" (plist-get snapshot :repository)
                                     "show-ref" "--verify" "--hash") " ")))
         (name (format "cci_check_refs_%d" (plist-get step :step-id))))
    (when conditions
      (concat
       "  " name "() {\n"
       (mapconcat
        (lambda (condition)
          (concat "    status=0; actual=$(" command " "
                  (claude-code-ide-zmx--quote (plist-get condition :name))
                  " 2>/dev/null) || status=$?\n"
                  (if (plist-get condition :oid)
                      (concat "    [ \"$status\" = 0 ] && [ \"$actual\" = "
                              (claude-code-ide-zmx--quote (plist-get condition :oid)) " ] || return 1")
                    "    [ \"$status\" = 1 ] || return 1")))
        conditions "\n")
       "\n  }\n  cci_watchdog_run 30 " name " || return \"$?\""))))

(defun claude-code-ide-remote-worktree--render-plan (operation)
  "Validate and render OPERATION's complete, dependency-ordered step plan."
  (let ((steps (claude-code-ide-remote-worktree--operation-steps operation))
        (snapshot (claude-code-ide-remote-worktree--operation-snapshot operation))
        (options (claude-code-ide-remote-worktree--operation-options operation))
        (index 0)
        lines)
    (unless (consp steps)
      (user-error "A remote mutation requires a complete step plan"))
    (claude-code-ide-remote-worktree--conditions operation)
    (dolist (step steps)
      (cl-incf index)
      (unless (and (proper-list-p step) (zerop (% (length step) 2))
                   (eql (plist-get step :step-id) index)
                   (memq (plist-get step :kind)
                         claude-code-ide-remote-worktree--step-kinds)
                   (proper-list-p (plist-get step :argv))
                   (proper-list-p (plist-get step :requires))
                   (cl-every (lambda (dependency)
                               (and (integerp dependency) (> dependency 0)
                                    (< dependency index)))
                             (plist-get step :requires)))
        (user-error "The Worktree step plan has an invalid order or command"))
      (let ((fields step) seen)
        (while fields
          (let ((key (pop fields)))
            (pop fields)
            (unless (and (memq key '(:step-id :kind :cwd :program :argv :requires
                                              :protected-targets :preconditions :postconditions
                                              :merge-record :merge-cleanup :merge-target-override :prune-check))
                         (not (memq key seen)))
              (user-error "The Worktree step plan has an unsupported or duplicate field"))
            (push key seen))))
      (let* ((cwd (plist-get step :cwd))
             (program (plist-get step :program))
             (rendered-cwd
              (if (eq cwd :created)
                  (progn
                    (push "  cci_cwd=$(cci_created_directory) || return \"$?\"" lines)
                    "\"$cci_cwd\"")
                (unless (claude-code-ide-zmx--valid-directory-p cwd)
                  (user-error "A Worktree step requires an absolute remote directory"))
                (claude-code-ide-zmx--quote cwd))))
        (unless (or (eq program :runner)
                    (and (claude-code-ide-remote-worktree--literal-p program)
                         (not (string-empty-p program))
                         (not (string-prefix-p "-" program))))
          (user-error "A Worktree step has an invalid program"))
        (when-let* ((check (claude-code-ide-remote-worktree--render-ref-preconditions operation step)))
          (push check lines))
        (when (memq (plist-get step :kind) '(native-push backend-push))
          (unless (and (plist-get snapshot :publication-preview)
                       (plist-get snapshot :publication-argv))
            (user-error "Publication has no captured selection preview"))
          (push "  cci_watchdog_run 30 cci_publication_admission || return \"$?\"" lines))
        (if-let* ((cleanup (plist-get step :merge-cleanup)))
            (let* ((source (plist-get snapshot :worktree))
                   (branch (plist-get snapshot :branch))
                   (landing (plist-get cleanup :landing-step)))
              (unless (and (memq landing (plist-get step :requires))
                           (equal (plist-get step :protected-targets) (list source))
                           (equal (plist-get (nth (1- landing) steps) :merge-record)
                                  (list :source-ref (plist-get cleanup :source-ref)
                                        :target-ref (plist-get cleanup :target-ref))))
                (user-error "The cleanup has no matching landing dependency"))
              (push
               (concat "  cci_protect_cleanup "
                       (mapconcat
                        #'claude-code-ide-zmx--quote
                        (list (number-to-string index)
                              (alist-get 'zmx (plist-get snapshot :tools))
                              (alist-get 'git (plist-get snapshot :tools))
                              (plist-get snapshot :repository) source branch
                              (number-to-string landing)
                              (plist-get cleanup :source-ref)
                              (plist-get cleanup :target-ref)) " ")
                       " || return \"$?\"")
               lines))
          (when (or (memq (plist-get step :kind)
                          claude-code-ide-remote-worktree--protected-kinds)
                    (plist-get step :protected-targets))
            (push (claude-code-ide-remote-worktree--render-protection operation step) lines)))
        (when-let* ((check (plist-get step :prune-check)))
          (let ((path (plist-get check :path))
                (marker-path (plist-get check :landed-marker-path))
                (marker (plist-get check :landed-marker))
                (name (format "cci_prune_check_%d" index)))
            (unless (and (eq (plist-get step :kind) 'named-remove)
                         (eq (claude-code-ide-remote-worktree--operation-kind operation) 'prune)
                         (equal (plist-get step :protected-targets) (list path))
                         (equal (plist-get step :argv) (list "rm" (plist-get check :name)))
                         (claude-code-ide-zmx--valid-directory-p marker-path)
                         (stringp marker) (<= (length marker) 16384))
              (user-error "The prune step lacks its exact named landing evidence"))
            (push
             (concat
              "  " name "() {\n    gitdir=$("
              (mapconcat #'claude-code-ide-zmx--quote
                         (list (alist-get 'git (plist-get snapshot :tools)) "-C" path
                               "rev-parse" "--absolute-git-dir") " ")
              ") || return \"$?\"\n    marker=" (claude-code-ide-zmx--quote marker-path) "\n"
              "    [ \"$gitdir/" magit-lane-core-landed-marker-relpath "\" = \"$marker\" ] || return 1\n"
              "    [ -f \"$marker\" ] && [ ! -L \"$marker\" ] || return 1\n"
              "    [ \"$(wc -c < \"$marker\")\" -le 16384 ] || return 1\n"
              "    actual=$(base64 < \"$marker\" | tr -d '\\n') || return \"$?\"\n"
              "    [ \"$actual\" = " (claude-code-ide-zmx--quote (base64-encode-string marker t)) " ]\n"
              "  }\n  cci_watchdog_run 30 " name " || return \"$?\"")
             lines)))
        (push
         (format "  %s %d %s %s %s%s || return \"$?\""
                 (if (plist-get step :merge-target-override) "cci_step_merge_cleanup" "cci_step")
                 index (symbol-name (plist-get step :kind)) rendered-cwd
                 (if-let* ((target (plist-get step :merge-target-override)))
                     (progn
                       (unless (or (equal (concat "refs/heads/" target)
                                          (plist-get (plist-get step :merge-cleanup) :target-ref))
                                   (and (claude-code-ide-remote-worktree--operation-parent-attempt operation)
                                        (seq-some
                                         (lambda (condition)
                                           (and (eq (plist-get condition :kind) 'ref)
                                                (equal (plist-get condition :name) (concat "refs/heads/" target))
                                                (plist-get condition :oid)))
                                         (plist-get step :preconditions))))
                         (user-error "The cleanup override changes the approved target"))
                       (concat (claude-code-ide-zmx--quote target) " "))
                   "")
                 (mapconcat
                  (lambda (value)
                    (claude-code-ide-remote-worktree--render-value operation value))
                  (cons program (plist-get step :argv)) " "))
         lines)
        (when-let* ((record (plist-get step :merge-record)))
          (unless (and (eq (plist-get step :kind) 'backend-merge)
                       (equal (list :kind 'landing
                                    :source-ref (plist-get record :source-ref)
                                    :target-ref (plist-get record :target-ref))
                              (car (plist-get step :postconditions))))
            (user-error "The landing receipt does not match its approved postcondition"))
          (push
           (concat "  cci_record_merge "
                   (mapconcat
                    #'claude-code-ide-zmx--quote
                    (list (number-to-string index)
                          (alist-get 'git (plist-get snapshot :tools))
                          (plist-get snapshot :repository)
                          (plist-get record :source-ref)
                          (plist-get record :target-ref)) " ")
                   " || return \"$?\"")
           lines))))
    (concat
     "CCI_EXPECTED_REPOSITORY="
     (claude-code-ide-zmx--quote (or (plist-get snapshot :repository) "")) "\n"
     "CCI_EXPECTED_BRANCH="
     (claude-code-ide-zmx--quote
      (or (plist-get options :name) (plist-get snapshot :branch) "")) "\n"
     (when-let* ((preview (plist-get snapshot :publication-preview)))
       (concat
        "cci_publication_admission() {\n"
        "  export GIT_TERMINAL_PROMPT=0 GIT_ASKPASS=/bin/false SSH_ASKPASS=/bin/false SSH_ASKPASS_REQUIRE=never\n"
        "  cd " (claude-code-ide-zmx--quote (plist-get snapshot :worktree)) " || return \"$?\"\n"
        "  expected=$(printf '%s' "
        (claude-code-ide-zmx--quote (base64-encode-string (encode-coding-string preview 'utf-8-unix) t))
        " | base64 -d) || return \"$?\"\n"
        "  actual=$("
        (mapconcat
         #'claude-code-ide-zmx--quote
         (append (list (alist-get 'git (plist-get snapshot :tools))
                       "-c" "credential.interactive=false" "push" "--dry-run" "--porcelain" "--no-verify")
                 (cdr (plist-get snapshot :publication-argv))) " ")
        ") || return \"$?\"\n  [ \"$actual\" = \"$expected\" ]\n}\n"))
     "cci_plan() {\n" (mapconcat #'identity (nreverse lines) "\n")
     "\n}\ncci_plan\n")))

(defconst claude-code-ide-remote-worktree--stage-script
  (mapconcat
   #'identity
   '("set -eu"
     "umask 077"
     "set -C"
     "dir=$1; shift"
     "[ -d \"$dir\" ] && [ ! -L \"$dir\" ]"
     "attributes=$(stat -c '%u:%a' \"$dir\" 2>/dev/null || stat -f '%u:%Lp' \"$dir\")"
     "[ \"$attributes\" = \"$(id -u):700\" ]"
     "for file in runner.sh manifest plan.sh created.sh admitted-inventory; do printf '%s' \"$1\" | base64 -d > \"$dir/$file\"; shift; done"
     "if [ \"$#\" -gt 0 ]; then printf '%s' \"$1\" | base64 -d > \"$dir/bootstrap.sh\"; chmod 700 \"$dir/bootstrap.sh\"; fi"
     "chmod 700 \"$dir/runner.sh\" \"$dir/created.sh\""
     "printf 'staged\\n'")
   "; ")
  "Fixed private staging command.  Its arguments contain base64 data only.")

(defun claude-code-ide-remote-worktree--render-bootstrap (operation)
  "Render OPERATION's owned wrapper with literal remote launch arguments."
  (let* ((snapshot (claude-code-ide-remote-worktree--operation-snapshot operation))
         (launch (plist-get snapshot :launch))
         (attempt (claude-code-ide-remote-worktree--operation-attempt-id operation))
         (root (claude-code-ide-remote-worktree--operation-receipt-directory operation))
         (created (eq (claude-code-ide-remote-worktree--operation-kind operation) 'create)))
    (when launch
      (concat
       "#!/bin/sh\n[ \"$#\" = 1 ] && [ \"$1\" = "
       (claude-code-ide-zmx--quote attempt) " ] || exit 64\n/bin/sh "
       (mapconcat
        #'claude-code-ide-zmx--quote
        (append
         (list (concat root "/runner.sh") "agent" root attempt
               (alist-get 'git (plist-get snapshot :tools))
               (plist-get snapshot :repository)
               (if (eq (plist-get launch :directory) :created) "created" (plist-get launch :directory))
               (or (if created
                       (plist-get (claude-code-ide-remote-worktree--operation-options operation) :name)
                     (plist-get snapshot :branch)) "")
               (plist-get launch :zmx-name) (plist-get launch :executable))
         (plist-get launch :args))
        " ")
       "\n"))))

(defun claude-code-ide-remote-worktree--stage (operation callback)
  "Allocate and stage OPERATION once, then call CALLBACK with OPERATION."
  (unless (and (eq (claude-code-ide-remote-worktree--operation-state operation)
                   'awaiting-confirmation)
               (claude-code-ide-remote-worktree--approved-p operation)
               (not (claude-code-ide-remote-worktree--operation-request operation))
               (not (claude-code-ide-remote-worktree--operation-receipt-directory operation)))
    (user-error "The Worktree operation is not approved for private staging"))
  (let ((runner (with-temp-buffer
                  (insert-file-contents claude-code-ide-remote-worktree--runner-file)
                  (buffer-string))))
    (claude-code-ide-remote-worktree--control
     operation "worktree-allocation" "sh"
     '("-c" "umask 077; root=$(mktemp -d /tmp/cci-worktree.XXXXXXXXXX) || exit; cd \"$root\" || exit; pwd -P")
     (lambda (stdout)
       (unless (string-match "\\`\\(/\\(?:[^[:cntrl:]]*/\\)?cci-worktree\\.[A-Za-z0-9]+\\)\n\\'" stdout)
         (user-error "The host returned an invalid private operation directory"))
       (setf (claude-code-ide-remote-worktree--operation-receipt-directory operation)
             (match-string 1 stdout))
       (unless (claude-code-ide-remote-worktree--approved-p operation)
         (user-error "The approved operation changed before staging"))
       (let* ((root (claude-code-ide-remote-worktree--operation-receipt-directory operation))
              (attempt (claude-code-ide-remote-worktree--operation-attempt-id operation))
              (steps (claude-code-ide-remote-worktree--operation-steps operation))
              (manifest
               (format "protocol=cci-worktree-1\noperation=%s\nattempt=%s\nkind=%s\nsteps=%d\n"
                       (claude-code-ide-remote-worktree--operation-id operation)
                       attempt (claude-code-ide-remote-worktree--operation-kind operation)
                       (length steps))))
         (let* ((plan (claude-code-ide-remote-worktree--render-plan operation))
                (created
                 (concat "#!/bin/sh\nexec /bin/sh "
                         (claude-code-ide-zmx--quote (concat root "/runner.sh"))
                         " created " (claude-code-ide-zmx--quote root) " "
                         (claude-code-ide-zmx--quote attempt) "\n"))
                (payload
                 (mapcar (lambda (text)
                           (base64-encode-string (encode-coding-string text 'utf-8-unix) t))
                         (append
                          (list runner manifest plan created
                                (or (plist-get
                                     (claude-code-ide-remote-worktree--operation-snapshot operation)
                                     :agent-inventory)
                                    ""))
                          (when-let* ((bootstrap (claude-code-ide-remote-worktree--render-bootstrap operation)))
                            (list bootstrap))))))
           (when (> (apply #'+ (mapcar #'string-bytes payload)) 98304)
             (user-error "The Worktree plan exceeds the SSH staging limit"))
           (claude-code-ide-remote-worktree--control
            operation "worktree-staging" "sh"
            (append (list "-c" claude-code-ide-remote-worktree--stage-script
                          "cci-worktree-stage" root) payload)
            (lambda (_stdout) (funcall callback operation)))))))))

(defun claude-code-ide-remote-worktree--dispatch (operation callback)
  "Submit OPERATION's detached attempt and report acknowledgment to CALLBACK."
  (let* ((target (claude-code-ide-remote-worktree--operation-target operation))
         (root (claude-code-ide-remote-worktree--operation-receipt-directory operation)))
    (claude-code-ide-zmx--validate-host (plist-get target :host))
    (unless (and root
                 (eq (claude-code-ide-remote-worktree--operation-state operation)
                     'awaiting-confirmation)
                 (claude-code-ide-remote-worktree--approved-p operation))
      (user-error "The Worktree operation has no approved staged attempt"))
    ;; From this point, losing the request cannot prove that execution did not start.
    (claude-code-ide-remote-worktree--transition operation 'dispatching)
    (claude-code-ide-remote-worktree--control
     operation "worktree-dispatch" "/bin/sh"
     (list (concat root "/runner.sh") "dispatch" root
           (claude-code-ide-remote-worktree--operation-attempt-id operation))
     (lambda (_stdout)
       (claude-code-ide-remote-worktree--transition operation 'observing)
       (setf (claude-code-ide-remote-worktree--operation-observation operation) 'observing)
       (funcall callback operation))
     "/tmp" 4096)))

(defun claude-code-ide-remote-worktree--approval-signature (operation)
  "Bind approval to OPERATION's exact attempt, snapshot, options, and plan."
  (let ((print-length nil) (print-level nil) (print-circle t))
    (secure-hash
     'sha256
     (prin1-to-string
      (list (claude-code-ide-remote-worktree--operation-attempt-id operation)
            (claude-code-ide-remote-worktree--operation-kind operation)
            (claude-code-ide-remote-worktree--operation-target operation)
            (claude-code-ide-remote-worktree--operation-options operation)
            (claude-code-ide-remote-worktree--operation-snapshot operation)
            (claude-code-ide-remote-worktree--operation-steps operation))))))

(defun claude-code-ide-remote-worktree--approved-p (operation)
  "Return non-nil when OPERATION still matches its confirmed plan."
  (let ((approval (claude-code-ide-remote-worktree--operation-approval operation)))
    (and (stringp approval)
         (claude-code-ide-remote-worktree--launch-current-p operation)
         (equal approval (claude-code-ide-remote-worktree--approval-signature operation)))))

(defun claude-code-ide-remote-worktree--confirmation-prompts (operation)
  "Describe OPERATION's exact targets and separate authorization consequences."
  (let* ((target (claude-code-ide-remote-worktree--operation-target operation))
         (snapshot (claude-code-ide-remote-worktree--operation-snapshot operation))
         (options (claude-code-ide-remote-worktree--operation-options operation))
         (kind (claude-code-ide-remote-worktree--operation-kind operation))
         (step-kinds (mapcar (lambda (step) (plist-get step :kind))
                             (claude-code-ide-remote-worktree--operation-steps operation)))
         (backend (or (plist-get options :backend)
                      (plist-get (plist-get snapshot :settings) :backend)))
         (host (plist-get target :host))
         (repository (plist-get snapshot :repository))
         (source (or (plist-get snapshot :worktree) (plist-get target :directory)))
         (targets
          (if (eq kind 'prune)
              (plist-get snapshot :prune-candidates)
            (mapcar
             (lambda (path)
               (or (seq-find (lambda (entry) (equal (plist-get entry :path) path))
                             (plist-get snapshot :worktrees))
                   (list :path path :branch (and (equal path source)
                                                 (plist-get snapshot :branch)))))
             (delete-dups
              (cons source
                    (copy-sequence
                     (claude-code-ide-remote-worktree--protected-targets operation)))))))
         (print-length nil)
         (print-level nil)
         prompts)
    (when (claude-code-ide-remote-worktree--operation-parent-attempt operation)
      (push
       (format
        (concat "Host: %s\nRepository: %s\nTerminal predecessor: %s\nNew attempt: %s\n"
                "Retry only these unentered steps:\n%s\n"
                "Do not repeat completed steps. Approve this remaining work? ")
        host repository
        (claude-code-ide-remote-worktree--operation-parent-attempt operation)
        (claude-code-ide-remote-worktree--operation-attempt-id operation)
        (mapconcat
         (lambda (step)
           (format "  %d %s in %s: %S"
                   (plist-get step :step-id) (plist-get step :kind)
                   (plist-get step :cwd)
                   (cons (plist-get step :program) (plist-get step :argv))))
         (claude-code-ide-remote-worktree--operation-steps operation) "\n"))
       prompts))
    (when (and (eq kind 'create) (memq 'backend-create step-kinds))
      (push
       (format
        (concat "Host: %s\nRepository: %s\nBackend: %s\n"
                "Create branch and Worktree: %s\nBase: %s\n"
                "Destination: the selected backend's configured directory\n"
                "Agent: %s\nRun the backend's approved setup hooks and create this Worktree? ")
        host repository backend (plist-get options :name)
        (or (plist-get options :base) "the backend default")
        (if (plist-get options :create-only) "Do not start an Agent" "Start the configured remote Agent"))
       prompts))
    (when (memq kind '(remove move merge push prune))
      (when (and (eq kind 'push) (not (plist-get snapshot :publication)))
        (user-error "Resolve the publication destination and affected refs before confirmation"))
      (when (and (eq kind 'merge) (not (plist-get options :base)))
        (user-error "Resolve the merge destination before confirmation"))
      (when (and (eq kind 'prune) (not targets))
        (user-error "Resolve the exact prune candidate set before confirmation"))
      (push
       (format
        (concat "Host: %s\nRepository: %s\nAction: %s (%s)\n"
                "%s:\n  %s\nDestination/base: %s\n"
                "History: %s\nDirty files: %s\nLocal branch deletion: %s\n"
                "Cleanup: %s\nPublication: %s\nProceed? ")
        host repository kind backend
        (if (eq kind 'prune) "Prune candidates" "Worktrees")
        (mapconcat (lambda (entry)
                     (format "%s [branch: %s]" (plist-get entry :path)
                             (or (plist-get entry :branch) "detached")))
                   targets "\n  ")
        (or (plist-get options :destination) (plist-get options :base) "not changed")
        (pcase kind
          ('merge (if (memq 'backend-merge step-kinds)
                      "Run the confirmed backend merge and its commit, squash, or rebase preparation"
                    "Landing already completed. Do not repeat it"))
          ('push (if (eq backend 'lane)
                     "Rebase the source and create its note commit before publication"
                   "Publish the listed remote refs"))
          (_ "No merge or rebase"))
        (if (plist-get options :force) "Discard dirty work in the named removal targets"
          "No dirty-work deletion is authorized")
        (cond
         ((plist-get options :keep-branch) "Retain the branch")
         ((and (eq backend 'lane) (memq kind '(remove prune)))
          "Delete each named Lane branch, including unmerged history")
         ((plist-get options :force-delete) "Delete the named branch, including unmerged history")
         ((memq kind '(remove merge)) "Only the backend's safe merged-branch deletion is authorized")
         (t "No additional branch deletion"))
        (cond ((plist-get options :keep) "Keep the source Worktree")
              ((eq kind 'prune) "Only the exact displayed candidates")
              ((eq kind 'merge) "Only separately recorded and protected source removal")
              (t "Only the named action"))
        (if-let* ((publication (plist-get snapshot :publication)))
            (format "%s\nCaptured Git argv: %s\n%s"
                    (plist-get publication :destination)
                    (mapconcat #'claude-code-ide-zmx--quote
                               (plist-get snapshot :publication-argv) " ")
                    (mapconcat (lambda (change)
                                 (format "%s: %s" (cdr change) (car change)))
                               (plist-get publication :changes) "\n"))
          "Not applicable"))
       prompts))
    (when (and (eq backend 'lane) (plist-get options :initialize)
               (not (plist-get snapshot :lane-store)))
      (push (format "Host: %s\nRepository: %s\nWrite Lane instructions to %s/AGENTS.md? "
                    host repository (plist-get snapshot :main-worktree))
            prompts))
    (nreverse prompts)))

(defvar claude-code-ide-remote-worktree--confirmation-active nil
  "Non-nil while one Worktree confirmation owns the main-thread prompt.")

(defun claude-code-ide-remote-worktree--ask-approval (operation details)
  "Show complete DETAILS without clipping targets in OPERATION's prompt."
  (let ((buffer (generate-new-buffer "*Remote Worktree approval*"))
        window)
    (unwind-protect
        (progn
          (with-current-buffer buffer
            (setq default-directory temporary-file-directory)
            (insert "Remote Worktree approval\n\n" details "\n")
            (special-mode))
          (setq window
                (display-buffer-below-selected buffer '((window-height . fit-window-to-buffer))))
          (unless (window-live-p window)
            (user-error "No window is available for Worktree approval"))
          (and (yes-or-no-p
                (format "Approve %s on %s in %s? "
                        (claude-code-ide-remote-worktree--operation-kind operation)
                        (plist-get (claude-code-ide-remote-worktree--operation-target operation)
                                   :host)
                        (plist-get (claude-code-ide-remote-worktree--operation-snapshot operation)
                                   :repository)))
               (buffer-live-p buffer)
               (window-live-p window)
               (eq (window-buffer window) buffer)))
      (if (and (window-live-p window) (eq (window-buffer window) buffer))
          (quit-window t window)
        (when (buffer-live-p buffer) (kill-buffer buffer))))))

(defun claude-code-ide-remote-worktree--confirm-ready
    (operation callback attempt generation signature)
  "Ask for the captured OPERATION when no other confirmation owns input."
  (when (and (claude-code-ide-remote-worktree--current-p operation attempt generation)
             (eq (claude-code-ide-remote-worktree--operation-state operation)
                 'awaiting-confirmation))
    (if (or claude-code-ide-remote-worktree--confirmation-active
            (active-minibuffer-window))
        (setf (claude-code-ide-remote-worktree--operation-timer operation)
              (run-at-time 0.1 nil #'claude-code-ide-remote-worktree--confirm-ready
                           operation callback attempt generation signature))
      (setf (claude-code-ide-remote-worktree--operation-timer operation) nil)
      (let ((claude-code-ide-remote-worktree--confirmation-active t))
        (condition-case error-data
            (cl-flet
                ((validate ()
                   (claude-code-ide-zmx--validate-host
                    (plist-get (claude-code-ide-remote-worktree--operation-target operation) :host))
                   (unless (and
                            (claude-code-ide-remote-worktree--current-p operation attempt generation)
                            (claude-code-ide-remote-worktree--launch-current-p operation)
                            (equal signature
                                   (claude-code-ide-remote-worktree--approval-signature operation)))
                     (user-error "The operation changed during confirmation"))))
              (validate)
              (claude-code-ide-remote-worktree--assert-unprotected operation)
              (dolist (prompt (claude-code-ide-remote-worktree--confirmation-prompts operation))
                (unless (claude-code-ide-remote-worktree--ask-approval operation prompt)
                  (user-error "Confirmation declined"))
                (validate))
              (validate)
              (setf (claude-code-ide-remote-worktree--operation-approval operation) signature)
              (funcall callback operation))
          ((error quit)
           (when (and (claude-code-ide-remote-worktree--current-p operation attempt generation)
                      (eq (claude-code-ide-remote-worktree--operation-state operation)
                          'awaiting-confirmation))
             (claude-code-ide-remote-worktree--fail
              operation (error-message-string error-data)))))))))

(defun claude-code-ide-remote-worktree--confirm (operation callback)
  "Ask on the main thread, then call CALLBACK only for unchanged OPERATION."
  (claude-code-ide-remote-worktree--transition operation 'awaiting-confirmation)
  (setf (claude-code-ide-remote-worktree--operation-timer operation)
        (run-at-time
         0 nil #'claude-code-ide-remote-worktree--confirm-ready operation callback
         (claude-code-ide-remote-worktree--operation-attempt-id operation)
         (claude-code-ide-remote-worktree--operation-generation operation)
         (claude-code-ide-remote-worktree--approval-signature operation))))

(defun claude-code-ide-remote-worktree--prerequisites (operation)
  "Check OPERATION's captured tools and optional support without local fallback."
  (claude-code-ide-zmx--validate-host
   (plist-get (claude-code-ide-remote-worktree--operation-target operation) :host))
  (let* ((snapshot (claude-code-ide-remote-worktree--operation-snapshot operation))
         (options (claude-code-ide-remote-worktree--operation-options operation))
         (steps (claude-code-ide-remote-worktree--operation-steps operation))
         (kinds (mapcar (lambda (step) (plist-get step :kind)) steps))
         (backend (or (plist-get options :backend)
                      (plist-get (plist-get snapshot :settings) :backend)))
         (required '(git)))
    (when (or (and (eq (claude-code-ide-remote-worktree--operation-kind operation) 'open)
                   (not (plist-get options :view-only)))
              (memq 'bootstrap kinds)
              (claude-code-ide-remote-worktree--protection-required-p operation))
      (push 'zmx required))
    (when (seq-some (lambda (kind)
                      (memq kind '(backend-setup backend-create backend-merge
                                                 named-remove backend-push)))
                    kinds)
      (let ((feature (cdr (assq backend '((lane . magit-lane-core)
                                          (wt . magit-worktrunk-core))))))
        (unless (and feature (require feature nil t))
          (user-error "The selected Worktree backend package is unavailable: %s" backend)))
      (push backend required))
    (dolist (tool required)
      (unless (claude-code-ide-zmx--valid-directory-p
               (alist-get tool (plist-get snapshot :tools)))
        (user-error "The required remote tool is unavailable: %s" tool)))
    (dolist (step steps)
      (when (memq (plist-get step :kind)
                  '(backend-setup backend-create backend-merge named-remove
                                  backend-push native-push))
        (when (seq-some (lambda (argument)
                          (member argument '("-y" "--yes" "--no-verify"
                                             "--no-hooks" "--skip-hooks")))
                        (plist-get step :argv))
          (user-error "Remote Worktree steps cannot bypass repository hook approval"))))
    (when (or (plist-get options :create-only) (plist-get options :view-only))
      (unless (and (require 'claude-code-ide-remote-project nil t)
                   (claude-code-ide-remote-project-target-available-p))
        (user-error "This action requires compatible optional RPC and Magit support"))))
  operation)

(defun claude-code-ide-remote-worktree--admit (operation callback)
  "Check prerequisites, refresh protection, and confirm OPERATION before CALLBACK."
  (condition-case error-data
      (progn
        (claude-code-ide-remote-worktree--prerequisites operation)
        (if (or (claude-code-ide-remote-worktree--protection-required-p operation)
                (seq-some (lambda (step) (eq (plist-get step :kind) 'bootstrap))
                          (claude-code-ide-remote-worktree--operation-steps operation)))
            (claude-code-ide-remote-worktree--inventory
             operation
             (lambda (ready) (claude-code-ide-remote-worktree--confirm ready callback)))
          (claude-code-ide-remote-worktree--confirm operation callback)))
    (error (claude-code-ide-remote-worktree--fail
            operation (error-message-string error-data)))))

(defun claude-code-ide-remote-worktree--launch-spec (operation)
  "Capture validated host launch settings for OPERATION without remote I/O."
  (require 'claude-code-ide)
  (unless (equal (claude-code-ide-remote-worktree--operation-launch-selection operation)
                 (claude-code-ide-remote-worktree--launch-selection
                  (plist-get (claude-code-ide-remote-worktree--operation-target operation) :host)))
    (user-error "The selected remote Agent settings changed during preparation"))
  (let* ((host (plist-get (claude-code-ide-remote-worktree--operation-target operation) :host))
         (config (cdr (assoc host (default-value 'claude-code-ide-remote-launch-config))))
         (cli-type (claude-code-ide--cli-type-for-command
                    (default-value 'claude-code-ide-cli-path)))
         (executable (or (plist-get config :executable) (symbol-name cli-type)))
         (args (plist-get config :args))
         (fields config) seen)
    (unless (and (proper-list-p config) (zerop (% (length config) 2)))
      (user-error "The remote Agent override must be a property list"))
    (while fields
      (let ((key (pop fields)))
        (pop fields)
        (unless (and (memq key '(:executable :args)) (not (memq key seen)))
          (user-error "The remote Agent override contains an unknown or duplicate key"))
        (push key seen)))
    (unless (and (claude-code-ide-remote-worktree--literal-p executable)
                 (not (string-empty-p executable)) (not (string-prefix-p "-" executable))
                 (proper-list-p args)
                 (cl-every #'claude-code-ide-remote-worktree--literal-p args))
      (user-error "The remote Agent executable or argument list is invalid"))
    (list :cli-type cli-type :executable (copy-sequence executable)
          :args (copy-tree args)
          :zmx-name (concat "cci-worktree-" (claude-code-ide-remote-worktree--operation-attempt-id operation))
          :bootstrap-token (claude-code-ide-remote-worktree--operation-attempt-id operation))))

(defun claude-code-ide-remote-worktree--prepare-launch (operation callback)
  "Resolve OPERATION's remote Agent executable and append its owned bootstrap."
  (let* ((launch (claude-code-ide-remote-worktree--launch-spec operation))
         (snapshot (claude-code-ide-remote-worktree--operation-snapshot operation))
         (created (eq (claude-code-ide-remote-worktree--operation-kind operation) 'create)))
    (claude-code-ide-remote-worktree--control
     operation "worktree-agent-program" "/bin/sh"
     (list "-c" "set -eu; program=$(command -v \"$1\"); case \"$program\" in /*) [ -f \"$program\" ] && [ -x \"$program\" ]; printf '%s\\n' \"$program\";; *) exit 1;; esac"
           "cci-agent-program" (plist-get launch :executable))
     (lambda (stdout)
       (let ((program (string-remove-suffix "\n" stdout))
             (steps (claude-code-ide-remote-worktree--operation-steps operation)))
         (unless (claude-code-ide-zmx--valid-directory-p program)
           (user-error "The host did not resolve an absolute Agent executable"))
         (setq launch (plist-put launch :executable program)
               launch (plist-put launch :directory (if created :created (plist-get snapshot :worktree))))
         (setf (claude-code-ide-remote-worktree--operation-snapshot operation)
               (plist-put snapshot :launch launch)
               (claude-code-ide-remote-worktree--operation-steps operation)
               (append steps
                       (list (list :step-id (1+ (length steps)) :kind 'bootstrap
                                   :cwd (plist-get launch :directory) :program :runner
                                   :argv (list "bootstrap" :resource :attempt
                                               (alist-get 'zmx (plist-get snapshot :tools))
                                               (plist-get launch :zmx-name))
                                   :requires (and steps (list (length steps)))
                                   :preconditions (and created '((:kind creation)))
                                   :postconditions '((:kind bootstrap))))))
         (funcall callback operation))))))

(defun claude-code-ide-remote-worktree--display-current-p (operation)
  "Return non-nil for OPERATION's owned origin or its selected results view."
  (let* ((context (claude-code-ide-remote-worktree--operation-display-context operation))
         (window (plist-get context :window)))
    (and context
         (eq (plist-get context :frame) (selected-frame))
         (or (and (window-live-p window) (eq window (selected-window))
                  (eq (plist-get context :buffer) (window-buffer window)))
             (and (eq (window-buffer (selected-window))
                      claude-code-ide-remote-worktree--results-buffer)
                  (with-current-buffer claude-code-ide-remote-worktree--results-buffer
                    (equal claude-code-ide-remote-worktree--selected-operation
                           (claude-code-ide-remote-worktree--operation-id operation))))))))

(defun claude-code-ide-remote-worktree--prompt (operation callback)
  "Schedule CALLBACK for OPERATION without taking another prompt's input."
  (let ((attempt (claude-code-ide-remote-worktree--operation-attempt-id operation))
        (generation (claude-code-ide-remote-worktree--operation-generation operation)))
    (setf
     (claude-code-ide-remote-worktree--operation-timer operation)
     (run-at-time
      0.1 nil
      (lambda ()
        (when (claude-code-ide-remote-worktree--current-p operation attempt generation)
          (setf (claude-code-ide-remote-worktree--operation-timer operation) nil)
          (if (or (active-minibuffer-window) claude-code-ide-remote-worktree--confirmation-active)
              (claude-code-ide-remote-worktree--prompt operation callback)
            (condition-case error-data
                (funcall callback operation)
              ((error quit)
               (when (claude-code-ide-remote-worktree--current-p operation attempt generation)
                 (claude-code-ide-remote-worktree--fail operation (error-message-string error-data))))))))))))

(defun claude-code-ide-remote-worktree--attach (operation target)
  "Attach to OPERATION's verified TARGET without creating a replacement Agent."
  (require 'claude-code-ide)
  (let ((attempt (claude-code-ide-remote-worktree--operation-attempt-id operation))
        (generation (claude-code-ide-remote-worktree--operation-generation operation)))
    (claude-code-ide-remote-worktree--local-result operation :attachment '(:status attaching))
    (condition-case error-data
        (let ((session (claude-code-ide--attach-zmx-entry
                        (list :host (plist-get target :host) :name (plist-get target :name))
                        (plist-get target :directory) (symbol-name (plist-get target :cli-type))
                        (plist-get target :session-id)
                        (lambda ()
                          (and (claude-code-ide-remote-worktree--current-p operation attempt generation)
                               (claude-code-ide-remote-worktree--display-current-p operation))))))
          (when (claude-code-ide-remote-worktree--current-p operation attempt generation)
            (unless session (user-error "Another request owns this Agent attachment"))
            (claude-code-ide-remote-worktree--local-result
             operation :attachment
             (list :status 'completed :session-id (claude-code-ide-session-id session)))
            (when (claude-code-ide-remote-worktree--display-current-p operation)
              (claude-code-ide-manager-switch-to-session (claude-code-ide-session-id session)))))
      (error
       (when (claude-code-ide-remote-worktree--current-p operation attempt generation)
         (claude-code-ide-remote-worktree--local-result
          operation :attachment (list :status 'failed :error (error-message-string error-data))))))))

(defun claude-code-ide-remote-worktree--open-existing (operation name cli-type &optional session-id)
  "Retain NAME and CLI-TYPE for OPERATION, with optional remembered SESSION-ID."
  (let* ((snapshot (claude-code-ide-remote-worktree--operation-snapshot operation))
         (target (list :host (plist-get snapshot :host) :directory (plist-get snapshot :worktree)
                       :name name :cli-type cli-type :session-id session-id)))
    (unless (and name cli-type)
      (user-error "The remembered Agent lacks its name or type"))
    (setf (claude-code-ide-remote-worktree--operation-results operation)
          (list :outcome 'completed :attachment-target target
                :view-target (list :host (plist-get target :host) :directory (plist-get target :directory)))
          (claude-code-ide-remote-worktree--operation-observation operation) 'stopped)
    (claude-code-ide-remote-worktree--transition operation 'completed)
    (claude-code-ide-remote-worktree--finish operation)))

(defun claude-code-ide-remote-worktree--open-inventory (operation)
  "Choose an existing Agent from OPERATION's fresh inventory or prepare a launch."
  (let* ((snapshot (claude-code-ide-remote-worktree--operation-snapshot operation))
         (agents (plist-get snapshot :agents))
         (sibling (plist-get (claude-code-ide-remote-worktree--operation-options operation) :sibling))
         (matches (seq-filter
                   (lambda (agent) (equal (plist-get agent :worktree) (plist-get snapshot :worktree)))
                   agents)))
    (when (seq-some
           (lambda (agent)
             (and (plist-get agent :error)
                  (let ((path (or (plist-get agent :worktree) (plist-get agent :directory))))
                    (or (not (claude-code-ide-zmx--valid-directory-p path))
                        (string-prefix-p
                         (file-name-as-directory (plist-get snapshot :worktree))
                         (file-name-as-directory path))))))
           agents)
      (user-error "Resolve the unknown Agent identities before opening a Worktree"))
    (if (or sibling (not matches))
        (claude-code-ide-remote-worktree--prepare-launch
         operation #'claude-code-ide-remote-worktree--submit)
      (let* ((names (mapcar (lambda (agent) (plist-get agent :name)) matches))
             (name (if (cdr names)
                       (completing-read (format "Existing Agent on %s: " (plist-get snapshot :host))
                                        names nil t)
                     (car names)))
             (agent (seq-find (lambda (entry) (equal (plist-get entry :name) name)) matches)))
        (claude-code-ide-remote-worktree--open-existing operation name (plist-get agent :cli-type))))))

(defun claude-code-ide-remote-worktree--open-selected (operation)
  "Reuse or discover an Agent for OPERATION's selected canonical Worktree."
  (require 'claude-code-ide)
  (let* ((snapshot (claude-code-ide-remote-worktree--operation-snapshot operation))
         (host (plist-get snapshot :host))
         (directory (plist-get snapshot :worktree))
         (sibling (plist-get (claude-code-ide-remote-worktree--operation-options operation) :sibling))
         (session (and (not sibling) (claude-code-ide--preferred-session directory host))))
    (cl-labels
        ((discover ()
           (claude-code-ide-remote-worktree--inventory
            operation
            (lambda (ready)
              (claude-code-ide-remote-worktree--prompt
               ready #'claude-code-ide-remote-worktree--open-inventory))))
         (choose (items)
           (if (not items)
               (discover)
             (claude-code-ide-remote-worktree--prompt
              operation
              (lambda (ready)
                (let* ((names (mapcar #'claude-code-ide-manager-item-zmx-name items))
                       (name (if (cdr names)
                                 (completing-read (format "Remembered Agent on %s: " host) names nil t)
                               (car names)))
                       (item (seq-find (lambda (row) (equal name (claude-code-ide-manager-item-zmx-name row))) items)))
                  (claude-code-ide-remote-worktree--open-existing
                   ready name (claude-code-ide-manager-item-cli-type item)
                   (claude-code-ide-manager-item-session-key item))))))))
      (cond
       (session
        (claude-code-ide-remote-worktree--open-existing
         operation (claude-code-ide-session-zmx-name session) (claude-code-ide-session-cli-type session)
         (claude-code-ide-session-id session)))
       (sibling (discover))
       (t
        (unless (claude-code-ide-manager--scope-state-entry '(:type global))
          (claude-code-ide-manager--load-state))
        (let ((items (seq-filter (lambda (item) (equal host (claude-code-ide-manager-item-host item)))
                                 (claude-code-ide-manager--all-items))))
          (if (not items)
              (discover)
            (claude-code-ide-remote-worktree--metadata
             operation (mapcar #'claude-code-ide-manager-item-directory items)
             (lambda (records)
               (let (matches)
                 (cl-mapc
                  (lambda (item record)
                    ;; Unmatched rows still require fresh discovery before launch.
                    ;; A failed lookup at the selected target cannot authorize replacement.
                    (let ((path (claude-code-ide-manager-item-directory item)))
                      (when (and (eq (plist-get record :kind) 'error)
                                 (or (not (claude-code-ide-zmx--valid-directory-p path))
                                     (string-prefix-p (file-name-as-directory directory)
                                                      (file-name-as-directory path))))
                        (user-error "Resolve the remembered Agent directory before opening another Agent")))
                    (when (and (equal directory (plist-get record :worktree-path))
                               (equal (plist-get snapshot :repository) (plist-get record :common-dir)))
                      (push item matches)))
                  items records)
                 (choose (nreverse matches))))))))))))

(defun claude-code-ide-remote-worktree--open (operation)
  "Select an existing Worktree for OPERATION and preserve its exact host."
  (claude-code-ide-remote-worktree--prerequisites operation)
  (let* ((snapshot (claude-code-ide-remote-worktree--operation-snapshot operation))
         (options (claude-code-ide-remote-worktree--operation-options operation))
         (select (plist-get options :select))
         (name (plist-get options :name))
         (named (and name (seq-find
                           (lambda (row)
                             (equal name (alist-get (if (eq (plist-get snapshot :backend) 'lane) 'name 'branch) row)))
                           (plist-get snapshot :backend-entries))))
         (entries (seq-filter (lambda (entry)
                                (and (eq (plist-get entry :exists) t) (not (plist-get entry :bare))))
                              (plist-get snapshot :worktrees)))
         (paths (mapcar (lambda (entry) (plist-get entry :path)) entries))
         (directory (cond
                     ((plist-get options :main) (plist-get snapshot :main-worktree))
                     (name (and named (alist-get 'path named)))
                     (select
                      (if (cdr paths)
                          (completing-read (format "Worktree on %s: " (plist-get snapshot :host)) paths nil t)
                        (car paths)))
                     (t (plist-get snapshot :worktree))))
         (entry (seq-find (lambda (item) (equal directory (plist-get item :path))) entries)))
    (unless entry (user-error "No accessible Worktree matches the selected directory"))
    (setf (plist-get snapshot :worktree) directory
          (plist-get snapshot :branch) (plist-get entry :branch)
          (claude-code-ide-remote-worktree--operation-snapshot operation) snapshot)
    (if (plist-get options :view-only)
        (claude-code-ide-remote-worktree--complete-read
         operation (list :host (plist-get snapshot :host) :directory directory))
      (claude-code-ide-remote-worktree--open-selected operation))))

(defun claude-code-ide-remote-worktree--complete-read (operation &optional view-target)
  "Complete OPERATION's explicit read and retain its optional VIEW-TARGET."
  (setf (claude-code-ide-remote-worktree--operation-results operation)
        (list :outcome 'completed
              :snapshot (claude-code-ide-remote-worktree--operation-snapshot operation)
              :view-target view-target)
        (claude-code-ide-remote-worktree--operation-observation operation) 'stopped)
  (claude-code-ide-remote-worktree--transition operation 'completed)
  (claude-code-ide-remote-worktree--finish operation))

(defun claude-code-ide-remote-worktree--finish (operation)
  "Complete OPERATION's owned local actions or retain explicit deferred results."
  (let ((result (claude-code-ide-remote-worktree--operation-results operation))
        (owned (claude-code-ide-remote-worktree--display-current-p operation))
        (deferred '(:status deferred
                            :error "The local display no longer belongs to this operation. Use the retained recovery action.")))
    (cond
     ((plist-get result :attachment-target)
      (if owned
          (claude-code-ide-remote-worktree--attach operation (plist-get result :attachment-target))
        (claude-code-ide-remote-worktree--local-result operation :attachment deferred)))
     ((and (memq (plist-get result :outcome) '(completed partial confirmed-unfinished))
           (or (seq-some (lambda (key)
                           (plist-get (claude-code-ide-remote-worktree--operation-options operation) key))
                         '(:create-only :view-only :refresh))
               (plist-get (plist-get result :reconciliation) :origin-removed)
               (let ((origin (plist-get (claude-code-ide-remote-worktree--operation-snapshot operation)
                                        :origin-worktree)))
                 (and origin
                      (seq-some (lambda (entry) (equal origin (plist-get entry :path)))
                                (plist-get (plist-get result :reconciliation) :surviving)))))
           (plist-get result :view-target))
      (if owned
          (claude-code-ide-remote-worktree-recover-view
           (claude-code-ide-remote-worktree--operation-id operation) t)
        (claude-code-ide-remote-worktree--local-result operation :view deferred)))))
  (claude-code-ide-remote-worktree--release operation))

(defun claude-code-ide-remote-worktree--submit (operation)
  "Admit and submit OPERATION's complete plan, then observe its receipts."
  (claude-code-ide-remote-worktree--admit
   operation
   (lambda (approved)
     (claude-code-ide-remote-worktree--stage
      approved
      (lambda (staged)
        (claude-code-ide-remote-worktree--dispatch
         staged (lambda (submitted)
                  (claude-code-ide-remote-worktree--observe
                   submitted #'claude-code-ide-remote-worktree--finish))))))))

(defun claude-code-ide-remote-worktree--prepare-create (operation callback)
  "Validate OPERATION's new name and conflicts before any backend setup."
  (let* ((options (claude-code-ide-remote-worktree--operation-options operation))
         (snapshot (claude-code-ide-remote-worktree--operation-snapshot operation))
         (backend (or (plist-get options :backend) (plist-get (plist-get snapshot :settings) :backend)))
         (name (plist-get options :name))
         (base (plist-get options :base)))
    (claude-code-ide-remote-worktree--check-backend-options backend options)
    (when (and (eq backend 'lane)
               (not (plist-member options :initialize))
               (claude-code-ide-remote-worktree--operation-lane-initialization operation))
      (setf (claude-code-ide-remote-worktree--operation-options operation)
            (setq options (plist-put options :initialize t))))
    (unless (and (claude-code-ide-remote-worktree--literal-p name)
                 (not (string-empty-p (string-trim name)))
                 (not (string-prefix-p "/" name)) (not (string-prefix-p "-" name))
                 (not (seq-some (lambda (part) (member part '("" "." ".."))) (split-string name "/"))))
      (user-error "The new Worktree name is invalid"))
    (let ((ref (concat "refs/heads/" name)))
      (when (seq-some (lambda (entry)
                        (or (equal ref (car entry))
                            (string-prefix-p (concat ref "/") (car entry))
                            (string-prefix-p (concat (car entry) "/") ref)))
                      (plist-get snapshot :refs))
        (user-error "The requested branch conflicts with an existing branch: %s" name)))
    (claude-code-ide-remote-worktree--control
     operation "worktree-create-validation" "/bin/sh"
     (list "-c"
           (mapconcat
            #'identity
            '("set -eu"
              "git=$1; name=$2; main=$3; backend=$4; base=$5"
              "checked=$(\"$git\" check-ref-format --branch \"$name\"); [ \"$checked\" = \"$name\" ]"
              "status=0; \"$git\" show-ref --verify --quiet \"refs/heads/$name\" || status=$?"
              "[ \"$status\" = 1 ] || { echo 'The requested branch exists or cannot be checked' >&2; exit 1; }"
              "if [ -n \"$base\" ]; then \"$git\" rev-parse --verify --end-of-options \"$base^{commit}\" >/dev/null; fi"
              "if [ \"$backend\" = lane ]; then parent=\"$main/.lane/trees\"; suffix=; while [ ! -e \"$parent\" ] && [ ! -L \"$parent\" ]; do suffix=\"/$(basename \"$parent\")$suffix\"; parent=$(dirname \"$parent\"); done; root=\"$(cd \"$parent\" && pwd -P)$suffix\"; target=\"$root/$name\"; [ ! -e \"$target\" ] && [ ! -L \"$target\" ] || { echo 'The requested Lane destination is occupied' >&2; exit 1; }; printf '%s\\n' \"$root\"; else printf '\\n'; fi")
            "; ")
           "cci-create-validation" (alist-get 'git (plist-get snapshot :tools))
           name (plist-get snapshot :main-worktree) (symbol-name backend) (or base ""))
     (lambda (stdout)
       (when (eq backend 'lane)
         (let ((root (string-remove-suffix "\n" stdout)))
           (unless (claude-code-ide-zmx--valid-directory-p root)
             (user-error "The host did not resolve the Lane trees root"))
           (setf (claude-code-ide-remote-worktree--operation-snapshot operation)
                 (plist-put snapshot :lane-trees-root root))))
       (funcall callback operation)))))

(defun claude-code-ide-remote-worktree--wt-merge-settings (report)
  "Read effective merge flags from Worktrunk's parsed configuration REPORT."
  (let* ((user (gethash "user" report))
         (case-fold-search nil)
         (config (gethash "config" user))
         (project (gethash "identifier" (gethash "project" report)))
         (projects (and (hash-table-p config) (gethash "projects" config)))
         (merge (and (hash-table-p config) (gethash "merge" config)))
         (remove (if (hash-table-p merge) (gethash "remove" merge t) t))
         (verify (if (hash-table-p merge) (gethash "verify" merge t) t))
         matches)
    (unless (hash-table-p config)
      (user-error "Worktrunk did not expose its merged user configuration"))
    (unless (or (null project) (claude-code-ide-remote-worktree--literal-p project))
      (user-error "Worktrunk returned an invalid project identifier"))
    (when (and (stringp project) (hash-table-p projects))
      (maphash
       (lambda (pattern value)
         (when (string-match-p
                (concat "\\`" (mapconcat #'regexp-quote (split-string pattern "\\*" nil) ".*") "\\'")
                project)
           (push (list (length (string-replace "*" "" pattern))
                       (if (string-match-p "\\*" pattern) 0 1) pattern value)
                 matches)))
       projects)
      (dolist (match (sort matches (lambda (left right)
                                     (cond
                                      ((/= (car left) (car right)) (< (car left) (car right)))
                                      ((/= (cadr left) (cadr right)) (< (cadr left) (cadr right)))
                                      (t (string< (nth 2 left) (nth 2 right)))))))
        (let ((override (gethash "merge" (nth 3 match))))
          (when (hash-table-p override)
            (setq remove (gethash "remove" override remove)
                  verify (gethash "verify" override verify))))))
    (unless (and (memq remove '(t :false)) (memq verify '(t :false)))
      (user-error "Worktrunk returned invalid merge flags"))
    (unless (eq verify t)
      (user-error "The remote Worktrunk configuration disables merge hooks"))
    (list :keep (eq remove :false))))

(defun claude-code-ide-remote-worktree--prepare-merge (operation callback)
  "Resolve OPERATION's exact merge target and effective cleanup settings."
  (let* ((snapshot (claude-code-ide-remote-worktree--operation-snapshot operation))
         (options (claude-code-ide-remote-worktree--operation-options operation))
         (backend (plist-get snapshot :backend))
         (git (alist-get 'git (plist-get snapshot :tools))))
    (cl-labels
        ((finish (settings)
           (setf (plist-get settings :keep) (or (plist-get options :keep) (plist-get settings :keep))
                 (plist-get snapshot :merge-settings) settings
                 (claude-code-ide-remote-worktree--operation-snapshot operation) snapshot
                 (claude-code-ide-remote-worktree--operation-options operation) options)
           (funcall callback operation))
         (read-settings (&optional empty-user)
           (unless (claude-code-ide-zmx--valid-directory-p (alist-get 'wt (plist-get snapshot :tools)))
             (user-error "The required remote tool is unavailable: wt"))
           (claude-code-ide-remote-worktree--control
            operation "worktree-merge-settings" "/bin/sh"
            (append
             (list "-c"
                   "set -eu; default=$1; shift; if [ -n \"$default\" ]; then n=${GIT_CONFIG_COUNT:-0}; case \"$n\" in *[!0-9]*) exit 1;; esac; while [ \"${n#0}\" != \"$n\" ]; do n=${n#0}; done; n=${n:-0}; exec env \"GIT_CONFIG_KEY_$n=worktrunk.default-branch\" \"GIT_CONFIG_VALUE_$n=$default\" \"GIT_CONFIG_COUNT=$((n+1))\" \"$@\"; fi; exec \"$@\""
                   "cci-read-merge-settings" (or (plist-get snapshot :default-branch) "")
                   (alist-get 'wt (plist-get snapshot :tools)))
             (when empty-user '("--config" "/dev/null")) '("config" "show" "--format=json"))
            (lambda (stdout)
              (let ((report (json-parse-string stdout :object-type 'hash-table :array-type 'list
                                               :null-object nil :false-object :false)))
                (if (and (not empty-user) (eq (gethash "exists" (gethash "user" report)) :false))
                    (read-settings t)
                  (finish (claude-code-ide-remote-worktree--wt-merge-settings report)))))
            (plist-get snapshot :worktree))))
      (claude-code-ide-remote-worktree--control
       operation "worktree-merge-target" "/bin/sh"
       (list "-c"
             (mapconcat
              #'identity
              '("set -eu;"
                "git=$1; backend=$2; branch=$3; base=$4;"
                "default=;"
                "if [ \"$backend\" = wt ]; then"
                " default=$(\"$git\" config --get worktrunk.default-branch || :); default=$(printf '%s' \"$default\" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//');"
                " if [ -z \"$default\" ]; then"
                "  remote=$(\"$git\" config --get checkout.defaultRemote || :);"
                "  if [ -z \"$remote\" ] || [ -z \"$(\"$git\" config --get \"remote.$remote.url\" || :)\" ]; then remote=$(\"$git\" config --name-only --get-regexp '^remote\\..*\\.url$' | LC_ALL=C sort | sed -n '1{s/^remote\\.//;s/\\.url$//;p;}'); fi;"
                "  if [ -n \"$remote\" ]; then"
                "   default=$(\"$git\" symbolic-ref --quiet --short \"refs/remotes/$remote/HEAD\" 2>/dev/null || :); default=${default#\"$remote\"/};"
                "   if [ -z \"$default\" ]; then default=$(\"$git\" ls-remote --symref -- \"$remote\" HEAD 2>/dev/null | sed -n 's/^ref: refs\\/heads\\/\\(.*\\)[[:space:]]HEAD$/\\1/p'); fi;"
                "  fi;"
                " fi;"
                " if [ -z \"$default\" ]; then"
                "  branches=$(\"$git\" for-each-ref --format='%(refname:short)' refs/heads); set -f; set -- $branches;"
                "  if [ \"$#\" = 1 ]; then default=$1; elif [ \"$#\" = 0 ] || [ \"$(\"$git\" rev-parse --is-bare-repository)\" = true ]; then default=$(\"$git\" symbolic-ref --quiet --short HEAD || :); fi;"
                "  if [ -z \"$default\" ]; then candidate=$(\"$git\" config --get init.defaultBranch || :); if [ -n \"$candidate\" ] && \"$git\" show-ref --verify --quiet \"refs/heads/$candidate\"; then default=$candidate; fi; fi;"
                "  if [ -z \"$default\" ]; then for candidate in main master develop trunk; do if \"$git\" show-ref --verify --quiet \"refs/heads/$candidate\"; then default=$candidate; break; fi; done; fi;"
                " fi;"
                "else"
                " origin=$(\"$git\" symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null || :); origin=${origin#origin/};"
                " for candidate in \"$origin\" main master trunk; do if [ -n \"$candidate\" ] && \"$git\" show-ref --verify --quiet \"refs/heads/$candidate\"; then default=$candidate; break; fi; done;"
                " if [ -z \"$default\" ]; then default=$(\"$git\" symbolic-ref --quiet --short HEAD); fi;"
                " if [ -z \"$base\" ]; then base=$(\"$git\" config --get \"lane.$branch.base\" || :); if [ -n \"$base\" ] && ! \"$git\" rev-parse --verify --quiet --end-of-options \"$base^{commit}\" >/dev/null; then base=; fi; fi;"
                "fi;"
                "base=${base:-$default}; base=${base#refs/heads/};"
                "\"$git\" show-ref --verify --quiet \"refs/heads/$base\";"
                "printf '%s\\000%s\\000' \"$default\" \"$base\"")
              " ")
             "cci-merge-target" git (symbol-name backend) (plist-get snapshot :branch)
             (or (plist-get options :base) ""))
       (lambda (stdout)
         (let* ((fields (split-string stdout (string 0)))
                (default (car fields)) (base (cadr fields))
                (oid (cdr (assoc (concat "refs/heads/" base) (plist-get snapshot :refs))))
                (target (seq-find (lambda (entry) (equal (plist-get entry :branch) base))
                                  (plist-get snapshot :worktrees))))
           (unless (and (= (length fields) 3) (equal (nth 2 fields) "") oid
                        (claude-code-ide-remote-worktree--literal-p default)
                        (claude-code-ide-remote-worktree--literal-p base))
             (user-error "The merge destination has no captured branch identity"))
           (setf (plist-get options :base) base
                 (plist-get snapshot :default-branch) (unless (string-empty-p default) default)
                 (plist-get snapshot :merge-target)
                 (or target (list :branch base :head oid)))
           (if (eq backend 'lane) (finish nil) (read-settings))))
       (plist-get snapshot :main-worktree)))))

(defun claude-code-ide-remote-worktree--publication-preview (stdout refs)
  "Resolve Git porcelain STDOUT into one publication destination and exact REFS."
  (let (destination selected changes)
    (dolist (line (split-string stdout "\n" t))
      (cond
       ((string-prefix-p "To " line)
        (when destination (user-error "Publication has more than one destination"))
        (setq destination (substring line 3)))
       ((string-match "\\`[ =*+!-]\t\\([^:\t]*\\):\\(refs/[^\t]+\\)\t" line)
        (let ((source (match-string 1 line)) (target (match-string 2 line)))
          (when (or (eq (aref line 0) ?!) (assoc target selected))
            (user-error "Git refused or repeated a publication ref"))
          (unless (or (string-empty-p source) (assoc source refs))
            (user-error "The publication source is not a captured full ref: %s" source))
          (push (cons target (unless (string-empty-p source) source)) selected)
          (push (cons target (pcase (aref line 0)
                               (?+ "Rewrite remote history")
                               (?- "Delete remote ref")
                               (?* "Create remote ref")
                               (?= "Leave remote ref unchanged")
                               (_ "Fast-forward remote ref")))
                changes)))
       ((or (equal line "Done")
            (string-match-p "\\`Would set upstream of '.*' to '.*' of '.*'\\'" line)))
       (t (user-error "Git returned an unsupported publication preview"))))
    (unless (and destination selected
                 (claude-code-ide-remote-worktree--literal-p destination)
                 (not (string-prefix-p "-" destination)))
      (user-error "Git did not resolve the publication destination and refs"))
    (list :destination destination :refs (nreverse selected)
          :changes (nreverse changes))))

(defun claude-code-ide-remote-worktree--prepare-publication (operation callback)
  "Resolve OPERATION's native publication selection with Git's read-only preview."
  (let* ((snapshot (claude-code-ide-remote-worktree--operation-snapshot operation))
         (options (claude-code-ide-remote-worktree--operation-options operation))
         (native (plist-get options :native-argv))
         (git (alist-get 'git (plist-get snapshot :tools))))
    (cl-labels
        ((preview (argv)
           (unless (and (equal (car argv) "push")
                        (cl-every #'claude-code-ide-remote-worktree--literal-p argv)
                        (not (seq-some
                              (lambda (arg)
                                (or (member arg '("--mirror" "--no-verify" "--dry-run" "--porcelain"))
                                    (string-prefix-p "--receive-pack" arg)
                                    (string-prefix-p "--exec" arg)))
                              argv)))
             (user-error "The native publication command has an unsupported shape"))
           (claude-code-ide-remote-worktree--control
            operation "worktree-publication-preview" git
            (append '("-c" "credential.interactive=false" "push" "--dry-run" "--porcelain" "--no-verify")
                    (cdr argv))
            (lambda (stdout)
              (setf (plist-get snapshot :publication)
                    (claude-code-ide-remote-worktree--publication-preview stdout (plist-get snapshot :refs))
                    (plist-get snapshot :publication-argv) argv
                    (plist-get snapshot :publication-preview) stdout
                    (claude-code-ide-remote-worktree--operation-snapshot operation) snapshot)
              (funcall callback operation))
            (plist-get snapshot :worktree))))
      (if native
          (preview native)
        (unless (eq (plist-get snapshot :backend) 'lane)
          (user-error "Worktrunk publication requires a captured native Magit command"))
        (claude-code-ide-remote-worktree--control
         operation "worktree-lane-publication" "/bin/sh"
         (list "-c"
               "set -eu; upstream=$(\"$1\" rev-parse --abbrev-ref --symbolic-full-name '@{upstream}' 2>/dev/null || :); case \"$upstream\" in */*) printf '%s\\n' \"${upstream%%/*}\";; *) \"$1\" config --get remote.origin.url >/dev/null; printf 'origin\\n';; esac"
               "cci-lane-publication" git)
         (lambda (stdout)
           (let ((remote (string-remove-suffix "\n" stdout)))
             (unless (and (claude-code-ide-remote-worktree--literal-p remote)
                          (not (string-empty-p remote)) (not (string-prefix-p "-" remote)))
               (user-error "Lane has no valid publication remote"))
             (preview (list "push" "--force-with-lease" "--force-if-includes" "-u"
                            remote (plist-get snapshot :branch)))))
         (plist-get snapshot :worktree))))))

(defun claude-code-ide-remote-worktree--prepare-move (operation callback)
  "Resolve native movement's actual destination before OPERATION confirmation."
  (let* ((snapshot (claude-code-ide-remote-worktree--operation-snapshot operation))
         (options (claude-code-ide-remote-worktree--operation-options operation))
         (argv (plist-get options :native-argv))
         (source (plist-get snapshot :worktree))
         (destination (nth 3 argv)))
    (unless (and (eq (plist-get snapshot :backend) 'wt)
                 (= (length argv) 4) (equal (seq-take argv 2) '("worktree" "move"))
                 (equal (directory-file-name (nth 2 argv)) source)
                 (claude-code-ide-zmx--valid-directory-p destination)
                 (not (equal source (plist-get snapshot :main-worktree)))
                 (not (string-prefix-p (concat (plist-get snapshot :main-worktree) "/.lane/trees/") source)))
      (user-error "Native movement requires a captured non-primary Worktrunk Worktree"))
    (claude-code-ide-remote-worktree--control
     operation "worktree-move-destination" "/bin/sh"
     (list "-c"
           "set -eu; source=$1; destination=$2; lane=\"$3/.lane/trees\"; if [ -d \"$lane\" ]; then lane=$(cd \"$lane\" && pwd -P); case \"$source\" in \"$lane\"/*) echo 'Lane Worktrees cannot move' >&2; exit 1;; esac; fi; if [ -d \"$destination\" ]; then destination=\"$destination/$(basename \"$source\")\"; fi; parent=$(dirname \"$destination\"); name=$(basename \"$destination\"); parent=$(cd \"$parent\" && pwd -P); destination=\"$parent/$name\"; [ ! -e \"$destination\" ] && [ ! -L \"$destination\" ]; printf '%s\\n' \"$destination\""
           "cci-move-destination" source destination (plist-get snapshot :main-worktree))
     (lambda (stdout)
       (let ((resolved (string-remove-suffix "\n" stdout)))
         (unless (claude-code-ide-zmx--valid-directory-p resolved)
           (user-error "The native destination has no canonical remote path"))
         (setf (plist-get options :destination) resolved
               (claude-code-ide-remote-worktree--operation-options operation) options)
         (funcall callback operation)))
     (plist-get snapshot :main-worktree))))

(defun claude-code-ide-remote-worktree--native-plan (snapshot action options)
  "Build the fixed plan for captured native ACTION using SNAPSHOT and OPTIONS."
  (let* ((source (plist-get snapshot :worktree))
         (branch (plist-get snapshot :branch))
         (argv (plist-get options :native-argv))
         (entry (seq-find (lambda (item) (equal (plist-get item :path) source))
                          (plist-get snapshot :worktrees)))
         (head (plist-get entry :head))
         (publication (plist-get snapshot :publication))
         (destination (plist-get options :destination)))
    (unless (and (memq action '(move push)) entry argv)
      (user-error "The native command has no captured Worktree identity"))
    (list
     (list :step-id 1 :kind (if (eq action 'move) 'native-move 'native-push)
           :cwd (if (eq action 'move) (plist-get snapshot :main-worktree) source)
           :program (alist-get 'git (plist-get snapshot :tools)) :argv argv :requires nil
           :protected-targets
           (delete-dups
            (cons source
                  (when (eq action 'push)
                    (mapcar
                     (lambda (item) (plist-get item :path))
                     (seq-filter
                      (lambda (item)
                        (member (concat "refs/heads/" (or (plist-get item :branch) ""))
                                (mapcar #'cdr (plist-get publication :refs))))
                      (plist-get snapshot :worktrees))))))
           :preconditions
           (cons (list :kind 'worktree :path source :branch branch :head head)
                 (when (eq action 'push)
                   (mapcar (lambda (ref)
                             (list :kind 'ref :name ref :oid (cdr (assoc ref (plist-get snapshot :refs)))))
                           (delete-dups (delq nil (mapcar #'cdr (plist-get publication :refs)))))))
           :postconditions
           (if (eq action 'move)
               (list (list :kind 'worktree :path source :absent t)
                     (list :kind 'directory :path source :exists nil)
                     (list :kind 'worktree :path destination :branch branch :head head))
             (list (list :kind 'publication :destination (plist-get publication :destination)
                         :refs (mapcar
                                (lambda (ref)
                                  (cons (car ref) (cdr (assoc (cdr ref) (plist-get snapshot :refs)))))
                                (plist-get publication :refs)))))))))

(defun claude-code-ide-remote-worktree--prepare-lane-prune (operation callback)
  "Read landed Lane candidates without the fetch hidden in Lane's prune preview."
  (let* ((snapshot (claude-code-ide-remote-worktree--operation-snapshot operation))
         (entries (seq-filter
                   (lambda (entry) (and (equal (alist-get 'state entry) "landed")
                                        (eq (alist-get 'pending_notes entry) 0)))
                   (plist-get snapshot :backend-entries))))
    (if (not entries)
        (progn
          (setf (plist-get snapshot :prune-candidates) nil
                (claude-code-ide-remote-worktree--operation-snapshot operation) snapshot)
          (funcall callback operation))
      (claude-code-ide-remote-worktree--control
       operation "worktree-prune-candidates" "/bin/sh"
       (append
        (list "-c"
              (mapconcat
               #'identity
               '("set -eu;"
                 "git=$1; rel=$2; shift 2;"
                 "for path do"
                 " gitdir=$(\"$git\" -C \"$path\" rev-parse --absolute-git-dir); marker=\"$gitdir/$rel\";"
                 " if [ ! -f \"$marker\" ] || [ -L \"$marker\" ]; then printf '\\000\\000'; continue; fi;"
                 " size=$(wc -c < \"$marker\"); [ \"$size\" -le 16384 ];"
                 " status=$(\"$git\" -C \"$path\" status --porcelain); changes=$(printf '%s\\n' \"$status\" | sed '/\\.lane\\/memory/d');"
                 " if [ -n \"$changes\" ]; then printf '\\000\\000'; continue; fi;"
                 " IFS=' ' read -r id stamp tip extra < \"$marker\" || exit 1;"
                 " if [ -n \"$tip\" ]; then case \"$tip\" in *[!0-9a-f]*) exit 1;; esac; case ${#tip} in 40|64) :;; *) exit 1;; esac; after=$(\"$git\" -C \"$path\" rev-list --count \"$tip..HEAD\"); if [ \"$after\" != 0 ]; then printf '\\000\\000'; continue; fi; fi;"
                 " printf '%s\\000' \"$marker\"; base64 < \"$marker\" | tr -d '\\n'; printf '\\000';"
                 "done")
               " ")
              "cci-lane-prune-candidates" (alist-get 'git (plist-get snapshot :tools))
              magit-lane-core-landed-marker-relpath)
        (mapcar (lambda (entry) (alist-get 'path entry)) entries))
       (lambda (stdout)
         (unless (string-suffix-p (string 0) stdout)
           (user-error "The prune candidate read has no final delimiter"))
         (let ((fields (split-string (substring stdout 0 -1) (string 0))) candidates)
           (unless (= (length fields) (* 2 (length entries)))
             (user-error "The prune candidate read has incomplete identities"))
           (dolist (entry entries)
             (let* ((marker-path (pop fields)) (encoded (pop fields))
                    (path (alist-get 'path entry))
                    (identity (seq-find (lambda (item) (equal (plist-get item :path) path))
                                        (plist-get snapshot :worktrees))))
               (unless (string-empty-p marker-path)
                 (unless (and identity (claude-code-ide-zmx--valid-directory-p marker-path)
                              (string-suffix-p (concat "/" magit-lane-core-landed-marker-relpath) marker-path))
                   (user-error "A prune candidate has an invalid landing marker identity"))
                 (let ((marker (base64-decode-string encoded)))
                   (unless (and (equal encoded (base64-encode-string marker t))
                                (<= (length marker) 16384))
                     (user-error "A prune candidate has an invalid landing marker"))
                   (push (append (list :name (alist-get 'name entry)
                                       :landed-marker-path marker-path :landed-marker marker)
                                 identity)
                         candidates)))))
           (setf (plist-get snapshot :prune-candidates) (nreverse candidates)
                 (claude-code-ide-remote-worktree--operation-snapshot operation) snapshot)
           (funcall callback operation)))
       (plist-get snapshot :main-worktree)))))

(defun claude-code-ide-remote-worktree--prepare-mutation (operation callback)
  "Resolve OPERATION's selected backend targets before building its closed plan."
  (let* ((snapshot (claude-code-ide-remote-worktree--operation-snapshot operation))
         (options (claude-code-ide-remote-worktree--operation-options operation))
         (action (claude-code-ide-remote-worktree--operation-kind operation))
         (backend (plist-get snapshot :backend))
         (entries (plist-get snapshot :backend-entries))
         (name (plist-get options :name))
         (selected
          (seq-find
           (lambda (entry)
             (if name
                 (equal name (alist-get (if (eq backend 'lane) 'name 'branch) entry))
               (equal (plist-get snapshot :worktree) (alist-get 'path entry))))
           entries)))
    (when (and (memq action '(remove merge push)) (not (plist-get options :native-argv)))
      (unless selected
        (user-error "The selected Worktree is not a current member of this backend"))
      (setf (plist-get snapshot :worktree) (alist-get 'path selected)
            (plist-get snapshot :branch) (alist-get 'branch selected)
            (plist-get options :name) (alist-get (if (eq backend 'lane) 'name 'branch) selected)
            (claude-code-ide-remote-worktree--operation-options operation) options
            (claude-code-ide-remote-worktree--operation-snapshot operation) snapshot))
    (pcase action
      ('prune
       (if (eq backend 'wt)
           (progn
             (setf (plist-get snapshot :prune-candidates)
                   (seq-filter (lambda (entry) (plist-get entry :prunable))
                               (plist-get snapshot :worktrees))
                   (claude-code-ide-remote-worktree--operation-snapshot operation) snapshot)
             (funcall callback operation))
         (claude-code-ide-remote-worktree--prepare-lane-prune operation callback)))
      ('move
       (claude-code-ide-remote-worktree--prepare-move operation callback))
      ('merge
       (claude-code-ide-remote-worktree--prepare-merge operation callback))
      ('push
       (claude-code-ide-remote-worktree--prepare-publication operation callback))
      (_ (funcall callback operation)))))

(defun claude-code-ide-remote-worktree--plan-operation (operation)
  "Build OPERATION's backend steps and submit its complete launch intent."
  (let* ((snapshot (claude-code-ide-remote-worktree--operation-snapshot operation))
         (action (claude-code-ide-remote-worktree--operation-kind operation))
         (options (claude-code-ide-remote-worktree--operation-options operation))
         (backend (or (plist-get options :backend) (plist-get (plist-get snapshot :settings) :backend)))
         (feature (cdr (assq backend '((lane . magit-lane-core) (wt . magit-worktrunk-core)))))
         (planner (cdr (assq backend '((lane . magit-lane-core-operation-plan)
                                       (wt . magit-worktrunk-core-operation-plan))))))
    (unless (or (plist-get options :native-argv)
                (and feature (require feature nil t) (fboundp planner)))
      (user-error "The selected Worktree backend has no operation planner: %s" backend))
    (setf (claude-code-ide-remote-worktree--operation-steps operation)
          (if (plist-get options :native-argv)
              (claude-code-ide-remote-worktree--native-plan snapshot action options)
            (funcall planner snapshot action options)))
    (cond
     ((and (eq action 'prune)
           (or (plist-get options :dry-run)
               (not (claude-code-ide-remote-worktree--operation-steps operation))))
      (claude-code-ide-remote-worktree--complete-read operation nil))
     ((and (eq action 'create) (not (plist-get options :create-only)))
      (claude-code-ide-remote-worktree--prepare-launch
       operation #'claude-code-ide-remote-worktree--submit))
     (t (claude-code-ide-remote-worktree--submit operation)))))

(defun claude-code-ide-remote-worktree--prepared (operation _snapshot)
  "Route OPERATION through its prepared snapshot without synchronous I/O."
  (cond
   ((plist-get (claude-code-ide-remote-worktree--operation-options operation) :native-argv)
    (let* ((options (claude-code-ide-remote-worktree--operation-options operation))
           (snapshot (claude-code-ide-remote-worktree--operation-snapshot operation))
           (backend (or (plist-get options :backend) 'wt)))
      (setf (plist-get snapshot :backend) backend
            (claude-code-ide-remote-worktree--operation-snapshot operation) snapshot
            (claude-code-ide-remote-worktree--operation-options operation)
            (plist-put options :backend backend))
      (claude-code-ide-remote-worktree--prepare-mutation
       operation #'claude-code-ide-remote-worktree--plan-operation)))
   ((eq (claude-code-ide-remote-worktree--operation-kind operation) 'create)
    (claude-code-ide-remote-worktree--prepare-create
     operation #'claude-code-ide-remote-worktree--plan-operation))
   ((and (eq (claude-code-ide-remote-worktree--operation-kind operation) 'open)
         (not (plist-get (claude-code-ide-remote-worktree--operation-options operation) :backend))
         (not (plist-get (claude-code-ide-remote-worktree--operation-options operation) :name)))
    (claude-code-ide-remote-worktree--prompt operation #'claude-code-ide-remote-worktree--open))
   (t
    (claude-code-ide-remote-worktree--prepare-backend
     operation
     (lambda (ready)
       (pcase (claude-code-ide-remote-worktree--operation-kind ready)
         ('open
          (claude-code-ide-remote-worktree--prompt ready #'claude-code-ide-remote-worktree--open))
         ('list
          (claude-code-ide-remote-worktree--prerequisites ready)
          (let ((snapshot (claude-code-ide-remote-worktree--operation-snapshot ready)))
            (claude-code-ide-remote-worktree--complete-read
             ready
             (and (plist-get (claude-code-ide-remote-worktree--operation-options ready) :refresh)
                  (plist-get snapshot :worktree)
                  (list :host (plist-get snapshot :host) :directory (plist-get snapshot :worktree))))))
         (_ (claude-code-ide-remote-worktree--prepare-mutation
             ready #'claude-code-ide-remote-worktree--plan-operation))))))))

(defun claude-code-ide-remote-worktree--start (operation attempt generation)
  "Start preparation only while OPERATION owns ATTEMPT and GENERATION."
  (when (and (claude-code-ide-remote-worktree--current-p operation attempt generation)
             (eq (claude-code-ide-remote-worktree--operation-state operation) 'preparing))
    (setf (claude-code-ide-remote-worktree--operation-timer operation) nil
          (claude-code-ide-remote-worktree--operation-observation operation) 'observing)
    (condition-case error-data
        (progn
          (claude-code-ide-remote-worktree--present-results operation t)
          (claude-code-ide-remote-worktree--prepare
           operation
           (lambda (snapshot)
             (when (claude-code-ide-remote-worktree--current-p operation attempt generation)
               (claude-code-ide-remote-worktree--prepared operation snapshot)))))
      (error
       (claude-code-ide-remote-worktree--fail operation (error-message-string error-data))))))

;;;###autoload
(defun claude-code-ide-remote-worktree-request (action host directory &optional options)
  "Request ACTION on exact HOST and absolute remote DIRECTORY with OPTIONS.
Return the retained operation ID before preparation or remote I/O.
OPTIONS contains literal action-specific values, never shell source.
Use `claude-code-ide-remote-worktree-show' to inspect the retained result."
  (let ((operation (claude-code-ide-remote-worktree--new-operation
                    action host directory options)))
    (setf (claude-code-ide-remote-worktree--operation-timer operation)
          (run-at-time
           0 nil #'claude-code-ide-remote-worktree--start operation
           (claude-code-ide-remote-worktree--operation-attempt-id operation)
           (claude-code-ide-remote-worktree--operation-generation operation)))
    (claude-code-ide-remote-worktree--operation-id operation)))

(defun claude-code-ide-remote-worktree--decimal (text &optional positive maximum)
  "Validate canonical decimal TEXT, with optional POSITIVE and MAXIMUM bounds."
  (unless (and (stringp text)
               (string-match-p "\\`\\(?:0\\|[1-9][0-9]*\\)\\'" text))
    (user-error "A Worktree receipt contains an invalid decimal value"))
  (let ((number (string-to-number text)))
    (unless (and (or (not positive) (> number 0))
                 (or (not maximum) (<= number maximum)))
      (user-error "A Worktree receipt number exceeds its permitted range"))
    number))

(defun claude-code-ide-remote-worktree--receipt-keys (name count)
  "Return the exact permitted keys for receipt NAME within COUNT steps."
  (or (cdr (assoc name
                  '(("manifest" "protocol" "operation" "attempt" "kind" "steps")
                    ("worker-started" "attempt" "pid" "start-signature")
                    ("creation-result" "attempt" "directory" "repository" "branch")
                    ("merge-result" "attempt" "step" "source-ref" "source-oid" "target-ref" "target-oid")
                    ("bootstrap-owned" "attempt" "name" "directory" "token")
                    ("agent-exit" "attempt" "name" "status")
                    ("finished" "attempt" "entered" "state"))))
      (when (string-match "\\`step-\\([1-9][0-9]*\\)\\.\\(entered\\|exit\\)\\'" name)
        (let ((number (match-string 1 name))
              (kind (match-string 2 name)))
          (claude-code-ide-remote-worktree--decimal number t count)
          (if (equal kind "entered")
              '("attempt" "step" "state")
            '("attempt" "step" "status"))))
      (user-error "The outcome response contains an unknown authority filename")))

(defun claude-code-ide-remote-worktree--parse-authority (bytes keys)
  "Parse bounded UTF-8 BYTES with exactly KEYS and a final newline."
  (let ((text (decode-coding-string bytes 'utf-8-unix))
        fields)
    (unless (and (<= (length bytes) 16384)
                 (string-suffix-p "\n" text)
                 (cl-every (lambda (character) (<= character #x10ffff)) text))
      (user-error "A Worktree authority file has invalid encoding, size, or termination"))
    (dolist (line (split-string (substring text 0 -1) "\n"))
      (unless (and (claude-code-ide-remote-worktree--literal-p line)
                   (string-match "\\`\\([^=]+\\)=\\(.*\\)\\'" line))
        (user-error "A Worktree authority file contains an invalid record"))
      (let ((key (match-string 1 line))
            (value (match-string 2 line)))
        (unless (and (member key keys) (not (assoc key fields)))
          (user-error "A Worktree authority file contains an unknown or duplicate key"))
        (push (cons key value) fields)))
    (unless (= (length fields) (length keys))
      (user-error "A Worktree authority file lacks a required key"))
    fields))

(defun claude-code-ide-remote-worktree--decode-receipts (operation stdout)
  "Validate OPERATION's read-only receipt response in STDOUT."
  (let* ((lines (split-string stdout "\n"))
         (count (length (claude-code-ide-remote-worktree--operation-steps operation)))
         (attempt (claude-code-ide-remote-worktree--operation-attempt-id operation))
         (snapshot (claude-code-ide-remote-worktree--operation-snapshot operation))
         generation live receipts diagnostics entries authority)
    (unless (and (equal (pop lines) "cci-receipts-1")
                 (equal (car (last lines)) ""))
      (user-error "The receipt response has an invalid envelope"))
    (setq generation (pop lines) live (pop lines) lines (butlast lines))
    (unless (and (member generation '("generation=stable" "generation=changed"))
                 (member live '("worker-live=0" "worker-live=1" "worker-live=unknown")))
      (user-error "The receipt response has invalid observation evidence"))
    (dolist (line lines)
      (unless (string-match "\\`\\(file\\|diagnostic\\)=\\([a-z0-9.-]+\\)\t\\(.*\\)\\'" line)
        (user-error "The receipt response contains an invalid file frame"))
      (let* ((kind (match-string 1 line))
             (name (match-string 2 line))
             (encoded (match-string 3 line))
             (bytes (condition-case nil (base64-decode-string encoded)
                      (error (user-error "The receipt response contains invalid base64")))))
        (unless (equal encoded (base64-encode-string bytes t))
          (user-error "The receipt response contains noncanonical base64"))
        (if (equal kind "file")
            (progn
              (push line authority)
              (when (assoc name receipts)
                (user-error "The receipt response repeats an authority file"))
              (push (cons name
                          (claude-code-ide-remote-worktree--parse-authority
                           bytes (claude-code-ide-remote-worktree--receipt-keys name count)))
                    receipts))
          (unless (and (<= (length bytes) 65536)
                       (not (assoc name diagnostics))
                       (or (equal name "worker.log")
                           (and (string-match "\\`step-\\([1-9][0-9]*\\)\\.\\(?:stdout\\|stderr\\)\\'" name)
                                (claude-code-ide-remote-worktree--decimal
                                 (match-string 1 name) t count))))
            (user-error "The receipt response contains an invalid diagnostic file"))
          (push (cons name (decode-coding-string bytes 'utf-8-unix)) diagnostics))))
    (dolist (receipt receipts)
      (unless (equal (cdr (assoc "attempt" (cdr receipt))) attempt)
        (user-error "A receipt belongs to a different Worktree attempt")))
    (let ((manifest (cdr (assoc "manifest" receipts))))
      (unless (and (equal (cdr (assoc "protocol" manifest)) "cci-worktree-1")
                   (equal (cdr (assoc "operation" manifest))
                          (claude-code-ide-remote-worktree--operation-id operation))
                   (equal (cdr (assoc "kind" manifest))
                          (symbol-name (claude-code-ide-remote-worktree--operation-kind operation)))
                   (= (claude-code-ide-remote-worktree--decimal
                       (cdr (assoc "steps" manifest)) t) count))
        (user-error "The receipt manifest does not match the captured operation")))
    ;; A live writer can advance between receipt files.  Discard that mixed
    ;; snapshot instead of interpreting its cross-file order as corruption.
    (if (equal generation "generation=changed")
        (list :stable nil
              :worker-live (pcase live ("worker-live=1" t) ("worker-live=0" nil) (_ 'unknown))
              :steps (mapcar (lambda (step) (list :step-id (plist-get step :step-id)))
                             (claude-code-ide-remote-worktree--operation-steps operation))
              :diagnostics diagnostics)
      (progn
        (let ((previous-exit 0) gap)
          (dolist (step (claude-code-ide-remote-worktree--operation-steps operation))
            (let* ((number (plist-get step :step-id))
                   (entered (cdr (assoc (format "step-%d.entered" number) receipts)))
                   (exited (cdr (assoc (format "step-%d.exit" number) receipts)))
                   status)
              (when (and exited (not entered))
                (user-error "A step exit has no matching entry receipt"))
              (if (not entered)
                  (setq gap t)
                (unless (and (not gap) (eql previous-exit 0)
                             (equal (cdr (assoc "step" entered)) (number-to-string number))
                             (equal (cdr (assoc "state" entered)) "entered"))
                  (user-error "The entered steps violate the captured execution order"))
                (when exited
                  (unless (equal (cdr (assoc "step" exited)) (number-to-string number))
                    (user-error "A step exit identifies a different step"))
                  (setq status (claude-code-ide-remote-worktree--decimal
                                (cdr (assoc "status" exited)) nil 255)))
                (setq previous-exit status))
              (push (list :step-id number :entered (and entered t) :exit-code status) entries))))
        (setq entries (nreverse entries))
        (let* ((worker (cdr (assoc "worker-started" receipts)))
               (terminal (cdr (assoc "finished" receipts)))
               (entered (seq-filter (lambda (step) (plist-get step :entered)) entries))
               (creation (cdr (assoc "creation-result" receipts)))
               (bootstrap (cdr (assoc "bootstrap-owned" receipts)))
               (agent-exit (cdr (assoc "agent-exit" receipts)))
               (landing (cdr (assoc "merge-result" receipts))))
          (when worker
            (claude-code-ide-remote-worktree--decimal (cdr (assoc "pid" worker)) t)
            (when (string-empty-p (cdr (assoc "start-signature" worker)))
              (user-error "The worker receipt lacks its process identity")))
          (when (and (or entered terminal (equal live "worker-live=1")) (not worker))
            (user-error "The attempt has no worker ownership receipt"))
          (when terminal
            (unless (and (equal (cdr (assoc "state" terminal)) "finished")
                         (= (claude-code-ide-remote-worktree--decimal
                             (cdr (assoc "entered" terminal)) nil count) (length entered))
                         (cl-every (lambda (step) (integerp (plist-get step :exit-code))) entered))
              (user-error "The terminal receipt does not match all entered step exits")))
          (when creation
            (unless (and (claude-code-ide-zmx--valid-directory-p (cdr (assoc "directory" creation)))
                         (equal (cdr (assoc "repository" creation)) (plist-get snapshot :repository))
                         (equal (cdr (assoc "branch" creation))
                                (plist-get (claude-code-ide-remote-worktree--operation-options operation) :name)))
              (user-error "The creation receipt identifies a different Worktree")))
          (when landing
            (let* ((number (claude-code-ide-remote-worktree--decimal (cdr (assoc "step" landing)) t count))
                   (step (nth (1- number) (claude-code-ide-remote-worktree--operation-steps operation)))
                   (record (plist-get step :merge-record)))
              (unless (and record (eql (plist-get (nth (1- number) entries) :exit-code) 0)
                           (equal (cdr (assoc "source-ref" landing)) (plist-get record :source-ref))
                           (equal (cdr (assoc "target-ref" landing)) (plist-get record :target-ref))
                           (cl-every
                            (lambda (key)
                              (string-match-p "\\`[0-9a-f]\\{40\\}\\(?:[0-9a-f]\\{24\\}\\)?\\'"
                                              (cdr (assoc key landing))))
                            '("source-oid" "target-oid")))
                (user-error "The landing receipt does not match the successful approved step"))))
          (when bootstrap
            (unless (and (equal (cdr (assoc "token" bootstrap)) attempt)
                         (equal (cdr (assoc "name" bootstrap))
                                (plist-get (plist-get snapshot :launch) :zmx-name))
                         (claude-code-ide-zmx--valid-directory-p (cdr (assoc "directory" bootstrap)))
                         (equal (cdr (assoc "directory" bootstrap))
                                (let ((directory (plist-get (plist-get snapshot :launch) :directory)))
                                  (if (eq directory :created)
                                      (cdr (assoc "directory" creation))
                                    directory))))
              (user-error "The bootstrap receipt lacks the captured Agent identity")))
          (when agent-exit
            (unless (and bootstrap (equal (cdr (assoc "name" agent-exit)) (cdr (assoc "name" bootstrap))))
              (user-error "The Agent exit lacks matching bootstrap ownership"))
            (claude-code-ide-remote-worktree--decimal (cdr (assoc "status" agent-exit)) nil 255))
          (list :stable (equal generation "generation=stable")
                :worker-live (pcase live ("worker-live=1" t) ("worker-live=0" nil) (_ 'unknown))
                :receipts receipts :steps entries :terminal terminal
                :authority (mapconcat #'identity (nreverse authority) "\n")
                :creation creation :bootstrap bootstrap :agent-exit agent-exit :landing landing
                :diagnostics diagnostics))))))

(defun claude-code-ide-remote-worktree--classify (operation evidence fresh)
  "Classify validated EVIDENCE for OPERATION against FRESH postconditions."
  (let ((steps (copy-tree (plist-get evidence :steps)))
        (checks (plist-get fresh :postconditions))
        (preconditions (plist-get fresh :preconditions))
        verified retryable mixed outcome)
    (setq steps (cl-mapcar
                 (lambda (step plan)
                   (let* ((number (plist-get step :step-id))
                          (check (alist-get number checks))
                          (state (cond ((not (plist-get step :entered)) 'unentered)
                                       ((and (eql (plist-get step :exit-code) 0) (eq check 'verified))
                                        (push number verified) 'verified)
                                       ((and (integerp (plist-get step :exit-code))
                                             (/= (plist-get step :exit-code) 0))
                                        (when (memq check '(verified partial)) (setq mixed t))
                                        'failed)
                                       ((and (null (plist-get step :exit-code))
                                             (plist-get evidence :stable)
                                             (not (plist-get evidence :terminal))
                                             (eq (plist-get evidence :worker-live) t))
                                        'pending)
                                       ((memq check '(verified partial)) (setq mixed t) 'partial)
                                       (t 'unknown))))
                     (setf (plist-get step :outcome) state)
                     (when (and (eq state 'unentered)
                                (eq (alist-get number preconditions) t)
                                (cl-every (lambda (prior) (memq prior verified))
                                          (number-sequence 1 (1- number)))
                                (cl-every (lambda (prior) (memq prior verified))
                                          (plist-get plan :requires)))
                       (push number retryable))
                     step))
                 steps (claude-code-ide-remote-worktree--operation-steps operation)))
    (setq outcome
          (cond
           ((or (not (plist-get evidence :stable)) (not (plist-get evidence :terminal)))
            (setq retryable nil)
            (if (eq (plist-get evidence :worker-live) t) 'still-running 'unknown))
           ((= (length verified) (length steps)) 'completed)
           (retryable 'confirmed-unfinished)
           ((or verified mixed) 'partial)
           (t 'unknown)))
    (list :outcome outcome :steps steps :verified (nreverse verified)
          :retryable (nreverse retryable) :evidence evidence :fresh fresh)))

;; ponytail: Snapshots read all refs under a 1 MiB cap. Query selected refs if this cap is reached.
(defun claude-code-ide-remote-worktree--parse-refs (text)
  "Parse exact ref names and object IDs from a bounded Git read in TEXT."
  (let (refs)
    (dolist (line (split-string text "\n" t))
      (unless (string-match
               "\\`\\(refs/[^[:space:][:cntrl:]]+\\) \\([0-9a-f]\\{40\\}\\(?:[0-9a-f]\\{24\\}\\)?\\)\\'"
               line)
        (user-error "The reference listing is invalid"))
      (let ((name (match-string 1 line)) (oid (match-string 2 line)))
        (when (assoc name refs)
          (user-error "The reference listing repeats a ref"))
        (push (cons name oid) refs)))
    (nreverse refs)))

(defconst claude-code-ide-remote-worktree--state-script
  (mapconcat
   #'identity
   '("set -eu"
     "export LC_ALL=C GIT_OPTIONAL_LOCKS=0 GIT_TERMINAL_PROMPT=0 GIT_ASKPASS=/bin/false SSH_ASKPASS=/bin/false SSH_ASKPASS_REQUIRE=never"
     "git=$1; repository=$2; shift 2"
     "[ -d \"$repository\" ] && [ \"$(cd \"$repository\" && pwd -P)\" = \"$repository\" ]"
     "common=$(\"$git\" --git-dir=\"$repository\" rev-parse --git-common-dir)"
     "[ \"$common\" = \"$repository\" ]"
     "printf 'cci-state-1\\000%s\\000' \"$repository\""
     "for path do if [ -L \"$path\" ]; then state=unknown; elif [ -d \"$path\" ] && [ -x \"$path\" ]; then state=directory; elif [ -f \"$path\" ]; then state=file; elif [ -e \"$path\" ]; then state=other; else parent=$(dirname \"$path\"); while [ ! -e \"$parent\" ] && [ ! -L \"$parent\" ] && [ \"$parent\" != / ]; do parent=$(dirname \"$parent\"); done; if [ -d \"$parent\" ] && [ -r \"$parent\" ] && [ -x \"$parent\" ]; then state=missing; else state=unknown; fi; fi; printf '%s\\000' \"$state\"; done"
     "refs=$(\"$git\" --git-dir=\"$repository\" for-each-ref '--format=%(refname) %(objectname)' 2>&1)"
     "printf '%s\\000' \"$refs\""
     "\"$git\" --git-dir=\"$repository\" worktree list --porcelain -z")
   "; ")
  "Read exact Git and path facts without optional Git writes.")

(defun claude-code-ide-remote-worktree--conditions (operation)
  "Return OPERATION's validated fixed preconditions and postconditions."
  (let ((conditions
         (apply #'append
                (mapcar (lambda (step)
                          (unless (and (proper-list-p (plist-get step :preconditions))
                                       (proper-list-p (plist-get step :postconditions)))
                            (user-error "Worktree conditions must be proper lists"))
                          (append (plist-get step :preconditions) (plist-get step :postconditions)))
                        (claude-code-ide-remote-worktree--operation-steps operation)))))
    (cl-labels
        ((oid-p (value)
           (and (stringp value)
                (string-match-p "\\`[0-9a-f]\\{40\\}\\(?:[0-9a-f]\\{24\\}\\)?\\'" value)))
         (ref-p (value)
           (and (claude-code-ide-remote-worktree--literal-p value)
                (string-prefix-p "refs/" value) (> (length value) 5))))
      (dolist (condition conditions)
        (unless (and (proper-list-p condition) (zerop (% (length condition) 2)))
          (user-error "A Worktree condition must be a property list"))
        (let* ((kind (plist-get condition :kind))
               (allowed (cdr (assq kind '((directory :kind :path :exists)
                                          (file :kind :path :exists)
                                          (worktree :kind :path :absent :branch :head)
                                          (ref :kind :name :oid)
                                          (creation :kind) (bootstrap :kind)
                                          (ancestor :kind :older :newer)
                                          (landing :kind :source-ref :target-ref)
                                          (branch-policy :kind :name :oid :target :policy)
                                          (publication :kind :destination :refs)))))
               (fields condition) seen)
          (unless allowed (user-error "The Worktree plan contains an unsupported condition"))
          (while fields
            (let ((key (pop fields)))
              (pop fields)
              (unless (and (memq key allowed) (not (memq key seen)))
                (user-error "A Worktree condition contains an unknown or duplicate field"))
              (push key seen)))
          (unless
              (pcase kind
                ((or 'directory 'file 'worktree)
                 (and (claude-code-ide-zmx--valid-directory-p (plist-get condition :path))
                      (if (memq kind '(directory file))
                          (and (plist-member condition :exists)
                               (memq (plist-get condition :exists) '(nil t)))
                        (and (memq (plist-get condition :absent) '(nil t))
                             (or (not (plist-get condition :branch))
                                 (and (claude-code-ide-remote-worktree--literal-p (plist-get condition :branch))
                                      (not (string-empty-p (plist-get condition :branch)))))
                             (or (not (plist-member condition :head)) (oid-p (plist-get condition :head)))))))
                ('ref (and (ref-p (plist-get condition :name)) (plist-member condition :oid)
                           (or (not (plist-get condition :oid)) (oid-p (plist-get condition :oid)))))
                ('branch-policy
                 (and (ref-p (plist-get condition :name))
                      (memq (plist-get condition :policy) '(safe keep delete))
                      (or (not (plist-get condition :oid)) (oid-p (plist-get condition :oid)))
                      (or (not (plist-get condition :target)) (ref-p (plist-get condition :target)))))
                ('landing (and (ref-p (plist-get condition :source-ref))
                               (ref-p (plist-get condition :target-ref))))
                ('ancestor (cl-every (lambda (value) (or (oid-p value) (ref-p value)))
                                     (list (plist-get condition :older) (plist-get condition :newer))))
                ('publication
                 (let ((destination (plist-get condition :destination))
                       (refs (plist-get condition :refs)) names)
                   (and (claude-code-ide-remote-worktree--literal-p destination)
                        (not (string-empty-p destination)) (not (string-prefix-p "-" destination))
                        (not (string-match-p "\\`[A-Za-z0-9+-]+::" destination))
                        (consp refs) (proper-list-p refs)
                        (cl-every
                         (lambda (ref)
                           (and (consp ref) (ref-p (car ref))
                                (or (not (cdr ref)) (oid-p (cdr ref)) (ref-p (cdr ref)))
                                (not (member (car ref) names))
                                (push (car ref) names)))
                         refs))))
                ((or 'creation 'bootstrap) t))
            (user-error "A Worktree condition has invalid or missing values")))))
    conditions))

(defun claude-code-ide-remote-worktree--read-state (operation callback)
  "Read fresh Git and path facts for OPERATION, then call CALLBACK."
  (let* ((snapshot (claude-code-ide-remote-worktree--operation-snapshot operation))
         (repository (plist-get snapshot :repository))
         (git (alist-get 'git (plist-get snapshot :tools)))
         (paths (delete-dups
                 (delq nil
                       (append
                        (mapcar (lambda (entry) (plist-get entry :path))
                                (plist-get snapshot :worktrees))
                        (mapcar (lambda (condition) (plist-get condition :path))
                                (claude-code-ide-remote-worktree--conditions operation)))))))
    (unless (and (claude-code-ide-zmx--valid-directory-p repository)
                 (claude-code-ide-zmx--valid-directory-p git)
                 (cl-every #'claude-code-ide-zmx--valid-directory-p paths))
      (user-error "The outcome check lacks captured remote Git identities"))
    (claude-code-ide-remote-worktree--control
     operation "worktree-state" "/bin/sh"
     (append (list "-c" claude-code-ide-remote-worktree--state-script
                   "cci-worktree-state" git repository) paths)
     (lambda (stdout)
       (unless (string-suffix-p (string 0) stdout)
         (user-error "The current Worktree state has no final delimiter"))
       (let* ((fields (split-string (substring stdout 0 -1) (string 0)))
              (states (seq-subseq fields 2 (+ 2 (length paths))))
              (entries (claude-code-ide-remote-worktree--parse-worktrees
                        (nthcdr (+ 3 (length paths)) fields)))
              (fresh (list :repository repository
                           :refs (claude-code-ide-remote-worktree--parse-refs
                                  (nth (+ 2 (length paths)) fields))
                           :paths (cl-mapcar #'cons paths (mapcar #'intern-soft states)))))
         (unless (and (equal (car fields) "cci-state-1")
                      (equal (cadr fields) repository)
                      (cl-every (lambda (state) (member state '("directory" "file" "missing" "other" "unknown")))
                                states))
           (user-error "The current Worktree state has invalid identities"))
         (dolist (entry entries)
           (when-let* ((branch (plist-get entry :branch)))
             (unless (equal (plist-get entry :head)
                            (cdr (assoc (concat "refs/heads/" branch) (plist-get fresh :refs))))
               (user-error "The repository refs changed during the outcome read"))))
         (claude-code-ide-remote-worktree--metadata
          operation (mapcar (lambda (entry) (plist-get entry :path)) entries)
          (lambda (records)
            (setq entries (cl-mapcar
                           (lambda (entry record)
                             (plist-put entry :exists
                                        (and (eq (plist-get record :kind) 'git)
                                             (equal (plist-get record :common-dir) repository)
                                             (or (plist-get entry :bare)
                                                 (and (equal (plist-get record :worktree-path) (plist-get entry :path))
                                                      (equal (plist-get record :branch) (plist-get entry :branch)))))))
                           entries records))
            (funcall callback (plist-put fresh :worktrees entries))))))
     "/tmp")))

(defun claude-code-ide-remote-worktree--condition-result (condition fresh evidence)
  "Check one fixed CONDITION against FRESH facts and validated EVIDENCE."
  (let* ((path (plist-get condition :path))
         (entry (seq-find (lambda (item) (equal (plist-get item :path) path))
                          (plist-get fresh :worktrees))))
    (pcase (plist-get condition :kind)
      ((or 'directory 'file)
       (let ((state (cdr (assoc path (plist-get fresh :paths)))))
         (if (memq state '(directory file missing other))
             (eq state (if (plist-get condition :exists) (plist-get condition :kind) 'missing))
           'unknown)))
      ('worktree
       (if (plist-get condition :absent)
           (not entry)
         (and entry (eq (plist-get entry :exists) t)
              (or (not (plist-member condition :branch))
                  (equal (plist-get entry :branch) (plist-get condition :branch)))
              (or (not (plist-member condition :head))
                  (equal (plist-get entry :head) (plist-get condition :head))))))
      ('ref
       (equal (cdr (assoc (plist-get condition :name) (plist-get fresh :refs)))
              (plist-get condition :oid)))
      ('branch-policy
       (let* ((name (plist-get condition :name))
              (current (cdr (assoc name (plist-get fresh :refs))))
              (landing (plist-get evidence :landing))
              (expected (or (plist-get condition :oid)
                            (and (equal name (cdr (assoc "source-ref" landing)))
                                 (cdr (assoc "source-oid" landing))))))
         (pcase (plist-get condition :policy)
           ('delete (not current))
           ('keep (and expected (equal current expected)))
           ('safe (or (not current) (and expected (equal current expected)))))))
      ('creation
       (let* ((creation (plist-get evidence :creation))
              (created (seq-find
                        (lambda (item)
                          (equal (plist-get item :path) (cdr (assoc "directory" creation))))
                        (plist-get fresh :worktrees))))
         (and creation created (eq (plist-get created :exists) t)
              (equal (plist-get created :branch) (cdr (assoc "branch" creation))))))
      ('bootstrap
       (and (plist-get evidence :bootstrap)
            (or (and (plist-get evidence :agent-exit) t)
                (eq (plist-get fresh :bootstrap-verified) t))))
      ('landing
       (let ((landing (plist-get evidence :landing)))
         (and landing
              (equal (plist-get condition :source-ref) (cdr (assoc "source-ref" landing)))
              (equal (plist-get condition :target-ref) (cdr (assoc "target-ref" landing)))
              (equal (cdr (assoc (plist-get condition :target-ref) (plist-get fresh :refs)))
                     (cdr (assoc "target-oid" landing))))))
      ((or 'ancestor 'publication)
       (let ((result (assoc condition (plist-get fresh :extra))))
         (if result (cdr result) 'unknown)))
      (_ (user-error "The Worktree plan contains an unsupported condition")))))

(defun claude-code-ide-remote-worktree--cleanup-preconditions (step evidence)
  "Replace STEP's pre-landing identities only with EVIDENCE's owned landing result."
  (let ((conditions (plist-get step :preconditions))
        (landing (plist-get evidence :landing)))
    (if (not (and (plist-get step :merge-cleanup) landing))
        conditions
      (append
       (mapcar
        (lambda (condition)
          (if (eq (plist-get condition :kind) 'worktree)
              (plist-put (copy-sequence condition) :head (cdr (assoc "source-oid" landing)))
            condition))
        conditions)
       (mapcar (lambda (side)
                 (list :kind 'ref :name (cdr (assoc (concat side "-ref") landing))
                       :oid (cdr (assoc (concat side "-oid") landing))))
               '("source" "target"))))))

(defun claude-code-ide-remote-worktree--evaluate-conditions (operation evidence fresh)
  "Add OPERATION's per-step prerequisite and postcondition checks to FRESH."
  (dolist (phase '(:preconditions :postconditions))
    (let (checks)
      (dolist (step (claude-code-ide-remote-worktree--operation-steps operation))
        (let* ((conditions (if (eq phase :preconditions)
                               (claude-code-ide-remote-worktree--cleanup-preconditions step evidence)
                             (plist-get step phase)))
               (verified (and (consp conditions)
                              (cl-every
                               (lambda (condition)
                                 (eq (claude-code-ide-remote-worktree--condition-result
                                      condition fresh evidence) t))
                               conditions))))
          (push (cons (plist-get step :step-id)
                      (if (eq phase :preconditions) verified
                        (if verified 'verified 'unknown)))
                checks)))
      (setq fresh (plist-put fresh phase (nreverse checks)))))
  fresh)

(defun claude-code-ide-remote-worktree--read-bootstrap (operation evidence fresh callback)
  "Check owned bootstrap identity for OPERATION before calling CALLBACK with FRESH."
  (let ((bootstrap (plist-get evidence :bootstrap)))
    (if (or (not bootstrap) (plist-get evidence :agent-exit))
        (funcall callback fresh)
      (let* ((attempt (claude-code-ide-remote-worktree--operation-attempt-id operation))
             (generation (claude-code-ide-remote-worktree--operation-generation operation))
             (host (plist-get (claude-code-ide-remote-worktree--operation-target operation) :host))
             (root (claude-code-ide-remote-worktree--operation-receipt-directory operation))
             (expected-command (format "/bin/sh %s/bootstrap.sh %s" root attempt)))
        (setf (claude-code-ide-remote-worktree--operation-request operation)
              (claude-code-ide-zmx-discover-remote
               host
               (lambda (result)
                 (when (claude-code-ide-remote-worktree--current-p operation attempt generation)
                   (setf (claude-code-ide-remote-worktree--operation-request operation) nil)
                   (if (plist-get result :error)
                       (claude-code-ide-remote-worktree--fail operation (plist-get result :error))
                     (let* ((session (seq-find
                                      (lambda (item)
                                        (equal (plist-get item :name) (cdr (assoc "name" bootstrap))))
                                      (plist-get result :sessions)))
                            (directory (and session (claude-code-ide-remote-worktree--agent-directory session)))
                            (identity (mapcar (lambda (key) (plist-get session key))
                                              '(:name :pid :created :cmd :start_dir)))
                            (previous (plist-get
                                       (claude-code-ide-remote-worktree--operation-results operation)
                                       :bootstrap-identity)))
                       (if (not (and directory (not (plist-get session :error))
                                     (equal (plist-get session :cmd) expected-command)
                                     (or (not previous) (equal identity previous))))
                           (funcall callback fresh)
                         (claude-code-ide-remote-worktree--metadata
                          operation (list directory)
                          (lambda (records)
                            (let ((record (car records)))
                              (setq fresh
                                    (plist-put fresh :bootstrap-verified
                                               (and (eq (plist-get record :kind) 'git)
                                                    (equal (plist-get record :worktree-path)
                                                           (cdr (assoc "directory" bootstrap)))
                                                    (equal (plist-get record :common-dir)
                                                           (plist-get fresh :repository)))))
                              (when (plist-get fresh :bootstrap-verified)
                                (setq fresh (plist-put fresh :bootstrap-identity identity)))
                              (funcall callback fresh)))))))))))))))

(defun claude-code-ide-remote-worktree--read-extra-conditions (operation evidence fresh callback)
  "Read remaining Git facts, then call CALLBACK with FRESH."
  (let* ((snapshot (claude-code-ide-remote-worktree--operation-snapshot operation))
         (git (alist-get 'git (plist-get snapshot :tools)))
         (repository (plist-get snapshot :repository))
         (pending (delete-dups
                   (seq-filter (lambda (condition)
                                 (memq (plist-get condition :kind) '(ancestor publication)))
                               (claude-code-ide-remote-worktree--conditions operation)))))
    (cl-labels
        ((next ()
           (if (not pending)
               (claude-code-ide-remote-worktree--read-bootstrap operation evidence fresh callback)
             (let* ((condition (pop pending))
                    (publication (eq (plist-get condition :kind) 'publication))
                    (arguments
                     (if publication
                         (append (list "ls-remote" "--refs" "--" (plist-get condition :destination))
                                 (mapcar #'car (plist-get condition :refs)))
                       (list "merge-base" "--is-ancestor"
                             (plist-get condition :older) (plist-get condition :newer)))))
               (unless (cl-every #'claude-code-ide-remote-worktree--literal-p arguments)
                 (user-error "A Worktree postcondition has invalid Git arguments"))
               (claude-code-ide-remote-worktree--control
                operation "worktree-postcondition" "/bin/sh"
                (append
                 (list "-c"
                       (concat
                        "export GIT_OPTIONAL_LOCKS=0 GIT_TERMINAL_PROMPT=0 GIT_ASKPASS=/bin/false SSH_ASKPASS=/bin/false SSH_ASKPASS_REQUIRE=never; "
                        (if publication "exec \"$@\""
                          "\"$@\" >/dev/null 2>&1; status=$?; case $status in 0) printf 'true\\n';; 1) printf 'false\\n';; *) exit \"$status\";; esac"))
                       "cci-worktree-postcondition" git
                       "-c" "credential.interactive=false" "--git-dir" repository)
                 arguments)
                (lambda (stdout)
                  (let ((verified
                         (if (not publication)
                             (progn
                               (unless (member stdout '("true\n" "false\n"))
                                 (user-error "The ancestor check returned invalid evidence"))
                               (equal stdout "true\n"))
                           (let (refs)
                             (dolist (line (split-string stdout "\n" t))
                               (unless (string-match
                                        "\\`\\([0-9a-f]\\{40\\}\\(?:[0-9a-f]\\{24\\}\\)?\\)\t\\(refs/[^[:space:][:cntrl:]]+\\)\\'"
                                        line)
                                 (user-error "The publication destination returned invalid refs"))
                               (let ((oid (match-string 1 line)) (name (match-string 2 line)))
                                 (when (assoc name refs)
                                   (user-error "The publication destination repeats a ref"))
                                 (push (cons name oid) refs)))
                             (cl-every (lambda (expected)
                                         (equal (cdr (assoc (car expected) refs))
                                                (if (and (stringp (cdr expected))
                                                         (string-prefix-p "refs/" (cdr expected)))
                                                    (cdr (assoc (cdr expected) (plist-get fresh :refs)))
                                                  (cdr expected))))
                                       (plist-get condition :refs))))))
                    (setq fresh (plist-put fresh :extra
                                           (cons (cons condition verified) (plist-get fresh :extra))))
                    (next)))
                "/tmp")))))
      (next))))

(defun claude-code-ide-remote-worktree--view-target (operation evidence fresh)
  "Return OPERATION's verified surviving Worktree target from EVIDENCE and FRESH."
  (let* ((directory
          (pcase (claude-code-ide-remote-worktree--operation-kind operation)
            ('create (cdr (assoc "directory" (or (plist-get evidence :creation)
                                                 (plist-get evidence :bootstrap)))))
            ('move (plist-get (claude-code-ide-remote-worktree--operation-options operation) :destination))
            (_ (plist-get (claude-code-ide-remote-worktree--operation-snapshot operation) :worktree))))
         (entry (seq-find (lambda (item) (equal (plist-get item :path) directory))
                          (plist-get fresh :worktrees))))
    (when (and directory (eq (plist-get entry :exists) t)
               (pcase (claude-code-ide-remote-worktree--operation-kind operation)
                 ('create
                  (if (plist-get evidence :creation)
                      (claude-code-ide-remote-worktree--condition-result '(:kind creation) fresh evidence)
                    (and (plist-get evidence :bootstrap)
                         (equal (plist-get entry :branch)
                                (plist-get (claude-code-ide-remote-worktree--operation-options operation) :name)))))
                 ('move (equal (plist-get entry :branch)
                               (plist-get (claude-code-ide-remote-worktree--operation-snapshot operation)
                                          :branch)))
                 (_ t)))
      (list :host (plist-get (claude-code-ide-remote-worktree--operation-target operation) :host)
            :directory directory))))

(defun claude-code-ide-remote-worktree--reconcile (operation fresh)
  "Reconcile only OPERATION's freshly proven removed or moved Worktree paths."
  (let* ((snapshot (claude-code-ide-remote-worktree--operation-snapshot operation))
         (host (plist-get snapshot :host))
         (surviving (seq-filter (lambda (entry)
                                  (and (eq (plist-get entry :exists) t) (not (plist-get entry :bare))))
                                (plist-get fresh :worktrees)))
         (affected
          (delete-dups
           (mapcar
            (lambda (condition) (plist-get condition :path))
            (seq-filter
             (lambda (condition)
               (and (eq (plist-get condition :kind) 'worktree) (plist-get condition :absent)
                    (not (assoc (plist-get condition :path)
                                (mapcar (lambda (entry) (cons (plist-get entry :path) entry))
                                        (plist-get fresh :worktrees))))
                    (eq (cdr (assoc (plist-get condition :path) (plist-get fresh :paths))) 'missing)))
             (claude-code-ide-remote-worktree--conditions operation))))))
    (when fresh
      (let (keys)
        (maphash
         (lambda (key cached)
           (when (and (equal (car key) host)
                      (equal (plist-get cached :repository) (plist-get snapshot :repository)))
             (push key keys)))
         claude-code-ide-remote-worktree--snapshots)
        (dolist (key keys) (remhash key claude-code-ide-remote-worktree--snapshots))))
    (when (and affected (require 'claude-code-ide-remote-project nil t))
      (let ((report
             (claude-code-ide-remote-project-reconcile-worktrees
              host affected surviving
              (when (eq (claude-code-ide-remote-worktree--operation-kind operation) 'move)
                (plist-get (claude-code-ide-remote-worktree--operation-options operation) :destination))))
            (origin (plist-get snapshot :origin-worktree)))
        (setq report (plist-put report :origin-removed
                                (and origin
                                     (seq-some (lambda (path)
                                                 (string-prefix-p (file-name-as-directory path)
                                                                  (file-name-as-directory origin)))
                                               affected))))
        (plist-put report :surviving surviving)))))

(defun claude-code-ide-remote-worktree--publish-check (operation evidence fresh)
  "Retain OPERATION's checked EVIDENCE and FRESH facts without remote side effects."
  (let ((result (claude-code-ide-remote-worktree--classify
                 operation evidence
                 (and fresh (claude-code-ide-remote-worktree--evaluate-conditions operation evidence fresh)))))
    (dolist (key '(:attachment :view :attempts :bootstrap-identity
                               :retained-evidence :resource-status :resource-error :view-request))
      (when-let* ((value (plist-get (claude-code-ide-remote-worktree--operation-results operation) key)))
        (setq result (plist-put result key value))))
    (when-let* ((target (claude-code-ide-remote-worktree--view-target operation evidence fresh)))
      (setq result (plist-put result :view-target target)))
    (when-let* ((report (and fresh (claude-code-ide-remote-worktree--reconcile operation fresh))))
      (setq result (plist-put result :reconciliation report))
      (when-let* ((destination (and (not (plist-get result :view-target))
                                    (plist-get report :destination))))
        (setq result (plist-put result :view-target
                                (list :host (plist-get (claude-code-ide-remote-worktree--operation-target operation) :host)
                                      :directory (plist-get destination :path)))))
      (when (and (plist-get report :origin-removed) (not (plist-get result :view-target)))
        (setq result
              (plist-put result :view
                         (list :status 'unavailable
                               :error (format "No surviving Worktree is available on host %s."
                                              (plist-get (claude-code-ide-remote-worktree--operation-target operation)
                                                         :host))))))
      (let* ((snapshot (claude-code-ide-remote-worktree--operation-snapshot operation))
             (origin (plist-get snapshot :origin-worktree))
             (surviving (plist-get report :surviving))
             (current (seq-find (lambda (entry) (equal origin (plist-get entry :path))) surviving))
             (target (if current
                         (list :host (plist-get snapshot :host) :directory origin)
                       (plist-get result :view-target))))
        (when target
          (setq result (plist-put result :view-target target))
          (when (plist-get snapshot :backend)
            (let ((view-snapshot (copy-tree snapshot))
                  (directory (plist-get target :directory)))
              (setf (plist-get view-snapshot :directory) directory
                    (plist-get view-snapshot :worktree) directory
                    (plist-get view-snapshot :worktrees) (copy-tree (plist-get fresh :worktrees))
                    (plist-get view-snapshot :refs) (copy-tree (plist-get fresh :refs)))
              (unless (seq-find (lambda (entry)
                                  (equal (plist-get entry :path) (plist-get snapshot :main-worktree)))
                                surviving)
                (setf (plist-get view-snapshot :main-worktree) directory))
              (setq result (plist-put result :view-snapshot view-snapshot)))))))
    (when-let* ((identity (plist-get fresh :bootstrap-identity)))
      (setq result (plist-put result :bootstrap-identity identity)))
    (when (and (plist-get fresh :bootstrap-verified) (not (plist-get evidence :agent-exit)))
      (let ((bootstrap (plist-get evidence :bootstrap))
            (launch (plist-get (claude-code-ide-remote-worktree--operation-snapshot operation) :launch)))
        (setq result
              (plist-put result :attachment-target
                         (list :host (plist-get (claude-code-ide-remote-worktree--operation-target operation) :host)
                               :directory (cdr (assoc "directory" bootstrap))
                               :name (cdr (assoc "name" bootstrap))
                               :cli-type (plist-get launch :cli-type))))))
    (when (and (plist-get evidence :agent-exit) (not (plist-get result :attachment)))
      (setq result (plist-put result :attachment '(:status agent-exited))))
    (setf (claude-code-ide-remote-worktree--operation-results operation) result
          (claude-code-ide-remote-worktree--operation-observation operation) 'stopped
          (claude-code-ide-remote-worktree--operation-error operation) nil)
    (claude-code-ide-remote-worktree--transition operation (plist-get result :outcome))))

(defun claude-code-ide-remote-worktree--select-operation ()
  "Select one retained operation using local data only."
  (let (choices)
    (maphash
     (lambda (id operation)
       (push (cons (format "%s %s %s [%s, %s]"
                           (plist-get (claude-code-ide-remote-worktree--operation-target operation) :host)
                           (claude-code-ide-remote-worktree--operation-kind operation)
                           (plist-get (claude-code-ide-remote-worktree--operation-target operation) :directory)
                           (claude-code-ide-remote-worktree--operation-state operation)
                           id)
                   id)
             choices))
     claude-code-ide-remote-worktree--operations)
    (unless choices (user-error "There are no retained Worktree operations"))
    (cdr (assoc (completing-read "Worktree operation: " choices nil t) choices))))

(defun claude-code-ide-remote-worktree--runner-request (operation action callback &optional extra failure)
  "Run trusted local reader or release code for OPERATION, never resource code."
  (unless (member action '("read" "release"))
    (user-error "Unsupported Worktree resource action"))
  (claude-code-ide-remote-worktree--control
   operation (if (equal action "read") "worktree-receipts" "worktree-release") "/bin/sh"
   (append
    (list "-c"
          "script=$(printf '%s' \"$1\" | base64 -d) || exit; shift; exec /bin/sh -c \"$script\" cci-worktree-reader \"$@\""
          "cci-worktree-reader"
          (with-temp-buffer
            (insert-file-contents claude-code-ide-remote-worktree--runner-file)
            (base64-encode-string (encode-coding-string (buffer-string) 'utf-8-unix) t))
          action (claude-code-ide-remote-worktree--operation-receipt-directory operation)
          (claude-code-ide-remote-worktree--operation-attempt-id operation)
          (claude-code-ide-remote-worktree--operation-id operation)
          (number-to-string (length (claude-code-ide-remote-worktree--operation-steps operation))))
    extra)
   callback "/tmp" (if (equal action "read") 1048576 4096) failure))

(defun claude-code-ide-remote-worktree--release (operation)
  "Retain terminal proof, then release only OPERATION's completed, unused resource.
Never call this function from Check outcome."
  (let* ((result (claude-code-ide-remote-worktree--operation-results operation))
         (evidence (plist-get result :evidence)))
    (when (and (eq operation (gethash (claude-code-ide-remote-worktree--operation-id operation)
                                      claude-code-ide-remote-worktree--operations))
               (eq (claude-code-ide-remote-worktree--operation-state operation) 'completed)
               (eq (plist-get result :outcome) 'completed)
               (plist-get evidence :stable) (plist-get evidence :terminal)
               (null (plist-get evidence :worker-live))
               (or (not (plist-get evidence :bootstrap)) (plist-get evidence :agent-exit))
               (stringp (plist-get evidence :authority))
               (claude-code-ide-remote-worktree--operation-receipt-directory operation)
               (not (claude-code-ide-remote-worktree--operation-request operation))
               (not (plist-get result :resource-status)))
      (setq result (plist-put result :retained-evidence evidence)
            result (plist-put result :resource-status 'releasing))
      (setf (claude-code-ide-remote-worktree--operation-results operation) result)
      (let ((failure
             (lambda (diagnostic)
               (let ((results (claude-code-ide-remote-worktree--operation-results operation)))
                 (setq results (plist-put results :resource-status 'unknown)
                       results (plist-put results :resource-error diagnostic))
                 (setf (claude-code-ide-remote-worktree--operation-results operation) results))
               (claude-code-ide-remote-worktree--refresh-results operation))))
        (condition-case error-data
            (claude-code-ide-remote-worktree--runner-request
             operation "release"
             (lambda (stdout)
               (unless (equal stdout "released\n")
                 (user-error "The resource release acknowledgment is invalid"))
               (setf (claude-code-ide-remote-worktree--operation-receipt-directory operation) nil
                     (claude-code-ide-remote-worktree--operation-results operation)
                     (plist-put (claude-code-ide-remote-worktree--operation-results operation)
                                :resource-status 'released))
               (claude-code-ide-remote-worktree--refresh-results operation))
             (list (base64-encode-string
                    (encode-coding-string (plist-get evidence :authority) 'utf-8-unix) t))
             failure)
          (error (funcall failure (error-message-string error-data))))))))

;;;###autoload
(defun claude-code-ide-remote-worktree-cancel-observation (operation-id)
  "Stop OPERATION-ID's local work without stopping a submitted mutation."
  (interactive (list (claude-code-ide-remote-worktree--select-operation)))
  (let* ((operation (gethash operation-id claude-code-ide-remote-worktree--operations))
         (state (and operation (claude-code-ide-remote-worktree--operation-state operation)))
         (request (and operation (claude-code-ide-remote-worktree--operation-request operation)))
         (timer (and operation (claude-code-ide-remote-worktree--operation-timer operation)))
         (result (and operation (claude-code-ide-remote-worktree--operation-results operation)))
         (view-request (plist-get result :view-request)))
    (unless operation (user-error "The Worktree operation is not retained"))
    ;; Invalidate callbacks before deleting the owned local request.
    (cl-incf (claude-code-ide-remote-worktree--operation-generation operation))
    (setf (claude-code-ide-remote-worktree--operation-request operation) nil
          (claude-code-ide-remote-worktree--operation-timer operation) nil
          (claude-code-ide-remote-worktree--operation-display-context operation) nil
          (claude-code-ide-remote-worktree--operation-observation operation) 'stopped)
    (when timer (cancel-timer timer))
    (when (and (processp request) (process-live-p request))
      (delete-process request))
    (when (eq (plist-get result :resource-status) 'releasing)
      (setq result (plist-put result :resource-status 'unknown)
            result (plist-put result :resource-error
                              "Release observation stopped. The exact resource might already be removed.")))
    (when (or view-request (eq (plist-get (plist-get result :view) :status) 'opening))
      (setq result (plist-put result :view-request nil)
            result (plist-put result :view '(:status stopped)))
      (condition-case error-data
          (when view-request (claude-code-ide-remote-project-cancel-target view-request))
        (error
         (setq result (plist-put result :view
                                 (list :status 'stopped :error (error-message-string error-data)))))))
    (setf (claude-code-ide-remote-worktree--operation-results operation) result)
    (let ((next (cond ((memq state '(preparing awaiting-confirmation)) 'canceled-before-dispatch)
                      ((memq state '(dispatching observing checking still-running)) 'observation-stopped)
                      (t state))))
      (if (eq state next)
          (claude-code-ide-remote-worktree--refresh-results operation)
        (claude-code-ide-remote-worktree--transition operation next)))
    operation-id))

(defun claude-code-ide-remote-worktree--observe (operation &optional callback)
  "Observe OPERATION with serial bounded reads, then call CALLBACK when settled."
  (let ((attempt (claude-code-ide-remote-worktree--operation-attempt-id operation))
        (generation (claude-code-ide-remote-worktree--operation-generation operation)))
    (when (claude-code-ide-remote-worktree--current-p operation attempt generation)
      (condition-case error-data
          (claude-code-ide-remote-worktree--check-operation
           (claude-code-ide-remote-worktree--operation-id operation)
           (lambda (checked)
             (when (claude-code-ide-remote-worktree--current-p checked attempt generation)
               (if (or (eq (claude-code-ide-remote-worktree--operation-state checked) 'still-running)
                       (not (plist-get
                             (plist-get (claude-code-ide-remote-worktree--operation-results checked) :evidence)
                             :stable)))
                   (setf
                    (claude-code-ide-remote-worktree--operation-observation checked) 'observing
                    (claude-code-ide-remote-worktree--operation-timer checked)
                    (run-at-time
                     1 nil
                     (lambda ()
                       (when (claude-code-ide-remote-worktree--current-p checked attempt generation)
                         (setf (claude-code-ide-remote-worktree--operation-timer checked) nil)
                         (claude-code-ide-remote-worktree--observe checked callback)))))
                 (when callback (funcall callback checked)))))
           t)
        (error (claude-code-ide-remote-worktree--fail operation (error-message-string error-data)))))))

(defun claude-code-ide-remote-worktree--check-operation (operation-id &optional callback polling)
  "Read OPERATION-ID, then call CALLBACK.
POLLING retains the current observation generation."
  (let* ((operation (gethash operation-id claude-code-ide-remote-worktree--operations))
         (root (and operation (claude-code-ide-remote-worktree--operation-receipt-directory operation)))
         (retained (and operation
                        (plist-get (claude-code-ide-remote-worktree--operation-results operation)
                                   :retained-evidence)))
         (publish (lambda (evidence fresh)
                    (claude-code-ide-remote-worktree--publish-check operation evidence fresh)
                    (when callback (funcall callback operation)))))
    (unless (and operation (or root retained)
                 (memq (claude-code-ide-remote-worktree--operation-state operation)
                       '(observing observation-stopped unknown partial completed failed
                                   still-running confirmed-unfinished)))
      (user-error "This Worktree operation has no submitted receipt resource"))
    (when (claude-code-ide-remote-worktree--operation-request operation)
      (user-error "This Worktree operation already has an active control request"))
    (when (plist-get (claude-code-ide-remote-worktree--operation-results operation) :view-request)
      (user-error "This Worktree operation already has an active Project-view request"))
    (when (eq (claude-code-ide-remote-worktree--operation-state operation) 'observing)
      (claude-code-ide-remote-worktree--transition operation 'observation-stopped))
    (claude-code-ide-remote-worktree--transition operation 'checking)
    (unless polling
      (when-let* ((timer (claude-code-ide-remote-worktree--operation-timer operation)))
        (cancel-timer timer)
        (setf (claude-code-ide-remote-worktree--operation-timer operation) nil))
      (cl-incf (claude-code-ide-remote-worktree--operation-generation operation)))
    (condition-case error-data
        (cl-labels
            ((check (evidence)
               (if (not (and (plist-get evidence :stable) (plist-get evidence :terminal)))
                   (funcall publish evidence nil)
                 (claude-code-ide-remote-worktree--read-state
                  operation
                  (lambda (fresh)
                    (claude-code-ide-remote-worktree--read-extra-conditions
                     operation evidence fresh
                     (lambda (checked) (funcall publish evidence checked))))))))
          (if retained
              (check retained)
            (claude-code-ide-remote-worktree--runner-request
             operation "read"
             (lambda (stdout)
               (check (claude-code-ide-remote-worktree--decode-receipts operation stdout))))))
      (error (claude-code-ide-remote-worktree--fail operation (error-message-string error-data))))
    operation-id))

;;;###autoload
(defun claude-code-ide-remote-worktree-check-outcome (operation-id)
  "Read OPERATION-ID's outcome without mutation, cleanup, or retry."
  (interactive (list (claude-code-ide-remote-worktree--select-operation)))
  (claude-code-ide-remote-worktree--check-operation operation-id))

(defun claude-code-ide-remote-worktree--retry-source (operation)
  "Return OPERATION's eligible terminal attempt, including after a declined retry."
  (when operation
    (if (eq (claude-code-ide-remote-worktree--operation-state operation) 'confirmed-unfinished)
        operation
      (when (memq (claude-code-ide-remote-worktree--operation-state operation)
                  '(refused canceled-before-dispatch))
        (seq-find
         (lambda (prior)
           (and (equal (claude-code-ide-remote-worktree--operation-attempt-id prior)
                       (claude-code-ide-remote-worktree--operation-parent-attempt operation))
                (eq (claude-code-ide-remote-worktree--operation-state prior) 'confirmed-unfinished)))
         (plist-get (claude-code-ide-remote-worktree--operation-results operation) :attempts))))))

(defun claude-code-ide-remote-worktree--remaining-plan (operation)
  "Copy only OPERATION's terminally proven unentered suffix, with new step numbers."
  (let* ((result (claude-code-ide-remote-worktree--operation-results operation))
         (evidence (plist-get result :evidence))
         (first (car (plist-get result :retryable)))
         (steps (claude-code-ide-remote-worktree--operation-steps operation))
         (creation (plist-get evidence :creation)))
    (unless (and (eq (plist-get result :outcome) 'confirmed-unfinished)
                 (plist-get evidence :stable) (plist-get evidence :terminal)
                 (integerp first) (> first 0) (<= first (length steps))
                 (cl-every (lambda (step) (not (plist-get step :entered)))
                           (nthcdr (1- first) (plist-get evidence :steps))))
      (user-error "Retry requires a terminal attempt and proven unentered remaining steps"))
    (mapcar
     (lambda (step)
       (setf (plist-get step :step-id) (- (plist-get step :step-id) (1- first)))
       (setq step
             (plist-put step :requires
                        (delq nil
                              (mapcar
                               (lambda (dependency)
                                 (if (>= dependency first)
                                     (- dependency (1- first))
                                   (unless (memq dependency (plist-get result :verified))
                                     (user-error "A retry dependency has no verified completion"))
                                   nil))
                               (plist-get step :requires)))))
       (when (and (eq (plist-get step :cwd) :created) creation)
         (setf (plist-get step :cwd) (cdr (assoc "directory" creation))))
       (when creation
         (setf (plist-get step :preconditions)
               (mapcar
                (lambda (condition)
                  (if (eq (plist-get condition :kind) 'creation)
                      (list :kind 'worktree :path (cdr (assoc "directory" creation))
                            :branch (cdr (assoc "branch" creation)))
                    condition))
                (plist-get step :preconditions))))
       (when (plist-get step :merge-cleanup)
         (unless (plist-get evidence :landing)
           (user-error "Cleanup retry requires the predecessor's owned landing receipt"))
         (setf (plist-get step :preconditions)
               (claude-code-ide-remote-worktree--cleanup-preconditions step evidence)
               (plist-get step :postconditions)
               (mapcar
                (lambda (condition)
                  (if (and (eq (plist-get condition :kind) 'branch-policy)
                           (not (plist-get condition :oid)))
                      (plist-put condition :oid (cdr (assoc "source-oid" (plist-get evidence :landing))))
                    condition))
                (plist-get step :postconditions)))
         (cl-remf step :merge-cleanup))
       step)
     (copy-tree (nthcdr (1- first) steps)))))

(defun claude-code-ide-remote-worktree--retry-ready (predecessor)
  "Prepare and confirm a new remaining-step attempt after fresh PREDECESSOR proof."
  (let (operation)
    (condition-case error-data
        (let* ((steps (claude-code-ide-remote-worktree--remaining-plan predecessor))
               (old-snapshot (claude-code-ide-remote-worktree--operation-snapshot predecessor))
               (old-results (claude-code-ide-remote-worktree--operation-results predecessor))
               (results (list :attempts (cons predecessor (plist-get old-results :attempts)))))
          (dolist (key '(:attachment :view))
            (when-let* ((value (plist-get old-results key)))
              (setq results (plist-put results key value))))
          (setq operation (copy-claude-code-ide-remote-worktree--operation predecessor))
          (setf (claude-code-ide-remote-worktree--operation-attempt-id operation)
                (claude-code-ide-remote-worktree--token)
                (claude-code-ide-remote-worktree--operation-parent-attempt operation)
                (claude-code-ide-remote-worktree--operation-attempt-id predecessor)
                (claude-code-ide-remote-worktree--operation-steps operation) steps
                (claude-code-ide-remote-worktree--operation-state operation) 'preparing
                (claude-code-ide-remote-worktree--operation-observation operation) 'stopped
                (claude-code-ide-remote-worktree--operation-results operation) results
                (claude-code-ide-remote-worktree--operation-approval operation) nil
                (claude-code-ide-remote-worktree--operation-receipt-directory operation) nil
                (claude-code-ide-remote-worktree--operation-error operation) nil
                (claude-code-ide-remote-worktree--operation-request operation) nil
                (claude-code-ide-remote-worktree--operation-timer operation) nil)
          (puthash (claude-code-ide-remote-worktree--operation-id operation)
                   operation claude-code-ide-remote-worktree--operations)
          (claude-code-ide-remote-worktree--refresh-results operation)
          (claude-code-ide-remote-worktree--prepare
           operation
           (lambda (snapshot)
             (dolist (key '(:repository :worktree))
               (unless (equal (plist-get old-snapshot key) (plist-get snapshot key))
                 (user-error "The retry target identity changed during preparation")))
             (unless (equal
                      (or (plist-get (claude-code-ide-remote-worktree--operation-options operation) :backend)
                          (plist-get (plist-get old-snapshot :settings) :backend))
                      (or (plist-get (claude-code-ide-remote-worktree--operation-options operation) :backend)
                          (plist-get (plist-get snapshot :settings) :backend)))
               (user-error "The selected retry backend changed during preparation"))
             (dolist (tool (plist-get old-snapshot :tools))
               (when (seq-some (lambda (step) (equal (plist-get step :program) (cdr tool))) steps)
                 (unless (equal (cdr tool) (alist-get (car tool) (plist-get snapshot :tools)))
                   (user-error "A retry executable changed during preparation"))))
             (let ((merged (copy-sequence old-snapshot)) (fields snapshot))
               (while fields
                 (let ((key (pop fields)) (value (pop fields)))
                   (setq merged (plist-put merged key value))))
               (when-let* ((launch (copy-tree (plist-get merged :launch)))
                           (bootstrap (seq-find (lambda (step) (eq (plist-get step :kind) 'bootstrap)) steps)))
                 (setq launch (plist-put launch :directory (plist-get bootstrap :cwd))
                       launch (plist-put launch :bootstrap-token
                                         (claude-code-ide-remote-worktree--operation-attempt-id operation))
                       merged (plist-put merged :launch launch)))
               (setf (claude-code-ide-remote-worktree--operation-snapshot operation) merged))
             (claude-code-ide-remote-worktree--read-state
              operation
              (lambda (fresh)
                (claude-code-ide-remote-worktree--read-extra-conditions
                 operation (plist-get old-results :evidence) fresh
                 (lambda (checked)
                   (unless (eq (alist-get
                                1 (plist-get
                                   (claude-code-ide-remote-worktree--evaluate-conditions
                                    operation (plist-get old-results :evidence) checked)
                                   :preconditions)) t)
                     (user-error "The remaining step no longer satisfies its prerequisites"))
                   (claude-code-ide-remote-worktree--admit
                    operation
                    (lambda (approved)
                      (claude-code-ide-remote-worktree--stage
                       approved
                       (lambda (staged)
                         (claude-code-ide-remote-worktree--dispatch
                          staged
                          (lambda (submitted)
                            (claude-code-ide-remote-worktree--observe
                             submitted #'claude-code-ide-remote-worktree--finish))))))))))))))
      (error
       (if operation
           (claude-code-ide-remote-worktree--fail operation (error-message-string error-data))
         (setf (claude-code-ide-remote-worktree--operation-error predecessor)
               (format "Retry unavailable: %s" (error-message-string error-data)))
         (claude-code-ide-remote-worktree--refresh-results predecessor))))))

;;;###autoload
(defun claude-code-ide-remote-worktree-retry-remaining (operation-id)
  "Recheck OPERATION-ID, then seek fresh approval for its unentered remaining work."
  (interactive (list (claude-code-ide-remote-worktree--select-operation)))
  (let* ((current (gethash operation-id claude-code-ide-remote-worktree--operations))
         (source (claude-code-ide-remote-worktree--retry-source current)))
    (unless (and source (not (claude-code-ide-remote-worktree--operation-request current))
                 (not (claude-code-ide-remote-worktree--operation-timer current)))
      (user-error "This operation has no eligible terminal attempt available for retry"))
    (unless (eq source current)
      (let ((restored (copy-claude-code-ide-remote-worktree--operation source)))
        (setf (claude-code-ide-remote-worktree--operation-results restored)
              (plist-put (copy-sequence (claude-code-ide-remote-worktree--operation-results source))
                         :attempts
                         (cons current
                               (remq source (copy-sequence
                                             (plist-get
                                              (claude-code-ide-remote-worktree--operation-results current)
                                              :attempts))))))
        (puthash operation-id restored claude-code-ide-remote-worktree--operations)))
    (claude-code-ide-remote-worktree--check-operation
     operation-id #'claude-code-ide-remote-worktree--retry-ready)))

;;;###autoload
(defun claude-code-ide-remote-worktree-recover-view (operation-id &optional release)
  "Open OPERATION-ID's retained Project view.
RELEASE permits normal completion to release its unused receipt resource.
Never start an Agent or replay a remote mutation."
  (interactive (list (claude-code-ide-remote-worktree--select-operation)))
  (let* ((operation (gethash operation-id claude-code-ide-remote-worktree--operations))
         (result (and operation (claude-code-ide-remote-worktree--operation-results operation)))
         (target (plist-get result :view-target))
         (frame (selected-frame))
         (window (selected-window))
         (origin (window-buffer window))
         (attempt (and operation (claude-code-ide-remote-worktree--operation-attempt-id operation)))
         (generation (and operation (claude-code-ide-remote-worktree--operation-generation operation)))
         (targets (list target)))
    (unless target
      (user-error "Check outcome to identify a surviving Worktree before view recovery"))
    (when (or (plist-get result :view-request)
              (claude-code-ide-remote-worktree--operation-request operation)
              (claude-code-ide-remote-worktree--operation-timer operation))
      (user-error "Wait for the active Worktree request before view recovery"))
    (cl-labels
        ((failed (diagnostic)
           (claude-code-ide-remote-worktree--local-result
            operation :view (list :status 'failed :error diagnostic))
           (when release (claude-code-ide-remote-worktree--release operation)))
         (open-next (&optional _operation)
           (when (claude-code-ide-remote-worktree--current-p operation attempt generation)
             (if (null targets)
                 (when release (claude-code-ide-remote-worktree--release operation))
               (let ((next (pop targets)) finished request)
                 (setq request
                       (claude-code-ide-remote-project-open-target
                        (plist-get next :host) (plist-get next :directory)
                        (lambda (outcome)
                          (setq finished t)
                          (when (claude-code-ide-remote-worktree--current-p operation attempt generation)
                            (setf (claude-code-ide-remote-worktree--operation-results operation)
                                  (plist-put (claude-code-ide-remote-worktree--operation-results operation)
                                             :view-request nil))
                            (when (equal next target)
                              (claude-code-ide-remote-worktree--local-result operation :view outcome)
                              (when (and (eq (plist-get outcome :status) 'completed)
                                         (buffer-live-p (plist-get outcome :buffer))
                                         (frame-live-p frame) (eq frame (selected-frame))
                                         (window-live-p window) (eq window (selected-window))
                                         (eq origin (window-buffer window)))
                                (set-window-buffer window (plist-get outcome :buffer))))
                            (when (and (not (equal next target))
                                       (not (eq (plist-get outcome :status) 'completed)))
                              (claude-code-ide-remote-worktree--local-result operation :view outcome))
                            (open-next)))
                        'worktree-recovery
                        (lambda ()
                          (when (claude-code-ide-remote-worktree--current-p operation attempt generation)
                            (claude-code-ide-remote-worktree-cancel-observation operation-id)))))
                 (unless finished
                   (setf (claude-code-ide-remote-worktree--operation-results operation)
                         (plist-put (claude-code-ide-remote-worktree--operation-results operation)
                                    :view-request request))))))))
      (condition-case error-data
          (progn
            (unless (require 'claude-code-ide-remote-project nil t)
              (user-error "The optional remote Project-view package is unavailable"))
            (when-let* ((surviving (plist-get (plist-get result :reconciliation) :surviving)))
              (dolist (buffer (buffer-list))
                (with-current-buffer buffer
                  (when (and (memq major-mode '(magit-status-mode dired-mode))
                             (not (buffer-modified-p)) (not buffer-file-name)
                             (not (get-buffer-process buffer)))
                    (when-let* ((other (ignore-errors
                                         (claude-code-ide-remote-worktree-target-for-file default-directory))))
                      (setf (plist-get other :directory)
                            (directory-file-name (plist-get other :directory)))
                      (when (and (equal (plist-get other :host) (plist-get target :host))
                                 (seq-find (lambda (entry)
                                             (equal (plist-get entry :path) (plist-get other :directory)))
                                           surviving)
                                 (not (member other targets)))
                        (setq targets (append targets (list other)))))))))
            (claude-code-ide-remote-worktree--local-result operation :view '(:status opening))
            (if-let* ((snapshot (plist-get result :view-snapshot)))
                (claude-code-ide-remote-worktree--prepare-backend
                 operation #'open-next (copy-tree snapshot) #'failed)
              (open-next)))
        (error (failed (error-message-string error-data)))))
    operation-id))

;;;###autoload
(defun claude-code-ide-remote-worktree-recover-attachment (operation-id)
  "Attach to OPERATION-ID's retained Agent without launching a replacement."
  (interactive (list (claude-code-ide-remote-worktree--select-operation)))
  (let* ((operation (gethash operation-id claude-code-ide-remote-worktree--operations))
         (target (and operation
                      (plist-get (claude-code-ide-remote-worktree--operation-results operation) :attachment-target))))
    (unless target (user-error "Check outcome to identify an existing Agent before attachment recovery"))
    (when (or (claude-code-ide-remote-worktree--operation-request operation)
              (claude-code-ide-remote-worktree--operation-timer operation))
      (user-error "Wait for the active Worktree request before attachment recovery"))
    (setf (claude-code-ide-remote-worktree--operation-display-context operation)
          (list :frame (selected-frame) :window (selected-window) :buffer (current-buffer)))
    (if (or (claude-code-ide-remote-worktree--operation-receipt-directory operation)
            (plist-get (claude-code-ide-remote-worktree--operation-results operation) :retained-evidence))
        (claude-code-ide-remote-worktree--check-operation
         operation-id
         (lambda (checked)
           (if-let* ((current-target (plist-get
                                      (claude-code-ide-remote-worktree--operation-results checked)
                                      :attachment-target)))
               (when (claude-code-ide-remote-worktree--display-current-p checked)
                 (claude-code-ide-remote-worktree--attach checked current-target))
             (claude-code-ide-remote-worktree--local-result
              checked :attachment '(:status unavailable :error "The owned Agent is no longer verified")))))
      (claude-code-ide-remote-worktree--attach operation target))
    operation-id))

(defun claude-code-ide-remote-worktree--recover-selected-attachment ()
  "Attach to the selected operation's retained Agent."
  (interactive)
  (claude-code-ide-remote-worktree-recover-attachment claude-code-ide-remote-worktree--selected-operation))

(defun claude-code-ide-remote-worktree--recover-selected-view ()
  "Recover the selected operation's local Project view."
  (interactive)
  (claude-code-ide-remote-worktree-recover-view claude-code-ide-remote-worktree--selected-operation))

(defun claude-code-ide-remote-worktree--retry-selected ()
  "Request explicit retry for the selected operation."
  (interactive)
  (claude-code-ide-remote-worktree-retry-remaining
   claude-code-ide-remote-worktree--selected-operation))

(defun claude-code-ide-remote-worktree--display-text (value)
  "Return VALUE as plain text without terminal controls."
  (let ((ansi-color-context nil))
    (replace-regexp-in-string
     "[\0-\10\13-\37\177-\237]"
     "" (ansi-color-filter-apply (substring-no-properties (format "%s" (or value "")))) t t)))

(defun claude-code-ide-remote-worktree--check-selected ()
  "Check the selected operation without another operation prompt."
  (interactive)
  (unless claude-code-ide-remote-worktree--selected-operation
    (user-error "Select a Worktree operation first"))
  (claude-code-ide-remote-worktree-check-outcome claude-code-ide-remote-worktree--selected-operation))

(defun claude-code-ide-remote-worktree--cancel-selected ()
  "Cancel only the selected operation's local observation."
  (interactive)
  (when (gethash claude-code-ide-remote-worktree--selected-operation
                 claude-code-ide-remote-worktree--operations)
    (claude-code-ide-remote-worktree-cancel-observation
     claude-code-ide-remote-worktree--selected-operation)))

(defun claude-code-ide-remote-worktree--results-killed ()
  "Stop observation without removing the selected operation record."
  (when (eq (current-buffer) claude-code-ide-remote-worktree--results-buffer)
    (setq claude-code-ide-remote-worktree--results-buffer nil)
    (claude-code-ide-remote-worktree--cancel-selected)))

(defun claude-code-ide-remote-worktree--results-visibility-changed (_frame)
  "Stop observation when the last results window closes or changes its buffer."
  (when (buffer-live-p claude-code-ide-remote-worktree--results-buffer)
    (with-current-buffer claude-code-ide-remote-worktree--results-buffer
      (let ((visible (and (get-buffer-window (current-buffer) t) t))
            (previous claude-code-ide-remote-worktree--results-visible))
        (setq claude-code-ide-remote-worktree--results-visible visible)
        (when (and previous (not visible))
          (claude-code-ide-remote-worktree--cancel-selected))))))

(add-hook 'window-buffer-change-functions
          #'claude-code-ide-remote-worktree--results-visibility-changed)

(defun claude-code-ide-remote-worktree--close-results ()
  "Close the results view and stop its selected observation."
  (interactive)
  (setq claude-code-ide-remote-worktree--results-visible nil)
  (claude-code-ide-remote-worktree--cancel-selected)
  (quit-window))

(defvar claude-code-ide-remote-worktree-results-mode-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "a") #'claude-code-ide-remote-worktree--recover-selected-attachment)
    (define-key map (kbd "c") #'claude-code-ide-remote-worktree--cancel-selected)
    (define-key map (kbd "v") #'claude-code-ide-remote-worktree--recover-selected-view)
    (define-key map (kbd "g") #'claude-code-ide-remote-worktree--check-selected)
    (define-key map (kbd "r") #'claude-code-ide-remote-worktree--retry-selected)
    (define-key map (kbd "s") #'claude-code-ide-remote-worktree-show)
    (define-key map (kbd "q") #'claude-code-ide-remote-worktree--close-results)
    map)
  "Local keys for retained Worktree results.")

(define-derived-mode claude-code-ide-remote-worktree-results-mode special-mode "Worktree Results"
  "Show retained Worktree results without implicit remote requests."
  (add-hook 'kill-buffer-hook #'claude-code-ide-remote-worktree--results-killed nil t)
  (setq-local truncate-lines nil)
  (setq-local bidi-display-reordering nil)
  (setq-local header-line-format "g: Check  c: Cancel  r: Retry  a: Attach  v: View  s: Select  q: Close")
  (setq-local revert-buffer-function
              (lambda (&rest _)
                (when-let* ((operation (gethash claude-code-ide-remote-worktree--selected-operation
                                                claude-code-ide-remote-worktree--operations)))
                  (claude-code-ide-remote-worktree--refresh-results operation)))))

(with-eval-after-load 'evil
  (evil-set-initial-state 'claude-code-ide-remote-worktree-results-mode 'emacs))

(defun claude-code-ide-remote-worktree--refresh-results (operation)
  "Refresh an existing selected view of OPERATION without display or remote I/O."
  (when (and (eq operation (gethash (claude-code-ide-remote-worktree--operation-id operation)
                                    claude-code-ide-remote-worktree--operations))
             (buffer-live-p claude-code-ide-remote-worktree--results-buffer))
    (with-current-buffer claude-code-ide-remote-worktree--results-buffer
      (when (equal claude-code-ide-remote-worktree--selected-operation
                   (claude-code-ide-remote-worktree--operation-id operation))
        (let* ((inhibit-read-only t)
               (position (point))
               (target (claude-code-ide-remote-worktree--operation-target operation))
               (snapshot (claude-code-ide-remote-worktree--operation-snapshot operation))
               (result (claude-code-ide-remote-worktree--operation-results operation))
               (state (claude-code-ide-remote-worktree--operation-state operation))
               (receipts (plist-get result :steps))
               (backend (or (plist-get (claude-code-ide-remote-worktree--operation-options operation) :backend)
                            (plist-get (plist-get snapshot :settings) :backend))))
          (erase-buffer)
          (insert (propertize "Remote Worktree results\n" 'face 'bold))
          (dolist (field (list
                          (cons "Host" (plist-get target :host))
                          (cons "Action" (claude-code-ide-remote-worktree--operation-kind operation))
                          (cons "Target" (plist-get target :directory))
                          (cons "Repository" (or (plist-get snapshot :repository) "Not resolved"))
                          (cons "Backend" (or backend "Not selected"))
                          (cons "Operation" (claude-code-ide-remote-worktree--operation-id operation))
                          (cons "Attempt" (claude-code-ide-remote-worktree--operation-attempt-id operation))
                          (cons "State" state)))
            (insert (car field) ": " (claude-code-ide-remote-worktree--display-text (cdr field)) "\n"))
          (insert "\n"
                  (pcase state
                    ('observation-stopped "Observation stopped. Submitted remote work can still run.")
                    ('canceled-before-dispatch "Canceled before dispatch. No remote mutation started.")
                    ('unknown "The overall outcome is unknown. Read the step evidence. Check outcome before recovery. Retry is unavailable.")
                    ('partial "Some work completed. Preserve it. Inspect the remaining step results before recovery.")
                    ('confirmed-unfinished "A terminal attempt left proven unentered work. Retry requires fresh approval.")
                    ('completed "The request completed. Attachment and Project-view results are separate.")
                    ('refused "The request was refused before mutation.")
                    ('failed "The request failed. Read the recorded step evidence.")
                    ('checking "The read-only outcome check is active.")
                    (_ "The operation is pending. Remote work has no fixed execution deadline."))
                  "\n\nRemote steps\n")
          (if (not (claude-code-ide-remote-worktree--operation-steps operation))
              (insert "No remote mutation plan is recorded.\n")
            (dolist (plan (claude-code-ide-remote-worktree--operation-steps operation))
              (let* ((step (pop receipts))
                     (status (plist-get step :exit-code)))
                (insert (format "%2d  %-16s %-12s%s\n"
                                (plist-get plan :step-id) (plist-get plan :kind)
                                (or (plist-get step :outcome) 'not-observed)
                                (if (integerp status) (format " (exit %d)" status) ""))))))
          (insert "\nLocal continuation\n")
          (when-let* ((view-target (plist-get result :view-target)))
            (insert "Recovery Worktree: "
                    (claude-code-ide-remote-worktree--display-text (plist-get view-target :directory)) "\n"))
          (dolist (entry (plist-get (plist-get result :reconciliation) :retained))
            (insert "Retained unavailable view: "
                    (claude-code-ide-remote-worktree--display-text (plist-get entry :path))
                    " (" (symbol-name (plist-get entry :reason)) ")\n"))
          (dolist (stage '(:attachment :view))
            (let ((outcome (plist-get result stage)))
              (insert (if (eq stage :attachment) "Terminal attachment: " "Project view: ")
                      (claude-code-ide-remote-worktree--display-text
                       (or (plist-get outcome :status) 'not-requested)) "\n")
              (when-let* ((error-text (plist-get outcome :error)))
                (insert "  " (claude-code-ide-remote-worktree--display-text error-text) "\n"))))
          (when-let* ((attempts (plist-get result :attempts)))
            (insert "\nPrevious attempts (retained, never replayed)\n")
            (dolist (prior attempts)
              (insert (format "%s  %s  verified steps: %S\n"
                              (claude-code-ide-remote-worktree--operation-attempt-id prior)
                              (claude-code-ide-remote-worktree--operation-state prior)
                              (plist-get (claude-code-ide-remote-worktree--operation-results prior) :verified)))
              (when-let* ((resource (claude-code-ide-remote-worktree--operation-receipt-directory prior)))
                (insert "  " (claude-code-ide-remote-worktree--display-text resource) "\n"))))
          (when-let* ((error-text (claude-code-ide-remote-worktree--operation-error operation)))
            (insert "\n" (claude-code-ide-remote-worktree--display-text error-text) "\n"))
          (when-let* ((status (plist-get result :resource-status)))
            (insert "\nResource release: " (symbol-name status) "\n")
            (when-let* ((diagnostic (plist-get result :resource-error)))
              (insert (claude-code-ide-remote-worktree--display-text diagnostic) "\n")))
          (when-let* ((resource (claude-code-ide-remote-worktree--operation-receipt-directory operation)))
            (insert "\nExact remote resource: " (claude-code-ide-remote-worktree--display-text resource) "\n"))
          (when (eq backend 'wt)
            (insert "\nWorktrunk hook approval stays with the remote backend.\n"
                    "On the captured host, run wt config approvals add.\n"
                    "Worktrunk 0.34 uses wt hook approvals add instead.\n"
                    "This workflow does not add approval or hook-bypass flags.\n"))
          (when-let* ((diagnostics (plist-get (plist-get result :evidence) :diagnostics)))
            (insert "\nDiagnostics (first 64 KiB per file)\n")
            (dolist (diagnostic diagnostics)
              (unless (string-empty-p (cdr diagnostic))
                (insert "\n" (car diagnostic) ":\n"
                        (claude-code-ide-remote-worktree--display-text (cdr diagnostic)) "\n"))))
          (insert "\n")
          (when (or (memq state '(preparing awaiting-confirmation dispatching observing checking still-running))
                    (claude-code-ide-remote-worktree--operation-request operation)
                    (claude-code-ide-remote-worktree--operation-timer operation)
                    (plist-get result :view-request))
            (insert-text-button "Cancel observation (c)" 'follow-link t
                                'action (lambda (_) (claude-code-ide-remote-worktree--cancel-selected)))
            (insert "    "))
          (when (and (or (claude-code-ide-remote-worktree--operation-receipt-directory operation)
                         (plist-get result :retained-evidence))
                     (memq state '(observing observation-stopped unknown partial completed failed
                                             still-running confirmed-unfinished))
                     (not (claude-code-ide-remote-worktree--operation-request operation)))
            (insert-text-button "Check outcome (g)"
                                'follow-link t
                                'action (lambda (_) (claude-code-ide-remote-worktree--check-selected)))
            (insert "    "))
          (when (and (claude-code-ide-remote-worktree--retry-source operation)
                     (not (claude-code-ide-remote-worktree--operation-request operation))
                     (not (claude-code-ide-remote-worktree--operation-timer operation)))
            (insert-text-button "Retry remaining (r)" 'follow-link t
                                'action (lambda (_) (claude-code-ide-remote-worktree--retry-selected)))
            (insert "    "))
          (when (and (plist-get result :attachment-target)
                     (not (claude-code-ide-remote-worktree--operation-request operation))
                     (not (claude-code-ide-remote-worktree--operation-timer operation)))
            (insert-text-button "Attach existing Agent (a)" 'follow-link t
                                'action (lambda (_) (claude-code-ide-remote-worktree--recover-selected-attachment)))
            (insert "    "))
          (when (and (plist-get result :view-target)
                     (not (plist-get result :view-request))
                     (not (claude-code-ide-remote-worktree--operation-request operation)))
            (insert-text-button "Open Project view (v)" 'follow-link t
                                'action (lambda (_) (claude-code-ide-remote-worktree--recover-selected-view)))
            (insert "    "))
          (insert-text-button "Select operation (s)" 'follow-link t
                              'action (lambda (_) (claude-code-ide-remote-worktree-show)))
          (insert "    ")
          (insert-text-button "Close (q)" 'follow-link t
                              'action (lambda (_) (claude-code-ide-remote-worktree--close-results)))
          (insert "\n")
          (set-buffer-modified-p nil)
          (goto-char (min position (point-max))))))))

(defun claude-code-ide-remote-worktree--local-result (operation stage outcome)
  "Store OPERATION's independent local STAGE OUTCOME and refresh its existing view."
  (unless (memq stage '(:attachment :view))
    (error "Unsupported local Worktree result stage: %S" stage))
  (setf (claude-code-ide-remote-worktree--operation-results operation)
        (plist-put (claude-code-ide-remote-worktree--operation-results operation) stage outcome))
  (claude-code-ide-remote-worktree--refresh-results operation))

(defun claude-code-ide-remote-worktree--results-buffer-for (operation)
  "Prepare OPERATION's local results buffer without selecting a window."
  (unless (buffer-live-p claude-code-ide-remote-worktree--results-buffer)
    (setq claude-code-ide-remote-worktree--results-buffer
          (generate-new-buffer "*Remote Worktree results*"))
    (with-current-buffer claude-code-ide-remote-worktree--results-buffer
      (claude-code-ide-remote-worktree-results-mode)))
  (with-current-buffer claude-code-ide-remote-worktree--results-buffer
    (setq claude-code-ide-remote-worktree--selected-operation
          (claude-code-ide-remote-worktree--operation-id operation))
    (claude-code-ide-remote-worktree--refresh-results operation)
    (goto-char (point-min)))
  claude-code-ide-remote-worktree--results-buffer)

(defun claude-code-ide-remote-worktree--present-results (operation &optional notify)
  "Expose OPERATION locally without replacing another result or changing focus."
  (claude-code-ide-remote-worktree--refresh-results operation)
  (when (and (not noninteractive)
             (claude-code-ide-remote-worktree--operation-display-context operation)
             (eq operation (gethash (claude-code-ide-remote-worktree--operation-id operation)
                                    claude-code-ide-remote-worktree--operations)))
    (when (and (claude-code-ide-remote-worktree--display-current-p operation)
               (or (not (buffer-live-p claude-code-ide-remote-worktree--results-buffer))
                   (and (not (get-buffer-window claude-code-ide-remote-worktree--results-buffer t))
                        (with-current-buffer claude-code-ide-remote-worktree--results-buffer
                          (equal claude-code-ide-remote-worktree--selected-operation
                                 (claude-code-ide-remote-worktree--operation-id operation))))))
      (when (display-buffer
             (claude-code-ide-remote-worktree--results-buffer-for operation)
             '(display-buffer-pop-up-window (inhibit-same-window . t)))
        (with-current-buffer claude-code-ide-remote-worktree--results-buffer
          (setq claude-code-ide-remote-worktree--results-visible t))))
    (when (and notify
               (memq (claude-code-ide-remote-worktree--operation-state operation)
                     '(preparing refused failed unknown partial completed confirmed-unfinished)))
      (let ((target (claude-code-ide-remote-worktree--operation-target operation)))
        (message "Host %s: %s %s is %s [%s]. Use M-x claude-code-ide-remote-worktree-show for results."
                 (claude-code-ide-remote-worktree--display-text (plist-get target :host))
                 (claude-code-ide-remote-worktree--operation-kind operation)
                 (claude-code-ide-remote-worktree--display-text (plist-get target :directory))
                 (claude-code-ide-remote-worktree--operation-state operation)
                 (claude-code-ide-remote-worktree--operation-id operation))))))

;;;###autoload
(defun claude-code-ide-remote-worktree-show (&optional operation-id)
  "Display retained OPERATION-ID, or select one locally.  Make no remote request."
  (interactive)
  (let ((operation (gethash (or operation-id (claude-code-ide-remote-worktree--select-operation))
                            claude-code-ide-remote-worktree--operations)))
    (unless operation (user-error "The Worktree operation is not retained"))
    (pop-to-buffer (claude-code-ide-remote-worktree--results-buffer-for operation))
    (with-current-buffer claude-code-ide-remote-worktree--results-buffer
      (setq claude-code-ide-remote-worktree--results-visible t))
    claude-code-ide-remote-worktree--results-buffer))

;;; Native capture

(defvar magit-credential-hook)
(defvar magit--refresh-cache)
(defvar magit-git-debug)

(declare-function magit-worktree-move "magit-worktree" (worktree directory))
(declare-function magit-call-git "magit-process" (&rest args))
(declare-function magit-run-git-async "magit-process" (&rest args))
(declare-function magit-process-git "magit-process" (destination &rest args))
(declare-function magit-list-worktrees "magit-worktree" ())
(declare-function magit-section-value-if "magit-section" (values))
(declare-function magit-completing-read "magit-git"
                  (prompt collection &optional predicate require-match
                          initial-input hist def))
(declare-function magit-push-arguments "magit-push" ())

;; Not `define-error' with its default `error' parent: a generic
;; `(condition-case _ BODY (error ...))' anywhere between the native
;; executor and `claude-code-ide-remote-worktree--capture-native' must
;; never swallow this as an ordinary failure.
(put 'claude-code-ide-remote-worktree--captured
     'error-conditions '(claude-code-ide-remote-worktree--captured))
(put 'claude-code-ide-remote-worktree--captured
     'error-message "Native Git command captured")

(defvar claude-code-ide-remote-worktree--capture-scope nil
  "List of (THREAD TOKEN OPERATION) naming the exact extent of one
native capture call.  Only the shared executor advice, the
`file-directory-p' advice, and the low-level Git read advice below
consult this.  Every other call, local or remote, keeps its native
execution path unaffected.")

(defun claude-code-ide-remote-worktree--capture-scope-p ()
  "Return non-nil only inside the thread and call that owns the
current native capture scope."
  (and claude-code-ide-remote-worktree--capture-scope
       (eq (nth 0 claude-code-ide-remote-worktree--capture-scope) (current-thread))))

(defun claude-code-ide-remote-worktree--capture-operation ()
  "Return the operation owning the current native capture scope."
  (nth 2 claude-code-ide-remote-worktree--capture-scope))

(defun claude-code-ide-remote-worktree--capture-executor (orig-fn &rest args)
  "Shared :around advice for `magit-call-git' and `magit-run-git-async'.
Exit through the private capture condition instead of starting a
process while the current thread owns a native capture scope.  Every
other call, local or remote, keeps its exact original execution and
never enters this branch."
  (if (claude-code-ide-remote-worktree--capture-scope-p)
      (signal 'claude-code-ide-remote-worktree--captured
              (cons (nth 1 claude-code-ide-remote-worktree--capture-scope)
                    (flatten-tree args)))
    (apply orig-fn args)))

(defun claude-code-ide-remote-worktree--capture-prompt (original &rest args)
  "Refuse a preparatory prompt inside native capture without opening a minibuffer."
  (if (claude-code-ide-remote-worktree--capture-scope-p)
      (user-error "Select an explicit push target before starting native capture")
    (apply original args)))

(defun claude-code-ide-remote-worktree--capture-native (operation thunk)
  "Run THUNK against OPERATION's target and return the literal Git argv
it captured.  THUNK must reach `magit-call-git' or `magit-run-git-async'
through the scoped executor advice above; no native process or native
cleanup ever runs, and THUNK's own local credential hook is suppressed
for this extent."
  (let* ((token (claude-code-ide-remote-worktree--token))
         (claude-code-ide-remote-worktree--capture-scope
          (list (current-thread) token operation))
         (magit-credential-hook nil))
    (condition-case error-data
        (progn
          (funcall thunk)
          (user-error "The native Magit command completed without a Git command to capture"))
      (claude-code-ide-remote-worktree--captured
       (pcase-let ((`(,_symbol ,got-token . ,argv) error-data))
         (unless (eq got-token token)
           (user-error "The native Git capture token does not match the active request"))
         (unless (and (consp argv) (proper-list-p argv)
                      (cl-every #'claude-code-ide-remote-worktree--literal-p argv))
           (user-error "The captured native Git command is not a literal argument list"))
         argv)))))

(defun claude-code-ide-remote-worktree--bounded-read (operation purpose program argv)
  "Run one bounded control read for OPERATION and return its stdout.
Let the editor event loop start the control request.  The capture
worker waits without processing editor timers or process callbacks."
  (let* ((attempt (claude-code-ide-remote-worktree--operation-attempt-id operation))
         (generation (claude-code-ide-remote-worktree--operation-generation operation))
         (mutex (make-mutex "cci-native-read"))
         (wake (make-condition-variable mutex "cci-native-read"))
         done result
         (failed (lambda (diagnostic)
                   (with-mutex mutex
                     (setq result (cons :error diagnostic) done t)
                     (condition-notify wake))))
         (timer (run-at-time 0.05 0.05
                             (lambda () (with-mutex mutex (condition-notify wake))))))
    (unwind-protect
        (progn
          (run-at-time
           0 nil
           (lambda ()
             (condition-case error-data
                 (if (claude-code-ide-remote-worktree--current-p operation attempt generation)
                     (claude-code-ide-remote-worktree--control
                      operation purpose program argv
                      (lambda (stdout)
                        (with-mutex mutex
                          (setq result (cons :ok stdout) done t)
                          (condition-notify wake)))
                      nil nil failed)
                   (funcall failed "The remote Worktree operation is no longer current"))
               (error (funcall failed (error-message-string error-data))))))
          (with-mutex mutex
            (while (and (not done)
                        (claude-code-ide-remote-worktree--current-p operation attempt generation))
              (condition-wait wake))
            (cond
             ((not done) (user-error "The remote Worktree operation is no longer current"))
             ((eq (car result) :ok) (cdr result))
             (t (user-error "%s" (cdr result))))))
      (cancel-timer timer))))

(defconst claude-code-ide-remote-worktree--directory-p-script
  "if [ -d \"$1\" ]; then printf yes; else printf no; fi"
  "Print \"yes\" or \"no\" for whether $1 is a directory.  Always exits 0
so a control request never treats a plain \"no\" as a request failure.")

(defun claude-code-ide-remote-worktree--capture-directory-p (operation directory)
  "Return non-nil when DIRECTORY exists on OPERATION's host as a
directory.  Check with one bounded control read instead of a raw
Tramp file operation."
  (equal
   (claude-code-ide-remote-worktree--bounded-read
    operation "native-capture-directory-p" "sh"
    (list "-c" claude-code-ide-remote-worktree--directory-p-script
          "cci-native-directory-p" directory))
   "yes"))

(defun claude-code-ide-remote-worktree--capture-file-directory-p (orig-fn filename)
  "Redirect FILENAME's directory check through a bounded remote read
while a native capture scope is active and FILENAME names the active
capture's own approved host, so native preparatory queries never touch
Tramp directly and never re-consult global host configuration from a
worker thread.  Every other call, including a local path checked
during capture, keeps its exact original path."
  (let* ((operation (and (claude-code-ide-remote-worktree--capture-scope-p)
                         (claude-code-ide-remote-worktree--capture-operation)))
         (host (and operation
                    (plist-get (claude-code-ide-remote-worktree--operation-target operation)
                               :host)))
         (prefix (and host (format "/rpc:%s:" host))))
    (if (and prefix (string-prefix-p prefix filename))
        (claude-code-ide-remote-worktree--capture-directory-p
         operation (substring filename (length prefix)))
      (funcall orig-fn filename))))

(defconst claude-code-ide-remote-worktree--git-read-script
  "for encoded do decoded=$(printf '%s' \"$encoded\" | base64 -d && printf .) || exit 1; shift; set -- \"$@\" \"${decoded%.}\"; done; export GIT_OPTIONAL_LOCKS=0 GIT_TERMINAL_PROMPT=0 GIT_ASKPASS=/bin/false SSH_ASKPASS=/bin/false SSH_ASKPASS_REQUIRE=never; \"$@\"; printf '\\ncci-git-status:%d\\n' \"$?\""
  "Decode literal query arguments, preserving native format delimiters.
Append a status marker so a nonzero Git status remains query data.
The sentinel preserves trailing newlines during shell substitution.")

(defun claude-code-ide-remote-worktree--parse-git-read (output)
  "Split OUTPUT into (STATUS . STDOUT) using the fixed status marker
`claude-code-ide-remote-worktree--git-read-script' appends."
  (if (string-match "\ncci-git-status:\\([0-9]+\\)\n\\'" output)
      (cons (string-to-number (match-string 1 output))
            (substring output 0 (match-beginning 0)))
    (user-error "The remote Git read response is missing its status marker")))

(defconst claude-code-ide-remote-worktree--safe-git-read-commands
  '("rev-parse" "for-each-ref" "show-ref" "ls-remote" "merge-base"
    "describe" "rev-list" "log")
  "Query subcommands supported during native capture.
The read gate also rejects output files and external diff helpers.
Configuration, remote, and symbolic-ref queries require fixed shapes.")

(defun claude-code-ide-remote-worktree--safe-git-read-p (args)
  "Return non-nil only for a supported read-only Git command in ARGS."
  (and
   (cl-every (lambda (arg) (and (stringp arg) (not (string-match-p "\0" arg)))) args)
   (not (cl-some (lambda (arg)
                   (string-match-p "\\`--\\(?:output\\|ext-diff\\|textconv\\)\\(?:=\\|\\'\\)" arg))
                 args))
   (pcase args
     (`("symbolic-ref" "--short" "HEAD") t)
     (`("remote") t)
     (`("ls-remote" . ,rest)
      (and rest
           (cl-every
            (lambda (arg)
              (or (member arg '("--" "-h" "-t" "-q" "--heads" "--branches"
                                "--tags" "--refs" "--symref" "--quiet" "--exit-code"))
                  (and (not (string-prefix-p "-" arg))
                       (not (string-prefix-p "ext::" arg)))))
            rest)))
     ((or '("config" "--local" "--list") '("config" "--list" "-z")) t)
     (`("config" . ,rest)
      (catch 'unsupported
        (let (query operands)
          (while rest
            (let ((arg (pop rest)))
              (cond
               ((member arg '("--get" "--get-all" "--get-regexp" "--get-urlmatch"))
                (when query (throw 'unsupported nil))
                (setq query t))
               ((member arg '("-z" "--null" "--include" "--includes" "--no-includes"
                              "--local" "--global" "--system" "--worktree"
                              "--bool" "--int" "--bool-or-int" "--path")))
               ((member arg '("--default" "--type"))
                (unless rest (throw 'unsupported nil))
                (pop rest))
               ((string-prefix-p "-" arg) (throw 'unsupported nil))
               (t (push arg operands)))))
          (if query (memq (length operands) '(1 2)) (= (length operands) 1)))))
     (`(,cmd . ,_) (member cmd claude-code-ide-remote-worktree--safe-git-read-commands))
     (_ nil))))

(defun claude-code-ide-remote-worktree--capture-git-read (operation args)
  "Run ARGS as a bounded read-only Git query for OPERATION's host.
Insert its stdout at point and return its exit status, mirroring
`magit-process-git' so the calling Magit read helper parses the
result exactly as it would a local one."
  (let* ((raw (claude-code-ide-remote-worktree--bounded-read
               operation "native-capture-git-read" "sh"
               (append (list "-c" claude-code-ide-remote-worktree--git-read-script
                             "cci-native-git-read")
                       (mapcar (lambda (arg)
                                 (base64-encode-string (encode-coding-string arg 'utf-8-unix) t))
                               (cons "git" args)))))
         (parsed (claude-code-ide-remote-worktree--parse-git-read raw)))
    (insert (cdr parsed))
    (car parsed)))

(defun claude-code-ide-remote-worktree--capture-process-git (orig-fn destination &rest args)
  "Redirect a preparatory synchronous Git read through a bounded
control request while a native capture scope is active.  Only a fixed
allowlist of read-only Git command shapes is supported; every other
shape and every call outside a capture scope keeps its exact original
path."
  (if (not (claude-code-ide-remote-worktree--capture-scope-p))
      (apply orig-fn destination args)
    (let ((flat (flatten-tree args)))
      (unless (claude-code-ide-remote-worktree--safe-git-read-p flat)
        (user-error "Unsupported native Git read during capture: %S" flat))
      (when (consp destination)
        (unless (equal (cdr destination) '(nil))
          (user-error "The native Git read requires an unsupported output destination"))
        (setq destination (car destination)))
      (if destination
          (with-current-buffer (if (eq destination t) (current-buffer)
                                 (get-buffer-create destination))
            (claude-code-ide-remote-worktree--capture-git-read
             (claude-code-ide-remote-worktree--capture-operation) flat))
        (with-temp-buffer
          (claude-code-ide-remote-worktree--capture-git-read
           (claude-code-ide-remote-worktree--capture-operation) flat))))))

(defun claude-code-ide-remote-worktree--prepared-worktree-paths (filename)
  "Return prepared plain Worktree paths for FILENAME's repository, or nil.
Read whichever backend already has a snapshot; never perform I/O."
  (catch 'claude-code-ide-remote-worktree--found
    (dolist (backend '(wt lane))
      (when-let* ((snapshot (claude-code-ide-remote-worktree-snapshot-for-file
                             filename backend)))
        (throw 'claude-code-ide-remote-worktree--found
               (cl-loop for entry in (plist-get snapshot :worktrees)
                        when (and (eq (plist-get entry :exists) t)
                                  (not (plist-get entry :bare))
                                  (not (equal (plist-get entry :path) (plist-get snapshot :main-worktree))))
                        collect (plist-get entry :path)))))))

(defun claude-code-ide-remote-worktree--read-move-args ()
  "Interactive spec for the remote-aware `magit-worktree-move' advice.
Use only the already-prepared snapshot for an approved RPC directory;
never a native Worktree listing or destination directory browser over
Tramp.  An unsupported remote directory fails closed here, before any
native prompt or native capture starts."
  (let ((target (claude-code-ide-remote-worktree-target-for-file default-directory)))
    (if (not target)
        (list (magit-completing-read "Move worktree" (cdr (magit-list-worktrees))
                                     nil t nil nil (magit-section-value-if 'worktree))
              (read-directory-name "Move worktree to: "))
      (let* ((host (plist-get target :host))
             (prefix (format "/rpc:%s:" host))
             (paths (claude-code-ide-remote-worktree--prepared-worktree-paths default-directory)))
        (unless paths
          (user-error "Refresh the remote Worktree listing before moving a worktree"))
        (list (concat prefix (magit-completing-read (format "Move worktree on %s" host) paths nil t))
              (concat prefix (read-string (format "Move Worktree on %s to (absolute remote path): " host))))))))

(defun claude-code-ide-remote-worktree--strip-rpc-prefix (path host)
  "Return PATH's plain remote-side form for HOST.
PATH may already carry the exact \"/rpc:HOST:\" prefix -- the shape
`magit-call-git' always sees for an unchanged native argument -- or
may already be the plain absolute path a native Magit filename
conversion produced for a destination, since `magit--expand-worktree'
passes a remote filename through unmodified but may also normalize
it.  Both shapes name the same approved HOST validated before capture
started."
  (let ((prefix (format "/rpc:%s:" host)))
    (if (string-prefix-p prefix path)
        (substring path (length prefix))
      path)))

(defun claude-code-ide-remote-worktree--spawn-capture (operation directory thunk on-argv)
  "Capture THUNK in a worker, then continue OPERATION on the main thread.
Keep the original buffer, prefix argument, and operation registry.
Use the Project-view worker's NS scheduling and cleanup pattern."
  (let ((attempt (claude-code-ide-remote-worktree--operation-attempt-id operation))
        (generation (claude-code-ide-remote-worktree--operation-generation operation))
        (origin (current-buffer))
        (prefix current-prefix-arg)
        (operations claude-code-ide-remote-worktree--operations)
        (yield-timer (when (featurep 'ns) (run-at-time 0 0.05 #'thread-yield)))
        worker)
    (unwind-protect
        (condition-case error-data
            (setq worker
                  (make-thread
                   (lambda ()
                     (unwind-protect
                         (let (outcome)
                           (condition-case capture-error
                               (setq outcome
                                     (cons :ok
                                           (with-current-buffer origin
                                             (let ((default-directory directory)
                                                   (current-prefix-arg prefix)
                                                   (magit--refresh-cache nil)
                                                   (magit-git-debug nil)
                                                   (claude-code-ide-remote-worktree--operations operations))
                                               (unless (claude-code-ide-remote-worktree--current-p
                                                        operation attempt generation)
                                                 (user-error "The remote Worktree operation is no longer current"))
                                               (claude-code-ide-remote-worktree--capture-native operation thunk)))))
                             (error (setq outcome (cons :error (error-message-string capture-error)))))
                           (run-at-time
                            0 nil
                            (lambda ()
                              (when (claude-code-ide-remote-worktree--current-p operation attempt generation)
                                (if (eq (car outcome) :ok)
                                    (condition-case continuation-error
                                        (progn
                                          (funcall on-argv (cdr outcome))
                                          (claude-code-ide-remote-worktree--start operation attempt generation))
                                      (error (claude-code-ide-remote-worktree--fail
                                              operation (error-message-string continuation-error))))
                                  (claude-code-ide-remote-worktree--fail operation (cdr outcome)))))))
                       (when yield-timer (cancel-timer yield-timer))))
                   "cci-native-capture"))
          (error (claude-code-ide-remote-worktree--fail operation (error-message-string error-data))))
      (unless worker
        (when yield-timer (cancel-timer yield-timer))))))

;;;###autoload
(defun claude-code-ide-remote-worktree-native-move (worktree directory &optional backend)
  "Move remote WORKTREE to DIRECTORY through captured native Magit.
Run the real `magit-worktree-move' in an owned worker thread inside a
bounded capture scope, so its exact literal Git command is captured
before any process starts, then dispatch that command as an admitted
remote mutation instead of running it locally.  WORKTREE and DIRECTORY
must both name the same approved RPC host.  Return a new operation ID
immediately; preparation continues in the background."
  (let ((target (claude-code-ide-remote-worktree-target-for-file worktree))
        (destination (claude-code-ide-remote-worktree-target-for-file directory)))
    (unless (and target destination
                 (equal (plist-get target :host) (plist-get destination :host)))
      (user-error "Native Worktree move requires one approved remote host"))
    (let* ((host (plist-get target :host))
           (operation (claude-code-ide-remote-worktree--new-operation
                       'move host (plist-get target :directory)
                       (list :backend (or backend 'wt)))))
      (claude-code-ide-remote-worktree--spawn-capture
       operation worktree
       (lambda () (magit-worktree-move worktree directory))
       (lambda (argv)
         (unless (and (= (length argv) 4)
                      (equal (nth 0 argv) "worktree") (equal (nth 1 argv) "move"))
           (user-error "The native move command has an unsupported shape"))
         (let ((source (claude-code-ide-remote-worktree--strip-rpc-prefix (nth 2 argv) host))
               (dest (claude-code-ide-remote-worktree--strip-rpc-prefix (nth 3 argv) host)))
           (unless (and (claude-code-ide-zmx--valid-directory-p source)
                        (claude-code-ide-zmx--valid-directory-p dest))
             (user-error "The native move command has an unsupported destination shape"))
           (setf (claude-code-ide-remote-worktree--operation-options operation)
                 (plist-put (claude-code-ide-remote-worktree--operation-options operation)
                            :native-argv (list "worktree" "move" source dest))))))
      (claude-code-ide-remote-worktree--operation-id operation))))

(defun claude-code-ide-remote-worktree--worktree-move-advice (orig-fn worktree directory)
  "Redirect a remote WORKTREE move to the native capture route.
Keep the exact original path for a local move or one already inside a
native capture scope.  An unsupported remote WORKTREE fails closed
through `claude-code-ide-remote-worktree-target-for-file'."
  (interactive (claude-code-ide-remote-worktree--read-move-args))
  (if (or (claude-code-ide-remote-worktree--capture-scope-p)
          (not (claude-code-ide-remote-worktree-target-for-file worktree)))
      (funcall orig-fn worktree directory)
    (claude-code-ide-remote-worktree-native-move worktree directory)))

(defconst claude-code-ide-remote-worktree--push-suffixes
  '(magit-push-current-to-pushremote
    magit-push-current-to-upstream
    magit-push-current
    magit-push-other
    magit-push-refspecs
    magit-push-matching
    magit-push-tag
    magit-push-tags
    magit-push-notes-ref
    magit-push-implicitly
    magit-push-to-remote)
  "Every native Magit push suffix command captured for remote dispatch.")

(defconst claude-code-ide-remote-worktree--push-suffix-prompts
  `((magit-push-current
     . ,(lambda (host) (list (read-string (format "Push current branch on %s to: " host))
                             (magit-push-arguments))))
    (magit-push-other
     . ,(lambda (host) (list (read-string (format "Push branch or commit on %s: " host))
                             (read-string (format "Push from %s to: " host))
                             (magit-push-arguments))))
    (magit-push-refspecs
     . ,(lambda (host) (list (read-string (format "Push from %s to remote: " host))
                             (split-string
                              (read-string (format "Push refspec(s) on %s, comma-separated: " host)) "," t)
                             (magit-push-arguments))))
    (magit-push-matching
     . ,(lambda (host) (list (read-string (format "Push matching branches on %s to remote: " host))
                             (magit-push-arguments))))
    (magit-push-tag
     . ,(lambda (host) (list (read-string (format "Push tag on %s: " host))
                             (read-string (format "Push from %s to remote: " host))
                             (magit-push-arguments))))
    (magit-push-tags
     . ,(lambda (host) (list (read-string (format "Push tags on %s to remote: " host))
                             (magit-push-arguments))))
    (magit-push-notes-ref
     . ,(lambda (host) (list (read-string (format "Push notes ref on %s: " host))
                             (read-string (format "Push from %s to remote: " host))
                             (magit-push-arguments))))
    (magit-push-to-remote
     . ,(lambda (host) (list (read-string (format "Push from %s to remote: " host))
                             (magit-push-arguments)))))
  "Freeform interactive replacement for every push suffix whose native
interactive spec would otherwise read a live remote or branch listing
over Tramp.  Keyed by `this-command', which Transient sets to the
exact suffix symbol before evaluating its interactive form.  A suffix
absent here has no live read in its own interactive spec.
Each prompt function receives the captured host.")

(defvar claude-code-ide-remote-worktree--push-suffix-natives (make-hash-table :test #'eq)
  "Hash of SUFFIX to its own native interactive form, captured once
before advice is added, so a local directory keeps its exact original
prompts and completion candidates.")

(defun claude-code-ide-remote-worktree--push-suffix-read-args ()
  "Return the calling push suffix's resolved interactive argument list.
Use a fixed freeform prompt set for an approved RPC directory, keyed
by `this-command'; for a local directory, evaluate that suffix's own
captured native interactive form unaffected."
  (if-let* ((target (claude-code-ide-remote-worktree-target-for-file default-directory)))
      (if-let* ((prompt (alist-get this-command
                                   claude-code-ide-remote-worktree--push-suffix-prompts)))
          (funcall prompt (plist-get target :host))
        (list (magit-push-arguments)))
    (eval (gethash this-command claude-code-ide-remote-worktree--push-suffix-natives) t)))

(defun claude-code-ide-remote-worktree--dispatch-native-push (suffix args)
  "Run SUFFIX, a native Magit push command, with ARGS applied to it.
Capture its exact literal Git command in an owned worker thread before
any process starts, then dispatch that command as an admitted remote
mutation.  DEFAULT-DIRECTORY supplies the exact Configured host and
repository; it must be an approved RPC directory.  Return a new
operation ID immediately; preparation continues in the background."
  (let ((target (claude-code-ide-remote-worktree-target-for-file default-directory)))
    (unless target
      (user-error "Native Worktree push requires an approved remote directory"))
    (let ((operation (claude-code-ide-remote-worktree--new-operation
                      'push (plist-get target :host) (plist-get target :directory)
                      (list :backend 'wt)))
          (directory default-directory))
      (claude-code-ide-remote-worktree--spawn-capture
       operation directory
       (lambda () (apply suffix args))
       (lambda (argv)
         (unless (equal (car argv) "push")
           (user-error "The native push command has an unsupported shape"))
         (setf (claude-code-ide-remote-worktree--operation-options operation)
               (plist-put (claude-code-ide-remote-worktree--operation-options operation)
                          :native-argv argv))))
      (claude-code-ide-remote-worktree--operation-id operation))))

(defun claude-code-ide-remote-worktree--push-suffix-advice (orig-fn &rest args)
  "Shared :around advice for every symbol in
`claude-code-ide-remote-worktree--push-suffixes'.  Redirect only when
DEFAULT-DIRECTORY is an approved RPC directory and no capture is
already active; every local or already-captured call keeps its exact
native path.  An unsupported remote DEFAULT-DIRECTORY fails closed
through `claude-code-ide-remote-worktree-target-for-file'."
  (interactive (claude-code-ide-remote-worktree--push-suffix-read-args))
  (if (or (claude-code-ide-remote-worktree--capture-scope-p)
          (not (claude-code-ide-remote-worktree-target-for-file default-directory)))
      (apply orig-fn args)
    (claude-code-ide-remote-worktree--dispatch-native-push orig-fn args)))

(with-eval-after-load 'magit-process
  (unless (advice-member-p #'claude-code-ide-remote-worktree--capture-executor
                           'magit-call-git)
    (advice-add 'magit-call-git :around
                #'claude-code-ide-remote-worktree--capture-executor))
  (unless (advice-member-p #'claude-code-ide-remote-worktree--capture-executor
                           'magit-run-git-async)
    (advice-add 'magit-run-git-async :around
                #'claude-code-ide-remote-worktree--capture-executor))
  (unless (advice-member-p #'claude-code-ide-remote-worktree--capture-process-git
                           'magit-process-git)
    (advice-add 'magit-process-git :around
                #'claude-code-ide-remote-worktree--capture-process-git)))

(unless (advice-member-p #'claude-code-ide-remote-worktree--capture-file-directory-p
                         'file-directory-p)
  (advice-add 'file-directory-p :around
              #'claude-code-ide-remote-worktree--capture-file-directory-p))

(dolist (reader '(read-from-minibuffer read-string completing-read yes-or-no-p y-or-n-p))
  (unless (advice-member-p #'claude-code-ide-remote-worktree--capture-prompt reader)
    (advice-add reader :around #'claude-code-ide-remote-worktree--capture-prompt)))

(with-eval-after-load 'magit-worktree
  (unless (advice-member-p #'claude-code-ide-remote-worktree--worktree-move-advice
                           'magit-worktree-move)
    (advice-add 'magit-worktree-move :around
                #'claude-code-ide-remote-worktree--worktree-move-advice)))

(with-eval-after-load 'magit-push
  (dolist (suffix claude-code-ide-remote-worktree--push-suffixes)
    (unless (advice-member-p #'claude-code-ide-remote-worktree--push-suffix-advice suffix)
      (puthash suffix (cadr (interactive-form suffix))
               claude-code-ide-remote-worktree--push-suffix-natives)
      (advice-add suffix :around
                  #'claude-code-ide-remote-worktree--push-suffix-advice))))

(provide 'claude-code-ide-remote-worktree)
;;; claude-code-ide-remote-worktree.el ends here
