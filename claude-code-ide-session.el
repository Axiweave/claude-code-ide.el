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
;; This module owns the Session minor mode, Session buffer detection,
;; Ghostel input, and buffer-local Session hooks.

;;; Code:

(require 'cl-lib)
(require 'subr-x)

;; External declarations shared with the main package.
(defvar ghostel-enable-url-detection)
(defvar ghostel--process)
(defvar ghostel-mode-hook)
(defvar ghostel-module-auto-install)


(declare-function ghostel-mode "ghostel" ())
(declare-function ghostel-create "ghostel" (&optional name display identity))
(declare-function ghostel--send-string "ghostel" (string))
(declare-function ghostel-paste-string "ghostel" (string))
(declare-function ghostel-send-C-c "ghostel" ())
(declare-function ghostel-send-C-g "ghostel" ())
(declare-function ghostel-yank "ghostel" ())

(declare-function claude-code-ide--current-cli-type "claude-code-ide" ())
(declare-function claude-code-ide-session-idle-record-activity
                  "claude-code-ide-session-idle" (&optional buffer))
(declare-function claude-code-ide--touch-session-for-buffer
                  "claude-code-ide" (&optional buffer))
(declare-function claude-code-ide--format-insertion "claude-code-ide" (body))

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

(defvar claude-code-ide-session-setup-hook nil
  "Hook run after a Claude Code session buffer has been configured.")

(defvar claude-code-ide-session-mode-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "C-c C-c") #'claude-code-ide-session-send-interrupt)
    (define-key map (kbd "s-v") #'claude-code-ide-session-paste-clipboard)
    (define-key map (kbd "H-v") #'claude-code-ide-session-paste-clipboard)
    map)
  "Keymap for `claude-code-ide-session-mode'.")

(defvar claude-code-ide-session--emulation-mode-map-alist
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "s-v") #'claude-code-ide-session-paste-clipboard)
    (define-key map (kbd "H-v") #'claude-code-ide-session-paste-clipboard)
    `((claude-code-ide-session-mode . ,map)))
  "Emulation map that gives session paste keys precedence over terminal maps.")

(defvar-local claude-code-ide-session--configured-p nil
  "Non-nil when the current session buffer has been configured.")


(defun claude-code-ide-session--default-reader (buffer)
  "Return non-nil when BUFFER has the standard Claude Code session name."
  (when-let* ((name (if (stringp buffer) buffer (buffer-name buffer))))
    (string-prefix-p "*claude-code[" name)))

(defun claude-code-ide-session-buffer-p (buffer)
  "Return non-nil when BUFFER belongs to a Claude Code session."
  (cl-some (lambda (reader)
             (when (functionp reader)
               (funcall reader buffer)))
           claude-code-ide-session-buffer-predicate-functions))

(defalias 'claude-code-ide--session-buffer-p #'claude-code-ide-session-buffer-p)


(defun claude-code-ide-session--ensure-ghostel ()
  "Check Ghostel and its native support without installing software."
  (let ((ghostel-module-auto-install nil))
    (unless (condition-case err
                (require 'ghostel nil t)
              (error
               (user-error "Cannot load Ghostel: %s. Check its installation"
                           (error-message-string err))))
      (user-error "Install Ghostel before starting a terminal"))
    (unless (fboundp 'ghostel--new)
      (user-error "Ghostel native support is unavailable. Install its native module before starting a terminal"))))

(defun claude-code-ide-session--ensure-ghostel-buffer ()
  "Reject terminal operations outside actual Ghostel mode."
  (unless (derived-mode-p 'ghostel-mode)
    (user-error "This command needs a Ghostel terminal. After an upgrade, restart Emacs and open a new Session")))

(defun claude-code-ide-session--live-ghostel-process-p (buffer process)
  "Return non-nil when PROCESS is BUFFER's own live Ghostel process."
  (and (buffer-live-p buffer)
       (with-current-buffer buffer (derived-mode-p 'ghostel-mode))
       (processp process)
       (process-live-p process)
       (eq (process-buffer process) buffer)))

(defun claude-code-ide-session--companion-shell-live-p (buffer)
  "Return non-nil when BUFFER has its own live Ghostel process."
  (and (buffer-live-p buffer)
       (local-variable-p 'ghostel--process buffer)
       (claude-code-ide-session--live-ghostel-process-p
        buffer (buffer-local-value 'ghostel--process buffer))))

(defun claude-code-ide-session--create-companion-shell (directory name)
  "Start an ordinary Ghostel shell in DIRECTORY with a unique NAME."
  (unless (and (stringp directory)
               (file-name-absolute-p directory)
               (file-accessible-directory-p directory))
    (user-error "Session directory is not accessible: %s" directory))
  (let ((ghostel-module-auto-install nil))
    (claude-code-ide-session--ensure-ghostel)
    (let* ((default-directory (file-name-as-directory directory))
           buffer
           (ghostel-mode-hook
            (cons (lambda () (unless buffer (setq buffer (current-buffer))))
                  ghostel-mode-hook)))
      (condition-case err
          (let ((created (ghostel-create (generate-new-buffer-name name) nil)))
            (unless (claude-code-ide-session--companion-shell-live-p created)
              (user-error "Ghostel did not start a live shell"))
            created)
        ((error quit)
         (when (buffer-live-p buffer)
           (if (process-live-p (get-buffer-process buffer))
               (message "Shell startup stopped. The live shell remains in %s" (buffer-name buffer))
             (kill-buffer buffer)))
         (signal (car err) (cdr err)))))))


(defun claude-code-ide-session--configure-ghostel-buffer ()
  "Configure ghostel for Claude Code session buffers."
  (claude-code-ide-session--ensure-ghostel-buffer)
  (setq-local cursor-in-non-selected-windows nil)
  (setq-local blink-cursor-mode nil)
  (setq-local cursor-type nil)
  (setq-local ghostel-enable-url-detection nil)
  (when (featurep 'hl-line)
    (hl-line-mode -1))
  (face-remap-add-relative 'nobreak-space :inherit 'default))

(defun claude-code-ide-session-setup-buffer ()
  "Apply package-owned session configuration to the current buffer."
  (when (and (derived-mode-p 'ghostel-mode)
             (claude-code-ide-session-buffer-p (current-buffer)))
    (unless claude-code-ide-session--configured-p
      (setq claude-code-ide-session--configured-p t)
      (claude-code-ide-session--configure-ghostel-buffer)
      (claude-code-ide-session-setup-terminal-keybindings)
      (run-hooks 'claude-code-ide-session-setup-hook))))

(define-minor-mode claude-code-ide-session-mode
  "Minor mode for Claude Code session buffers."
  :lighter " CC-Session"
  :keymap claude-code-ide-session-mode-map
  (when (and claude-code-ide-session-mode
             (not (derived-mode-p 'ghostel-mode)))
    (setq claude-code-ide-session-mode nil)
    (claude-code-ide-session--ensure-ghostel-buffer))
  (if claude-code-ide-session-mode
      (progn
        (unless (memq 'claude-code-ide-session--emulation-mode-map-alist
                      emulation-mode-map-alists)
          (setq-local emulation-mode-map-alists
                      (cons 'claude-code-ide-session--emulation-mode-map-alist
                            emulation-mode-map-alists)))
        (claude-code-ide-session-setup-buffer)
        (add-hook 'post-command-hook
                  #'claude-code-ide-session--touch-current-session nil t))
    (remove-hook 'post-command-hook
                 #'claude-code-ide-session--touch-current-session t)
    (setq-local emulation-mode-map-alists
                (delq 'claude-code-ide-session--emulation-mode-map-alist
                      emulation-mode-map-alists))
    (setq claude-code-ide-session--configured-p nil)))

(defun claude-code-ide--maybe-enable-session-mode ()
  "Enable session mode in the current buffer when it is package-owned."
  (when (and (derived-mode-p 'ghostel-mode)
             (claude-code-ide-session-buffer-p (current-buffer)))
    (claude-code-ide-session-mode 1)))

(defalias 'claude-code-ide-session--maybe-enable
  #'claude-code-ide--maybe-enable-session-mode)

(defun claude-code-ide-session--ensure-session-buffer ()
  "Signal an error unless this is a Ghostel Session buffer."
  (claude-code-ide-session--ensure-ghostel-buffer)
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

(defun claude-code-ide-session--touch-current-session ()
  "Make the current terminal's exact live session preferred."
  (when (claude-code-ide-session-buffer-p (current-buffer))
    (when (fboundp 'claude-code-ide--touch-session-for-buffer)
      (claude-code-ide--touch-session-for-buffer (current-buffer)))))

(defun claude-code-ide-session--record-activity ()
  "Record shared idle activity after a package-owned input action."
  (when (claude-code-ide-session-buffer-p (current-buffer))
    (claude-code-ide-session--touch-current-session)
    (claude-code-ide-session-idle-record-activity)))

(defun claude-code-ide-session-send-omp-packet (kind value)
  "Send an Oh My Pi `pi:KIND;VALUE' APC packet to the current session buffer.

KIND is \"prompt\" (set the leading slash command) or \"keyword\"
(insert a standalone magic keyword at the cursor)."
  (claude-code-ide-session-send-string
   (concat "\e_pi:" kind ";" value "\e\\")))

(defun claude-code-ide-session-insert-command (&optional command in-place)
  "Insert COMMAND into the current Claude Code session buffer.

When COMMAND is nil, use
`claude-code-ide-session-command-reader-function'.  For Oh My Pi, a
bare `/name' sets the prompt's slash command and a bare word inserts
a magic keyword, both through `pi:' APC packets instead of a paste.

With IN-PLACE non-nil, interactively a prefix argument, paste COMMAND
at the cursor instead.  The paste keeps a leading space unless the
cursor already follows whitespace, and always adds a trailing space."
  (interactive (list nil current-prefix-arg))
  (claude-code-ide-session--ensure-session-buffer)
  (let ((text (or command (claude-code-ide-session--read-command))))
    (unless (string-empty-p text)
      (cond
       (in-place
        (claude-code-ide-session-send-string
         (claude-code-ide--format-insertion (string-trim text)) t))
       ((not (eq (claude-code-ide--current-cli-type) 'omp))
        (claude-code-ide-session-send-string text t))
       ((string-match "\\`/\\([^[:space:]/[:cntrl:]]+\\)[[:space:]]*\\'" text)
        (claude-code-ide-session-send-omp-packet "prompt" (match-string 1 text)))
       ((string-match "\\`\\([^[:space:]/[:cntrl:]]+\\)[[:space:]]*\\'" text)
        (claude-code-ide-session-send-omp-packet "keyword" (match-string 1 text)))
       (t
        (claude-code-ide-session-send-string text t))))))

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
  "Send STRING to the current Ghostel terminal.
