;;; claude-code-ide.el --- Claude Code integration for Emacs  -*- lexical-binding: t; -*-

;; Copyright (C) 2025

;; Author: Yoav Orot
;; Version: 0.2.6
;; Package-Requires: ((emacs "28.1") (websocket "1.12") (transient "0.9.0") (web-server "0.1.2"))
;; Keywords: ai, claude, code, assistant, mcp, websocket
;; URL: https://github.com/manzaltu/claude-code-ide.el

;; This file is not part of GNU Emacs.

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

;; Claude Code IDE integration for Emacs provides seamless integration
;; with Claude Code CLI through the Model Context Protocol (MCP).
;; It supports file operations, diagnostics, and editor state management.
;;
;; This package starts a WebSocket server that Claude Code CLI connects to,
;; enabling real-time communication between Emacs and Claude.  It supports
;; multiple concurrent sessions per project.
;;
;; Features:
;; - Automatic IDE mode activation when starting Claude
;; - MCP WebSocket server for bidirectional communication
;; - Project-aware sessions with automatic working directory detection
;; - Clean session management with automatic cleanup on exit
;; - Selection and buffer state tracking
;; - Tool support for file operations, diagnostics, and more
;; - Emacs MCP tools for xref and project navigation
;;
;; Usage:
;; M-x claude-code-ide - Start Claude Code for current project
;; M-x claude-code-ide-continue - Continue most recent conversation in directory
;; M-x claude-code-ide-resume - Resume Claude Code with previous conversation
;; M-x claude-code-ide-stop - Stop Claude Code for current project
;; M-x claude-code-ide-switch-to-buffer - Switch to project's Claude buffer
;; M-x claude-code-ide-list-sessions - List and switch between all sessions
;; M-x claude-code-ide-check-status - Check CLI availability and version
;; M-x claude-code-ide-insert-at-mentioned - Send selected text to Claude
;;
;; Emacs MCP Tools:
;; To enable Emacs tools for Claude, add to your config:
;;   (claude-code-ide-emacs-tools-setup)

;;; Code:

