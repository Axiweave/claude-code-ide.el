;;; claude-code-ide.el --- Claude Code integration for Emacs  -*- lexical-binding: t; -*-

;; Copyright (C) 2025 Yoav Orot
;; Copyright (C) 2026 Yu-Fu Fu

;; Author: Yoav Orot
;; Maintainer: Yu-Fu Fu <yufu@yfu.tw>
;; Version: 0.2.6
;; Package-Requires: ((emacs "28.1") (websocket "1.12") (transient "0.9.0") (web-server "0.1.2") (persist "0.6.1") (with-editor "3.4.2") (avy "0.5.0"))
;; Keywords: ai, claude, code, assistant, mcp, websocket
;; URL: https://github.com/axiweave/claude-code-ide.el

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
(require 'with-editor)
(require 'which-func)
(require 'claude-code-ide-debug)
(require 'claude-code-ide-manager)
(require 'claude-code-ide-mcp)
(require 'claude-code-ide-mcp-sse-server)
(require 'claude-code-ide-session)
(require 'claude-code-ide-session-idle)
(require 'claude-code-ide-transient)
(require 'claude-code-ide-mcp-server)
(require 'claude-code-ide-emacs-tools)
(require 'claude-code-ide-zmx)

;; External variable declarations
(defvar eat-terminal)
(defvar eat--synchronize-scroll-function)
(defvar vterm-shell)
(defvar vterm-environment)
(defvar eat-term-name)
(defvar vterm--process)
(defvar ghostel-enable-url-detection)
(defvar ghostel--term)
(defvar ghostel--term-rows)
(defvar ghostel--cursor-pos)
(defvar ghostel--cursor-char-pos)
(defvar ghostel--input-mode)
(defvar ghostel-title)

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

;; External function declarations for ghostel
(declare-function ghostel-mode "ghostel" ())
(declare-function ghostel--filter "ghostel" (process output))
(declare-function ghostel-exec "ghostel" (buffer program &optional args))
(declare-function ghostel--adjust-size "ghostel" (window &optional force))

;; External function declarations from MCP
(declare-function claude-code-ide-mcp--get-current-session "claude-code-ide-mcp" ())
(declare-function claude-code-ide-mcp--get-session "claude-code-ide-mcp" (session-id))
(declare-function claude-code-ide-mcp-session-id "claude-code-ide-mcp" (session))
(declare-function claude-code-ide-mcp-session-project-dir "claude-code-ide-mcp" (session))

;; External function declarations from Magit
(declare-function magit-file-at-point "magit" ())

;;; Customization

(defgroup claude-code-ide nil
  "Claude Code integration for Emacs."
  :group 'tools
  :prefix "claude-code-ide-")

(defconst claude-code-ide-agent-definitions
  '(("Claude Code" . "claude")
    ("Codex" . "codex")
    ("OpenCode" . "opencode")
    ("Pi" . "pi")
    ("Oh My Pi" . "omp"))
  "Official agent names mapped to their CLI command names.")

(defun claude-code-ide--agent-completion-candidates ()
  "Return display labels mapped to agent CLI command names."
  (mapcar (lambda (agent)
            (let ((name (car agent))
                  (command (cdr agent)))
              (cons (format "%s (%s)" name command) command)))
          claude-code-ide-agent-definitions))

(defun claude-code-ide--read-agent (&optional prompt initial-agent)
  "Read an agent command using PROMPT and INITIAL-AGENT as the default."
  (let* ((choices (claude-code-ide--agent-completion-candidates))
         (selection
          (completing-read (or prompt "Agent: ") choices nil t nil nil
                           (car (rassoc initial-agent choices)))))
    (cdr (assoc selection choices))))

(defvar claude-code-ide--suppress-initial-display nil
  "When non-nil, do not display a newly created session buffer immediately.

Manager-driven session switches bind this so a newly created session is only
revealed through the final restored or default layout, not in the current
layout first.")

(defun claude-code-ide--supported-agent-p (value)
  "Return non-nil when VALUE is a supported project-local agent."
  (and (stringp value)
       (member value (mapcar #'cdr claude-code-ide-agent-definitions))))

(defcustom claude-code-ide-cli-path "claude"
  "Path to the Claude Code CLI executable."
  :type 'string
  :safe #'claude-code-ide--supported-agent-p
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

(defcustom claude-code-ide-bypass-permissions-by-default t
  "Whether lowercase transient launch actions bypass permissions by default."
  :type 'boolean
  :group 'claude-code-ide)

(defcustom claude-code-ide-use-with-editor t
  "Whether new sessions use the current Emacs instance as their editor.
This makes editor commands such as C-g in Claude Code and Codex open
their prompt buffer in Emacs."
  :type 'boolean
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
  `auto' - Automatically allow all configured emacs-tools (default)
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
Can be `vterm', `eat', or `ghostel'.  The vterm backend is the
default and provides a fully-featured terminal emulator.  The eat
backend is an alternative terminal emulator that may work better
in some environments.  The ghostel backend currently has only
basic integration."
  :type '(choice (const :tag "vterm" vterm)
                 (const :tag "eat" eat)
                 (const :tag "ghostel" ghostel))
  :group 'claude-code-ide)

(defcustom claude-code-ide-cli-terminal-backends nil
  "Per-CLI terminal backend overrides.
Each entry maps `claude', `codex', `opencode', `pi', or `omp' to either `vterm'
`eat', or `ghostel'.  When a CLI has no override,
`claude-code-ide-terminal-backend' is used."
  :type '(alist :key-type (choice (const :tag "Claude" claude)
                                  (const :tag "Codex" codex)
                                  (const :tag "OpenCode" opencode)
                                  (const :tag "Pi" pi)
                                  (const :tag "Oh My Pi" omp))
                :value-type (choice (const :tag "vterm" vterm)
                                    (const :tag "eat" eat)
                                    (const :tag "ghostel" ghostel)))
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

(define-obsolete-variable-alias
  'claude-code-ide-eat-initialization-delay
  'claude-code-ide-terminal-initialization-delay
  "0.2.6")

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

(defconst claude-code-ide--temporary-prompt-buffer-regexp
  "^/\\(?:private/\\)?\\(?:tmp\\|var/folders/.*/T\\)/.*\\.\\(?:zsh\\|md\\)\\'"
  "Regexp matching transient prompt buffers opened by CLI tools.")

(defcustom claude-code-ide-prompt-buffer-patterns
  (list claude-code-ide--temporary-prompt-buffer-regexp
        "claude-prompt.*\\.md\\'"
        "\\.claude/plans/.*\\.md\\'")
  "List of regexps to identify transient prompt and plan buffers.
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

;;; Constants

(defconst claude-code-ide--active-editor-notification-delay 0.1
  "Delay in seconds before sending active editor notification after connection.")

;;; Variables

(defvar claude-code-ide--cli-available nil
  "Whether Claude Code CLI is available and detected.")

(cl-defstruct (claude-code-ide-session
               (:constructor claude-code-ide-session-create))
  id directory process buffer cli-type cli-session-id order created-at last-accessed-at custom-name title zmx-name pid host group-metadata)

(defvar claude-code-ide--sessions (make-hash-table :test #'equal)
  "Live sessions keyed by generated session ID.")

(defvar claude-code-ide--session-order-counters (make-hash-table :test #'equal)
  "Last assigned session order keyed by normalized directory.")

(defvar claude-code-ide--last-accessed-buffer nil
  "The most recently accessed Claude Code buffer.")

(defvar claude-code-ide--live-prompt-terminal-window-sync-timer nil
  "Timer used to coalesce deferred live-prompt terminal window sync passes.")

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

(defvar-local claude-code-ide--terminal-backend nil
  "Resolved terminal backend for the current session buffer.")

(defvar-local claude-code-ide--session-cli-type nil
  "Resolved CLI type for the current session buffer.")

(defun claude-code-ide--current-cli-type ()
  "Return the CLI type for the current buffer or current configuration."
  (or claude-code-ide--session-cli-type
      (claude-code-ide--configured-cli-type)))

(defun claude-code-ide--resolve-terminal-backend (&optional cli-type)
  "Resolve the terminal backend for CLI-TYPE.
Falls back to `claude-code-ide-terminal-backend' when no per-CLI
override is configured."
  (or (alist-get (or cli-type (claude-code-ide--current-cli-type))
                 claude-code-ide-cli-terminal-backends
                 nil nil #'eq)
      claude-code-ide-terminal-backend))

(defun claude-code-ide--current-terminal-backend ()
  "Return the terminal backend for the current buffer or CLI."
  (or claude-code-ide--terminal-backend
      (claude-code-ide--resolve-terminal-backend)))

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
  (if (or (not (eq (claude-code-ide--current-cli-type) 'claude))
          (not claude-code-ide-vterm-anti-flicker)
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
  (if (or (not (eq (claude-code-ide--current-cli-type) 'claude))
          (not claude-code-ide-vterm-anti-flicker)
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
  (when-let* ((buf (claude-code-ide--find-prompt-buffer)))
    (with-current-buffer buf
      (insert string)
      (let ((target-point (point)))
        (dolist (win (get-buffer-window-list buf nil t))
          (when (window-live-p win)
            (set-window-point win target-point)))))
    buf))

(defun claude-code-ide--format-insertion (body)
  "Format BODY for insertion at point.
Prepends a space unless point is at beginning of buffer or after
whitespace, and always appends a trailing space."
  (concat
   (if-let* ((prev (char-before)))
       (if (eq (char-syntax prev) ?\s) "" " ")
     "")
   body
   " "))

(defun claude-code-ide--any-visible-session-buffer ()
  "Return a live Claude Code session buffer with a window on this frame.
Returns nil if no session buffer currently has a visible window."
  (let (found)
    (maphash (lambda (_id session)
               (unless found
                 (let ((buffer (claude-code-ide-session-buffer session)))
                   (when (and buffer (buffer-live-p buffer) (get-buffer-window buffer))
                     (setq found buffer)))))
             claude-code-ide--sessions)
    found))

(defun claude-code-ide--reference-target-buffer ()
  "Return the session buffer a file reference would be sent to, or nil.
Prefers any session buffer visible on this frame, then falls back
to the project-associated session."
  (or (claude-code-ide--any-visible-session-buffer)
      (claude-code-ide--get-session-buffer)))

(defun claude-code-ide--file-reference-path (file &optional target-buffer)
  "Return FILE formatted for a reference sent to TARGET-BUFFER's session.
FILE is an absolute path.  Returns a path relative to the target
session's directory when FILE lies inside it; otherwise the absolute
path.  When the target session is unknown, falls back to the current
project root.  TARGET-BUFFER defaults to the resolved reference target."
  (let* ((target (or target-buffer (claude-code-ide--reference-target-buffer)))
         (session (and target (claude-code-ide--session-for-buffer target)))
         (root (if session
                   (claude-code-ide-session-directory session)
                 (when-let* ((project (project-current)))
                   (project-root project))))
         (relative (and root (file-relative-name file root))))
    (if (and relative (not (string-prefix-p "../" relative)))
        relative
      file)))

(defun claude-code-ide--send-reference-body (reference-body)
  "Send REFERENCE-BODY to the visible prompt buffer or session terminal.
Falls back to any session buffer visible on this frame when the
current buffer has no project-associated session, e.g. when
referencing a file that is not part of a project."
  (let ((buffer (claude-code-ide--reference-target-buffer)))
    (if-let* ((prompt-buf (claude-code-ide--find-prompt-buffer)))
        (progn
          (claude-code-ide--prompt-buffer-send-string
           (with-current-buffer prompt-buf
             (claude-code-ide--format-insertion reference-body)))
          (claude-code-ide-debug "Sent file reference to prompt buffer: %s"
                                 reference-body)
          (claude-code-ide--maybe-switch-to-window prompt-buf))
      (if buffer
          (progn
            (with-current-buffer buffer
              (claude-code-ide--terminal-send-string
               (claude-code-ide--format-insertion reference-body) t))
            (claude-code-ide-debug "Sent file reference to Claude Code: %s"
                                   reference-body)
            (claude-code-ide--maybe-switch-to-window buffer))
        (user-error "No Claude Code session or prompt buffer for this project")))))

(defun claude-code-ide--sync-terminal-dimensions (buffer window)
  "Sync terminal dimensions in BUFFER to match WINDOW size.
This ensures the terminal process has the correct dimensions after
the buffer has been displayed in its final window, which may differ
from the window where it was initially created."
  (when (and buffer window (buffer-live-p buffer) (window-live-p window))
    (with-current-buffer buffer
      (when-let* ((proc (get-buffer-process buffer)))
        (let ((height (window-body-height window))
              (width (window-body-width window)))
          (set-process-window-size proc height width))))))

;;; Terminal Reflow Glitch Prevention
;;
;; This section implements a workaround for Claude Code bug #1422
;; where terminal reflows during height-only changes can cause
;; uncontrollable scrolling. This code should be removed once
;; the upstream bug is fixed.
;; See: https://github.com/anthropics/claude-code/issues/1422

(defun claude-code-ide--terminal-resize-handler (&optional backend)
  "Retrieve the terminal's resize handling function based on backend."
  (pcase (or backend (claude-code-ide--current-terminal-backend))
    ('vterm #'vterm--window-adjust-process-window-size)
    ('eat #'eat--adjust-process-window-size)
    ('ghostel #'ghostel--adjust-size)
    (_ (error "Unsupported terminal backend: %s"
              (or backend (claude-code-ide--current-terminal-backend))))))

(defun claude-code-ide--terminal-supports-reflow-guard-p (&optional backend)
  "Return non-nil when BACKEND supports the reflow workaround hooks."
  (memq (or backend (claude-code-ide--current-terminal-backend))
        '(vterm eat ghostel)))

(defun claude-code-ide--backend-for-process (process)
  "Return the terminal backend associated with PROCESS, when known."
  (when-let* ((buffer (claude-code-ide--session-buffer-from-process process)))
    (buffer-local-value 'claude-code-ide--terminal-backend buffer)))

(defun claude-code-ide--terminal-scroll-mode-active-p ()
  "Determine if terminal is currently in scroll/copy mode."
  (pcase (claude-code-ide--current-terminal-backend)
    ('vterm (bound-and-true-p vterm-copy-mode))
    ('eat (not (bound-and-true-p eat--semi-char-mode)))
    ('ghostel (eq ghostel--input-mode 'copy))
    (_ nil)))

(defun claude-code-ide--terminal-working-resize-observer (original-fn &rest args)
  "Suppress working detection while ORIGINAL-FN resizes the session."
  (when (claude-code-ide--session-buffer-p (current-buffer))
    (claude-code-ide-session-working-suppress-after-resize
     (current-buffer)))
  (apply original-fn args))

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

(defun claude-code-ide--install-terminal-resize-observer (&optional backend)
  "Install resize observation used by working-state detection."
  (let ((handler (claude-code-ide--terminal-resize-handler backend)))
    (unless (advice-member-p #'claude-code-ide--terminal-working-resize-observer
                             handler)
      (advice-add handler :around
                  #'claude-code-ide--terminal-working-resize-observer))))

(defun claude-code-ide--remove-terminal-resize-observer (&optional backend)
  "Remove resize observation used by working-state detection."
  (advice-remove (claude-code-ide--terminal-resize-handler backend)
                 #'claude-code-ide--terminal-working-resize-observer))


;;; Helper Functions

(defun claude-code-ide--default-buffer-name (directory)
  "Generate default buffer name for DIRECTORY."
  (format "*claude-code[%s]*"
          (file-name-nondirectory (directory-file-name directory))))

(defun claude-code-ide--get-working-directory ()
  "Get the current working directory (project root or current directory)."
  (if-let* ((project (project-current)))
      (expand-file-name (project-root project))
    (expand-file-name default-directory)))

(defun claude-code-ide--get-current-directory ()
  "Get the current directory without promoting to the project root."
  (expand-file-name default-directory))

(defun claude-code-ide--get-project-root ()
  "Get the current project root.
Signal a `user-error' when the current buffer is not in a project."
  (if-let* ((project (project-current nil)))
      (expand-file-name (project-root project))
    (user-error "Not in a project")))

(defun claude-code-ide--normalize-directory (directory)
  "Return DIRECTORY as a normalized absolute directory name."
  (when directory
    (file-name-as-directory (expand-file-name directory))))

(defun claude-code-ide--project-key (directory &optional host)
  "Return the project identity for DIRECTORY on HOST.
Keep remote directory text unchanged.  Normalize local directories."
  (if host (cons host directory)
    (claude-code-ide--normalize-directory directory)))

(defun claude-code-ide--path-basename (path)
  "Return PATH's final slash-separated component as plain text.
Never consults `file-name-handler-alist'; safe for remote directory
text that is metadata rather than a local filesystem instruction."
  (car (last (split-string path "/" t))))

(defun claude-code-ide--put-session (session)
  "Store SESSION by its generated ID and return it."
  (puthash (claude-code-ide-session-id session) session
           claude-code-ide--sessions)
  session)

(defun claude-code-ide--get-session (session-id)
  "Return the live session identified by SESSION-ID, or nil."
  (gethash session-id claude-code-ide--sessions))

(defun claude-code-ide--set-session-custom-name (session name)
  "Store canonical custom NAME on SESSION and return SESSION."
  (setf (claude-code-ide-session-custom-name session) name)
  session)

(defun claude-code-ide--set-session-group-metadata (session metadata)
  "Store METADATA plist on SESSION and return SESSION."
  (setf (claude-code-ide-session-group-metadata session) metadata)
  session)

(defun claude-code-ide--session-for-buffer (&optional buffer)
  "Return the live session that owns BUFFER, or nil."
  (let ((buffer (or buffer (current-buffer)))
        found)
    (maphash
     (lambda (_session-id session)
       (when (eq buffer
                 (or (and (buffer-live-p (claude-code-ide-session-buffer session))
                          (claude-code-ide-session-buffer session))
                     (claude-code-ide--session-buffer-from-process
                      (claude-code-ide-session-process session))))
         (setq found session)))
     claude-code-ide--sessions)
    found))

(defun claude-code-ide-session-for-buffer (&optional buffer)
  "Return the Session that owns BUFFER, or nil.
BUFFER defaults to the current buffer.  This is the supported entry
point for code outside this package; it wraps
`claude-code-ide--session-for-buffer' and makes no remote call."
  (claude-code-ide--session-for-buffer buffer))

(defun claude-code-ide-recent-session ()
  "Return the live Session with the newest access time, or nil.
This is the supported entry point for code outside this package when
no buffer or window identifies a Session, for example a temporary
prompt buffer that an Agent opened.  It reads the same
`last-accessed-at' the manager sorts by and makes no remote call."
  (let (recent)
    (maphash
     (lambda (_session-id session)
       (when (and (buffer-live-p (claude-code-ide-session-buffer session))
                  (or (null recent)
                      (> (or (claude-code-ide-session-last-accessed-at session) 0)
                         (or (claude-code-ide-session-last-accessed-at recent) 0))))
         (setq recent session)))
     claude-code-ide--sessions)
    recent))

(defun claude-code-ide--session-buffer-for-agent (zmx-name buffer-name)
  "Return the live session buffer identified by ZMX-NAME or BUFFER-NAME.
ZMX-NAME wins because it survives Emacs restarts.  BUFFER-NAME covers
sessions that run without zmx.  A remote session's zmx name or buffer
name never associates local MCP state.  Return nil when neither
matches."
  (let (found)
    (when zmx-name
      (maphash (lambda (_id session)
                 (when (and (not found)
                            (not (claude-code-ide-session-host session))
                            (equal (claude-code-ide-session-zmx-name session) zmx-name))
                   (setq found (claude-code-ide-session-buffer session))))
               claude-code-ide--sessions))
    (unless found
      (let* ((buffer (and buffer-name (get-buffer buffer-name)))
             (session (and buffer (claude-code-ide--session-for-buffer buffer))))
        (when (and session (not (claude-code-ide-session-host session)))
          (setq found buffer))))
    (and (buffer-live-p found) found)))


(defun claude-code-ide--record-ghostel-title (&rest _args)
  "Store the current Ghostel title on its live session.
For a local zmx-backed session, mirror a changed title to a zmx
`title' label so `zmx list' shows it in terminals.  A remote
session's title stays local and never contacts either side's zmx."
  (when-let* ((session (claude-code-ide--session-for-buffer)))
    (let ((old (claude-code-ide-session-title session)))
      (setf (claude-code-ide-session-title session) ghostel-title)
      (when-let* ((zmx-name (and (not (claude-code-ide-session-host session))
                                 (claude-code-ide-session-zmx-name session))))
        (unless (equal (claude-code-ide-zmx--title-value ghostel-title)
                       (claude-code-ide-zmx--title-value old))
          (claude-code-ide-zmx-set-title zmx-name ghostel-title))))))

(defun claude-code-ide--install-ghostel-title-observer ()
  "Install the Ghostel title observer once."
  (when (and (fboundp 'ghostel--set-title)
             (not (advice-member-p #'claude-code-ide--record-ghostel-title
                                   'ghostel--set-title)))
    (advice-add 'ghostel--set-title :after
                #'claude-code-ide--record-ghostel-title)))

(with-eval-after-load 'ghostel
  (claude-code-ide--install-ghostel-title-observer))
(defun claude-code-ide--touch-session-for-buffer (&optional buffer)
  "Mark BUFFER's exact live session as recently accessed."
  (when-let* ((session (claude-code-ide--session-for-buffer buffer)))
    (claude-code-ide--touch-session (claude-code-ide-session-id session))))

(defun claude-code-ide--next-session-order (directory &optional host)
  "Return the next never-reused positive session order for DIRECTORY.
HOST distinguishes a remote project from a local one with the same
directory text; see `claude-code-ide--project-key'."
  (let* ((key (claude-code-ide--project-key directory host))
         (last-order (gethash key claude-code-ide--session-order-counters 0))
         (live-order
          (cl-loop for session being the hash-values of claude-code-ide--sessions
                   when (equal key
                               (claude-code-ide--project-key
                                (claude-code-ide-session-directory session)
                                (claude-code-ide-session-host session)))
                   maximize (or (claude-code-ide-session-order session) 0) into maximum
                   finally return (or maximum 0)))
         (next-order (1+ (max last-order live-order))))
    (puthash key next-order claude-code-ide--session-order-counters)
    next-order))

(defun claude-code-ide--sessions-for-directory (directory &optional host)
  "Return live sessions for DIRECTORY on HOST, most recently accessed first.
HOST distinguishes a remote project from a local one with the same
directory text; see `claude-code-ide--project-key'."
  (let ((key (claude-code-ide--project-key directory host)) sessions)
    (maphash (lambda (session-id _)
               (let ((session (claude-code-ide--get-session session-id)))
                 (when (equal key
                              (claude-code-ide--project-key
                               (claude-code-ide-session-directory session)
                               (claude-code-ide-session-host session)))
                   (push session sessions))))
             claude-code-ide--sessions)
    (sort sessions (lambda (a b)
                     (> (or (claude-code-ide-session-last-accessed-at a) 0)
                        (or (claude-code-ide-session-last-accessed-at b) 0))))))

(defun claude-code-ide--preferred-session (directory)
  "Return the preferred live session for DIRECTORY, or nil."
  (car (claude-code-ide--sessions-for-directory directory)))

(defun claude-code-ide--touch-session (session-id)
  "Mark SESSION-ID as most recently accessed and return its session."
  (when-let* ((session (claude-code-ide--get-session session-id)))
    (setf (claude-code-ide-session-last-accessed-at session) (float-time))
    session))

(defun claude-code-ide--directory-contains-p (parent child)
  "Return non-nil when PARENT contains CHILD."
  (let ((parent (claude-code-ide--normalize-directory parent))
        (child (claude-code-ide--normalize-directory child)))
    (and parent child
         (string-prefix-p parent child))))

(defun claude-code-ide--directory-related-p (directory other-directory)
  "Return non-nil when DIRECTORY and OTHER-DIRECTORY are in the same tree."
  (or (claude-code-ide--directory-contains-p directory other-directory)
      (claude-code-ide--directory-contains-p other-directory directory)))

(defun claude-code-ide--sort-directories-by-specificity (directories)
  "Return DIRECTORIES sorted from most specific to least specific."
  (sort (copy-sequence directories)
        (lambda (left right)
          (> (length (claude-code-ide--normalize-directory left))
             (length (claude-code-ide--normalize-directory right))))))

(defun claude-code-ide--get-related-session-directories (&optional directory)
  "Return active local session directories related to DIRECTORY or the current dir.
A remote session is excluded: its directory is opaque host metadata,
never a local path to compare against another directory."
  (let ((directory (claude-code-ide--normalize-directory
                    (or directory (claude-code-ide--get-current-directory))))
        (matches '()))
    (when directory
      (maphash (lambda (session-id _)
                 (let ((session (claude-code-ide--get-session session-id)))
                   (unless (claude-code-ide-session-host session)
                     (let ((session-directory (claude-code-ide-session-directory session)))
                       (when (claude-code-ide--directory-related-p
                              directory session-directory)
                         (push session-directory matches))))))
               claude-code-ide--sessions)
      (claude-code-ide--sort-directories-by-specificity
       (delete-dups matches)))))

(defun claude-code-ide--get-related-sessions (&optional directory)
  "Return live local sessions related to DIRECTORY or the current directory.
A remote session is excluded; see
`claude-code-ide--get-related-session-directories'."
  (let ((directory (claude-code-ide--normalize-directory
                    (or directory (claude-code-ide--get-current-directory))))
        matches)
    (when directory
      (maphash
       (lambda (_session-id session)
         (when (and (not (claude-code-ide-session-host session))
                    (buffer-live-p (claude-code-ide-session-buffer session))
                    (claude-code-ide--directory-related-p
                     directory (claude-code-ide-session-directory session)))
           (push session matches)))
       claude-code-ide--sessions)
      (sort matches
            (lambda (left right)
              (let ((left-directory
                     (claude-code-ide--normalize-directory
                      (claude-code-ide-session-directory left)))
                    (right-directory
                     (claude-code-ide--normalize-directory
                      (claude-code-ide-session-directory right))))
                (if (equal left-directory right-directory)
                    (> (or (claude-code-ide-session-last-accessed-at left) 0)
                       (or (claude-code-ide-session-last-accessed-at right) 0))
                  (> (length left-directory) (length right-directory)))))))))

(defun claude-code-ide--get-attached-working-directory (&optional fallback-directory)
  "Return the active session directory attached to the current buffer.
When no attached session exists, use FALLBACK-DIRECTORY or the default
project-aware working directory."
  (or (when-let* ((session (claude-code-ide-mcp--get-current-session)))
        (claude-code-ide-mcp-session-project-dir session))
      fallback-directory
      (claude-code-ide--get-working-directory)))

(defun claude-code-ide--get-buffer-name (&optional directory)
  "Get the buffer name for the Claude Code session in DIRECTORY.
If DIRECTORY is not provided, use the current working directory."
  (funcall claude-code-ide-buffer-name-function
           (or directory (claude-code-ide--get-working-directory))))

(defun claude-code-ide--get-session-buffer (&optional directory)
  "Return the Claude session buffer for DIRECTORY or the attached session."
  (let ((attached-directory (or directory
                                (when-let* ((session (claude-code-ide-mcp--get-current-session)))
                                  (claude-code-ide-mcp-session-project-dir session))))
        (fallback-directory (or directory
                                (claude-code-ide--get-working-directory))))
    (or (when-let* ((session (and (null directory)
                                  (claude-code-ide--session-for-buffer))))
          (or (and (buffer-live-p (claude-code-ide-session-buffer session))
                   (claude-code-ide-session-buffer session))
              (claude-code-ide--session-buffer-from-process
               (claude-code-ide-session-process session))))
        (when-let* ((session (and attached-directory
                                  (claude-code-ide--preferred-session
                                   attached-directory))))
          (or (and (buffer-live-p (claude-code-ide-session-buffer session))
                   (claude-code-ide-session-buffer session))
              (claude-code-ide--session-buffer-from-process
               (claude-code-ide-session-process session))))
        (when-let* ((session (claude-code-ide--preferred-session
                              fallback-directory)))
          (or (and (buffer-live-p (claude-code-ide-session-buffer session))
                   (claude-code-ide-session-buffer session))
              (claude-code-ide--session-buffer-from-process
               (claude-code-ide-session-process session))))
        (get-buffer (if attached-directory
                        (claude-code-ide--get-buffer-name attached-directory)
                      (claude-code-ide--get-buffer-name))))))

(defun claude-code-ide--maybe-switch-to-window (buffer)
  "Select BUFFER's window if `claude-code-ide-switch-after-send' is non-nil.
Only switches if BUFFER has a visible window.  Does nothing if the
variable is nil or the buffer has no visible window."
  (when claude-code-ide-switch-after-send
    (when-let* ((win (get-buffer-window buffer)))
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

(defun claude-code-ide--treemacs-path-at-point ()
  "Return the Treemacs file path at point, or nil when unavailable."
  (when (and (fboundp 'treemacs-current-button)
             (fboundp 'treemacs-safe-button-get))
    (when-let* ((path (if (macrop 'treemacs-safe-button-get)
                          (eval '(treemacs-safe-button-get (treemacs-current-button) :path))
                        (treemacs-safe-button-get (treemacs-current-button) :path)))
                ((stringp path)))
      path)))

(defun claude-code-ide--get-file-reference-context ()
  "Return a `(FILE . BUFFER)' pair for `claude-code-ide-send-current-file'.
FILE is the absolute file path to reference.  BUFFER is the source
buffer to inspect for an active line selection, or nil when no line
range should be attached."
  (cond
   (buffer-file-name
    (cons buffer-file-name (current-buffer)))
   ((and (derived-mode-p 'dired-mode)
         (fboundp 'dired-get-filename))
    (when-let* ((path (dired-get-filename nil t)))
      (cons path nil)))
   ((and (derived-mode-p 'magit-status-mode)
         (fboundp 'magit-file-at-point))
    (when-let* ((path (magit-file-at-point)))
      (cons path nil)))
   ((derived-mode-p 'treemacs-mode)
    (when-let* ((path (claude-code-ide--treemacs-path-at-point)))
      (cons path nil)))
   ((claude-code-ide--session-buffer-p (current-buffer))
    (when-let* ((ctx-buf (claude-code-ide--get-context-buffer)))
      (with-current-buffer ctx-buf
        (when buffer-file-name
          (cons buffer-file-name ctx-buf)))))))

(defun claude-code-ide--session-buffer-from-process (process)
  "Return the live session buffer attached to PROCESS, if any."
  (cond
   ((bufferp process)
    (and (buffer-live-p process) process))
   ((processp process)
    (when-let* ((buffer (process-buffer process)))
      (and (buffer-live-p buffer) buffer)))))

(defun claude-code-ide--register-session (session)
  "Register SESSION and install global advice for the first live session."
  (let* ((process (claude-code-ide-session-process session))
         (backend (claude-code-ide--backend-for-process process))
         (buffer (or (and (buffer-live-p (claude-code-ide-session-buffer session))
                          (claude-code-ide-session-buffer session))
                     (claude-code-ide--session-buffer-from-process process))))
    (when (= (hash-table-count claude-code-ide--sessions) 0)
      (claude-code-ide--install-terminal-resize-observer backend)
      (when (and (eq (claude-code-ide--current-cli-type) 'claude)
                 claude-code-ide-prevent-reflow-glitch
                 (claude-code-ide--terminal-supports-reflow-guard-p backend))
        ;; Apply advice globally for the first Claude session when enabled.
        (advice-add (claude-code-ide--terminal-resize-handler backend)
                    :around #'claude-code-ide--terminal-reflow-filter)))
    (prog1 (claude-code-ide--put-session session)
      (when buffer
        (with-current-buffer buffer
          (when (eq claude-code-ide--terminal-backend 'ghostel)
            (claude-code-ide--record-ghostel-title))))
      (claude-code-ide-manager-refresh-all))))

(defun claude-code-ide--cleanup-dead-processes ()
  "Clean up live-session entries whose processes have exited."
  (dolist (session-id (hash-table-keys claude-code-ide--sessions))
    (when-let* ((session (claude-code-ide--get-session session-id)))
      (unless (process-live-p (claude-code-ide-session-process session))
        (claude-code-ide--cleanup-on-exit session-id)))))

(defun claude-code-ide--cleanup-all-sessions ()
  "Clean up all active Claude Code sessions."
  (dolist (session-id (hash-table-keys claude-code-ide--sessions))
    (when-let* ((session (claude-code-ide--get-session session-id)))
      (when (process-live-p (claude-code-ide-session-process session))
        (claude-code-ide--cleanup-on-exit session-id)))))

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

(defun claude-code-ide--show-session-buffer (buffer)
  "Show session BUFFER, reusing an existing visible Claude window when possible."
  (or (when-let* ((window (get-buffer-window buffer)))
        (when claude-code-ide-focus-on-open
          (select-window window))
        window)
      (when-let* ((window (cl-loop for win in (window-list nil 'no-minibuffer)
                                   for win-buffer = (window-buffer win)
                                   when (claude-code-ide--session-buffer-p win-buffer)
                                   return win)))
        (set-window-buffer window buffer)
        (setq claude-code-ide--last-accessed-buffer buffer)
        (claude-code-ide--sync-terminal-dimensions buffer window)
        (when claude-code-ide-focus-on-open
          (select-window window))
        window)
      (claude-code-ide--display-buffer-in-side-window buffer)))

(defun claude-code-ide--close-session-windows (buffer)
  "Close every window showing session BUFFER, on any frame.
Killing BUFFER alone leaves an ordinary window alive showing an unrelated
buffer, while a side window is deleted; this makes both layouts behave the
same.  Emacs refuses to delete a frame's sole main window, and that window
keeps whatever buffer the following kill puts in it."
  (dolist (window (get-buffer-window-list buffer 'no-minibuf t))
    (when (window-live-p window)
      (ignore-errors (delete-window window)))))

(defun claude-code-ide--cleanup-session-resources (session &optional keep-buffer disposition)
  "Clean up resources owned by SESSION after it leaves the live-session table.
When KEEP-BUFFER is non-nil, let the active buffer kill finish.
DISPOSITION `verified-stop' means a Stop transport already confirmed
the remote target is gone: skip remembering a disconnected manager row
and leave the manager row's own finalization to the caller instead of
notifying it here."
  (let* ((session-id (claude-code-ide-session-id session))
         (directory (claude-code-ide-session-directory session))
         (process (claude-code-ide-session-process session))
         (buffer (claude-code-ide-session-buffer session))
         (cli-type (claude-code-ide-session-cli-type session))
         (host (claude-code-ide-session-host session))
         (backend (claude-code-ide--backend-for-process process)))
    (when (= (hash-table-count claude-code-ide--sessions) 0)
      (claude-code-ide--remove-terminal-resize-observer backend)
      (when (and claude-code-ide-prevent-reflow-glitch
                 (claude-code-ide--terminal-supports-reflow-guard-p backend))
        (advice-remove (claude-code-ide--terminal-resize-handler backend)
                       #'claude-code-ide--terminal-reflow-filter)))
    (when (and claude-code-ide-vterm-anti-flicker
               (= (hash-table-count claude-code-ide--sessions) 0))
      (advice-remove 'vterm--filter #'claude-code-ide--vterm-smart-renderer)
      (advice-remove 'eat--filter #'claude-code-ide--eat-smart-renderer))
    (when (and (eq cli-type 'claude) (not host))
      (claude-code-ide-mcp-stop-session session-id)
      (claude-code-ide-mcp-server-session-ended session-id))
    (unless (eq disposition 'verified-stop)
      (claude-code-ide-manager-session-ended session-id))
    (when (buffer-live-p buffer)
      (when (claude-code-ide-session-buffer-p buffer)
        (with-current-buffer buffer
          (claude-code-ide-session-idle-disable)
          (claude-code-ide-session-tracking--clear-timer)))
      (claude-code-ide--close-session-windows buffer)
      (unless keep-buffer
        (let ((kill-buffer-query-functions nil))
          (kill-buffer buffer))))
    (claude-code-ide-debug "Cleaned up Claude Code session for %s"
                           (claude-code-ide--path-basename directory))))

(defun claude-code-ide--cleanup-on-exit (session-id &optional keep-buffer expected-process disposition)
  "Remove SESSION-ID and clean up only the resources it owns.
The buffer kill hook passes KEEP-BUFFER to prevent a recursive buffer
kill.  EXPECTED-PROCESS is the process a sentinel or kill hook
captured when it was installed; when given, cleanup runs only if it
still matches SESSION-ID's current process, so a stale callback from a
replaced or already-finished attach process cannot tear down a session
it no longer owns.  DISPOSITION reaches
`claude-code-ide--cleanup-session-resources'."
  (save-current-buffer
    (when-let* ((session (claude-code-ide--get-session session-id)))
      (when (or (null expected-process)
                (eq expected-process (claude-code-ide-session-process session)))
        (when (and (claude-code-ide-session-host session)
                   (not (eq disposition 'verified-stop)))
          (claude-code-ide-manager--remember-remote-session session))
        ;; Removing first is the ID-scoped recursion guard for sentinel/hook races.
        (remhash session-id claude-code-ide--sessions)
        (apply #'claude-code-ide--cleanup-session-resources session keep-buffer
               (and disposition (list disposition)))))))

;;; CLI Detection

(defun claude-code-ide--cli-type-for-command (command)
  "Return the CLI type symbol for COMMAND's basename.
Returns \\='claude, \\='codex, \\='opencode, \\='pi, or \\='omp based on the
basename prefix.  Unknown commands fall back to \\='claude."
  (let ((basename (file-name-nondirectory command)))
    (cond
     ((string-prefix-p "opencode" basename) 'opencode)
     ((string-prefix-p "omp" basename) 'omp)
     ((string-prefix-p "pi" basename) 'pi)
     ((string-prefix-p "code" basename) 'codex)
     (t 'claude))))

(defun claude-code-ide--configured-cli-type ()
  "Detect CLI type from `claude-code-ide-cli-path'."
  (claude-code-ide--cli-type-for-command claude-code-ide-cli-path))

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

(defun claude-code-ide--toggle-existing-window (existing-buffer _working-dir)
  "Toggle visibility of EXISTING-BUFFER window.
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
        (when-let* ((live-session (claude-code-ide--session-for-buffer existing-buffer))
                    (session (claude-code-ide-mcp--get-session
                              (claude-code-ide-session-id live-session))))
          (when (fboundp 'tab-bar--current-tab)
            (setf (claude-code-ide-mcp-session-original-tab session) (tab-bar--current-tab))))
        (claude-code-ide-debug "Claude Code window shown")))))

(defun claude-code-ide--build-claude-command (&optional continue resume session-id)
  "Build the Claude command with optional flags.
If CONTINUE is non-nil, add the -c flag.
If RESUME is non-nil, add the -r flag.
If SESSION-ID is provided, it's included in the MCP server URL path.
If `claude-code-ide-cli-debug' is non-nil, add the -d flag.
If `claude-code-ide-system-prompt' is non-nil, add --append-system-prompt.
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
      (when-let* ((config (claude-code-ide-mcp-server-get-config session-id)))
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

(defun claude-code-ide--build-opencode-command (&optional continue resume _session-id)
  "Build the OpenCode command with optional flags.
If CONTINUE is non-nil, use `opencode --continue'.
If RESUME is non-nil, use `opencode --continue' (same behavior).
_SESSION-ID is unused (no MCP for opencode).
Additional flags from `claude-code-ide-cli-extra-flags' are included."
  (let ((opencode-cmd claude-code-ide-cli-path))
    ;; OpenCode uses --continue / -c for resuming the last session
    (when (or continue resume)
      (setq opencode-cmd (concat opencode-cmd " --continue")))
    ;; Add any extra flags
    (when (and claude-code-ide-cli-extra-flags
               (not (string-empty-p claude-code-ide-cli-extra-flags)))
      (setq opencode-cmd (concat opencode-cmd " " claude-code-ide-cli-extra-flags)))
    opencode-cmd))

(defun claude-code-ide--build-pi-command (&optional continue resume _session-id)
  "Build the Pi or Oh My Pi command with optional flags."
  (let ((pi-cmd claude-code-ide-cli-path))
    (cond (continue (setq pi-cmd (concat pi-cmd " --continue")))
          (resume (setq pi-cmd (concat pi-cmd " --resume"))))
    (when (and claude-code-ide-cli-extra-flags
               (not (string-empty-p claude-code-ide-cli-extra-flags)))
      (setq pi-cmd (concat pi-cmd " " claude-code-ide-cli-extra-flags)))
    pi-cmd))

(defun claude-code-ide--build-command (&optional continue resume session-id)
  "Build CLI command, dispatching by CLI type.
Arguments CONTINUE, RESUME, SESSION-ID are passed to the CLI-specific builder."
  (pcase (claude-code-ide--current-cli-type)
    ('opencode (claude-code-ide--build-opencode-command continue resume session-id))
    ((or 'pi 'omp) (claude-code-ide--build-pi-command continue resume session-id))
    ('codex (claude-code-ide--build-codex-command continue resume session-id))
    (_ (claude-code-ide--build-claude-command continue resume session-id))))

(defun claude-code-ide--live-prompt-bottom-margin ()
  "Return the bottom margin, in lines, for the current CLI's live prompt.
Codex renders a multi-line prompt block (input line plus hints) whose
cursor sits above the last terminal row, so the pinned view needs room
below the cursor.  Oh My Pi and the other CLIs keep the cursor on the
bottom line and need no extra room."
  (if (eq (claude-code-ide--current-cli-type) 'codex)
      4
    1))

(defun claude-code-ide--terminal-position-keeper (window-list)
  "Maintain stable terminal view position across window switches.
WINDOW-LIST contains windows requiring position synchronization.
Implements intelligent scroll management to preserve user context
when navigating between terminal and other buffers."
  (let* ((terminal-point (eat-term-display-cursor eat-terminal))
         (visible-windows (get-buffer-window-list (current-buffer) nil t))
         (sync-windows (cl-remove-duplicates
                        (append (delq 'buffer (copy-sequence window-list))
                                visible-windows)
                        :test #'eq))
         (recenter-line (- (claude-code-ide--live-prompt-bottom-margin))))
    (when (memq 'buffer window-list)
      (goto-char terminal-point))
    (unless buffer-read-only         ; Skip when terminal is in navigation mode
      (dolist (win sync-windows)
        (when (window-live-p win)
          (with-selected-window win
            (when (evil-emacs-state-p)
              (set-window-point win terminal-point)
              (goto-char terminal-point)
              (recenter recenter-line))))))))

(defun claude-code-ide--live-prompt-cli-p ()
  "Return non-nil when the current CLI keeps a live prompt at the terminal bottom.
Codex and Oh My Pi render a persistent bottom input prompt whose live
cursor position must be tracked to keep the window pinned after layout
restores."
  (memq (claude-code-ide--current-cli-type) '(codex omp)))

(defun claude-code-ide--omp-visible-prompt-start (cursor)
  "Return OMP's first visible input position before CURSOR.
Scan at most 18 physical rows for the nearest known prompt gutter.
Stop at a preceding composer border or rule.  Return CURSOR when the
visible prompt has no usable marker."
  (save-excursion
    (goto-char cursor)
    (catch 'prompt-start
      (dotimes (_ 18 cursor)
        (beginning-of-line)
        (cond
         ((looking-at "\\(?:❯ \\|╰─ \\)")
          (throw 'prompt-start (match-end 0)))
         ((looking-at "\\(?:[╭┌]─\\|─+\\)")
          (throw 'prompt-start cursor)))
        (forward-line -1)))))

(defun claude-code-ide-move-to-omp-visible-prompt-start ()
  "Move point to OMP's first visible prompt input position."
  (interactive)
  (goto-char
   (claude-code-ide--omp-visible-prompt-start
    (claude-code-ide--live-prompt-terminal-window-target-point))))

(defun claude-code-ide--live-prompt-terminal-window-target-point ()
  "Return the live prompt position for the current live-prompt terminal buffer."
  (pcase (claude-code-ide--current-terminal-backend)
    ('eat
     (if (and (bound-and-true-p eat-terminal)
              (fboundp 'eat-term-display-cursor))
         (eat-term-display-cursor eat-terminal)
       (point-max)))
    ('ghostel
     (cond
      ;; The native renderer publishes the exact cursor buffer position;
      ;; prefer it over the viewport-coordinate approximation below.
      ((and (bound-and-true-p ghostel--term)
            (bound-and-true-p ghostel--cursor-char-pos)
            (<= (point-min) ghostel--cursor-char-pos)
            (<= ghostel--cursor-char-pos (point-max)))
       ghostel--cursor-char-pos)
      ((and (bound-and-true-p ghostel--term)
            (bound-and-true-p ghostel--term-rows)
            ghostel--cursor-pos)
       (save-excursion
         (let ((scrollback (max 0 (- (line-number-at-pos (point-max))
                                     ghostel--term-rows))))
           (goto-char (point-min))
           (forward-line (+ scrollback (cdr ghostel--cursor-pos)))
           (move-to-column (car ghostel--cursor-pos))
           (point))))
      (t (point-max))))
    (_ (point-max))))

(defun claude-code-ide--window-start-for-point-near-bottom (win point &optional bottom-margin)
  "Return a `window-start' that shows POINT near the bottom of WIN.
BOTTOM-MARGIN defaults to 4 lines, matching the Codex live-prompt
layout.  Callers pass the per-CLI margin from
`claude-code-ide--live-prompt-bottom-margin'."
  (save-excursion
    (goto-char point)
    (forward-line (- (max 0 (- (window-body-height win) (or bottom-margin 4) 1))))
    (line-beginning-position)))

(defun claude-code-ide--sync-visible-live-prompt-terminal-windows ()
  "Keep visible live-prompt terminal windows pinned to the live prompt.
Perspective/window-state restores can resurrect stale `window-point' values
without any terminal output event, so synchronize visible live-prompt terminal
windows after window configuration changes."
  (dolist (win (window-list nil 'no-minibuf))
    (when-let* ((buffer (window-buffer win)))
      (when (and (window-live-p win)
                 (claude-code-ide--session-buffer-p buffer))
        (with-current-buffer buffer
          (when (and (claude-code-ide--live-prompt-cli-p)
                     (memq (claude-code-ide--current-terminal-backend)
                           '(vterm eat ghostel))
                     (or (not (fboundp 'evil-emacs-state-p))
                         (evil-emacs-state-p)))
            (let ((target-point
                   (claude-code-ide--live-prompt-terminal-window-target-point))
                  (backend (claude-code-ide--current-terminal-backend))
                  (bottom-margin (claude-code-ide--live-prompt-bottom-margin)))
              (with-selected-window win
                (set-window-point win target-point)
                (goto-char target-point)
                (cond
                 ((eq backend 'ghostel)
                  (unless (pos-visible-in-window-p target-point win)
                    (set-window-start
                     win
                     (claude-code-ide--window-start-for-point-near-bottom
                      win target-point bottom-margin)
                     t)))
                 (t
                  (recenter (- bottom-margin))))))))))))

(defun claude-code-ide--run-live-prompt-terminal-window-sync ()
  "Run the deferred live-prompt terminal window sync pass."
  (setq claude-code-ide--live-prompt-terminal-window-sync-timer nil)
  (claude-code-ide--sync-visible-live-prompt-terminal-windows))

(defun claude-code-ide--schedule-live-prompt-terminal-window-sync ()
  "Sync live-prompt terminal windows now and queue one deferred follow-up pass.
Some popup and minibuffer flows restore stale window state after
`window-configuration-change-hook' has already run.  The deferred
pass corrects those late restores without waiting for terminal output."
  (claude-code-ide--sync-visible-live-prompt-terminal-windows)
  (when claude-code-ide--live-prompt-terminal-window-sync-timer
    (cancel-timer claude-code-ide--live-prompt-terminal-window-sync-timer))
  (setq claude-code-ide--live-prompt-terminal-window-sync-timer
        (run-at-time 0 nil #'claude-code-ide--run-live-prompt-terminal-window-sync)))

(defun claude-code-ide--install-live-prompt-terminal-window-sync ()
  "Install hooks that keep live-prompt terminal windows at the live prompt."
  (unless (memq #'claude-code-ide--schedule-live-prompt-terminal-window-sync
                window-configuration-change-hook)
    (add-hook 'window-configuration-change-hook
              #'claude-code-ide--schedule-live-prompt-terminal-window-sync)))

(claude-code-ide--install-live-prompt-terminal-window-sync)

(defun claude-code-ide--parse-command-string (command-string)
  "Parse a command string into (program . args) for eat-exec.
COMMAND-STRING is a shell command line to parse.
Returns a cons cell (program . args) where program is the executable
and args is a list of arguments."
  (let ((parts (split-string-shell-command command-string)))
    (cons (car parts) (cdr parts))))


(defvar claude-code-ide--pending-remote-host nil
  "Host for the remote session buffer being created, or nil for local.
Let-bound around terminal creation so setup hooks running during
buffer configuration can see the pending host before the new Session
is registered.")

(defun claude-code-ide--create-terminal-with-command (buffer-name working-dir cmd env-vars)
  "Create a terminal buffer running CMD with ENV-VARS.
BUFFER-NAME is the name for the terminal buffer.
WORKING-DIR is the working directory.
CMD is the shell command string to run.
ENV-VARS is a list of \"KEY=VALUE\" environment variable strings.

Returns a cons cell of (buffer . process) on success.
Signals an error if terminal fails to initialize."
  (when (and claude-code-ide-zmx--pending-name
             (not claude-code-ide--pending-remote-host))
    (setq cmd (claude-code-ide-zmx-wrap-command
               claude-code-ide-zmx--pending-name
               (unless claude-code-ide-zmx--pending-attach-only cmd))))
  (let* ((cli-type (claude-code-ide--current-cli-type))
         (backend (claude-code-ide--resolve-terminal-backend cli-type)))
    (claude-code-ide--terminal-ensure-backend)
    (let ((default-directory working-dir))
      (claude-code-ide-debug "Starting with command: %s" cmd)
      (claude-code-ide-debug "Working directory: %s" working-dir)
      (claude-code-ide-debug "Terminal backend: %s" backend)

      (cond
       ;; vterm backend
       ((eq backend 'vterm)
        (let* ((vterm-buffer-name buffer-name)
               (vterm-shell cmd)
               (vterm-environment (append env-vars vterm-environment)))
          (let ((buffer (save-window-excursion
                          (vterm vterm-buffer-name))))
            (unless buffer
              (error "Failed to create vterm buffer.  Please ensure vterm is properly installed and compiled"))
            (with-current-buffer buffer
              (setq-local claude-code-ide--session-cli-type cli-type)
              (setq-local claude-code-ide--terminal-backend backend)
              (claude-code-ide-session-mode 1)
              (claude-code-ide-session-setup-buffer))
            (let ((process (get-buffer-process buffer)))
              (unless process
                (error "Failed to get vterm process.  The vterm module may not be compiled correctly"))
              (unless (buffer-live-p buffer)
                (error "Vterm buffer was killed during initialization"))
              (cons buffer process)))))

       ;; eat backend
       ((eq backend 'eat)
        (let* ((buffer (get-buffer-create buffer-name))
               ;; (eat-term-name "xterm-256color")
               (cmd-parts (claude-code-ide--parse-command-string cmd))
               (program (car cmd-parts))
               (args (cdr cmd-parts)))
          (with-current-buffer buffer
            (setq-local claude-code-ide--session-cli-type cli-type)
            (setq-local claude-code-ide--terminal-backend backend)
            (unless (eq major-mode 'eat-mode)
              (eat-mode))
            (claude-code-ide-session-mode 1)
            (claude-code-ide-session-setup-buffer)
            (when (and claude-code-ide-eat-preserve-position
                       ;; (eq (claude-code-ide--current-cli-type) 'claude)
                       (not (eq (claude-code-ide--current-cli-type) 'opencode))
                       )
              (setq-local eat--synchronize-scroll-function
                          #'claude-code-ide--terminal-position-keeper))
            (setq-local process-environment
                        (append env-vars process-environment))
            (eat-exec buffer buffer-name program nil args)
            (let ((process (get-buffer-process buffer)))
              (unless process
                (error "Failed to create eat process.  Please ensure eat is properly installed"))
              (cons buffer process)))))

       ;; ghostel backend
       ((eq backend 'ghostel)
        (let* ((buffer (get-buffer-create buffer-name))
               (program (or shell-file-name "/bin/sh"))
               (args (list "-lc" cmd))
               (process-environment (append env-vars process-environment))
               process)
          (with-current-buffer buffer
            ;; Ghostel may emit an OSC title very early in startup.
            ;; v0.50.0's default `ghostel-buffer-name-function' nil already
            ;; keeps buffer names stable; no title hook is set here.
            (setq-local ghostel-enable-url-detection nil))
          (setq process (ghostel-exec buffer program args))
          (unless process
            (error "Failed to create ghostel process.  Please ensure ghostel is properly installed"))
          (with-current-buffer buffer
            (setq-local claude-code-ide--session-cli-type cli-type)
            (setq-local claude-code-ide--terminal-backend backend)
            (claude-code-ide-session-mode 1)
            (claude-code-ide-session-setup-buffer))
          (cons buffer process)))

       (t
        (error "Unknown terminal backend: %s" backend))))))

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
                        "FORCE_CODE_TERMINAL=true"
                        ;; "CLAUDE_CODE_NO_FLICKER=1"
                        )))
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

(defun claude-code-ide--create-opencode-terminal-session (buffer-name working-dir _port continue resume session-id)
  "Create a new terminal session for OpenCode CLI.
BUFFER-NAME is the name for the terminal buffer.
WORKING-DIR is the working directory.
_PORT is unused (no MCP for OpenCode).
CONTINUE is whether to continue the most recent conversation.
RESUME is whether to resume a previous conversation.
SESSION-ID is the unique identifier for this session.

Returns a cons cell of (buffer . process) on success."
  (let ((cmd (claude-code-ide--build-opencode-command continue resume session-id))
        (env-vars (list (format "EMACS_BUFFER_NAME=%s" buffer-name))))
    (claude-code-ide-debug "Session ID: %s" session-id)
    (claude-code-ide--create-terminal-with-command buffer-name working-dir cmd env-vars)))

(defun claude-code-ide--create-pi-terminal-session (buffer-name working-dir _port continue resume session-id)
  "Create a new terminal session for Pi or Oh My Pi."
  (let ((cmd (claude-code-ide--build-pi-command continue resume session-id))
        (env-vars (list (format "EMACS_BUFFER_NAME=%s" buffer-name))))
    (when (and (eq (claude-code-ide--current-cli-type) 'omp)
               (eq (claude-code-ide--resolve-terminal-backend 'omp) 'ghostel))
      ;; Outer terminal identifiers do not describe Emacs image support.
      (push (if (display-graphic-p)
                "PI_FORCE_IMAGE_PROTOCOL=kitty"
              "PI_FORCE_IMAGE_PROTOCOL=off")
            env-vars))
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
  (pcase (claude-code-ide--current-cli-type)
    ('opencode (claude-code-ide--create-opencode-terminal-session
                buffer-name working-dir port continue resume session-id))
    ((or 'pi 'omp) (claude-code-ide--create-pi-terminal-session
                    buffer-name working-dir port continue resume session-id))
    ('codex (claude-code-ide--create-codex-terminal-session
             buffer-name working-dir port continue resume session-id))
    (_ (claude-code-ide--create-claude-terminal-session
        buffer-name working-dir port continue resume session-id))))

(defun claude-code-ide--toggle-session (session)
  "Toggle SESSION and mark it as the preferred sibling."
  (prog1 (claude-code-ide--touch-session (claude-code-ide-session-id session))
    (claude-code-ide--toggle-existing-window
     (claude-code-ide-session-buffer session)
     (claude-code-ide-session-directory session))))

(defun claude-code-ide--zmx-live-names ()
  "Return local zmx names attached by live sessions in this Emacs instance.
A remote session's name lives in a separate namespace on another host
and must never hide or match a local zmx name."
  (let (names)
    (maphash (lambda (_id session)
               (when (and (not (claude-code-ide-session-host session))
                          (claude-code-ide-session-zmx-name session))
                 (push (claude-code-ide-session-zmx-name session) names)))
             claude-code-ide--sessions)
    names))

(defun claude-code-ide--live-session-for-target (host zmx-name)
  "Return the live session already attached to HOST and ZMX-NAME, or nil."
  (when host
    (let (found)
      (maphash (lambda (_id session)
                 (when (and (not found)
                            (equal (claude-code-ide-session-host session) host)
                            (equal (claude-code-ide-session-zmx-name session) zmx-name))
                   (setq found session)))
               claude-code-ide--sessions)
      found)))

(defun claude-code-ide--remembered-target-session-id (host zmx-name)
  "Return the Session ID of the remembered item for HOST and ZMX-NAME."
  (unless (claude-code-ide-manager--scope-state-entry '(:type global))
    (claude-code-ide-manager--load-state))
  (when-let* ((item (cl-find-if
                     (lambda (item)
                       (and (equal (claude-code-ide-manager-item-host item) host)
                            (equal (claude-code-ide-manager-item-zmx-name item) zmx-name)))
                     (claude-code-ide-manager--all-items))))
    (claude-code-ide-manager-item-session-key item)))

(defun claude-code-ide--remote-target-process-name (session-id)
  "Return the stable request process name owning SESSION-ID's remote target.
A pending reattach and a pending Stop share this exact name, so either
can detect and refuse to race the other; see
`claude-code-ide--remote-target-pending-reason'."
  (format "claude-code-ide-remote-target-%s" session-id))

(defun claude-code-ide--remote-target-pending-reason (session-id)
  "Return a description of SESSION-ID's in-flight remote request, or nil."
  (let ((process (get-process (claude-code-ide--remote-target-process-name session-id))))
    (when (process-live-p process)
      (if (eq (process-get process 'cci-operation) 'stop)
          "a Stop request"
        "an attach request"))))

(defun claude-code-ide-session-agent-pid (session)
  "Return the agent process pid for SESSION, or nil.
The first successful lookup is cached in the session's `pid' slot.
A remote SESSION always returns nil: its Agent runs on another
machine, so no local process table lookup applies, cached or not.
Otherwise a zmx-backed session asks zmx, since the agent runs under
the zmx server rather than under Emacs.  Otherwise use the terminal
process pid, descending one level when that process is a shell
wrapper \(vterm and ghostel run the command through `sh -c')."
  (unless (claude-code-ide-session-host session)
    (or (claude-code-ide-session-pid session)
        (setf (claude-code-ide-session-pid session)
              (if-let* ((name (claude-code-ide-session-zmx-name session)))
                  (claude-code-ide-zmx-session-pid name)
                (when-let* ((process (claude-code-ide-session-process session))
                            (pid (and (process-live-p process) (process-id process))))
                  (if (member (alist-get 'comm (process-attributes pid))
                              '("sh" "bash" "zsh" "fish" "dash"))
                      (seq-find (lambda (child)
                                  (eql (alist-get 'ppid (process-attributes child)) pid))
                                (list-system-processes))
                    pid)))))))

(defun claude-code-ide--zmx-launch-spec (working-dir continue resume session-id attach-name)
  "Return (ZMX-NAME . ATTACH-ONLY) for the session being created, or nil.
WORKING-DIR, CONTINUE, RESUME, and SESSION-ID describe the new session.
ATTACH-NAME forces reattach/adoption of that existing zmx session.
A plain start offers eligible zmx sessions via `completing-read';
continue/resume starts offer only sessions with zero attached clients."
  (cond
   (attach-name (cons attach-name t))
   ((not claude-code-ide-use-zmx) nil)
   (t
    (claude-code-ide-zmx--ensure)
    (let* ((cli-type (claude-code-ide--current-cli-type))
           (new-name (claude-code-ide-zmx-session-name cli-type working-dir session-id))
           (eligible (claude-code-ide-zmx--eligible-sessions
                      cli-type working-dir
                      (claude-code-ide--zmx-live-names)
                      (or continue resume))))
      (if (null eligible)
          (cons new-name nil)
        (let ((choice (completing-read
                       "Reattach to zmx session: "
                       (append eligible '("Create new session")) nil t)))
          (if (equal choice "Create new session")
              (cons new-name nil)
            (cons choice t))))))))

(defun claude-code-ide--create-local-session (working-dir continue resume &optional zmx-attach-name)
  "Create a local terminal session in WORKING-DIR.
CONTINUE and RESUME select the CLI conversation mode.
ZMX-ATTACH-NAME reattaches to that existing zmx session instead of
running a freshly built CLI command."
  (claude-code-ide--terminal-ensure-backend)
  (let* ((session-id
          (make-temp-name
           (format "claude-%s-%s-"
                   (file-name-nondirectory (directory-file-name working-dir))
                   (format-time-string "%Y%m%d-%H%M%S"))))
         (cli-type (claude-code-ide--current-cli-type))
         (agent-name
          (car (rassoc (symbol-name cli-type)
                       claude-code-ide-agent-definitions)))
         (zmx-spec (claude-code-ide--zmx-launch-spec
                    working-dir continue resume session-id zmx-attach-name))
         (buffer-name
          (generate-new-buffer-name
           (claude-code-ide--get-buffer-name working-dir)))
         port buffer process session
         mcp-started-p mcp-tools-started-p)
    (condition-case err
        (progn
          (pcase cli-type
            ('claude
             (setq port (claude-code-ide-mcp-start working-dir session-id)
                   mcp-started-p t))
            ('omp
             (setq port (claude-code-ide-mcp-sse-ensure-server))))
          (let* ((claude-code-ide-zmx--pending-name (car zmx-spec))
                 (claude-code-ide-zmx--pending-attach-only (cdr zmx-spec))
                 (buffer-and-process
                  (claude-code-ide--create-terminal-session
                   buffer-name working-dir port continue resume session-id)))
            (setq buffer (car buffer-and-process)
                  process (cdr buffer-and-process))
            (when (eq cli-type 'claude)
              (setq mcp-tools-started-p t)
              (claude-code-ide-mcp-server-session-started
               session-id working-dir buffer))
            (let ((created-at (float-time)))
              (setq session
                    (claude-code-ide-session-create
                     :id session-id
                     :directory working-dir
                     :process process
                     :buffer buffer
                     :cli-type cli-type
                     :order (claude-code-ide--next-session-order working-dir)
                     :created-at created-at
                     :last-accessed-at created-at
                     :zmx-name (car zmx-spec))))
            (claude-code-ide--register-session session)
            (set-process-sentinel
             process
             (lambda (proc event)
               (when (string-match "exited abnormally with code \\([0-9]+\\)" event)
                 (let ((exit-code (match-string 1 event)))
                   (claude-code-ide-debug
                    "Claude process exited with code %s, event: %s"
                    exit-code event)
                   (message "Claude exited with error code %s" exit-code)))
               (when (string-match-p "finished\\|exited\\|killed\\|terminated" event)
                 (claude-code-ide--cleanup-on-exit session-id nil proc))))
            (with-current-buffer buffer
              (add-hook 'kill-buffer-hook
                        (lambda ()
                          (claude-code-ide--cleanup-on-exit session-id t process))
                        nil t)
              (pcase (claude-code-ide--current-terminal-backend)
                ('vterm
                 (add-hook 'vterm-exit-functions
                           (lambda (&rest _)
                             (when (buffer-live-p buffer)
                               (kill-buffer buffer)))
                           nil t))
                ('eat
                 (setq-local eat-kill-buffer-on-exit t))))
            (sleep-for claude-code-ide-terminal-initialization-delay)
            (unless claude-code-ide--suppress-initial-display
              (if (and (cdr zmx-spec)
                       (claude-code-ide-manager--visible-sidebar-scopes))
                  ;; Use the manager layout only when its sidebar is visible.
                  (claude-code-ide-manager-switch-to-session session-id)
                (claude-code-ide--display-buffer-in-side-window buffer)))
            (claude-code-ide-log "%s %sstarted in %s%s%s"
                                 agent-name
                                 (cond (continue "continued and ")
                                       (resume "resumed and ")
                                       (t ""))
                                 (file-name-nondirectory
                                  (directory-file-name working-dir))
                                 (if (and port
                                          (memq cli-type '(claude omp)))
                                     (format " with MCP on port %d" port)
                                   "")
                                 (if claude-code-ide-cli-debug
                                     " (debug mode enabled)"
                                   ""))
            session))
      (error
       (if (claude-code-ide--get-session session-id)
           (claude-code-ide--cleanup-on-exit session-id)
         (when mcp-tools-started-p
           (claude-code-ide-mcp-server-session-ended session-id))
         (when (process-live-p process)
           (delete-process process))
         (when (buffer-live-p buffer)
           (let ((kill-buffer-hook nil)
                 (kill-buffer-query-functions nil))
             (kill-buffer buffer)))
         (when mcp-started-p
           (claude-code-ide-mcp-stop-session session-id)))
       (signal (car err) (cdr err))))))

(defun claude-code-ide--materialize-remote-target (session-id host zmx-name directory order created-at)
  "Remember a disconnected manager row for a remote target before attaching.
Build a minimal Session with no buffer or process yet, carrying only
identity and presentation fields, and hand it to
`claude-code-ide-manager--remember-remote-session', so a first-attach
failure still leaves exactly one disconnected row instead of none."
  (claude-code-ide-manager--remember-remote-session
   (claude-code-ide-session-create
    :id session-id
    :directory directory
    :cli-type (claude-code-ide--current-cli-type)
    :order order
    :created-at created-at
    :last-accessed-at created-at
    :zmx-name zmx-name
    :host host)))

(defun claude-code-ide--create-remote-session
    (working-dir zmx-attach-name host reusable-session-id)
  "Attach a terminal session to an existing remote zmx target.
WORKING-DIR is the remote project directory, kept as opaque metadata:
never passed through a local file-name function.  ZMX-ATTACH-NAME is
the existing zmx session name on HOST.  REUSABLE-SESSION-ID reuses that Session ID instead of
minting a new one, so a remembered item keeps its identity, order,
and creation time across a reattach.  Bypasses Agent builders, MCP
startup, and local zmx wrapping; shared terminal setup, Session
registration, and cleanup orchestration still run, matching the local
path.  Materializes a disconnected manager row before the terminal
exists, so a failed first attach still leaves one row instead of
none."
  (unless zmx-attach-name
    (user-error "Remote attachment needs an existing zmx session name"))
  (unless (claude-code-ide-zmx--valid-directory-p working-dir)
    (user-error "Remote project directory must be absolute path text"))
  (let ((backend (claude-code-ide--current-terminal-backend)))
    (unless (eq backend 'ghostel)
      (user-error "Remote attachment supports the ghostel backend only, not %s" backend)))
  (let* ((session-id
          (or reusable-session-id
              (make-temp-name (format "claude-remote-%s-" host))))
         (existing-item (claude-code-ide-manager--item-by-session-key session-id))
         (order (if existing-item
                    (claude-code-ide-manager-item-order existing-item)
                  (claude-code-ide--next-session-order working-dir host)))
         (created-at (if existing-item
                         (claude-code-ide-manager-item-created-at existing-item)
                       (float-time)))
         (cmd (claude-code-ide-zmx--remote-attach-command host zmx-attach-name))
         (buffer-name
          (generate-new-buffer-name
           (format "*claude-code[%s@%s]*"
                   (claude-code-ide--path-basename working-dir) host)))
         buffer process session)
    (claude-code-ide--materialize-remote-target
     session-id host zmx-attach-name working-dir order created-at)
    (condition-case err
        (progn
          (claude-code-ide--terminal-ensure-backend)
          (when reusable-session-id
            (claude-code-ide-zmx-require-remote-session
             host zmx-attach-name
             (claude-code-ide--remote-target-process-name session-id)))
          (let* ((claude-code-ide--pending-remote-host host)
                 (buffer-and-process
                  (claude-code-ide--create-terminal-with-command
                   buffer-name temporary-file-directory cmd nil)))
            (setq buffer (car buffer-and-process)
                  process (cdr buffer-and-process))
            (setq session
                  (claude-code-ide-session-create
                   :id session-id
                   :directory working-dir
                   :process process
                   :buffer buffer
                   :cli-type (claude-code-ide--current-cli-type)
                   :order order
                   :created-at created-at
                   :custom-name (and existing-item
                                     (claude-code-ide-manager-item-custom-name existing-item))
                   :last-accessed-at (float-time)
                   :zmx-name zmx-attach-name
                   :host host))
            (claude-code-ide--register-session session)
            (set-process-sentinel
             process
             (lambda (proc event)
               (when (string-match "exited abnormally with code \\([0-9]+\\)" event)
                 (claude-code-ide-log "Remote agent %s on %s exited abnormally (code %s)"
                                      zmx-attach-name host (match-string 1 event)))
               (when (string-match-p "finished\\|exited\\|killed\\|terminated" event)
                 (claude-code-ide--cleanup-on-exit session-id nil proc))))
            (with-current-buffer buffer
              (add-hook 'kill-buffer-hook
                        (lambda ()
                          (claude-code-ide--cleanup-on-exit session-id t process))
                        nil t))
            (sleep-for claude-code-ide-terminal-initialization-delay)
            (unless (and (process-live-p process)
                         (buffer-live-p buffer)
                         (eq session (claude-code-ide--get-session session-id)))
              (user-error "Cannot attach %s on %s. The attachment process exited"
                          zmx-attach-name host))
            (unless claude-code-ide--suppress-initial-display
              (claude-code-ide--display-buffer-in-side-window buffer))
            (claude-code-ide-log "Started attachment to %s on %s" zmx-attach-name host)
            (condition-case metadata-error
                (claude-code-ide-manager--enqueue-remote-metadata session)
              (error
               (claude-code-ide-log "Remote metadata request for %s on %s failed: %s"
                                    zmx-attach-name host
                                    (error-message-string metadata-error))))
            session))
      (error
       (if (claude-code-ide--get-session session-id)
           (claude-code-ide--cleanup-on-exit session-id)
         (when (process-live-p process)
           (delete-process process))
         (when (buffer-live-p buffer)
           (let ((kill-buffer-hook nil)
                 (kill-buffer-query-functions nil))
             (kill-buffer buffer))))
       (signal (car err) (cdr err))))))

(defun claude-code-ide--create-session
    (working-dir continue resume &optional zmx-attach-name host reusable-session-id)
  "Create a terminal session in WORKING-DIR, locally or on HOST.
CONTINUE and RESUME select the CLI conversation mode; a non-nil HOST
requires both nil, since a remote session always reattaches to an
existing target instead of starting a conversation.  ZMX-ATTACH-NAME
reattaches to that existing zmx session instead of running a freshly
built CLI command; it is required when HOST is non-nil.
REUSABLE-SESSION-ID only applies to a remote HOST; see
`claude-code-ide--create-remote-session'."
  (if host
      (progn
        (when (or continue resume)
          (user-error "Remote attachment does not support continue or resume"))
        (claude-code-ide--create-remote-session
         working-dir zmx-attach-name host reusable-session-id))
    (claude-code-ide--create-local-session
     working-dir continue resume zmx-attach-name)))

(defun claude-code-ide--start-session (&optional continue resume directory force-new)
  "Start or toggle a session in DIRECTORY.
CONTINUE and RESUME select the CLI conversation mode.  FORCE-NEW creates a
sibling even when a session already exists for the directory."
  (unless (claude-code-ide--ensure-cli)
    (user-error "Claude Code CLI not available.  Please install it and ensure it's in PATH"))
  (claude-code-ide--cleanup-dead-processes)
  (let* ((working-dir (or directory (claude-code-ide--get-working-directory)))
         (existing (claude-code-ide--preferred-session working-dir)))
    (if (and existing (not force-new))
        (claude-code-ide--toggle-session existing)
      (if claude-code-ide-use-with-editor
          (progn
            (dolist (pattern claude-code-ide-prompt-buffer-patterns)
              (setf (alist-get pattern with-editor-server-window-alist
                               nil nil #'equal)
                    #'switch-to-buffer))
            (with-editor
             (claude-code-ide--create-session working-dir continue resume)))
        (claude-code-ide--create-session working-dir continue resume)))))

;;;###autoload
(defun claude-code-ide (&optional new-session)
  "Run Claude Code in a terminal for the current project or directory."
  (interactive "P")
  (claude-code-ide--start-session nil nil nil new-session))

;;;###autoload
(defun claude-code-ide-new-session ()
  "Start a sibling session for the current project or directory."
  (interactive)
  (claude-code-ide--start-session nil nil nil t))

;;;###autoload
(defun claude-code-ide-current-directory ()
  "Run Claude Code in a terminal for the current directory."
  (interactive)
  (claude-code-ide--start-session nil nil (claude-code-ide--get-current-directory)))

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
(defun claude-code-ide-stop (&optional session-id)
  "Stop the Claude Code session identified by SESSION-ID.
Without SESSION-ID, resolve the exact session attached to the current
buffer before falling back to the session for the current project or
directory.  For a zmx-backed local session, ask before killing the
zmx session; killing it stops the agent process for every attached
client.  For a remote session, confirm the host, exact zmx name, and
impact on every attached client, then run a verified remote Stop
instead of a local kill."
  (interactive)
  (let* ((current (unless session-id (claude-code-ide--session-for-buffer)))
         (directory (unless (or session-id current)
                      (claude-code-ide--get-attached-working-directory)))
         (buffer (unless (or session-id current)
                   (claude-code-ide--get-session-buffer directory)))
         (session
          (if session-id
              (or (claude-code-ide--get-session session-id)
                  (when-let* ((item (claude-code-ide-manager--item-by-session-key session-id))
                              (host (claude-code-ide-manager-item-host item)))
                    (claude-code-ide-session-create
                     :id session-id :host host
                     :zmx-name (claude-code-ide-manager-item-zmx-name item)
                     :directory (claude-code-ide-manager-item-directory item)))
                  (user-error "No session with ID %s" session-id))
            (or current
                (and buffer (claude-code-ide--session-for-buffer buffer))
                (when (buffer-live-p buffer)
                  (claude-code-ide-session-create :directory directory :buffer buffer))))))
    (cond
     ((null session)
      (claude-code-ide-log "No Claude Code session is running in this directory"))
     ((claude-code-ide-session-host session)
      (claude-code-ide--stop-remote-session session))
     (t
      (claude-code-ide--stop-local-session session)))))

(defun claude-code-ide--stop-local-session (session)
  "Confirm and kill SESSION's local zmx-backed or plain terminal.
A zmx-backed SESSION asks first, since killing it stops the agent
process for every attached client; declining keeps it running."
  (let ((buffer (claude-code-ide-session-buffer session))
        (zmx-name (claude-code-ide-session-zmx-name session))
        (directory (claude-code-ide-session-directory session)))
    (if (and zmx-name
             (not (yes-or-no-p
                   (format "Kill zmx session %s (killing stops the agent everywhere)? "
                           zmx-name))))
        (claude-code-ide-log "Kept zmx session %s running" zmx-name)
      (when zmx-name
        (claude-code-ide-zmx-kill zmx-name))
      ;; Kill the buffer (cleanup will be handled by hooks)
      ;; The process sentinel will handle cleanup when the process dies
      (kill-buffer buffer)
      (claude-code-ide-log "Stopping Claude Code in %s..."
                           (file-name-nondirectory (directory-file-name directory))))))

(defun claude-code-ide--stop-remote-session (session)
  "Confirm and dispatch a verified remote Stop for SESSION.
Name SESSION's host and zmx name and warn that stopping affects every
attached client.  Canceling sends no request.  A confirmed Stop
refuses while a request already owns this Session ID, revalidates the
destination, then keeps the initial kill process as the ownership
token until the host verifies the target is gone.  On verified
success, invalidate the captured live Session before releasing its
resources and let the manager forget the row; an unconfirmed result
retains the row and is never retried."
  (let* ((session-id (claude-code-ide-session-id session))
         (host (claude-code-ide-session-host session))
         (zmx-name (claude-code-ide-session-zmx-name session))
         (pending (claude-code-ide--remote-target-pending-reason session-id)))
    (cond
     (pending
      (user-error "Cannot stop %s on %s. %s is already in progress"
                  zmx-name host pending))
     ((not (yes-or-no-p
            (format "Stop %s on %s?  This stops the agent for every attached client. "
                    zmx-name host)))
      (claude-code-ide-log "Kept %s on %s running" zmx-name host))
     (t
      (claude-code-ide-zmx--validate-host host)
      (claude-code-ide-zmx--validate-name zmx-name)
      (when-let* ((owner (claude-code-ide--remote-target-pending-reason session-id)))
        (user-error "Cannot stop %s on %s. %s is already in progress"
                    zmx-name host owner))
      (let ((attach-process (claude-code-ide-session-process session))
            (request-name (claude-code-ide--remote-target-process-name session-id)))
        (claude-code-ide-log "Stopping %s on %s..." zmx-name host)
        (claude-code-ide-zmx-stop-remote
         host zmx-name
         (lambda (outcome)
           (if (plist-get outcome :verified)
               (let ((current (claude-code-ide--get-session session-id)))
                 (when (or (null current)
                           (and attach-process
                                (eq attach-process
                                    (claude-code-ide-session-process current))))
                   (when current
                     (claude-code-ide--cleanup-on-exit
                      session-id nil attach-process 'verified-stop))
                   (claude-code-ide-manager-session-ended session-id t)
                   (claude-code-ide-log "Stopped %s on %s" zmx-name host)))
             (claude-code-ide-log "%s" (plist-get outcome :error))))
         request-name))))))

(defun claude-code-ide--reattach-cli-path (item)
  "Return the CLI path to reattach ITEM's remote target with.
Reuse ITEM's remembered CLI type when set; otherwise fall back to
manual Agent identification, matching individual attach's fallback."
  (if-let* ((cli-type (claude-code-ide-manager-item-cli-type item)))
      (symbol-name cli-type)
    (claude-code-ide--read-agent
     (format "Agent running in %s: " (claude-code-ide-manager-item-zmx-name item)))))

(defun claude-code-ide--reattach-remote-session (session-id)
  "Explicitly reattach the remembered remote target for SESSION-ID.
Startup, selection, and refresh never call this; only an explicit
command does.  Revalidate the configured host, exact zmx name, and
directory metadata, reject while a Stop or another attach already
owns this target, and
reuse the shared terminal path under the same SESSION-ID so its
identity, names, order, and pin state survive.  A failure retains the
disconnected row and reports the host and target."
  (let* ((item (or (claude-code-ide-manager--item-by-session-key session-id)
                   (user-error "No remembered session %s" session-id)))
         (host (or (claude-code-ide-manager-item-host item)
                   (user-error "Session %s is not a remote target" session-id)))
         (zmx-name (claude-code-ide-manager-item-zmx-name item))
         (directory (claude-code-ide-manager-item-directory item))
         (pending (claude-code-ide--remote-target-pending-reason session-id)))
    (cond
     (pending
      (user-error "Cannot reattach %s on %s. %s is already in progress"
                  zmx-name host pending))
     ((claude-code-ide--get-session session-id)
      (claude-code-ide-manager-switch-to-session session-id))
     (t
      (claude-code-ide-zmx--validate-host host)
      (claude-code-ide-zmx--validate-name zmx-name)
      (unless (claude-code-ide-zmx--valid-directory-p directory)
        (user-error "Session %s has invalid remembered directory metadata" session-id))
      (let ((cli-path (claude-code-ide--reattach-cli-path item)))
        (claude-code-ide-log "Reattaching %s on %s..." zmx-name host)
        (when-let* ((session (claude-code-ide--attach-zmx-entry
                              (list :host host :name zmx-name)
                              directory cli-path session-id)))
          (claude-code-ide-manager-switch-to-session
           (claude-code-ide-session-id session))))))))

;;;###autoload
(defun claude-code-ide-copy-zmx-name ()
  "Copy the current session's zmx name to the kill ring.
Use it to run `zmx attach <name>' from a plain terminal."
  (interactive)
  (let* ((session (or (claude-code-ide--session-for-buffer)
                      (when-let* ((buffer (claude-code-ide--get-session-buffer)))
                        (claude-code-ide--session-for-buffer buffer))))
         (name (and session (claude-code-ide-session-zmx-name session))))
    (cond
     ((null session) (user-error "No session for this buffer or project"))
     ((null name) (user-error "Session is not zmx-backed"))
     (t
      (kill-new name)
      (message "Copied zmx name: %s" name)))))

(defun claude-code-ide--zmx-adoptable-sessions ()
  "Return zmx session plists not attached in this Emacs instance."
  (claude-code-ide-zmx--ensure)
  (let ((live (claude-code-ide--zmx-live-names)))
    (seq-remove (lambda (entry) (member (plist-get entry :name) live))
                (claude-code-ide-zmx-list-sessions))))

(defun claude-code-ide--zmx-entry-label (entry)
  "Return \"PROJECT  TITLE  CMD\" for zmx ENTRY; TITLE is omitted when absent.
A :host-bearing ENTRY is prefixed \"HOST: \" ahead of PROJECT."
  (let ((project (if-let* ((dir (plist-get entry :start_dir)))
                     (claude-code-ide--path-basename dir)
                   "?"))
        (title (plist-get entry :title))
        (host (plist-get entry :host)))
    (concat (and host (concat host ": "))
            project
            (when title (concat "  " (subst-char-in-string ?_ ?\s title)))
            "  " (or (plist-get entry :cmd) ""))))

(defun claude-code-ide--attach-zmx-entry (entry directory cli-path &optional session-id)
  "Adopt zmx ENTRY as a session in DIRECTORY running CLI-PATH.
ENTRY's :host routes the attachment to that remote
target instead of the local zmx server; DIRECTORY then stays opaque
remote metadata instead of a local directory.  SESSION-ID reuses that
Session ID when reattaching a remembered item.  Deduplicates by
\(:host . :name\): an already-connected target is returned unchanged
instead of opening a second client, and an otherwise-unspecified
SESSION-ID falls back to a remembered target's own Session ID so a
fresh attach reuses its identity rather than creating a duplicate row.
Return the new or existing session, or nil when creation returns nil
or another request already owns this target."
  (let* ((host (plist-get entry :host))
         (zmx-name (plist-get entry :name))
         (live (and host (claude-code-ide--live-session-for-target host zmx-name)))
         (session-id (or session-id
                         (and host
                              (claude-code-ide--remembered-target-session-id host zmx-name))))
         (pending (and host session-id
                       (claude-code-ide--remote-target-pending-reason session-id))))
    (cond
     (live live)
     (pending
      (claude-code-ide-log "%s on %s: %s already in progress" zmx-name host pending)
      nil)
     (t
      (let ((claude-code-ide-cli-path cli-path)
            (claude-code-ide--suppress-initial-display t))
        (if host
            (claude-code-ide--create-session
             directory nil nil zmx-name host session-id)
          (claude-code-ide--create-session (file-name-as-directory directory)
                                           nil nil zmx-name)))))))

(defun claude-code-ide--attach-zmx-entries (entries)
  "Adopt every zmx entry in ENTRIES without prompting.
Skip an entry carrying its own `:error', one whose `:start_dir' is
missing or, for a :host-bearing entry, not absolute remote path
metadata, or one whose `:cmd' does not map to a known agent
(`claude-code-ide-zmx-infer-cli-command'); a malformed `:cmd' is
caught rather than aborting the rest of ENTRIES.  Log entries whose
creation signals, and return the number of sessions attached."
  (let ((attached 0) skipped)
    (dolist (entry entries)
      (let* ((name (plist-get entry :name))
             (host (plist-get entry :host))
             (directory (plist-get entry :start_dir))
             (candidate-error (plist-get entry :error))
             (cli-path (and (not candidate-error)
                            (ignore-errors
                              (claude-code-ide-zmx-infer-cli-command
                               (plist-get entry :cmd))))))
        (cond
         (candidate-error
          (push (format "%s (%s)" name candidate-error) skipped))
         ((not cli-path)
          (push name skipped))
         ((and host (not (claude-code-ide-zmx--valid-directory-p directory)))
          (push (format "%s (invalid remote directory)" name) skipped))
         ((not directory)
          (push name skipped))
         (t
          (condition-case err
              (when (claude-code-ide--attach-zmx-entry entry directory cli-path)
                (setq attached (1+ attached)))
            (error
             (claude-code-ide-log "Failed to attach %s: %s"
                                  name (error-message-string err))
             (push name skipped)))))))
    (claude-code-ide-log "Attached %d zmx session%s%s"
                         attached
                         (if (= attached 1) "" "s")
                         (if skipped
                             (format "; skipped %s" (string-join (nreverse skipped) ", "))
                           ""))
    attached))

(defun claude-code-ide--read-remote-host ()
  "Prompt for one destination from `claude-code-ide-remote-hosts'."
  (unless claude-code-ide-remote-hosts
    (user-error "No hosts configured in `claude-code-ide-remote-hosts'"))
  (completing-read "Host: " claude-code-ide-remote-hosts nil t))

(defun claude-code-ide--remote-discovery-callback (continuation)
  "Return a `claude-code-ide-zmx-discover-remote' callback wrapping CONTINUATION.
On success, call CONTINUATION with the possibly empty candidate list
from the discovery outcome.  On failure, report the error with
`claude-code-ide-log' instead of signaling: the callback runs
asynchronously, outside any interactive command's call stack, so a
raw signal here cannot reach the command that requested discovery."
  (lambda (outcome)
    (if-let* ((failure (plist-get outcome :error)))
        (claude-code-ide-log "%s" failure)
      (funcall continuation (plist-get outcome :sessions)))))

(defun claude-code-ide--attach-discovered-entries (sessions)
  "Attach every entry in SESSIONS without prompting, or log if none."
  (if (null sessions)
      (claude-code-ide-log "No zmx sessions to adopt")
    (claude-code-ide--attach-zmx-entries sessions)))

;;;###autoload
(defun claude-code-ide-attach-all (&optional host)
  "Adopt every zmx session not already attached in this Emacs instance.
Sessions without a start directory or with an unrecognized command are
skipped and named in the summary message; adopt those with
`claude-code-ide-attach'.  With a prefix argument, or when HOST names a
configured destination, adopt every existing session on that remote
host instead."
  (interactive (list (when current-prefix-arg (claude-code-ide--read-remote-host))))
  (if host
      (claude-code-ide-zmx-discover-remote
       host (claude-code-ide--remote-discovery-callback
             #'claude-code-ide--attach-discovered-entries))
    (claude-code-ide--attach-discovered-entries
     (claude-code-ide--zmx-adoptable-sessions))))

(defun claude-code-ide--resolve-attach-directory (entry)
  "Return ENTRY's start directory, prompting when it is missing or invalid.
A :host-bearing ENTRY must resolve to absolute remote path metadata
(`claude-code-ide-zmx--valid-directory-p'); prompt with `read-string'
for typed absolute text instead of completing against a local path,
reprompting on invalid input."
  (if (plist-get entry :host)
      (let ((directory (plist-get entry :start_dir)))
        (while (not (claude-code-ide-zmx--valid-directory-p directory))
          (setq directory (read-string "Remote project directory (absolute path): ")))
        directory)
    (or (plist-get entry :start_dir)
        (read-directory-name "Project directory for session: "))))

(defun claude-code-ide--attach-one-of (sessions)
  "Prompt for one zmx entry among SESSIONS and attach it.
An entry carrying its own `:error' is named in a message and excluded
from the prompt instead of being offered as a choice."
  (let ((errored (seq-filter (lambda (entry) (plist-get entry :error)) sessions))
        (usable (seq-remove (lambda (entry) (plist-get entry :error)) sessions)))
    (when errored
      (claude-code-ide-log
       "Skipped %s"
       (string-join
        (mapcar (lambda (entry)
                  (format "%s (%s)" (plist-get entry :name) (plist-get entry :error)))
                errored)
        ", ")))
    (if (null usable)
        (claude-code-ide-log "No zmx sessions to adopt")
      (let* ((candidates
              (mapcar (lambda (entry)
                        (cons (concat
                               (claude-code-ide--zmx-entry-label entry)
                               ;; Keep candidates unique but hide the raw
                               ;; zmx name; `assoc' ignores text properties.
                               (propertize (concat "  " (plist-get entry :name))
                                           'invisible t))
                              entry))
                      usable))
             (choice (completing-read "Attach to zmx session: " candidates nil t))
             (entry (cdr (assoc choice candidates)))
             (directory (claude-code-ide--resolve-attach-directory entry))
             (cli-path (or (claude-code-ide-zmx-infer-cli-command (plist-get entry :cmd))
                           (claude-code-ide--read-agent
                            (format "Agent running in %s: " (plist-get entry :name))))))
        (when-let* ((session (claude-code-ide--attach-zmx-entry entry directory cli-path)))
          (claude-code-ide-manager-switch-to-session
           (claude-code-ide-session-id session)))))))

;;;###autoload
(defun claude-code-ide-attach (&optional host)
  "Adopt a zmx session into a Claude Code IDE session.
List zmx sessions (including ones launched outside Emacs), excluding
ones already attached in this Emacs instance, infer the agent CLI from
the session's command, and open an attached terminal buffer with full
session integration.  With a prefix argument, or when HOST names a
configured destination, list an existing session on that remote host
instead; picking one attaches to it without creating anything."
  (interactive (list (when current-prefix-arg (claude-code-ide--read-remote-host))))
  (if host
      (claude-code-ide-zmx-discover-remote
       host (claude-code-ide--remote-discovery-callback #'claude-code-ide--attach-one-of))
    (claude-code-ide--attach-one-of (claude-code-ide--zmx-adoptable-sessions))))

(defcustom claude-code-ide-attach-select-premark t
  "When non-nil, `claude-code-ide-attach-select' starts with every row marked."
  :type 'boolean
  :group 'claude-code-ide)

(defvar-local claude-code-ide--attach-select-return-window nil
  "Window that showed the attach-select buffer.")
(defvar-local claude-code-ide--attach-select-return-buffer nil
  "Buffer to restore when the attach-select buffer closes.")

(defvar claude-code-ide-attach-select-mode-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "m") #'claude-code-ide-attach-select-mark)
    (define-key map (kbd "u") #'claude-code-ide-attach-select-unmark)
    (define-key map (kbd "SPC") #'claude-code-ide-attach-select-toggle)
    (define-key map (kbd "t") #'claude-code-ide-attach-select-toggle-all)
    (define-key map (kbd "n") #'next-line)
    (define-key map (kbd "p") #'previous-line)
    (define-key map (kbd "C-c C-c") #'claude-code-ide-attach-select-apply)
    (define-key map (kbd "C-c C-k") #'claude-code-ide-attach-select-cancel)
    (define-key map (kbd "q") #'claude-code-ide-attach-select-cancel)
    map)
  "Keymap for `claude-code-ide-attach-select-mode'.")

(define-derived-mode claude-code-ide-attach-select-mode special-mode "CC-Attach"
  "Major mode for choosing zmx sessions to adopt."
  (setq truncate-lines t))

(defun claude-code-ide--attach-select-set-mark (marked)
  "Set the mark of the row at point to MARKED when point is on a row."
  (when (get-text-property (line-beginning-position) 'claude-code-ide-zmx-entry)
    (let ((inhibit-read-only t))
      (save-excursion
        (goto-char (1+ (line-beginning-position)))
        (delete-char 1)
        (insert-and-inherit (if marked "X" " "))))))

(defun claude-code-ide--attach-select-marked-p ()
  "Return non-nil when the row at point is marked."
  (eq (char-after (1+ (line-beginning-position))) ?X))

(defun claude-code-ide-attach-select-mark ()
  "Mark the row at point and move to the next row."
  (interactive)
  (claude-code-ide--attach-select-set-mark t)
  (forward-line 1))

(defun claude-code-ide-attach-select-unmark ()
  "Unmark the row at point and move to the next row."
  (interactive)
  (claude-code-ide--attach-select-set-mark nil)
  (forward-line 1))

(defun claude-code-ide-attach-select-toggle ()
  "Invert the mark of the row at point and move to the next row."
  (interactive)
  (claude-code-ide--attach-select-set-mark
   (not (claude-code-ide--attach-select-marked-p)))
  (forward-line 1))

(defun claude-code-ide-attach-select-toggle-all ()
  "Invert the mark of every row."
  (interactive)
  (save-excursion
    (goto-char (point-min))
    (while (not (eobp))
      (claude-code-ide--attach-select-set-mark
       (not (claude-code-ide--attach-select-marked-p)))
      (forward-line 1))))

(defun claude-code-ide--attach-select-close ()
  "Kill the attach-select buffer and restore the buffer it replaced."
  (let ((buffer (current-buffer))
        (window claude-code-ide--attach-select-return-window)
        (return-buffer claude-code-ide--attach-select-return-buffer))
    (when (and (window-live-p window) (buffer-live-p return-buffer))
      (set-window-buffer window return-buffer)
      (select-window window))
    (kill-buffer buffer)))

(defun claude-code-ide-attach-select-apply ()
  "Attach every marked row, then close the attach-select buffer."
  (interactive)
  (let (entries)
    (save-excursion
      (goto-char (point-min))
      (while (not (eobp))
        (when (claude-code-ide--attach-select-marked-p)
          (push (get-text-property (point) 'claude-code-ide-zmx-entry) entries))
        (forward-line 1)))
    (unless entries
      (user-error "No zmx sessions marked"))
    (claude-code-ide--attach-select-close)
    (claude-code-ide--attach-zmx-entries (nreverse entries))))

(defun claude-code-ide-attach-select-cancel ()
  "Close the attach-select buffer without attaching."
  (interactive)
  (claude-code-ide--attach-select-close))

(defun claude-code-ide--open-attach-select-buffer (sessions)
  "Open a buffer listing SESSIONS for marking and bulk attach.
An entry carrying its own `:error' is named in a message and excluded
from the buffer instead of being listed as a choice."
  (let ((errored (seq-filter (lambda (entry) (plist-get entry :error)) sessions))
        (sessions (seq-remove (lambda (entry) (plist-get entry :error)) sessions)))
    (when errored
      (claude-code-ide-log
       "Skipped %s"
       (string-join
        (mapcar (lambda (entry)
                  (format "%s (%s)" (plist-get entry :name) (plist-get entry :error)))
                errored)
        ", ")))
    (if (null sessions)
        (claude-code-ide-log "No zmx sessions to adopt")
      (let* ((window (claude-code-ide-manager--content-window))
             (return-buffer (window-buffer window))
             (buffer (generate-new-buffer "*claude-code-ide-attach*")))
        (with-current-buffer buffer
          (claude-code-ide-attach-select-mode)
          (setq claude-code-ide--attach-select-return-window window
                claude-code-ide--attach-select-return-buffer return-buffer)
          (let ((inhibit-read-only t))
            (dolist (entry sessions)
              (insert (propertize
                       (concat (if claude-code-ide-attach-select-premark "[X] " "[ ] ")
                               (claude-code-ide--zmx-entry-label entry)
                               "  " (plist-get entry :name))
                       'claude-code-ide-zmx-entry entry)
                      "\n")))
          (goto-char (point-min)))
        (set-window-buffer window buffer)
        (select-window window)
        (message "m/u/SPC mark, unmark, toggle rows; t inverts all; C-c C-c attaches marked, C-c C-k cancels")))))

;;;###autoload
(defun claude-code-ide-attach-select (&optional host)
  "Choose zmx sessions to adopt in a buffer, then attach the marked ones.
`m' and `u' mark and unmark the row at point, `SPC' toggles it, `t'
inverts every mark, \\`C-c C-c' attaches the marked rows, \\`C-c C-k'
cancels.  `claude-code-ide-attach-select-premark' decides whether rows
start marked.  With a prefix argument, or when HOST names a configured
destination, list zmx sessions on that remote host instead."
  (interactive (list (when current-prefix-arg (claude-code-ide--read-remote-host))))
  (if host
      (claude-code-ide-zmx-discover-remote
       host (claude-code-ide--remote-discovery-callback
             #'claude-code-ide--open-attach-select-buffer))
    (claude-code-ide--open-attach-select-buffer (claude-code-ide--zmx-adoptable-sessions))))


;;;###autoload
(defun claude-code-ide-switch-to-buffer ()
  "Switch to the Claude Code buffer for the current project.
If the buffer is not visible, display it in the configured side window.
If the buffer is already visible, switch focus to it."
  (interactive)
  (if-let* ((buffer (claude-code-ide--get-session-buffer)))
      (if-let* ((window (get-buffer-window buffer)))
          ;; Buffer is visible, just focus it
          (select-window window)
        ;; Buffer exists but not visible, display it
        (claude-code-ide--display-buffer-in-side-window buffer))
    (user-error "No Claude Code session for this project.  Use M-x claude-code-ide to start one")))

;;;###autoload
(defun claude-code-ide-list-related-sessions ()
  "List active sessions related to the current buffer and switch to one."
  (interactive)
  (claude-code-ide--cleanup-dead-processes)
  (let* ((related-sessions (claude-code-ide--get-related-sessions))
         (directory-counts (make-hash-table :test #'equal))
         choices)
    (dolist (session related-sessions)
      (let ((directory (claude-code-ide--normalize-directory
                        (claude-code-ide-session-directory session))))
        (puthash directory (1+ (gethash directory directory-counts 0))
                 directory-counts)))
    (setq choices
          (mapcar
           (lambda (session)
             (let* ((directory (claude-code-ide--normalize-directory
                                (claude-code-ide-session-directory session)))
                    (buffer (claude-code-ide-session-buffer session))
                    (label (if (> (gethash directory directory-counts) 1)
                               (format "%s  %s"
                                       (abbreviate-file-name directory)
                                       (buffer-name buffer))
                             (abbreviate-file-name directory))))
               (cons label (claude-code-ide-session-id session))))
           related-sessions))
    (if choices
        (let ((choice (completing-read "Switch to related Claude Code session: "
                                       choices nil t)))
          (when choice
            (let* ((session-id (alist-get choice choices nil nil #'string=))
                   (session (claude-code-ide--get-session session-id))
                   (buffer (and session (claude-code-ide-session-buffer session))))
              (if (buffer-live-p buffer)
                  (progn
                    (claude-code-ide--touch-session session-id)
                    (claude-code-ide--show-session-buffer buffer))
                (user-error "Buffer for session %s no longer exists" choice)))))
      (claude-code-ide-log "No related Claude Code sessions"))))

;;;###autoload
(defun claude-code-ide-list-sessions ()
  "List all active Claude Code sessions and switch to selected one."
  (interactive)
  (claude-code-ide--cleanup-dead-processes)
  (let ((sessions '()))
    (maphash (lambda (session-id _)
               (let* ((session (claude-code-ide--get-session session-id))
                      (directory (claude-code-ide-session-directory session))
                      (buffer (claude-code-ide-session-buffer session)))
                 (when (buffer-live-p buffer)
                   (push (cons (format "%s  %s"
                                       (abbreviate-file-name directory)
                                       (buffer-name buffer))
                               session-id)
                         sessions))))
             claude-code-ide--sessions)
    (if sessions
        (let ((choice (completing-read "Switch to Claude Code session: "
                                       sessions nil t)))
          (when choice
            (let* ((session-id (alist-get choice sessions nil nil #'string=))
                   (session (claude-code-ide--get-session session-id))
                   (buffer (and session
                                (claude-code-ide-session-buffer session))))
              (if (buffer-live-p buffer)
                  (progn
                    (claude-code-ide--touch-session session-id)
                    (claude-code-ide--show-session-buffer buffer))
                (user-error "Buffer for session %s no longer exists" choice)))))
      (claude-code-ide-log "No active Claude Code sessions"))))

;;;###autoload
(defun claude-code-ide-insert-at-mentioned ()
  "Insert selected text into Claude prompt.
When called from a Claude Code session buffer, uses the most
recent visible file-visiting buffer on the current frame."
  (interactive)
  (let* ((owner (claude-code-ide--session-for-buffer))
         (session
          (or (claude-code-ide-mcp--get-current-session)
              (and (null owner)
                   (when-let* ((project-dir
                                (claude-code-ide-mcp--get-buffer-project)))
                     (claude-code-ide-mcp--get-session-for-project project-dir))))))
    (if (and session (claude-code-ide-mcp-session-client session))
        (progn
          (claude-code-ide--touch-session
           (claude-code-ide-mcp-session-id session))
          (let ((ctx-buf (or (claude-code-ide--get-context-buffer)
                             (current-buffer))))
            (with-current-buffer ctx-buf
              (claude-code-ide-mcp-send-at-mentioned session))
            (claude-code-ide-debug "Sent selection to Claude Code")
            (when-let* ((buffer (claude-code-ide--get-session-buffer)))
              (claude-code-ide--maybe-switch-to-window buffer))))
      (user-error "Claude Code is not connected.  Please start Claude Code first"))))

;;;###autoload
(defun claude-code-ide-set-omp-prompt-command (command)
  "Set the leading slash COMMAND in the active Oh My Pi prompt."
  (interactive (list (read-string "OMP slash command: ")))
  (when (or (zerop (length command))
            (string-match-p "[[:space:]/]" command)
            (seq-some (lambda (char)
                        (or (< char 32)
                            (and (>= char 127) (<= char 159))))
                      command))
    (user-error "Command must not contain spaces, slashes, or control characters"))
  (if-let* ((buffer (claude-code-ide--get-session-buffer)))
      (with-current-buffer buffer
        (unless (eq (claude-code-ide--current-cli-type) 'omp)
          (user-error "The active session is not Oh My Pi"))
        (claude-code-ide-session-send-omp-packet "prompt" command))
    (user-error "No Oh My Pi session for this project")))

;;;###autoload
(defun claude-code-ide-send-escape ()
  "Send escape key to the Claude Code terminal buffer for the current project."
  (interactive)
  (if-let* ((buffer (claude-code-ide--get-session-buffer)))
      (with-current-buffer buffer
        (claude-code-ide--terminal-send-escape))
    (user-error "No Claude Code session for this project")))

;;;###autoload
(defun claude-code-ide-send-double-escape ()
  "Send double escape to the Claude Code terminal for the current project."
  (interactive)
  (if-let* ((buffer (claude-code-ide--get-session-buffer)))
      (with-current-buffer buffer
        (claude-code-ide--terminal-send-escape)
        (claude-code-ide--terminal-send-escape))
    (user-error "No Claude Code session for this project")))

;;;###autoload
(defun claude-code-ide-insert-newline ()
  "Insert a newline in the prompt for the current session.
Send LF to Oh My Pi and backslash followed by Enter to other agents."
  (interactive)
  (if-let* ((buffer (claude-code-ide--get-session-buffer)))
      (with-current-buffer buffer
        (if (eq (claude-code-ide--current-cli-type) 'omp)
            (claude-code-ide-session-send-string "\n")
          (claude-code-ide--terminal-send-string "\\")
          ;; Let the prompt process the backslash before Return.
          (sit-for 0.1)
          (claude-code-ide--terminal-send-return)))
    (user-error "No Claude Code session for this project")))

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
(cl-defun claude-code-ide-send-prompt (&optional prompt (paste t))
  "Send a prompt to the Claude Code terminal.
When called interactively, reads a prompt from the minibuffer.
When called programmatically, sends the given PROMPT string."
  (interactive)
  (if-let* ((buffer (claude-code-ide--get-session-buffer)))
      (let ((prompt-to-send (or prompt (read-string "Claude prompt: "))))
        (when (not (string-empty-p prompt-to-send))
          (with-current-buffer buffer
            (claude-code-ide--terminal-send-string prompt-to-send paste)
            ;; Small delay to ensure prompt text is processed before sending return
            (sit-for 0.1)
            (claude-code-ide--terminal-send-return))
          (claude-code-ide-debug "Sent prompt to Claude Code: %s" prompt-to-send)
          (claude-code-ide--maybe-switch-to-window buffer)))
    (user-error "No Claude Code session for this project")))

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
  (when-let* ((comment-str (claude-code-ide--comment-prefix)))
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
  (if-let* ((project (project-current nil)))
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
  (let ((ctx-buf (claude-code-ide--get-context-buffer))
        (target-buffer (claude-code-ide--get-session-buffer)))
    (unless ctx-buf
      (user-error "Current buffer is not visiting a file"))
    (when-let* ((prompt
                 (with-current-buffer ctx-buf
                   (cl-block finalize
                     (when (claude-code-ide--implement-todo--handle-done-line)
                       (cl-return-from finalize nil))
                     (when (claude-code-ide--implement-todo--handle-blank-line)
                       (cl-return-from finalize nil))
                     (claude-code-ide--implement-todo--build-prompt arg)))))
      (if target-buffer
          (with-current-buffer target-buffer
            (claude-code-ide-send-prompt prompt))
        (claude-code-ide-send-prompt prompt)))))

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

(defun claude-code-ide--format-selection-line-suffix (range prefix)
  "Return a line suffix for RANGE using PREFIX, or an empty string.
RANGE is a cons cell of 1-based start and end lines."
  (cond
   ((null range) "")
   ((= (car range) (cdr range))
    (format "%s%d" prefix (car range)))
   (t
    (format "%s%d-%d" prefix (car range) (cdr range)))))

;;;###autoload
(defun claude-code-ide-send-current-file ()
  "Send current buffer's file path with @ prefix to the Claude Code terminal.
The path is relative to the target session's directory, or the
absolute path when the file lies outside it (e.g. a file from a
different project).  When an evil visual selection or Emacs region
is active, appends a line range suffix like #L12-14 (or #L12 for a
single line).
When called from Dired or Treemacs, uses the file at point.
When called from a Claude Code session buffer, uses the most
recent visible file-visiting buffer on the current frame."
  (interactive)
  (let* ((context (claude-code-ide--get-file-reference-context))
         (file (car context))
         (ctx-buf (cdr context))
         (target-buffer (claude-code-ide--reference-target-buffer)))
    (unless file
      (user-error "Current buffer is not visiting a file"))
    (let ((reference-body
           (with-current-buffer (or ctx-buf (current-buffer))
             (let* ((path (claude-code-ide--file-reference-path
                           file target-buffer))
                    (range (when ctx-buf
                             (claude-code-ide--get-selection-line-range)))
                    (suffix (claude-code-ide--format-selection-line-suffix
                             range "#L")))
               (concat "@" path suffix)))))
      (if target-buffer
          (with-current-buffer target-buffer
            (claude-code-ide--send-reference-body reference-body))
        (claude-code-ide--send-reference-body reference-body)))))

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
         (reference-body
          (concat "@" (claude-code-ide--file-reference-path
                       (expand-file-name file root)))))
    (claude-code-ide--send-reference-body reference-body)))

;;;###autoload
(defun claude-code-ide-send-file-from-root ()
  "Send a file path with @ prefix, browsing from project root.
Like `claude-code-ide-send-file' with prefix argument."
  (interactive)
  (claude-code-ide-send-file t))

;;;###autoload
(defun claude-code-ide-send-file-from-home ()
  "Send an absolute file path with @ prefix, browsing from the home directory.
Always sends the full absolute path, unlike `claude-code-ide-send-file'
which relativizes the path to the session directory when possible."
  (interactive)
  (let* ((home (expand-file-name "~/"))
         (selected (read-file-name "File: " home))
         (reference-body (concat "@" (expand-file-name selected home))))
    (claude-code-ide--send-reference-body reference-body)))

;;;###autoload
(defun claude-code-ide-send-current-file-line-reference ()
  "Send the current file's absolute path, with an optional selected line suffix.
The reference format is /absolute/path or /absolute/path:LINE[-END]
when an evil visual selection or Emacs region is active.  Unlike
`claude-code-ide-send-current-file', this requires a live file buffer
context so selection state comes from the target file."
  (interactive)
  (let* ((context (claude-code-ide--get-file-reference-context))
         (file (car context))
         (ctx-buf (cdr context))
         (target-buffer (claude-code-ide--get-session-buffer)))
    (unless file
      (user-error "Current buffer is not visiting a file"))
    (unless ctx-buf
      (user-error "Current context does not provide a file line number"))
    (let ((reference-body
           (with-current-buffer ctx-buf
             (let* ((range (claude-code-ide--get-selection-line-range))
                    (suffix (claude-code-ide--format-selection-line-suffix
                             range ":")))
               (concat file suffix)))))
      (if target-buffer
          (with-current-buffer target-buffer
            (claude-code-ide--send-reference-body reference-body))
        (claude-code-ide--send-reference-body reference-body)))))

;;;###autoload
(defun claude-code-ide-toggle ()
  "Toggle visibility of Claude Code window for the current project."
  (interactive)
  (let* ((working-dir (claude-code-ide--get-attached-working-directory))
         (buffer (claude-code-ide--get-session-buffer)))
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
    (maphash (lambda (session-id _)
               (let* ((session (claude-code-ide--get-session session-id))
                      (directory (claude-code-ide-session-directory session))
                      (buffer (claude-code-ide-session-buffer session)))
                 (when (and buffer
                            (buffer-live-p buffer)
                            (get-buffer-window buffer))
                   ;; Window is visible, use the toggle function to close it
                   (claude-code-ide--toggle-existing-window buffer directory)
                   (setq found-visible t))))
             claude-code-ide--sessions)

    (cond
     ;; We found and closed visible windows
     (found-visible
      (message "Closed all Claude Code windows"))

     ;; No windows were visible, show the most recent one
     ((and claude-code-ide--last-accessed-buffer
           (buffer-live-p claude-code-ide--last-accessed-buffer))
      (claude-code-ide--touch-session-for-buffer
       claude-code-ide--last-accessed-buffer)
      (claude-code-ide--display-buffer-in-side-window claude-code-ide--last-accessed-buffer)
      (message "Opened most recent Claude Code session"))

     ;; No recent session available
     (t
      (user-error "No recent Claude Code session to toggle")))))

(claude-code-ide-manager--initialize)

(provide 'claude-code-ide)

;;; claude-code-ide.el ends here
