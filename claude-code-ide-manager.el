;;; claude-code-ide-manager.el --- Session manager for Claude Code IDE  -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Yu-Fu Fu

;; Author: Yu-Fu Fu <yufu@yfu.tw>
;; Keywords: ai, claude, sessions, tools

;; This file is not part of GNU Emacs.

;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;;; Commentary:

;; Session manager primitives for Claude Code IDE.

;;; Code:

(require 'cl-lib)
(require 'avy)
(require 'project)
(require 'subr-x)
(require 'persist)
(require 'vc-git)
(require 'claude-code-ide-zmx)

(declare-function claude-code-ide--get-session-buffer "claude-code-ide" (&optional directory))
(declare-function claude-code-ide--get-session "claude-code-ide" (session-id))
(declare-function claude-code-ide--start-session "claude-code-ide" (&optional continue resume directory force-new))
(declare-function claude-code-ide--set-session-custom-name "claude-code-ide" (session name))
(declare-function claude-code-ide--set-session-group-metadata "claude-code-ide" (session metadata))
(declare-function claude-code-ide--preferred-session "claude-code-ide" (directory))
(declare-function claude-code-ide--touch-session "claude-code-ide" (session-id))
(declare-function claude-code-ide-session-buffer "claude-code-ide" (session))
(declare-function claude-code-ide-session-created-at "claude-code-ide" (session))
(declare-function claude-code-ide-session-custom-name "claude-code-ide" (session))
(declare-function claude-code-ide-session-directory "claude-code-ide" (session))
(declare-function claude-code-ide-session-id "claude-code-ide" (session))
(declare-function claude-code-ide-session-order "claude-code-ide" (session))
(declare-function claude-code-ide-session-process "claude-code-ide" (session))
(declare-function claude-code-ide-session-title "claude-code-ide" (session))
(declare-function claude-code-ide-session-zmx-name "claude-code-ide" (session))
(declare-function claude-code-ide-session-host "claude-code-ide" (session))
(declare-function claude-code-ide-session-group-metadata "claude-code-ide" (session))
(declare-function claude-code-ide-session-cli-type "claude-code-ide" (session))
(declare-function claude-code-ide--show-session-buffer "claude-code-ide" (buffer))
(declare-function claude-code-ide-attach "claude-code-ide" (&optional host))
(declare-function claude-code-ide-attach-select "claude-code-ide" (&optional host))
(declare-function claude-code-ide-stop "claude-code-ide" (&optional session-id))
(declare-function claude-code-ide--reattach-remote-session "claude-code-ide" (session-id))
(declare-function claude-code-ide--project-key "claude-code-ide" (directory &optional host))
(declare-function claude-code-ide-session-idle-clear-state "claude-code-ide-session-idle" (&optional acknowledged))
(declare-function claude-code-ide-session-idle-disable "claude-code-ide-session-idle" ())
(declare-function claude-code-ide-session-idle-reset-timer "claude-code-ide-session-idle" ())
(declare-function claude-code-ide-manager-open-menu "claude-code-ide-transient" ())
(declare-function claude-code-ide--transient-cli-path "claude-code-ide-transient" (arg))
(declare-function claude-code-ide--transient-launch-flags "claude-code-ide-transient" (&optional bypass))
(declare-function claude-code-ide-manager-sort-menu "claude-code-ide-transient" ())
(declare-function claude-code-ide-manager-dispatch "claude-code-ide-transient" ())
(declare-function claude-code-ide-log "claude-code-ide" (format-string &rest args))
(declare-function claude-code-ide--remote-target-pending-reason "claude-code-ide" (session-id))
(declare-function claude-code-ide--read-remote-host "claude-code-ide" ())
(declare-function claude-code-ide-remote-project-prepare
                  "claude-code-ide-remote-project"
                  (session-id host attachment frame reason))
(declare-function claude-code-ide-remote-project-record-display
                  "claude-code-ide-remote-project"
                  (session-id attachment view-buffer))
(declare-function claude-code-ide-remote-project-surviving-view
                  "claude-code-ide-remote-project"
                  (session-id attachment))
(declare-function claude-code-ide-remote-project-display-allowed-p
                  "claude-code-ide-remote-project"
                  (session-id attachment))
(declare-function claude-code-ide-remote-project-suppress
                  "claude-code-ide-remote-project"
                  (session-id attachment))
(declare-function claude-code-ide-remote-project-needs-replacement-p
                  "claude-code-ide-remote-project"
                  (session-id attachment))
(declare-function claude-code-ide-remote-project-cancel
                  "claude-code-ide-remote-project"
                  (session-id attachment))
(declare-function claude-code-ide-remote-project-invalidate
                  "claude-code-ide-remote-project"
                  (session-id &optional attachment reason))
(declare-function claude-code-ide-remote-project-cleanup-snapshot
                  "claude-code-ide-remote-project"
                  (session-id attachment host siblings))
(declare-function claude-code-ide-remote-project-cleanup
                  "claude-code-ide-remote-project"
                  (snapshot))

(defvar claude-code-ide--session-cli-type)
(defvar claude-code-ide-cli-path)
(defvar claude-code-ide-remote-hosts)

(defvar claude-code-ide-session-idle-hook nil)
(defvar claude-code-ide-session-working-hook nil)
(defvar claude-code-ide--suppress-initial-display nil)
(defvar claude-code-ide-cli-extra-flags "")

(defgroup claude-code-ide-manager nil
  "Session manager for Claude Code IDE."
  :group 'tools
  :prefix "claude-code-ide-manager-")

(defconst claude-code-ide-manager--state-version 4
  "Persisted cc-manager state schema version.")

(defconst claude-code-ide-manager--empty-persisted-state
  `(:version ,claude-code-ide-manager--state-version :scopes nil :layouts nil)
  "Persisted-state value that means \"nothing remembered\".")

(defvar claude-code-ide-manager--persisted-state
  (copy-tree claude-code-ide-manager--empty-persisted-state)
  "Serialized manager state stored through `persist'.")

(defun claude-code-ide-manager--persist-register ()
  "Register the persisted state symbol with a fixed empty default.
`persist-save' deletes the file when the value equals the registered
default, so the default must stay the empty state rather than track
the last saved value."
  (persist-symbol 'claude-code-ide-manager--persisted-state
                  claude-code-ide-manager--empty-persisted-state))

(defun claude-code-ide-manager--set-persist-state (symbol value)
  "Custom setter for persistence option SYMBOL with VALUE."
  (set-default symbol value)
  (if value
      (claude-code-ide-manager--persist-register)
    (persist-unpersist 'claude-code-ide-manager--persisted-state)))

(defcustom claude-code-ide-manager-persist-state t
  "Whether cc-manager state persists across Emacs sessions."
  :type 'boolean
  :set #'claude-code-ide-manager--set-persist-state
  :group 'claude-code-ide-manager)

(defcustom claude-code-ide-manager-window-width 22
  "Width of the manager side window."
  :type 'integer
  :group 'claude-code-ide-manager)

(defcustom claude-code-ide-manager-session-window-side 'right
  "Side of the content area where the default layout puts the session window.
`right' places the session window at the far right of the frame.
`left' places it in the middle, between the manager sidebar and the
status buffer."
  :type '(choice (const :tag "Right" right)
                 (const :tag "Left (middle)" left))
  :group 'claude-code-ide-manager)

(defcustom claude-code-ide-manager-status-buffer-function
  #'claude-code-ide-manager-magit-status-buffer
  "Function that returns the status buffer for the default layout.
It receives the session project DIRECTORY and returns a buffer shown
beside the session window.  When it signals an error or returns a
non-buffer, the layout falls back to a Dired buffer for DIRECTORY."
  :type '(choice (function-item claude-code-ide-manager-magit-status-buffer)
                 (function-item dired-noselect)
                 function)
  :group 'claude-code-ide-manager)

(defcustom claude-code-ide-remote-project-view-hosts nil
  "Exact approved hosts that may prepare remote Project views.
Each host must also occur in `claude-code-ide-remote-hosts'.  Setting
this option performs no remote work."
  :type '(repeat string)
  :group 'claude-code-ide-manager)

(defcustom claude-code-ide-remote-project-cleanup-hosts nil
  "Exact hosts that permit conservative owned Project-view cleanup.
This option is independent of Project-view preparation.  Setting it
performs no remote work."
  :type '(repeat string)
  :group 'claude-code-ide-manager)

(defcustom claude-code-ide-manager-repo-include-nested nil
  "Whether repo-local managers include nested git directories."
  :type 'boolean
  :group 'claude-code-ide-manager)

(defcustom claude-code-ide-manager-repo-label-strategy 'branch-or-basename
  "Visible label strategy for repo-local managers."
  :type '(choice (const :tag "Branch" branch)
                 (const :tag "Basename" basename)
                 (const :tag "Branch or basename" branch-or-basename))
  :group 'claude-code-ide-manager)

(defcustom claude-code-ide-manager-show-session-order nil
  "Whether generated session order suffixes appear in manager rows."
  :type 'boolean
  :group 'claude-code-ide-manager)

(defcustom claude-code-ide-manager-pin-order-show-titles t
  "Whether the pin-order editor appends session titles to ambiguous rows.

A row keeps its plain manager label when that label is unique among the
rows of the same editor."
  :type 'boolean
  :group 'claude-code-ide-manager)

(defcustom claude-code-ide-manager-sort-by 'name
  "Sort manager sessions by this fallback key."
  :type '(choice (const :tag "Name" name)
                 (const :tag "Creation time" created-at))
  :group 'claude-code-ide-manager)

(defcustom claude-code-ide-manager-sort-reverse nil
  "Whether to reverse sorting after pin and manual-order precedence."
  :type 'boolean
  :group 'claude-code-ide-manager)

(defcustom claude-code-ide-manager-default-target 'global
  "Default target for generic manager commands."
  :type '(choice (const :tag "Global" global)
                 (const :tag "Repo-local when in git" repo-local-when-in-git)
                 (const :tag "Repo-local with global fallback" repo-local-always-fallback-global))
  :group 'claude-code-ide-manager)

(defcustom claude-code-ide-manager-global-project-source 'auto
  "Project source used by global manager open.

When set to `auto', prefer Projectile when it is available and fall
back to `project.el' otherwise."
  :type '(choice (const :tag "Auto" auto)
                 (const :tag "Projectile" projectile)
                 (const :tag "project.el" project-el)
                 (const :tag "Merged" merged))
  :group 'claude-code-ide-manager)

(defcustom claude-code-ide-manager-treemacs-split-policy 'half
  "How to split the sidebar when collocating cc-manager with Treemacs."
  :type '(choice (const :tag "Half" half)
                 (const :tag "Adaptive" adaptive))
  :group 'claude-code-ide-manager)

(defface claude-code-ide-manager-current-session-face
  '((t :inherit highlight :foreground "white" :weight bold :extend t))
  "Face used to highlight the active session in the manager sidebar."
  :group 'claude-code-ide-manager)

(defface claude-code-ide-manager-current-marker-face
  '((t :foreground "#8fcf72" :weight bold))
  "Face used for the active session's left-edge marker."
  :group 'claude-code-ide-manager)

(defface claude-code-ide-manager-idle-session-face
  '((t :background "#8a6a14" :foreground "white" :extend t))
  "Face used to highlight output-detected idle sessions in the manager sidebar."
  :group 'claude-code-ide-manager)

(defface claude-code-ide-manager-working-session-face
  '((t :background "#3f6b4f" :foreground "white" :extend t))
  "Face used to highlight working sessions in the manager sidebar."
  :group 'claude-code-ide-manager)

(defface claude-code-ide-manager-attention-session-face
  '((t :background "red" :foreground "white" :extend t))
  "Face used to highlight sessions that need the user: `needs-input' or `failed'.
Red is reserved for these rows."
  :group 'claude-code-ide-manager)

(defface claude-code-ide-manager-done-session-face
  '((t :background "#2f5f8f" :foreground "white" :extend t))
  "Face used to highlight sessions whose agent finished a turn."
  :group 'claude-code-ide-manager)

(defface claude-code-ide-manager-host-face
  '((t :inherit font-lock-type-face :weight bold))
  "Face for the remote host label in the manager sidebar.
Used for the `[host]' group heading in the grouped view and for the
`[host]' prefix of a row in the flat view.  A row status face still
wins over this face."
  :group 'claude-code-ide-manager)

(defconst claude-code-ide-manager--bell-glyph "🔔"
  ;; NOTE: Some fonts render this emoji taller than surrounding fixed-pitch
  ;; text, which can make manager rows look uneven. Keep the current glyph for
  ;; now, but prefer a text-style or ASCII marker if we revisit the gutter UI.
  "Bell glyph used to mark idle sessions in the manager sidebar.")

(defconst claude-code-ide-manager--working-glyph "⚙︎"
  "Gear glyph used to mark working sessions in the manager sidebar.")

(defconst claude-code-ide-manager--pin-glyph "📌"
  "Pin glyph used to mark pinned sessions in the manager sidebar.")

(defconst claude-code-ide-manager--needs-input-glyph "?"
  "Glyph used to mark sessions whose agent waits for the user.
Text-width glyphs only: emoji such as ❓ report `string-width' 1 but
render two cells wide, which breaks gutter alignment.")

(defconst claude-code-ide-manager--done-glyph "✓"
  "Glyph used to mark sessions whose agent finished a turn.")

(defconst claude-code-ide-manager--failed-glyph "✗"
  "Glyph used to mark sessions whose agent turn failed.")

(defconst claude-code-ide-manager--marker-gutter-width 2
  "Fixed display width for the left marker gutter.")

(cl-defstruct claude-code-ide-manager-item
  "Sidebar row state for a managed session."
  session-key
  directory
  custom-name
  order
  created-at
  display-name
  secondary-text
  pinned
  order-key
  live-p
  host
  zmx-name
  cli-type
  group-metadata)

(defvar claude-code-ide-manager--items nil
  "Current manager items.")

(defvar claude-code-ide-manager--scope-state (make-hash-table :test 'equal)
  "Per-scope manager view state keyed by scope key.")

(defvar claude-code-ide-manager--priority-visits (make-hash-table :test 'equal)
  "Per-scope priority passes with :visited entries and a :resume session key.")

(defvar claude-code-ide-manager--uncleared-visits (make-hash-table :test 'equal)
  "Per-scope uncleared passes with :visited entries and a :resume session key.")

(defvar claude-code-ide-manager--layouts (make-hash-table :test 'equal)
  "Saved layouts keyed by session key.")

(defvar claude-code-ide-manager--legacy-adopted-p nil
  "Non-nil when the current item rebuild adopted directory-keyed state.")

(defconst claude-code-ide-manager--buffer-name "*claude-code-manager*"
  "Manager sidebar buffer name.")

(defconst claude-code-ide-manager--buffer-name-regexp
  "^\\*claude-code-manager\\(?:[:].*\\)?\\*$"
  "Regexp matching global and scoped manager buffer names.")

(defun claude-code-ide-manager--scope-key (scope)
  "Return a stable key for manager SCOPE."
  (pcase (plist-get scope :type)
    ('global "global")
    ('repo (format "repo:%s" (plist-get scope :git-root)))
    (_ (error "Unknown manager scope: %S" scope))))

(defun claude-code-ide-manager--buffer-name-for-scope (scope)
  "Return the manager buffer name for SCOPE."
  (pcase (plist-get scope :type)
    ('global claude-code-ide-manager--buffer-name)
    ('repo (let* ((git-root (file-name-as-directory
                             (expand-file-name (plist-get scope :git-root))))
                  (repo-name (file-name-nondirectory
                              (directory-file-name git-root)))
                  (root-hash (substring (md5 git-root) 0 8)))
             (format "*claude-code-manager:%s@%s*" repo-name root-hash)))
    (_ (error "Unknown manager scope: %S" scope))))

(defun claude-code-ide-manager--scope-state-entry (scope)
  "Return the state plist stored for SCOPE."
  (gethash (claude-code-ide-manager--scope-key scope)
           claude-code-ide-manager--scope-state))

(defun claude-code-ide-manager--set-scope-state-entry (scope state)
  "Store STATE plist for SCOPE and sync legacy global aliases."
  (puthash (claude-code-ide-manager--scope-key scope)
           state
           claude-code-ide-manager--scope-state)
  (when (eq (plist-get scope :type) 'global)
    (setq claude-code-ide-manager--items (plist-get state :items)))
  state)

(defun claude-code-ide-manager--scope-items (scope)
  "Return the current items stored for SCOPE."
  (if (eq (plist-get scope :type) 'global)
      (or (plist-get (claude-code-ide-manager--scope-state-entry scope) :items)
          claude-code-ide-manager--items)
    (plist-get (claude-code-ide-manager--scope-state-entry scope) :items)))

(defun claude-code-ide-manager--group-order (scope)
  "Return SCOPE's stored group identities in display order."
  (plist-get (claude-code-ide-manager--scope-state-entry scope) :group-order))

(defun claude-code-ide-manager--store-group-order (scope keys)
  "Store KEYS as SCOPE's leading group order, keeping other stored identities."
  ;; ponytail: stale identities are never pruned; prune when the list grows enough to matter.
  (let* ((state (copy-sequence
                 (or (claude-code-ide-manager--scope-state-entry scope)
                     (list :items claude-code-ide-manager--items))))
         (rest (cl-remove-if (lambda (key) (member key keys))
                             (plist-get state :group-order))))
    (claude-code-ide-manager--set-scope-state-entry
     scope (plist-put state :group-order (append keys rest)))))

(defun claude-code-ide-manager--view (scope)
  "Return the presentation for SCOPE."
  (if (and (eq (plist-get scope :type) 'global)
           (eq (plist-get (claude-code-ide-manager--scope-state-entry scope) :view)
               'grouped))
      'grouped
    'flat))

(defun claude-code-ide-manager--normalize-view (view)
  "Return VIEW normalized to `flat' or `grouped'."
  (if (eq view 'grouped) 'grouped 'flat))

(defun claude-code-ide-manager--valid-group-order (keys)
  "Return KEYS limited to well-formed group identities."
  (cl-remove-if-not
   (lambda (key)
     (and (proper-list-p key) (= (length key) 3)
          (memq (nth 0 key) '(git non-git unresolved unresolved-session))
          (or (null (nth 1 key)) (stringp (nth 1 key)))
          (stringp (nth 2 key))))
   (and (proper-list-p keys) keys)))

(defun claude-code-ide-manager--valid-group-metadata (metadata host directory)
  "Return validated METADATA for exact HOST and DIRECTORY, or nil."
  (when (and (proper-list-p metadata) (cl-evenp (length metadata)))
    (let ((kind (plist-get metadata :kind))
          (common (plist-get metadata :common-dir))
          (project (plist-get metadata :project-path))
          (worktree (plist-get metadata :worktree-path))
          (branch (plist-get metadata :branch)))
      (when (and (equal host (plist-get metadata :host))
                 (equal directory (plist-get metadata :directory))
                 (or (null host) (claude-code-ide-zmx--valid-host-p host))
                 (claude-code-ide-zmx--valid-directory-p directory)
                 (claude-code-ide-zmx--valid-directory-p project)
                 (or (null branch)
                     (and (stringp branch) (not (string-empty-p branch))
                          (not (string-match-p "[[:cntrl:]]" branch))))
                 (pcase kind
                   ('git
                    (and (claude-code-ide-zmx--valid-directory-p common)
                         (or (null worktree)
                             (claude-code-ide-zmx--valid-directory-p worktree))))
                   ('non-git
                    (and (null common) (null worktree) (null branch)
                         (or (null host) (equal project directory))))))
        (list :kind kind
              :host (and host (substring-no-properties host))
              :directory (substring-no-properties directory)
              :common-dir (and common (substring-no-properties common))
              :project-path (substring-no-properties project)
              :worktree-path (and worktree (substring-no-properties worktree))
              :branch (and branch (substring-no-properties branch)))))))

(defun claude-code-ide-manager--group-key (item)
  "Return the repository identity for ITEM without querying Git or SSH."
  (let* ((host (claude-code-ide-manager-item-host item))
         (directory (claude-code-ide-manager-item-directory item))
         (metadata (claude-code-ide-manager-item-group-metadata item)))
    (pcase (plist-get metadata :kind)
      ('git (list 'git host (plist-get metadata :common-dir)))
      ('non-git (list 'non-git host (plist-get metadata :project-path)))
      (_ (if (and (stringp directory) (not (string-empty-p directory)))
             (list 'unresolved host
                   (if host directory
                     (condition-case nil (directory-file-name (file-truename directory))
                       (file-error directory))))
           (list 'unresolved-session host
                 (claude-code-ide-manager-item-session-key item)))))))

(defun claude-code-ide-manager--local-group-metadata (directory)
  "Read local repository metadata for DIRECTORY, or return nil on error."
  (let ((stderr (make-temp-file "cci-git-stderr-"))
        (process-environment (copy-sequence process-environment)))
    (unwind-protect
        (condition-case nil
            (let ((default-directory (file-name-as-directory directory)))
              (dolist (name '("GIT_DIR" "GIT_WORK_TREE" "GIT_COMMON_DIR"))
                (setenv name nil))
              (setenv "LC_ALL" "C")
              (cl-labels
                  ((query (&rest args)
                     (with-temp-buffer
                       (let ((status (apply #'process-file "git" nil
                                            (list (current-buffer) stderr) nil args)))
                         (list status (string-remove-suffix "\n" (buffer-string))
                               (with-temp-buffer
                                 (insert-file-contents stderr)
                                 (buffer-string))))))
                   (value (result)
                     (unless (eq (car result) 0)
                       (error "Git metadata query failed: %s" (nth 2 result)))
                     (cadr result)))
                (let ((common-result (query "rev-parse" "--git-common-dir")))
                  (if (and (eq (car common-result) 128)
                           (string-match-p
                            (concat "\\`fatal: not a git repository (or any "
                                    "\\(?:of the parent directories): \\.git\n"
                                    "\\|parent up to mount point [^\n]+)\n"
                                    "Stopping at filesystem boundary (GIT_DISCOVERY_ACROSS_FILESYSTEM not set)\\.\n\\)\\'")
                            (nth 2 common-result)))
                      (claude-code-ide-manager--valid-group-metadata
                       (list :kind 'non-git :host nil :directory directory
                             :project-path (directory-file-name (file-truename directory)))
                       nil directory)
                    (let* ((common (directory-file-name
                                    (file-truename (expand-file-name
                                                    (value common-result) directory))))
                           (root-result (query "rev-parse" "--show-toplevel"))
                           (root (if (eq (car root-result) 0)
                                     (directory-file-name (file-truename (cadr root-result)))
                                   (unless (equal (value (query "rev-parse" "--is-bare-repository")) "true")
                                     (error "Cannot read the Worktree root"))
                                   nil))
                           (branch-result (query "symbolic-ref" "--quiet" "--short" "HEAD"))
                           (branch (unless (eq (car branch-result) 1)
                                     (value branch-result))))
                      (claude-code-ide-manager--valid-group-metadata
                       (list :kind 'git :host nil :directory directory :common-dir common
                             :project-path (if (equal (file-name-nondirectory common) ".git")
                                               (directory-file-name (file-name-directory common))
                                             common)
                             :worktree-path root :branch branch)
                       nil directory))))))
          (error nil))
      (delete-file stderr))))

(defun claude-code-ide-manager--refresh-local-group-metadata (items)
  "Refresh local metadata once per unique directory in ITEMS."
  (let ((queried (make-hash-table :test 'equal))
        (missing (make-symbol "missing")))
    (dolist (item items)
      (unless (claude-code-ide-manager-item-host item)
        (let* ((directory (claude-code-ide-manager-item-directory item))
               (metadata (gethash directory queried missing)))
          (when (eq metadata missing)
            (setq metadata (and directory
                                (claude-code-ide-manager--local-group-metadata directory)))
            (puthash directory metadata queried))
          (when metadata
            (setf (claude-code-ide-manager-item-group-metadata item) metadata)
            (when-let* ((session (claude-code-ide--get-session
                                  (claude-code-ide-manager-item-session-key item))))
              (claude-code-ide--set-session-group-metadata session metadata))))))))

(defun claude-code-ide-manager--group-path (item)
  "Return ITEM's cached project path without local path interpretation."
  (or (plist-get (claude-code-ide-manager-item-group-metadata item) :project-path)
      (claude-code-ide-manager-item-directory item) ""))

(defun claude-code-ide-manager--group-headings (items)
  "Return group identity to (HEADING . PATH) mappings for ITEMS."
  (let ((groups (make-hash-table :test 'equal))
        (names (make-hash-table :test 'equal)))
    (dolist (item items)
      (let ((key (claude-code-ide-manager--group-key item)))
        (unless (gethash key groups)
          (let* ((path (claude-code-ide-manager--group-path item))
                 (base (or (car (last (split-string path "/" t))) "/"))
                 (name (if (memq (car key) '(unresolved unresolved-session))
                           (concat base " [unresolved]") base)))
            (puthash key (cons name path) groups)
            (push key (gethash (list (cadr key) name) names))))))
    (maphash
     (lambda (_ keys)
       (when (cdr keys)
         (dolist (key keys)
           (let ((entry (gethash key groups)))
             (setcar entry (format "%s (%s)" (car entry) (cdr entry)))))))
     names)
    (clrhash names)
    (maphash (lambda (key entry) (push key (gethash (list (cadr key) (car entry)) names)))
             groups)
    (maphash
     (lambda (_ keys)
       (when (cdr keys)
         (dolist (key keys)
           (let ((entry (gethash key groups)))
             (setcar entry (format "%s %S" (car entry) key))))))
     names)
    groups))

(defun claude-code-ide-manager--grouped-labels (items)
  "Return cached, unambiguous grouped row labels keyed by ITEM."
  (let ((groups (make-hash-table :test 'equal))
        (labels (make-hash-table :test 'eq)))
    (dolist (item items)
      (push item (gethash (claude-code-ide-manager--group-key item) groups)))
    (maphash
     (lambda (_ group)
       (let ((counts (make-hash-table :test 'equal))
             bases)
         (dolist (item group)
           (let* ((metadata (claude-code-ide-manager-item-group-metadata item))
                  (branch (or (plist-get metadata :branch)
                              (car (last (split-string
                                          (or (plist-get metadata :worktree-path)
                                              (claude-code-ide-manager-item-directory item) "")
                                          "/" t)))
                              "/"))
                  (custom (claude-code-ide-manager-item-custom-name item))
                  (base (if custom (concat branch " · " custom) branch)))
             (setq base (replace-regexp-in-string
                         "[[:cntrl:]]" " " (substring-no-properties base)))
             (push base bases)
             (puthash base (1+ (gethash base counts 0)) counts)))
         (setq bases (nreverse bases))
         (cl-mapc
          (lambda (item name) (puthash item name labels))
          group
          (claude-code-ide-manager--disambiguate-display-names
           group
           (cl-mapcar
            (lambda (item base)
              (if (and (> (gethash base counts) 1)
                       (null (claude-code-ide-manager-item-custom-name item)))
                  (format "%s · %s" base (or (claude-code-ide-manager-item-order item)
                                             (claude-code-ide-manager-item-session-key item)))
                base))
            group bases)))))
     groups)
    labels))

(defun claude-code-ide-manager--group-less-p (left right headings positions)
  "Compare LEFT and RIGHT group identities using HEADINGS and stored POSITIONS."
  (let ((left-position (and positions (gethash left positions)))
        (right-position (and positions (gethash right positions))))
    (cond
     ((and left-position right-position) (< left-position right-position))
     (left-position t)
     (right-position nil)
     (t
      (let ((left-name (car (gethash left headings)))
            (right-name (car (gethash right headings)))
            (left-host (cadr left))
            (right-host (cadr right)))
        (cond
         ((not (equal left-name right-name))
          (string-version-lessp left-name right-name))
         ((equal left-host right-host)
          (string< (prin1-to-string left) (prin1-to-string right)))
         ((null left-host) t)
         ((null right-host) nil)
         (t (string-version-lessp left-host right-host))))))))

(defun claude-code-ide-manager--scope-selected-session-key (scope)
  "Return the last selected session key stored for SCOPE."
  (plist-get (claude-code-ide-manager--scope-state-entry scope)
             :selected-session-key))

(defun claude-code-ide-manager--scope-active-session-key (scope)
  "Return the active session key stored for SCOPE."
  (plist-get (claude-code-ide-manager--scope-state-entry scope)
             :active-session-key))

(defun claude-code-ide-manager--set-scope-selected-session-key
    (scope session-key)
  "Store SESSION-KEY as the last selected row for SCOPE."
  (let ((state (copy-sequence
                (or (claude-code-ide-manager--scope-state-entry scope)
                    (and (eq (plist-get scope :type) 'global)
                         (list :items claude-code-ide-manager--items))))))
    (claude-code-ide-manager--set-scope-state-entry
     scope
     (plist-put state :selected-session-key session-key))))

(defun claude-code-ide-manager--set-scope-active-session-key
    (scope session-key)
  "Store SESSION-KEY as the active session for SCOPE."
  (let ((state (copy-sequence
                (or (claude-code-ide-manager--scope-state-entry scope)
                    (and (eq (plist-get scope :type) 'global)
                         (list :items claude-code-ide-manager--items))))))
    (claude-code-ide-manager--set-scope-state-entry
     scope
     (plist-put state :active-session-key session-key))))

(defun claude-code-ide-manager--set-scope-items (scope items)
  "Store ITEMS for SCOPE."
  (let ((state (copy-sequence (claude-code-ide-manager--scope-state-entry scope))))
    (claude-code-ide-manager--set-scope-state-entry
     scope
     (plist-put state :items items))))

(defun claude-code-ide-manager--current-git-root ()
  "Return the current Git root directory when available."
  (or
   (when-let* ((default-directory (and default-directory
                                       (file-name-as-directory
                                        (expand-file-name default-directory))))
               (common-dir-line (car (ignore-errors
                                       (process-lines "git" "-C" default-directory
                                                      "rev-parse" "--git-common-dir"))))
               (common-dir (expand-file-name common-dir-line default-directory))
               ((string-equal (file-name-nondirectory (directory-file-name common-dir))
                              ".git")))
     (file-name-as-directory
      (file-name-directory (directory-file-name common-dir))))
   (when-let* ((root (ignore-errors (vc-git-root default-directory))))
     (file-name-as-directory (expand-file-name root)))))

(defun claude-code-ide-manager--session-record (session-or-key)
  "Return the live session represented by SESSION-OR-KEY, or nil."
  (if (and (recordp session-or-key)
           (eq (type-of session-or-key) 'claude-code-ide-session))
      session-or-key
    (claude-code-ide--get-session session-or-key)))

(defun claude-code-ide-manager--session-host (session-or-key)
  "Return the remote host of SESSION-OR-KEY, including remembered targets."
  (if-let* ((session (claude-code-ide-manager--session-record session-or-key)))
      (claude-code-ide-session-host session)
    (when-let* ((item (claude-code-ide-manager--item-by-session-key session-or-key)))
      (claude-code-ide-manager-item-host item))))

(defun claude-code-ide-manager--remote-project-enabled-p
    (session-key &optional expected-host)
  "Return non-nil when SESSION-KEY's exact host admits Project views.
When EXPECTED-HOST is non-nil, require that exact current host."
  (when-let* ((host
               (claude-code-ide-manager--session-host session-key)))
    (and
     (or (null expected-host) (equal host expected-host))
     (member host claude-code-ide-remote-hosts)
     (member host claude-code-ide-remote-project-view-hosts))))

(defun claude-code-ide-manager--maybe-prepare-remote-project
    (session-key attachment frame reason)
  "Prepare SESSION-KEY's enabled remote Project view.
ATTACHMENT, FRAME, and REASON establish exact display ownership.
Return nil without loading the feature when the host is not admitted."
  (when-let* ((host
               (claude-code-ide-manager--session-host session-key))
              ((claude-code-ide-manager--remote-project-enabled-p
                session-key))
              ((or (featurep 'claude-code-ide-remote-project)
                   (require 'claude-code-ide-remote-project nil t))))
    (claude-code-ide-remote-project-prepare
     session-key host attachment frame reason)
    t))

(defun claude-code-ide-manager--session-directory (session-or-key)
  "Return the directory represented by SESSION-OR-KEY."
  (or (when-let* ((session
                   (claude-code-ide-manager--session-record session-or-key)))
        (claude-code-ide-session-directory session))
      (when-let* ((item (and (stringp session-or-key)
                             (claude-code-ide-manager--item-by-session-key
                              session-or-key))))
        (claude-code-ide-manager-item-directory item))
      session-or-key))

(defun claude-code-ide-manager--session-buffer (session-key)
  "Return SESSION-KEY's owned buffer, or its local legacy directory buffer."
  (if-let* ((session (claude-code-ide--get-session session-key)))
      (when (or (null (claude-code-ide-session-host session))
                (process-live-p (claude-code-ide-session-process session)))
        (or (and (buffer-live-p (claude-code-ide-session-buffer session))
                 (claude-code-ide-session-buffer session))
            (let ((process (claude-code-ide-session-process session)))
              (cond
               ((bufferp process) (and (buffer-live-p process) process))
               ((processp process) (process-buffer process))))))
    (when (and (stringp session-key)
               (file-name-absolute-p session-key)
               (not (claude-code-ide-manager--session-host session-key)))
      (claude-code-ide--get-session-buffer session-key))))

(defun claude-code-ide-manager--session-git-root (session-or-key)
  "Return the local Git root for SESSION-OR-KEY when available."
  (unless (claude-code-ide-manager--session-host session-or-key)
    (let ((default-directory
           (claude-code-ide-manager--session-directory session-or-key)))
      (claude-code-ide-manager--current-git-root))))

(defun claude-code-ide-manager--session-branch-name (session-or-key)
  "Return the local branch name for SESSION-OR-KEY when available."
  (unless (claude-code-ide-manager--session-host session-or-key)
    (car (ignore-errors
           (process-lines "git" "-C"
                          (claude-code-ide-manager--session-directory session-or-key)
                          "branch" "--show-current")))))

(defun claude-code-ide-manager--session-help-echo (session-key path)
  "Return help text for SESSION-KEY using PATH.

Append the current branch when SESSION-KEY is on a named branch."
  (let ((branch (claude-code-ide-manager--session-branch-name session-key)))
    (if (and (stringp branch) (not (string-empty-p branch)))
        (format "%s [%s]" path branch)
      path)))

(defun claude-code-ide-manager--resolve-scope (target)
  "Resolve TARGET into a manager scope plist."
  (pcase target
    ('global '(:type global))
    ('repo (if-let* ((git-root (claude-code-ide-manager--current-git-root)))
               (list :type 'repo :git-root git-root)
             (user-error "No git repo for repo-local manager")))
    ((pred listp) target)
    (_ (error "Unknown manager target: %S" target))))

(defun claude-code-ide-manager--default-target ()
  "Return the configured default manager target."
  (pcase claude-code-ide-manager-default-target
    ('global 'global)
    ('repo-local-when-in-git
     (if (claude-code-ide-manager--current-git-root) 'repo 'global))
    ('repo-local-always-fallback-global
     (if (claude-code-ide-manager--current-git-root) 'repo 'global))
    (_ (error "Unknown manager default target: %S"
              claude-code-ide-manager-default-target))))

(defun claude-code-ide-manager--scope-session-keys (scope session-keys)
  "Return SESSION-KEYS visible within SCOPE."
  (pcase (plist-get scope :type)
    ('global session-keys)
    ('repo
     (cl-remove-if-not
      (lambda (session-key)
        (let ((root (claude-code-ide-manager--session-git-root session-key))
              (target-root (plist-get scope :git-root)))
          (if claude-code-ide-manager-repo-include-nested
              (and root (string-prefix-p target-root root))
            (equal root target-root))))
      session-keys))
    (_ (error "Unknown manager scope: %S" scope))))

(defun claude-code-ide-manager--remote-label (host directory order &optional custom-name)
  "Return a host-qualified label without local interpretation of DIRECTORY."
  (format "[%s] %s · %s" host
          (or (car (last (split-string directory "/" t))) "/")
          (or custom-name order)))

(defun claude-code-ide-manager--default-session-label (session)
  "Return SESSION's stable project label."
  (if-let* ((host (claude-code-ide-session-host session)))
      (claude-code-ide-manager--remote-label
       host (claude-code-ide-session-directory session)
       (claude-code-ide-session-order session))
    (format "%s · %d"
            (file-name-nondirectory
             (directory-file-name (claude-code-ide-session-directory session)))
            (claude-code-ide-session-order session))))

(defun claude-code-ide-manager--scope-display-name (scope session-or-key)
  "Return the display name for SESSION-OR-KEY within SCOPE."
  (if-let* ((host (claude-code-ide-manager--session-host session-or-key)))
      (let* ((session (claude-code-ide-manager--session-record session-or-key))
             (item (unless session
                     (claude-code-ide-manager--item-by-session-key session-or-key))))
        (claude-code-ide-manager--remote-label
         host (claude-code-ide-manager--session-directory session-or-key)
         (if session (claude-code-ide-session-order session)
           (claude-code-ide-manager-item-order item))))
    (if-let* ((session (claude-code-ide-manager--session-record session-or-key)))
        (pcase (plist-get scope :type)
          ('global (claude-code-ide-manager--default-session-label session))
          ('repo
           (let* ((directory (claude-code-ide-session-directory session))
                  (basename (file-name-nondirectory
                             (directory-file-name directory)))
                  (base
                   (pcase claude-code-ide-manager-repo-label-strategy
                     ('basename basename)
                     ((or 'branch 'branch-or-basename)
                      (or (claude-code-ide-manager--session-branch-name session)
                          basename))
                     (_ (error "Unknown repo label strategy: %S"
                               claude-code-ide-manager-repo-label-strategy)))))
             (format "%s · %d" base (claude-code-ide-session-order session))))
          (_ (error "Unknown manager scope: %S" scope)))
      ;; Directory-key compatibility for callers without a live record.
      (let ((directory (claude-code-ide-manager--session-directory session-or-key)))
        (pcase (plist-get scope :type)
          ('global (file-name-nondirectory (directory-file-name directory)))
          ('repo
           (pcase claude-code-ide-manager-repo-label-strategy
             ('basename (file-name-nondirectory (directory-file-name directory)))
             ((or 'branch 'branch-or-basename)
              (or (claude-code-ide-manager--session-branch-name session-or-key)
                  (file-name-nondirectory (directory-file-name directory))))
             (_ (error "Unknown repo label strategy: %S"
                       claude-code-ide-manager-repo-label-strategy))))
          (_ (error "Unknown manager scope: %S" scope)))))))

(defun claude-code-ide-manager--disambiguate-display-names (items &optional names)
  "Disambiguate ITEMS' labels, or supplied NAMES without path suffixes."
  (let ((groups (make-hash-table :test 'equal))
        (labels (make-hash-table :test 'eq))
        (remaining names))
    (dolist (item items)
      (let ((display-name (or (pop remaining)
                              (claude-code-ide-manager-item-display-name item))))
        (push item (gethash display-name groups))
        (puthash item display-name labels)))
    (dolist (display-name (unless names (hash-table-keys groups)))
      (let ((group (nreverse (gethash display-name groups))))
        (when (> (length group) 1)
          (let ((suffix-length 1)
                resolved)
            (while (not resolved)
              (let ((seen (make-hash-table :test 'equal))
                    (collision nil))
                (dolist (item group)
                  (let* ((parts (split-string
                                 (directory-file-name
                                  (or (claude-code-ide-manager-item-directory item)
                                      (claude-code-ide-manager-item-session-key item)))
                                 "/" t))
                         (suffix-parts (last parts (min suffix-length
                                                        (length parts))))
                         (suffix (string-join suffix-parts "/")))
                    (if (gethash suffix seen)
                        (setq collision t)
                      (puthash suffix item seen))))
                (if (or (not collision)
                        (cl-every
                         (lambda (item)
                           (<= (length (split-string
                                        (directory-file-name
                                         (or (claude-code-ide-manager-item-directory item)
                                             (claude-code-ide-manager-item-session-key item)))
                                        "/" t))
                               suffix-length))
                         group))
                    (progn
                      (maphash
                       (lambda (suffix item)
                         (puthash item
                                  (format "%s [%s]" display-name suffix)
                                  labels))
                       seen)
                      (setq resolved t))
                  (setq suffix-length (1+ suffix-length)))))))))
    ;; Path suffixes can themselves match a literal custom name.  Extend only
    ;; those final collisions with the immutable session ID until all labels
    ;; are distinct.
    (let ((resolved nil))
      (while (not resolved)
        (let ((final-groups (make-hash-table :test 'equal)))
          (setq resolved t)
          (dolist (item items)
            (push item (gethash (gethash item labels) final-groups)))
          (maphash
           (lambda (label group)
             (when (> (length group) 1)
               (setq resolved nil)
               (dolist (item group)
                 (puthash
                  item
                  (format "%s [%s]" label
                          (claude-code-ide-manager-item-session-key item))
                  labels))))
           final-groups))))
    (mapcar (lambda (item) (gethash item labels)) items)))

(defvar claude-code-ide--sessions)

(defvar claude-code-ide-manager--current-session-key nil
  "Session key currently active in the manager frame.")

(defvar claude-code-ide-manager--command-scope nil
  "Dynamic scope override for manager command helpers.")

(defvar claude-code-ide-manager--open-target nil
  "Directory currently selected for manager-open transient actions.")

(defvar claude-code-ide-manager--open-scope nil
  "Manager scope currently associated with open transient actions.")

(defvar claude-code-ide-manager--in-window-config-refresh nil
  "Non-nil while cc-manager is reasserting sidebar state after layout changes.")

(defun claude-code-ide-manager--advance-layout-epoch (&optional frame)
  "Advance FRAME's layout epoch and clear its old display and command intent."
  (let ((frame (or frame (selected-frame))))
    (set-frame-parameter
     frame 'claude-code-ide-manager-remote-project-epoch
     (1+
      (or
       (frame-parameter
        frame 'claude-code-ide-manager-remote-project-epoch)
       0)))
    (set-frame-parameter
     frame 'claude-code-ide-manager-remote-project-display nil)
    (set-frame-parameter
     frame 'claude-code-ide-manager-remote-project-command nil)))

(defun claude-code-ide-manager--set-remote-project-frame-intent
    (session-key terminal view view-window &optional frame)
  "Record SESSION-KEY's TERMINAL, VIEW, and VIEW-WINDOW on FRAME."
  (let ((frame (or frame (selected-frame))))
    (set-frame-parameter
     frame 'claude-code-ide-manager-remote-project-display
     (list
      :session-key session-key
      :attachment terminal
      :view view
      :view-window view-window
      :epoch
      (or
       (frame-parameter
        frame 'claude-code-ide-manager-remote-project-epoch)
       0)))))

(defun claude-code-ide-manager--remote-project-pre-command ()
  "Capture a visible remote Project-view layout before a user command."
  (let* ((frame (selected-frame))
         (intent
          (frame-parameter
           frame 'claude-code-ide-manager-remote-project-display))
         (terminal (plist-get intent :attachment))
         (view (plist-get intent :view))
         (terminal-window
          (and
           (buffer-live-p terminal)
           (get-buffer-window terminal frame)))
         (view-window
          (and
           (buffer-live-p view)
           (get-buffer-window view frame))))
    (set-frame-parameter
     frame 'claude-code-ide-manager-remote-project-command
     (when (and terminal-window view-window)
       (list
        :session-key (plist-get intent :session-key)
        :attachment terminal
        :view view
        :view-window view-window
        :epoch (plist-get intent :epoch)
        :started-in-view
        (eq (selected-window) view-window))))))

(defun claude-code-ide-manager--remote-project-post-command ()
  "Record an actual user dismissal of a displayed remote Project view."
  (let* ((frame (selected-frame))
         (snapshot
          (frame-parameter
           frame 'claude-code-ide-manager-remote-project-command))
         (intent
          (frame-parameter
           frame 'claude-code-ide-manager-remote-project-display)))
    (set-frame-parameter
     frame 'claude-code-ide-manager-remote-project-command nil)
    (when snapshot
      (let* ((session-key (plist-get snapshot :session-key))
             (attachment (plist-get snapshot :attachment))
             (view (plist-get snapshot :view))
             (view-window (plist-get snapshot :view-window))
             (gone
              (or
               (not (buffer-live-p view))
               (not (get-buffer-window view frame))))
             (dismissed
              (or
               (not (window-live-p view-window))
               (not (buffer-live-p view))
               (plist-get snapshot :started-in-view))))
        (when
            (and
             gone dismissed
             (equal session-key (plist-get intent :session-key))
             (eq attachment (plist-get intent :attachment))
             (eq attachment
                 (claude-code-ide-manager--session-buffer session-key))
             (equal
              (plist-get snapshot :epoch)
              (plist-get intent :epoch)))
          (claude-code-ide-remote-project-suppress
           session-key attachment)
          (set-frame-parameter
           frame 'claude-code-ide-manager-remote-project-display
           (plist-put
            (plist-put intent :view nil)
            :view-window nil)))))))

(add-hook 'pre-command-hook
          #'claude-code-ide-manager--remote-project-pre-command)
(add-hook 'post-command-hook
          #'claude-code-ide-manager--remote-project-post-command)

(defvar-local claude-code-ide-manager--managed-session nil
  "Non-nil when the current session buffer has been shown through cc-manager.")

(defvar-local claude-code-ide-manager--scope nil
  "Scope descriptor associated with the current manager buffer.")

(defvar-local claude-code-ide-manager--last-point-path nil
  "Last full path shown in the echo area for the current manager buffer.")

(defvar-local claude-code-ide-manager--pin-order-scope nil
  "Scope edited by the current pin-order buffer.")

(defvar-local claude-code-ide-manager--pin-order-snapshot nil
  "Opening pin-order snapshot as ordered (SESSION-KEY . NAME) pairs.")

(defvar-local claude-code-ide-manager--pin-order-view 'flat
  "View captured when the current order editor opened.")

(defvar-local claude-code-ide-manager--pin-order-grouping nil
  "Captured group identities, fixed headings, and baseline flat Session IDs.")

(defvar-local claude-code-ide-manager--pin-order-return-window nil
  "Content window replaced by the current pin-order buffer.")

(defvar-local claude-code-ide-manager--pin-order-return-buffer nil
  "Content buffer replaced by the current pin-order buffer.")

(defun claude-code-ide-manager--manager-buffer-p (&optional buffer)
  "Return non-nil when BUFFER is a manager buffer."
  (when-let* ((buffer (or buffer (current-buffer))))
    (with-current-buffer buffer
      (derived-mode-p 'claude-code-ide-manager-mode))))

(defun claude-code-ide-manager--scope-from-buffer (&optional buffer)
  "Return the manager scope stored in BUFFER, defaulting to global."
  (or (and buffer
           (with-current-buffer buffer
             (and (claude-code-ide-manager--manager-buffer-p buffer)
                  claude-code-ide-manager--scope)))
      '(:type global)))

(defun claude-code-ide-manager--visible-sidebar-scope-for-frame (&optional frame)
  "Return the visible manager sidebar scope for FRAME, if any.
When multiple manager sidebars are visible, prefer the configured default
scope when it is visible; otherwise return the first visible scope."
  (let* ((frame (or frame (selected-frame)))
         (visible-scopes nil)
         (current-git-root (ignore-errors
                             (claude-code-ide-manager--current-git-root))))
    (walk-windows
     (lambda (window)
       (when (and (window-live-p window)
                  (eq (window-frame window) frame)
                  (claude-code-ide-manager--valid-sidebar-window-p window))
         (when-let* ((scope (claude-code-ide-manager--scope-from-buffer
                             (window-buffer window))))
           (push scope visible-scopes))))
     'no-minibuf
     frame)
    (setq visible-scopes (nreverse visible-scopes))
    (or (and (= (length visible-scopes) 1)
             (car visible-scopes))
        (cl-find-if (lambda (scope)
                      (and (eq (plist-get scope :type) 'repo)
                           current-git-root
                           (equal (plist-get scope :git-root)
                                  current-git-root)))
                    visible-scopes)
        (let ((default-scope (claude-code-ide-manager--resolve-scope
                              (claude-code-ide-manager--default-target))))
          (when (member default-scope visible-scopes)
            default-scope))
        (car visible-scopes))))

(defun claude-code-ide-manager--scope-for-command ()
  "Return the manager scope for the current command context."
  (if claude-code-ide-manager--command-scope
      claude-code-ide-manager--command-scope
    (if (claude-code-ide-manager--manager-buffer-p)
        (claude-code-ide-manager--scope-from-buffer (current-buffer))
      (or (claude-code-ide-manager--visible-sidebar-scope-for-frame)
          (claude-code-ide-manager--resolve-scope
           (claude-code-ide-manager--default-target))))))

(defun claude-code-ide-manager--manager-buffers ()
  "Return all live manager buffers."
  (cl-remove-if-not #'claude-code-ide-manager--manager-buffer-p
                    (buffer-list)))

(defun claude-code-ide-manager--apply-window-compatibility ()
  "Hide the manager sidebar from common window-selection packages."
  (when (boundp 'winum-ignored-buffers-regexp)
    (add-to-list 'winum-ignored-buffers-regexp
                 (regexp-quote claude-code-ide-manager--buffer-name))
    (add-to-list 'winum-ignored-buffers-regexp
                 claude-code-ide-manager--buffer-name-regexp))
  (when (boundp 'aw-ignored-buffers)
    (add-to-list 'aw-ignored-buffers 'claude-code-ide-manager-mode)))

(with-eval-after-load 'winum
  (claude-code-ide-manager--apply-window-compatibility))

(with-eval-after-load 'ace-window
  (claude-code-ide-manager--apply-window-compatibility))

(claude-code-ide-manager--apply-window-compatibility)

(declare-function evil-set-initial-state "evil" (mode state))
(declare-function evil-define-key* "evil-core" (state keymap &rest bindings))

(defvar claude-code-ide-manager-mode-map (make-sparse-keymap)
  "Keymap for `claude-code-ide-manager-mode'.")

(define-key claude-code-ide-manager-mode-map (kbd "g") #'claude-code-ide-manager-avy-switch)
(define-key claude-code-ide-manager-mode-map (kbd "G") #'claude-code-ide-manager-refresh)
(define-key claude-code-ide-manager-mode-map (kbd "v") #'claude-code-ide-manager-toggle-grouped-view)
(define-key claude-code-ide-manager-mode-map (kbd "RET") #'claude-code-ide-manager-switch-at-point)
(define-key claude-code-ide-manager-mode-map (kbd "<mouse-1>") #'claude-code-ide-manager-switch-at-mouse)
(define-key claude-code-ide-manager-mode-map (kbd "SPC") #'claude-code-ide-manager-switch-at-point-preserve-focus)
(define-key claude-code-ide-manager-mode-map (kbd "n") #'claude-code-ide-manager-next-line)
(define-key claude-code-ide-manager-mode-map (kbd "p") #'claude-code-ide-manager-previous-line)
(define-key claude-code-ide-manager-mode-map (kbd "j") #'claude-code-ide-manager-next-line)
(define-key claude-code-ide-manager-mode-map (kbd "k") #'claude-code-ide-manager-previous-line)
(define-key claude-code-ide-manager-mode-map (kbd "C-j") #'claude-code-ide-manager-next-project-group)
(define-key claude-code-ide-manager-mode-map (kbd "C-k") #'claude-code-ide-manager-previous-project-group)
(define-key claude-code-ide-manager-mode-map (kbd "o") #'claude-code-ide-manager-open)
(define-key claude-code-ide-manager-mode-map (kbd "s") #'claude-code-ide-manager-start-session-at-point)
(define-key claude-code-ide-manager-mode-map (kbd "S") #'claude-code-ide-manager-start-session-at-point-skip-permissions)
(define-key claude-code-ide-manager-mode-map (kbd "a") #'claude-code-ide-attach)
(define-key claude-code-ide-manager-mode-map (kbd "A") #'claude-code-ide-attach-select)
(define-key claude-code-ide-manager-mode-map (kbd "X") #'claude-code-ide-manager-detach-at-point)
(define-key claude-code-ide-manager-mode-map (kbd "D") #'claude-code-ide-manager-detach-at-point)
(define-key claude-code-ide-manager-mode-map (kbd "P") #'claude-code-ide-manager-toggle-pin)
(define-key claude-code-ide-manager-mode-map (kbd "E") #'claude-code-ide-manager-edit-pin-order)
(define-key claude-code-ide-manager-mode-map (kbd "r") #'claude-code-ide-manager-rename-at-point)
(define-key claude-code-ide-manager-mode-map (kbd "R") #'claude-code-ide-manager-reset-layout-at-point)
(define-key claude-code-ide-manager-mode-map (kbd "c") #'claude-code-ide-manager-reattach-at-point)
(define-key claude-code-ide-manager-mode-map (kbd "K") #'claude-code-ide-manager-stop-at-point)
(define-key claude-code-ide-manager-mode-map (kbd "M-p") #'claude-code-ide-manager-move-up)
(define-key claude-code-ide-manager-mode-map (kbd "M-n") #'claude-code-ide-manager-move-down)
(define-key claude-code-ide-manager-mode-map (kbd "M-k") #'claude-code-ide-manager-move-up)
(define-key claude-code-ide-manager-mode-map (kbd "M-j") #'claude-code-ide-manager-move-down)
(define-key claude-code-ide-manager-mode-map (kbd "M-P") #'claude-code-ide-manager-move-group-up)
(define-key claude-code-ide-manager-mode-map (kbd "M-N") #'claude-code-ide-manager-move-group-down)
(define-key claude-code-ide-manager-mode-map (kbd "M-K") #'claude-code-ide-manager-move-group-up)
(define-key claude-code-ide-manager-mode-map (kbd "M-J") #'claude-code-ide-manager-move-group-down)
(define-key claude-code-ide-manager-mode-map (kbd "C-s") #'claude-code-ide-manager-sort-menu)
(define-key claude-code-ide-manager-mode-map (kbd "!") #'claude-code-ide-manager-clear-all-idle-state)
(define-key claude-code-ide-manager-mode-map (kbd "?") #'claude-code-ide-manager-dispatch)

(defvar claude-code-ide-manager-pin-order-mode-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "C-c C-c") #'claude-code-ide-manager-pin-order-apply)
    (define-key map (kbd "C-c C-k") #'claude-code-ide-manager-pin-order-cancel)
    (define-key map (kbd "C-c C-s") #'claude-code-ide-manager-sort-menu)
    (define-key map (kbd "M-p") #'claude-code-ide-manager-pin-order-move-up)
    (define-key map (kbd "M-n") #'claude-code-ide-manager-pin-order-move-down)
    (define-key map (kbd "M-k") #'claude-code-ide-manager-pin-order-move-up)
    (define-key map (kbd "M-j") #'claude-code-ide-manager-pin-order-move-down)
    (define-key map (kbd "M-P") #'claude-code-ide-manager-pin-order-move-group-up)
    (define-key map (kbd "M-N") #'claude-code-ide-manager-pin-order-move-group-down)
    (define-key map (kbd "M-K") #'claude-code-ide-manager-pin-order-move-group-up)
    (define-key map (kbd "M-J") #'claude-code-ide-manager-pin-order-move-group-down)
    map)
  "Keymap for `claude-code-ide-manager-pin-order-mode'.")
(dotimes (index 10)
  (let ((slot (if (= index 9) 10 (1+ index))))
    (define-key
     claude-code-ide-manager-mode-map
     (kbd (number-to-string (mod (1+ index) 10)))
     (lambda ()
       (interactive)
       (claude-code-ide-manager-switch-by-slot-preserve-focus slot)))))

(defun claude-code-ide-manager--setup-evil-state ()
  "Start manager and attach-select buffers in Evil emacs state.
No-op when Evil is unavailable."
  (when (fboundp 'evil-set-initial-state)
    (evil-set-initial-state 'claude-code-ide-manager-mode 'emacs)
    (evil-set-initial-state 'claude-code-ide-attach-select-mode 'emacs)))

(defun claude-code-ide-manager--setup-pin-order-evil-keys ()
  "Mirror pin-order editor M- bindings into Evil normal state.
Does nothing when Evil is not available.  Keymaps store M- keys
under the ESC prefix, so iterate that sub-keymap."
  (when (fboundp 'evil-define-key*)
    (let ((esc-map (lookup-key claude-code-ide-manager-pin-order-mode-map
                               (kbd "ESC"))))
      (when (keymapp esc-map)
        (map-keymap
         (lambda (event definition)
           (when (and (integerp event) (commandp definition))
             (evil-define-key* 'normal
                               claude-code-ide-manager-pin-order-mode-map
                               (vector 27 event) definition)))
         esc-map)))))

(with-eval-after-load 'evil
  (claude-code-ide-manager--setup-evil-state)
  (claude-code-ide-manager--setup-pin-order-evil-keys))

(claude-code-ide-manager--setup-evil-state)
(claude-code-ide-manager--setup-pin-order-evil-keys)

(define-derived-mode claude-code-ide-manager-mode special-mode "CC-Manager"
  "Major mode for the cc-manager sidebar."
  (setq truncate-lines t)
  (setq-local global-hl-line-mode nil)
  (setq-local claude-code-ide-manager--last-point-path nil)
  (add-hook 'post-command-hook #'claude-code-ide-manager--show-point-path nil t)
  (when (featurep 'hl-line)
    (hl-line-mode -1)))

(define-derived-mode claude-code-ide-manager-pin-order-mode text-mode
  "CC-Pin-Order"
  "Major mode for editing the complete manager pin order."
  (setq truncate-lines t))

(defun claude-code-ide-manager--serialize-item (item)
  "Convert manager ITEM to a persistable plist."
  (list :session-key (claude-code-ide-manager-item-session-key item)
        :directory (claude-code-ide-manager-item-directory item)
        :host (claude-code-ide-manager-item-host item)
        :zmx-name (claude-code-ide-manager-item-zmx-name item)
        :cli-type (claude-code-ide-manager-item-cli-type item)
        :custom-name (claude-code-ide-manager-item-custom-name item)
        :order (claude-code-ide-manager-item-order item)
        :created-at (claude-code-ide-manager-item-created-at item)
        :display-name (claude-code-ide-manager-item-display-name item)
        :secondary-text (claude-code-ide-manager-item-secondary-text item)
        :pinned (claude-code-ide-manager-item-pinned item)
        :order-key (claude-code-ide-manager-item-order-key item)
        :live-p (claude-code-ide-manager-item-live-p item)
        :group-metadata (claude-code-ide-manager--valid-group-metadata
                         (claude-code-ide-manager-item-group-metadata item)
                         (claude-code-ide-manager-item-host item)
                         (claude-code-ide-manager-item-directory item))))

(defun claude-code-ide-manager--deserialize-item (data)
  "Convert persisted DATA into an item, rejecting invalid remote metadata."
  (let* ((host (plist-get data :host))
         (directory (plist-get data :directory))
         (order (plist-get data :order))
         (custom-name (plist-get data :custom-name)))
    (if (and host
             (not (and (claude-code-ide-zmx--valid-host-p host)
                       (claude-code-ide-zmx--valid-name-p (plist-get data :zmx-name))
                       (claude-code-ide-zmx--valid-directory-p directory)
                       (memq (plist-get data :cli-type) '(claude codex opencode pi omp))
                       (stringp (plist-get data :session-key))
                       (not (string-empty-p (plist-get data :session-key)))
                       (or (null order) (and (integerp order) (> order 0)))
                       (or (null custom-name) (stringp custom-name)))))
        (progn
          (message "Ignored invalid remote history for %S. Discover the target again." host)
          nil)
      (make-claude-code-ide-manager-item
       :session-key (plist-get data :session-key)
       :directory directory
       :host host
       :zmx-name (plist-get data :zmx-name)
       :cli-type (plist-get data :cli-type)
       :custom-name custom-name
       :order (if host (or order 1) order)
       :created-at (plist-get data :created-at)
       :display-name (if host
                         (claude-code-ide-manager--remote-label
                          host directory (or order 1) custom-name)
                       (plist-get data :display-name))
       :secondary-text (if host directory (plist-get data :secondary-text))
       :pinned (plist-get data :pinned)
       :order-key (plist-get data :order-key)
       :live-p (and (null host) (plist-get data :live-p))
       :group-metadata (claude-code-ide-manager--valid-group-metadata
                        (plist-get data :group-metadata) host directory)))))

(defun claude-code-ide-manager--persistable-layout (layout)
  "Return LAYOUT without memory-only Project-view identity."
  (if (not (listp layout))
      layout
    (let (persistable)
      (while layout
        (let ((key (pop layout))
              (value (pop layout)))
          (unless
              (memq key
                    '(:project-view-buffer :project-view-name))
            (push key persistable)
            (push value persistable))))
      (nreverse persistable))))

(defun claude-code-ide-manager--serialize-layouts ()
  "Return persisted layout data as an alist."
  (let (layouts)
    (maphash
     (lambda (session-key layout)
       (push
        (cons
         session-key
         (claude-code-ide-manager--persistable-layout layout))
        layouts))
     claude-code-ide-manager--layouts)
    (nreverse layouts)))

(defun claude-code-ide-manager--serialize-scope-state ()
  "Return persisted scope view state as an alist."
  (let ((global-scope '(:type global))
        serialized)
    ;; Keep the legacy global alias synchronized until all callers are scope-aware.
    (claude-code-ide-manager--set-scope-items global-scope claude-code-ide-manager--items)
    (maphash
     (lambda (scope-key state)
       (push (cons scope-key
                   (append
                    (list :items (mapcar #'claude-code-ide-manager--serialize-item
                                         (plist-get state :items))
                          :selected-session-key
                          (plist-get state :selected-session-key)
                          :active-session-key
                          (plist-get state :active-session-key))
                    (when (equal scope-key "global")
                      (list :view (claude-code-ide-manager--normalize-view
                                   (plist-get state :view))
                            :group-order (plist-get state :group-order)))))
             serialized))
     claude-code-ide-manager--scope-state)
    (nreverse serialized)))

(defun claude-code-ide-manager--deserialize-scope-state (scopes)
  "Return hash table for persisted SCOPES."
  (let ((table (make-hash-table :test 'equal)))
    (dolist (entry scopes)
      (puthash (car entry)
               (append
                (list :items (delq nil (mapcar #'claude-code-ide-manager--deserialize-item
                                               (plist-get (cdr entry) :items)))
                      :selected-session-key
                      (plist-get (cdr entry) :selected-session-key)
                      :active-session-key
                      (plist-get (cdr entry) :active-session-key))
                (when (equal (car entry) "global")
                  (list :view (claude-code-ide-manager--normalize-view
                               (plist-get (cdr entry) :view))
                        :group-order
                        (claude-code-ide-manager--valid-group-order
                         (plist-get (cdr entry) :group-order)))))
               table))
    table))

(defun claude-code-ide-manager--deserialize-layouts (layouts)
  "Return hash table for persisted LAYOUTS."
  (let ((table (make-hash-table :test 'equal)))
    (dolist (entry layouts)
      (puthash (car entry) (cdr entry) table))
    table))

(defun claude-code-ide-manager--serialize-state ()
  "Return current manager state as a plist."
  (list :version claude-code-ide-manager--state-version
        :scopes (claude-code-ide-manager--serialize-scope-state)
        :layouts (claude-code-ide-manager--serialize-layouts)))

(defun claude-code-ide-manager--restore-state (data)
  "Restore manager state from persisted DATA."
  (setq claude-code-ide-manager--scope-state
        (if-let* ((scopes (plist-get data :scopes)))
            (claude-code-ide-manager--deserialize-scope-state scopes)
          (let ((table (make-hash-table :test 'equal)))
            (puthash "global"
                     (list :items (delq nil (mapcar #'claude-code-ide-manager--deserialize-item
                                                    (plist-get data :items)))
                           :view 'flat)
                     table)
            table)))
  (setq claude-code-ide-manager--items
        (claude-code-ide-manager--scope-items '(:type global)))
  (setq claude-code-ide-manager--layouts
        (claude-code-ide-manager--deserialize-layouts
         (plist-get data :layouts)))
  (maphash
   (lambda (scope-key state)
     (let ((active (plist-get state :active-session-key)))
       (when (and active
                  (claude-code-ide-manager--session-host active)
                  (not (buffer-live-p (claude-code-ide-manager--session-buffer active))))
         (puthash scope-key (plist-put state :active-session-key nil)
                  claude-code-ide-manager--scope-state))))
   claude-code-ide-manager--scope-state)
  (when (and claude-code-ide-manager--current-session-key
             (claude-code-ide-manager--session-host
              claude-code-ide-manager--current-session-key)
             (not (buffer-live-p
                   (claude-code-ide-manager--session-buffer
                    claude-code-ide-manager--current-session-key))))
    (setq claude-code-ide-manager--current-session-key nil)))

(defun claude-code-ide-manager--load-state ()
  "Load persisted manager state when enabled."
  (when claude-code-ide-manager-persist-state
    (claude-code-ide-manager--persist-register)
    (persist-load 'claude-code-ide-manager--persisted-state)
    (when (and (listp claude-code-ide-manager--persisted-state)
               (memq (or (plist-get claude-code-ide-manager--persisted-state :version) 0)
                     '(1 2 3 4)))
      (claude-code-ide-manager--restore-state
       claude-code-ide-manager--persisted-state))))

(defun claude-code-ide-manager--save-state ()
  "Persist current manager state when enabled."
  (when claude-code-ide-manager-persist-state
    (claude-code-ide-manager--persist-register)
    (setq claude-code-ide-manager--persisted-state
          (claude-code-ide-manager--serialize-state))
    (persist-save 'claude-code-ide-manager--persisted-state)))

(defun claude-code-ide-manager--initialize ()
  "Initialize manager persistence for the current Emacs session."
  (claude-code-ide-manager--load-state))

(defun claude-code-ide-manager--reset-state ()
  "Reset in-memory manager state."
  (setq claude-code-ide-manager--items nil)
  (setq claude-code-ide-manager--scope-state (make-hash-table :test 'equal))
  (setq claude-code-ide-manager--priority-visits (make-hash-table :test 'equal))
  (setq claude-code-ide-manager--uncleared-visits (make-hash-table :test 'equal))
  (setq claude-code-ide-manager--layouts (make-hash-table :test 'equal))
  (setq claude-code-ide-manager--current-session-key nil)
  (setq claude-code-ide-manager--persisted-state
        `(:version ,claude-code-ide-manager--state-version
                   :scopes nil
                   :layouts nil)))

(defun claude-code-ide-manager--item-by-session-key (scope-or-session-key
                                                     &optional session-key)
  "Return existing item matching SESSION-KEY within SCOPE-OR-SESSION-KEY.

When SESSION-KEY is nil, treat SCOPE-OR-SESSION-KEY as the session key and
default to the global scope for backward compatibility."
  (let ((scope (if session-key scope-or-session-key '(:type global)))
        (session-key (or session-key scope-or-session-key)))
    (cl-find-if (lambda (item)
                  (equal (claude-code-ide-manager-item-session-key item)
                         session-key))
                (claude-code-ide-manager--scope-items scope))))

(defun claude-code-ide-manager--all-items ()
  "Return every distinct manager item across scopes."
  (let (items)
    (maphash (lambda (_ state)
               (dolist (item (plist-get state :items))
                 (cl-pushnew item items :test #'eq)))
             claude-code-ide-manager--scope-state)
    (dolist (item claude-code-ide-manager--items)
      (cl-pushnew item items :test #'eq))
    items))

(defun claude-code-ide-manager--clear-manual-order ()
  "Clear stored manual order keys across every scope.
Return non-nil when any key was cleared."
  (let (cleared)
    (dolist (item (claude-code-ide-manager--all-items))
      (let ((key (claude-code-ide-manager-item-order-key item)))
        (when (and key (/= key most-positive-fixnum))
          (setf (claude-code-ide-manager-item-order-key item) nil)
          (setq cleared t))))
    (when cleared
      (claude-code-ide-manager--save-state))
    cleared))

(defun claude-code-ide-manager--replace-display-suffix
    (display-name old-suffix new-suffix)
  "Replace OLD-SUFFIX with NEW-SUFFIX in DISPLAY-NAME."
  (let ((pattern
         (concat "\\`\\(.*\\)"
                 (regexp-quote (format " · %s" old-suffix))
                 "\\(\\(?: \\[.*\\]\\)*\\)\\'")))
    (if (string-match pattern display-name)
        (let ((prefix (match-string 1 display-name))
              (tail (or (match-string 2 display-name) "")))
          (if new-suffix
              (format "%s · %s%s" prefix new-suffix tail)
            (format "%s%s" prefix tail)))
      (if new-suffix
          (format "%s · %s" display-name new-suffix)
        display-name))))

(defun claude-code-ide-manager--live-sessions ()
  "Return live Claude Code session records in stable fallback order."
  (let (sessions)
    (maphash
     (lambda (session-id _)
       (when-let* ((session (claude-code-ide--get-session session-id)))
         (when (process-live-p (claude-code-ide-session-process session))
           (push session sessions))))
     claude-code-ide--sessions)
    (sort sessions
          (lambda (left right)
            (let ((left-directory (claude-code-ide-session-directory left))
                  (right-directory (claude-code-ide-session-directory right)))
              (if (equal left-directory right-directory)
                  (< (claude-code-ide-session-order left)
                     (claude-code-ide-session-order right))
                (string< left-directory right-directory)))))))

(defun claude-code-ide-manager--live-session-keys ()
  "Return IDs for live Claude Code sessions."
  (mapcar #'claude-code-ide-session-id
          (claude-code-ide-manager--live-sessions)))

(defun claude-code-ide-manager--scope-sessions (scope sessions)
  "Return SESSIONS visible within SCOPE."
  (pcase (plist-get scope :type)
    ('global sessions)
    ('repo
     (cl-remove-if-not
      (lambda (session)
        (let ((root (claude-code-ide-manager--session-git-root session))
              (target-root (plist-get scope :git-root)))
          (if claude-code-ide-manager-repo-include-nested
              (and root (string-prefix-p target-root root))
            (equal root target-root))))
      sessions))
    (_ (error "Unknown manager scope: %S" scope))))

(defun claude-code-ide-manager--make-item (scope session)
  "Build a manager item for SESSION within SCOPE."
  (let* ((session-key (claude-code-ide-session-id session))
         (directory (claude-code-ide-session-directory session))
         (host (claude-code-ide-session-host session))
         (existing (claude-code-ide-manager--item-by-session-key scope session-key))
         (legacy
          (and (null host) (null existing)
               (cl-find-if
                (lambda (item)
                  (let ((old-key
                         (claude-code-ide-manager-item-session-key item)))
                    (and (null (claude-code-ide-manager-item-directory item))
                         (stringp old-key)
                         (file-name-absolute-p old-key)
                         (equal (file-name-as-directory
                                 (expand-file-name old-key))
                                (file-name-as-directory
                                 (expand-file-name directory))))))
                (claude-code-ide-manager--scope-items scope))))
         (existing (or existing legacy))
         (persisted-name
          (or (and existing
                   (claude-code-ide-manager-item-custom-name existing))
              (cl-loop for item in (claude-code-ide-manager--all-items)
                       when (and
                             (equal session-key
                                    (claude-code-ide-manager-item-session-key item))
                             (claude-code-ide-manager-item-custom-name item))
                       return (claude-code-ide-manager-item-custom-name item))))
         (order (claude-code-ide-session-order session))
         (display-name (claude-code-ide-manager--scope-display-name scope session))
         (group-metadata
          (or (claude-code-ide-manager--valid-group-metadata
               (claude-code-ide-session-group-metadata session) host directory)
              (and existing
                   (claude-code-ide-manager--valid-group-metadata
                    (claude-code-ide-manager-item-group-metadata existing)
                    host directory)))))
    (when (and persisted-name
               (null (claude-code-ide-session-custom-name session)))
      (claude-code-ide--set-session-custom-name session persisted-name))
    (claude-code-ide--set-session-group-metadata session group-metadata)
    (when legacy
      (setq claude-code-ide-manager--legacy-adopted-p t)
      (let ((old-key (claude-code-ide-manager-item-session-key legacy))
            (missing (make-symbol "missing")))
        (setf (claude-code-ide-manager-item-session-key legacy) session-key
              (claude-code-ide-manager-item-directory legacy) directory
              (claude-code-ide-manager-item-order legacy) order)
        (let ((layout (gethash old-key claude-code-ide-manager--layouts missing)))
          (unless (eq layout missing)
            (puthash session-key layout claude-code-ide-manager--layouts)
            (remhash old-key claude-code-ide-manager--layouts)))
        (when (equal (claude-code-ide-manager--scope-selected-session-key scope)
                     old-key)
          (claude-code-ide-manager--set-scope-selected-session-key scope session-key))
        (when (equal (claude-code-ide-manager--scope-active-session-key scope)
                     old-key)
          (claude-code-ide-manager--set-scope-active-session-key scope session-key))))
    (let ((custom-name (claude-code-ide-session-custom-name session)))
      (make-claude-code-ide-manager-item
       :session-key session-key
       :directory directory
       :host host
       :zmx-name (claude-code-ide-session-zmx-name session)
       :cli-type (claude-code-ide-session-cli-type session)
       :custom-name custom-name
       :order order
       :created-at (claude-code-ide-session-created-at session)
       :display-name (if custom-name
                         (claude-code-ide-manager--replace-display-suffix
                          display-name order custom-name)
                       display-name)
       :secondary-text (if host directory (abbreviate-file-name directory))
       :pinned (and existing (claude-code-ide-manager-item-pinned existing))
       :order-key (or (and existing
                           (claude-code-ide-manager-item-order-key existing))
                      most-positive-fixnum)
       :group-metadata group-metadata
       :live-p t))))


(defun claude-code-ide-manager--build-items (scope)
  "Merge live items with remembered remote targets in SCOPE."
  (let ((live (mapcar (lambda (session)
                        (claude-code-ide-manager--make-item scope session))
                      (claude-code-ide-manager--scope-sessions
                       scope (claude-code-ide-manager--live-sessions))))
        remembered)
    (when (eq (plist-get scope :type) 'global)
      (dolist (item (claude-code-ide-manager--scope-items scope))
        (when (and (claude-code-ide-manager-item-host item)
                   (not (cl-find (claude-code-ide-manager-item-session-key item) live
                                 :key #'claude-code-ide-manager-item-session-key
                                 :test #'equal)))
          (setf (claude-code-ide-manager-item-live-p item) nil)
          (push item remembered))))
    (append live (nreverse remembered))))

(defun claude-code-ide-manager--remember-remote-session (session)
  "Remember SESSION as disconnected without refresh or network requests."
  (when (claude-code-ide-session-host session)
    (let* ((scope '(:type global))
           (session-id (claude-code-ide-session-id session))
           (item (claude-code-ide-manager--make-item scope session)))
      (setf (claude-code-ide-manager-item-live-p item) nil)
      (claude-code-ide-manager--set-scope-items
       scope
       (cons item (cl-remove session-id (claude-code-ide-manager--scope-items scope)
                             :key #'claude-code-ide-manager-item-session-key :test #'equal)))
      (maphash
       (lambda (scope-key state)
         (when (equal session-id (plist-get state :active-session-key))
           (puthash scope-key (plist-put state :active-session-key nil)
                    claude-code-ide-manager--scope-state)))
       claude-code-ide-manager--scope-state)
      (when (equal session-id claude-code-ide-manager--current-session-key)
        (setq claude-code-ide-manager--current-session-key nil))
      (claude-code-ide-manager--save-state)
      item)))

(defun claude-code-ide-manager--sorted-items (items &optional ignore-pin-order scope view)
  "Return ordered Session ITEMS for SCOPE and VIEW.
IGNORE-PIN-ORDER bypasses pins and manual keys, not group boundaries."
  (let* ((scope (or scope '(:type global)))
         (grouped (and (eq (plist-get scope :type) 'global)
                       (eq (or view (claude-code-ide-manager--view scope)) 'grouped)))
         (labels (and grouped (claude-code-ide-manager--grouped-labels items)))
         (headings (and grouped (claude-code-ide-manager--group-headings items)))
         (positions (and grouped
                         (let ((table (make-hash-table :test 'equal))
                               (index 0))
                           (dolist (key (claude-code-ide-manager--group-order scope))
                             (unless (gethash key table)
                               (puthash key index table)
                               (setq index (1+ index))))
                           table)))
         (keys (and grouped (make-hash-table :test 'eq)))
         (base-predicate
          (pcase claude-code-ide-manager-sort-by
            ('name
             (lambda (left right)
               (let ((left-name
                      (or (and labels (gethash left labels))
                          (claude-code-ide-manager-item-display-name left)
                          (claude-code-ide-manager-item-session-key left)))
                     (right-name
                      (or (and labels (gethash right labels))
                          (claude-code-ide-manager-item-display-name right)
                          (claude-code-ide-manager-item-session-key right))))
                 (cond
                  ((string-version-lessp left-name right-name) t)
                  ((string-version-lessp right-name left-name) nil)
                  (t
                   (string< (claude-code-ide-manager-item-session-key left)
                            (claude-code-ide-manager-item-session-key right)))))))
            ('created-at
             (lambda (left right)
               (let ((left-created-at
                      (or (claude-code-ide-manager-item-created-at left) 0))
                     (right-created-at
                      (or (claude-code-ide-manager-item-created-at right) 0)))
                 (if (= left-created-at right-created-at)
                     (string< (claude-code-ide-manager-item-session-key left)
                              (claude-code-ide-manager-item-session-key right))
                   (< left-created-at right-created-at)))))
            (_
             (error "Unknown manager sort key: %S"
                    claude-code-ide-manager-sort-by))))
         (fallback-predicate
          (if claude-code-ide-manager-sort-reverse
              (lambda (left right)
                (funcall base-predicate right left))
            base-predicate)))
    (when grouped
      (dolist (item items)
        (puthash item (claude-code-ide-manager--group-key item) keys)))
    (sort (copy-sequence items)
          (lambda (left right)
            (cond
             ((and grouped (not (equal (gethash left keys) (gethash right keys))))
              (claude-code-ide-manager--group-less-p
               (gethash left keys) (gethash right keys) headings positions))
             (ignore-pin-order (funcall fallback-predicate left right))
             ((and (claude-code-ide-manager-item-pinned left)
                   (not (claude-code-ide-manager-item-pinned right)))
              t)
             ((and (claude-code-ide-manager-item-pinned right)
                   (not (claude-code-ide-manager-item-pinned left)))
              nil)
             ((/= (or (claude-code-ide-manager-item-order-key left)
                      most-positive-fixnum)
                  (or (claude-code-ide-manager-item-order-key right)
                      most-positive-fixnum))
              (< (or (claude-code-ide-manager-item-order-key left)
                     most-positive-fixnum)
                 (or (claude-code-ide-manager-item-order-key right)
                     most-positive-fixnum)))
             (t
              (funcall fallback-predicate left right)))))))

(defun claude-code-ide-manager--slot-map (items &optional sorted-p scope view)
  "Return quick slots for ITEMS, using SCOPE and VIEW unless SORTED-P."
  (let ((slots (make-hash-table :test 'equal))
        (slot 1))
    (dolist (item (if sorted-p items
                    (claude-code-ide-manager--sorted-items items nil scope view)))
      (when (<= slot 10)
        (puthash (claude-code-ide-manager-item-session-key item) slot slots)
        (setq slot (1+ slot))))
    slots))

(defun claude-code-ide-manager--buffer-local-value (variable buffer)
  "Return VARIABLE's value in BUFFER when VARIABLE is bound there."
  (when (buffer-live-p buffer)
    (condition-case nil
        (buffer-local-value variable buffer)
      (void-variable nil))))

(defun claude-code-ide-manager--session-idle-p (session-key)
  "Return non-nil when SESSION-KEY's live buffer is idle-enabled and idle."
  (when-let* ((buffer (claude-code-ide-manager--session-buffer session-key)))
    (and (claude-code-ide-manager--buffer-local-value
          'claude-code-ide-session-idle-enabled buffer)
         (claude-code-ide-manager--buffer-local-value
          'claude-code-ide-session-idle-p buffer))))

(defun claude-code-ide-manager--session-working-p (session-key)
  "Return non-nil when SESSION-KEY's live buffer has tracked activity."
  (when-let* ((buffer (claude-code-ide-manager--session-buffer session-key)))
    (and (claude-code-ide-manager--buffer-local-value
          'claude-code-ide-session-idle-enabled buffer)
         (claude-code-ide-manager--buffer-local-value
          'claude-code-ide-session-working-p buffer))))

(defun claude-code-ide-manager--session-agent-state (session-key)
  "Return the CLI-reported agent state for SESSION-KEY's live buffer, or nil."
  (when-let* ((buffer (claude-code-ide-manager--session-buffer session-key)))
    (claude-code-ide-manager--buffer-local-value 'claude-code-ide-session-agent-state buffer)))

(defun claude-code-ide-manager--session-priority (session-key)
  "Return SESSION-KEY's state rank, with lower ranks first."
  (pcase (claude-code-ide-manager--session-agent-state session-key)
    ('needs-input 0)
    ('failed 1)
    ('done 2)
    ('working 4)
    ('nil (cond
           ((claude-code-ide-manager--session-idle-p session-key) 3)
           ((claude-code-ide-manager--session-working-p session-key) 4)
           (t 5)))
    (_ 5)))

(defun claude-code-ide-manager--marker-gutter (item)
  "Return a fixed-width marker gutter for ITEM.
A CLI-reported agent state takes precedence over terminal-output
markers, which take precedence over the pin marker."
  (let* ((session-key (claude-code-ide-manager-item-session-key item))
         (agent-state (claude-code-ide-manager--session-agent-state session-key))
         (marker (cond
                  ((eq agent-state 'needs-input) claude-code-ide-manager--needs-input-glyph)
                  ((eq agent-state 'done) claude-code-ide-manager--done-glyph)
                  ((eq agent-state 'failed) claude-code-ide-manager--failed-glyph)
                  ((eq agent-state 'working) claude-code-ide-manager--working-glyph)
                  ((and (null agent-state)
                        (claude-code-ide-manager--session-idle-p session-key))
                   claude-code-ide-manager--bell-glyph)
                  ((and (null agent-state)
                        (claude-code-ide-manager--session-working-p session-key))
                   claude-code-ide-manager--working-glyph)
                  ((claude-code-ide-manager-item-pinned item)
                   claude-code-ide-manager--pin-glyph)
                  (t "")))
         (padding (max 0 (- claude-code-ide-manager--marker-gutter-width
                            (string-width marker)))))
    (concat marker (make-string padding ?\s))))

(defun claude-code-ide-manager--row-face (scope session-key)
  "Return the face to apply to SESSION-KEY's row within SCOPE."
  (let ((agent-state (claude-code-ide-manager--session-agent-state session-key)))
    (cond
     ((equal session-key
             (or (claude-code-ide-manager--scope-active-session-key scope)
                 claude-code-ide-manager--current-session-key))
      'claude-code-ide-manager-current-session-face)
     ((memq agent-state '(needs-input failed))
      'claude-code-ide-manager-attention-session-face)
     ((eq agent-state 'done)
      'claude-code-ide-manager-done-session-face)
     ((eq agent-state 'working)
      'claude-code-ide-manager-working-session-face)
     ((and (null agent-state) (claude-code-ide-manager--session-idle-p session-key))
      'claude-code-ide-manager-idle-session-face)
     ((and (null agent-state) (claude-code-ide-manager--session-working-p session-key))
      'claude-code-ide-manager-working-session-face))))

(defun claude-code-ide-manager--session-key-for-buffer (buffer)
  "Return the session key whose live buffer is BUFFER."
  (let (match)
    (maphash
     (lambda (session-id _)
       (when (null match)
         (let* ((session (claude-code-ide--get-session session-id))
                (process (claude-code-ide-session-process session))
                (session-buffer
                 (or (claude-code-ide-session-buffer session)
                     (cond
                      ((bufferp process)
                       (and (buffer-live-p process) process))
                      ((processp process)
                       (process-buffer process))))))
           (when (eq buffer session-buffer)
             (setq match (claude-code-ide-session-id session))))))
     claude-code-ide--sessions)
    match))

(defun claude-code-ide-manager--visible-layout-session-key (&optional frame)
  "Return the visible session key that best matches FRAME's restored layout."
  (let* ((frame (or frame (selected-frame)))
         (selected (selected-window))
         (windows (window-list frame 'no-minibuf))
         (ordered (if (memq selected windows)
                      (cons selected (delq selected windows))
                    windows))
         session-key)
    (while (and ordered (null session-key))
      (let* ((window (pop ordered))
             (buffer (window-buffer window)))
        (unless (claude-code-ide-manager--manager-buffer-p buffer)
          (setq session-key
                (claude-code-ide-manager--session-key-for-buffer buffer)))))
    session-key))

(defun claude-code-ide-manager--visible-window (&optional scope)
  "Return the live manager window for SCOPE when the sidebar is visible."
  (claude-code-ide-manager--sidebar-window scope))

(defun claude-code-ide-manager--refresh-on-idle-transition (&rest _args)
  "Refresh visible manager sidebars after an idle state transition."
  (claude-code-ide-manager--refresh-sidebar-state))

(defun claude-code-ide-manager--refresh-on-window-configuration-change ()
  "Reassert visible manager sidebars after window configuration changes."
  (unless claude-code-ide-manager--in-window-config-refresh
    (let* ((selected-window (selected-window))
           (selected-buffer (and (window-live-p selected-window)
                                 (window-buffer selected-window)))
           (manager-visible-p (cl-some
                               (lambda (window)
                                 (claude-code-ide-manager--manager-buffer-p
                                  (window-buffer window)))
                               (window-list nil 'no-minibuf)))
           (selected-scope (and (claude-code-ide-manager--manager-buffer-p
                                 selected-buffer)
                                (claude-code-ide-manager--scope-from-buffer
                                 selected-buffer)))
           (layout-session-key
            (and manager-visible-p
                 (claude-code-ide-manager--visible-layout-session-key)))
           (layout-session-changed
            (and layout-session-key
                 (not (equal layout-session-key
                             claude-code-ide-manager--current-session-key))))
           (claude-code-ide-manager--in-window-config-refresh t))
      (when layout-session-changed
        (setq claude-code-ide-manager--current-session-key layout-session-key))
      (claude-code-ide-manager--reassert-visible-sidebar-state)
      (when layout-session-changed
        (claude-code-ide-manager--set-scope-active-session-key
         '(:type global)
         layout-session-key)
        (claude-code-ide-manager--save-state)
        (claude-code-ide-manager--refresh-sidebar-state nil nil))
      (when selected-scope
        (when-let* ((sidebar-window
                     (claude-code-ide-manager--sidebar-window selected-scope)))
          (select-window sidebar-window))))))

(defun claude-code-ide-manager--session-status-snapshot ()
  "Return the current buffer's manager-visible idle/working status."
  (list (bound-and-true-p claude-code-ide-session-idle-enabled)
        (bound-and-true-p claude-code-ide-session-idle-p)
        (bound-and-true-p claude-code-ide-session-working-p)
        (bound-and-true-p claude-code-ide-session-agent-state)))

(defun claude-code-ide-manager--refresh-after-session-status-change (orig-fn &rest args)
  "Refresh the sidebar when ORIG-FN changes manager-visible session status."
  (let ((before (claude-code-ide-manager--session-status-snapshot)))
    (prog1 (apply orig-fn args)
      (let ((after (claude-code-ide-manager--session-status-snapshot)))
        (unless (eq (nth 3 before) (nth 3 after))
          (when-let* ((key (claude-code-ide-manager--session-key-for-buffer
                            (current-buffer))))
            (dolist (passes (list claude-code-ide-manager--priority-visits
                                  claude-code-ide-manager--uncleared-visits))
              (maphash
               (lambda (_scope record)
                 (let ((visited (plist-get record :visited)))
                   (when (gethash key visited)
                     (puthash key
                              (if (memq (nth 3 after) '(needs-input failed done))
                                  'attention
                                t)
                              visited))))
               passes))))
        (unless (equal before after)
          (claude-code-ide-manager--refresh-on-idle-transition))))))

(defun claude-code-ide-manager--install-idle-refresh-hooks ()
  "Refresh the manager sidebar when session idle state changes."
  (unless (memq #'claude-code-ide-manager--refresh-on-idle-transition
                claude-code-ide-session-idle-hook)
    (add-hook 'claude-code-ide-session-idle-hook
              #'claude-code-ide-manager--refresh-on-idle-transition))
  (unless (memq #'claude-code-ide-manager--refresh-on-idle-transition
                claude-code-ide-session-working-hook)
    (add-hook 'claude-code-ide-session-working-hook
              #'claude-code-ide-manager--refresh-on-idle-transition))
  (when (advice-member-p #'claude-code-ide-manager--refresh-on-idle-transition
                         'claude-code-ide-session-idle-reset-timer)
    (advice-remove 'claude-code-ide-session-idle-reset-timer
                   #'claude-code-ide-manager--refresh-on-idle-transition))
  (when (advice-member-p #'claude-code-ide-manager--refresh-on-idle-transition
                         'claude-code-ide-session-idle-disable)
    (advice-remove 'claude-code-ide-session-idle-disable
                   #'claude-code-ide-manager--refresh-on-idle-transition))
  (when (advice-member-p #'claude-code-ide-manager--refresh-on-idle-transition
                         'claude-code-ide-session-idle-clear-state)
    (advice-remove 'claude-code-ide-session-idle-clear-state
                   #'claude-code-ide-manager--refresh-on-idle-transition))
  (unless (advice-member-p #'claude-code-ide-manager--refresh-after-session-status-change
                           'claude-code-ide-session-idle-reset-timer)
    (advice-add 'claude-code-ide-session-idle-reset-timer
                :around #'claude-code-ide-manager--refresh-after-session-status-change))
  (unless (advice-member-p #'claude-code-ide-manager--refresh-after-session-status-change
                           'claude-code-ide-session-idle-disable)
    (advice-add 'claude-code-ide-session-idle-disable
                :around #'claude-code-ide-manager--refresh-after-session-status-change))
  (unless (advice-member-p #'claude-code-ide-manager--refresh-after-session-status-change
                           'claude-code-ide-session-idle-clear-state)
    (advice-add 'claude-code-ide-session-idle-clear-state
                :around #'claude-code-ide-manager--refresh-after-session-status-change))
  (unless (advice-member-p #'claude-code-ide-manager--refresh-after-session-status-change
                           'claude-code-ide-session-idle-set-agent-state)
    (advice-add 'claude-code-ide-session-idle-set-agent-state
                :around #'claude-code-ide-manager--refresh-after-session-status-change))
  (when (advice-member-p #'claude-code-ide-manager--refresh-after-session-status-change
                         'claude-code-ide-session-idle-record-activity)
    (advice-remove 'claude-code-ide-session-idle-record-activity
                   #'claude-code-ide-manager--refresh-after-session-status-change)))

(defun claude-code-ide-manager--install-window-config-refresh-hook ()
  "Install a hook that keeps visible manager windows behaving like sidebars."
  (unless (memq #'claude-code-ide-manager--refresh-on-window-configuration-change
                window-configuration-change-hook)
    (add-hook 'window-configuration-change-hook
              #'claude-code-ide-manager--refresh-on-window-configuration-change)))

(with-eval-after-load 'claude-code-ide-session-idle
  (claude-code-ide-manager--install-idle-refresh-hooks))

(claude-code-ide-manager--install-window-config-refresh-hook)

(defun claude-code-ide-manager-refresh-items (&optional scope state-loaded-p)
  "Refresh manager items for SCOPE from the live session registry.
When STATE-LOADED-P is non-nil, do not reload persisted state."
  (let* ((scope (or scope (claude-code-ide-manager--scope-for-command)))
         (claude-code-ide-manager--legacy-adopted-p nil)
         (items nil))
    (unless state-loaded-p
      (claude-code-ide-manager--load-state))
    (setq items (claude-code-ide-manager--build-items scope))
    (when (eq (plist-get scope :type) 'global)
      (claude-code-ide-manager--refresh-local-group-metadata items))
    (cl-mapc (lambda (item display-name)
               (setf (claude-code-ide-manager-item-display-name item)
                     display-name))
             items
             (claude-code-ide-manager--disambiguate-display-names items))
    (claude-code-ide-manager--set-scope-items scope items)
    (when claude-code-ide-manager--legacy-adopted-p
      (claude-code-ide-manager--save-state))
    items))

(defun claude-code-ide-manager--get-buffer (&optional scope)
  "Return the manager buffer for SCOPE."
  (let* ((scope (or scope '(:type global)))
         (buffer (get-buffer-create
                  (claude-code-ide-manager--buffer-name-for-scope scope))))
    (with-current-buffer buffer
      (unless (derived-mode-p 'claude-code-ide-manager-mode)
        (claude-code-ide-manager-mode))
      (setq-local claude-code-ide-manager--scope scope))
    buffer))

(defun claude-code-ide-manager--item-at-point ()
  "Return manager item referenced by point."
  (when-let* ((session-key (get-text-property (point) 'claude-code-ide-manager-session-key)))
    (claude-code-ide-manager--item-by-session-key
     (claude-code-ide-manager--scope-for-command)
     session-key)))

(defun claude-code-ide-manager--show-point-path ()
  "Show the current row's full path in the echo area.
This mirrors mouse hover text for keyboard navigation in the manager."
  (when (eq (current-buffer) (window-buffer (selected-window)))
    (when-let* ((session-key (get-text-property (point)
                                                'claude-code-ide-manager-session-key)))
      (claude-code-ide-manager--set-scope-selected-session-key
       (claude-code-ide-manager--scope-from-buffer (current-buffer))
       session-key))
    (let ((path (get-text-property (point) 'help-echo)))
      (unless (equal path claude-code-ide-manager--last-point-path)
        (setq claude-code-ide-manager--last-point-path path)
        (if path
            (message "%s" path)
          (message ""))))))

(defun claude-code-ide-manager--visible-session-keys (scope)
  "Return visible session keys for SCOPE in sidebar order."
  (mapcar #'claude-code-ide-manager-item-session-key
          (claude-code-ide-manager--sorted-items
           (claude-code-ide-manager--scope-items scope) nil scope)))

(defun claude-code-ide-manager--item-visible-name (item &optional grouped-label)
  "Return ITEM's visible name, optionally GROUPED-LABEL, with disconnected status."
  (let ((name (or grouped-label
                  (claude-code-ide-manager-item-display-name item))))
    (concat
     (if (or claude-code-ide-manager-show-session-order
             (claude-code-ide-manager-item-custom-name item))
         name
       (claude-code-ide-manager--replace-display-suffix
        name
        (format "%s" (claude-code-ide-manager-item-order item))
        nil))
     (when (and (claude-code-ide-manager-item-host item)
                (not (claude-code-ide-manager-item-live-p item)))
       " [disconnected]"))))

(defun claude-code-ide-manager--pin-order-item-names (items &optional view)
  "Return ordered (SESSION-KEY . NAME) rows for ITEMS in VIEW."
  (let* ((labels (and (eq view 'grouped)
                      (claude-code-ide-manager--grouped-labels items)))
         (bases (mapcar (lambda (item)
                          (claude-code-ide-manager--item-visible-name
                           item (and labels (gethash item labels))))
                        items))
         (counts (make-hash-table :test 'equal)))
    (dolist (base bases)
      (puthash base (1+ (gethash base counts 0)) counts))
    (cl-loop
     for item in items
     for base in bases
     for session-key = (claude-code-ide-manager-item-session-key item)
     for session = (and (not labels) claude-code-ide-manager-pin-order-show-titles
                        (> (gethash base counts) 1)
                        (claude-code-ide-manager--session-record session-key))
     for title = (and session (claude-code-ide-session-title session))
     collect
     (cons session-key
           (if (and (stringp title) (not (string-empty-p title)))
               (concat base " - "
                       (replace-regexp-in-string "[\r\n]+" " " title))
             base)))))

(defun claude-code-ide-manager--pin-order-capture (items)
  "Capture opening labels and grouping for the displayed ITEMS."
  (setq claude-code-ide-manager--pin-order-snapshot
        (claude-code-ide-manager--pin-order-item-names
         items claude-code-ide-manager--pin-order-view)
        claude-code-ide-manager--pin-order-grouping nil)
  (when (eq claude-code-ide-manager--pin-order-view 'grouped)
    (let ((groups (make-hash-table :test 'equal))
          (names (claude-code-ide-manager--group-headings items))
          headings previous-group)
      (dolist (item items)
        (let* ((key (claude-code-ide-manager--group-key item))
               (host (claude-code-ide-manager-item-host item))
               (heading (gethash key names)))
          (puthash (claude-code-ide-manager-item-session-key item) key groups)
          (unless (equal key previous-group)
            (push (list key
                        (if host (format "[%s] %s" host (car heading)) (car heading))
                        (cdr heading))
                  headings)
            (setq previous-group key))))
      (setq claude-code-ide-manager--pin-order-grouping
            (list :groups groups :headings (nreverse headings)
                  :flat-order
                  (mapcar #'claude-code-ide-manager-item-session-key
                          (claude-code-ide-manager--sorted-items
                           items nil claude-code-ide-manager--pin-order-scope 'flat)))))))

(defun claude-code-ide-manager--render-pin-order-editor (snapshot)
  "Render ordered SNAPSHOT rows with any captured fixed headings."
  (let ((inhibit-read-only t)
        (groups (plist-get claude-code-ide-manager--pin-order-grouping :groups))
        (headings (plist-get claude-code-ide-manager--pin-order-grouping :headings)))
    (erase-buffer)
    (cl-loop for (session-key . name) in snapshot
             for index from 1
             for group = (and groups (gethash session-key groups))
             do
             (when (and headings (equal (caar headings) group))
               (let ((heading (pop headings))
                     (start (point)))
                 (claude-code-ide-manager--insert-group-heading
                  (nth 1 heading) (nth 2 heading) (car heading))
                 (put-text-property start (point) 'read-only t)))
             (insert (format "%d. " index))
             (let ((name-start (point)))
               (insert name)
               (add-text-properties
                name-start (point)
                (list 'claude-code-ide-manager-session-key session-key
                      'rear-nonsticky '(claude-code-ide-manager-session-key))))
             (insert "\n"))
    (goto-char (or (text-property-not-all
                    (point-min) (point-max) 'claude-code-ide-manager-session-key nil)
                   (point-min)))
    (beginning-of-line)))

(defun claude-code-ide-manager--pin-order-resync ()
  "Rebuild the order editor with current sorting and its captured view."
  (let* ((scope claude-code-ide-manager--pin-order-scope)
         (items (claude-code-ide-manager--sorted-items
                 (claude-code-ide-manager-refresh-items scope) t scope
                 claude-code-ide-manager--pin-order-view)))
    (unless items
      (user-error "No Sessions in the selected manager scope"))
    (claude-code-ide-manager--pin-order-capture items)
    (claude-code-ide-manager--render-pin-order-editor
     claude-code-ide-manager--pin-order-snapshot)
    (message "The editor reloaded rows and replaced unsaved edits.")))

(defun claude-code-ide-manager--pin-order-renumber ()
  "Renumber Session rows without changing headings or empty lines."
  (save-excursion
    (goto-char (point-min))
    (let ((index 1))
      (while (< (point) (point-max))
        (unless (or (looking-at-p "^$")
                    (get-text-property (point) 'claude-code-ide-manager-group-heading))
          (unless (looking-at "[0-9]+\\.")
            (user-error "Cannot renumber malformed row %d" index))
          (replace-match (format "%d." index) t t)
          (setq index (1+ index)))
        (forward-line 1)))))

(defun claude-code-ide-manager--pin-order-row-key ()
  "Return the hidden Session ID on the current numbered editor row."
  (save-excursion
    (beginning-of-line)
    (when (looking-at "[0-9]+\\. ")
      (get-text-property (match-end 0) 'claude-code-ide-manager-session-key))))

(defun claude-code-ide-manager--pin-order-move-row (direction)
  "Move the current Session row in DIRECTION within its opening group."
  (let* ((key (claude-code-ide-manager--pin-order-row-key))
         (current-start (line-beginning-position))
         (current-end (line-beginning-position 2))
         (groups (plist-get claude-code-ide-manager--pin-order-grouping :groups))
         (neighbor-start
          (save-excursion
            (while (and (zerop (forward-line direction))
                        (looking-at-p "^$")))
            (point)))
         (neighbor-key (save-excursion
                         (goto-char neighbor-start)
                         (claude-code-ide-manager--pin-order-row-key))))
    (when (and key neighbor-key (/= neighbor-start current-start)
               (or (null groups)
                   (equal (gethash key groups) (gethash neighbor-key groups))))
      (let ((neighbor-end (save-excursion
                            (goto-char neighbor-start)
                            (line-beginning-position 2)))
            (marker (copy-marker current-start)))
        (unwind-protect
            (progn
              (atomic-change-group
                (transpose-regions current-start current-end neighbor-start neighbor-end)
                (claude-code-ide-manager--pin-order-renumber))
              (goto-char marker)
              (beginning-of-line))
          (set-marker marker nil))))))

(defun claude-code-ide-manager-pin-order-move-up ()
  "Move the current pin-order row up."
  (interactive)
  (claude-code-ide-manager--pin-order-move-row -1))

(defun claude-code-ide-manager-pin-order-move-down ()
  "Move the current pin-order row down."
  (interactive)
  (claude-code-ide-manager--pin-order-move-row 1))

(defun claude-code-ide-manager--pin-order-block-starts ()
  "Return group heading line positions in buffer order."
  (save-excursion
    (goto-char (point-min))
    (let (starts)
      (while (< (point) (point-max))
        (when (get-text-property (point) 'claude-code-ide-manager-group-heading)
          (push (point) starts))
        (forward-line 1))
      (nreverse starts))))

(defun claude-code-ide-manager--pin-order-move-group (direction)
  "Move the group block at point in DIRECTION and keep captured headings in sync."
  (let ((headings (plist-get claude-code-ide-manager--pin-order-grouping :headings)))
    (unless headings
      (user-error "The flat order editor has no project groups"))
    (let* ((starts (claude-code-ide-manager--pin-order-block-starts))
           (line (line-beginning-position))
           (index (cl-position-if (lambda (start) (<= start line)) starts :from-end t))
           (target (and index (+ index direction))))
      (when (and index target (>= target 0) (< target (length starts)))
        (let* ((low (min index target))
               (first-start (nth low starts))
               (middle (nth (1+ low) starts))
               (end (or (nth (+ low 2) starts) (point-max)))
               (ordered (copy-sequence headings))
               (marker (copy-marker (point))))
          (cl-rotatef (nth low ordered) (nth (1+ low) ordered))
          (unwind-protect
              (progn
                (atomic-change-group
                  (let ((inhibit-read-only t))
                    (transpose-regions first-start middle middle end))
                  (claude-code-ide-manager--pin-order-renumber))
                (setq claude-code-ide-manager--pin-order-grouping
                      (plist-put claude-code-ide-manager--pin-order-grouping
                                 :headings ordered))
                (goto-char marker)
                (beginning-of-line))
            (set-marker marker nil)))))))

(defun claude-code-ide-manager-pin-order-move-group-up ()
  "Move the current group block up."
  (interactive)
  (claude-code-ide-manager--pin-order-move-group -1))

(defun claude-code-ide-manager-pin-order-move-group-down ()
  "Move the current group block down."
  (interactive)
  (claude-code-ide-manager--pin-order-move-group 1))

(defun claude-code-ide-manager--validate-pin-order-editor ()
  "Validate all editor rows and return their ordered Session IDs."
  (let* ((snapshot claude-code-ide-manager--pin-order-snapshot)
         (groups (plist-get claude-code-ide-manager--pin-order-grouping :groups))
         (headings (plist-get claude-code-ide-manager--pin-order-grouping :headings))
         (opening (make-hash-table :test 'equal))
         (seen (make-hash-table :test 'equal))
         (row-number 0)
         current-group keys)
    (dolist (row snapshot)
      (puthash (car row) row opening))
    (save-excursion
      (goto-char (point-min))
      (while (< (point) (point-max))
        (cond
         ((looking-at-p "^$"))
         ((and groups (get-text-property (point) 'claude-code-ide-manager-group-heading))
          (let* ((identity (get-text-property (point) 'claude-code-ide-manager-group-heading))
                 (heading (pop headings))
                 (end (line-end-position)))
            (unless (and heading
                         (equal identity (car heading))
                         (equal (buffer-substring-no-properties (point) end) (nth 1 heading))
                         (not (text-property-not-all
                               (point) end 'claude-code-ide-manager-group-heading identity))
                         (not (text-property-not-all
                               (point) end 'claude-code-ide-manager-session-key nil)))
              (user-error "A fixed heading changed. Reopen the order editor"))
            (setq current-group identity)))
         (t
          (cl-incf row-number)
          (unless (looking-at "[0-9]+\\. \\(.+\\)$")
            (user-error "Malformed row %d" row-number))
          (let* ((name (match-string-no-properties 1))
                 (name-start (match-beginning 1))
                 (name-end (match-end 1))
                 (session-key (get-text-property name-start 'claude-code-ide-manager-session-key))
                 (snapshot-row (and session-key (gethash session-key opening))))
            (unless (and session-key
                         (equal (next-single-property-change
                                 name-start 'claude-code-ide-manager-session-key nil name-end)
                                name-end)
                         (equal (get-text-property
                                 (1- name-end) 'claude-code-ide-manager-session-key)
                                session-key))
              (user-error "Row %d has no complete Session identity" row-number))
            (unless snapshot-row
              (user-error "Row %d has a foreign Session identity" row-number))
            (when (gethash session-key seen)
              (user-error "A Session appears more than once"))
            (unless (equal name (cdr snapshot-row))
              (user-error "Row %d has a changed Session name" row-number))
            (when (and groups (not (equal (gethash session-key groups) current-group)))
              (user-error "A Session moved to another project group"))
            (puthash session-key t seen)
            (push session-key keys))))
        (forward-line 1)))
    (when headings
      (user-error "A fixed heading is missing. Reopen the order editor"))
    (dolist (row snapshot)
      (unless (gethash (car row) seen)
        (user-error "A snapshot Session is missing")))
    (if groups
        (let ((current (make-hash-table :test 'equal)))
          (dolist (item (claude-code-ide-manager--scope-items
                         claude-code-ide-manager--pin-order-scope))
            (puthash (claude-code-ide-manager-item-session-key item)
                     (claude-code-ide-manager--group-key item) current))
          (dolist (row snapshot)
            (unless (gethash (car row) current)
              (user-error "A Session vanished. Reopen the order editor"))
            (unless (equal (gethash (car row) groups) (gethash (car row) current))
              (user-error "A project group changed. Reopen the order editor"))))
      (let ((live-visible-keys
             (mapcar #'claude-code-ide-session-id
                     (claude-code-ide-manager--scope-sessions
                      claude-code-ide-manager--pin-order-scope
                      (claude-code-ide-manager--live-sessions)))))
        (dolist (row snapshot)
          (unless (member (car row) live-visible-keys)
            (user-error "A snapshot Session is no longer live in this scope")))))
    (nreverse keys)))

(defun claude-code-ide-manager-pin-order-apply ()
  "Validate and apply the complete Session order, then clear scope pins."
  (interactive)
  (let* ((scope claude-code-ide-manager--pin-order-scope)
         (grouping claude-code-ide-manager--pin-order-grouping)
         (session-keys (claude-code-ide-manager--validate-pin-order-editor)))
    (unless grouping
      (claude-code-ide-manager-refresh-items scope))
    (when grouping
      (let ((groups (plist-get grouping :groups))
            sequence)
        (dolist (key session-keys)
          (cl-pushnew (gethash key groups) sequence :test #'equal))
        (claude-code-ide-manager--store-group-order scope (nreverse sequence)))
      (setq session-keys
            (claude-code-ide-manager--merge-group-order
             (plist-get grouping :flat-order) session-keys (plist-get grouping :groups))))
    (let ((by-key (make-hash-table :test 'equal)))
      (dolist (item (claude-code-ide-manager--scope-items scope))
        (puthash (claude-code-ide-manager-item-session-key item) item by-key))
      (unless (cl-every (lambda (key) (gethash key by-key)) session-keys)
        (user-error "A snapshot Session vanished before apply"))
      (dolist (item (claude-code-ide-manager--scope-items scope))
        (setf (claude-code-ide-manager-item-pinned item) nil))
      (cl-loop for key in session-keys
               for order-key from 1
               do (setf (claude-code-ide-manager-item-order-key (gethash key by-key)) order-key))
      (claude-code-ide-manager--save-state)
      (claude-code-ide-manager--render scope)
      (set-buffer-modified-p nil)
      (claude-code-ide-manager--close-pin-order-editor)
      (message "The manager saved the Session order and cleared all pins."))))

(defun claude-code-ide-manager-pin-order-cancel ()
  "Discard pin-order edits and close the editor."
  (interactive)
  (set-buffer-modified-p nil)
  (claude-code-ide-manager--close-pin-order-editor))

(defun claude-code-ide-manager--close-pin-order-editor ()
  "Close the current pin-order editor and restore its content buffer."
  (let ((editor (current-buffer))
        (return-window claude-code-ide-manager--pin-order-return-window)
        (return-buffer claude-code-ide-manager--pin-order-return-buffer))
    (when (and (window-live-p return-window)
               (buffer-live-p return-buffer))
      (set-window-buffer return-window return-buffer)
      (select-window return-window))
    (kill-buffer editor)))

;;;###autoload
(defun claude-code-ide-manager-edit-pin-order ()
  "Edit the complete Session order using the selected manager scope and view."
  (interactive)
  (let* ((scope (claude-code-ide-manager--scope-for-command))
         (view (claude-code-ide-manager--view scope))
         (items (claude-code-ide-manager-refresh-items scope))
         (items (claude-code-ide-manager--sorted-items items nil scope view)))
    (unless items
      (user-error "No Sessions in the selected manager scope"))
    (let* ((window (claude-code-ide-manager--content-window))
           (return-buffer (window-buffer window))
           (editor (generate-new-buffer "*claude-code-manager-pin-order*")))
      (with-current-buffer editor
        (claude-code-ide-manager-pin-order-mode)
        (setq-local claude-code-ide-manager--pin-order-scope scope
                    claude-code-ide-manager--pin-order-view view
                    claude-code-ide-manager--pin-order-return-window window
                    claude-code-ide-manager--pin-order-return-buffer return-buffer)
        (claude-code-ide-manager--pin-order-capture items)
        (claude-code-ide-manager--render-pin-order-editor
         claude-code-ide-manager--pin-order-snapshot))
      (set-window-buffer window editor)
      (select-window window)
      (message
       "C-c C-c applies. C-c C-k cancels. M-p/M-k move rows. M-P/M-K move groups."))))

(defun claude-code-ide-manager--insert-item (scope item slot &optional grouped-label)
  "Insert ITEM with SLOT in SCOPE, optionally using GROUPED-LABEL.
Reserve one active-marker cell and two status-marker cells before SLOT."
  (let* ((start (point))
         (session-key (claude-code-ide-manager-item-session-key item))
         (current-p
          (equal session-key
                 (or (claude-code-ide-manager--scope-active-session-key scope)
                     claude-code-ide-manager--current-session-key))))
    (insert (if current-p
                (propertize
                 "▌" 'display
                 (propertize "▌" 'face
                             'claude-code-ide-manager-current-marker-face))
              " "))
    (insert (claude-code-ide-manager--marker-gutter item))
    (insert (propertize " " 'display '(space :align-to 3)))
    (insert (if (numberp slot) (format "%2d." slot) " - "))
    (insert " ")
    (let ((name-start (point)))
      (insert (claude-code-ide-manager--item-visible-name item grouped-label) "\n")
      (when-let* ((host (and (null grouped-label)
                             (claude-code-ide-manager-item-host item)))
                  (prefix (format "[%s]" host))
                  (end (+ name-start (length prefix)))
                  ((<= end (1- (point))))
                  ((equal (buffer-substring-no-properties name-start end) prefix)))
        (put-text-property name-start end
                           'face 'claude-code-ide-manager-host-face))
      (put-text-property name-start (min (1+ name-start) (1- (point)))
                         'claude-code-ide-manager-session-name-start t))
    (add-text-properties
     start (1- (point))
     '(mouse-face highlight))
    (add-text-properties
     start (point)
     (append
      (list 'claude-code-ide-manager-session-key session-key
            'help-echo
            (if (eq (plist-get scope :type) 'global)
                (let* ((branch (plist-get (claude-code-ide-manager-item-group-metadata item) :branch))
                       (path (or (claude-code-ide-manager-item-secondary-text item)
                                 (claude-code-ide-manager-item-directory item)))
                       (details (if branch (format "%s [%s]" path branch) path)))
                  (if (and (claude-code-ide-manager-item-host item)
                           (not (claude-code-ide-manager-item-live-p item)))
                      (format "%s. Session is disconnected. Press c to reattach." details)
                    details))
              (claude-code-ide-manager--session-help-echo
               session-key (claude-code-ide-manager-item-secondary-text item))))
      (when-let* ((face (claude-code-ide-manager--row-face
                         scope session-key)))
        (list 'face face))))))

(defun claude-code-ide-manager--insert-group-heading (text path &optional identity)
  "Insert non-selectable heading TEXT with PATH and optional IDENTITY."
  (let ((start (point)))
    (insert text "\n")
    (set-text-properties
     start (point)
     (list 'face (if (eq (car-safe identity) 'host)
                     'claude-code-ide-manager-host-face
                   'font-lock-keyword-face)
           'help-echo path
           'claude-code-ide-manager-group-heading identity 'rear-nonsticky t))))

(defun claude-code-ide-manager-toggle-grouped-view ()
  "Toggle global grouped view without switching or acknowledging a Session."
  (interactive)
  (let* ((scope '(:type global))
         (buffer (get-buffer (claude-code-ide-manager--buffer-name-for-scope scope)))
         (window (and buffer (get-buffer-window buffer t)))
         (selected (or (and window
                            (with-current-buffer buffer
                              (get-text-property (window-point window)
                                                 'claude-code-ide-manager-session-key)))
                       (claude-code-ide-manager--scope-selected-session-key scope)))
         (state (copy-sequence (or (claude-code-ide-manager--scope-state-entry scope)
                                   (list :items claude-code-ide-manager--items)))))
    (setq state (plist-put state :view
                           (if (eq (claude-code-ide-manager--view scope) 'grouped)
                               'flat 'grouped)))
    (when selected (setq state (plist-put state :selected-session-key selected)))
    (claude-code-ide-manager--set-scope-state-entry scope state)
    (claude-code-ide-manager--save-state)
    (when buffer
      (claude-code-ide-manager--render scope)
      (dolist (visible (get-buffer-window-list buffer nil t))
        (set-window-point visible (with-current-buffer buffer (point)))))
    (message "Global manager view: %s" (plist-get state :view))))

(defun claude-code-ide-manager--render (&optional scope)
  "Render the manager sidebar for SCOPE."
  (let* ((scope (or scope (claude-code-ide-manager--scope-for-command)))
         (items (claude-code-ide-manager--sorted-items
                 (claude-code-ide-manager--scope-items scope) nil scope))
         (visible-session-keys (mapcar #'claude-code-ide-manager-item-session-key items))
         (grouped (eq (claude-code-ide-manager--view scope) 'grouped))
         (labels (and grouped (claude-code-ide-manager--grouped-labels items)))
         (headings (and grouped (claude-code-ide-manager--group-headings items)))
         (active-session-key (claude-code-ide-manager--scope-active-session-key scope)))
    (with-current-buffer (claude-code-ide-manager--get-buffer scope)
      (let* ((selection-window
              (or (claude-code-ide-manager--sidebar-window scope)
                  (claude-code-ide-manager--visible-manager-window scope)))
             (stored-session-key
              (claude-code-ide-manager--scope-selected-session-key scope))
             (selected-session-key
              (or (and (window-live-p selection-window)
                       (get-text-property
                        (window-point selection-window)
                        'claude-code-ide-manager-session-key))
                  stored-session-key
                  (get-text-property (point) 'claude-code-ide-manager-session-key)))
             (inhibit-read-only t)
             (slots (claude-code-ide-manager--slot-map items t))
             previous-group previous-host)
        (erase-buffer)
        (dolist (item items)
          (when grouped
            (let* ((key (claude-code-ide-manager--group-key item))
                   (host (claude-code-ide-manager-item-host item))
                   (heading (gethash key headings)))
              (unless (equal key previous-group)
                (when (and host (not (equal host previous-host)))
                  (claude-code-ide-manager--insert-group-heading
                   (format "[%s]" host) host (list 'host host)))
                (claude-code-ide-manager--insert-group-heading
                 (concat (if host "  " "") (car heading)) (cdr heading) key)
                (setq previous-group key previous-host host))))
          (claude-code-ide-manager--insert-item
           scope item (gethash (claude-code-ide-manager-item-session-key item) slots)
           (and labels (gethash item labels))))
        (goto-char (point-min))
        (when-let* ((target-session-key
                     (cond
                      ((and selected-session-key
                            (member selected-session-key visible-session-keys))
                       selected-session-key)
                      ((and active-session-key
                            (member active-session-key visible-session-keys))
                       active-session-key)
                      ((and claude-code-ide-manager--current-session-key
                            (member claude-code-ide-manager--current-session-key
                                    visible-session-keys))
                       claude-code-ide-manager--current-session-key))))
          (claude-code-ide-manager--set-scope-selected-session-key
           scope target-session-key)
          (claude-code-ide-manager--move-point-to-session-key
           target-session-key))))))

(defun claude-code-ide-manager--content-window ()
  "Return a non-sidebar content window for layout operations."
  (or (cl-find-if (lambda (window)
                    (and (not (window-parameter window 'window-side))
                         (not (window-parameter
                               window
                               'claude-code-ide-manager-collocated))))
                  (window-list nil 'no-minibuf))
      (selected-window)))

(defun claude-code-ide-manager--treemacs-window ()
  "Return the visible Treemacs sidebar window when available."
  (cl-find-if
   (lambda (window)
     (when-let* ((buffer (window-buffer window)))
       (with-current-buffer buffer
         (and (eq major-mode 'treemacs-mode)
              (eq (window-parameter window 'window-side) 'left)))))
   (window-list nil 'no-minibuf)))

(defun claude-code-ide-manager--treemacs-visible-p ()
  "Return non-nil when Treemacs is currently visible in a sidebar."
  (not (null (claude-code-ide-manager--treemacs-window))))

(defun claude-code-ide-manager--collocated-sidebar-height (treemacs-window)
  "Return the Treemacs top-pane height in a collocated sidebar."
  (let* ((total (max 2 (window-total-height treemacs-window)))
         (max-top (1- total)))
    (pcase claude-code-ide-manager-treemacs-split-policy
      ('adaptive (max 1 (min max-top (/ (* total 3) 4))))
      (_ (max 1 (min max-top (round (/ total 2.0))))))))

(defun claude-code-ide-manager--collocated-treemacs-params (treemacs-window)
  "Capture Treemacs window parameters used by collocation."
  (list :window-side (window-parameter treemacs-window 'window-side)
        :no-delete-other-windows (window-parameter treemacs-window 'no-delete-other-windows)
        :no-other-window (window-parameter treemacs-window 'no-other-window)
        :window-size-fixed (window-parameter treemacs-window 'window-size-fixed)))

(defun claude-code-ide-manager--restore-collocated-treemacs-params
    (treemacs-window treemacs-params)
  "Restore TREEMACS-WINDOW using TREEMACS-PARAMS."
  (when (window-live-p treemacs-window)
    (set-window-parameter treemacs-window
                          'window-side
                          (plist-get treemacs-params :window-side))
    (set-window-parameter treemacs-window
                          'no-delete-other-windows
                          (plist-get treemacs-params :no-delete-other-windows))
    (set-window-parameter treemacs-window
                          'no-other-window
                          (plist-get treemacs-params :no-other-window))
    (set-window-parameter treemacs-window
                          'window-size-fixed
                          (plist-get treemacs-params :window-size-fixed))))

(defun claude-code-ide-manager--sidebar-window (&optional scope)
  "Return the manager-owned sidebar window for SCOPE."
  (let ((buffer (claude-code-ide-manager--get-buffer scope)))
    (cl-find-if
     (lambda (window)
       (and (window-live-p window)
            (eq (window-buffer window) buffer)
            (claude-code-ide-manager--valid-sidebar-window-p window)))
     (window-list nil 'no-minibuf))))

(defun claude-code-ide-manager--visible-manager-window (&optional scope)
  "Return any visible window displaying the manager buffer for SCOPE."
  (let ((buffer (claude-code-ide-manager--get-buffer scope)))
    (cl-find-if
     (lambda (window)
       (and (window-live-p window)
            (eq (window-buffer window) buffer)))
     (window-list nil 'no-minibuf))))

(defun claude-code-ide-manager--stale-collocated-sidebar-window (&optional scope)
  "Return a stale collocated manager window for SCOPE when Treemacs is gone."
  (let ((buffer (claude-code-ide-manager--get-buffer scope)))
    (cl-find-if
     (lambda (window)
       (and (window-live-p window)
            (eq (window-buffer window) buffer)
            (window-parameter window 'claude-code-ide-manager-collocated)
            (not (claude-code-ide-manager--valid-collocated-sidebar-window-p
                  window))))
     (window-list nil 'no-minibuf))))

(defun claude-code-ide-manager--valid-standalone-sidebar-window-p (window)
  "Return non-nil when WINDOW is a valid standalone manager sidebar."
  (and (window-live-p window)
       (window-parameter window 'claude-code-ide-manager-sidebar)
       (not (window-parameter window 'claude-code-ide-manager-collocated))
       (eq (window-parameter window 'window-side) 'left)
       (window-at-side-p window 'left)))

(defun claude-code-ide-manager--valid-collocated-sidebar-window-p (window)
  "Return non-nil when WINDOW is a valid collocated manager sidebar."
  (when-let* ((treemacs-window (claude-code-ide-manager--treemacs-window)))
    (and (window-live-p window)
         (window-parameter window 'claude-code-ide-manager-sidebar)
         (window-parameter window 'claude-code-ide-manager-collocated)
         (claude-code-ide-manager--window-collocated-with-treemacs-p
          window treemacs-window))))

(defun claude-code-ide-manager--valid-sidebar-window-p (window)
  "Return non-nil when WINDOW is a valid manager-owned sidebar."
  (or (claude-code-ide-manager--valid-standalone-sidebar-window-p window)
      (claude-code-ide-manager--valid-collocated-sidebar-window-p window)))

(defun claude-code-ide-manager--visible-sidebar-scopes ()
  "Return the scopes whose manager sidebars are currently visible."
  (let (scopes)
    (dolist (buffer (claude-code-ide-manager--manager-buffers))
      (when-let* ((scope (claude-code-ide-manager--scope-from-buffer buffer)))
        (when (claude-code-ide-manager--sidebar-window scope)
          (push scope scopes))))
    (nreverse scopes)))

(defun claude-code-ide-manager--adopt-visible-sidebar-window (window)
  "Mark WINDOW as a manager-owned sidebar without changing its geometry."
  (set-window-parameter window 'claude-code-ide-manager-sidebar t)
  (if-let* ((treemacs-window (claude-code-ide-manager--treemacs-window)))
      (if (claude-code-ide-manager--window-collocated-with-treemacs-p
           window treemacs-window)
          (let ((treemacs-params
                 (claude-code-ide-manager--collocated-treemacs-params
                  treemacs-window)))
            (set-window-parameter window 'claude-code-ide-manager-collocated t)
            (set-window-parameter
             window
             'claude-code-ide-manager-collocated-treemacs-params
             treemacs-params))
        (set-window-parameter window 'claude-code-ide-manager-collocated nil)
        (set-window-parameter window
                              'claude-code-ide-manager-collocated-treemacs-params
                              nil))
    (set-window-parameter window 'claude-code-ide-manager-collocated nil)
    (set-window-parameter window
                          'claude-code-ide-manager-collocated-treemacs-params
                          nil)))

(defun claude-code-ide-manager--adopt-visible-sidebars (scopes)
  "Adopt any already-visible manager windows for SCOPES as sidebars."
  (dolist (scope scopes)
    (when-let* ((window (claude-code-ide-manager--visible-manager-window scope)))
      (when (claude-code-ide-manager--valid-sidebar-window-p window)
        (claude-code-ide-manager--adopt-visible-sidebar-window window)))))

(defun claude-code-ide-manager--restore-visible-sidebars (scopes)
  "Ensure each scope in SCOPES has a visible manager sidebar."
  (dolist (scope scopes)
    (unless (claude-code-ide-manager--sidebar-window scope)
      (claude-code-ide-manager--show-sidebar scope))))

(defun claude-code-ide-manager--session-managed-p (session-key)
  "Return non-nil when SESSION-KEY already has manager-owned layout state."
  (when-let* ((buffer (claude-code-ide-manager--session-buffer session-key)))
    (and (buffer-live-p buffer)
         (buffer-local-value 'claude-code-ide-manager--managed-session buffer))))

(defun claude-code-ide-manager--mark-session-managed (session-key)
  "Mark SESSION-KEY's live session buffer as manager-owned."
  (when-let* ((buffer (claude-code-ide-manager--session-buffer session-key)))
    (when (buffer-live-p buffer)
      (with-current-buffer buffer
        (setq-local claude-code-ide-manager--managed-session t)))))

(defun claude-code-ide-manager--evict-manager-buffer-from-window (window buffer)
  "Remove BUFFER from non-sidebar WINDOW."
  (condition-case nil
      (delete-window window)
    (error
     (switch-to-prev-buffer window 'bury)
     (when (eq (window-buffer window) buffer)
       (set-window-buffer
        window
        (or (get-buffer "*scratch*")
            (other-buffer buffer t)))))))

(defun claude-code-ide-manager--normalize-visible-manager-windows (&optional scope)
  "Ensure the manager buffer for SCOPE is only visible in the sidebar."
  (let ((buffer (claude-code-ide-manager--get-buffer scope)))
    (dolist (window (window-list nil 'no-minibuf))
      (when (and (window-live-p window)
                 (eq (window-buffer window) buffer)
                 (not (claude-code-ide-manager--valid-sidebar-window-p window)))
        (claude-code-ide-manager--evict-manager-buffer-from-window window buffer)))))

(defun claude-code-ide-manager--sync-collocated-side-metadata
    (treemacs-window manager-window)
  "Make TREEMACS-WINDOW and MANAGER-WINDOW share side-window metadata."
  (let ((side (window-parameter treemacs-window 'window-side))
        (slot (window-parameter treemacs-window 'window-slot)))
    (when (window-live-p manager-window)
      (set-window-parameter manager-window 'window-side side)
      (set-window-parameter manager-window 'window-slot slot))
    (when-let* ((parent (window-parent treemacs-window)))
      (set-window-parameter parent 'window-side side))))

(defun claude-code-ide-manager--clear-collocated-side-metadata
    (treemacs-window manager-window)
  "Clear side-window metadata for a collocated Treemacs branch."
  (when (window-live-p treemacs-window)
    (set-window-parameter treemacs-window 'window-side nil))
  (when (window-live-p manager-window)
    (set-window-parameter manager-window 'window-side nil))
  (when-let* ((parent (or (and (window-live-p treemacs-window)
                               (window-parent treemacs-window))
                          (and (window-live-p manager-window)
                               (window-parent manager-window)))))
    (set-window-parameter parent 'window-side nil)))

(defun claude-code-ide-manager--clear-sidebar-markers (window)
  "Clear cc-manager bookkeeping parameters from WINDOW."
  (when (window-live-p window)
    (set-window-parameter window 'claude-code-ide-manager-sidebar nil)
    (set-window-parameter window 'claude-code-ide-manager-collocated nil)
    (set-window-parameter window
                          'claude-code-ide-manager-collocated-treemacs-params
                          nil)))

(defun claude-code-ide-manager--collocated-window-attached-p (window treemacs-window)
  "Return non-nil when WINDOW is still collocated beneath TREEMACS-WINDOW."
  (and (window-live-p window)
       (window-live-p treemacs-window)
       (window-parameter window 'claude-code-ide-manager-collocated)
       (eq (window-parent window) (window-parent treemacs-window))
       (> (nth 1 (window-edges window))
          (nth 1 (window-edges treemacs-window)))))

(defun claude-code-ide-manager--show-collocated-sidebar (treemacs-window scope)
  "Show the manager buffer beneath TREEMACS-WINDOW for SCOPE."
  (let* ((buffer (claude-code-ide-manager--get-buffer scope))
         (existing-window (claude-code-ide-manager--sidebar-window scope))
         (height (claude-code-ide-manager--collocated-sidebar-height treemacs-window))
         (treemacs-params (claude-code-ide-manager--collocated-treemacs-params
                           treemacs-window))
         (treemacs-side (plist-get treemacs-params :window-side)))
    (claude-code-ide-manager--clear-sidebar-markers treemacs-window)
    (if (claude-code-ide-manager--collocated-window-attached-p
         existing-window treemacs-window)
        (progn
          (set-window-buffer existing-window buffer)
          (claude-code-ide-manager--sync-collocated-side-metadata
           treemacs-window existing-window)
          (set-window-parameter existing-window
                                'claude-code-ide-manager-collocated-treemacs-params
                                treemacs-params)
          existing-window)
      (dolist (window (window-list nil 'no-minibuf))
        (when (and (window-live-p window)
                   (not (eq window treemacs-window))
                   (eq (window-buffer window) buffer)
                   (window-parameter window 'claude-code-ide-manager-sidebar))
          (delete-window window)))
      ;; Emacs will not split a side window directly, so temporarily clear the
      ;; side metadata, split below, and restore the Treemacs window as the top
      ;; pane of the sidebar stack.
      (set-window-parameter treemacs-window 'window-side nil)
      (unwind-protect
          (let ((manager-window (split-window treemacs-window height 'below)))
            (set-window-buffer manager-window buffer)
            (set-window-parameter manager-window
                                  'claude-code-ide-manager-sidebar t)
            (set-window-parameter manager-window
                                  'claude-code-ide-manager-collocated t)
            (set-window-parameter manager-window
                                  'claude-code-ide-manager-collocated-treemacs-params
                                  treemacs-params)
            (set-window-parameter treemacs-window 'window-side treemacs-side)
            (dolist (window (list treemacs-window manager-window))
              (set-window-parameter window 'no-delete-other-windows t)
              (set-window-parameter window 'no-other-window t))
            (set-window-parameter treemacs-window 'window-size-fixed 'both)
            (set-window-parameter manager-window 'window-size-fixed nil)
            (claude-code-ide-manager--sync-collocated-side-metadata
             treemacs-window manager-window)
            manager-window)
        (unless (eq (window-parameter treemacs-window 'window-side) treemacs-side)
          (set-window-parameter treemacs-window 'window-side treemacs-side))))))

(defun claude-code-ide-manager--delete-stale-collocated-sidebar-windows (&optional scope)
  "Delete stale collocated manager windows for SCOPE."
  (let ((buffer (claude-code-ide-manager--get-buffer scope)))
    (dolist (window (window-list nil 'no-minibuf))
      (when (and (window-live-p window)
                 (eq (window-buffer window) buffer)
                 (window-parameter window 'claude-code-ide-manager-collocated))
        (delete-window window)))))

(defun claude-code-ide-manager--hide-collocated-sidebar (window)
  "Hide collocated sidebar WINDOW while preserving Treemacs."
  (let* ((treemacs-window (claude-code-ide-manager--treemacs-window))
         (treemacs-params (or (window-parameter
                               window
                               'claude-code-ide-manager-collocated-treemacs-params)
                              (and (window-live-p treemacs-window)
                                   (claude-code-ide-manager--collocated-treemacs-params
                                    treemacs-window)))))
    (if (window-live-p treemacs-window)
        (let ((treemacs-side (plist-get treemacs-params :window-side)))
          (claude-code-ide-manager--clear-collocated-side-metadata
           treemacs-window window)
          (unwind-protect
              (when (window-live-p window)
                (delete-window window))
            (claude-code-ide-manager--restore-collocated-treemacs-params
             treemacs-window treemacs-params)
            (when (window-live-p treemacs-window)
              (set-window-parameter treemacs-window 'window-side treemacs-side))))
      (when (window-live-p window)
        (delete-window window)))))

(defun claude-code-ide-manager--neighbor-in-bucket (scope session-key direction)
  "Return neighboring item for SCOPE SESSION-KEY in DIRECTION.
DIRECTION should be -1 for up or 1 for down."
  (let* ((sorted (claude-code-ide-manager--sorted-items
                  (claude-code-ide-manager--scope-items scope) nil scope))
         (index (cl-position session-key sorted
                             :key #'claude-code-ide-manager-item-session-key
                             :test #'equal)))
    (when index
      (let* ((current (nth index sorted))
             (target-index (+ index direction))
             (candidate (and (>= target-index 0) (nth target-index sorted))))
        (when (and candidate
                   (eq (claude-code-ide-manager-item-pinned current)
                       (claude-code-ide-manager-item-pinned candidate))
                   (or (not (eq (claude-code-ide-manager--view scope) 'grouped))
                       (equal (claude-code-ide-manager--group-key current)
                              (claude-code-ide-manager--group-key candidate))))
          candidate)))))

(defun claude-code-ide-manager--displayed-groups (scope)
  "Return SCOPE's displayed (GROUP-KEY . FIRST-ITEM) pairs in grouped order."
  (let (groups previous)
    (dolist (item (claude-code-ide-manager--sorted-items
                   (claude-code-ide-manager--scope-items scope) nil scope 'grouped))
      (let ((key (claude-code-ide-manager--group-key item)))
        (unless (equal key previous)
          (push (cons key item) groups)
          (setq previous key))))
    (nreverse groups)))

(defun claude-code-ide-manager--origin-item (scope)
  "Return the item for point, or SCOPE's selected or active row."
  (cl-loop for key in (list (get-text-property (point) 'claude-code-ide-manager-session-key)
                            (claude-code-ide-manager--scope-selected-session-key scope)
                            (claude-code-ide-manager--scope-active-session-key scope))
           for item = (and key (claude-code-ide-manager--item-by-session-key scope key))
           when item return item))

(defun claude-code-ide-manager--merge-group-order (baseline ordered groups)
  "Fill each group's BASELINE positions from ORDERED using Session GROUPS.
BASELINE and ORDERED contain Session IDs. GROUPS maps each ID to its group."
  (let ((queues (make-hash-table :test 'equal)))
    (dolist (key ordered)
      (push key (gethash (gethash key groups) queues)))
    (maphash (lambda (group keys) (puthash group (nreverse keys) queues)) queues)
    (mapcar (lambda (key) (pop (gethash (gethash key groups) queues))) baseline)))

(defun claude-code-ide-manager--materialize-order-keys (scope)
  "Assign explicit order keys matching SCOPE's current visible order."
  (cl-loop for item in (claude-code-ide-manager--sorted-items
                        (claude-code-ide-manager--scope-items scope) nil scope)
           for order-key from 1
           do (setf (claude-code-ide-manager-item-order-key item) order-key)))

(defun claude-code-ide-manager--swap-order (scope left right)
  "Swap order keys for LEFT and RIGHT within SCOPE."
  (if (eq (claude-code-ide-manager--view scope) 'grouped)
      (let* ((items (claude-code-ide-manager--scope-items scope))
             (groups (make-hash-table :test 'equal))
             (by-key (make-hash-table :test 'equal))
             (baseline
              (mapcar #'claude-code-ide-manager-item-session-key
                      (claude-code-ide-manager--sorted-items items nil scope 'flat)))
             (ordered
              (mapcar (lambda (item)
                        (claude-code-ide-manager-item-session-key
                         (cond ((eq item left) right)
                               ((eq item right) left)
                               (t item))))
                      (claude-code-ide-manager--sorted-items items nil scope 'grouped))))
        (dolist (item items)
          (let ((key (claude-code-ide-manager-item-session-key item)))
            (puthash key (claude-code-ide-manager--group-key item) groups)
            (puthash key item by-key)))
        (cl-loop for key in (claude-code-ide-manager--merge-group-order baseline ordered groups)
                 for order from 1
                 do (setf (claude-code-ide-manager-item-order-key (gethash key by-key)) order)))
    (claude-code-ide-manager--materialize-order-keys scope)
    (let ((left-order (claude-code-ide-manager-item-order-key left))
          (right-order (claude-code-ide-manager-item-order-key right)))
      (setf (claude-code-ide-manager-item-order-key left) right-order)
      (setf (claude-code-ide-manager-item-order-key right) left-order)))
  (claude-code-ide-manager--save-state)
  (claude-code-ide-manager--render scope))

(defun claude-code-ide-manager-refresh (&optional scope)
  "Refresh live sessions and redraw the manager for SCOPE."
  (interactive)
  (let ((scope (or scope (claude-code-ide-manager--scope-for-command))))
    (claude-code-ide-manager-refresh-items scope)
    (claude-code-ide-manager--render scope)))

(defun claude-code-ide-manager-refresh-all ()
  "Refresh live records and redraw visible manager sidebars."
  (claude-code-ide-manager--load-state)
  (dolist (buffer (claude-code-ide-manager--manager-buffers))
    (let ((scope (claude-code-ide-manager--scope-from-buffer buffer)))
      (claude-code-ide-manager-refresh-items scope t)
      (claude-code-ide-manager--render scope))))

(defun claude-code-ide-manager-session-ended (session-key &optional forget)
  "Retain a disconnected remote SESSION-KEY, or remove an ended local row.
With FORGET, remove the remote row after verified Stop or explicit detach."
  (when (featurep 'claude-code-ide-remote-project)
    (claude-code-ide-remote-project-invalidate
     session-key nil
     (if forget 'detach 'session-ended)))
  (let ((retain (and (not forget)
                     (claude-code-ide-manager--session-host session-key))))
    (when-let* ((item (and retain
                           (claude-code-ide-manager--item-by-session-key session-key))))
      (setf (claude-code-ide-manager-item-live-p item) nil))
    (maphash
     (lambda (scope-key state)
       (unless retain
         (setq state
               (plist-put
                state :items
                (cl-remove session-key (plist-get state :items)
                           :key #'claude-code-ide-manager-item-session-key
                           :test #'equal)))
         (when (equal session-key (plist-get state :selected-session-key))
           (setq state (plist-put state :selected-session-key nil))))
       (when (equal session-key (plist-get state :active-session-key))
         (setq state (plist-put state :active-session-key nil)))
       (puthash scope-key state claude-code-ide-manager--scope-state)
       (when (equal scope-key "global")
         (setq claude-code-ide-manager--items (plist-get state :items))))
     claude-code-ide-manager--scope-state)
    (unless retain
      (setq claude-code-ide-manager--items
            (cl-remove session-key claude-code-ide-manager--items
                       :key #'claude-code-ide-manager-item-session-key :test #'equal))
      (remhash session-key claude-code-ide-manager--layouts))
    (when (equal session-key claude-code-ide-manager--current-session-key)
      (setq claude-code-ide-manager--current-session-key nil))
    (claude-code-ide-manager--save-state)
    (claude-code-ide-manager-refresh-all)))

(defun claude-code-ide-manager--show-sidebar (&optional scope)
  "Show the manager sidebar for SCOPE.
When Treemacs is visible, collocate the manager beneath it.
Otherwise, use the standalone left side window layout."
  (claude-code-ide-manager-refresh scope)
  (claude-code-ide-manager--normalize-visible-manager-windows scope)
  (if-let* ((treemacs-window (claude-code-ide-manager--treemacs-window)))
      (claude-code-ide-manager--show-collocated-sidebar treemacs-window scope)
    (progn
      (claude-code-ide-manager--delete-stale-collocated-sidebar-windows scope)
      (let ((window
             (display-buffer-in-side-window
              (claude-code-ide-manager--get-buffer scope)
              `((side . left)
                (slot . -1)
                (window-width . ,claude-code-ide-manager-window-width)
                (window-parameters . ((no-delete-other-windows . t)
                                      (no-other-window . t)
                                      (window-size-fixed . both)))))))
        (set-window-parameter window 'claude-code-ide-manager-sidebar t)
        (window-preserve-size window t t)
        window))))

(defun claude-code-ide-manager--hide-sidebar (&optional scope)
  "Hide the manager sidebar for SCOPE."
  (when-let* ((window (or (claude-code-ide-manager--sidebar-window scope)
                          (claude-code-ide-manager--stale-collocated-sidebar-window
                           scope))))
    (if (window-parameter window 'claude-code-ide-manager-collocated)
        (claude-code-ide-manager--hide-collocated-sidebar window)
      (delete-window window))))

(defun claude-code-ide-manager-toggle-sidebar-for-scope (scope &optional arg)
  "Toggle the manager sidebar for SCOPE.

With a positive ARG, open and focus the sidebar.
With a negative ARG, hide the sidebar."
  (let ((direction (and arg (prefix-numeric-value arg))))
    (if (or (and (null direction)
                 (or (claude-code-ide-manager--sidebar-window scope)
                     (claude-code-ide-manager--stale-collocated-sidebar-window
                      scope)))
            (and direction (< direction 0)))
        (progn
          (claude-code-ide-manager--hide-sidebar scope)
          nil)
      (let ((window (claude-code-ide-manager--show-sidebar scope)))
        (select-window window)
        window))))

(defun claude-code-ide-manager-toggle-sidebar (&optional arg)
  "Toggle the default manager sidebar.

With a positive ARG, open and focus the sidebar.
With a negative ARG, hide the sidebar."
  (interactive "P")
  (claude-code-ide-manager-toggle-sidebar-for-scope
   (claude-code-ide-manager--resolve-scope
    (claude-code-ide-manager--default-target))
   arg))

(defun claude-code-ide-manager-toggle-global-sidebar (&optional arg)
  "Toggle the global manager sidebar."
  (interactive "P")
  (claude-code-ide-manager-toggle-sidebar-for-scope '(:type global) arg))

(defun claude-code-ide-manager-toggle-repo-sidebar (&optional arg)
  "Toggle the repo-local manager sidebar for the current Git root."
  (interactive "P")
  (claude-code-ide-manager-toggle-sidebar-for-scope
   (claude-code-ide-manager--resolve-scope 'repo)
   arg))

(defun claude-code-ide-manager--move-point-to-session-key (session-key)
  "Move point to the row for SESSION-KEY in the manager buffer."
  (goto-char (point-min))
  (while (and (not (eobp))
              (not (equal (get-text-property (point) 'claude-code-ide-manager-session-key)
                          session-key)))
    (forward-line 1))
  (beginning-of-line))

(defun claude-code-ide-manager--sync-point-to-session-key (scope session-key)
  "Move manager buffer point for SCOPE to SESSION-KEY when the buffer exists."
  (claude-code-ide-manager--set-scope-selected-session-key scope session-key)
  (when-let* ((buffer (get-buffer
                       (claude-code-ide-manager--buffer-name-for-scope scope))))
    (with-current-buffer buffer
      (claude-code-ide-manager--move-point-to-session-key session-key)
      (let ((position (point)))
        (when-let* ((window (claude-code-ide-manager--sidebar-window scope)))
          (set-window-point window position))))))

(defun claude-code-ide-manager--window-collocated-with-treemacs-p
    (window treemacs-window)
  "Return non-nil when WINDOW is the pane beneath TREEMACS-WINDOW."
  (and (window-live-p window)
       (window-live-p treemacs-window)
       (eq (window-parent window) (window-parent treemacs-window))
       (> (nth 1 (window-edges window))
          (nth 1 (window-edges treemacs-window)))))

(defun claude-code-ide-manager--reassert-standalone-sidebar-state (window)
  "Restore standalone sidebar parameters on WINDOW."
  (set-window-parameter window 'claude-code-ide-manager-sidebar t)
  (set-window-parameter window 'claude-code-ide-manager-collocated nil)
  (set-window-parameter window
                        'claude-code-ide-manager-collocated-treemacs-params
                        nil)
  (set-window-parameter window 'window-side 'left)
  (set-window-parameter window 'window-slot -1)
  (set-window-parameter window 'no-delete-other-windows t)
  (set-window-parameter window 'no-other-window t)
  (set-window-parameter window 'window-size-fixed 'both)
  (window-preserve-size window t t))

(defun claude-code-ide-manager--reassert-visible-sidebar-state (&optional scope)
  "Restore sidebar parameters for any visible manager window in SCOPE."
  (dolist (buffer (claude-code-ide-manager--manager-buffers))
    (let ((buffer-scope (claude-code-ide-manager--scope-from-buffer buffer)))
      (when (or (null scope)
                (equal buffer-scope scope))
        (when-let* ((window (claude-code-ide-manager--visible-manager-window
                             buffer-scope)))
          (if-let* ((treemacs-window (claude-code-ide-manager--treemacs-window)))
              (if (claude-code-ide-manager--valid-collocated-sidebar-window-p
                   window)
                  (let ((treemacs-params
                         (claude-code-ide-manager--collocated-treemacs-params
                          treemacs-window)))
                    (set-window-parameter window 'claude-code-ide-manager-sidebar t)
                    (set-window-parameter window 'claude-code-ide-manager-collocated t)
                    (set-window-parameter
                     window
                     'claude-code-ide-manager-collocated-treemacs-params
                     treemacs-params)
                    (dolist (managed-window (list treemacs-window window))
                      (set-window-parameter managed-window 'no-delete-other-windows t)
                      (set-window-parameter managed-window 'no-other-window t))
                    (set-window-parameter treemacs-window 'window-size-fixed 'both)
                    (set-window-parameter window 'window-size-fixed nil)
                    (claude-code-ide-manager--sync-collocated-side-metadata
                     treemacs-window window))
                (claude-code-ide-manager--show-sidebar buffer-scope))
            (if (claude-code-ide-manager--valid-standalone-sidebar-window-p
                 window)
                (claude-code-ide-manager--reassert-standalone-sidebar-state
                 window)
              (claude-code-ide-manager--show-sidebar buffer-scope))))))))

(defun claude-code-ide-manager--refresh-sidebar-state (&optional scope reassert)
  "Rerender visible manager sidebars for SCOPE and sync their window point.

When REASSERT is non-nil, first normalize visible manager windows back into
owned sidebar windows."
  (when reassert
    (claude-code-ide-manager--reassert-visible-sidebar-state scope))
  (dolist (buffer (claude-code-ide-manager--manager-buffers))
    (let ((buffer-scope (claude-code-ide-manager--scope-from-buffer buffer)))
      (when (or (null scope)
                (equal buffer-scope scope))
        (with-current-buffer buffer
          (claude-code-ide-manager--render buffer-scope)
          (let ((position (point)))
            (when-let* ((window (claude-code-ide-manager--sidebar-window
                                 buffer-scope)))
              (set-window-point window position))))))))

(defun claude-code-ide-manager--cycle-session-key (scope step)
  "Return the visible session key in SCOPE STEP positions away from point."
  (let* ((keys (claude-code-ide-manager--visible-session-keys scope))
         (count (length keys))
         (current (or (get-text-property (point) 'claude-code-ide-manager-session-key)
                      claude-code-ide-manager--current-session-key))
         (index (cl-position current keys :test #'equal)))
    (when (> count 0)
      (cond
       (index (nth (mod (+ index step) count) keys))
       ((> step 0) (car keys))
       (t (car (last keys)))))))

(defun claude-code-ide-manager--normalize-target-directory (directory)
  "Return DIRECTORY as a normalized session key."
  (file-name-as-directory (expand-file-name directory)))

(defun claude-code-ide-manager--project-el-known-project-roots ()
  "Return known `project.el' roots."
  (cond
   ((fboundp 'project-known-project-roots)
    (project-known-project-roots))
   ((boundp 'project-known-project-roots)
    project-known-project-roots)
   (t nil)))

(defun claude-code-ide-manager--projectile-known-project-roots ()
  "Return known Projectile roots."
  (cond
   ((fboundp 'projectile-known-projects)
    (projectile-known-projects))
   ((boundp 'projectile-known-projects)
    projectile-known-projects)
   (t nil)))

(defun claude-code-ide-manager--known-project-roots ()
  "Return known project roots for global manager open."
  (pcase claude-code-ide-manager-global-project-source
    ('projectile
     (claude-code-ide-manager--projectile-known-project-roots))
    ('project-el
     (claude-code-ide-manager--project-el-known-project-roots))
    ('merged
     (cl-delete-duplicates
      (append (claude-code-ide-manager--projectile-known-project-roots)
              (claude-code-ide-manager--project-el-known-project-roots))
      :test #'equal))
    ('auto
     (or (claude-code-ide-manager--projectile-known-project-roots)
         (claude-code-ide-manager--project-el-known-project-roots)))
    (_
     (error "Unknown manager global project source: %S"
            claude-code-ide-manager-global-project-source))))

(defun claude-code-ide-manager--project-completion-table (projects)
  "Return a completion table for PROJECTS with project metadata."
  (lambda (string pred action)
    (cond
     ((eq action 'metadata)
      '(metadata . ((category . project-file))))
     (t
      (complete-with-action action projects string pred)))))

(defun claude-code-ide-manager--select-global-project ()
  "Prompt for a known project and return its normalized root."
  (let ((projects (mapcar #'claude-code-ide-manager--normalize-target-directory
                          (claude-code-ide-manager--known-project-roots))))
    (unless projects
      (user-error "No known projects"))
    (claude-code-ide-manager--normalize-target-directory
     (completing-read "Open project: "
                      (claude-code-ide-manager--project-completion-table projects)
                      nil t))))

(defun claude-code-ide-manager--repo-worktree-directories (git-root)
  "Return normalized worktree directories for GIT-ROOT."
  (let ((default-directory git-root)
        directories)
    (dolist (line (ignore-errors
                    (process-lines "git" "-C" git-root "worktree" "list" "--porcelain")))
      (when (string-prefix-p "worktree " line)
        (push (claude-code-ide-manager--normalize-target-directory
               (string-remove-prefix "worktree " line))
              directories)))
    (nreverse directories)))

(defun claude-code-ide-manager--select-repo-worktree (scope)
  "Prompt for an existing worktree in SCOPE and return its normalized root."
  (let* ((git-root (plist-get scope :git-root))
         (worktrees (claude-code-ide-manager--repo-worktree-directories git-root)))
    (unless git-root
      (user-error "No repo scope for manager open"))
    (unless worktrees
      (user-error "No worktrees for %s" git-root))
    (claude-code-ide-manager--normalize-target-directory
     (completing-read "Open worktree: " worktrees nil t))))

(defun claude-code-ide-manager--open-target-for-scope (scope)
  "Prompt for an open target within SCOPE."
  (pcase (plist-get scope :type)
    ('global (claude-code-ide-manager--select-global-project))
    ('repo (claude-code-ide-manager--select-repo-worktree scope))
    (_ (error "Unknown manager scope: %S" scope))))

(defun claude-code-ide-manager--sidebar-buffer-p ()
  "Return non-nil when the current buffer is the manager buffer."
  (not (null (derived-mode-p 'claude-code-ide-manager-mode))))

(defun claude-code-ide-manager--navigate-project-group (step)
  "Select the first Session in the group STEP groups from the current row."
  (let ((scope (claude-code-ide-manager--scope-for-command)))
    (unless (and (claude-code-ide-manager--sidebar-buffer-p)
                 (eq (plist-get scope :type) 'global)
                 (eq (claude-code-ide-manager--view scope) 'grouped))
      (user-error "Grouped global view is required"))
    (let* ((groups (claude-code-ide-manager--displayed-groups scope))
           (origin (claude-code-ide-manager--origin-item scope)))
      (unless groups
        (user-error "No Sessions in this manager scope"))
      (when (cdr groups)
        (let* ((index (and origin
                           (cl-position (claude-code-ide-manager--group-key origin)
                                        groups :key #'car :test #'equal)))
               (target (cdr (nth (if index
                                     (mod (+ index step) (length groups))
                                   (if (> step 0) 0 (1- (length groups))))
                                 groups)))
               (key (claude-code-ide-manager-item-session-key target)))
          (if (and (claude-code-ide-manager-item-host target)
                   (not (buffer-live-p (claude-code-ide-manager--session-buffer key))))
              (progn
                (claude-code-ide-manager--sync-point-to-session-key scope key)
                (claude-code-ide-manager--save-state)
                (message "Session is disconnected. Press c to reattach."))
            (claude-code-ide-manager-switch-to-session key t scope)))))))

(defun claude-code-ide-manager-next-project-group ()
  "Select the first Session in the next displayed project group."
  (interactive)
  (claude-code-ide-manager--navigate-project-group 1))

(defun claude-code-ide-manager-previous-project-group ()
  "Select the first Session in the previous displayed project group."
  (interactive)
  (claude-code-ide-manager--navigate-project-group -1))

(defun claude-code-ide-manager-next-line ()
  "Move point to the next manager row and switch to it."
  (interactive)
  (let ((scope (claude-code-ide-manager--scope-for-command)))
    (when-let* ((session-key (claude-code-ide-manager--cycle-session-key scope 1)))
      (claude-code-ide-manager--sync-point-to-session-key scope session-key)
      (claude-code-ide-manager-switch-to-session
       session-key
       (claude-code-ide-manager--sidebar-buffer-p)))))

(defun claude-code-ide-manager--next-priority-session (visits &optional uncleared-only)
  "Focus the next priority session using the per-scope VISITS table.
When UNCLEARED-ONLY is non-nil, exclude cleared and unmarked sessions."
  (let ((scope (claude-code-ide-manager--scope-for-command)))
    (claude-code-ide-manager-refresh-items scope)
    (let* ((eligible
            (cl-remove-if-not
             (lambda (key)
               (buffer-live-p (claude-code-ide-manager--session-buffer key)))
             (claude-code-ide-manager--visible-session-keys scope)))
           (scope-key (claude-code-ide-manager--scope-key scope))
           (record (gethash scope-key visits))
           (visited (plist-get record :visited))
           (resume (plist-get record :resume))
           (current
            (cl-loop for key in
                     (list (claude-code-ide-manager--session-key-for-buffer
                            (window-buffer (selected-window)))
                           (claude-code-ide-manager--visible-layout-session-key)
                           (claude-code-ide-manager--scope-active-session-key scope)
                           claude-code-ide-manager--current-session-key)
                     when (member key eligible) return key))
           (others (remove current eligible))
           (unvisited (if visited
                          (cl-remove-if
                           (lambda (key) (eq (gethash key visited) t)) others)
                        others))
           new-pass target)
      (unless eligible
        (user-error "No live sessions in this manager scope"))
      (unless others
        (user-error "No other live session in this manager scope"))
      (cl-flet ((pick (keys)
                  (let ((best-rank (if uncleared-only 5 most-positive-fixnum))
                        best)
                    (dolist (key keys best)
                      (let ((rank (claude-code-ide-manager--session-priority key)))
                        (when (< rank best-rank)
                          (setq best key
                                best-rank rank)))))))
        (unless (and (member resume others) (pick (list resume)))
          (setq resume nil))
        (setq target (pick unvisited))
        (unless target
          (setq target resume))
        (unless target
          (setq new-pass t
                target (pick (cl-remove-if-not
                              (lambda (key) (and visited (gethash key visited)))
                              others)))))
      (unless target
        (user-error "No other uncleared session in this manager scope"))
      (cond
       ((or new-pass (equal target resume)) (setq resume nil))
       ((and visited (eq (gethash target visited) 'attention) (not resume))
        (setq resume current)))
      (let ((window (claude-code-ide-manager-switch-to-session target nil scope))
            (updated (make-hash-table :test 'equal)))
        ;; Saved layouts can restore editor focus.  This command visits the agent.
        (when-let* ((session-window
                     (get-buffer-window
                      (claude-code-ide-manager--session-buffer target))))
          (select-window session-window))
        (dolist (key eligible)
          (cond
           ((or (equal key target) (equal key current))
            (puthash key t updated))
           ((and (not new-pass) visited (gethash key visited))
            (puthash key (gethash key visited) updated))))
        (puthash scope-key (list :visited updated :resume resume) visits)
        window))))

(defun claude-code-ide-manager-next-priority-session ()
  "Focus the next unvisited session in state-priority order."
  (interactive)
  (claude-code-ide-manager--next-priority-session
   claude-code-ide-manager--priority-visits))

(defun claude-code-ide-manager-next-uncleared-session ()
  "Focus the next unvisited uncleared session in state-priority order.
Skip cleared and unmarked sessions, but include working sessions.
Keep a separate pass from
`claude-code-ide-manager-next-priority-session'."
  (interactive)
  (claude-code-ide-manager--next-priority-session
   claude-code-ide-manager--uncleared-visits t))

(defun claude-code-ide-manager-previous-line ()
  "Move point to the previous manager row and switch to it."
  (interactive)
  (let ((scope (claude-code-ide-manager--scope-for-command)))
    (when-let* ((session-key (claude-code-ide-manager--cycle-session-key scope -1)))
      (claude-code-ide-manager--sync-point-to-session-key scope session-key)
      (claude-code-ide-manager-switch-to-session
       session-key
       (claude-code-ide-manager--sidebar-buffer-p)))))

(defun claude-code-ide-manager-focus ()
  "Focus the default manager sidebar."
  (interactive)
  (claude-code-ide-manager-toggle-sidebar 1))

(defun claude-code-ide-manager-focus-global ()
  "Focus the global manager sidebar."
  (interactive)
  (claude-code-ide-manager-toggle-global-sidebar 1))

(defun claude-code-ide-manager-focus-repo ()
  "Focus the repo-local manager sidebar."
  (interactive)
  (claude-code-ide-manager-toggle-repo-sidebar 1))

(defun claude-code-ide-manager-open ()
  "Open a project or worktree relevant to the current manager scope."
  (interactive)
  (when-let* ((item (claude-code-ide-manager--item-at-point))
              (host (claude-code-ide-manager--session-host
                     (claude-code-ide-manager-item-session-key item))))
    (user-error "Remote project access on %s is not available in attach mode" host))
  (let* ((scope (claude-code-ide-manager--scope-for-command))
         (target (claude-code-ide-manager--open-target-for-scope scope))
         (session (claude-code-ide--preferred-session target)))
    (if session
        (claude-code-ide-manager-switch-to-session
         (claude-code-ide-session-id session) nil scope)
      (setq claude-code-ide-manager--open-target target)
      (setq claude-code-ide-manager--open-scope scope)
      (claude-code-ide-manager-open-menu))))

(defun claude-code-ide-manager-rename-session (session-key name)
  "Rename SESSION-KEY to NAME, or clear its name when NAME is empty."
  (let* ((name (unless (string-empty-p name) name))
         (items (claude-code-ide-manager--all-items))
         (target (or (claude-code-ide-manager--item-by-session-key session-key)
                     (cl-find session-key items
                              :key #'claude-code-ide-manager-item-session-key
                              :test #'equal))))
    (unless target
      (user-error "No manager session %s" session-key))
    (when name
      (let ((directory (claude-code-ide--project-key
                        (claude-code-ide-manager-item-directory target)
                        (claude-code-ide-manager-item-host target))))
        (when (cl-find-if
               (lambda (item)
                 (and (not (equal session-key
                                  (claude-code-ide-manager-item-session-key item)))
                      (equal name
                             (claude-code-ide-manager-item-custom-name item))
                      (when-let* ((other-directory
                                   (claude-code-ide-manager-item-directory item)))
                        (equal directory
                               (claude-code-ide--project-key
                                other-directory (claude-code-ide-manager-item-host item))))))
               items)
          (user-error "Session name already used in %s" directory))))
    (when-let* ((session (claude-code-ide--get-session session-key)))
      (claude-code-ide--set-session-custom-name session name))
    (let ((session-items
           (cl-remove-if-not
            (lambda (item)
              (equal session-key
                     (claude-code-ide-manager-item-session-key item)))
            items)))
      (cl-pushnew target session-items :test #'eq)
      (dolist (item session-items)
        (let ((old-suffix (or (claude-code-ide-manager-item-custom-name item)
                              (claude-code-ide-manager-item-order item)))
              (new-suffix (or name
                              (claude-code-ide-manager-item-order item))))
          (setf (claude-code-ide-manager-item-custom-name item) name
                (claude-code-ide-manager-item-display-name item)
                (claude-code-ide-manager--replace-display-suffix
                 (claude-code-ide-manager-item-display-name item)
                 old-suffix new-suffix)))))
    (claude-code-ide-manager--save-state)
    (claude-code-ide-manager-refresh-all)))

(defun claude-code-ide-manager-rename-at-point ()
  "Prompt for a custom name for the manager item at point."
  (interactive)
  (if-let* ((item (claude-code-ide-manager--item-at-point)))
      (claude-code-ide-manager-rename-session
       (claude-code-ide-manager-item-session-key item)
       (read-string "Session name (empty to clear): "
                    (claude-code-ide-manager-item-custom-name item)))
    (user-error "No manager session at point")))

(defun claude-code-ide-manager--toggle-pin-for-session-key (scope session-key)
  "Toggle pin state for SESSION-KEY within SCOPE."
  (when-let* ((item (claude-code-ide-manager--item-by-session-key scope session-key)))
    (setf (claude-code-ide-manager-item-pinned item)
          (not (claude-code-ide-manager-item-pinned item)))
    (claude-code-ide-manager--set-scope-items
     scope
     (mapcar (lambda (current)
               (if (equal (claude-code-ide-manager-item-session-key current)
                          session-key)
                   item
                 current))
             (claude-code-ide-manager--scope-items scope)))
    (claude-code-ide-manager--save-state)
    (claude-code-ide-manager--render scope)))

(defun claude-code-ide-manager-toggle-pin ()
  "Toggle pin state for the item at point."
  (interactive)
  (let ((scope (claude-code-ide-manager--scope-for-command)))
    (when-let* ((item (claude-code-ide-manager--item-at-point))
                (session-key (claude-code-ide-manager-item-session-key item)))
      (claude-code-ide-manager--toggle-pin-for-session-key scope session-key))))

(defun claude-code-ide-manager-toggle-current-session-pin ()
  "Toggle pin state for the current active manager session."
  (interactive)
  (let* ((scope (claude-code-ide-manager--scope-for-command))
         (session-key (or (claude-code-ide-manager--scope-active-session-key scope)
                          claude-code-ide-manager--current-session-key)))
    (when session-key
      (claude-code-ide-manager--toggle-pin-for-session-key scope session-key))))

(defun claude-code-ide-manager--move-group (scope group-key direction)
  "Move GROUP-KEY by DIRECTION among SCOPE's displayed groups."
  (let* ((groups (mapcar #'car (claude-code-ide-manager--displayed-groups scope)))
         (index (cl-position group-key groups :test #'equal))
         (target (and index (+ index direction))))
    (when (and index (>= target 0) (< target (length groups)))
      (let ((ordered (copy-sequence groups)))
        (cl-rotatef (nth index ordered) (nth target ordered))
        (claude-code-ide-manager--store-group-order scope ordered)
        (claude-code-ide-manager--save-state)
        (claude-code-ide-manager--render scope)
        t))))

(defun claude-code-ide-manager--move-group-at-point (direction)
  "Move the project group of the current row by DIRECTION."
  (let ((scope (claude-code-ide-manager--scope-for-command)))
    (unless (and (eq (plist-get scope :type) 'global)
                 (eq (claude-code-ide-manager--view scope) 'grouped))
      (user-error "Grouped global view is required"))
    (when-let* ((item (claude-code-ide-manager--origin-item scope)))
      (claude-code-ide-manager--move-group
       scope (claude-code-ide-manager--group-key item) direction))))

(defun claude-code-ide-manager-move-group-up ()
  "Move the current row's project group up."
  (interactive)
  (claude-code-ide-manager--move-group-at-point -1))

(defun claude-code-ide-manager-move-group-down ()
  "Move the current row's project group down."
  (interactive)
  (claude-code-ide-manager--move-group-at-point 1))

(defun claude-code-ide-manager--lone-grouped-row-p (scope item)
  "Return non-nil when ITEM is the only displayed row of its group in SCOPE."
  (and (eq (plist-get scope :type) 'global)
       (eq (claude-code-ide-manager--view scope) 'grouped)
       (let ((key (claude-code-ide-manager--group-key item)))
         (= 1 (cl-count-if
               (lambda (other) (equal key (claude-code-ide-manager--group-key other)))
               (claude-code-ide-manager--scope-items scope))))))

(defun claude-code-ide-manager--move-row-at-point (direction)
  "Move the current row by DIRECTION, or its group when the row is its only member."
  (let* ((scope (claude-code-ide-manager--scope-for-command))
         (item (claude-code-ide-manager--item-at-point))
         (session-key (and item (claude-code-ide-manager-item-session-key item))))
    (when item
      (if (claude-code-ide-manager--lone-grouped-row-p scope item)
          (claude-code-ide-manager--move-group
           scope (claude-code-ide-manager--group-key item) direction)
        (when-let* ((neighbor (claude-code-ide-manager--neighbor-in-bucket
                               scope session-key direction)))
          (claude-code-ide-manager--swap-order scope item neighbor))))))

(defun claude-code-ide-manager-move-up ()
  "Move the current row up within its pinned bucket, or its lone group."
  (interactive)
  (claude-code-ide-manager--move-row-at-point -1))

(defun claude-code-ide-manager-move-down ()
  "Move the current row down within its pinned bucket, or its lone group."
  (interactive)
  (claude-code-ide-manager--move-row-at-point 1))

(defun claude-code-ide-manager--capture-layout (session-key)
  "Capture current frame layout for SESSION-KEY."
  (let ((layout
         (list
          :session-key session-key
          :window-state
          (window-state-get (frame-root-window) t)
          :selected-buffer-name
          (buffer-name (window-buffer (selected-window)))))
        (session-buffer
         (claude-code-ide-manager--session-buffer session-key)))
    (when (claude-code-ide-manager--session-host session-key)
      (setq
       layout
       (plist-put
        layout :terminal-buffer-name
        (and
         (buffer-live-p session-buffer)
         (buffer-name session-buffer))))
      (when (featurep 'claude-code-ide-remote-project)
        (when-let* ((view
                     (claude-code-ide-remote-project-surviving-view
                      session-key session-buffer))
                    ((get-buffer-window view (selected-frame))))
          (setq
           layout
           (plist-put layout :project-view-buffer view)
           layout
           (plist-put
            layout :project-view-name (buffer-name view))))))
    layout))

(defun claude-code-ide-manager-magit-status-buffer (directory)
  "Return the magit status buffer for DIRECTORY, or a Dired buffer without magit."
  (if (fboundp 'magit-status-setup-buffer)
      (magit-status-setup-buffer directory)
    (dired-noselect directory)))

(defun claude-code-ide-manager--open-status-buffer (directory)
  "Return the status buffer for DIRECTORY.
Call `claude-code-ide-manager-status-buffer-function' and fall back to
Dired when it fails or returns a non-buffer."
  (let ((buffer (condition-case nil
                    (funcall claude-code-ide-manager-status-buffer-function
                             directory)
                  (error nil))))
    (if (buffer-live-p buffer)
        buffer
      (dired-noselect directory))))

(defun claude-code-ide-manager--restore-layout (session-key)
  "Restore SESSION-KEY's layout with exact current owned buffers."
  (let* ((layout
          (gethash session-key claude-code-ide-manager--layouts))
         (window-state (plist-get layout :window-state))
         (remote
          (claude-code-ide-manager--session-host session-key))
         (session-buffer
          (claude-code-ide-manager--session-buffer session-key))
         (saved-view
          (plist-get layout :project-view-buffer))
         (current-view
          (and
           (featurep 'claude-code-ide-remote-project)
           (claude-code-ide-remote-project-surviving-view
            session-key session-buffer)))
         (enabled
          (and
           remote
           (claude-code-ide-manager--remote-project-enabled-p
            session-key))))
    (when
        (and
         window-state
         (or (not remote) (buffer-live-p session-buffer))
         (or
          (null saved-view)
          (and
           enabled
           (buffer-live-p saved-view)
           (eq saved-view current-view))))
      (when-let* ((remote)
                  (old-name
                   (plist-get layout :terminal-buffer-name)))
        (setq
         window-state
         (cl-subst
          (buffer-name session-buffer)
          old-name window-state :test #'equal)))
      (when-let* ((saved-view)
                  (old-name
                   (plist-get layout :project-view-name)))
        (setq
         window-state
         (cl-subst
          (buffer-name saved-view)
          old-name window-state :test #'equal)))
      (claude-code-ide-manager--advance-layout-epoch)
      (window-state-put
       window-state (frame-root-window) 'safe)
      (setq
       claude-code-ide-manager--current-session-key session-key)
      (let* ((selected-buffer-name
              (plist-get layout :selected-buffer-name))
             (selected-buffer-name
              (if
                  (and
                   saved-view
                   (equal
                    selected-buffer-name
                    (plist-get layout :project-view-name)))
                  (buffer-name saved-view)
                selected-buffer-name))
             (selected-buffer
              (and selected-buffer-name
                   (when-let* ((buffer
                                (get-buffer
                                 selected-buffer-name)))
                     (unless
                         (claude-code-ide-manager--manager-buffer-p
                          buffer)
                       buffer))))
             (target-window
              (if remote
                  (or
                   (get-buffer-window session-buffer)
                   (claude-code-ide--show-session-buffer
                    session-buffer))
                (or
                 (and
                  selected-buffer
                  (get-buffer-window selected-buffer))
                 (and
                  session-buffer
                  (get-buffer-window session-buffer))))))
        (when target-window
          (select-window target-window))
        (when enabled
          (claude-code-ide-manager--set-remote-project-frame-intent
           session-key session-buffer
           (and
            current-view
            (get-buffer-window current-view)
            current-view)
           (and current-view
                (get-buffer-window current-view))))
        target-window))))

(defun claude-code-ide-manager--session-active-file (session-key)
  "Return the selected active file for a local SESSION-KEY."
  (unless (claude-code-ide-manager--session-host session-key)
    (let* ((project-root
            (file-name-as-directory
             (expand-file-name
              (claude-code-ide-manager--session-directory session-key))))
           (buffer (window-buffer (selected-window)))
           (file (buffer-local-value 'buffer-file-name buffer)))
      (when (and (stringp file)
                 (ignore-errors
                   (file-in-directory-p (expand-file-name file) project-root)))
        (expand-file-name file)))))

(defun claude-code-ide-manager--sync-treemacs-to-session (session-key)
  "Sync visible Treemacs state to a local SESSION-KEY."
  (unless (claude-code-ide-manager--session-host session-key)
    (let ((project-root
           (file-name-as-directory
            (expand-file-name
             (claude-code-ide-manager--session-directory session-key))))
          (active-file (claude-code-ide-manager--session-active-file session-key)))
      (let ((default-directory project-root))
        (cond
         ((fboundp 'treemacs-add-and-display-current-project-exclusively)
          (ignore-errors
            (treemacs-add-and-display-current-project-exclusively)))
         ((fboundp 'treemacs-display-current-project-exclusively)
          (ignore-errors
            (treemacs-display-current-project-exclusively)))
         ((fboundp 'treemacs-add-and-display-current-project)
          (ignore-errors
            (treemacs-add-and-display-current-project)))))
      (when (and active-file
                 (fboundp 'treemacs-find-file))
        (condition-case nil
            (treemacs-find-file active-file)
          (wrong-number-of-arguments
           (ignore-errors
             (with-current-buffer (or (get-file-buffer active-file)
                                      (find-file-noselect active-file))
               (treemacs-find-file))))
          (error nil))))))

(defun claude-code-ide-manager--record-remote-project-display
    (session-key attachment frame view-buffer view-window)
  "Record a displayed VIEW-BUFFER and VIEW-WINDOW for SESSION-KEY."
  (claude-code-ide-manager--advance-layout-epoch frame)
  (claude-code-ide-manager--set-remote-project-frame-intent
   session-key attachment view-buffer view-window frame)
  (claude-code-ide-remote-project-record-display
   session-key attachment view-buffer))

(defun claude-code-ide-manager--display-remote-project-view
    (session-key attachment frame view-buffer)
  "Display VIEW-BUFFER beside SESSION-KEY's exact ATTACHMENT on FRAME.
Preserve keyboard focus.  Return non-nil only after display."
  (when (frame-live-p frame)
    (let ((intent
           (frame-parameter
            frame 'claude-code-ide-manager-remote-project-display)))
      (when
          (and
           (claude-code-ide-manager--remote-project-enabled-p
            session-key)
           (equal session-key (plist-get intent :session-key))
           (eq attachment (plist-get intent :attachment))
           (eq attachment
               (claude-code-ide-manager--session-buffer session-key))
           (buffer-live-p view-buffer))
        (let ((terminal-window
               (get-buffer-window attachment frame)))
          (cond
           ((when-let* ((view-window
                         (get-buffer-window view-buffer frame)))
              (claude-code-ide-manager--record-remote-project-display
               session-key attachment frame view-buffer view-window)
              t))
           ((and
             (window-live-p terminal-window)
             (not
              (window-parameter terminal-window 'window-side)))
            (let ((selected (selected-window)))
              (condition-case nil
                  (let ((view-window
                         (split-window
                          terminal-window nil
                          (if
                              (eq
                               claude-code-ide-manager-session-window-side
                               'right)
                              'left
                            'right))))
                    (set-window-buffer view-window view-buffer)
                    (claude-code-ide-manager--record-remote-project-display
                     session-key attachment frame view-buffer view-window)
                    (when (window-live-p selected)
                      (select-window selected))
                    t)
                (error
                 (when (window-live-p selected)
                   (select-window selected))
                 (message
                  "Project view is ready for %s but the terminal cannot split. Press R"
                  session-key)
                 nil))))
           (t
            (message
             "Project view is ready for %s but its terminal is not an ordinary window. Press R"
             session-key)
            nil)))))))

(defun claude-code-ide-manager--build-default-layout (session-key &optional scope)
  "Build the default layout for SESSION-KEY in SCOPE and return the session window."
  (let* ((scope (or scope '(:type global)))
         (directory (claude-code-ide-manager--session-directory session-key))
         (session-buffer (claude-code-ide-manager--session-buffer session-key)))
    (unless (buffer-live-p session-buffer)
      (claude-code-ide-manager-refresh)
      (user-error "No live session buffer for %s" session-key))
    (claude-code-ide-manager--advance-layout-epoch)
    (if (claude-code-ide-manager--session-host session-key)
        (if
            (claude-code-ide-manager--remote-project-enabled-p
             session-key)
            (progn
              (when-let* ((old-window
                           (get-buffer-window session-buffer))
                          ((window-parameter old-window 'window-side)))
                (delete-window old-window))
              (select-window
               (claude-code-ide-manager--content-window))
              (delete-other-windows)
              (let ((window (selected-window)))
                (set-window-buffer window session-buffer)
                (claude-code-ide-manager--set-remote-project-frame-intent
                 session-key session-buffer nil nil)
                (setq
                 claude-code-ide-manager--current-session-key
                 session-key)
                (claude-code-ide-manager--set-scope-active-session-key
                 scope session-key)
                (claude-code-ide-manager--save-state)
                (claude-code-ide-manager--show-sidebar scope)
                (select-window window)
                window))
          (let ((window
                 (claude-code-ide--show-session-buffer
                  session-buffer)))
            (setq
             claude-code-ide-manager--current-session-key
             session-key)
            (claude-code-ide-manager--set-scope-active-session-key
             scope session-key)
            (claude-code-ide-manager--save-state)
            (claude-code-ide-manager--show-sidebar scope)
            window))
      (let ((status-buffer (claude-code-ide-manager--open-status-buffer directory)))
        (select-window (claude-code-ide-manager--content-window))
        (delete-other-windows)
        (let ((status-window (selected-window))
              (session-window nil))
          (set-window-buffer status-window status-buffer)
          (setq session-window
                (split-window status-window nil
                              claude-code-ide-manager-session-window-side))
          (set-window-buffer session-window session-buffer)
          (setq claude-code-ide-manager--current-session-key session-key)
          (claude-code-ide-manager--set-scope-active-session-key scope session-key)
          (claude-code-ide-manager--save-state)
          (claude-code-ide-manager--show-sidebar scope)
          (select-window session-window)
          session-window)))))

(defun claude-code-ide-manager--ensure-live-target (session-key &optional _scope)
  "Return non-nil for a live SESSION-KEY, with guidance for disconnected targets."
  (if (or (member session-key (claude-code-ide-manager--live-session-keys))
          (buffer-live-p (claude-code-ide-manager--session-buffer session-key)))
      t
    (if-let* ((host (claude-code-ide-manager--session-host session-key)))
        (if (member host claude-code-ide-remote-hosts)
            (user-error "Remote target on %s is disconnected. Press c to reattach" host)
          (user-error "Host %s is disconnected. Restore it in `claude-code-ide-remote-hosts' before reattach" host))
      (claude-code-ide-manager-refresh)
      nil)))

(defun claude-code-ide-manager--reset-session-idle-state (session-key)
  "Clear idle state and acknowledge results for SESSION-KEY.
Explicit manager actions apply even when output-idle monitoring is disabled."
  (when-let* ((session-buffer (claude-code-ide-manager--session-buffer session-key)))
    (with-current-buffer session-buffer
      (claude-code-ide-session-idle-clear-state t)
      t)))

(defun claude-code-ide-manager-clear-all-idle-state ()
  "Clear idle state and acknowledge results for every live session.
Return the number of sessions cleared."
  (interactive)
  (let ((count 0))
    (dolist (session-key (claude-code-ide-manager--live-session-keys) count)
      (when (claude-code-ide-manager--reset-session-idle-state session-key)
        (cl-incf count)))))

(defun claude-code-ide-manager-switch-to-session (session-key &optional keep-manager-focus scope)
  "Switch the current frame to SESSION-KEY.

When KEEP-MANAGER-FOCUS is non-nil, reselect the manager window after the
session layout is updated."
  (interactive)
  (when (claude-code-ide-manager--session-host session-key)
    (setq scope '(:type global))
    (claude-code-ide-manager--set-scope-selected-session-key scope session-key)
    (claude-code-ide-manager--save-state))
  (unless (claude-code-ide-manager--ensure-live-target session-key scope)
    (user-error "No live session buffer for %s" session-key))
  (claude-code-ide--touch-session session-key)
  (let ((scope (or scope (claude-code-ide-manager--scope-for-command)))
        (visible-sidebar-scopes
         (claude-code-ide-manager--visible-sidebar-scopes))
        (first-managed-switch
         (not (claude-code-ide-manager--session-managed-p session-key)))
        (claude-code-ide-manager--command-scope
         (or scope (claude-code-ide-manager--scope-for-command))))
    (when claude-code-ide-manager--current-session-key
      (puthash claude-code-ide-manager--current-session-key
               (claude-code-ide-manager--capture-layout
                claude-code-ide-manager--current-session-key)
               claude-code-ide-manager--layouts)
      (claude-code-ide-manager--save-state))
    (let ((target-window
           (if first-managed-switch
               (claude-code-ide-manager--build-default-layout session-key scope)
             (or (claude-code-ide-manager--restore-layout session-key)
                 (claude-code-ide-manager--build-default-layout session-key scope)))))
      (let ((preferred-window (if (window-live-p target-window)
                                  target-window
                                (selected-window))))
        (claude-code-ide-manager--set-scope-active-session-key scope session-key)
        (claude-code-ide-manager--save-state)
        (claude-code-ide-manager--mark-session-managed session-key)
        (claude-code-ide-manager--reset-session-idle-state session-key)
        (claude-code-ide-manager--adopt-visible-sidebars visible-sidebar-scopes)
        (claude-code-ide-manager--restore-visible-sidebars visible-sidebar-scopes)
        (when (claude-code-ide-manager--treemacs-window)
          (claude-code-ide-manager--sync-treemacs-to-session session-key))
        (claude-code-ide-manager--refresh-sidebar-state scope nil)
        (if keep-manager-focus
            (when-let* ((window (claude-code-ide-manager--sidebar-window scope)))
              (select-window window)
              (claude-code-ide-manager--sync-point-to-session-key scope session-key))
          (when (window-live-p preferred-window)
            (select-window preferred-window))))
      (when-let* (((featurep 'claude-code-ide-remote-project))
                  ((claude-code-ide-manager--remote-project-enabled-p session-key))
                  (attachment (claude-code-ide-manager--session-buffer session-key))
                  (view (claude-code-ide-remote-project-surviving-view
                         session-key attachment))
                  ((claude-code-ide-remote-project-display-allowed-p
                    session-key attachment)))
        (claude-code-ide-manager--display-remote-project-view
         session-key attachment (selected-frame) view))
      (cond
       (first-managed-switch
        (claude-code-ide-manager--maybe-prepare-remote-project
         session-key
         (claude-code-ide-manager--session-buffer session-key)
         (selected-frame)
         'first-display))
       ((and
         (claude-code-ide-manager--remote-project-enabled-p
          session-key)
         (featurep 'claude-code-ide-remote-project)
         (claude-code-ide-remote-project-needs-replacement-p
          session-key
          (claude-code-ide-manager--session-buffer session-key)))
        (claude-code-ide-manager--maybe-prepare-remote-project
         session-key
         (claude-code-ide-manager--session-buffer session-key)
         (selected-frame)
         'replacement)))
      target-window)))

(defun claude-code-ide-manager-reset-layout (session-key &optional keep-manager-focus scope)
  "Reset SESSION-KEY to the default manager layout.

When KEEP-MANAGER-FOCUS is non-nil, reselect the manager window after the
default layout is rebuilt."
  (interactive)
  (when (claude-code-ide-manager--session-host session-key)
    (setq scope '(:type global)))
  (unless (claude-code-ide-manager--ensure-live-target session-key scope)
    (user-error "No live session buffer for %s" session-key))
  (claude-code-ide--touch-session session-key)
  (let* ((scope (or scope (claude-code-ide-manager--scope-for-command)))
         (visible-sidebar-scopes
          (claude-code-ide-manager--visible-sidebar-scopes))
         (claude-code-ide-manager--command-scope
          (or scope (claude-code-ide-manager--scope-for-command))))
    (when (and claude-code-ide-manager--current-session-key
               (not (equal claude-code-ide-manager--current-session-key session-key)))
      (puthash claude-code-ide-manager--current-session-key
               (claude-code-ide-manager--capture-layout
                claude-code-ide-manager--current-session-key)
               claude-code-ide-manager--layouts))
    (remhash session-key claude-code-ide-manager--layouts)
    (claude-code-ide-manager--save-state)
    (let ((target-window
           (claude-code-ide-manager--build-default-layout session-key scope)))
      (let ((preferred-window (if (window-live-p target-window)
                                  target-window
                                (selected-window))))
        (claude-code-ide-manager--set-scope-active-session-key scope session-key)
        (claude-code-ide-manager--save-state)
        (claude-code-ide-manager--mark-session-managed session-key)
        (claude-code-ide-manager--reset-session-idle-state session-key)
        (claude-code-ide-manager--adopt-visible-sidebars visible-sidebar-scopes)
        (claude-code-ide-manager--refresh-sidebar-state scope nil)
        (when (claude-code-ide-manager--treemacs-window)
          (claude-code-ide-manager--sync-treemacs-to-session session-key))
        (if keep-manager-focus
            (claude-code-ide-manager-focus)
          (when (window-live-p preferred-window)
            (select-window preferred-window))))
      (claude-code-ide-manager--maybe-prepare-remote-project
       session-key
       (claude-code-ide-manager--session-buffer session-key)
       (selected-frame)
       'reset)
      (when-let* ((host (claude-code-ide-manager--session-host session-key)))
        (claude-code-ide-manager--cancel-remote-metadata host)
        (claude-code-ide-manager-refresh-remote-metadata host))
      target-window)))

(defun claude-code-ide-manager-switch-at-point ()
  "Switch to the session on the current row."
  (interactive)
  (when-let* ((item (claude-code-ide-manager--item-at-point)))
    (claude-code-ide-manager-switch-to-session
     (claude-code-ide-manager-item-session-key item))))

(defun claude-code-ide-manager-avy-switch ()
  "Select a visible manager row with Avy and focus its session."
  (interactive)
  (unless (derived-mode-p 'claude-code-ide-manager-mode)
    (user-error "Select a CC Manager window first"))
  (let ((avy-action nil))
    (avy-with claude-code-ide-manager-avy-switch
              (let ((avy-all-windows nil)
                    (current-prefix-arg nil)
                    (avy-dispatch-alist nil))
                (avy-jump "."
                          :pred
                          (lambda ()
                            (get-text-property
                             (match-beginning 0)
                             'claude-code-ide-manager-session-name-start))
                          :action
                          (lambda (position)
                            (goto-char position)
                            (claude-code-ide-manager-switch-at-point)))))))

(defun claude-code-ide-manager-switch-at-mouse (event)
  "Switch to the session clicked by mouse EVENT."
  (interactive "e")
  (mouse-set-point event)
  (claude-code-ide-manager-switch-at-point))

(defun claude-code-ide-manager-switch-at-point-preserve-focus ()
  "Switch to the session on the current row and keep focus in the manager."
  (interactive)
  (when-let* ((item (claude-code-ide-manager--item-at-point)))
    (claude-code-ide-manager-switch-to-session
     (claude-code-ide-manager-item-session-key item)
     t)))

(defun claude-code-ide-manager-reattach-at-point ()
  "Explicitly reattach the selected remembered remote target."
  (interactive)
  (let ((item (or (claude-code-ide-manager--item-at-point)
                  (user-error "No manager session at point"))))
    (unless (claude-code-ide-manager-item-host item)
      (user-error "Use the attach commands for local zmx sessions"))
    (claude-code-ide--reattach-remote-session
     (claude-code-ide-manager-item-session-key item))))

(defun claude-code-ide-manager-stop-at-point ()
  "Request confirmed Stop for the exact selected Session ID."
  (interactive)
  (let ((item (or (claude-code-ide-manager--item-at-point)
                  (user-error "No manager session at point"))))
    (claude-code-ide-stop (claude-code-ide-manager-item-session-key item))))

(defun claude-code-ide-manager-cancel-project-view-at-point ()
  "Cancel the pending remote Project-view attempt at point."
  (interactive)
  (let* ((item
          (or
           (claude-code-ide-manager--item-at-point)
           (user-error "No manager session at point")))
         (session-key
          (claude-code-ide-manager-item-session-key item))
         (attachment
          (claude-code-ide-manager--session-buffer session-key)))
    (unless
        (and
         (featurep 'claude-code-ide-remote-project)
         (buffer-live-p attachment)
         (claude-code-ide-remote-project-cancel
          session-key attachment))
      (user-error
       "No pending Project view for %s" session-key))
    (message
     "Canceled the pending Project view for %s" session-key)))

(defun claude-code-ide-manager--remote-project-cleanup-siblings
    (session-key)
  "Return known local sharing evidence except for SESSION-KEY."
  (let (siblings seen)
    (dolist (item claude-code-ide-manager--items)
      (let ((other
             (claude-code-ide-manager-item-session-key item)))
        (when
            (and
             (not (equal other session-key))
             (not (member other seen))
             (claude-code-ide-manager-item-live-p item)
             (claude-code-ide-manager-item-host item))
          (push other seen)
          (push
           (list
            :session-id other
            :host
            (claude-code-ide-manager-item-host item)
            :worktree-path
            (plist-get
             (claude-code-ide-manager-item-group-metadata item)
             :worktree-path)
            :live-p t)
           siblings))))
    siblings))

(defun claude-code-ide-manager-detach-at-point ()
  "Detach the zmx-backed session at point and remove its manager row.
Remove disconnected remote rows without contacting the host.
Leave the remote zmx session and its agent process unchanged."
  (interactive)
  (let* ((item
          (or
           (claude-code-ide-manager--item-at-point)
           (user-error "No manager session at point")))
         (session-key
          (claude-code-ide-manager-item-session-key item))
         (session
          (claude-code-ide--get-session session-key))
         (host
          (or
           (and session
                (claude-code-ide-session-host session))
           (claude-code-ide-manager-item-host item)))
         (buffer
          (claude-code-ide-manager--session-buffer session-key))
         (zmx-name
          (if session
              (claude-code-ide-session-zmx-name session)
            (claude-code-ide-manager-item-zmx-name item)))
         (scope
          (claude-code-ide-manager--scope-for-command))
         (keys
          (claude-code-ide-manager--visible-session-keys scope))
         (index
          (cl-position session-key keys :test #'equal))
         (survivor
          (and
           index
           (or
            (nth (1+ index) keys)
            (nth (1- index) keys))))
         cleanup-snapshot)
    (unless (or session host)
      (user-error "Session no longer exists"))
    (when-let* ((pending
                 (and
                  host
                  (claude-code-ide--remote-target-pending-reason
                   session-key))))
      (user-error
       "Cannot detach %s on %s. %s is already in progress"
       zmx-name host pending))
    (unless zmx-name
      (user-error "Session is not zmx-backed"))
    (when
        (and
         host
         (featurep 'claude-code-ide-remote-project))
      (setq
       cleanup-snapshot
       (claude-code-ide-remote-project-cleanup-snapshot
        session-key buffer host
        (claude-code-ide-manager--remote-project-cleanup-siblings
         session-key))))
    (cond
     ((buffer-live-p buffer)
      (kill-buffer buffer))
     (host
      (when session
        (claude-code-ide--cleanup-on-exit session-key)))
     (t
      (user-error "Session buffer no longer exists")))
    (when (buffer-live-p buffer)
      (user-error "Detach did not close the Session buffer"))
    (when cleanup-snapshot
      (claude-code-ide-remote-project-cleanup
       cleanup-snapshot))
    (when host
      (claude-code-ide-manager-session-ended session-key t))
    (when
        (member
         survivor
         (claude-code-ide-manager--visible-session-keys scope))
      (claude-code-ide-manager--sync-point-to-session-key
       scope survivor))
    (if host
        (message
         "Detached zmx session %s on %s" zmx-name host)
      (message "Detached zmx session %s" zmx-name))))

(defun claude-code-ide-manager-start-session-at-point (&optional dangerous arg)
  "Start and switch to a session for the row or repo scope at point.
With prefix ARG, select the CLI for this launch.
When DANGEROUS is non-nil, force the selected launch CLI's permissions bypass."
  (interactive (list nil current-prefix-arg))
  (let* ((item (claude-code-ide-manager--item-at-point))
         (scope (claude-code-ide-manager--scope-for-command))
         (directory (or (and item
                             (claude-code-ide-manager-item-directory item))
                        (and (eq (plist-get scope :type) 'repo)
                             (plist-get scope :git-root))
                        (user-error "No manager session at point"))))
    (when (and item
               (claude-code-ide-manager--session-host
                (claude-code-ide-manager-item-session-key item)))
      (user-error "Remote session creation is not available in attach mode"))
    (let* ((directory (file-name-as-directory (expand-file-name directory)))
           (claude-code-ide--suppress-initial-display t)
           (claude-code-ide--session-cli-type
            (unless arg claude-code-ide--session-cli-type))
           (claude-code-ide-cli-path
            (claude-code-ide--transient-cli-path arg))
           (claude-code-ide-cli-extra-flags
            (claude-code-ide--transient-launch-flags dangerous)))
      (when-let* ((session (claude-code-ide--start-session
                            nil nil directory t)))
        (claude-code-ide-manager-switch-to-session
         (claude-code-ide-session-id session) nil scope)))))

(defun claude-code-ide-manager-start-session-at-point-skip-permissions (&optional arg)
  "Start a sibling with the selected launch CLI's permissions bypass."
  (interactive "P")
  (claude-code-ide-manager-start-session-at-point t arg))

(defun claude-code-ide-manager-reset-layout-at-point ()
  "Reset the selected session to the default manager layout."
  (interactive)
  (when-let* ((item (claude-code-ide-manager--item-at-point)))
    (claude-code-ide-manager-reset-layout
     (claude-code-ide-manager-item-session-key item))))

(defun claude-code-ide-manager-switch-by-slot-preserve-focus (slot)
  "Switch to visible SLOT and keep focus in the manager."
  (let* ((scope (claude-code-ide-manager--scope-for-command))
         (items (claude-code-ide-manager--scope-items scope)))
    (when-let* ((item (nth (1- slot)
                           (cl-subseq (claude-code-ide-manager--sorted-items items nil scope)
                                      0
                                      (min 10 (length items)))))
                (session-key (claude-code-ide-manager-item-session-key item)))
      (claude-code-ide-manager--sync-point-to-session-key scope session-key)
      (claude-code-ide-manager-switch-to-session session-key t scope))))

(defun claude-code-ide-manager-switch-by-slot (slot)
  "Switch to visible SLOT."
  (interactive "nSlot: ")
  (let* ((scope (claude-code-ide-manager--scope-for-command))
         (items (claude-code-ide-manager--scope-items scope)))
    (when-let* ((item (nth (1- slot)
                           (cl-subseq (claude-code-ide-manager--sorted-items items nil scope)
                                      0
                                      (min 10 (length items)))))
                (session-key (claude-code-ide-manager-item-session-key item)))
      (claude-code-ide-manager--sync-point-to-session-key scope session-key)
      (claude-code-ide-manager-switch-to-session session-key nil scope))))

;;; Remote grouping metadata

(cl-defstruct (claude-code-ide-manager--remote-metadata-operation
               (:constructor claude-code-ide-manager--remote-metadata-operation-create))
  "In-flight remote Git metadata operation state for one host."
  process pending known)

(defvar claude-code-ide-manager--remote-metadata-operations (make-hash-table :test 'equal)
  "Per-host `claude-code-ide-manager--remote-metadata-operation', keyed by host.")

(defun claude-code-ide-manager--remote-metadata-live-snapshot (session)
  "Capture a live-target metadata snapshot plist for SESSION.
HOST is carried by the enclosing operation, not this snapshot: every
snapshot queued together always shares that one host."
  (list :session-key (claude-code-ide-session-id session)
        :directory (claude-code-ide-session-directory session)
        :zmx-name (claude-code-ide-session-zmx-name session)
        :session session
        :process (claude-code-ide-session-process session)))

(defun claude-code-ide-manager--remote-metadata-item-snapshot (item)
  "Capture a metadata snapshot plist for manager ITEM, live or remembered."
  (if-let* ((session (claude-code-ide--get-session
                      (claude-code-ide-manager-item-session-key item))))
      (claude-code-ide-manager--remote-metadata-live-snapshot session)
    (list :session-key (claude-code-ide-manager-item-session-key item)
          :directory (claude-code-ide-manager-item-directory item)
          :zmx-name (claude-code-ide-manager-item-zmx-name item)
          :session nil :process nil)))

(defun claude-code-ide-manager--apply-remote-metadata-record (host record snapshot)
  "Apply RECORD to the live-or-remembered target in SNAPSHOT on HOST.
Return non-nil if the update was applied. Refuse a stale SNAPSHOT: one
whose session was removed, replaced, or whose process changed, or one
whose target moved to a different host, directory, or zmx name, or one
with a remote request currently in flight for its own session."
  (let* ((session-key (plist-get snapshot :session-key))
         (directory (plist-get snapshot :directory))
         (zmx-name (plist-get snapshot :zmx-name))
         (captured-session (plist-get snapshot :session))
         (captured-process (plist-get snapshot :process))
         (item (claude-code-ide-manager--item-by-session-key '(:type global) session-key))
         (current-session (claude-code-ide--get-session session-key))
         (valid (claude-code-ide-manager--valid-group-metadata record host directory)))
    (when (and valid item
               (equal (claude-code-ide-manager-item-host item) host)
               (equal (claude-code-ide-manager-item-directory item) directory)
               (equal (claude-code-ide-manager-item-zmx-name item) zmx-name)
               (not (claude-code-ide--remote-target-pending-reason session-key))
               (if captured-session
                   (and (eq current-session captured-session)
                        (eq (claude-code-ide-session-process current-session) captured-process)
                        (process-live-p captured-process)
                        (buffer-live-p (claude-code-ide-session-buffer current-session))
                        (equal (claude-code-ide-session-host current-session) host)
                        (equal (claude-code-ide-session-directory current-session) directory)
                        (equal (claude-code-ide-session-zmx-name current-session) zmx-name))
                 (not current-session)))
      (setf (claude-code-ide-manager-item-group-metadata item) valid)
      (when current-session
        (claude-code-ide--set-session-group-metadata current-session valid))
      t)))

(defun claude-code-ide-manager--remote-metadata-callback (host operation batch)
  "Return a callback for BATCH while HOST still owns OPERATION."
  (lambda (outcome)
    (when (and (eq operation (gethash host claude-code-ide-manager--remote-metadata-operations))
               (eq (claude-code-ide-manager--remote-metadata-operation-process operation)
                   (plist-get outcome :process)))
      (setf (claude-code-ide-manager--remote-metadata-operation-process operation) nil)
      (if (not (member host claude-code-ide-remote-hosts))
          (remhash host claude-code-ide-manager--remote-metadata-operations)
        (unwind-protect
            (let (applied)
              (if-let* ((failure (plist-get outcome :error)))
                  (claude-code-ide-log
                   "Remote metadata for %S on %s failed: %s"
                   (mapcar #'car batch) host failure)
                (cl-loop for (directory . snapshots) in batch
                         for record in (plist-get outcome :records)
                         do (if (eq (plist-get record :kind) 'error)
                                (claude-code-ide-log
                                 "Remote metadata for %s on %s failed: %s"
                                 directory host (plist-get record :diagnostic))
                              (dolist (snapshot snapshots)
                                (when (claude-code-ide-manager--apply-remote-metadata-record
                                       host record snapshot)
                                  (setq applied t))))))
              (when applied
                (claude-code-ide-manager--save-state)
                (when-let* ((buffer (get-buffer claude-code-ide-manager--buffer-name)))
                  (claude-code-ide-manager--render '(:type global))
                  (dolist (window (get-buffer-window-list buffer nil t))
                    (set-window-point window (with-current-buffer buffer (point)))))))
          (claude-code-ide-manager--dispatch-remote-metadata-batch host))))))

(defun claude-code-ide-manager--dispatch-remote-metadata-batch (host)
  "Dispatch HOST's next bounded batch and return its owned process.
An SSH startup failure consumes that batch without blocking later targets."
  (let ((operation (gethash host claude-code-ide-manager--remote-metadata-operations)))
    (while (and operation
                (eq operation (gethash host claude-code-ide-manager--remote-metadata-operations))
                (not (claude-code-ide-manager--remote-metadata-operation-process operation)))
      (if (or (not (member host claude-code-ide-remote-hosts))
              (not (claude-code-ide-manager--remote-metadata-operation-pending operation)))
          (progn
            (remhash host claude-code-ide-manager--remote-metadata-operations)
            (setq operation nil))
        (let* ((remaining
                (nreverse (claude-code-ide-manager--remote-metadata-operation-pending operation)))
               (batch (list (pop remaining))))
          (while (and remaining
                      (< (length batch) claude-code-ide-zmx--metadata-max-directories)
                      (<= (claude-code-ide-zmx--metadata-command-size
                           (mapcar #'car (cons (car remaining) batch)))
                          claude-code-ide-zmx--metadata-max-command-bytes))
            (push (pop remaining) batch))
          (setq batch (nreverse batch))
          (setf (claude-code-ide-manager--remote-metadata-operation-pending operation)
                (nreverse remaining))
          (condition-case err
              (setf (claude-code-ide-manager--remote-metadata-operation-process operation)
                    (claude-code-ide-zmx--query-remote-metadata
                     host (mapcar #'car batch)
                     (claude-code-ide-manager--remote-metadata-callback host operation batch)))
            (error
             (claude-code-ide-log "Remote metadata for %s could not start: %s"
                                  host (error-message-string err)))))))
    (and operation (claude-code-ide-manager--remote-metadata-operation-process operation))))

(defun claude-code-ide-manager--enqueue-remote-metadata-snapshots (host snapshots)
  "Queue new SNAPSHOTS for HOST and dispatch while no request is active.
Deduplicate exact directories while retaining distinct owners.
A new owner can reuse a Session ID.
Skip invalid or oversized directories without blocking valid targets.
Never retry a target snapshot during the same operation."
  (let* ((operation
          (or (gethash host claude-code-ide-manager--remote-metadata-operations)
              (puthash host
                       (claude-code-ide-manager--remote-metadata-operation-create
                        :known (make-hash-table :test 'equal))
                       claude-code-ide-manager--remote-metadata-operations)))
         (known (claude-code-ide-manager--remote-metadata-operation-known operation)))
    (dolist (snapshot snapshots)
      (let* ((directory (plist-get snapshot :directory))
             (seen (gethash directory known))
             (entry (assoc directory
                           (claude-code-ide-manager--remote-metadata-operation-pending
                            operation))))
        (unless (cl-find-if
                 (lambda (old)
                   (and (eq (plist-get old :session) (plist-get snapshot :session))
                        (equal old snapshot)))
                 seen)
          (puthash directory (cons snapshot seen) known)
          (cond
           ((not (claude-code-ide-zmx--valid-directory-p directory))
            (claude-code-ide-log
             "Skipped invalid remote metadata directory %S on %s" directory host))
           (entry (setcdr entry (cons snapshot (cdr entry))))
           ((> (claude-code-ide-zmx--metadata-command-size (list directory))
               claude-code-ide-zmx--metadata-max-command-bytes)
            (claude-code-ide-log
             "Skipped oversized remote metadata target %s on %s" directory host))
           (t (push (cons directory (list snapshot))
                    (claude-code-ide-manager--remote-metadata-operation-pending
                     operation)))))))
    (unless (claude-code-ide-manager--remote-metadata-operation-process operation)
      (claude-code-ide-manager--dispatch-remote-metadata-batch host))))

(defun claude-code-ide-manager--enqueue-remote-metadata (session)
  "Queue a post-attach remote Git metadata request for SESSION."
  (when (claude-code-ide-session-host session)
    (claude-code-ide-zmx--validate-host (claude-code-ide-session-host session))
    (claude-code-ide-manager--enqueue-remote-metadata-snapshots
     (claude-code-ide-session-host session)
     (list (claude-code-ide-manager--remote-metadata-live-snapshot session)))))

(defun claude-code-ide-manager--cancel-remote-metadata (host)
  "Cancel HOST's in-flight remote metadata operation, if any.
Kill only the control process this operation itself owns. Clear
HOST's pending queue. Any callback already dispatched is stale by
construction once the operation record is gone."
  (when-let* ((operation (gethash host claude-code-ide-manager--remote-metadata-operations)))
    (remhash host claude-code-ide-manager--remote-metadata-operations)
    (let ((process (claude-code-ide-manager--remote-metadata-operation-process operation)))
      (when (process-live-p process)
        (delete-process process)))))

;;;###autoload
(defun claude-code-ide-manager-refresh-remote-metadata (&optional host)
  "Refresh remote Git metadata for every known target on HOST.
Prompt for one configured host when HOST is omitted. Snapshot HOST's
current live and remembered global targets once, then queue them:
later attaches or Stops are unaffected by this snapshot."
  (interactive)
  (let ((host (or host (claude-code-ide--read-remote-host))))
    (claude-code-ide-zmx--validate-host host)
    (when (gethash host claude-code-ide-manager--remote-metadata-operations)
      (user-error "A metadata refresh for %s is already in progress" host))
    (unless (claude-code-ide-manager--scope-state-entry '(:type global))
      (claude-code-ide-manager--load-state))
    (let ((snapshots
           (mapcar #'claude-code-ide-manager--remote-metadata-item-snapshot
                   (cl-remove-if-not
                    (lambda (item) (equal (claude-code-ide-manager-item-host item) host))
                    (claude-code-ide-manager--scope-items '(:type global))))))
      (if snapshots
          (claude-code-ide-manager--enqueue-remote-metadata-snapshots host snapshots)
        (message "No known remote targets for %s" host)
        nil))))


(provide 'claude-code-ide-manager)
;;; claude-code-ide-manager.el ends here