Use paste input when PASTE is non-nil."
  (claude-code-ide-session--ensure-ghostel-buffer)
  (prog1
      (if paste
          (ghostel-paste-string string)
        (ghostel--send-string string))
    (claude-code-ide-session--record-activity)))

(defun claude-code-ide-session--clipboard-image-p ()
  "Return non-nil when the GUI clipboard advertises an image target."
  (condition-case nil
      (let ((targets (gui-get-selection 'CLIPBOARD 'TARGETS)))
        (and (or (listp targets) (vectorp targets))
             (cl-some
              (lambda (target)
                (when (symbolp target)
                  (setq target (symbol-name target)))
                (and (stringp target)
                     (let ((name (downcase target)))
                       (or (string-prefix-p "image/" name)
                           (member name '("png" "jpeg" "jpg" "gif" "tiff"
                                          "webp" "bmp" "public.png"
                                          "public.jpeg" "public.jpg"
                                          "public.gif" "public.tiff"
                                          "public.webp" "public.bmp"
                                          "bitmap" "dib" "dibv5"))))))
              targets)))
    (error nil)))

(defun claude-code-ide-session-paste-clipboard ()
  "Paste from the clipboard, forwarding images to Claude, Codex, and Oh My Pi."
  (interactive)
  (claude-code-ide-session--ensure-ghostel-buffer)
  (if (and (claude-code-ide-session--clipboard-image-p)
           (memq (claude-code-ide--current-cli-type) '(claude codex omp)))
      (claude-code-ide-session-send-string "\026")
    (ghostel-yank)))

(defun claude-code-ide-session-send-escape ()
  "Send Escape to the terminal in the current Session buffer."
  (claude-code-ide-session-send-string "\e"))

(defun claude-code-ide-session-send-return ()
  "Send Return to the terminal in the current Session buffer."
  (claude-code-ide-session-send-string "\r"))

(defun claude-code-ide-session-send-interrupt ()
  "Send an interrupt to the terminal in the current Session buffer."
  (interactive)
  (claude-code-ide-session--ensure-session-buffer)
  (prog1 (ghostel-send-C-c)
    (claude-code-ide-session--record-activity)))

(defun claude-code-ide-session-send-control-g ()
  "Send C-g to the terminal in the current Session buffer."
  (interactive)
  (claude-code-ide-session--ensure-session-buffer)
  (prog1 (ghostel-send-C-g)
    (claude-code-ide-session--record-activity)))

(defun claude-code-ide-session-setup-terminal-keybindings ()
  "Set up package-owned keybindings for the current Session buffer."
  (claude-code-ide-session--ensure-ghostel-buffer)
  (local-set-key (kbd "S-<return>") #'claude-code-ide-insert-newline)
  (local-set-key (kbd "C-<escape>") #'claude-code-ide-send-escape))

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
  "Install Ghostel Session hooks."
  (with-eval-after-load 'ghostel
    (add-hook 'ghostel-mode-hook #'claude-code-ide--maybe-enable-session-mode)))

(claude-code-ide-session--install-hook-wiring)

(require 'claude-code-ide-session-idle)

(provide 'claude-code-ide-session)

;;; claude-code-ide-session.el ends here
