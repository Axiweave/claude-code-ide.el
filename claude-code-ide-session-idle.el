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
(require 'subr-x)
(require 'claude-code-ide-debug)

(declare-function claude-code-ide--get-related-session-directories "claude-code-ide" (&optional directory))
(declare-function claude-code-ide-session-buffer-p "claude-code-ide-session" (buffer))
(declare-function claude-code-ide--get-session-buffer "claude-code-ide" (&optional directory))

(defvar claude-code-ide-session-setup-hook)

(defgroup claude-code-ide-session-idle nil
  "Idle monitoring for Claude Code IDE sessions."
  :group 'claude-code-ide-session
  :prefix "claude-code-ide-session-idle-")

(defcustom claude-code-ide-session-idle-delay 5
  "Idle delay in seconds before the session idle hook runs."
  :type 'number
  :group 'claude-code-ide-session-idle)

(defcustom claude-code-ide-session-idle-default-enabled nil
  "Whether session idle monitoring is enabled by default."
  :type 'boolean
  :group 'claude-code-ide-session-idle)

(defcustom claude-code-ide-session-working-delay 3
  "Seconds a session stays in working state after terminal output."
  :type 'number
  :group 'claude-code-ide-session-idle)

(defcustom claude-code-ide-session-working-resize-suppress-delay 0.75
  "Seconds to ignore working detection after a terminal resize."
  :type 'number
  :group 'claude-code-ide-session-idle)

(defcustom claude-code-ide-session-tracking-start-delay 10
  "Seconds to ignore idle and working tracking after session setup."
  :type 'number
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

(defvar claude-code-ide-session-working-hook nil
  "Hook run when a session's working state changes.")

(defvar-local claude-code-ide-session-idle-enabled nil
  "Non-nil when idle monitoring is enabled for the current session buffer.")

(defvar-local claude-code-ide-session-idle-p nil
  "Non-nil when the current session buffer is idle.")

(defvar-local claude-code-ide-session-working-p nil
  "Non-nil when the current session buffer has seen recent terminal output.")

(defvar-local claude-code-ide-session-idle-generation 0
  "Monotonic token for the currently scheduled idle callback.")

(defvar-local claude-code-ide-session-working-generation 0
  "Monotonic token for the currently scheduled working callback.")

(defvar-local claude-code-ide-session-tracking-start-generation 0
  "Monotonic token for the currently scheduled tracking-start callback.")

(defvar-local claude-code-ide-session-idle-timer nil
  "Idle timer object for the current session buffer.")

(defvar-local claude-code-ide-session-working-timer nil
  "Working timer object for the current session buffer.")

(defvar-local claude-code-ide-session-working-suppress-until nil
  "Absolute time in seconds until working detection stays suppressed.")

(defvar-local claude-code-ide-session-tracking-start-timer nil
  "Timer object that enables tracking after the startup grace window.")

(defvar-local claude-code-ide-session-tracking-started-p t
  "Non-nil when idle and working tracking are active for this session.")

(defvaralias 'claude-code-ide-session-idle--enabled
  'claude-code-ide-session-idle-enabled)

(defvaralias 'claude-code-ide-session-idle--timer
  'claude-code-ide-session-idle-timer)

(defvar claude-code-ide-session-idle--in-visibility-refresh nil
  "Non-nil while visible-session idle state is being refreshed.")

(defvar-local claude-code-ide-session-idle--prompt-owner-directory nil
  "Cached session directory that owns the current prompt-edit buffer.")

(defun claude-code-ide-session-idle--suppressed-p (&optional buffer)
  "Return non-nil when idle monitoring should be suppressed."
  (or (claude-code-ide-session-idle--prompt-edit-suppressed-p
       (or buffer (current-buffer)))
      (and (functionp claude-code-ide-session-idle-suppressed-predicate)
           (funcall claude-code-ide-session-idle-suppressed-predicate
                    (or buffer (current-buffer))))))

(defun claude-code-ide-session-idle--clear-timer ()
  "Cancel the current session idle timer, if any."
  (when (timerp claude-code-ide-session-idle-timer)
    (cancel-timer claude-code-ide-session-idle-timer))
  (setq claude-code-ide-session-idle-generation
        (1+ claude-code-ide-session-idle-generation)
        claude-code-ide-session-idle-timer nil
        claude-code-ide-session-idle-p nil))

(defun claude-code-ide-session-working--set-state (state)
  "Set the current session buffer's working STATE and run hooks on change."
  (let ((new-state (and state t)))
    (unless (eq claude-code-ide-session-working-p new-state)
      (setq claude-code-ide-session-working-p new-state)
      (run-hook-with-args 'claude-code-ide-session-working-hook
                          (current-buffer)))))

(defun claude-code-ide-session-working--clear-timer ()
  "Cancel the current session working timer, if any."
  (when (timerp claude-code-ide-session-working-timer)
    (cancel-timer claude-code-ide-session-working-timer))
  (setq claude-code-ide-session-working-generation
        (1+ claude-code-ide-session-working-generation)
        claude-code-ide-session-working-timer nil))

(defun claude-code-ide-session-working-clear-state ()
  "Clear working state in the current session buffer."
  (claude-code-ide-session-working--clear-timer)
  (claude-code-ide-session-working--set-state nil))

(defun claude-code-ide-session-tracking--active-p ()
  "Return non-nil when idle and working tracking are active."
  claude-code-ide-session-tracking-started-p)

(defun claude-code-ide-session-tracking--clear-timer ()
  "Cancel the current session tracking-start timer, if any."
  (when (timerp claude-code-ide-session-tracking-start-timer)
    (cancel-timer claude-code-ide-session-tracking-start-timer))
  (setq claude-code-ide-session-tracking-start-generation
        (1+ claude-code-ide-session-tracking-start-generation)
        claude-code-ide-session-tracking-start-timer nil))

(defun claude-code-ide-session-tracking--arm-start-timer ()
  "Arm the startup grace timer for the current session buffer."
  (when (> claude-code-ide-session-tracking-start-delay 0)
    (setq claude-code-ide-session-tracking-start-timer
          (run-with-timer claude-code-ide-session-tracking-start-delay nil
                          #'claude-code-ide-session-tracking--fire-start-timer
                          (current-buffer)
                          claude-code-ide-session-tracking-start-generation))))

(defun claude-code-ide-session-tracking--fire-start-timer (buffer &optional generation)
  "Enable tracking for BUFFER when GENERATION is still current."
  (when (buffer-live-p buffer)
    (with-current-buffer buffer
      (when (or (null generation)
                (= generation claude-code-ide-session-tracking-start-generation))
        (setq claude-code-ide-session-tracking-start-timer nil
              claude-code-ide-session-tracking-started-p t)
        (unless (claude-code-ide-session-idle--buffer-visible-in-focused-frame-p
                 buffer)
          (claude-code-ide-session-idle--arm-timer))))))

(defun claude-code-ide-session-working--arm-timer ()
  "Arm the working timer for the current session buffer."
  (when (> claude-code-ide-session-working-delay 0)
    (setq claude-code-ide-session-working-timer
          (run-with-timer claude-code-ide-session-working-delay nil
                          #'claude-code-ide-session-working--fire-timer
                          (current-buffer)
                          claude-code-ide-session-working-generation)))
  claude-code-ide-session-working-timer)

(defun claude-code-ide-session-working--suppressed-p ()
  "Return non-nil when working detection is temporarily suppressed."
  (and claude-code-ide-session-working-suppress-until
       (< (float-time (current-time))
          claude-code-ide-session-working-suppress-until)))

(defun claude-code-ide-session-working-suppress-after-resize (&optional buffer)
  "Suppress working detection briefly for session BUFFER after a resize."
  (let ((target-buffer (or buffer (current-buffer))))
    (when (and (buffer-live-p target-buffer)
               (claude-code-ide-session-buffer-p target-buffer))
      (with-current-buffer target-buffer
        (setq claude-code-ide-session-working-suppress-until
              (when (> claude-code-ide-session-working-resize-suppress-delay 0)
                (+ (float-time (current-time))
                   claude-code-ide-session-working-resize-suppress-delay)))))))

(defun claude-code-ide-session-working-record-output (&optional buffer)
  "Record terminal output activity for BUFFER."
  (let ((target-buffer (or buffer (current-buffer))))
    (when (and (buffer-live-p target-buffer)
               (claude-code-ide-session-buffer-p target-buffer))
      (with-current-buffer target-buffer
        (when (and (claude-code-ide-session-tracking--active-p)
                   (not (claude-code-ide-session-working--suppressed-p)))
          (claude-code-ide-session-working--clear-timer)
          (claude-code-ide-session-working--set-state t)
          (claude-code-ide-session-working--arm-timer))))))

(defun claude-code-ide-session-working--fire-timer (buffer &optional generation)
  "Clear BUFFER's working state if GENERATION is still current."
  (when (buffer-live-p buffer)
    (with-current-buffer buffer
      (when (or (null generation)
                (= generation claude-code-ide-session-working-generation))
        (setq claude-code-ide-session-working-timer nil)
        (claude-code-ide-session-working--set-state nil)))))

(defun claude-code-ide-session-idle-clear-state ()
  "Clear idle state in the current session buffer without rearming a timer."
  (interactive)
  (claude-code-ide-session-idle--ensure-session-buffer)
  (claude-code-ide-session-idle--clear-timer))

(defun claude-code-ide-session-idle--ensure-session-buffer ()
  "Signal a user error unless the current buffer is a session buffer."
  (unless (claude-code-ide-session-buffer-p (current-buffer))
    (user-error "Idle monitoring only applies to Claude Code session buffers")))

(defun claude-code-ide-session-idle--arm-timer ()
  "Arm the idle timer for the current session buffer."
  (when (and claude-code-ide-session-idle-enabled
             (claude-code-ide-session-tracking--active-p)
             (not (claude-code-ide-session-idle--suppressed-p (current-buffer)))
             (claude-code-ide-session-buffer-p (current-buffer)))
    (setq claude-code-ide-session-idle-timer
          (run-with-timer claude-code-ide-session-idle-delay nil
                          #'claude-code-ide-session-idle--fire-timer
                          (current-buffer)
                          claude-code-ide-session-idle-generation)))
  claude-code-ide-session-idle-timer)

(defun claude-code-ide-session-idle-record-activity (&optional buffer)
  "Record output activity for BUFFER and rearm only when hidden.
The current idle state is cleared first so stale idle state never survives
fresh output from the session backend."
  (let ((target-buffer (or buffer (current-buffer))))
    (when (and (buffer-live-p target-buffer)
               (claude-code-ide-session-buffer-p target-buffer))
      (with-current-buffer target-buffer
        (when (claude-code-ide-session-tracking--active-p)
          (claude-code-ide-session-idle-clear-state)
          (unless (claude-code-ide-session-idle--buffer-visible-in-focused-frame-p
                   target-buffer)
            (claude-code-ide-session-idle--arm-timer)))))))

(defun claude-code-ide-session-idle--buffer-visible-in-focused-frame-p (&optional buffer)
  "Return non-nil when BUFFER is visible in a focused frame."
  (let ((target-buffer (or buffer (current-buffer))))
    (cl-some (lambda (window)
               (frame-focus-state (window-frame window)))
             (get-buffer-window-list target-buffer nil t))))

(defun claude-code-ide-session-idle--visible-prompt-buffers ()
  "Return visible prompt-edit buffers shown in focused frames."
  (let (buffers)
    (walk-windows
     (lambda (window)
       (let ((buffer (window-buffer window)))
         (when (and (buffer-live-p buffer)
                    (frame-focus-state (window-frame window))
                    (with-current-buffer buffer
                      (bound-and-true-p leo/ai-tmp-prompt-file-mode))
                    (not (memq buffer buffers)))
           (push buffer buffers))))
     'no-minibuf
     'visible)
    (nreverse buffers)))

(defun claude-code-ide-session-idle--visible-session-buffers (&optional frame)
  "Return visible session buffers shown in focused FRAME or any focused frame."
  (let (buffers)
    (walk-windows
     (lambda (window)
       (let ((buffer (window-buffer window))
             (window-frame (window-frame window)))
         (when (and (buffer-live-p buffer)
                    (frame-focus-state window-frame)
                    (claude-code-ide-session-buffer-p buffer)
                    (or (null frame)
                        (eq frame window-frame))
                    (not (memq buffer buffers)))
           (push buffer buffers))))
     'no-minibuf
     'visible)
    (nreverse buffers)))

(defun claude-code-ide-session-idle--cache-prompt-owner (prompt-buffer session-buffer)
  "Cache SESSION-BUFFER ownership on PROMPT-BUFFER."
  (when (and (buffer-live-p prompt-buffer)
             (buffer-live-p session-buffer))
    (with-current-buffer prompt-buffer
      (setq-local claude-code-ide-session-idle--prompt-owner-directory
                  (file-name-as-directory
                   (expand-file-name
                    (with-current-buffer session-buffer
                      default-directory)))))))

(defun claude-code-ide-session-idle--prompt-buffer-cached-session-buffer (prompt-buffer)
  "Return the cached owner session buffer for PROMPT-BUFFER."
  (when (buffer-live-p prompt-buffer)
    (with-current-buffer prompt-buffer
      (when claude-code-ide-session-idle--prompt-owner-directory
        (when-let ((buffer
                    (claude-code-ide--get-session-buffer
                     claude-code-ide-session-idle--prompt-owner-directory)))
          (and (buffer-live-p buffer)
               buffer))))))

(defun claude-code-ide-session-idle--prompt-buffer-window-history-session-buffer (prompt-buffer)
  "Return the owner session buffer for PROMPT-BUFFER from window history."
  (cl-some (lambda (window)
             (when (and (window-live-p window)
                        (frame-focus-state (window-frame window)))
               (cl-some (lambda (entry)
                          (let ((buffer (car entry)))
                            (and (buffer-live-p buffer)
                                 (claude-code-ide-session-buffer-p buffer)
                                 buffer)))
                        (window-prev-buffers window))))
           (get-buffer-window-list prompt-buffer nil t)))

(defun claude-code-ide-session-idle--prompt-buffer-visible-session-buffer (prompt-buffer)
  "Return the sole visible session buffer in PROMPT-BUFFER's focused frame."
  (cl-some (lambda (window)
             (when (and (window-live-p window)
                        (frame-focus-state (window-frame window)))
               (let ((buffers
                      (claude-code-ide-session-idle--visible-session-buffers
                       (window-frame window))))
                 (and (= (length buffers) 1)
                      (car buffers)))))
           (get-buffer-window-list prompt-buffer nil t)))

(defun claude-code-ide-session-idle--prompt-buffer-session-buffer (prompt-buffer)
  "Return the live session buffer owned by PROMPT-BUFFER."
  (when (buffer-live-p prompt-buffer)
    (let ((session-buffer
           (or (claude-code-ide-session-idle--prompt-buffer-cached-session-buffer
                prompt-buffer)
               (claude-code-ide-session-idle--prompt-buffer-window-history-session-buffer
                prompt-buffer)
               (claude-code-ide-session-idle--prompt-buffer-visible-session-buffer
                prompt-buffer)
               (when (and (fboundp 'claude-code-ide--get-related-session-directories)
                          (fboundp 'claude-code-ide--get-session-buffer))
                 (with-current-buffer prompt-buffer
                   (cl-some (lambda (directory)
                              (let ((buffer
                                     (claude-code-ide--get-session-buffer
                                      directory)))
                                (and (buffer-live-p buffer)
                                     buffer)))
                            (claude-code-ide--get-related-session-directories
                             default-directory)))))))
      (when session-buffer
        (claude-code-ide-session-idle--cache-prompt-owner
         prompt-buffer
         session-buffer))
      session-buffer)))

(defun claude-code-ide-session-idle--visible-prompt-session-buffers ()
  "Return live session buffers owned by visible prompt-edit buffers."
  (let (buffers)
    (dolist (prompt-buffer
             (claude-code-ide-session-idle--visible-prompt-buffers))
      (when-let ((buffer
                  (claude-code-ide-session-idle--prompt-buffer-session-buffer
                   prompt-buffer)))
        (cl-pushnew buffer buffers)))
    (nreverse buffers)))

(defun claude-code-ide-session-idle--prompt-edit-suppressed-p (&optional buffer)
  "Return non-nil when BUFFER belongs to the session currently editing a prompt."
  (let ((target-buffer (or buffer (current-buffer)))
        (prompt-session-buffers
         (claude-code-ide-session-idle--visible-prompt-session-buffers)))
    (and (buffer-live-p target-buffer)
         (memq target-buffer prompt-session-buffers))))

(defun claude-code-ide-session-idle--clear-visible-prompt-session-idle-state ()
  "Clear idle state for sessions that own visible prompt-edit buffers."
  (dolist (buffer
           (claude-code-ide-session-idle--visible-prompt-session-buffers))
    (when (buffer-live-p buffer)
      (with-current-buffer buffer
        (when (and claude-code-ide-session-idle-enabled
                   (claude-code-ide-session-buffer-p buffer))
          (claude-code-ide-session-idle-clear-state))))))

(defun claude-code-ide-session-idle--refresh-visible-session-idle-state ()
  "Clear idle state for session buffers visible in a focused frame."
  (unless claude-code-ide-session-idle--in-visibility-refresh
    (let ((claude-code-ide-session-idle--in-visibility-refresh t)
          (seen-buffers nil))
      (walk-windows
       (lambda (window)
         (let ((buffer (window-buffer window)))
           (when (and (buffer-live-p buffer)
                      (frame-focus-state (window-frame window))
                      (claude-code-ide-session-buffer-p buffer)
                      (not (memq buffer seen-buffers)))
             (push buffer seen-buffers)
             (with-current-buffer buffer
               (claude-code-ide-session-idle-clear-state)))))
       'no-minibuf
       'visible))))

(defun claude-code-ide-session-idle--handle-visibility-change ()
  "Refresh idle state after focus or window visibility changes."
  (claude-code-ide-session-idle--refresh-visible-session-idle-state)
  (claude-code-ide-session-idle--clear-visible-prompt-session-idle-state))

(defun claude-code-ide-session-idle--notify (buffer)
  "Emit an idle notification for BUFFER when policy includes alerts."
  (when (memq claude-code-ide-session-idle-notification-policy
              '(alert manager-and-alert))
    (when (fboundp 'alert)
      (alert (format "Session idle: %s" (buffer-name buffer))
             :title "Claude Code"))))

(defun claude-code-ide-session-idle--debug-output-sample (output)
  "Return a compact debug representation for terminal OUTPUT."
  (let* ((text (format "%S" output))
         (limit 200))
    (if (> (length text) limit)
        (concat (substring text 0 limit) "...")
      text)))

(defun claude-code-ide-session-idle--filter-advice (orig-fn &rest args)
  "Run ORIG-FN, then forward session-buffer activity to the idle helper."
  (let* ((process (car args))
         (output (cadr args))
         (process-buffer (ignore-errors
                           (process-buffer process)))
         (target-buffer (or process-buffer (current-buffer))))
    (prog1 (apply orig-fn args)
      (when (and claude-code-ide-debug
                 process-buffer
                 (buffer-live-p process-buffer))
        (claude-code-ide-debug
         "Idle observer output: process=%s buffer=%s bytes=%d payload=%s"
         (if (processp process)
             (process-name process)
           (format "%S" process))
         (buffer-name process-buffer)
         (if (stringp output)
             (string-bytes output)
           0)
         (claude-code-ide-session-idle--debug-output-sample output)))
      (when (and (buffer-live-p target-buffer)
                 (claude-code-ide-session-buffer-p target-buffer))
        (with-current-buffer target-buffer
          (claude-code-ide-session-idle-record-activity)
          (claude-code-ide-session-working-record-output))))))

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
        (cond
         ((claude-code-ide-session-idle--buffer-visible-in-focused-frame-p buffer)
          (claude-code-ide-session-idle-clear-state))
         ((not (claude-code-ide-session-tracking--active-p))
          nil)
         ((and claude-code-ide-session-idle-enabled
               (not (claude-code-ide-session-idle--suppressed-p buffer)))
          (claude-code-ide-session-working-clear-state)
          (setq claude-code-ide-session-idle-p t)
          (claude-code-ide-session-idle--notify buffer)
          (run-hook-with-args 'claude-code-ide-session-idle-hook buffer)))))))

(defun claude-code-ide-session-idle-reset-timer ()
  "Reset the idle timer for the current session buffer when hidden."
  (interactive)
  (claude-code-ide-session-idle--ensure-session-buffer)
  (claude-code-ide-session-idle--clear-timer)
  (unless (claude-code-ide-session-idle--buffer-visible-in-focused-frame-p
           (current-buffer))
    (claude-code-ide-session-idle--arm-timer))
  claude-code-ide-session-idle-timer)

(defun claude-code-ide-session-idle-enable ()
  "Enable idle monitoring in the current session buffer."
  (interactive)
  (claude-code-ide-session-idle--ensure-session-buffer)
  (setq claude-code-ide-session-idle-enabled t)
  (claude-code-ide-session-idle--clear-timer))

(defun claude-code-ide-session-idle-disable ()
  "Disable idle monitoring in the current session buffer."
  (interactive)
  (claude-code-ide-session-idle--ensure-session-buffer)
  (setq claude-code-ide-session-idle-enabled nil)
  (claude-code-ide-session-idle--clear-timer)
  (claude-code-ide-session-working-clear-state))

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
    (claude-code-ide-session-tracking--clear-timer)
    (setq claude-code-ide-session-idle-enabled
          claude-code-ide-session-idle-default-enabled
          claude-code-ide-session-working-suppress-until nil
          claude-code-ide-session-tracking-started-p
          (<= claude-code-ide-session-tracking-start-delay 0))
    (claude-code-ide-session-idle--clear-timer)
    (claude-code-ide-session-working-clear-state)
    (unless claude-code-ide-session-tracking-started-p
      (claude-code-ide-session-tracking--arm-start-timer))))

(defun claude-code-ide-session-idle-unload-function ()
  "Clean up global hooks and timers installed by session idle."
  (remove-hook 'window-state-change-hook
               #'claude-code-ide-session-idle--handle-visibility-change)
  (remove-hook 'window-configuration-change-hook
               #'claude-code-ide-session-idle--handle-visibility-change)
  (remove-function after-focus-change-function
                   #'claude-code-ide-session-idle--handle-visibility-change)
  nil)

(claude-code-ide-session-idle--install-output-observers)

(unless (memq #'claude-code-ide-session-idle--handle-visibility-change
              window-state-change-hook)
  (add-hook 'window-state-change-hook
            #'claude-code-ide-session-idle--handle-visibility-change))

(unless (memq #'claude-code-ide-session-idle--handle-visibility-change
              window-configuration-change-hook)
  (add-hook 'window-configuration-change-hook
            #'claude-code-ide-session-idle--handle-visibility-change))

(unless (advice-member-p #'claude-code-ide-session-idle--handle-visibility-change
                         'after-focus-change-function)
  (add-function :after after-focus-change-function
                #'claude-code-ide-session-idle--handle-visibility-change))

(add-hook 'claude-code-ide-session-setup-hook
          #'claude-code-ide-session-idle--setup-buffer)

(provide 'claude-code-ide-session-idle)

;;; claude-code-ide-session-idle.el ends here
