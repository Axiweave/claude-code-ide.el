;;; claude-code-ide-session.el --- Session core for Claude Code IDE  -*- lexical-binding: t; -*-

;; Copyright (C) 2025 Yoav Orot
;; Copyright (C) 2026 Yu-Fu Fu

;; Author: Yoav Orot
;; Maintainer: Yu-Fu Fu <yufu@yfu.tw>
;; Keywords: ai, claude, sessions, terminal

;; This file is not part of GNU Emacs.

;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;;; Commentary:

;; Package-owned session support for Claude Code IDE.
;; This module owns the session minor mode, session buffer detection,
;; backend dispatch, and the buffer-local hooks used by vterm/eat
;; terminal sessions.

;;; Code:

(require 'cl-lib)
(require 'subr-x)

;; External declarations shared with the main package.
(defvar eat-terminal)
(defvar eat--synchronize-scroll-function)
(defvar vterm-copy-mode)
(defvar vterm-shell)
(defvar vterm-environment)
(defvar eat-term-name)
(defvar vterm--process)
(defvar claude-code-ide-terminal-backend)
(defvar claude-code-ide-cli-terminal-backends)
(defvar claude-code-ide-vterm-anti-flicker)
(defvar claude-code-ide-vterm-render-delay)
(defvar ghostel-set-title-function)
(defvar ghostel-enable-url-detection)

(declare-function vterm "vterm" (&optional arg))
(declare-function vterm-send-string "vterm" (string &optional paste))
(declare-function vterm-send-key "vterm" (key &optional shift meta ctrl))
(declare-function vterm-send-escape "vterm" ())
(declare-function vterm-send-return "vterm" ())
(declare-function vterm--window-adjust-process-window-size "vterm" (&optional frame))

(declare-function eat-mode "eat" ())
(declare-function eat-exec "eat" (buffer name command startfile &rest switches))
(declare-function eat-term-send-string "eat" (terminal string))
(declare-function eat-term-send-string-as-yank "eat" (terminal string))
(declare-function eat-term-display-cursor "eat" (terminal))
(declare-function eat--adjust-process-window-size "eat" (process windows))
(declare-function eat--filter "eat" (process input))

(declare-function ghostel-mode "ghostel" ())
(declare-function ghostel--send-string "ghostel" (string))
(declare-function ghostel-paste-string "ghostel" (string))
(declare-function ghostel-send-C-c "ghostel" ())

(declare-function claude-code-ide--current-terminal-backend "claude-code-ide" ())
(declare-function claude-code-ide-session-idle-record-activity
                  "claude-code-ide-session-idle" (&optional buffer))

(defgroup claude-code-ide-session nil
  "Session support for Claude Code IDE."
  :group 'claude-code-ide
  :prefix "claude-code-ide-session-")

(defun claude-code-ide-session--default-command-reader (_buffer)
  "Read a command string for the current session buffer."
  (read-string "Claude command: "))

(defun claude-code-ide-session--default-file-reference-reader (_buffer)
  "Read a file reference string for the current session buffer."
  (read-file-name "File reference: " nil nil t))

(defcustom claude-code-ide-session-command-reader-function
  #'claude-code-ide-session--default-command-reader
  "Function used by `claude-code-ide-session-insert-command'.

The function is called with the current session buffer and must
return the string to insert."
  :type 'function
  :group 'claude-code-ide-session)

(defcustom claude-code-ide-session-file-reference-reader-function
  #'claude-code-ide-session--default-file-reference-reader
  "Function used by `claude-code-ide-session-insert-file-reference'.

The function is called with the current session buffer and must
return the string to insert."
  :type 'function
  :group 'claude-code-ide-session)

(defcustom claude-code-ide-session-buffer-predicate-functions
  '(claude-code-ide-session--default-reader)
  "Predicate functions used to recognize Claude Code session buffers."
  :type '(repeat function)
  :group 'claude-code-ide-session)

(defvaralias 'claude-code-ide-session-reader-functions
  'claude-code-ide-session-buffer-predicate-functions)

(defvar claude-code-ide-session-setup-hook nil
  "Hook run after a Claude Code session buffer has been configured.")

(defvar claude-code-ide-session-mode-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "C-c C-c") #'claude-code-ide-session-send-interrupt)
    map)
  "Keymap for `claude-code-ide-session-mode'.")

(defvar-local claude-code-ide-session--configured-p nil
  "Non-nil when the current session buffer has been configured.")

(defvar-local claude-code-ide--saved-cursor-type nil
  "Saved cursor-type before entering vterm-copy-mode.")

(defun claude-code-ide-session--default-reader (buffer)
  "Return non-nil when BUFFER has the standard Claude Code session name."
  (when-let ((name (if (stringp buffer) buffer (buffer-name buffer))))
    (string-prefix-p "*claude-code[" name)))

(defun claude-code-ide-session-buffer-p (buffer)
  "Return non-nil when BUFFER belongs to a Claude Code session."
  (cl-some (lambda (reader)
             (when (functionp reader)
               (funcall reader buffer)))
           claude-code-ide-session-buffer-predicate-functions))

(defalias 'claude-code-ide--session-buffer-p #'claude-code-ide-session-buffer-p)

(defun claude-code-ide-session--current-terminal-backend ()
  "Return the terminal backend for the current session buffer."
  (cond
   ((bound-and-true-p claude-code-ide--terminal-backend)
    claude-code-ide--terminal-backend)
   ((derived-mode-p 'vterm-mode) 'vterm)
   ((derived-mode-p 'eat-mode) 'eat)
   ((derived-mode-p 'ghostel-mode) 'ghostel)
   ((fboundp 'claude-code-ide--current-terminal-backend)
    (claude-code-ide--current-terminal-backend))))

(defun claude-code-ide--terminal-ensure-backend ()
  "Ensure the selected terminal backend is available."
  (let ((backend (claude-code-ide-session--current-terminal-backend)))
    (cond
     ((eq backend 'vterm)
      (unless (featurep 'vterm)
        (require 'vterm nil t))
      (unless (featurep 'vterm)
        (user-error "The package vterm is not installed.  Please install the vterm package or change the terminal backend configuration to 'eat")))
     ((eq backend 'eat)
      (unless (featurep 'eat)
        (require 'eat nil t))
      (unless (featurep 'eat)
        (user-error "The package eat is not installed.  Please install the eat package or change the terminal backend configuration to 'vterm")))
     ((eq backend 'ghostel)
      (unless (featurep 'ghostel)
        (require 'ghostel nil t))
      (unless (featurep 'ghostel)
        (user-error "The package ghostel is not installed.  Please install the ghostel package or change the terminal backend configuration to 'vterm")))
     (t
      (user-error "Invalid terminal backend: %s.  Valid options are 'vterm, 'eat, or 'ghostel" backend)))))

(defun claude-code-ide-session--vterm-copy-mode-hook ()
  "Keep the cursor visible in `vterm-copy-mode'."
  (if vterm-copy-mode
      (progn
        (setq claude-code-ide--saved-cursor-type cursor-type)
        (when (null cursor-type)
          (setq cursor-type t)))
    (setq cursor-type claude-code-ide--saved-cursor-type)))

(defun claude-code-ide-session--configure-vterm-buffer ()
  "Configure vterm for Claude Code session buffers."
  (setq-local vterm-scroll-to-bottom-on-output nil)
  (when (boundp 'vterm--redraw-immididately)
    (setq-local vterm--redraw-immididately nil))
  (when (boundp 'vterm--redraw-immediately)
    (setq-local vterm--redraw-immediately nil))
  (setq-local cursor-in-non-selected-windows nil)
  (setq-local blink-cursor-mode nil)
  (setq-local cursor-type nil)
  (setq-local global-hl-line-mode nil)
  (when (featurep 'hl-line)
    (hl-line-mode -1))
  (face-remap-add-relative 'nobreak-space :inherit 'default)
  (add-hook 'vterm-copy-mode-hook #'claude-code-ide-session--vterm-copy-mode-hook nil t)
  (when-let ((proc (get-buffer-process (current-buffer))))
    (set-process-query-on-exit-flag proc nil)
    (when (fboundp 'process-put)
      (process-put proc 'read-output-max 4096)))
  (when (bound-and-true-p claude-code-ide-vterm-anti-flicker)
    (advice-add 'vterm--filter :around #'claude-code-ide--vterm-smart-renderer)))

(defun claude-code-ide-session--configure-eat-buffer ()
  "Configure eat for Claude Code session buffers."
  (setq-local cursor-in-non-selected-windows nil)
  (setq-local blink-cursor-mode nil)
  (setq-local cursor-type nil)
  (when (featurep 'hl-line)
    (hl-line-mode -1))
  (face-remap-add-relative 'nobreak-space :inherit 'default)
  (when (bound-and-true-p claude-code-ide-vterm-anti-flicker)
    (advice-add 'eat--filter :around #'claude-code-ide--eat-smart-renderer)))

(defun claude-code-ide-session--configure-ghostel-buffer ()
  "Configure ghostel for Claude Code session buffers."
  (setq-local cursor-in-non-selected-windows nil)
  (setq-local blink-cursor-mode nil)
  (setq-local cursor-type nil)
  (setq-local ghostel-set-title-function nil)
  (setq-local ghostel-enable-url-detection nil)
  (when (featurep 'hl-line)
    (hl-line-mode -1))
  (face-remap-add-relative 'nobreak-space :inherit 'default))

(defun claude-code-ide-session-setup-buffer ()
  "Apply package-owned session configuration to the current buffer."
  (when (claude-code-ide-session-buffer-p (current-buffer))
    (unless claude-code-ide-session--configured-p
      (setq claude-code-ide-session--configured-p t)
      (pcase (claude-code-ide-session--current-terminal-backend)
        ('vterm (claude-code-ide-session--configure-vterm-buffer))
        ('eat (claude-code-ide-session--configure-eat-buffer))
        ('ghostel (claude-code-ide-session--configure-ghostel-buffer)))
      (claude-code-ide-session-setup-terminal-keybindings)
      (run-hooks 'claude-code-ide-session-setup-hook))))

(define-minor-mode claude-code-ide-session-mode
  "Minor mode for Claude Code session buffers."
  :lighter " CC-Session"
  :keymap claude-code-ide-session-mode-map
  (if claude-code-ide-session-mode
      (claude-code-ide-session-setup-buffer)
    (setq claude-code-ide-session--configured-p nil)))

(defun claude-code-ide--maybe-enable-session-mode ()
  "Enable session mode in the current buffer when it is package-owned."
  (when (claude-code-ide-session-buffer-p (current-buffer))
    (claude-code-ide-session-mode 1)))

(defalias 'claude-code-ide-session--maybe-enable
  #'claude-code-ide--maybe-enable-session-mode)

(defun claude-code-ide-session--ensure-session-buffer ()
  "Signal a user error unless the current buffer is a session buffer."
  (unless (claude-code-ide-session-buffer-p (current-buffer))
    (user-error "This command only applies to Claude Code session buffers")))

(defun claude-code-ide-session--read-command ()
  "Read a command string for the current session buffer."
  (funcall claude-code-ide-session-command-reader-function
           (current-buffer)))

(defun claude-code-ide-session--read-file-reference ()
  "Read a file reference string for the current session buffer."
  (funcall claude-code-ide-session-file-reference-reader-function
           (current-buffer)))

(defun claude-code-ide-session--record-activity ()
  "Record shared idle activity after a package-owned input action."
  (when (claude-code-ide-session-buffer-p (current-buffer))
    (claude-code-ide-session-idle-record-activity)))

(defun claude-code-ide-session-insert-command (&optional command)
  "Insert COMMAND into the current Claude Code session buffer.

When COMMAND is nil, use
`claude-code-ide-session-command-reader-function'."
  (interactive)
  (claude-code-ide-session--ensure-session-buffer)
  (let ((text (or command (claude-code-ide-session--read-command))))
    (unless (string-empty-p text)
      (claude-code-ide-session-send-string text t))))

(defun claude-code-ide-session-insert-file-reference (&optional reference)
  "Insert REFERENCE into the current Claude Code session buffer.

When REFERENCE is nil, use
`claude-code-ide-session-file-reference-reader-function'."
  (interactive)
  (claude-code-ide-session--ensure-session-buffer)
  (let ((text (or reference (claude-code-ide-session--read-file-reference))))
    (unless (string-empty-p text)
      (claude-code-ide-session-send-string text t))))

(defun claude-code-ide-session-send-string (string &optional paste)
  "Send STRING to the terminal in the current session buffer."
  (prog1
      (pcase (claude-code-ide-session--current-terminal-backend)
        ('vterm
         (vterm-send-string string paste))
        ('eat
         (when eat-terminal
           (if paste
               (eat-term-send-string-as-yank eat-terminal string)
             (eat-term-send-string eat-terminal string))))
        ('ghostel
         (if paste
             (ghostel-paste-string string)
           (ghostel--send-string string)))
        (_
         (error "Unknown terminal backend: %s"
                (claude-code-ide-session--current-terminal-backend))))
    (claude-code-ide-session--record-activity)))

(defun claude-code-ide-session-send-escape ()
  "Send escape key to the terminal in the current session buffer."
  (prog1
      (pcase (claude-code-ide-session--current-terminal-backend)
        ('vterm
         (vterm-send-escape))
        ('eat
         (when eat-terminal
           (eat-term-send-string eat-terminal "\e")))
        ('ghostel
         (ghostel--send-string "\e"))
        (_
         (error "Unknown terminal backend: %s"
                (claude-code-ide-session--current-terminal-backend))))
    (claude-code-ide-session--record-activity)))

(defun claude-code-ide-session-send-return ()
  "Send return key to the terminal in the current session buffer."
  (prog1
      (pcase (claude-code-ide-session--current-terminal-backend)
        ('vterm
         (vterm-send-return))
        ('eat
         (when eat-terminal
           (eat-term-send-string eat-terminal "\r")))
        ('ghostel
         (ghostel--send-string "\r"))
        (_
         (error "Unknown terminal backend: %s"
                (claude-code-ide-session--current-terminal-backend))))
    (claude-code-ide-session--record-activity)))

(defun claude-code-ide-session-send-interrupt ()
  "Send an interrupt to the terminal in the current session buffer."
  (interactive)
  (claude-code-ide-session--ensure-session-buffer)
  (prog1
      (pcase (claude-code-ide-session--current-terminal-backend)
        ('vterm
         (vterm-send-key "c" nil nil t))
        ('eat
         (when eat-terminal
           (eat-term-send-string eat-terminal "\003")))
        ('ghostel
         (ghostel-send-C-c))
        (_
         (error "Unknown terminal backend: %s"
                (claude-code-ide-session--current-terminal-backend))))
    (claude-code-ide-session--record-activity)))

(defun claude-code-ide-session-setup-terminal-keybindings ()
  "Set up package-owned keybindings for the current session buffer."
  (pcase (claude-code-ide-session--current-terminal-backend)
    ('vterm
     (local-set-key (kbd "S-<return>") #'claude-code-ide-insert-newline)
     (local-set-key (kbd "C-<escape>") #'claude-code-ide-send-escape))
    ('eat
     (local-set-key (kbd "S-<return>") #'claude-code-ide-insert-newline)
     (local-set-key (kbd "C-<escape>") #'claude-code-ide-send-escape))
    ('ghostel
     (local-set-key (kbd "S-<return>") #'claude-code-ide-insert-newline)
     (local-set-key (kbd "C-<escape>") #'claude-code-ide-send-escape))
    (_
     (error "Unknown terminal backend: %s"
            (claude-code-ide-session--current-terminal-backend)))))

(defalias 'claude-code-ide--configure-vterm-buffer
  #'claude-code-ide-session--configure-vterm-buffer)
(defalias 'claude-code-ide--configure-eat-buffer
  #'claude-code-ide-session--configure-eat-buffer)
(defalias 'claude-code-ide--configure-ghostel-buffer
  #'claude-code-ide-session--configure-ghostel-buffer)
(defalias 'claude-code-ide--terminal-send-string
  #'claude-code-ide-session-send-string)
(defalias 'claude-code-ide--terminal-send-escape
  #'claude-code-ide-session-send-escape)
(defalias 'claude-code-ide--terminal-send-return
  #'claude-code-ide-session-send-return)
(defalias 'claude-code-ide--setup-terminal-keybindings
  #'claude-code-ide-session-setup-terminal-keybindings)

(defun claude-code-ide-session--install-hook-wiring ()
  "Install package-owned hooks for supported session backends."
  (with-eval-after-load 'vterm
    (add-hook 'vterm-mode-hook #'claude-code-ide--maybe-enable-session-mode))
  (with-eval-after-load 'eat
    (add-hook 'eat-mode-hook #'claude-code-ide--maybe-enable-session-mode))
  (with-eval-after-load 'ghostel
    (add-hook 'ghostel-mode-hook #'claude-code-ide--maybe-enable-session-mode)))

(claude-code-ide-session--install-hook-wiring)

(require 'claude-code-ide-session-idle)

(provide 'claude-code-ide-session)

;;; claude-code-ide-session.el ends here
