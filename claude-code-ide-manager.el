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
(require 'project)
(require 'subr-x)
(require 'persist)
(require 'vc-git)

(declare-function claude-code-ide--get-session-buffer "claude-code-ide" (&optional directory))
(declare-function claude-code-ide--get-session "claude-code-ide" (session-id))
(declare-function claude-code-ide--start-session "claude-code-ide" (&optional continue resume directory force-new))
(declare-function claude-code-ide--set-session-custom-name "claude-code-ide" (session name))
(declare-function claude-code-ide--preferred-session "claude-code-ide" (directory))
(declare-function claude-code-ide--touch-session "claude-code-ide" (session-id))
(declare-function claude-code-ide-session-buffer "claude-code-ide" (session))
(declare-function claude-code-ide-session-custom-name "claude-code-ide" (session))
(declare-function claude-code-ide-session-directory "claude-code-ide" (session))
(declare-function claude-code-ide-session-id "claude-code-ide" (session))
(declare-function claude-code-ide-session-order "claude-code-ide" (session))
(declare-function claude-code-ide-session-process "claude-code-ide" (session))
(declare-function claude-code-ide-session-idle-clear-state "claude-code-ide-session-idle" ())
(declare-function claude-code-ide-session-idle-disable "claude-code-ide-session-idle" ())
(declare-function claude-code-ide-session-idle-reset-timer "claude-code-ide-session-idle" ())
(declare-function claude-code-ide-manager-open-menu "claude-code-ide-transient" ())
(declare-function claude-code-ide--transient-launch-flags "claude-code-ide-transient" (&optional bypass))

(defvar claude-code-ide-session-idle-hook nil)
(defvar claude-code-ide-session-working-hook nil)
(defvar claude-code-ide--suppress-initial-display nil)
(defvar claude-code-ide-cli-extra-flags "")

(defgroup claude-code-ide-manager nil
  "Session manager for Claude Code IDE."
  :group 'tools
  :prefix "claude-code-ide-manager-")

(defconst claude-code-ide-manager--state-version 2
  "Persisted cc-manager state schema version.")

(defvar claude-code-ide-manager--persisted-state
  `(:version ,claude-code-ide-manager--state-version
             :scopes nil
             :layouts nil)
  "Serialized manager state stored through `persist'.")

(defun claude-code-ide-manager--set-persist-state (symbol value)
  "Custom setter for persistence option SYMBOL with VALUE."
  (set-default symbol value)
  (if value
      (persist-symbol 'claude-code-ide-manager--persisted-state
                      claude-code-ide-manager--persisted-state)
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
  '((t :inherit highlight))
  "Face used to highlight the active session in the manager sidebar."
  :group 'claude-code-ide-manager)

(defface claude-code-ide-manager-idle-session-face
  '((t :background "red"))
  "Face used to highlight idle sessions in the manager sidebar."
  :group 'claude-code-ide-manager)

(defface claude-code-ide-manager-working-session-face
  '((t :background "#3f6b4f" :foreground "white"))
  "Face used to highlight working sessions in the manager sidebar."
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

(defconst claude-code-ide-manager--marker-gutter-width 2
  "Fixed display width for the left marker gutter.")

(cl-defstruct claude-code-ide-manager-item
  "Sidebar row state for a managed session."
  session-key
  directory
  custom-name
  order
  display-name
  secondary-text
  pinned
  order-key
  live-p)

(defvar claude-code-ide-manager--items nil
  "Current manager items.")

(defvar claude-code-ide-manager--scope-state (make-hash-table :test 'equal)
  "Per-scope manager view state keyed by scope key.")

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
   (when-let ((root (ignore-errors (vc-git-root default-directory))))
     (file-name-as-directory (expand-file-name root)))))

(defun claude-code-ide-manager--session-record (session-or-key)
  "Return the live session represented by SESSION-OR-KEY, or nil."
  (if (and (recordp session-or-key)
           (eq (type-of session-or-key) 'claude-code-ide-session))
      session-or-key
    (claude-code-ide--get-session session-or-key)))

(defun claude-code-ide-manager--session-directory (session-or-key)
  "Return the directory represented by SESSION-OR-KEY."
  (or (when-let ((session
                  (claude-code-ide-manager--session-record session-or-key)))
        (claude-code-ide-session-directory session))
      (when-let ((item (and (stringp session-or-key)
                            (claude-code-ide-manager--item-by-session-key
                             session-or-key))))
        (claude-code-ide-manager-item-directory item))
      session-or-key))

(defun claude-code-ide-manager--session-buffer (session-key)
  "Return SESSION-KEY's exact live buffer, or its legacy directory buffer."
  (if-let ((session (claude-code-ide--get-session session-key)))
      (or (and (buffer-live-p (claude-code-ide-session-buffer session))
               (claude-code-ide-session-buffer session))
          (let ((process (claude-code-ide-session-process session)))
            (cond
             ((bufferp process) (and (buffer-live-p process) process))
             ((processp process) (process-buffer process)))))
    (when (and (stringp session-key)
               (file-name-absolute-p session-key))
      (claude-code-ide--get-session-buffer session-key))))

(defun claude-code-ide-manager--session-git-root (session-or-key)
  "Return the Git root for SESSION-OR-KEY when available."
  (let ((default-directory
         (claude-code-ide-manager--session-directory session-or-key)))
    (claude-code-ide-manager--current-git-root)))

(defun claude-code-ide-manager--session-branch-name (session-or-key)
  "Return the current branch name for SESSION-OR-KEY when available."
  (car (ignore-errors
         (process-lines "git" "-C"
                        (claude-code-ide-manager--session-directory session-or-key)
                        "branch" "--show-current"))))

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
    ('repo (if-let ((git-root (claude-code-ide-manager--current-git-root)))
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

(defun claude-code-ide-manager--default-session-label (session)
  "Return SESSION's stable directory-local fallback label."
  (format "%s · %d"
          (file-name-nondirectory
           (directory-file-name (claude-code-ide-session-directory session)))
          (claude-code-ide-session-order session)))

(defun claude-code-ide-manager--scope-display-name (scope session-or-key)
  "Return the display name for SESSION-OR-KEY within SCOPE."
  (if-let ((session (claude-code-ide-manager--session-record session-or-key)))
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
    ;; Directory-key compatibility for callers that do not yet have a live record.
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
        (_ (error "Unknown manager scope: %S" scope))))))

(defun claude-code-ide-manager--disambiguate-display-names (items)
  "Return display names for ITEMS with duplicate labels disambiguated."
  (let ((groups (make-hash-table :test 'equal))
        (labels (make-hash-table :test 'equal)))
    (dolist (item items)
      (let ((display-name (claude-code-ide-manager-item-display-name item)))
        (push item (gethash display-name groups))
        (puthash item display-name labels)))
    (dolist (display-name (hash-table-keys groups))
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

(defvar-local claude-code-ide-manager--managed-session nil
  "Non-nil when the current session buffer has been shown through cc-manager.")

(defvar-local claude-code-ide-manager--scope nil
  "Scope descriptor associated with the current manager buffer.")

(defvar-local claude-code-ide-manager--last-point-path nil
  "Last full path shown in the echo area for the current manager buffer.")

(defun claude-code-ide-manager--manager-buffer-p (&optional buffer)
  "Return non-nil when BUFFER is a manager buffer."
  (when-let ((buffer (or buffer (current-buffer))))
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
         (when-let ((scope (claude-code-ide-manager--scope-from-buffer
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

(defvar claude-code-ide-manager-mode-map (make-sparse-keymap)
  "Keymap for `claude-code-ide-manager-mode'.")

(define-key claude-code-ide-manager-mode-map (kbd "g") #'claude-code-ide-manager-refresh)
(define-key claude-code-ide-manager-mode-map (kbd "RET") #'claude-code-ide-manager-switch-at-point)
(define-key claude-code-ide-manager-mode-map (kbd "SPC") #'claude-code-ide-manager-switch-at-point-preserve-focus)
(define-key claude-code-ide-manager-mode-map (kbd "n") #'claude-code-ide-manager-next-line)
(define-key claude-code-ide-manager-mode-map (kbd "p") #'claude-code-ide-manager-previous-line)
(define-key claude-code-ide-manager-mode-map (kbd "o") #'claude-code-ide-manager-open)
(define-key claude-code-ide-manager-mode-map (kbd "s") #'claude-code-ide-manager-start-session-at-point)
(define-key claude-code-ide-manager-mode-map (kbd "S") #'claude-code-ide-manager-start-session-at-point-skip-permissions)
(define-key claude-code-ide-manager-mode-map (kbd "P") #'claude-code-ide-manager-toggle-pin)
(define-key claude-code-ide-manager-mode-map (kbd "r") #'claude-code-ide-manager-rename-at-point)
(define-key claude-code-ide-manager-mode-map (kbd "R") #'claude-code-ide-manager-reset-layout-at-point)
(define-key claude-code-ide-manager-mode-map (kbd "M-p") #'claude-code-ide-manager-move-up)
(define-key claude-code-ide-manager-mode-map (kbd "M-n") #'claude-code-ide-manager-move-down)
(dotimes (index 10)
  (let ((slot (if (= index 9) 10 (1+ index))))
    (define-key
     claude-code-ide-manager-mode-map
     (kbd (number-to-string (mod (1+ index) 10)))
     (lambda ()
       (interactive)
       (claude-code-ide-manager-switch-by-slot-preserve-focus slot)))))

(defun claude-code-ide-manager--setup-evil-state ()
  "Start manager buffers in Evil emacs state when Evil is available."
  (when (fboundp 'evil-set-initial-state)
    (evil-set-initial-state 'claude-code-ide-manager-mode 'emacs)))

(with-eval-after-load 'evil
  (claude-code-ide-manager--setup-evil-state))

(claude-code-ide-manager--setup-evil-state)

(define-derived-mode claude-code-ide-manager-mode special-mode "CC-Manager"
  "Major mode for the cc-manager sidebar."
  (setq truncate-lines t)
  (setq-local global-hl-line-mode nil)
  (setq-local claude-code-ide-manager--last-point-path nil)
  (add-hook 'post-command-hook #'claude-code-ide-manager--show-point-path nil t)
  (when (featurep 'hl-line)
    (hl-line-mode -1)))

(defun claude-code-ide-manager--serialize-item (item)
  "Convert manager ITEM to a persistable plist."
  (list :session-key (claude-code-ide-manager-item-session-key item)
        :directory (claude-code-ide-manager-item-directory item)
        :custom-name (claude-code-ide-manager-item-custom-name item)
        :order (claude-code-ide-manager-item-order item)
        :display-name (claude-code-ide-manager-item-display-name item)
        :secondary-text (claude-code-ide-manager-item-secondary-text item)
        :pinned (claude-code-ide-manager-item-pinned item)
        :order-key (claude-code-ide-manager-item-order-key item)
        :live-p (claude-code-ide-manager-item-live-p item)))

(defun claude-code-ide-manager--deserialize-item (data)
  "Convert persisted DATA into a manager item."
  (make-claude-code-ide-manager-item
   :session-key (plist-get data :session-key)
   :directory (plist-get data :directory)
   :custom-name (plist-get data :custom-name)
   :order (plist-get data :order)
   :display-name (plist-get data :display-name)
   :secondary-text (plist-get data :secondary-text)
   :pinned (plist-get data :pinned)
   :order-key (plist-get data :order-key)
   :live-p (plist-get data :live-p)))

(defun claude-code-ide-manager--serialize-layouts ()
  "Return persisted layout data as an alist."
  (let (layouts)
    (maphash (lambda (session-key layout)
               (push (cons session-key layout) layouts))
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
                   (list :items (mapcar #'claude-code-ide-manager--serialize-item
                                        (plist-get state :items))
                         :selected-session-key
                         (plist-get state :selected-session-key)
                         :active-session-key
                         (plist-get state :active-session-key)))
             serialized))
     claude-code-ide-manager--scope-state)
    (nreverse serialized)))

(defun claude-code-ide-manager--deserialize-scope-state (scopes)
  "Return hash table for persisted SCOPES."
  (let ((table (make-hash-table :test 'equal)))
    (dolist (entry scopes)
      (puthash (car entry)
               (list :items (mapcar #'claude-code-ide-manager--deserialize-item
                                    (plist-get (cdr entry) :items))
                     :selected-session-key
                     (plist-get (cdr entry) :selected-session-key)
                     :active-session-key
                     (plist-get (cdr entry) :active-session-key))
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
        (if-let ((scopes (plist-get data :scopes)))
            (claude-code-ide-manager--deserialize-scope-state scopes)
          (let ((table (make-hash-table :test 'equal)))
            (puthash "global"
                     (list :items (mapcar #'claude-code-ide-manager--deserialize-item
                                          (plist-get data :items)))
                     table)
            table)))
  (setq claude-code-ide-manager--items
        (claude-code-ide-manager--scope-items '(:type global)))
  (setq claude-code-ide-manager--layouts
        (claude-code-ide-manager--deserialize-layouts
         (plist-get data :layouts))))

(defun claude-code-ide-manager--load-state ()
  "Load persisted manager state when enabled."
  (when claude-code-ide-manager-persist-state
    (persist-symbol 'claude-code-ide-manager--persisted-state
                    claude-code-ide-manager--persisted-state)
    (persist-load 'claude-code-ide-manager--persisted-state)
    (when (and (listp claude-code-ide-manager--persisted-state)
               (memq (or (plist-get claude-code-ide-manager--persisted-state :version) 0)
                     '(1 2)))
      (claude-code-ide-manager--restore-state
       claude-code-ide-manager--persisted-state))))

(defun claude-code-ide-manager--save-state ()
  "Persist current manager state when enabled."
  (when claude-code-ide-manager-persist-state
    (persist-symbol 'claude-code-ide-manager--persisted-state
                    claude-code-ide-manager--persisted-state)
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

(defun claude-code-ide-manager--replace-display-suffix
    (display-name old-suffix new-suffix)
  "Replace OLD-SUFFIX with NEW-SUFFIX in DISPLAY-NAME."
  (let ((pattern
         (concat "\\`\\(.*\\)"
                 (regexp-quote (format " · %s" old-suffix))
                 "\\(\\(?: \\[[^]]+\\]\\)*\\)\\'")))
    (if (string-match pattern display-name)
        (format "%s · %s%s"
                (match-string 1 display-name)
                new-suffix
                (or (match-string 2 display-name) ""))
      (format "%s · %s" display-name new-suffix))))

(defun claude-code-ide-manager--live-sessions ()
  "Return live Claude Code session records in stable fallback order."
  (let (sessions)
    (maphash
     (lambda (session-id _)
       (when-let ((session (claude-code-ide--get-session session-id)))
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
         (existing (claude-code-ide-manager--item-by-session-key scope session-key))
         (legacy
          (and (null existing)
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
         (display-name (claude-code-ide-manager--scope-display-name scope session)))
    (when (and persisted-name
               (null (claude-code-ide-session-custom-name session)))
      (claude-code-ide--set-session-custom-name session persisted-name))
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
       :custom-name custom-name
       :order order
       :display-name (if custom-name
                         (claude-code-ide-manager--replace-display-suffix
                          display-name order custom-name)
                       display-name)
       :secondary-text (abbreviate-file-name
                        directory)
       :pinned (and existing (claude-code-ide-manager-item-pinned existing))
       :order-key (or (and existing
                           (claude-code-ide-manager-item-order-key existing))
                      most-positive-fixnum)
       :live-p t))))

(defun claude-code-ide-manager--fallback-sort-key (item &optional scope)
  "Return the fallback sort key for ITEM within SCOPE."
  (if (eq (plist-get scope :type) 'repo)
      (or (claude-code-ide-manager-item-display-name item)
          (claude-code-ide-manager-item-session-key item))
    (format "%s\0%020d"
            (or (claude-code-ide-manager-item-directory item)
                (claude-code-ide-manager-item-session-key item))
            (or (claude-code-ide-manager-item-order item) 0))))

(defun claude-code-ide-manager--build-items (scope)
  "Build manager items for the live sessions visible within SCOPE."
  (mapcar (lambda (session)
            (claude-code-ide-manager--make-item scope session))
          (claude-code-ide-manager--scope-sessions
           scope (claude-code-ide-manager--live-sessions))))

(defun claude-code-ide-manager--sorted-items (items &optional scope)
  "Return ITEMS sorted for sidebar display within SCOPE."
  (sort (copy-sequence items)
        (lambda (left right)
          (let ((left-key (claude-code-ide-manager--fallback-sort-key left scope))
                (right-key (claude-code-ide-manager--fallback-sort-key right scope)))
            (cond
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
             ((string= left-key right-key)
              (string< (claude-code-ide-manager-item-session-key left)
                       (claude-code-ide-manager-item-session-key right)))
             (t
              (string< left-key right-key)))))))

(defun claude-code-ide-manager--slot-map (items &optional scope)
  "Return a hash table mapping visible ITEMS to quick slots within SCOPE."
  (let ((slots (make-hash-table :test 'equal))
        (slot 1))
    (dolist (item (claude-code-ide-manager--sorted-items items scope))
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
  (when-let ((buffer (claude-code-ide-manager--session-buffer session-key)))
    (and (claude-code-ide-manager--buffer-local-value
          'claude-code-ide-session-idle-enabled buffer)
         (claude-code-ide-manager--buffer-local-value
          'claude-code-ide-session-idle-p buffer))))

(defun claude-code-ide-manager--session-working-p (session-key)
  "Return non-nil when SESSION-KEY's live buffer has tracked activity."
  (when-let ((buffer (claude-code-ide-manager--session-buffer session-key)))
    (and (claude-code-ide-manager--buffer-local-value
          'claude-code-ide-session-idle-enabled buffer)
         (claude-code-ide-manager--buffer-local-value
          'claude-code-ide-session-working-p buffer))))

(defun claude-code-ide-manager--marker-gutter (item)
  "Return a fixed-width marker gutter for ITEM.
Idle markers take precedence over working and pinned markers."
  (let* ((marker (cond
                  ((claude-code-ide-manager--session-idle-p
                    (claude-code-ide-manager-item-session-key item))
                   claude-code-ide-manager--bell-glyph)
                  ((claude-code-ide-manager--session-working-p
                    (claude-code-ide-manager-item-session-key item))
                   claude-code-ide-manager--working-glyph)
                  ((claude-code-ide-manager-item-pinned item)
                   claude-code-ide-manager--pin-glyph)
                  (t "")))
         (padding (max 0 (- claude-code-ide-manager--marker-gutter-width
                            (string-width marker)))))
    (concat marker (make-string padding ?\s))))

(defun claude-code-ide-manager--row-face (scope session-key)
  "Return the face to apply to SESSION-KEY's row within SCOPE."
  (cond
   ((equal session-key
           (or (claude-code-ide-manager--scope-active-session-key scope)
               claude-code-ide-manager--current-session-key))
    'claude-code-ide-manager-current-session-face)
   ((claude-code-ide-manager--session-idle-p session-key)
    'claude-code-ide-manager-idle-session-face)
   ((claude-code-ide-manager--session-working-p session-key)
    'claude-code-ide-manager-working-session-face)))

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
        (when-let ((sidebar-window
                    (claude-code-ide-manager--sidebar-window selected-scope)))
          (select-window sidebar-window))))))

(defun claude-code-ide-manager--session-status-snapshot ()
  "Return the current buffer's manager-visible idle/working status."
  (list (bound-and-true-p claude-code-ide-session-idle-enabled)
        (bound-and-true-p claude-code-ide-session-idle-p)
        (bound-and-true-p claude-code-ide-session-working-p)))

(defun claude-code-ide-manager--refresh-after-session-status-change (orig-fn &rest args)
  "Refresh the sidebar when ORIG-FN changes manager-visible session status."
  (let ((before (claude-code-ide-manager--session-status-snapshot)))
    (prog1 (apply orig-fn args)
      (unless (equal before
                     (claude-code-ide-manager--session-status-snapshot))
        (claude-code-ide-manager--refresh-on-idle-transition)))))

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

(defun claude-code-ide-manager-refresh-items (&optional scope)
  "Refresh manager items for SCOPE from the live session registry."
  (let* ((scope (or scope (claude-code-ide-manager--scope-for-command)))
         (claude-code-ide-manager--legacy-adopted-p nil)
         (items nil))
    (claude-code-ide-manager--load-state)
    (setq items (claude-code-ide-manager--build-items scope))
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
  (when-let ((session-key (get-text-property (point) 'claude-code-ide-manager-session-key)))
    (claude-code-ide-manager--item-by-session-key
     (claude-code-ide-manager--scope-for-command)
     session-key)))

(defun claude-code-ide-manager--show-point-path ()
  "Show the current row's full path in the echo area.
This mirrors mouse hover text for keyboard navigation in the manager."
  (when (eq (current-buffer) (window-buffer (selected-window)))
    (when-let ((session-key (get-text-property (point)
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
           (claude-code-ide-manager--scope-items scope)
           scope)))

(defun claude-code-ide-manager--insert-item (scope item slot)
  "Insert ITEM into the current buffer using SLOT for SCOPE."
  (let ((start (point)))
    (insert (claude-code-ide-manager--marker-gutter item))
    (insert " ")
    (insert (if (numberp slot) (format "%d." slot) " -"))
    (insert " ")
    (insert (claude-code-ide-manager-item-display-name item))
    (insert "\n")
    (add-text-properties
     start (point)
     (append
      (list 'claude-code-ide-manager-session-key
            (claude-code-ide-manager-item-session-key item)
            'help-echo (claude-code-ide-manager--session-help-echo
                        (claude-code-ide-manager-item-session-key item)
                        (claude-code-ide-manager-item-secondary-text item)))
      (when-let ((face (claude-code-ide-manager--row-face
                        scope
                        (claude-code-ide-manager-item-session-key item))))
        (list 'face face))))))

(defun claude-code-ide-manager--render (&optional scope)
  "Render the manager sidebar for SCOPE."
  (let* ((scope (or scope (claude-code-ide-manager--scope-for-command)))
         (items (claude-code-ide-manager--scope-items scope))
         (visible-session-keys (claude-code-ide-manager--visible-session-keys scope))
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
             (slots (claude-code-ide-manager--slot-map items scope)))
        (erase-buffer)
        (dolist (item (claude-code-ide-manager--sorted-items items scope))
          (claude-code-ide-manager--insert-item
           scope
           item
           (gethash (claude-code-ide-manager-item-session-key item) slots)))
        (goto-char (point-min))
        (when-let ((target-session-key
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
     (when-let ((buffer (window-buffer window)))
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
  (when-let ((treemacs-window (claude-code-ide-manager--treemacs-window)))
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
      (when-let ((scope (claude-code-ide-manager--scope-from-buffer buffer)))
        (when (claude-code-ide-manager--sidebar-window scope)
          (push scope scopes))))
    (nreverse scopes)))

(defun claude-code-ide-manager--adopt-visible-sidebar-window (window)
  "Mark WINDOW as a manager-owned sidebar without changing its geometry."
  (set-window-parameter window 'claude-code-ide-manager-sidebar t)
  (if-let ((treemacs-window (claude-code-ide-manager--treemacs-window)))
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
    (when-let ((window (claude-code-ide-manager--visible-manager-window scope)))
      (when (claude-code-ide-manager--valid-sidebar-window-p window)
        (claude-code-ide-manager--adopt-visible-sidebar-window window)))))

(defun claude-code-ide-manager--restore-visible-sidebars (scopes)
  "Ensure each scope in SCOPES has a visible manager sidebar."
  (dolist (scope scopes)
    (unless (claude-code-ide-manager--sidebar-window scope)
      (claude-code-ide-manager--show-sidebar scope))))

(defun claude-code-ide-manager--session-managed-p (session-key)
  "Return non-nil when SESSION-KEY already has manager-owned layout state."
  (when-let ((buffer (claude-code-ide-manager--session-buffer session-key)))
    (and (buffer-live-p buffer)
         (buffer-local-value 'claude-code-ide-manager--managed-session buffer))))

(defun claude-code-ide-manager--mark-session-managed (session-key)
  "Mark SESSION-KEY's live session buffer as manager-owned."
  (when-let ((buffer (claude-code-ide-manager--session-buffer session-key)))
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
    (when-let ((parent (window-parent treemacs-window)))
      (set-window-parameter parent 'window-side side))))

(defun claude-code-ide-manager--clear-collocated-side-metadata
    (treemacs-window manager-window)
  "Clear side-window metadata for a collocated Treemacs branch."
  (when (window-live-p treemacs-window)
    (set-window-parameter treemacs-window 'window-side nil))
  (when (window-live-p manager-window)
    (set-window-parameter manager-window 'window-side nil))
  (when-let ((parent (or (and (window-live-p treemacs-window)
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
                  (claude-code-ide-manager--scope-items scope)
                  scope))
         (index (cl-position session-key sorted
                             :key #'claude-code-ide-manager-item-session-key
                             :test #'equal)))
    (when index
      (let* ((current (nth index sorted))
             (target-index (+ index direction))
             (candidate (nth target-index sorted)))
        (when (and candidate
                   (eq (claude-code-ide-manager-item-pinned current)
                       (claude-code-ide-manager-item-pinned candidate)))
          candidate)))))

(defun claude-code-ide-manager--swap-order (scope left right)
  "Swap order keys for LEFT and RIGHT within SCOPE."
  (let ((left-order (claude-code-ide-manager-item-order-key left))
        (right-order (claude-code-ide-manager-item-order-key right)))
    (setf (claude-code-ide-manager-item-order-key left) right-order)
    (setf (claude-code-ide-manager-item-order-key right) left-order)
    (claude-code-ide-manager--save-state)
    (claude-code-ide-manager--render scope)))

(defun claude-code-ide-manager-refresh (&optional scope)
  "Refresh live sessions and redraw the manager for SCOPE."
  (interactive)
  (let ((scope (or scope (claude-code-ide-manager--scope-for-command))))
    (claude-code-ide-manager-refresh-items scope)
    (claude-code-ide-manager--render scope)))

(defun claude-code-ide-manager-refresh-all ()
  "Redraw all visible manager sidebars."
  (dolist (buffer (claude-code-ide-manager--manager-buffers))
    (let ((scope (claude-code-ide-manager--scope-from-buffer buffer)))
      (claude-code-ide-manager-refresh-items scope)
      (claude-code-ide-manager--render scope))))

(defun claude-code-ide-manager-session-ended (session-key)
  "Remove SESSION-KEY from manager rows, layouts, and scope references."
  (maphash
   (lambda (scope-key state)
     (setq state
           (plist-put
            state :items
            (cl-remove session-key (plist-get state :items)
                       :key #'claude-code-ide-manager-item-session-key
                       :test #'equal)))
     (when (equal session-key (plist-get state :selected-session-key))
       (setq state (plist-put state :selected-session-key nil)))
     (when (equal session-key (plist-get state :active-session-key))
       (setq state (plist-put state :active-session-key nil)))
     (puthash scope-key state claude-code-ide-manager--scope-state)
     (when (equal scope-key "global")
       (setq claude-code-ide-manager--items (plist-get state :items))))
   claude-code-ide-manager--scope-state)
  (remhash session-key claude-code-ide-manager--layouts)
  (when (equal session-key claude-code-ide-manager--current-session-key)
    (setq claude-code-ide-manager--current-session-key nil))
  (claude-code-ide-manager--save-state)
  (claude-code-ide-manager-refresh-all))

(defun claude-code-ide-manager--show-sidebar (&optional scope)
  "Show the manager sidebar for SCOPE.
When Treemacs is visible, collocate the manager beneath it.
Otherwise, use the standalone left side window layout."
  (claude-code-ide-manager-refresh scope)
  (claude-code-ide-manager--normalize-visible-manager-windows scope)
  (if-let ((treemacs-window (claude-code-ide-manager--treemacs-window)))
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
  (when-let ((window (or (claude-code-ide-manager--sidebar-window scope)
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
  (when-let ((buffer (get-buffer
                      (claude-code-ide-manager--buffer-name-for-scope scope))))
    (with-current-buffer buffer
      (claude-code-ide-manager--move-point-to-session-key session-key)
      (let ((position (point)))
        (when-let ((window (claude-code-ide-manager--sidebar-window scope)))
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
        (when-let ((window (claude-code-ide-manager--visible-manager-window
                            buffer-scope)))
          (if-let ((treemacs-window (claude-code-ide-manager--treemacs-window)))
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
            (when-let ((window (claude-code-ide-manager--sidebar-window
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

(defun claude-code-ide-manager-next-line ()
  "Move point to the next manager row and switch to it."
  (interactive)
  (let ((scope (claude-code-ide-manager--scope-for-command)))
    (when-let ((session-key (claude-code-ide-manager--cycle-session-key scope 1)))
      (claude-code-ide-manager--sync-point-to-session-key scope session-key)
      (claude-code-ide-manager-switch-to-session
       session-key
       (claude-code-ide-manager--sidebar-buffer-p)))))

(defun claude-code-ide-manager-previous-line ()
  "Move point to the previous manager row and switch to it."
  (interactive)
  (let ((scope (claude-code-ide-manager--scope-for-command)))
    (when-let ((session-key (claude-code-ide-manager--cycle-session-key scope -1)))
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
      (let ((directory (file-name-as-directory
                        (expand-file-name
                         (claude-code-ide-manager-item-directory target)))))
        (when (cl-find-if
               (lambda (item)
                 (and (not (equal session-key
                                  (claude-code-ide-manager-item-session-key item)))
                      (equal name
                             (claude-code-ide-manager-item-custom-name item))
                      (when-let ((other-directory
                                  (claude-code-ide-manager-item-directory item)))
                        (equal directory
                               (file-name-as-directory
                                (expand-file-name other-directory))))))
               items)
          (user-error "Session name already used in %s" directory))))
    (when-let ((session (claude-code-ide--get-session session-key)))
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
  (if-let ((item (claude-code-ide-manager--item-at-point)))
      (claude-code-ide-manager-rename-session
       (claude-code-ide-manager-item-session-key item)
       (read-string "Session name (empty to clear): "
                    (claude-code-ide-manager-item-custom-name item)))
    (user-error "No manager session at point")))

(defun claude-code-ide-manager--toggle-pin-for-session-key (scope session-key)
  "Toggle pin state for SESSION-KEY within SCOPE."
  (when-let ((item (claude-code-ide-manager--item-by-session-key scope session-key)))
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

(defun claude-code-ide-manager-move-up ()
  "Move the current row up within its pinned bucket."
  (interactive)
  (let ((scope (claude-code-ide-manager--scope-for-command)))
    (when-let* ((item (claude-code-ide-manager--item-at-point))
                (neighbor (claude-code-ide-manager--neighbor-in-bucket
                           scope
                           (claude-code-ide-manager-item-session-key item) -1)))
      (claude-code-ide-manager--swap-order scope item neighbor))))

(defun claude-code-ide-manager-move-down ()
  "Move the current row down within its pinned bucket."
  (interactive)
  (let ((scope (claude-code-ide-manager--scope-for-command)))
    (when-let* ((item (claude-code-ide-manager--item-at-point))
                (neighbor (claude-code-ide-manager--neighbor-in-bucket
                           scope
                           (claude-code-ide-manager-item-session-key item) 1)))
      (claude-code-ide-manager--swap-order scope item neighbor))))

(defun claude-code-ide-manager--capture-layout (session-key)
  "Capture current frame layout for SESSION-KEY."
  (list :session-key session-key
        :window-state (window-state-get (frame-root-window) t)
        :selected-buffer-name (buffer-name (window-buffer (selected-window)))))

(defun claude-code-ide-manager--open-status-buffer (directory)
  "Return the status buffer for DIRECTORY."
  (condition-case nil
      (if (fboundp 'magit-status-setup-buffer)
          (magit-status-setup-buffer directory)
        (dired-noselect directory))
    (error
     (dired-noselect directory))))

(defun claude-code-ide-manager--restore-layout (session-key)
  "Restore saved layout for SESSION-KEY.
Return the selected window when successful."
  (when-let* ((layout (gethash session-key claude-code-ide-manager--layouts))
              (window-state (plist-get layout :window-state)))
    (window-state-put window-state (frame-root-window) 'safe)
    (setq claude-code-ide-manager--current-session-key session-key)
    (let* ((selected-buffer-name (plist-get layout :selected-buffer-name))
           (selected-buffer
            (and selected-buffer-name
                 (when-let ((buffer (get-buffer selected-buffer-name)))
                   (unless (claude-code-ide-manager--manager-buffer-p buffer)
                     buffer))))
           (session-buffer (claude-code-ide-manager--session-buffer session-key))
           (target-window (or (and selected-buffer
                                   (get-buffer-window selected-buffer))
                              (and session-buffer
                                   (get-buffer-window session-buffer)))))
      (when target-window
        (select-window target-window))
      target-window)))

(defun claude-code-ide-manager--session-active-file (session-key)
  "Return the active file for SESSION-KEY when the selected window visits one."
  (let* ((project-root
          (file-name-as-directory
           (expand-file-name
            (claude-code-ide-manager--session-directory session-key))))
         (buffer (window-buffer (selected-window)))
         (file (buffer-local-value 'buffer-file-name buffer)))
    (when (and (stringp file)
               (ignore-errors
                 (file-in-directory-p (expand-file-name file) project-root)))
      (expand-file-name file))))

(defun claude-code-ide-manager--sync-treemacs-to-session (session-key)
  "Sync visible Treemacs state to SESSION-KEY."
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
        (error nil)))))

(defun claude-code-ide-manager--build-default-layout (session-key &optional scope)
  "Build the default layout for SESSION-KEY in SCOPE and return the session window."
  (let* ((scope (or scope '(:type global)))
         (directory (claude-code-ide-manager--session-directory session-key))
         (session-buffer (claude-code-ide-manager--session-buffer session-key)))
    (unless (buffer-live-p session-buffer)
      (claude-code-ide-manager-refresh)
      (user-error "No live session buffer for %s" session-key))
    (let ((status-buffer (claude-code-ide-manager--open-status-buffer directory)))
      (select-window (claude-code-ide-manager--content-window))
      (delete-other-windows)
      (let ((status-window (selected-window))
            (session-window nil))
        (set-window-buffer status-window status-buffer)
        (setq session-window (split-window status-window nil 'right))
        (set-window-buffer session-window session-buffer)
        (setq claude-code-ide-manager--current-session-key session-key)
        (claude-code-ide-manager--set-scope-active-session-key scope session-key)
        (claude-code-ide-manager--save-state)
        (claude-code-ide-manager--show-sidebar scope)
        (select-window session-window)
        session-window))))

(defun claude-code-ide-manager--ensure-live-target (session-key &optional _scope)
  "Return non-nil when SESSION-KEY still has a live session."
  (if (or (member session-key (claude-code-ide-manager--live-session-keys))
          (buffer-live-p (claude-code-ide-manager--session-buffer session-key)))
      t
    (claude-code-ide-manager-refresh)
    nil))

(defun claude-code-ide-manager--reset-session-idle-state (session-key)
  "Clear idle monitoring state for SESSION-KEY after an explicit manager switch."
  (when-let ((session-buffer (claude-code-ide-manager--session-buffer session-key)))
    (with-current-buffer session-buffer
      (when (bound-and-true-p claude-code-ide-session-idle-enabled)
        (claude-code-ide-session-idle-clear-state)))))

(defun claude-code-ide-manager-switch-to-session (session-key &optional keep-manager-focus scope)
  "Switch the current frame to SESSION-KEY.

When KEEP-MANAGER-FOCUS is non-nil, reselect the manager window after the
session layout is updated."
  (interactive)
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
            (when-let ((window (claude-code-ide-manager--sidebar-window scope)))
              (select-window window)
              (claude-code-ide-manager--sync-point-to-session-key scope session-key))
          (when (window-live-p preferred-window)
            (select-window preferred-window))))
      target-window)))

(defun claude-code-ide-manager-reset-layout (session-key &optional keep-manager-focus scope)
  "Reset SESSION-KEY to the default manager layout.

When KEEP-MANAGER-FOCUS is non-nil, reselect the manager window after the
default layout is rebuilt."
  (interactive)
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
      target-window)))

(defun claude-code-ide-manager-switch-at-point ()
  "Switch to the session on the current row."
  (interactive)
  (when-let ((item (claude-code-ide-manager--item-at-point)))
    (claude-code-ide-manager-switch-to-session
     (claude-code-ide-manager-item-session-key item))))

(defun claude-code-ide-manager-switch-at-point-preserve-focus ()
  "Switch to the session on the current row and keep focus in the manager."
  (interactive)
  (when-let ((item (claude-code-ide-manager--item-at-point)))
    (claude-code-ide-manager-switch-to-session
     (claude-code-ide-manager-item-session-key item)
     t)))

(defun claude-code-ide-manager-start-session-at-point (&optional dangerous)
  "Start and switch to a sibling session for the row at point.
When DANGEROUS is non-nil, force the current CLI's permissions bypass."
  (interactive)
  (let ((item (claude-code-ide-manager--item-at-point)))
    (unless item
      (user-error "No manager session at point"))
    (let* ((scope (claude-code-ide-manager--scope-for-command))
           (directory (file-name-as-directory
                       (expand-file-name
                        (claude-code-ide-manager-item-directory item))))
           (claude-code-ide--suppress-initial-display t)
           (claude-code-ide-cli-extra-flags
            (claude-code-ide--transient-launch-flags dangerous)))
      (when-let ((session (claude-code-ide--start-session
                           nil nil directory t)))
        (claude-code-ide-manager-switch-to-session
         (claude-code-ide-session-id session) nil scope)))))

(defun claude-code-ide-manager-start-session-at-point-skip-permissions ()
  "Start a sibling at point with the current CLI's permissions bypass."
  (interactive)
  (claude-code-ide-manager-start-session-at-point t))

(defun claude-code-ide-manager-reset-layout-at-point ()
  "Reset the selected session to the default manager layout."
  (interactive)
  (when-let ((item (claude-code-ide-manager--item-at-point)))
    (claude-code-ide-manager-reset-layout
     (claude-code-ide-manager-item-session-key item))))

(defun claude-code-ide-manager-switch-by-slot-preserve-focus (slot)
  "Switch to visible SLOT and keep focus in the manager."
  (let* ((scope (claude-code-ide-manager--scope-for-command))
         (items (claude-code-ide-manager--scope-items scope)))
    (when-let* ((item (nth (1- slot)
                           (cl-subseq (claude-code-ide-manager--sorted-items items scope)
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
                           (cl-subseq (claude-code-ide-manager--sorted-items items scope)
                                      0
                                      (min 10 (length items)))))
                (session-key (claude-code-ide-manager-item-session-key item)))
      (claude-code-ide-manager--sync-point-to-session-key scope session-key)
      (claude-code-ide-manager-switch-to-session session-key nil scope))))

(claude-code-ide-manager--initialize)

(provide 'claude-code-ide-manager)
;;; claude-code-ide-manager.el ends here