(require 'cl-lib)
(require 'project)
(require 'subr-x)
(require 'which-func)
(require 'claude-code-ide-debug)
(require 'claude-code-ide-mcp)
(require 'claude-code-ide-transient)
(require 'claude-code-ide-mcp-server)
(require 'claude-code-ide-emacs-tools)

;; External variable declarations
(defvar eat-terminal)
(defvar eat--synchronize-scroll-function)
(defvar vterm-shell)
(defvar vterm-environment)
(defvar eat-term-name)
(defvar vterm--process)

;; External function declarations for vterm
(declare-function vterm "vterm" (&optional arg))
(declare-function vterm-send-string "vterm" (string))
(declare-function vterm-send-escape "vterm" ())
(declare-function vterm-send-return "vterm" ())
(declare-function vterm--window-adjust-process-window-size "vterm" (&optional frame))

;; External function declarations for eat
(declare-function eat-mode "eat" ())
(declare-function eat-exec "eat" (buffer name command startfile &rest switches))
(declare-function eat-term-send-string "eat" (terminal string))
(declare-function eat-term-display-cursor "eat" (terminal))
(declare-function eat--adjust-process-window-size "eat" (process windows))
(declare-function eat--filter "eat" (process input))

;;; Customization

(defgroup claude-code-ide nil
  "Claude Code integration for Emacs."
  :group 'tools
  :prefix "claude-code-ide-")

(defcustom claude-code-ide-cli-path "claude"
  "Path to the Claude Code CLI executable."
  :type 'string
  :group 'claude-code-ide)

(defcustom claude-code-ide-buffer-name-function #'claude-code-ide--default-buffer-name
  "Function to generate buffer names for Claude Code sessions.
The function is called with one argument, the working directory,
and should return a string to use as the buffer name."
  :type 'function
  :group 'claude-code-ide)

(defcustom claude-code-ide-cli-debug nil
  "When non-nil, launch Claude Code with the -d debug flag."
  :type 'boolean
  :group 'claude-code-ide)

(defcustom claude-code-ide-cli-extra-flags ""
  "Additional flags to pass to the Claude Code CLI.
This should be a string of space-separated flags, e.g. \"--model opus\"."
  :type 'string
  :group 'claude-code-ide)

(defcustom claude-code-ide-system-prompt nil
  "System prompt to append to Claude's default system prompt.
When non-nil, the --append-system-prompt flag will be added with this value.
Set to nil to disable (default)."
  :type '(choice (const :tag "Disabled" nil)
                 (string :tag "System prompt text"))
  :group 'claude-code-ide)

(defcustom claude-code-ide-mcp-allowed-tools 'auto
  "Configuration for allowed MCP tools when MCP server is enabled.
Can be one of:
  'auto - Automatically allow all configured emacs-tools (default)
  nil - Disable the --allowedTools flag
  A string - Custom pattern/tools passed directly to --allowedTools
  A list of strings - List of specific tool names to allow"
  :type '(choice (const :tag "Auto (all emacs-tools)" auto)
                 (const :tag "Disabled" nil)
                 (string :tag "Custom pattern")
                 (repeat :tag "Specific tools" string))
  :group 'claude-code-ide)

(defcustom claude-code-ide-window-side 'right
  "Side of the frame where the Claude Code window should appear.
Can be `'left', `'right', `'top', or `'bottom'."
  :type '(choice (const :tag "Left" left)
                 (const :tag "Right" right)
                 (const :tag "Top" top)
                 (const :tag "Bottom" bottom))
  :group 'claude-code-ide)

(defcustom claude-code-ide-window-width 90
  "Width of the Claude Code side window when opened on left or right."
  :type 'integer
  :group 'claude-code-ide)

(defcustom claude-code-ide-window-height 20
  "Height of the Claude Code side window when opened on top or bottom."
  :type 'integer
  :group 'claude-code-ide)

(defcustom claude-code-ide-focus-on-open t
  "Whether to focus the Claude Code window when it opens."
  :type 'boolean
  :group 'claude-code-ide)

(defcustom claude-code-ide-focus-claude-after-ediff t
  "Whether to focus the Claude Code window after opening ediff.
When non-nil (default), focus returns to the Claude Code window
after opening ediff.  When nil, focus remains on the ediff control
window, allowing direct interaction with the diff controls."
  :type 'boolean
  :group 'claude-code-ide)

(defcustom claude-code-ide-show-claude-window-in-ediff t
  "Whether to show the Claude Code side window when viewing diffs.
When non-nil (default), the Claude Code side window is restored
after opening ediff.  When nil, the Claude Code window remains
hidden during diff viewing, giving you more screen space for the
diff comparison."
  :type 'boolean
  :group 'claude-code-ide)

(defcustom claude-code-ide-use-ide-diff t
  "Whether to use IDE diff viewer for file differences.
When non-nil (default), Claude Code will open an IDE diff viewer
(ediff) when showing file changes.  When nil, Claude Code will
display diffs in the terminal instead."
  :type 'boolean
  :group 'claude-code-ide)

(defcustom claude-code-ide-switch-tab-on-ediff t
  "Whether to switch back to Claude's original tab when opening ediff.
When non-nil (default), Claude Code will switch back to the tab
where Claude Code was started when opening an ediff session.
When nil, the current tab remains active when ediff is opened."
  :type 'boolean
  :group 'claude-code-ide)

(defcustom claude-code-ide-use-side-window t
  "Whether to display Claude Code in a side window.
When non-nil (default), Claude Code opens in a dedicated side window
controlled by `claude-code-ide-window-side' and related settings.
When nil, Claude Code opens in a regular buffer that follows standard
display-buffer behavior."
  :type 'boolean
  :group 'claude-code-ide)

(defcustom claude-code-ide-terminal-backend 'vterm
  "Terminal backend to use for Claude Code sessions.
Can be either `vterm' or `eat'.  The vterm backend is the default
and provides a fully-featured terminal emulator.  The eat backend
is an alternative terminal emulator that may work better in some
environments."
  :type '(choice (const :tag "vterm" vterm)
                 (const :tag "eat" eat))
  :group 'claude-code-ide)

(defcustom claude-code-ide-prevent-reflow-glitch t
  "Workaround for Claude Code terminal scrolling bug #1422.
When non-nil (default), prevents the terminal from reflowing on height-only
changes which can trigger uncontrollable scrolling in Claude Code.
See: https://github.com/anthropics/claude-code/issues/1422
This setting should be removed once the upstream bug is fixed."
  :type 'boolean
  :group 'claude-code-ide)

(defcustom claude-code-ide-vterm-anti-flicker t
  "Enable intelligent flicker reduction for vterm display.
When enabled, this feature optimizes terminal rendering by detecting
and batching rapid update sequences.  This provides smoother visual
output during complex terminal operations such as expanding text areas
and rapid screen updates.

This optimization applies only to vterm and uses advanced pattern
matching to maintain responsiveness while improving visual quality."
  :type 'boolean
  :group 'claude-code-ide)

(defcustom claude-code-ide-vterm-render-delay 0.005
  "Rendering optimization delay for batched terminal updates.
This parameter defines the collection window for related terminal
update sequences when anti-flicker mode is active.  The timing
balances visual smoothness with interaction responsiveness.

The 0.005 second (5ms) default delivers optimal rendering quality
with imperceptible latency."
  :type 'number
  :group 'claude-code-ide)

(defcustom claude-code-ide-terminal-initialization-delay 0.1
  "Initialization delay for terminal stability.
Provides a brief stabilization period when launching terminals
to ensure proper layout calculation and rendering.

The delay allows terminals to complete initial dimension calculations,
preventing display artifacts like prompt misalignment and cursor
positioning errors.  The 100ms default ensures reliable initialization
without noticeable latency."
  :type 'number
  :group 'claude-code-ide)

(defcustom claude-code-ide-eat-preserve-position t
  "Maintain terminal scroll position when switching windows.
When enabled, prevents the eat terminal from jumping to the top
when you switch focus to other windows and return.  This provides
a more stable viewing experience when working with multiple windows."
  :type 'boolean
  :group 'claude-code-ide)

(defcustom claude-code-ide-prompt-buffer-patterns
  '("claude-prompt.*\\.md\\'" "\\.claude/plans/.*\\.md\\'")
  "List of regexps to identify Claude prompt and plan buffers.
Each regexp is matched against `buffer-file-name'.  Used by
`claude-code-ide--find-prompt-buffer' to locate a visible
prompt or plan editing buffer."
  :type '(repeat regexp)
  :group 'claude-code-ide)

(defcustom claude-code-ide-switch-after-send nil
  "Whether to switch to the target buffer after sending content.
When non-nil, send commands will select the window of the buffer
that received the text.  For commands that send to a prompt buffer,
the prompt buffer window is selected.  For commands that send to
the terminal, the terminal window is selected.  Only switches if
the target window is already visible."
  :type 'boolean
  :group 'claude-code-ide)

(define-obsolete-variable-alias
  'claude-code-ide-eat-initialization-delay
  'claude-code-ide-terminal-initialization-delay
  "0.2.6")

;;; Constants

(defconst claude-code-ide--active-editor-notification-delay 0.1
  "Delay in seconds before sending active editor notification after connection.")

;;; Variables

(defvar claude-code-ide--cli-available nil
  "Whether Claude Code CLI is available and detected.")

(defvar claude-code-ide--processes (make-hash-table :test 'equal)
  "Hash table mapping project/directory roots to their Claude Code processes.")

(defvar claude-code-ide--session-ids (make-hash-table :test 'equal)
  "Hash table mapping project/directory roots to their session IDs.")

(defvar claude-code-ide--last-accessed-buffer nil
  "The most recently accessed Claude Code buffer.")

;;; Vterm Rendering Optimization

(defvar-local claude-code-ide--vterm-render-queue nil
  "List of pending terminal output strings awaiting batched rendering.
Stored in reverse order for O(1) push, joined at flush time.")

(defvar-local claude-code-ide--vterm-render-timer nil
  "Timer for executing queued rendering operations.")

(defvar-local claude-code-ide--eat-render-queue nil
  "List of pending eat output strings awaiting batched rendering.
Stored in reverse order for O(1) push, joined at flush time.")

(defvar-local claude-code-ide--eat-render-timer nil
  "Timer for executing queued eat rendering operations.")

(defun claude-code-ide--count-escape-sequence (sequence input)
  "Count occurrences of escape SEQUENCE in INPUT.
More efficient than split-string + cl-count-if for simple counting."
  (let ((count 0) (start 0))
    (while (setq start (string-search sequence input start))
      (cl-incf count)
      (cl-incf start (length sequence)))
    count))

(defun claude-code-ide--vterm-smart-renderer (orig-fun process input)
  "Smart rendering filter for optimized vterm display updates.
This advanced filter analyzes terminal output patterns to identify
rapid update sequences that benefit from batched processing.
It significantly improves visual quality during complex operations.

ORIG-FUN is the underlying filter to enhance.
PROCESS is the terminal process being optimized.
INPUT contains the terminal output stream."
  (if (or (not claude-code-ide-vterm-anti-flicker)
          (not (claude-code-ide--session-buffer-p (process-buffer process))))
      ;; Feature disabled or not a Claude buffer, pass through normally
      (funcall orig-fun process input)
    (with-current-buffer (process-buffer process)
      ;; Fast path: plain text with no active queue skips all pattern detection
      ;; This optimizes the common case of typing in the prompt
      (if (and (not claude-code-ide--vterm-render-queue)
               (not (string-search "\033" input)))
          (funcall orig-fun process input)
        ;; Detect rapid terminal redraw sequences
        ;; Pattern analysis for complex terminal updates:
        ;; - Vertical cursor movements (ESC[<n>A)
        ;; - Line clearing operations (ESC[K)
        ;; - High escape sequence density
        (let* ((complex-redraw-detected
                ;; Pattern: vertical movement + clear, repeated
                (string-match-p "\033\\[[0-9]*A.*\033\\[K.*\033\\[[0-9]*A.*\033\\[K" input))
               (clear-count (claude-code-ide--count-escape-sequence "\033[K" input))
               (escape-count (cl-count ?\033 input))
               (input-length (length input))
               ;; High escape density indicates redrawing, not normal output
               (escape-density (if (> input-length 0)
                                   (/ (float escape-count) input-length)
                                 0)))
          ;; Optimize rendering for detected patterns:
          ;; 1. Complex redraw sequence detected, OR
          ;; 2. Escape sequence density exceeds threshold with line operations
          ;; 3. OR already queuing (to complete the sequence)
          (if (or complex-redraw-detected
                  (and (> escape-density 0.3)
                       (>= clear-count 2))
                  claude-code-ide--vterm-render-queue)
              (progn
                ;; Add to queue (list for O(1) push, joined at flush time)
                (push input claude-code-ide--vterm-render-queue)
                ;; Reset existing render timer
                (when claude-code-ide--vterm-render-timer
                  (cancel-timer claude-code-ide--vterm-render-timer))
                ;; Schedule optimized rendering
                ;; Timing calibrated for visual quality
                (setq claude-code-ide--vterm-render-timer
                      (run-at-time claude-code-ide-vterm-render-delay nil
                                   (lambda (buf)
                                     (when (buffer-live-p buf)
                                       (with-current-buffer buf
                                         (when claude-code-ide--vterm-render-queue
                                           (let* ((inhibit-redisplay t)
                                                  (queue claude-code-ide--vterm-render-queue)
                                                  ;; Join list in correct order
                                                  (data (apply #'concat (nreverse queue))))
                                             ;; Clear queue first to prevent recursion
                                             (setq claude-code-ide--vterm-render-queue nil
                                                   claude-code-ide--vterm-render-timer nil)
                                             ;; Execute queued rendering
                                             (funcall orig-fun
                                                      (get-buffer-process buf)
                                                      data))))))
                                   (current-buffer))))
            ;; Standard processing for regular output
            (funcall orig-fun process input)))))))

(defun claude-code-ide--eat-smart-renderer (orig-fun process input)
  "Smart rendering filter for optimized eat display updates.
ORIG-FUN is the underlying filter to enhance.
PROCESS is the terminal process being optimized.
INPUT contains the terminal output stream."
  (if (or (not claude-code-ide-vterm-anti-flicker)
          (not (claude-code-ide--session-buffer-p (process-buffer process))))
      (funcall orig-fun process input)
    (with-current-buffer (process-buffer process)
      (if (and (not claude-code-ide--eat-render-queue)
               (not (string-search "\033" input)))
          (funcall orig-fun process input)
        (let* ((complex-redraw-detected
                (string-match-p "\033\\[[0-9]*A.*\033\\[K.*\033\\[[0-9]*A.*\033\\[K" input))
               (clear-count (claude-code-ide--count-escape-sequence "\033[K" input))
               (escape-count (cl-count ?\033 input))
               (input-length (length input))
               (escape-density (if (> input-length 0)
                                   (/ (float escape-count) input-length)
                                 0)))
          (if (or complex-redraw-detected
                  (and (> escape-density 0.3)
                       (>= clear-count 2))
                  claude-code-ide--eat-render-queue)
              (progn
                (push input claude-code-ide--eat-render-queue)
                (when claude-code-ide--eat-render-timer
                  (cancel-timer claude-code-ide--eat-render-timer))
                (setq claude-code-ide--eat-render-timer
                      (run-at-time claude-code-ide-vterm-render-delay nil
                                   (lambda (buf)
                                     (when (buffer-live-p buf)
                                       (with-current-buffer buf
                                         (when claude-code-ide--eat-render-queue
                                           (let* ((inhibit-redisplay t)
                                                  (queue claude-code-ide--eat-render-queue)
                                                  (data (apply #'concat (nreverse queue))))
                                             (setq claude-code-ide--eat-render-queue nil
                                                   claude-code-ide--eat-render-timer nil)
                                             (funcall orig-fun
                                                      (get-buffer-process buf)
                                                      data))))))
                                   (current-buffer))))
            (funcall orig-fun process input)))))))

(defvar-local claude-code-ide--saved-cursor-type nil
  "Saved cursor-type before entering vterm-copy-mode.")

(defun claude-code-ide--vterm-copy-mode-hook ()
  "Make sure cursor is visible in `vterm-copy-mode'.
Saves the current cursor-type when entering copy mode and restores it
when exiting, ensuring compatibility with evil-mode and other packages
that manage cursor appearance."
  (if vterm-copy-mode
      ;; Entering copy mode: save current cursor-type and make cursor visible
      (progn
        (setq claude-code-ide--saved-cursor-type cursor-type)
        (when (null cursor-type)
          (setq cursor-type t)))
    ;; Exiting copy mode: restore previous cursor-type
    (setq cursor-type claude-code-ide--saved-cursor-type)))

(defun claude-code-ide--configure-vterm-buffer ()
  "Configure vterm for enhanced performance and visual quality.
Establishes optimal terminal settings including rendering optimizations,
cursor management, and process buffering for superior user experience."
  ;; Disable automatic scrolling to bottom on output to prevent flickering
  (setq-local vterm-scroll-to-bottom-on-output nil)
  ;; Disable immediate redraw to batch updates and reduce flickering
  (when (boundp 'vterm--redraw-immididately)
    (setq-local vterm--redraw-immididately nil))
  ;; Try to prevent cursor flickering by disabling Emacs' own cursor management
  (setq-local cursor-in-non-selected-windows nil)
  (setq-local blink-cursor-mode nil)
  (setq-local cursor-type nil)  ; Let vterm handle the cursor entirely
  ;; disable hl-line-mode, eliminates another source of flicker
  (setq-local global-hl-line-mode nil)
  (when (featurep 'hl-line)
    (hl-line-mode -1))
  ;; make sure the non-breaking space in the prompt isn't themed
  (face-remap-add-relative 'nobreak-space :inherit 'default)
  ;; Register hook for copy-mode cursor visibility
  (add-hook 'vterm-copy-mode-hook #'claude-code-ide--vterm-copy-mode-hook nil t)
  ;; Increase process read buffering to batch more updates together
  (when-let ((proc (get-buffer-process (current-buffer))))
    (set-process-query-on-exit-flag proc nil)
    ;; Try to make vterm read larger chunks at once
    (when (fboundp 'process-put)
      (process-put proc 'read-output-max 4096)))
  ;; Set up rendering optimization
  (when claude-code-ide-vterm-anti-flicker
    (advice-add 'vterm--filter :around #'claude-code-ide--vterm-smart-renderer)))

(defun claude-code-ide--configure-eat-buffer ()
  "Configure eat for Claude Code anti-flicker rendering."
  (when claude-code-ide-vterm-anti-flicker
    (advice-add 'eat--filter :around #'claude-code-ide--eat-smart-renderer)))


;;; Terminal Backend Abstraction

(defun claude-code-ide--terminal-ensure-backend ()
  "Ensure the selected terminal backend is available."
  (cond
   ((eq claude-code-ide-terminal-backend 'vterm)
    (unless (featurep 'vterm)
      (require 'vterm nil t))
    (unless (featurep 'vterm)
      (user-error "The package vterm is not installed.  Please install the vterm package or change `claude-code-ide-terminal-backend' to 'eat")))
   ((eq claude-code-ide-terminal-backend 'eat)
    (unless (featurep 'eat)
      (require 'eat nil t))
    (unless (featurep 'eat)
      (user-error "The package eat is not installed.  Please install the eat package or change `claude-code-ide-terminal-backend' to 'vterm")))
   (t
    (user-error "Invalid terminal backend: %s.  Valid options are 'vterm or 'eat" claude-code-ide-terminal-backend))))

(defun claude-code-ide--terminal-send-string (string &optional paste)
  "Send STRING to the terminal in the current buffer."
  (cond
   ((eq claude-code-ide-terminal-backend 'vterm)
    (vterm-send-string string paste))
   ((eq claude-code-ide-terminal-backend 'eat)
    (when eat-terminal
      (eat-term-send-string eat-terminal string)))
   (t
    (error "Unknown terminal backend: %s" claude-code-ide-terminal-backend))))

(defun claude-code-ide--terminal-send-escape ()
  "Send escape key to the terminal in the current buffer."
  (cond
   ((eq claude-code-ide-terminal-backend 'vterm)
    (vterm-send-escape))
   ((eq claude-code-ide-terminal-backend 'eat)
    (when eat-terminal
      (eat-term-send-string eat-terminal "\e")))
   (t
    (error "Unknown terminal backend: %s" claude-code-ide-terminal-backend))))

(defun claude-code-ide--terminal-send-return ()
  "Send return key to the terminal in the current buffer."
  (cond
   ((eq claude-code-ide-terminal-backend 'vterm)
    (vterm-send-return))
   ((eq claude-code-ide-terminal-backend 'eat)
    (when eat-terminal
      (eat-term-send-string eat-terminal "\r")))
   (t
    (error "Unknown terminal backend: %s" claude-code-ide-terminal-backend))))

(defun claude-code-ide--find-prompt-buffer ()
  "Find a visible buffer whose file name matches a prompt/plan pattern.
Scans all windows on all visible frames.  Returns the first
matching buffer, or nil."
  (let ((result nil))
    (walk-windows
     (lambda (win)
       (unless result
         (let* ((buf (window-buffer win))
                (fname (buffer-file-name buf)))
           (when (and fname
                      (cl-some (lambda (pat) (string-match-p pat fname))
                               claude-code-ide-prompt-buffer-patterns))
             (setq result buf)))))
     'no-minibuffer 'visible)
    result))

(defun claude-code-ide--prompt-buffer-send-string (string)
  "Insert STRING into the first visible prompt/plan buffer at point.
Returns the buffer on success, or nil if no prompt buffer is visible."
  (when-let ((buf (claude-code-ide--find-prompt-buffer)))
    (with-current-buffer buf
      (insert string))
    buf))

(defun claude-code-ide--sync-terminal-dimensions (buffer window)
  "Sync terminal dimensions in BUFFER to match WINDOW size.
This ensures the terminal process has the correct dimensions after
the buffer has been displayed in its final window, which may differ
from the window where it was initially created."
  (when (and buffer window (buffer-live-p buffer) (window-live-p window))
    (with-current-buffer buffer
      (when-let ((proc (get-buffer-process buffer)))
        (let ((height (window-body-height window))
              (width (window-body-width window)))
          (set-process-window-size proc height width))))))

(defun claude-code-ide--setup-terminal-keybindings ()
  "Set up keybindings for the Claude Code terminal buffer.
This function binds:
- M-RET (Alt-Return) to insert a newline
- C-<escape> to send escape"
  (cond
   ((eq claude-code-ide-terminal-backend 'vterm)
    ;; For vterm, we set up local keybindings in vterm-mode-map
    (local-set-key (kbd "S-<return>") #'claude-code-ide-insert-newline)
    (local-set-key (kbd "C-<escape>") #'claude-code-ide-send-escape))
   ((eq claude-code-ide-terminal-backend 'eat)
    ;; For eat, we need to modify the semi-char mode map which is the default
    ;; We use local-set-key to make it buffer-local
    (local-set-key (kbd "S-<return>") #'claude-code-ide-insert-newline)
    (local-set-key (kbd "C-<escape>") #'claude-code-ide-send-escape))
   (t
    (error "Unknown terminal backend: %s" claude-code-ide-terminal-backend))))

;;; Terminal Reflow Glitch Prevention
;;
;; This section implements a workaround for Claude Code bug #1422
;; where terminal reflows during height-only changes can cause
;; uncontrollable scrolling. This code should be removed once
;; the upstream bug is fixed.
;; See: https://github.com/anthropics/claude-code/issues/1422

(defun claude-code-ide--terminal-resize-handler ()
  "Retrieve the terminal's resize handling function based on backend."
  (pcase claude-code-ide-terminal-backend
    ('vterm #'vterm--window-adjust-process-window-size)
    ('eat #'eat--adjust-process-window-size)
    (_ (error "Unsupported terminal backend: %s" claude-code-ide-terminal-backend))))

(defun claude-code-ide--terminal-scroll-mode-active-p ()
  "Determine if terminal is currently in scroll/copy mode."
  (pcase claude-code-ide-terminal-backend
    ('vterm (bound-and-true-p vterm-copy-mode))
    ('eat (not (bound-and-true-p eat--semi-char-mode)))
    (_ nil)))

(defun claude-code-ide--session-buffer-p (buffer)
  "Check if BUFFER belongs to a Claude Code session."
  (when-let ((name (if (stringp buffer) buffer (buffer-name buffer))))
    (string-prefix-p "*claude-code[" name)))

(defun claude-code-ide--terminal-reflow-filter (original-fn &rest args)
  "Filter terminal reflows to prevent height-only resize triggers.
This wraps ORIGINAL-FN to suppress reflow signals unless the terminal
width has actually changed, working around the scrolling glitch."
  (let* ((base-result (apply original-fn args))
         (dimensions-stable t))
    ;; Only examine windows showing the current buffer, across ALL frames
    (when (claude-code-ide--session-buffer-p (current-buffer))
      (dolist (win (get-buffer-window-list (current-buffer) nil t))
        (let* ((new-width (window-width win))
               (cached-width (window-parameter win 'claude-code-ide-cached-width)))
          (unless (eql new-width cached-width)
            (setq dimensions-stable nil)
            (set-window-parameter win 'claude-code-ide-cached-width new-width)))))
    ;; Decide whether to allow reflow
    (cond
     ;; Not in a Claude buffer - pass through
     ((not (claude-code-ide--session-buffer-p (current-buffer)))
      base-result)
     ;; In scroll mode - suppress reflow
     ((claude-code-ide--terminal-scroll-mode-active-p)
      nil)
     ;; Dimensions changed - allow reflow
     ((not dimensions-stable)
      base-result)
     ;; No width change - suppress reflow
     (t nil))))


;;; Helper Functions

(defun claude-code-ide--default-buffer-name (directory)
  "Generate default buffer name for DIRECTORY."
  (format "*claude-code[%s]*"
          (file-name-nondirectory (directory-file-name directory))))

(defun claude-code-ide--get-working-directory ()
  "Get the current working directory (project root or current directory)."
  (if-let ((project (project-current)))
      (expand-file-name (project-root project))
    (expand-file-name default-directory)))

(defun claude-code-ide--get-buffer-name (&optional directory)
  "Get the buffer name for the Claude Code session in DIRECTORY.
If DIRECTORY is not provided, use the current working directory."
  (funcall claude-code-ide-buffer-name-function
           (or directory (claude-code-ide--get-working-directory))))

(defun claude-code-ide--maybe-switch-to-window (buffer)
  "Select BUFFER's window if `claude-code-ide-switch-after-send' is non-nil.
Only switches if BUFFER has a visible window.  Does nothing if the
variable is nil or the buffer has no visible window."
  (when claude-code-ide-switch-after-send
    (when-let ((win (get-buffer-window buffer)))
      (select-window win))))

(defun claude-code-ide--get-context-buffer ()
  "Return the buffer to use for file/selection context.
If the current buffer is visiting a file, return it directly.
If the current buffer is a Claude Code session buffer, find the
most recent visible file-visiting buffer in another window on
the current frame.  Returns nil if no suitable buffer is found."
  (cond
   (buffer-file-name (current-buffer))
   ((claude-code-ide--session-buffer-p (current-buffer))
    (let ((current (current-buffer)))
      (cl-loop for win in (window-list nil 'no-minibuffer)
               for buf = (window-buffer win)
               when (and (not (eq buf current))
                         (buffer-file-name buf))
               return buf)))))

(defun claude-code-ide--get-process (&optional directory)
  "Get the Claude Code process for DIRECTORY or current working directory."
  (gethash (or directory (claude-code-ide--get-working-directory))
           claude-code-ide--processes))

(defun claude-code-ide--set-process (process &optional directory)
  "Set the Claude Code PROCESS for DIRECTORY or current working directory."
  ;; Check if this is the first session starting
  (when (and claude-code-ide-prevent-reflow-glitch
             (= (hash-table-count claude-code-ide--processes) 0))
    ;; Apply advice globally for the first session
    (advice-add (claude-code-ide--terminal-resize-handler)
                :around #'claude-code-ide--terminal-reflow-filter))
  (puthash (or directory (claude-code-ide--get-working-directory))
           process
           claude-code-ide--processes))

(defun claude-code-ide--cleanup-dead-processes ()
  "Remove entries for dead processes from the process table."
  (maphash (lambda (directory process)
             (unless (process-live-p process)
               (remhash directory claude-code-ide--processes)))
           claude-code-ide--processes))

(defun claude-code-ide--cleanup-all-sessions ()
  "Clean up all active Claude Code sessions."
  (maphash (lambda (directory process)
             (when (process-live-p process)
               (claude-code-ide--cleanup-on-exit directory)))
           claude-code-ide--processes))

;; Ensure cleanup on Emacs exit
(add-hook 'kill-emacs-hook #'claude-code-ide--cleanup-all-sessions)

(defun claude-code-ide--display-buffer-in-side-window (buffer)
  "Display BUFFER in a side window according to customization.
The window is displayed on the side specified by
`claude-code-ide-window-side' with dimensions from
`claude-code-ide-window-width' or `claude-code-ide-window-height'.
If `claude-code-ide-focus-on-open' is non-nil, the window is selected."
  (let ((window
         (if claude-code-ide-use-side-window
             ;; Use side window
             (let* ((side claude-code-ide-window-side)
                    (slot 0)
                    (window-parameters '((no-delete-other-windows . t)))
                    (display-buffer-alist
                     `((,(regexp-quote (buffer-name buffer))
                        (display-buffer-in-side-window)
                        (side . ,side)
                        (slot . ,slot)
                        ,@(when (memq side '(left right))
                            `((window-width . ,claude-code-ide-window-width)))
                        ,@(when (memq side '(top bottom))
                            `((window-height . ,claude-code-ide-window-height)))
                        (window-parameters . ,window-parameters)))))
               (display-buffer buffer))
           ;; Use regular buffer
           (display-buffer buffer))))
    ;; Update last accessed buffer whenever we display a Claude buffer
    (setq claude-code-ide--last-accessed-buffer buffer)
    ;; Select the window to give it focus if configured to do so
    (when (and window claude-code-ide-focus-on-open)
      (select-window window))
    ;; For bottom/top windows, explicitly set and preserve the height
    (when (and window
               claude-code-ide-use-side-window
               (memq claude-code-ide-window-side '(top bottom)))
      (set-window-text-height window claude-code-ide-window-height)
      (set-window-dedicated-p window t))
    ;; Sync terminal dimensions with the actual window size
    ;; This is necessary because vterm/eat may have been created with
    ;; different dimensions before being displayed in this window
    (when window
      (claude-code-ide--sync-terminal-dimensions buffer window))
    window))

(defvar claude-code-ide--cleanup-in-progress nil
  "Flag to prevent recursive cleanup calls.")

(defun claude-code-ide--cleanup-on-exit (directory)
  "Clean up MCP server and process tracking when Claude exits for DIRECTORY."
  (unless claude-code-ide--cleanup-in-progress
    (setq claude-code-ide--cleanup-in-progress t)
    (unwind-protect
        (progn
          ;; Remove from process table
          (remhash directory claude-code-ide--processes)
          ;; Check if this was the last session
          (when (and claude-code-ide-prevent-reflow-glitch
                     (= (hash-table-count claude-code-ide--processes) 0))
            ;; Remove advice globally when no sessions remain
            (advice-remove (claude-code-ide--terminal-resize-handler)
                           #'claude-code-ide--terminal-reflow-filter))
          ;; Remove vterm rendering optimization if no sessions remain
          (when (and claude-code-ide-vterm-anti-flicker
                     (= (hash-table-count claude-code-ide--processes) 0))
            (cond
             ((eq claude-code-ide-terminal-backend 'vterm)
              (advice-remove 'vterm--filter #'claude-code-ide--vterm-smart-renderer))
             ((eq claude-code-ide-terminal-backend 'eat)
              (advice-remove 'eat--filter #'claude-code-ide--eat-smart-renderer))))
          ;; Stop MCP server for this project directory
          (claude-code-ide-mcp-stop-session directory)
          ;; Notify MCP tools server about session end with session ID
          (let ((session-id (gethash directory claude-code-ide--session-ids)))
            (claude-code-ide-mcp-server-session-ended session-id)
            ;; Clean up session ID mapping
            (when session-id
              (remhash directory claude-code-ide--session-ids)))
          ;; Kill the vterm buffer if it exists
          (let ((buffer-name (claude-code-ide--get-buffer-name directory)))
            (when-let ((buffer (get-buffer buffer-name)))
              (when (buffer-live-p buffer)
                (let ((kill-buffer-hook nil) ; Disable hooks to prevent recursion
                      (kill-buffer-query-functions nil)) ; Don't ask for confirmation
                  (kill-buffer buffer)))))
          (claude-code-ide-debug "Cleaned up Claude Code session for %s"
                                 (file-name-nondirectory (directory-file-name directory))))
      (setq claude-code-ide--cleanup-in-progress nil))))

;;; CLI Detection

(defun claude-code-ide--cli-type ()
  "Detect CLI type from `claude-code-ide-cli-path'.
Returns \\='claude or \\='codex based on the basename prefix.
Unknown CLIs fall back to \\='claude."
  (let ((basename (file-name-nondirectory claude-code-ide-cli-path)))
    (cond
     ((string-prefix-p "codex" basename) 'codex)
     (t 'claude))))

(defun claude-code-ide--detect-cli ()
  "Detect if Claude Code CLI is available."
  (let ((available (condition-case nil
                       (eq (call-process claude-code-ide-cli-path nil nil nil "--version") 0)
                     (error nil))))
    (setq claude-code-ide--cli-available available)))

(defun claude-code-ide--ensure-cli ()
  "Ensure Claude Code CLI is available, detect if needed."
  (unless claude-code-ide--cli-available
    (claude-code-ide--detect-cli))
  claude-code-ide--cli-available)

;;; Commands

(defun claude-code-ide--toggle-existing-window (existing-buffer working-dir)
  "Toggle visibility of EXISTING-BUFFER window for WORKING-DIR.
If the window is visible, it will be hidden.
If the window is not visible, it will be shown in a side window."
  (let ((window (get-buffer-window existing-buffer)))
    (if window
        ;; Window is visible, hide it
        (progn
          ;; Track this buffer as last accessed when closing
          (setq claude-code-ide--last-accessed-buffer existing-buffer)
          (delete-window window)
          (claude-code-ide-debug "Claude Code window hidden"))
      ;; Window is not visible, show it
      (progn
        (claude-code-ide--display-buffer-in-side-window existing-buffer)
        ;; Update the original tab when showing the window
        (when-let ((session (claude-code-ide-mcp--get-session-for-project working-dir)))
          (when (fboundp 'tab-bar--current-tab)
            (setf (claude-code-ide-mcp-session-original-tab session) (tab-bar--current-tab))))
        (claude-code-ide-debug "Claude Code window shown")))))

(defun claude-code-ide--build-claude-command (&optional continue resume session-id)
  "Build the Claude command with optional flags.
If CONTINUE is non-nil, add the -c flag.
If RESUME is non-nil, add the -r flag.
If SESSION-ID is provided, it's included in the MCP server URL path.
If `claude-code-ide-cli-debug' is non-nil, add the -d flag.
If `claude-code-ide-system-prompt' is non-nil, add the --append-system-prompt flag.
Additional flags from `claude-code-ide-cli-extra-flags' are also included."
  (let ((claude-cmd claude-code-ide-cli-path))
    ;; Add debug flag if enabled
    (when claude-code-ide-cli-debug
      (setq claude-cmd (concat claude-cmd " -d")))
    ;; Add resume flag if requested
    (when resume
      (setq claude-cmd (concat claude-cmd " -r")))
    ;; Add continue flag if requested
    (when continue
      (setq claude-cmd (concat claude-cmd " -c")))
    ;; Add append-system-prompt flag with Emacs context
    (let ((emacs-prompt "IMPORTANT: Connected to Emacs via claude-code-ide.el integration. Emacs uses mixed coordinates: Lines: 1-based (line 1 = first line), Columns: 0-based (column 0 = first column). Example: First character in file is at line 1, column 0. Available: xref (LSP), tree-sitter, imenu, project.el, flycheck/flymake diagnostics. Context-aware with automatic project/file/selection tracking.")
          (combined-prompt nil))
      ;; Always include the Emacs-specific prompt
      (setq combined-prompt emacs-prompt)
      ;; Append user's custom prompt if set
      (when claude-code-ide-system-prompt
        (setq combined-prompt (concat combined-prompt "\n\n" claude-code-ide-system-prompt)))
      ;; Add the combined prompt to the command
      (setq claude-cmd (concat claude-cmd " --append-system-prompt "
                               (shell-quote-argument combined-prompt))))
    ;; Add any extra flags
    (when (and claude-code-ide-cli-extra-flags
               (not (string-empty-p claude-code-ide-cli-extra-flags)))
      (setq claude-cmd (concat claude-cmd " " claude-code-ide-cli-extra-flags)))
    ;; Add MCP tools config if enabled
    (when (claude-code-ide-mcp-server-ensure-server)
      (when-let ((config (claude-code-ide-mcp-server-get-config session-id)))
        (let ((json-str (json-encode config)))
          (claude-code-ide-debug "MCP tools config JSON: %s" json-str)
          ;; For vterm, we need to escape for sh -c context
          ;; First escape backslashes, then quotes
          (setq json-str (replace-regexp-in-string "\\\\" "\\\\\\\\" json-str))
          (setq json-str (replace-regexp-in-string "\"" "\\\\\"" json-str))
          (setq claude-cmd (concat claude-cmd " --mcp-config \"" json-str "\""))
          ;; Add allowedTools flag if configured
          (let ((allowed-tools
                 (cond
                  ;; Auto mode: get all emacs-tools names
                  ((eq claude-code-ide-mcp-allowed-tools 'auto)
                   (mapconcat 'identity (claude-code-ide-mcp-server-get-tool-names "mcp__emacs-tools__") " "))
                  ;; List of specific tools
                  ((listp claude-code-ide-mcp-allowed-tools)
                   (mapconcat 'identity claude-code-ide-mcp-allowed-tools " "))
                  ;; String pattern or nil
                  (t claude-code-ide-mcp-allowed-tools))))
            (when allowed-tools
              (setq claude-cmd (concat claude-cmd " --allowedTools " allowed-tools)))))))
    claude-cmd))

(defun claude-code-ide--build-codex-command (&optional continue resume _session-id)
  "Build the Codex command with optional flags.
If CONTINUE is non-nil, use `codex resume --last'.
If RESUME is non-nil, use `codex resume' (picker).
_SESSION-ID is unused (no MCP for codex).
Additional flags from `claude-code-ide-cli-extra-flags' are included."
  (let ((codex-cmd (cond
                    (resume (concat claude-code-ide-cli-path " resume"))
                    (continue (concat claude-code-ide-cli-path " resume --last"))
                    (t claude-code-ide-cli-path))))
    ;; Add any extra flags
    (when (and claude-code-ide-cli-extra-flags
               (not (string-empty-p claude-code-ide-cli-extra-flags)))
      (setq codex-cmd (concat codex-cmd " " claude-code-ide-cli-extra-flags)))
    codex-cmd))

(defun claude-code-ide--build-command (&optional continue resume session-id)
  "Build CLI command, dispatching by CLI type.
Arguments CONTINUE, RESUME, SESSION-ID are passed to the CLI-specific builder."
  (pcase (claude-code-ide--cli-type)
    ('codex (claude-code-ide--build-codex-command continue resume session-id))
    (_ (claude-code-ide--build-claude-command continue resume session-id))))

(defun claude-code-ide--terminal-position-keeper (window-list)
  "Maintain stable terminal view position across window switches.
WINDOW-LIST contains windows requiring position synchronization.
Implements intelligent scroll management to preserve user context
when navigating between terminal and other buffers."
  (dolist (win window-list)
    (if (eq win 'buffer)
        ;; Direct buffer point update
        (goto-char (eat-term-display-cursor eat-terminal))
      ;; Window-specific position management
      (unless buffer-read-only  ; Skip when terminal is in navigation mode
        (let ((terminal-point (eat-term-display-cursor eat-terminal)))
          ;; Update window point to match terminal state
          (set-window-point win terminal-point)
          ;; Apply smart positioning strategy
          (cond
           ;; Terminal at bottom: maintain bottom alignment for active prompts
           ((>= terminal-point (- (point-max) 2))
            (with-selected-window win
              (goto-char terminal-point)
              (recenter -1)))  ; Pin to bottom
           ;; Terminal out of view: restore visibility
           ((not (pos-visible-in-window-p terminal-point win))
            (with-selected-window win
              (goto-char terminal-point)
              (recenter)))))))))

(defun claude-code-ide--parse-command-string (command-string)
  "Parse a command string into (program . args) for eat-exec.
COMMAND-STRING is a shell command line to parse.
Returns a cons cell (program . args) where program is the executable
and args is a list of arguments."
  (let ((parts (split-string-shell-command command-string)))
    (cons (car parts) (cdr parts))))


(defun claude-code-ide--create-terminal-with-command (buffer-name working-dir cmd env-vars)
  "Create a terminal buffer running CMD with ENV-VARS.
BUFFER-NAME is the name for the terminal buffer.
WORKING-DIR is the working directory.
CMD is the shell command string to run.
ENV-VARS is a list of \"KEY=VALUE\" environment variable strings.

Returns a cons cell of (buffer . process) on success.
Signals an error if terminal fails to initialize."
  (claude-code-ide--terminal-ensure-backend)
  (let ((default-directory working-dir))
    (claude-code-ide-debug "Starting with command: %s" cmd)
    (claude-code-ide-debug "Working directory: %s" working-dir)
    (claude-code-ide-debug "Terminal backend: %s" claude-code-ide-terminal-backend)

    (cond
     ;; vterm backend
     ((eq claude-code-ide-terminal-backend 'vterm)
      (let* ((vterm-buffer-name buffer-name)
             (vterm-shell cmd)
             (vterm-environment (append env-vars vterm-environment)))
        (let ((buffer (save-window-excursion
                        (vterm vterm-buffer-name))))
          (unless buffer
            (error "Failed to create vterm buffer.  Please ensure vterm is properly installed and compiled"))
          (with-current-buffer buffer
            (claude-code-ide--configure-vterm-buffer))
          (let ((process (get-buffer-process buffer)))
            (unless process
              (error "Failed to get vterm process.  The vterm module may not be compiled correctly"))
            (unless (buffer-live-p buffer)
              (error "Vterm buffer was killed during initialization"))
            (cons buffer process)))))

     ;; eat backend
     ((eq claude-code-ide-terminal-backend 'eat)
      (let* ((buffer (get-buffer-create buffer-name))
             (eat-term-name "xterm-256color")
             (cmd-parts (claude-code-ide--parse-command-string cmd))
             (program (car cmd-parts))
             (args (cdr cmd-parts)))
        (with-current-buffer buffer
          (unless (eq major-mode 'eat-mode)
            (eat-mode))
          (claude-code-ide--configure-eat-buffer)
          (when claude-code-ide-eat-preserve-position
            (setq-local eat--synchronize-scroll-function
                        #'claude-code-ide--terminal-position-keeper))
          (setq-local process-environment
                      (append env-vars process-environment))
          (eat-exec buffer buffer-name program nil args)
          (let ((process (get-buffer-process buffer)))
            (unless process
              (error "Failed to create eat process.  Please ensure eat is properly installed"))
            (cons buffer process)))))

     (t
      (error "Unknown terminal backend: %s" claude-code-ide-terminal-backend)))))

(defun claude-code-ide--create-claude-terminal-session (buffer-name working-dir port continue resume session-id)
  "Create a new terminal session for the CLI.
BUFFER-NAME is the name for the terminal buffer.
WORKING-DIR is the working directory.
PORT is the MCP server port.
CONTINUE is whether to continue the most recent conversation.
RESUME is whether to resume a previous conversation.
SESSION-ID is the unique identifier for this session.

Returns a cons cell of (buffer . process) on success."
  (let ((cmd (claude-code-ide--build-claude-command continue resume session-id))
        (env-vars (list (format "CLAUDE_CODE_SSE_PORT=%d" port)
                        (format "EMACS_BUFFER_NAME=%s" buffer-name)
                        "ENABLE_IDE_INTEGRATION=true"
                        "TERM_PROGRAM=emacs"
                        "FORCE_CODE_TERMINAL=true")))
    (claude-code-ide-debug "Environment: CLAUDE_CODE_SSE_PORT=%d" port)
    (claude-code-ide-debug "Session ID: %s" session-id)
    (claude-code-ide--create-terminal-with-command buffer-name working-dir cmd env-vars)))

(defun claude-code-ide--create-codex-terminal-session (buffer-name working-dir _port continue resume session-id)
  "Create a new terminal session for Codex CLI.
BUFFER-NAME is the name for the terminal buffer.
WORKING-DIR is the working directory.
_PORT is unused (no MCP for Codex).
CONTINUE is whether to continue the most recent conversation.
RESUME is whether to resume a previous conversation.
SESSION-ID is the unique identifier for this session.

Returns a cons cell of (buffer . process) on success."
  (let ((cmd (claude-code-ide--build-codex-command continue resume session-id))
        (env-vars (list (format "EMACS_BUFFER_NAME=%s" buffer-name)
                        ;; "TERM_PROGRAM=emacs"
                        )))
    (claude-code-ide-debug "Session ID: %s" session-id)
    (claude-code-ide--create-terminal-with-command buffer-name working-dir cmd env-vars)))

(defun claude-code-ide--create-terminal-session (buffer-name working-dir port continue resume session-id)
  "Create a new terminal session, dispatching by CLI type.
BUFFER-NAME is the name for the terminal buffer.
WORKING-DIR is the working directory.
PORT is the MCP server port.
CONTINUE is whether to continue the most recent conversation.
RESUME is whether to resume a previous conversation.
SESSION-ID is the unique identifier for this session.

Returns a cons cell of (buffer . process) on success."
  (pcase (claude-code-ide--cli-type)
    ('codex (claude-code-ide--create-codex-terminal-session
             buffer-name working-dir port continue resume session-id))
    (_ (claude-code-ide--create-claude-terminal-session
        buffer-name working-dir port continue resume session-id))))

(defun claude-code-ide--start-session (&optional continue resume)
  "Start a Claude Code session for the current project.
If CONTINUE is non-nil, start Claude with the -c (continue) flag.
If RESUME is non-nil, start Claude with the -r (resume) flag.

This function handles:
- CLI availability checking
- Dead process cleanup
- Existing session detection and window toggling
- New session creation with MCP server setup
- Process and buffer lifecycle management"
  (unless (claude-code-ide--ensure-cli)
    (user-error "Claude Code CLI not available.  Please install it and ensure it's in PATH"))

  ;; Clean up any dead processes first
  (claude-code-ide--cleanup-dead-processes)

  (let* ((working-dir (claude-code-ide--get-working-directory))
         (buffer-name (claude-code-ide--get-buffer-name))
         (existing-buffer (get-buffer buffer-name))
         (existing-process (claude-code-ide--get-process working-dir)))

    ;; If buffer exists and process is alive, toggle the window
    (if (and existing-buffer
             (buffer-live-p existing-buffer)
             existing-process)
        (claude-code-ide--toggle-existing-window existing-buffer working-dir)
      ;; Ensure the selected terminal backend is available before starting MCP
      (claude-code-ide--terminal-ensure-backend)
      ;; Start MCP server with project directory
      (let ((port nil)
            (session-id (format "claude-%s-%s"
                                (file-name-nondirectory (directory-file-name working-dir))
                                (format-time-string "%Y%m%d-%H%M%S"))))
        (condition-case err
            (progn
              ;; Start MCP server
              (setq port (claude-code-ide-mcp-start working-dir))
              ;; Create new terminal session
              (let* ((buffer-and-process (claude-code-ide--create-terminal-session
                                          buffer-name working-dir port continue resume session-id))
                     (buffer (car buffer-and-process))
                     (process (cdr buffer-and-process)))
                ;; Notify MCP tools server about new session with session info
                (claude-code-ide-mcp-server-session-started session-id working-dir buffer)
                (claude-code-ide--set-process process working-dir)
                ;; Store session ID for cleanup
                (puthash working-dir session-id claude-code-ide--session-ids)
                ;; Set up process sentinel to clean up when Claude exits
                (set-process-sentinel process
                                      (lambda (_proc event)
                                        ;; Check for abnormal exit with error code
                                        (when (string-match "exited abnormally with code \\([0-9]+\\)" event)
                                          (let ((exit-code (match-string 1 event)))
                                            (claude-code-ide-debug "Claude process exited with code %s, event: %s"
                                                                   exit-code event)
                                            (message "Claude exited with error code %s" exit-code)))
                                        (when (or (string-match "finished" event)
                                                  (string-match "exited" event)
                                                  (string-match "killed" event)
                                                  (string-match "terminated" event))
                                          (claude-code-ide--cleanup-on-exit working-dir))))
                ;; Also add buffer kill hook as a backup
                (with-current-buffer buffer
                  (add-hook 'kill-buffer-hook
                            (lambda ()
                              (claude-code-ide--cleanup-on-exit working-dir))
                            nil t)
                  ;; Set up terminal keybindings
                  (claude-code-ide--setup-terminal-keybindings)
                  ;; Add terminal-specific exit hooks
                  (cond
                   ((eq claude-code-ide-terminal-backend 'vterm)
                    ;; Add vterm exit hook to ensure buffer is killed when process exits
                    ;; vterm runs Claude directly, no shell involved
                    (add-hook 'vterm-exit-functions
                              (lambda (&rest _)
                                (when (buffer-live-p buffer)
                                  (kill-buffer buffer)))
                              nil t))
                   ((eq claude-code-ide-terminal-backend 'eat)
                    ;; eat uses kill-buffer-on-exit variable
                    (setq-local eat-kill-buffer-on-exit t))))
                ;; Stabilization period for terminal layout initialization
                (sleep-for claude-code-ide-terminal-initialization-delay)
                ;; Display the buffer in a side window
                (claude-code-ide--display-buffer-in-side-window buffer)
                (claude-code-ide-log "Claude Code %sstarted in %s with MCP on port %d%s"
                                     (cond (continue "continued and ")
                                           (resume "resumed and ")
                                           (t ""))
                                     (file-name-nondirectory (directory-file-name working-dir))
                                     port
                                     (if claude-code-ide-cli-debug " (debug mode enabled)" ""))))
          (error
           ;; Terminal session creation failed - clean up MCP server
           (when port
             (claude-code-ide-mcp-stop-session working-dir))
           ;; Re-signal the error with improved message
           (signal (car err) (cdr err))))))))

;;;###autoload
(defun claude-code-ide ()
  "Run Claude Code in a terminal for the current project or directory."
  (interactive)
  (claude-code-ide--start-session))

;;;###autoload
(defun claude-code-ide-resume ()
  "Resume Claude Code in a terminal for the current project or directory.
This starts Claude with the -r (resume) flag to continue the previous
conversation."
  (interactive)
  (claude-code-ide--start-session nil t))

;;;###autoload
(defun claude-code-ide-continue ()
  "Continue the most recent Claude Code conversation in the current directory.
This starts Claude with the -c (continue) flag to continue the most recent
conversation in the current directory."
  (interactive)
  (claude-code-ide--start-session t))

;;;###autoload
(defun claude-code-ide-check-status ()
  "Check Claude Code CLI status."
  (interactive)
  (claude-code-ide--detect-cli)
  (if claude-code-ide--cli-available
      (let ((version-output
             (with-temp-buffer
               (call-process claude-code-ide-cli-path nil t nil "--version")
               (buffer-string))))
        (claude-code-ide-log "Claude Code CLI version: %s" (string-trim version-output)))
    (claude-code-ide-log "Claude Code is not installed.")))

;;;###autoload
(defun claude-code-ide-stop ()
  "Stop the Claude Code session for the current project or directory."
  (interactive)
  (let* ((working-dir (claude-code-ide--get-working-directory))
         (buffer-name (claude-code-ide--get-buffer-name)))
    (if-let ((buffer (get-buffer buffer-name)))
        (progn
          ;; Kill the buffer (cleanup will be handled by hooks)
          ;; The process sentinel will handle cleanup when the process dies
          (kill-buffer buffer)
          (claude-code-ide-log "Stopping Claude Code in %s..."
                               (file-name-nondirectory (directory-file-name working-dir))))
      (claude-code-ide-log "No Claude Code session is running in this directory"))))


;;;###autoload
(defun claude-code-ide-switch-to-buffer ()
  "Switch to the Claude Code buffer for the current project.
If the buffer is not visible, display it in the configured side window.
If the buffer is already visible, switch focus to it."
  (interactive)
  (let ((buffer-name (claude-code-ide--get-buffer-name)))
    (if-let ((buffer (get-buffer buffer-name)))
        (if-let ((window (get-buffer-window buffer)))
            ;; Buffer is visible, just focus it
            (select-window window)
          ;; Buffer exists but not visible, display it
          (claude-code-ide--display-buffer-in-side-window buffer))
      (user-error "No Claude Code session for this project.  Use M-x claude-code-ide to start one"))))

;;;###autoload
(defun claude-code-ide-list-sessions ()
  "List all active Claude Code sessions and switch to selected one."
  (interactive)
  (claude-code-ide--cleanup-dead-processes)
  (let ((sessions '()))
    (maphash (lambda (directory _)
               (push (cons (abbreviate-file-name directory)
                           directory)
                     sessions))
             claude-code-ide--processes)
    (if sessions
        (let ((choice (completing-read "Switch to Claude Code session: "
                                       sessions nil t)))
          (when choice
            (let* ((directory (alist-get choice sessions nil nil #'string=))
                   (buffer-name (funcall claude-code-ide-buffer-name-function directory)))
              (if-let ((buffer (get-buffer buffer-name)))
                  (claude-code-ide--display-buffer-in-side-window buffer)
                (user-error "Buffer for session %s no longer exists" choice)))))
      (claude-code-ide-log "No active Claude Code sessions"))))

;;;###autoload
(defun claude-code-ide-insert-at-mentioned ()
  "Insert selected text into Claude prompt.
When called from a Claude Code session buffer, uses the most
recent visible file-visiting buffer on the current frame."
  (interactive)
  (if-let* ((project-dir (claude-code-ide-mcp--get-buffer-project))
            (session (claude-code-ide-mcp--get-session-for-project project-dir))
            (client (claude-code-ide-mcp-session-client session)))
      (let ((ctx-buf (or (claude-code-ide--get-context-buffer) (current-buffer))))
        (with-current-buffer ctx-buf
          (claude-code-ide-mcp-send-at-mentioned))
        (claude-code-ide-debug "Sent selection to Claude Code")
        (when-let ((buffer (get-buffer (claude-code-ide--get-buffer-name))))
          (claude-code-ide--maybe-switch-to-window buffer)))
    (user-error "Claude Code is not connected.  Please start Claude Code first")))

;;;###autoload
(defun claude-code-ide-send-escape ()
  "Send escape key to the Claude Code terminal buffer for the current project."
  (interactive)
  (let ((buffer-name (claude-code-ide--get-buffer-name)))
    (if-let ((buffer (get-buffer buffer-name)))
        (with-current-buffer buffer
          (claude-code-ide--terminal-send-escape))
      (user-error "No Claude Code session for this project"))))

;;;###autoload
(defun claude-code-ide-send-double-escape ()
  "Send double escape key to the Claude Code terminal buffer for the current project."
  (interactive)
  (let ((buffer-name (claude-code-ide--get-buffer-name)))
    (if-let ((buffer (get-buffer buffer-name)))
        (with-current-buffer buffer
          (claude-code-ide--terminal-send-escape)
          (claude-code-ide--terminal-send-escape))
      (user-error "No Claude Code session for this project"))))

;;;###autoload
(defun claude-code-ide-insert-newline ()
  "Send newline (backslash + return) to the Claude Code terminal buffer for the current project.
This simulates typing backslash followed by Enter, which Claude Code interprets as a newline."
  (interactive)
  (let ((buffer-name (claude-code-ide--get-buffer-name)))
    (if-let ((buffer (get-buffer buffer-name)))
        (with-current-buffer buffer
          (claude-code-ide--terminal-send-string "\\")
          ;; Small delay to ensure prompt text is processed before sending return
          (sit-for 0.1)
          (claude-code-ide--terminal-send-return))
      (user-error "No Claude Code session for this project"))))

;;;###autoload
(defun claude-code-ide-toggle-vterm-optimization ()
  "Toggle vterm rendering optimization.
This command switches the advanced rendering optimization on or off.
Use this to balance between visual smoothness and raw responsiveness."
  (interactive)
  (setq claude-code-ide-vterm-anti-flicker
        (not claude-code-ide-vterm-anti-flicker))
  (message "Vterm rendering optimization %s"
           (if claude-code-ide-vterm-anti-flicker
               "enabled (smoother display with minimal latency)"
             "disabled (direct rendering, maximum responsiveness)")))

;;;###autoload
(defun claude-code-ide-send-prompt (&optional prompt)
  "Send a prompt to the Claude Code terminal.
When called interactively, reads a prompt from the minibuffer.
When called programmatically, sends the given PROMPT string."
  (interactive)
  (let ((buffer-name (claude-code-ide--get-buffer-name)))
    (if-let ((buffer (get-buffer buffer-name)))
        (let ((prompt-to-send (or prompt (read-string "Claude prompt: "))))
          (when (not (string-empty-p prompt-to-send))
            (with-current-buffer buffer
              (claude-code-ide--terminal-send-string prompt-to-send)
              ;; Small delay to ensure prompt text is processed before sending return
              (sit-for 0.1)
              (claude-code-ide--terminal-send-return))
            (claude-code-ide-debug "Sent prompt to Claude Code: %s" prompt-to-send)
            (claude-code-ide--maybe-switch-to-window buffer)))
      (user-error "No Claude Code session for this project"))))

(defun claude-code-ide--get-clipboard-text ()
  "Return the current clipboard contents as a plain string, or nil if unavailable."
  (let* ((selection (when (fboundp 'gui-get-selection)
                      (or (let ((text (gui-get-selection 'CLIPBOARD 'UTF8_STRING)))
                            (and (stringp text) (not (string-empty-p text)) text))
                          (let ((text (gui-get-selection 'CLIPBOARD 'STRING)))
                            (and (stringp text) (not (string-empty-p text)) text)))))
         (kill-text (condition-case nil
                        (current-kill 0 t)
                      (error nil))))
    (let ((text (or selection kill-text)))
      (when (stringp text)
        (substring-no-properties text)))))

(defun claude-code-ide--comment-prefix ()
  "Return the comment prefix for the current buffer."
  (when comment-start
    (if (derived-mode-p 'emacs-lisp-mode)
        (let* ((trimmed (string-trim-right comment-start)))
          (if (= (length trimmed) 1)
              (make-string 2 (string-to-char trimmed))
            trimmed))
      (string-trim-right comment-start))))

(defun claude-code-ide--is-comment-line (line)
  "Return non-nil when LINE is a comment line for the current buffer.
Lines whose comment body begins with `DONE:' are excluded."
  (when-let ((comment-str (claude-code-ide--comment-prefix)))
    (let* ((trimmed-line (string-trim-left line))
           (comment-re (concat "^[ \t]*"
                               (regexp-quote comment-str)
                               "+[ \t]*")))
      (when (string-match comment-re trimmed-line)
        (let ((content (string-trim-left (substring trimmed-line (match-end 0)))))
          (unless (string-prefix-p "DONE:" content)
            t))))))

(defun claude-code-ide--is-comment-block (text)
  "Return non-nil when TEXT contains only comment lines and blanks."
  (let ((lines (split-string text "\n")))
    (cl-every (lambda (line)
                (or (string-blank-p line)
                    (claude-code-ide--is-comment-line line)))
              lines)))

(defun claude-code-ide--relative-file-name (file-name)
  "Return FILE-NAME relative to the current project when possible."
  (if-let ((project (project-current nil)))
      (file-relative-name file-name (project-root project))
    file-name))

(defun claude-code-ide--get-region-location-info (region-beginning region-end)
  "Return file and line range information for REGION-BEGINNING and REGION-END."
  (when (and region-beginning region-end buffer-file-name)
    (let ((region-start-line (line-number-at-pos region-beginning))
          (region-end-line (line-number-at-pos region-end)))
      (format "%s#L%d-L%d"
              (claude-code-ide--relative-file-name buffer-file-name)
              region-start-line
              region-end-line))))

(defun claude-code-ide--get-context-files-string ()
  "Return a formatted list of visible file buffers for additional context."
  (if (not buffer-file-name)
      ""
    (let* ((current-file buffer-file-name)
           (files (list current-file)))
      (dolist (win (window-list nil 'no-minibuffer))
        (let ((file (buffer-file-name (window-buffer win))))
          (when (and file (not (equal file current-file)))
            (cl-pushnew file files :test #'string=))))
      (concat "\nFiles:\n"
              (mapconcat #'claude-code-ide--relative-file-name files "\n")))))

(defun claude-code-ide--get-function-name-for-comment ()
  "Return the most relevant function name for the comment at point."
  (let* ((current-func (which-function))
         (resolved-func
          (save-excursion
            (cl-labels ((line-text ()
                          (buffer-substring-no-properties
                           (line-beginning-position)
                           (line-end-position))))
              (forward-line 1)
              (cl-block resolve
                (let ((text (line-text)))
                  (when (or (eobp) (string-blank-p text))
                    (cl-return-from resolve nil))
                  (while (claude-code-ide--is-comment-line text)
                    (forward-line 1)
                    (setq text (line-text))
                    (when (or (eobp) (string-blank-p text))
                      (cl-return-from resolve nil)))
                  (let ((next-func (which-function)))
                    (cl-loop with lookahead = 5
                             while (and (> lookahead 0)
                                        (or (null next-func)
                                            (string= next-func current-func)))
                             do (forward-line 1)
                                (setq lookahead (1- lookahead))
                                (setq text (line-text))
                                (when (string-blank-p text)
                                  (cl-return-from resolve nil))
                                (unless (claude-code-ide--is-comment-line text)
                                  (setq next-func (which-function)))
                             finally return (cond
                                             ((not current-func) next-func)
                                             ((not next-func) current-func)
                                             ((not (string= next-func current-func)) next-func)
                                             (t current-func))))))))))
    resolved-func))

(defun claude-code-ide--implement-todo--handle-done-line ()
  "Handle actions when the current line is a DONE comment.
Return non-nil when the caller should stop processing."
  (let* ((line-str (buffer-substring-no-properties (line-beginning-position)
                                                   (line-end-position)))
         (comment-prefix (claude-code-ide--comment-prefix))
         (done-re (when comment-prefix
                    (concat "^\\([ \t]*" (regexp-quote comment-prefix) "+[ \t]*\\)DONE:"))))
    (when (and line-str done-re (string-match done-re line-str) (not (use-region-p)))
      (let* ((action (completing-read
                      "Current line starts with DONE:. Action: "
                      '("Toggle to TODO" "Delete comment line" "Keep as DONE")
                      nil t nil nil "Toggle to TODO"))
             (line-beg (line-beginning-position))
             (line-end (line-end-position)))
        (pcase action
          ("Toggle to TODO"
           (save-excursion
             (goto-char line-beg)
             (when (search-forward "DONE:" line-end t)
               (replace-match "TODO:" nil nil)))
           (message "Changed DONE comment back to TODO"))
          ("Delete comment line"
           (let ((line-next
                  (save-excursion
                    (goto-char line-beg)
                    (forward-line 1)
                    (min (point) (point-max)))))
             (delete-region line-beg line-next))
           (message "Deleted DONE comment line"))
          (_
           (message "Keeping DONE comment unchanged")))
        t))))

(defun claude-code-ide--implement-todo--handle-blank-line ()
  "Insert a TODO comment when point is on a blank line.
Return non-nil when the caller should stop processing."
  (when (and (not (use-region-p))
             (or (not (thing-at-point 'line t))
                 (string-blank-p (thing-at-point 'line t)))
             comment-start)
    (let ((todo-text (read-string "Enter TODO comment: "))
          (comment-prefix (claude-code-ide--comment-prefix)))
      (unless (string-blank-p todo-text)
        (delete-region (line-beginning-position) (line-end-position))
        (indent-according-to-mode)
        (insert comment-prefix
                " TODO: "
                todo-text
                (if (and comment-end (not (string-blank-p comment-end)))
                    (concat " " (string-trim-left comment-end))
                  ""))
        (indent-according-to-mode)))
    t))

(defun claude-code-ide--implement-todo--prompt-label (clipboard-context)
  "Return the minibuffer label for TODO implementation.
CLIPBOARD-CONTEXT indicates whether clipboard text will be appended."
  (if (and clipboard-context
           (string-match-p "\\S-" clipboard-context))
      "Implement TODO in Claude Code (clipboard context): "
    "Implement TODO in Claude Code: "))

(defun claude-code-ide--implement-todo--build-prompt (arg)
  "Build the TODO implementation prompt for prefix ARG."
  (let* ((clipboard-context (when arg (claude-code-ide--get-clipboard-text)))
         (current-line (string-trim (thing-at-point 'line t)))
         (current-line-number (line-number-at-pos (point)))
         (is-comment (claude-code-ide--is-comment-line current-line))
         (function-name (if is-comment
                            (claude-code-ide--get-function-name-for-comment)
                          (which-function)))
         (function-context (if function-name
                               (format "\nFunction: %s" function-name)
                             ""))
         (region-active (use-region-p))
         (region-text (when region-active
                        (buffer-substring-no-properties
                         (region-beginning)
                         (region-end))))
         (region-start-line (when region-active
                              (line-number-at-pos (region-beginning))))
         (region-location-info (when region-active
                                 (claude-code-ide--get-region-location-info
                                  (region-beginning)
                                  (region-end))))
         (region-location-line (when region-text
                                 (or (and region-location-info
                                          (format "Selected region: %s"
                                                  region-location-info))
                                     (when region-start-line
                                       (format "Selected region starting on line %d"
                                               region-start-line)))))
         (files-context-string (claude-code-ide--get-context-files-string))
         (prompt-label (claude-code-ide--implement-todo--prompt-label
                        clipboard-context))
         (initial-input
          (cond
           (region-text
            (unless (claude-code-ide--is-comment-block region-text)
              (user-error "Selected region must be a comment block"))
            (format
             "Please implement code for this TODO comment block in the selected region first. After implementing, keep the comment in place and ensure it begins with a DONE prefix (change TODO to DONE or prepend DONE if no prefix). If this is a pure new code block, place it after the comment; otherwise keep the existing structure and make the corresponding change for the surrounding code.\n%s\n%s%s%s"
             region-location-line
             region-text
             function-context
             files-context-string))
           (is-comment
            (format
             "Please implement code for this TODO comment on line %d: '%s' first. After implementing, keep the comment in place and ensure it begins with a DONE prefix (change TODO to DONE or prepend DONE if needed). If this is a pure new code block, place it after the comment; otherwise keep the existing structure and make the corresponding change for the surrounding code.%s%s"
             current-line-number
             current-line
             function-context
             files-context-string))
           (t
            (user-error
             "Current line is not a TODO comment. Select a TODO comment, a comment block, or use a blank line"))))
         (prompt (read-string prompt-label initial-input))
         (final-prompt
          (concat prompt
                  (when (and clipboard-context
                             (string-match-p "\\S-" clipboard-context))
                    (concat "\n\nClipboard context:\n" clipboard-context)))))
    final-prompt))

;;;###autoload
(defun claude-code-ide-implement-todo (arg)
  "Build and send a TODO implementation prompt for the current context.
With prefix ARG, append clipboard text as extra context."
  (interactive "P")
  (let ((ctx-buf (claude-code-ide--get-context-buffer)))
    (unless ctx-buf
      (user-error "Current buffer is not visiting a file"))
    (with-current-buffer ctx-buf
      (cl-block finalize
        (when (claude-code-ide--implement-todo--handle-done-line)
          (cl-return-from finalize nil))
        (when (claude-code-ide--implement-todo--handle-blank-line)
          (cl-return-from finalize nil))
        (claude-code-ide-send-prompt
         (claude-code-ide--implement-todo--build-prompt arg))))))

(defun claude-code-ide--get-selection-line-range ()
  "Return (START-LINE . END-LINE) for the active selection, or nil.
Checks evil visual state first, then falls back to `use-region-p'.
Line numbers are 1-based."
  (cond
   ;; Evil visual state
   ((and (fboundp 'evil-visual-state-p)
         (funcall #'evil-visual-state-p))
    (let* ((range (funcall #'evil-contract-range
                           (funcall #'evil-visual-range)))
           (start (nth 0 range))
           (end (nth 1 range)))
      (cons (line-number-at-pos start)
            (line-number-at-pos end))))
   ;; Regular Emacs region
   ((use-region-p)
    (let* ((start (region-beginning))
           (end (region-end))
           (end-line (line-number-at-pos end))
           ;; When region ends at column 0 of a line, the user selected
           ;; up to the end of the previous line, not into this line.
           (adjusted-end (if (and (> end start)
                                  (save-excursion
                                    (goto-char end)
                                    (bolp)))
                             (1- end-line)
                           end-line)))
      (cons (line-number-at-pos start)
            adjusted-end)))))

;;;###autoload
(defun claude-code-ide-send-current-file ()
  "Send current buffer's file path with @ prefix to the Claude Code terminal.
The path is relative to the project root.  When an evil visual
selection or Emacs region is active, appends a line range suffix
like #L12-14 (or #L12 for a single line).
When called from a Claude Code session buffer, uses the most
recent visible file-visiting buffer on the current frame."
  (interactive)
  (let ((ctx-buf (claude-code-ide--get-context-buffer)))
    (unless ctx-buf
      (user-error "Current buffer is not visiting a file"))
    (with-current-buffer ctx-buf
      (let* ((project (project-current t))
             (root (project-root project))
             (relative (file-relative-name buffer-file-name root))
             (range (claude-code-ide--get-selection-line-range))
             (suffix (cond
                      ((null range) "")
                      ((= (car range) (cdr range))
                       (format "#L%d" (car range)))
                      (t (format "#L%d-%d" (car range) (cdr range)))))
             (reference (concat "@" relative suffix " "))
             (buffer-name (claude-code-ide--get-buffer-name)))
        (if-let ((prompt-buf (claude-code-ide--prompt-buffer-send-string reference)))
            (progn
              (claude-code-ide-debug "Sent file reference to prompt buffer: %s"
                                     (string-trim reference))
              (claude-code-ide--maybe-switch-to-window prompt-buf))
          (if-let ((buffer (get-buffer buffer-name)))
              (progn
                (with-current-buffer buffer
                  (claude-code-ide--terminal-send-string reference t))
                (claude-code-ide-debug "Sent file reference to Claude Code: %s"
                                       (string-trim reference))
                (claude-code-ide--maybe-switch-to-window buffer))
            (user-error "No Claude Code session or prompt buffer for this project")))))))

;;;###autoload
(defun claude-code-ide-send-file (arg)
  "Send a project file path with @ prefix to the Claude Code terminal.
With prefix ARG, use `read-file-name' from project root instead of
`completing-read' over project files."
  (interactive "P")
  (let* ((project (project-current t))
         (root (project-root project))
         (file (if arg
                   (file-relative-name (read-file-name "File: " root) root)
                 (file-relative-name
                  (completing-read "File: " (project-files project))
                  root)))
         (reference (concat "@" file " "))
         (buffer-name (claude-code-ide--get-buffer-name)))
    (if-let ((prompt-buf (claude-code-ide--prompt-buffer-send-string reference)))
        (progn
          (claude-code-ide-debug "Sent file reference to prompt buffer: @%s" file)
          (claude-code-ide--maybe-switch-to-window prompt-buf))
      (if-let ((buffer (get-buffer buffer-name)))
          (progn
            (with-current-buffer buffer
              (claude-code-ide--terminal-send-string reference t))
            (claude-code-ide-debug "Sent file reference to Claude Code: @%s" file)
            (claude-code-ide--maybe-switch-to-window buffer))
        (user-error "No Claude Code session or prompt buffer for this project")))))

;;;###autoload
(defun claude-code-ide-send-file-from-root ()
  "Send a file path with @ prefix, browsing from project root.
Like `claude-code-ide-send-file' with prefix argument."
  (interactive)
  (claude-code-ide-send-file t))

;;;###autoload
(defun claude-code-ide-toggle ()
  "Toggle visibility of Claude Code window for the current project."
  (interactive)
  (let* ((working-dir (claude-code-ide--get-working-directory))
         (buffer-name (claude-code-ide--get-buffer-name))
         (buffer (get-buffer buffer-name)))
    (if buffer
        (claude-code-ide--toggle-existing-window buffer working-dir)
      (user-error "No Claude Code session for this project"))))

;;;###autoload
(defun claude-code-ide-toggle-recent ()
  "Toggle visibility of the most recent Claude Code window.
If any Claude window is visible, hide all of them.
If no Claude windows are visible, show the most recently accessed one."
  (interactive)
  (let ((found-visible nil))
    ;; Check all sessions and close any visible windows
    (maphash (lambda (directory _process)
               (let* ((buffer-name (funcall claude-code-ide-buffer-name-function directory))
                      (buffer (get-buffer buffer-name)))
                 (when (and buffer
                            (buffer-live-p buffer)
                            (get-buffer-window buffer))
                   ;; Window is visible, use the toggle function to close it
                   (claude-code-ide--toggle-existing-window buffer directory)
                   (setq found-visible t))))
             claude-code-ide--processes)

    (cond
     ;; We found and closed visible windows
     (found-visible
      (message "Closed all Claude Code windows"))

     ;; No windows were visible, show the most recent one
     ((and claude-code-ide--last-accessed-buffer
           (buffer-live-p claude-code-ide--last-accessed-buffer))
      (claude-code-ide--display-buffer-in-side-window claude-code-ide--last-accessed-buffer)
      (message "Opened most recent Claude Code session"))

     ;; No recent session available
     (t
      (user-error "No recent Claude Code session to toggle")))))

(provide 'claude-code-ide)

;;; claude-code-ide.el ends here
