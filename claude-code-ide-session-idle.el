;;; claude-code-ide-session-idle.el --- Session idle core for Claude Code IDE  -*- lexical-binding: t; -*-

;; Copyright (C) 2025

;; Author: Yoav Orot
;; Keywords: ai, claude, sessions, idle

;; This file is not part of GNU Emacs.

;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;;; Commentary:

;; Generic session idle infrastructure for Claude Code IDE.
;; This module owns the package-level idle timer state, enable/disable
;; commands, timer reset/fire helpers, and the hook that initializes
;; session-local idle monitoring when a session buffer is set up.

;;; Code:

(require 'cl-lib)

(declare-function claude-code-ide-session-buffer-p "claude-code-ide-session" (buffer))

(defvar claude-code-ide-session-setup-hook)

(defgroup claude-code-ide-session-idle nil
  "Idle monitoring for Claude Code IDE sessions."
  :group 'claude-code-ide-session
  :prefix "claude-code-ide-session-idle-")

(defcustom claude-code-ide-session-idle-delay 30
  "Idle delay in seconds before the session idle hook runs."
  :type 'number
  :group 'claude-code-ide-session-idle)

(defcustom claude-code-ide-session-idle-default-enabled nil
  "Whether session idle monitoring is enabled by default."
  :type 'boolean
  :group 'claude-code-ide-session-idle)

(defcustom claude-code-ide-session-idle-notification-policy 'manager
  "How idle transitions should notify the user.

`nil' means keep idle state only.
`manager' means rely on manager/sidebar idle state only.
`alert' means emit alerts in addition to idle state changes.
`manager-and-alert' means preserve manager idle state and emit alerts."
  :type '(choice (const :tag "Idle state only" nil)
                 (const :tag "Manager only" manager)
                 (const :tag "Alert only" alert)
                 (const :tag "Manager and alert" manager-and-alert))
  :group 'claude-code-ide-session-idle)

(defcustom claude-code-ide-session-idle-suppressed-predicate nil
  "Predicate function used to suppress session idle monitoring.
When non-nil, it is called with the session buffer.  A non-nil return value
prevents idle timer scheduling and idle hook execution."
  :type '(choice (const :tag "Disabled" nil)
                 (function :tag "Predicate"))
  :group 'claude-code-ide-session-idle)

(defvar claude-code-ide-session-idle-hook nil
  "Hook run when a session idle timer fires.")

(defvar-local claude-code-ide-session-idle-enabled nil
  "Non-nil when idle monitoring is enabled for the current session buffer.")

(defvar-local claude-code-ide-session-idle-p nil
  "Non-nil when the current session buffer is idle.")

(defvar-local claude-code-ide-session-idle-generation 0
  "Monotonic token for the currently scheduled idle callback.")

(defvar-local claude-code-ide-session-idle-timer nil
  "Idle timer object for the current session buffer.")

(defvar claude-code-ide-session-idle--selected-frame-visible-buffers-by-frame nil
  "Hash table of Claude session buffers last seen visible per frame.")

(defvar claude-code-ide-session-idle--in-visibility-refresh nil
  "Non-nil while handling selected-frame visibility changes.")

(defvar claude-code-ide-session-idle--visibility-refresh-timer nil
  "Timer used to defer focus-driven visibility refreshes.")

(defvaralias 'claude-code-ide-session-idle--enabled
  'claude-code-ide-session-idle-enabled)

(defvaralias 'claude-code-ide-session-idle--timer
  'claude-code-ide-session-idle-timer)

(defun claude-code-ide-session-idle--suppressed-p (&optional buffer)
  "Return non-nil when idle monitoring should be suppressed."
  (and (functionp claude-code-ide-session-idle-suppressed-predicate)
       (funcall claude-code-ide-session-idle-suppressed-predicate
                (or buffer (current-buffer)))))

(defun claude-code-ide-session-idle--clear-timer ()
  "Cancel the current session idle timer, if any."
  (when (timerp claude-code-ide-session-idle-timer)
    (cancel-timer claude-code-ide-session-idle-timer))
  (setq claude-code-ide-session-idle-generation
        (1+ claude-code-ide-session-idle-generation)
        claude-code-ide-session-idle-timer nil
        claude-code-ide-session-idle-p nil))

(defun claude-code-ide-session-idle--ensure-session-buffer ()
  "Signal a user error unless the current buffer is a session buffer."
  (unless (claude-code-ide-session-buffer-p (current-buffer))
    (user-error "Idle monitoring only applies to Claude Code session buffers")))

(defun claude-code-ide-session-idle--maybe-reset-timer (&optional buffer)
  "Reset idle monitoring for BUFFER when it is a session buffer."
  (let ((target-buffer (or buffer (current-buffer))))
    (when (and (buffer-live-p target-buffer)
               (claude-code-ide-session-buffer-p target-buffer))
      (with-current-buffer target-buffer
        (claude-code-ide-session-idle-reset-timer)))))

(defun claude-code-ide-session-idle--visible-session-buffers-on-frame (&optional frame)
  "Return Claude session buffers visible on FRAME."
  (let ((frame (or frame (selected-frame)))
        (buffers nil))
    (dolist (window (window-list frame 'no-minibuffer))
      (let ((buffer (window-buffer window)))
        (when (and (buffer-live-p buffer)
                   (claude-code-ide-session-buffer-p buffer))
          (push buffer buffers))))
    (nreverse (delete-dups buffers))))

(defun claude-code-ide-session-idle--notify (buffer)
  "Emit an idle notification for BUFFER when policy includes alerts."
  (when (memq claude-code-ide-session-idle-notification-policy
              '(alert manager-and-alert))
    (when (fboundp 'alert)
      (alert (format "Session idle: %s" (buffer-name buffer))
             :title "Claude Code"))))

(defun claude-code-ide-session-idle--visible-buffers-table ()
  "Return the selected-frame visibility table, initializing it when needed."
  (unless (hash-table-p claude-code-ide-session-idle--selected-frame-visible-buffers-by-frame)
    (setq claude-code-ide-session-idle--selected-frame-visible-buffers-by-frame
          (make-hash-table :test 'eq)))
  claude-code-ide-session-idle--selected-frame-visible-buffers-by-frame)

(defun claude-code-ide-session-idle--handle-selected-frame-visibility-change ()
  "Reset idle for session buffers that became newly visible on the selected frame."
  (unless claude-code-ide-session-idle--in-visibility-refresh
    (let* ((claude-code-ide-session-idle--in-visibility-refresh t)
           (frame (selected-frame))
           (table (claude-code-ide-session-idle--visible-buffers-table))
           (current (claude-code-ide-session-idle--visible-session-buffers-on-frame))
           (previous (gethash frame table)))
      (dolist (buffer current)
        (when (and (buffer-live-p buffer)
                   (not (memq buffer previous)))
          (with-current-buffer buffer
            (when claude-code-ide-session-idle-enabled
              (claude-code-ide-session-idle-reset-timer)))))
      (puthash frame current table))))

(defun claude-code-ide-session-idle--run-visibility-refresh ()
  "Run the deferred selected-frame visibility refresh."
  (setq claude-code-ide-session-idle--visibility-refresh-timer nil)
  (claude-code-ide-session-idle--handle-selected-frame-visibility-change))

(defun claude-code-ide-session-idle--schedule-visibility-refresh (&rest _)
  "Schedule a selected-frame visibility refresh after focus changes settle."
  (unless (timerp claude-code-ide-session-idle--visibility-refresh-timer)
    (setq claude-code-ide-session-idle--visibility-refresh-timer
          (run-at-time 0 nil
                       #'claude-code-ide-session-idle--run-visibility-refresh))))

(defun claude-code-ide-session-idle--filter-advice (orig-fn &rest args)
  "Run ORIG-FN, then reset the idle timer for session buffers."
  (let ((process-buffer (ignore-errors
                          (process-buffer (car args)))))
    (prog1 (apply orig-fn args)
      (claude-code-ide-session-idle--maybe-reset-timer process-buffer))))

(defun claude-code-ide-session-idle--install-output-observer (symbol)
  "Install the output observer for SYMBOL when available."
  (unless (advice-member-p #'claude-code-ide-session-idle--filter-advice symbol)
    (advice-add symbol :around #'claude-code-ide-session-idle--filter-advice)))

(defun claude-code-ide-session-idle--install-output-observers ()
  "Install output observers for supported terminal backends."
  (with-eval-after-load 'vterm
    (claude-code-ide-session-idle--install-output-observer 'vterm--filter))
  (with-eval-after-load 'eat
    (claude-code-ide-session-idle--install-output-observer 'eat--filter))
  (when (featurep 'vterm)
    (claude-code-ide-session-idle--install-output-observer 'vterm--filter))
  (when (featurep 'eat)
    (claude-code-ide-session-idle--install-output-observer 'eat--filter)))

(defun claude-code-ide-session-idle--fire-timer (buffer &optional generation)
  "Run the idle hook for BUFFER if monitoring is still active."
  (when (buffer-live-p buffer)
    (with-current-buffer buffer
      (when (or (null generation)
                (= generation claude-code-ide-session-idle-generation))
        (setq claude-code-ide-session-idle-timer nil)
        (when (and claude-code-ide-session-idle-enabled
                   (not (claude-code-ide-session-idle--suppressed-p buffer)))
          (setq claude-code-ide-session-idle-p t)
          (claude-code-ide-session-idle--notify buffer)
          (run-hook-with-args 'claude-code-ide-session-idle-hook buffer))))))

(defun claude-code-ide-session-idle-reset-timer ()
  "Reset the idle timer for the current session buffer."
  (interactive)
  (claude-code-ide-session-idle--ensure-session-buffer)
  (claude-code-ide-session-idle--clear-timer)
  (when (and claude-code-ide-session-idle-enabled
             (not (claude-code-ide-session-idle--suppressed-p (current-buffer)))
             (claude-code-ide-session-buffer-p (current-buffer)))
    (setq claude-code-ide-session-idle-timer
          (run-with-idle-timer claude-code-ide-session-idle-delay nil
                               #'claude-code-ide-session-idle--fire-timer
                               (current-buffer)
                               claude-code-ide-session-idle-generation)))
  claude-code-ide-session-idle-timer)

(defun claude-code-ide-session-idle-enable ()
  "Enable idle monitoring in the current session buffer."
  (interactive)
  (claude-code-ide-session-idle--ensure-session-buffer)
  (setq claude-code-ide-session-idle-enabled t)
  (claude-code-ide-session-idle-reset-timer))

(defun claude-code-ide-session-idle-disable ()
  "Disable idle monitoring in the current session buffer."
  (interactive)
  (claude-code-ide-session-idle--ensure-session-buffer)
  (setq claude-code-ide-session-idle-enabled nil)
  (claude-code-ide-session-idle--clear-timer))

(defun claude-code-ide-session-idle-toggle ()
  "Toggle idle monitoring in the current session buffer."
  (interactive)
  (claude-code-ide-session-idle--ensure-session-buffer)
  (if claude-code-ide-session-idle-enabled
      (claude-code-ide-session-idle-disable)
    (claude-code-ide-session-idle-enable)))

(defun claude-code-ide-session-idle--setup-buffer ()
  "Initialize idle monitoring state for the current session buffer."
  (when (claude-code-ide-session-buffer-p (current-buffer))
    (setq claude-code-ide-session-idle-enabled
          claude-code-ide-session-idle-default-enabled)
    (if claude-code-ide-session-idle-enabled
        (claude-code-ide-session-idle-reset-timer)
      (claude-code-ide-session-idle--clear-timer))))

(defun claude-code-ide-session-idle-unload-function ()
  "Clean up global hooks and timers installed by session idle."
  (remove-hook 'window-configuration-change-hook
               #'claude-code-ide-session-idle--handle-selected-frame-visibility-change)
  (remove-hook 'window-state-change-hook
               #'claude-code-ide-session-idle--handle-selected-frame-visibility-change)
  (remove-function after-focus-change-function
                   #'claude-code-ide-session-idle--schedule-visibility-refresh)
  (when (timerp claude-code-ide-session-idle--visibility-refresh-timer)
    (cancel-timer claude-code-ide-session-idle--visibility-refresh-timer))
  (setq claude-code-ide-session-idle--visibility-refresh-timer nil)
  nil)

(claude-code-ide-session-idle--install-output-observers)

(remove-hook 'window-configuration-change-hook
             #'claude-code-ide-session-idle--handle-selected-frame-visibility-change)

(unless (memq #'claude-code-ide-session-idle--handle-selected-frame-visibility-change
              window-state-change-hook)
  (add-hook 'window-state-change-hook
            #'claude-code-ide-session-idle--handle-selected-frame-visibility-change))

(add-function :after after-focus-change-function
              #'claude-code-ide-session-idle--schedule-visibility-refresh)

(add-hook 'claude-code-ide-session-setup-hook
          #'claude-code-ide-session-idle--setup-buffer)

(provide 'claude-code-ide-session-idle)

;;; claude-code-ide-session-idle.el ends here
