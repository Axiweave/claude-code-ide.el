;;; claude-code-ide-manager.el --- Session manager for Claude Code IDE  -*- lexical-binding: t; -*-

;; Copyright (C) 2025

;; Author: Yoav Orot
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
(require 'subr-x)
(require 'persist)

(declare-function claude-code-ide--get-session-buffer "claude-code-ide" (&optional directory))
(declare-function claude-code-ide-session-idle-disable "claude-code-ide-session-idle" ())
(declare-function claude-code-ide-session-idle-reset-timer "claude-code-ide-session-idle" ())

(defvar claude-code-ide-session-idle-hook)

(defgroup claude-code-ide-manager nil
  "Session manager for Claude Code IDE."
  :group 'tools
  :prefix "claude-code-ide-manager-")

(defconst claude-code-ide-manager--state-version 1
  "Persisted cc-manager state schema version.")

(defvar claude-code-ide-manager--persisted-state
  `(:version ,claude-code-ide-manager--state-version
             :items nil
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

(defface claude-code-ide-manager-current-session-face
  '((t :inherit highlight))
  "Face used to highlight the active session in the manager sidebar."
  :group 'claude-code-ide-manager)

(defface claude-code-ide-manager-idle-session-face
  '((t :background "red"))
  "Face used to highlight idle sessions in the manager sidebar."
  :group 'claude-code-ide-manager)

(defconst claude-code-ide-manager--bell-glyph "🔔"
  "Bell glyph used to mark idle sessions in the manager sidebar.")

(defconst claude-code-ide-manager--pin-glyph "📌"
  "Pin glyph used to mark pinned sessions in the manager sidebar.")

(defconst claude-code-ide-manager--marker-gutter-width 2
  "Fixed display width for the left marker gutter.")

(cl-defstruct claude-code-ide-manager-item
  "Sidebar row state for a managed session."
  session-key
  display-name
  secondary-text
  pinned
  order-key
  live-p)

(defvar claude-code-ide-manager--items nil
  "Current manager items.")

(defvar claude-code-ide-manager--layouts (make-hash-table :test 'equal)
  "Saved layouts keyed by session key.")

(defconst claude-code-ide-manager--buffer-name "*claude-code-manager*"
  "Manager sidebar buffer name.")

(defvar claude-code-ide--processes)

(defvar claude-code-ide-manager--current-session-key nil
  "Session key currently active in the manager frame.")

(defvar-local claude-code-ide-manager--last-point-path nil
  "Last full path shown in the echo area for the current manager buffer.")

(defun claude-code-ide-manager--apply-window-compatibility ()
  "Hide the manager sidebar from common window-selection packages."
  (when (boundp 'winum-ignored-buffers-regexp)
    (add-to-list 'winum-ignored-buffers-regexp
                 (regexp-quote claude-code-ide-manager--buffer-name)))
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
(define-key claude-code-ide-manager-mode-map (kbd "P") #'claude-code-ide-manager-toggle-pin)
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
        :display-name (claude-code-ide-manager-item-display-name item)
        :secondary-text (claude-code-ide-manager-item-secondary-text item)
        :pinned (claude-code-ide-manager-item-pinned item)
        :order-key (claude-code-ide-manager-item-order-key item)
        :live-p (claude-code-ide-manager-item-live-p item)))

(defun claude-code-ide-manager--deserialize-item (data)
  "Convert persisted DATA into a manager item."
  (make-claude-code-ide-manager-item
   :session-key (plist-get data :session-key)
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

(defun claude-code-ide-manager--deserialize-layouts (layouts)
  "Return hash table for persisted LAYOUTS."
  (let ((table (make-hash-table :test 'equal)))
    (dolist (entry layouts)
      (puthash (car entry) (cdr entry) table))
    table))

(defun claude-code-ide-manager--serialize-state ()
  "Return current manager state as a plist."
  (list :version claude-code-ide-manager--state-version
        :items (mapcar #'claude-code-ide-manager--serialize-item
                       claude-code-ide-manager--items)
        :layouts (claude-code-ide-manager--serialize-layouts)))

(defun claude-code-ide-manager--restore-state (data)
  "Restore manager state from persisted DATA."
  (setq claude-code-ide-manager--items
        (mapcar #'claude-code-ide-manager--deserialize-item
                (plist-get data :items)))
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
               (= (or (plist-get claude-code-ide-manager--persisted-state :version) 0)
                  claude-code-ide-manager--state-version))
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
  (setq claude-code-ide-manager--layouts (make-hash-table :test 'equal))
  (setq claude-code-ide-manager--current-session-key nil)
  (setq claude-code-ide-manager--persisted-state
        `(:version ,claude-code-ide-manager--state-version
                   :items nil
                   :layouts nil)))

(defun claude-code-ide-manager--item-by-session-key (session-key)
  "Return existing item matching SESSION-KEY."
  (cl-find-if (lambda (item)
                (equal (claude-code-ide-manager-item-session-key item)
                       session-key))
              claude-code-ide-manager--items))

(defun claude-code-ide-manager--live-session-keys ()
  "Return sorted keys for live Claude Code sessions."
  (let (keys)
    (maphash (lambda (session-key process)
               (when (process-live-p process)
                 (push session-key keys)))
             claude-code-ide--processes)
    (sort keys #'string<)))

(defun claude-code-ide-manager--make-item (session-key)
  "Build a manager item for SESSION-KEY."
  (let* ((existing (claude-code-ide-manager--item-by-session-key session-key))
         (display-name (file-name-nondirectory
                        (directory-file-name session-key))))
    (make-claude-code-ide-manager-item
     :session-key session-key
     :display-name display-name
     :secondary-text (abbreviate-file-name session-key)
     :pinned (and existing (claude-code-ide-manager-item-pinned existing))
     :order-key (or (and existing
                         (claude-code-ide-manager-item-order-key existing))
                    most-positive-fixnum)
     :live-p t)))

(defun claude-code-ide-manager--sorted-items (items)
  "Return ITEMS sorted for sidebar display."
  (sort (copy-sequence items)
        (lambda (left right)
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
           (t
            (string< (claude-code-ide-manager-item-session-key left)
                     (claude-code-ide-manager-item-session-key right)))))))

(defun claude-code-ide-manager--slot-map (items)
  "Return a hash table mapping visible ITEMS to quick slots."
  (let ((slots (make-hash-table :test 'equal))
        (slot 1))
    (dolist (item (claude-code-ide-manager--sorted-items items))
      (when (<= slot 10)
        (puthash (claude-code-ide-manager-item-session-key item) slot slots)
        (setq slot (1+ slot))))
    slots))

(defun claude-code-ide-manager--buffer-local-value (variable buffer)
  "Return VARIABLE's value in BUFFER when VARIABLE is bound there."
  (when (and (buffer-live-p buffer)
             (with-current-buffer buffer
               (boundp variable)))
    (buffer-local-value variable buffer)))

(defun claude-code-ide-manager--session-idle-p (session-key)
  "Return non-nil when SESSION-KEY's live buffer is idle-enabled and idle."
  (when-let ((buffer (claude-code-ide--get-session-buffer session-key)))
    (and (claude-code-ide-manager--buffer-local-value
          'claude-code-ide-session-idle-enabled buffer)
         (claude-code-ide-manager--buffer-local-value
          'claude-code-ide-session-idle-p buffer))))

(defun claude-code-ide-manager--marker-gutter (item)
  "Return a fixed-width marker gutter for ITEM.
Idle markers take precedence over pinned markers."
  (let* ((marker (cond
                  ((claude-code-ide-manager--session-idle-p
                    (claude-code-ide-manager-item-session-key item))
                   claude-code-ide-manager--bell-glyph)
                  ((claude-code-ide-manager-item-pinned item)
                   claude-code-ide-manager--pin-glyph)
                  (t "")))
         (padding (max 0 (- claude-code-ide-manager--marker-gutter-width
                            (string-width marker)))))
    (concat marker (make-string padding ?\s))))

(defun claude-code-ide-manager--row-face (session-key)
  "Return the face to apply to SESSION-KEY's row."
  (cond
   ((equal session-key claude-code-ide-manager--current-session-key)
    'claude-code-ide-manager-current-session-face)
   ((claude-code-ide-manager--session-idle-p session-key)
    'claude-code-ide-manager-idle-session-face)))

(defun claude-code-ide-manager--visible-window ()
  "Return the live manager window when the sidebar is visible."
  (when-let ((buffer (get-buffer claude-code-ide-manager--buffer-name))
             (window (get-buffer-window buffer)))
    window))

(defun claude-code-ide-manager--refresh-on-idle-transition (&rest _args)
  "Refresh the manager sidebar after an idle state transition."
  (when (claude-code-ide-manager--visible-window)
    (claude-code-ide-manager--refresh-sidebar-state)))

(defun claude-code-ide-manager--refresh-after-idle-clear (orig-fn &rest args)
  "Refresh the sidebar when ORIG-FN clears a previously idle session."
  (let ((was-idle (and (bound-and-true-p claude-code-ide-session-idle-enabled)
                       (bound-and-true-p claude-code-ide-session-idle-p))))
    (prog1 (apply orig-fn args)
      (when was-idle
        (claude-code-ide-manager--refresh-on-idle-transition)))))

(defun claude-code-ide-manager--install-idle-refresh-hooks ()
  "Refresh the manager sidebar when session idle state changes."
  (unless (memq #'claude-code-ide-manager--refresh-on-idle-transition
                claude-code-ide-session-idle-hook)
    (add-hook 'claude-code-ide-session-idle-hook
              #'claude-code-ide-manager--refresh-on-idle-transition))
  (when (advice-member-p #'claude-code-ide-manager--refresh-on-idle-transition
                         'claude-code-ide-session-idle-reset-timer)
    (advice-remove 'claude-code-ide-session-idle-reset-timer
                   #'claude-code-ide-manager--refresh-on-idle-transition))
  (when (advice-member-p #'claude-code-ide-manager--refresh-on-idle-transition
                         'claude-code-ide-session-idle-disable)
    (advice-remove 'claude-code-ide-session-idle-disable
                   #'claude-code-ide-manager--refresh-on-idle-transition))
  (unless (advice-member-p #'claude-code-ide-manager--refresh-after-idle-clear
                           'claude-code-ide-session-idle-reset-timer)
    (advice-add 'claude-code-ide-session-idle-reset-timer
                :around #'claude-code-ide-manager--refresh-after-idle-clear))
  (unless (advice-member-p #'claude-code-ide-manager--refresh-after-idle-clear
                           'claude-code-ide-session-idle-disable)
    (advice-add 'claude-code-ide-session-idle-disable
                :around #'claude-code-ide-manager--refresh-after-idle-clear)))

(with-eval-after-load 'claude-code-ide-session-idle
  (claude-code-ide-manager--install-idle-refresh-hooks))

(defun claude-code-ide-manager-refresh-items ()
  "Refresh manager items from the live session registry."
  (claude-code-ide-manager--load-state)
  (setq claude-code-ide-manager--items
        (mapcar #'claude-code-ide-manager--make-item
                (claude-code-ide-manager--live-session-keys))))

(defun claude-code-ide-manager--get-buffer ()
  "Return the manager buffer."
  (let ((buffer (get-buffer-create claude-code-ide-manager--buffer-name)))
    (with-current-buffer buffer
      (unless (derived-mode-p 'claude-code-ide-manager-mode)
        (claude-code-ide-manager-mode)))
    buffer))

(defun claude-code-ide-manager--item-at-point ()
  "Return manager item referenced by point."
  (when-let ((session-key (get-text-property (point) 'claude-code-ide-manager-session-key)))
    (claude-code-ide-manager--item-by-session-key session-key)))

(defun claude-code-ide-manager--show-point-path ()
  "Show the current row's full path in the echo area.
This mirrors mouse hover text for keyboard navigation in the manager."
  (when (eq (current-buffer) (window-buffer (selected-window)))
    (let ((path (get-text-property (point) 'help-echo)))
      (unless (equal path claude-code-ide-manager--last-point-path)
        (setq claude-code-ide-manager--last-point-path path)
        (if path
            (message "%s" path)
          (message ""))))))

(defun claude-code-ide-manager--visible-session-keys ()
  "Return visible session keys in sidebar order."
  (mapcar #'claude-code-ide-manager-item-session-key
          (claude-code-ide-manager--sorted-items claude-code-ide-manager--items)))

(defun claude-code-ide-manager--insert-item (item slot)
  "Insert ITEM into the current buffer using SLOT."
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
            'help-echo (claude-code-ide-manager-item-secondary-text item))
      (when-let ((face (claude-code-ide-manager--row-face
                        (claude-code-ide-manager-item-session-key item))))
        (list 'face face))))))

(defun claude-code-ide-manager--render ()
  "Render the manager sidebar."
  (with-current-buffer (claude-code-ide-manager--get-buffer)
    (let ((inhibit-read-only t)
          (slots (claude-code-ide-manager--slot-map claude-code-ide-manager--items)))
      (erase-buffer)
      (dolist (item (claude-code-ide-manager--sorted-items claude-code-ide-manager--items))
        (claude-code-ide-manager--insert-item
         item
         (gethash (claude-code-ide-manager-item-session-key item) slots)))
      (goto-char (point-min))
      (when (and claude-code-ide-manager--current-session-key
                 (member claude-code-ide-manager--current-session-key
                         (claude-code-ide-manager--visible-session-keys)))
        (claude-code-ide-manager--move-point-to-session-key
         claude-code-ide-manager--current-session-key)))))

(defun claude-code-ide-manager--content-window ()
  "Return a non-side content window for layout operations."
  (or (cl-find-if (lambda (window)
                    (not (window-parameter window 'window-side)))
                  (window-list nil 'no-minibuf))
      (selected-window)))

(defun claude-code-ide-manager--neighbor-in-bucket (session-key direction)
  "Return neighboring item for SESSION-KEY in DIRECTION.
DIRECTION should be -1 for up or 1 for down."
  (let* ((sorted (claude-code-ide-manager--sorted-items claude-code-ide-manager--items))
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

(defun claude-code-ide-manager--swap-order (left right)
  "Swap order keys for LEFT and RIGHT."
  (let ((left-order (claude-code-ide-manager-item-order-key left))
        (right-order (claude-code-ide-manager-item-order-key right)))
    (setf (claude-code-ide-manager-item-order-key left) right-order)
    (setf (claude-code-ide-manager-item-order-key right) left-order)
    (claude-code-ide-manager--save-state)
    (claude-code-ide-manager--render)))

(defun claude-code-ide-manager-refresh ()
  "Refresh live sessions and redraw the manager."
  (interactive)
  (claude-code-ide-manager-refresh-items)
  (claude-code-ide-manager--render))

(defun claude-code-ide-manager--show-sidebar ()
  "Show the manager sidebar in a dedicated left side window."
  (claude-code-ide-manager-refresh)
  (let ((window
         (display-buffer-in-side-window
          (claude-code-ide-manager--get-buffer)
          `((side . left)
            (slot . -1)
            (window-width . ,claude-code-ide-manager-window-width)
            (window-parameters . ((no-delete-other-windows . t)
                                  (no-other-window . t)
                                  (window-size-fixed . both)))))))
    (window-preserve-size window t t)
    window))

(defun claude-code-ide-manager--hide-sidebar ()
  "Hide the manager sidebar."
  (when-let ((window (get-buffer-window (claude-code-ide-manager--get-buffer))))
    (delete-window window)))

(defun claude-code-ide-manager-toggle-sidebar (&optional arg)
  "Toggle the manager sidebar.

With a positive ARG, open and focus the sidebar.
With a negative ARG, hide the sidebar."
  (interactive "P")
  (let ((direction (and arg (prefix-numeric-value arg))))
    (if (or (and (null direction)
                 (get-buffer-window (claude-code-ide-manager--get-buffer)))
            (and direction (< direction 0)))
        (progn
          (claude-code-ide-manager--hide-sidebar)
          nil)
      (let ((window (claude-code-ide-manager--show-sidebar)))
        (select-window window)
        window))))

(defun claude-code-ide-manager--move-point-to-session-key (session-key)
  "Move point to the row for SESSION-KEY in the manager buffer."
  (goto-char (point-min))
  (while (and (not (eobp))
              (not (equal (get-text-property (point) 'claude-code-ide-manager-session-key)
                          session-key)))
    (forward-line 1))
  (beginning-of-line))

(defun claude-code-ide-manager--sync-point-to-session-key (session-key)
  "Move manager buffer point to SESSION-KEY when the buffer exists."
  (when-let ((buffer (get-buffer claude-code-ide-manager--buffer-name)))
    (with-current-buffer buffer
      (claude-code-ide-manager--move-point-to-session-key session-key)
      (let ((position (point)))
        (when-let ((window (get-buffer-window buffer)))
          (set-window-point window position))))))

(defun claude-code-ide-manager--refresh-sidebar-state ()
  "Rerender the manager buffer and sync the sidebar window point."
  (when-let ((buffer (get-buffer claude-code-ide-manager--buffer-name)))
    (with-current-buffer buffer
      (claude-code-ide-manager--render)
      (let ((position (point)))
        (when-let ((window (get-buffer-window buffer)))
          (set-window-point window position))))))

(defun claude-code-ide-manager--cycle-session-key (step)
  "Return the visible session key STEP positions away from point, cycling."
  (let* ((keys (claude-code-ide-manager--visible-session-keys))
         (count (length keys))
         (current (or (get-text-property (point) 'claude-code-ide-manager-session-key)
                      claude-code-ide-manager--current-session-key))
         (index (cl-position current keys :test #'equal)))
    (when (> count 0)
      (cond
       (index (nth (mod (+ index step) count) keys))
       ((> step 0) (car keys))
       (t (car (last keys)))))))

(defun claude-code-ide-manager--sidebar-buffer-p ()
  "Return non-nil when the current buffer is the manager buffer."
  (not (null (derived-mode-p 'claude-code-ide-manager-mode))))

(defun claude-code-ide-manager-next-line ()
  "Move point to the next manager row and switch to it."
  (interactive)
  (when-let ((session-key (claude-code-ide-manager--cycle-session-key 1)))
    (claude-code-ide-manager--sync-point-to-session-key session-key)
    (claude-code-ide-manager-switch-to-session
     session-key
     (claude-code-ide-manager--sidebar-buffer-p))))

(defun claude-code-ide-manager-previous-line ()
  "Move point to the previous manager row and switch to it."
  (interactive)
  (when-let ((session-key (claude-code-ide-manager--cycle-session-key -1)))
    (claude-code-ide-manager--sync-point-to-session-key session-key)
    (claude-code-ide-manager-switch-to-session
     session-key
     (claude-code-ide-manager--sidebar-buffer-p))))

(defun claude-code-ide-manager-focus ()
  "Focus the manager sidebar."
  (interactive)
  (claude-code-ide-manager-toggle-sidebar 1))

(defun claude-code-ide-manager--toggle-pin-for-session-key (session-key)
  "Toggle pin state for SESSION-KEY."
  (when-let ((item (claude-code-ide-manager--item-by-session-key session-key)))
    (setf (claude-code-ide-manager-item-pinned item)
          (not (claude-code-ide-manager-item-pinned item)))
    (setq claude-code-ide-manager--items
          (mapcar (lambda (current)
                    (if (equal (claude-code-ide-manager-item-session-key current)
                               session-key)
                        item
                      current))
                  claude-code-ide-manager--items))
    (claude-code-ide-manager--save-state)
    (claude-code-ide-manager--render)))

(defun claude-code-ide-manager-toggle-pin ()
  "Toggle pin state for the item at point."
  (interactive)
  (when-let* ((item (claude-code-ide-manager--item-at-point))
              (session-key (claude-code-ide-manager-item-session-key item)))
    (claude-code-ide-manager--toggle-pin-for-session-key session-key)))

(defun claude-code-ide-manager-toggle-current-session-pin ()
  "Toggle pin state for the current active manager session."
  (interactive)
  (when claude-code-ide-manager--current-session-key
    (claude-code-ide-manager--toggle-pin-for-session-key
     claude-code-ide-manager--current-session-key)))

(defun claude-code-ide-manager-move-up ()
  "Move the current row up within its pinned bucket."
  (interactive)
  (when-let* ((item (claude-code-ide-manager--item-at-point))
              (neighbor (claude-code-ide-manager--neighbor-in-bucket
                         (claude-code-ide-manager-item-session-key item) -1)))
    (claude-code-ide-manager--swap-order item neighbor)))

(defun claude-code-ide-manager-move-down ()
  "Move the current row down within its pinned bucket."
  (interactive)
  (when-let* ((item (claude-code-ide-manager--item-at-point))
              (neighbor (claude-code-ide-manager--neighbor-in-bucket
                         (claude-code-ide-manager-item-session-key item) 1)))
    (claude-code-ide-manager--swap-order item neighbor)))

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
           (selected-buffer (and selected-buffer-name
                                 (not (equal selected-buffer-name
                                             claude-code-ide-manager--buffer-name))
                                 (get-buffer selected-buffer-name)))
           (session-buffer (claude-code-ide--get-session-buffer session-key))
           (target-window (or (and selected-buffer
                                   (get-buffer-window selected-buffer))
                              (and session-buffer
                                   (get-buffer-window session-buffer)))))
      (when target-window
        (select-window target-window))
      target-window)))

(defun claude-code-ide-manager--build-default-layout (session-key)
  "Build the default layout for SESSION-KEY and return the session window."
  (let ((session-buffer (claude-code-ide--get-session-buffer session-key)))
    (unless (buffer-live-p session-buffer)
      (claude-code-ide-manager-refresh)
      (user-error "No live session buffer for %s" session-key))
    (let ((status-buffer (claude-code-ide-manager--open-status-buffer session-key)))
      (select-window (claude-code-ide-manager--content-window))
      (delete-other-windows)
      (let ((status-window (selected-window))
            (session-window nil))
        (set-window-buffer status-window status-buffer)
        (setq session-window (split-window status-window nil 'right))
        (set-window-buffer session-window session-buffer)
        (setq claude-code-ide-manager--current-session-key session-key)
        (claude-code-ide-manager--show-sidebar)
        (select-window session-window)
        session-window))))

(defun claude-code-ide-manager--ensure-live-target (session-key)
  "Return non-nil when SESSION-KEY still has a live session."
  (if (or (member session-key (claude-code-ide-manager--live-session-keys))
          (buffer-live-p (claude-code-ide--get-session-buffer session-key)))
      t
    (claude-code-ide-manager-refresh)
    nil))

(defun claude-code-ide-manager-switch-to-session (session-key &optional keep-manager-focus)
  "Switch the current frame to SESSION-KEY.

When KEEP-MANAGER-FOCUS is non-nil, reselect the manager window after the
session layout is updated."
  (interactive)
  (when claude-code-ide-manager--current-session-key
    (puthash claude-code-ide-manager--current-session-key
             (claude-code-ide-manager--capture-layout
              claude-code-ide-manager--current-session-key)
             claude-code-ide-manager--layouts)
    (claude-code-ide-manager--save-state))
  (prog1
      (or (claude-code-ide-manager--restore-layout session-key)
          (claude-code-ide-manager--build-default-layout session-key))
    (claude-code-ide-manager--refresh-sidebar-state)
    (when keep-manager-focus
      (when-let ((window (get-buffer-window (claude-code-ide-manager--get-buffer))))
        (select-window window)))))

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

(defun claude-code-ide-manager-switch-by-slot-preserve-focus (slot)
  "Switch to visible SLOT and keep focus in the manager."
  (when-let* ((item (nth (1- slot)
                         (cl-subseq (claude-code-ide-manager--sorted-items
                                     claude-code-ide-manager--items)
                                    0
                                    (min 10 (length claude-code-ide-manager--items)))))
              (session-key (claude-code-ide-manager-item-session-key item)))
    (claude-code-ide-manager--sync-point-to-session-key session-key)
    (claude-code-ide-manager-switch-to-session session-key t)))

(defun claude-code-ide-manager-switch-by-slot (slot)
  "Switch to visible SLOT."
  (interactive "nSlot: ")
  (when-let* ((item (nth (1- slot)
                         (cl-subseq (claude-code-ide-manager--sorted-items
                                     claude-code-ide-manager--items)
                                    0
                                    (min 10 (length claude-code-ide-manager--items)))))
              (session-key (claude-code-ide-manager-item-session-key item)))
    (claude-code-ide-manager--sync-point-to-session-key session-key)
    (claude-code-ide-manager-switch-to-session session-key)))

(claude-code-ide-manager--initialize)

(provide 'claude-code-ide-manager)
;;; claude-code-ide-manager.el ends here
