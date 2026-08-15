;;; claude-code-ide-transient.el --- Transient menus for Claude Code IDE  -*- lexical-binding: t; -*-

;; Copyright (C) 2025 Yoav Orot
;; Copyright (C) 2026 Yu-Fu Fu

;; Author: Yoav Orot
;; Maintainer: Yu-Fu Fu <yufu@yfu.tw>
;; Keywords: ai, claude, transient, menu

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

;; This file provides transient menus for Claude Code IDE, offering
;; a convenient interface for all Claude Code operations.

;;; Code:

(require 'files-x)
(require 'transient)
(require 'claude-code-ide-debug)

;; Declare functions from other files to avoid circular dependencies
(declare-function claude-code-ide "claude-code-ide" ())
(declare-function claude-code-ide-new-session "claude-code-ide" ())
(declare-function claude-code-ide-current-directory "claude-code-ide" ())
(declare-function claude-code-ide-resume "claude-code-ide" ())
(declare-function claude-code-ide-continue "claude-code-ide" ())
(declare-function claude-code-ide-stop "claude-code-ide" ())
(declare-function claude-code-ide-list-sessions "claude-code-ide" ())
(declare-function claude-code-ide-list-related-sessions "claude-code-ide" ())
(declare-function claude-code-ide-switch-to-buffer "claude-code-ide" ())
(declare-function claude-code-ide-insert-at-mentioned "claude-code-ide" ())
(declare-function claude-code-ide-send-escape "claude-code-ide" ())
(declare-function claude-code-ide-toggle "claude-code-ide" ())
(declare-function claude-code-ide-check-status "claude-code-ide" ())
(declare-function claude-code-ide--ensure-cli "claude-code-ide" ())
(declare-function claude-code-ide--get-project-root "claude-code-ide" ())
(declare-function claude-code-ide--start-session "claude-code-ide" (&optional continue resume directory force-new))
(declare-function claude-code-ide-session-id "claude-code-ide" (session))
(declare-function claude-code-ide-manager-switch-to-session "claude-code-ide-manager" (session-key &optional keep-manager-focus scope))
(declare-function claude-code-ide-manager--visible-sidebar-scope-for-frame "claude-code-ide-manager" (&optional frame))
(declare-function claude-code-ide-manager-toggle-sidebar "claude-code-ide-manager" ())
(declare-function claude-code-ide-manager-toggle-global-sidebar "claude-code-ide-manager" ())
(declare-function claude-code-ide-manager-toggle-repo-sidebar "claude-code-ide-manager" ())
(declare-function claude-code-ide-manager-open "claude-code-ide-manager" ())
(declare-function claude-code-ide-manager-rename-at-point "claude-code-ide-manager" ())
(declare-function claude-code-ide-manager-next-line "claude-code-ide-manager" ())
(declare-function claude-code-ide-manager-previous-line "claude-code-ide-manager" ())
(declare-function claude-code-ide-manager-switch-by-slot "claude-code-ide-manager" (slot))
(declare-function claude-code-ide-manager-focus "claude-code-ide-manager" ())
(declare-function claude-code-ide-manager-refresh "claude-code-ide-manager" ())
(declare-function claude-code-ide-mcp--active-sessions "claude-code-ide-mcp" ())
(declare-function claude-code-ide-mcp-session-project-dir "claude-code-ide-mcp" (session))
(declare-function claude-code-ide-mcp-session-port "claude-code-ide-mcp" (session))
(declare-function claude-code-ide-mcp-session-client "claude-code-ide-mcp" (session))
(declare-function claude-code-ide-mcp-session-buffer "claude-code-ide-mcp" (session))
(declare-function claude-code-ide-mcp-session-last-buffer "claude-code-ide-mcp" (session))
(declare-function claude-code-ide-mcp--get-current-session "claude-code-ide-mcp" ())
(declare-function claude-code-ide-mcp--get-session-for-project "claude-code-ide-mcp" (project-dir))
(declare-function claude-code-ide--get-current-directory "claude-code-ide" ())
(declare-function claude-code-ide--get-working-directory "claude-code-ide" ())
(declare-function claude-code-ide--current-cli-type "claude-code-ide" ())
(declare-function claude-code-ide-send-current-file "claude-code-ide" ())
(declare-function claude-code-ide-send-current-file-line-reference "claude-code-ide" ())
(declare-function claude-code-ide-send-file "claude-code-ide" (arg))
(declare-function claude-code-ide-send-file-from-root "claude-code-ide" ())
(declare-function claude-code-ide-implement-todo "claude-code-ide" (arg))

;; Declare variables
(defvar claude-code-ide-cli-path)
(defvar claude-code-ide--session-cli-type)
(defvar claude-code-ide-supported-agents)
(defvar claude-code-ide-debug)
(defvar claude-code-ide-window-side)
(defvar claude-code-ide-window-width)
(defvar claude-code-ide--suppress-initial-display)
(defvar claude-code-ide-window-height)
(defvar claude-code-ide-focus-on-open)
(defvar claude-code-ide-focus-claude-after-ediff)
(defvar claude-code-ide-show-claude-window-in-ediff)
(defvar claude-code-ide-use-ide-diff)
(defvar claude-code-ide-switch-tab-on-ediff)
(defvar claude-code-ide-use-side-window)
(defvar claude-code-ide-cli-debug)
(defvar claude-code-ide-cli-extra-flags)
(defvar claude-code-ide-bypass-permissions-by-default)
(defvar claude-code-ide-system-prompt)
(defvar claude-code-ide-manager--command-scope)
(defvar claude-code-ide-manager--open-target)
(defvar claude-code-ide-manager--open-scope)

;;; Helper Functions

(defun claude-code-ide--has-active-session-p ()
  "Check if there's an attached Claude Code session for the current buffer."
  (when (claude-code-ide-mcp--get-current-session) t))

(defun claude-code-ide--has-project-session-p ()
  "Check whether the project-root launch target already has an active session."
  (when (claude-code-ide-mcp--get-session-for-project
         (claude-code-ide--get-working-directory))
    t))

(defun claude-code-ide--dangerous-permissions-flag ()
  "Return the dangerous permissions flag for the current CLI type."
  (pcase (claude-code-ide--current-cli-type)
    ('claude "--dangerously-skip-permissions")
    ('codex "--dangerously-bypass-approvals-and-sandbox")
    ('opencode "--auto")
    ('omp "--auto-approve")
    (_ "")))

(defun claude-code-ide--permissions-bypass-available-p ()
  "Return non-nil when the current CLI has a permissions bypass flag."
  (not (string-empty-p (claude-code-ide--dangerous-permissions-flag))))

(defun claude-code-ide--transient-launch-flags (&optional bypass)
  "Return launch flags with permissions bypass when BYPASS or the default is set."
  (if (or bypass claude-code-ide-bypass-permissions-by-default)
      (string-trim (concat claude-code-ide-cli-extra-flags
                           " " (claude-code-ide--dangerous-permissions-flag)))
    claude-code-ide-cli-extra-flags))

(defun claude-code-ide--transient-cli-path (arg)
  "Return the one-shot CLI selected by prefix ARG, or the configured CLI."
  (if arg
      (completing-read "Agent: " claude-code-ide-supported-agents nil t)
    claude-code-ide-cli-path))

(defun claude-code-ide--has-current-directory-session-p ()
  "Check whether the current directory already has an active session."
  (when (claude-code-ide-mcp--get-session-for-project
         (claude-code-ide--get-current-directory))
    t))

(defun claude-code-ide--start-description ()
  "Dynamic description for starting another session."
  (if (and claude-code-ide-bypass-permissions-by-default
           (claude-code-ide--permissions-bypass-available-p))
      "Start new Claude Code session (skip permissions)"
    "Start new Claude Code session"))

(defun claude-code-ide--start-if-no-session (&optional bypass arg)
  "Start another Claude Code session for the current project.
When BYPASS is non-nil, bypass permissions.
With prefix ARG, select the CLI for this launch."
  (interactive (list nil current-prefix-arg))
  (let* ((claude-code-ide--session-cli-type
         (unless arg claude-code-ide--session-cli-type))
        (claude-code-ide-cli-path
         (claude-code-ide--transient-cli-path arg))
        (claude-code-ide-cli-extra-flags
         (claude-code-ide--transient-launch-flags bypass)))
    (claude-code-ide--start-session nil nil nil t)))

(defun claude-code-ide--continue-description ()
  "Dynamic description for continuing in another session."
  (if (and claude-code-ide-bypass-permissions-by-default
           (claude-code-ide--permissions-bypass-available-p))
      "Continue most recent conversation (skip permissions)"
    "Continue most recent conversation"))

(defun claude-code-ide--current-directory-description ()
  "Dynamic description for current-directory start command."
  (if (and claude-code-ide-bypass-permissions-by-default
           (claude-code-ide--permissions-bypass-available-p))
      "Start in current dir (skip permissions)"
    "Start in current dir"))

(defun claude-code-ide--current-directory-if-no-session (&optional bypass arg)
  "Start another Claude Code session in the current directory.
When BYPASS is non-nil, bypass permissions.
With prefix ARG, select the CLI for this launch."
  (interactive (list nil current-prefix-arg))
  (let* ((claude-code-ide--session-cli-type
         (unless arg claude-code-ide--session-cli-type))
        (claude-code-ide-cli-path
         (claude-code-ide--transient-cli-path arg))
        (claude-code-ide-cli-extra-flags
         (claude-code-ide--transient-launch-flags bypass)))
    (claude-code-ide--start-session
     nil nil (claude-code-ide--get-current-directory) t)))

(defun claude-code-ide--current-directory-skip-description ()
  "Dynamic description for current-directory start with permissions bypass."
  (if (claude-code-ide--permissions-bypass-available-p)
      "Start in current dir (skip permissions)"
    "Start in current dir"))

(defun claude-code-ide--current-directory-skip-permissions (&optional arg)
  "Start Claude Code in the current directory with permissions bypass."
  (interactive "P")
  (claude-code-ide--current-directory-if-no-session t arg))

(defun claude-code-ide--continue-if-no-session (&optional bypass arg)
  "Continue Claude Code in another session.
When BYPASS is non-nil, bypass permissions.
With prefix ARG, select the CLI for this launch."
  (interactive (list nil current-prefix-arg))
  (let* ((claude-code-ide--session-cli-type
         (unless arg claude-code-ide--session-cli-type))
        (claude-code-ide-cli-path
         (claude-code-ide--transient-cli-path arg))
        (claude-code-ide-cli-extra-flags
         (claude-code-ide--transient-launch-flags bypass)))
    (claude-code-ide--start-session t nil nil t)))

(defun claude-code-ide--resume-description ()
  "Dynamic description for resuming in another session."
  (if (and claude-code-ide-bypass-permissions-by-default
           (claude-code-ide--permissions-bypass-available-p))
      "Resume session (skip permissions)"
    "Resume session (from previous conversation)"))

(defun claude-code-ide--resume-if-no-session (&optional bypass arg)
  "Resume Claude Code in another session.
When BYPASS is non-nil, bypass permissions.
With prefix ARG, select the CLI for this launch."
  (interactive (list nil current-prefix-arg))
  (let* ((claude-code-ide--session-cli-type
         (unless arg claude-code-ide--session-cli-type))
        (claude-code-ide-cli-path
         (claude-code-ide--transient-cli-path arg))
        (claude-code-ide-cli-extra-flags
         (claude-code-ide--transient-launch-flags bypass)))
    (claude-code-ide--start-session nil t nil t)))

(defun claude-code-ide--start-skip-description ()
  "Dynamic description for start with --dangerously-skip-permissions."
  (if (claude-code-ide--permissions-bypass-available-p) "Start (skip permissions)" "Start"))

(defun claude-code-ide--start-skip-permissions (&optional arg)
  "Start Claude Code with --dangerously-skip-permissions."
  (interactive "P")
  (claude-code-ide--start-if-no-session t arg))

(defun claude-code-ide--continue-skip-description ()
  "Dynamic description for continue with --dangerously-skip-permissions."
  (if (claude-code-ide--permissions-bypass-available-p) "Continue (skip permissions)" "Continue"))

(defun claude-code-ide--continue-skip-permissions (&optional arg)
  "Continue Claude Code with --dangerously-skip-permissions."
  (interactive "P")
  (claude-code-ide--continue-if-no-session t arg))

(defun claude-code-ide--resume-skip-description ()
  "Dynamic description for resume with --dangerously-skip-permissions."
  (if (claude-code-ide--permissions-bypass-available-p) "Resume (skip permissions)" "Resume"))

(defun claude-code-ide--resume-skip-permissions (&optional arg)
  "Resume Claude Code with --dangerously-skip-permissions."
  (interactive "P")
  (claude-code-ide--resume-if-no-session t arg))

(defun claude-code-ide-manager--open-target-label ()
  "Return a readable label for the selected manager-open target."
  (if claude-code-ide-manager--open-target
      (abbreviate-file-name claude-code-ide-manager--open-target)
    "<no target>"))

(defun claude-code-ide-manager--open-action-description (action &optional bypass)
  "Return manager ACTION label, disclosing an available BYPASS."
  (format "%s %s%s" action
          (claude-code-ide-manager--open-target-label)
          (if (and (or bypass claude-code-ide-bypass-permissions-by-default)
                   (claude-code-ide--permissions-bypass-available-p))
              " (skip permissions)"
            "")))

(defun claude-code-ide-transient-manager-open ()
  "Open against the currently visible manager sidebar scope.
This transient entry does not require point to be in a manager buffer."
  (interactive)
  (let ((scope (claude-code-ide-manager--visible-sidebar-scope-for-frame)))
    (unless scope
      (user-error "No manager sidebar is visible"))
    (let ((claude-code-ide-manager--command-scope scope))
      (claude-code-ide-manager-open))))

(defun claude-code-ide-manager--run-open-action (continue resume &optional dangerous)
  "Run a manager-open action against the selected target.
When CONTINUE is non-nil, continue the selected target.
When RESUME is non-nil, resume the selected target.
When DANGEROUS is non-nil, append the agent-specific dangerous flag."
  (let ((target claude-code-ide-manager--open-target)
        (scope claude-code-ide-manager--open-scope)
        (claude-code-ide--suppress-initial-display t)
        (claude-code-ide-cli-extra-flags
         (claude-code-ide--transient-launch-flags dangerous)))
    (unwind-protect
        (let ((session (claude-code-ide--start-session continue resume target)))
          (when (and scope session)
            (claude-code-ide-manager-switch-to-session
             (claude-code-ide-session-id session) nil scope)))
      (setq claude-code-ide-manager--open-target nil)
      (setq claude-code-ide-manager--open-scope nil))))

(defun claude-code-ide-manager-open-start ()
  "Start a new session in the manager-selected target."
  (interactive)
  (claude-code-ide-manager--run-open-action nil nil))

(defun claude-code-ide-manager-open-start-skip-permissions ()
  "Start a new session in the manager-selected target with dangerous permissions bypass."
  (interactive)
  (claude-code-ide-manager--run-open-action nil nil t))

(defun claude-code-ide-manager-open-continue ()
  "Continue in the manager-selected target."
  (interactive)
  (claude-code-ide-manager--run-open-action t nil))

(defun claude-code-ide-manager-open-continue-skip-permissions ()
  "Continue in the manager-selected target with dangerous permissions bypass."
  (interactive)
  (claude-code-ide-manager--run-open-action t nil t))

(defun claude-code-ide-manager-open-resume ()
  "Resume in the manager-selected target."
  (interactive)
  (claude-code-ide-manager--run-open-action nil t))

(defun claude-code-ide-manager-open-resume-skip-permissions ()
  "Resume in the manager-selected target with dangerous permissions bypass."
  (interactive)
  (claude-code-ide-manager--run-open-action nil t t))

(transient-define-prefix claude-code-ide-manager-open-menu ()
  "Transient for starting or resuming a manager-selected target."
  [["Manager Open"
    ("s" claude-code-ide-manager-open-start
     :description (lambda () (claude-code-ide-manager--open-action-description "Start")))
    ("S" claude-code-ide-manager-open-start-skip-permissions
     :description (lambda () (claude-code-ide-manager--open-action-description "Start" t)))
    ("c" claude-code-ide-manager-open-continue
     :description (lambda () (claude-code-ide-manager--open-action-description "Continue")))
    ("C" claude-code-ide-manager-open-continue-skip-permissions
     :description (lambda () (claude-code-ide-manager--open-action-description "Continue" t)))
    ("r" claude-code-ide-manager-open-resume
     :description (lambda () (claude-code-ide-manager--open-action-description "Resume")))
    ("R" claude-code-ide-manager-open-resume-skip-permissions
     :description (lambda () (claude-code-ide-manager--open-action-description "Resume" t)))]] )

(defun claude-code-ide--session-status ()
  "Return a string describing the current session status."
  (let ((cli-path (or claude-code-ide-cli-path "unknown")))
    (if-let ((session (claude-code-ide-mcp--get-current-session)))
        (let* ((project-dir (claude-code-ide-mcp-session-project-dir session))
               (project-name (file-name-nondirectory (directory-file-name project-dir))))
          (propertize (format "Active session in [%s] (%s)" project-name cli-path)
                      'face 'success))
      (propertize (format "No active session (%s)" cli-path)
                  'face 'transient-inactive-value))))

(defun claude-code-ide--project-dir-locals-file (&optional project-root)
  "Return the dir-locals file for PROJECT-ROOT."
  (expand-file-name dir-locals-file
                    (file-name-as-directory
                     (or project-root (claude-code-ide--get-project-root)))))

(defun claude-code-ide--save-project-dir-local-cli-path (operation &optional cli-path project-root)
  "Persist a project-local CLI path using OPERATION at PROJECT-ROOT.
OPERATION is either `set' or `clear'.  CLI-PATH is used when OPERATION is `set'."
  (let* ((root (file-name-as-directory
                (or project-root (claude-code-ide--get-project-root))))
         (file (claude-code-ide--project-dir-locals-file root))
         (existing-buffer (find-buffer-visiting file)))
    (when (or (eq operation 'set)
              (file-exists-p file))
      (save-window-excursion
        (save-current-buffer
          (pcase operation
            ('set
             (add-dir-local-variable nil 'claude-code-ide-cli-path cli-path file))
            ('clear
             (delete-dir-local-variable nil 'claude-code-ide-cli-path file)))
          (when-let ((buffer (get-file-buffer file)))
            (with-current-buffer buffer
              (save-buffer))
            (unless existing-buffer
              (kill-buffer buffer))))))))

(defun claude-code-ide-toggle-window ()
  "Toggle visibility of Claude Code window.
If called from a Claude vterm buffer, toggle that window.
Otherwise, if multiple sessions exist, prompt for selection."
  (interactive)
  (claude-code-ide-toggle))

(defun claude-code-ide-show-version-info ()
  "Show detailed version information for Claude Code CLI."
  (interactive)
  (if (claude-code-ide--ensure-cli)
      (let ((version-output
             (with-temp-buffer
               (call-process claude-code-ide-cli-path nil t nil "--version")
               (buffer-string))))
        (with-output-to-temp-buffer "*Claude Code Version*"
          (princ "Claude Code CLI Version Information\n")
          (princ "===================================\n\n")
          (princ version-output)
          (princ "\n\nExecutable path: ")
          (princ (executable-find claude-code-ide-cli-path))))
    (user-error "Claude Code CLI not available")))

(defun claude-code-ide-show-mcp-sessions ()
  "Show information about active MCP sessions."
  (interactive)
  (let ((sessions (claude-code-ide-mcp--active-sessions)))
    (if sessions
        (with-output-to-temp-buffer "*Claude Code MCP Sessions*"
          (princ "Active MCP Sessions\n")
          (princ "==================\n\n")
          (dolist (session sessions)
            (princ (format "Project: %s\n" (claude-code-ide-mcp-session-project-dir session)))
            (princ (format "  Port: %d\n" (claude-code-ide-mcp-session-port session)))
            (princ (format "  Connected: %s\n"
                           (if (claude-code-ide-mcp-session-client session) "Yes" "No")))
            (princ (format "  Buffer: %s\n"
                           (if (claude-code-ide-mcp-session-last-buffer session)
                               (buffer-name (claude-code-ide-mcp-session-last-buffer session))
                             "None")))
            (princ "\n")))
      (claude-code-ide-log "No active MCP sessions"))))

(defun claude-code-ide-show-active-ports ()
  "Show active ports used by MCP servers."
  (interactive)
  (let ((sessions (claude-code-ide-mcp--active-sessions)))
    (if sessions
        (with-output-to-temp-buffer "*Claude Code Active Ports*"
          (princ "Active MCP Server Ports\n")
          (princ "======================\n\n")
          (dolist (session sessions)
            (princ (format "Port %d: %s\n"
                           (claude-code-ide-mcp-session-port session)
                           (abbreviate-file-name (claude-code-ide-mcp-session-project-dir session))))))
      (claude-code-ide-log "No active MCP servers"))))

(defun claude-code-ide-toggle-debug-mode ()
  "Toggle Claude Code debug mode."
  (interactive)
  (setq claude-code-ide-debug (not claude-code-ide-debug))
  (claude-code-ide-log "Debug mode %s" (if claude-code-ide-debug "enabled" "disabled")))

;;; Transient Infix Classes

(transient-define-suffix claude-code-ide--set-window-side (side)
  "Set window side."
  :description "Set window side"
  (interactive (list (intern (completing-read "Window side: "
                                              '("left" "right" "top" "bottom")
                                              nil t nil nil
                                              (symbol-name claude-code-ide-window-side)))))
  (setq claude-code-ide-window-side side)
  (claude-code-ide-log "Window side set to %s" side))

(transient-define-suffix claude-code-ide--set-window-width (width)
  "Set window width."
  :description "Set window width"
  (interactive (list (read-number "Window width: " claude-code-ide-window-width)))
  (setq claude-code-ide-window-width width)
  (claude-code-ide-log "Window width set to %d" width))

(transient-define-suffix claude-code-ide--set-window-height (height)
  "Set window height."
  :description "Set window height"
  (interactive (list (read-number "Window height: " claude-code-ide-window-height)))
  (setq claude-code-ide-window-height height)
  (claude-code-ide-log "Window height set to %d" height))

(transient-define-suffix claude-code-ide--set-cli-path (path)
  "Set CLI path."
  :description "Set CLI path"
  (interactive (list (read-file-name "Claude CLI path: " nil claude-code-ide-cli-path t)))
  (setq claude-code-ide-cli-path path)
  (claude-code-ide-log "CLI path set to %s" path))

(transient-define-suffix claude-code-ide--set-project-agent (agent)
  "Set a project-local agent in .dir-locals.el."
  :description "Set project agent"
  (interactive
   (list (completing-read "Project agent: "
                          claude-code-ide-supported-agents
                          nil t nil nil
                          (and (member claude-code-ide-cli-path
                                       claude-code-ide-supported-agents)
                               claude-code-ide-cli-path))))
  (let ((project-root (claude-code-ide--get-project-root)))
    (claude-code-ide--save-project-dir-local-cli-path 'set agent project-root)
    (setq-local claude-code-ide-cli-path agent)
    (claude-code-ide-log "Project agent set to %s in %s" agent project-root)))

(transient-define-suffix claude-code-ide--clear-project-agent ()
  "Clear the project-local agent override from .dir-locals.el."
  :description "Clear project agent"
  (interactive)
  (let ((project-root (claude-code-ide--get-project-root)))
    (claude-code-ide--save-project-dir-local-cli-path 'clear nil project-root)
    (kill-local-variable 'claude-code-ide-cli-path)
    (claude-code-ide-log "Project agent cleared in %s" project-root)))

(transient-define-suffix claude-code-ide--set-cli-extra-flags (flags)
  "Set additional CLI flags."
  :description "Set additional CLI flags"
  (interactive (list (read-string "Additional CLI flags: " claude-code-ide-cli-extra-flags)))
  (setq claude-code-ide-cli-extra-flags flags)
  (claude-code-ide-log "CLI extra flags set to %s" flags))

(transient-define-suffix claude-code-ide--set-system-prompt (prompt)
  "Set the system prompt to append."
  :description "Set system prompt"
  (interactive (list (if claude-code-ide-system-prompt
                         (read-string "System prompt (leave empty to disable): "
                                      claude-code-ide-system-prompt)
                       (read-string "System prompt: "))))
  (setq claude-code-ide-system-prompt (if (string-empty-p prompt) nil prompt))
  (claude-code-ide-log "System prompt %s"
                       (if claude-code-ide-system-prompt
                           (format "set to: %s" claude-code-ide-system-prompt)
                         "disabled")))

;;; Transient Suffix Functions

(transient-define-suffix claude-code-ide--toggle-focus-on-open ()
  "Toggle focus on open setting."
  (interactive)
  (setq claude-code-ide-focus-on-open (not claude-code-ide-focus-on-open))
  (claude-code-ide-log "Focus on open %s" (if claude-code-ide-focus-on-open "enabled" "disabled")))

(transient-define-suffix claude-code-ide--toggle-focus-after-ediff ()
  "Toggle focus after ediff setting."
  (interactive)
  (setq claude-code-ide-focus-claude-after-ediff (not claude-code-ide-focus-claude-after-ediff))
  (claude-code-ide-log "Focus after ediff %s" (if claude-code-ide-focus-claude-after-ediff "enabled" "disabled")))

(transient-define-suffix claude-code-ide--toggle-show-claude-in-ediff ()
  "Toggle showing Claude window during ediff."
  (interactive)
  (setq claude-code-ide-show-claude-window-in-ediff (not claude-code-ide-show-claude-window-in-ediff))
  (claude-code-ide-log "Show Claude window in ediff %s" (if claude-code-ide-show-claude-window-in-ediff "enabled" "disabled")))

(transient-define-suffix claude-code-ide--toggle-use-side-window ()
  "Toggle use side window setting."
  (interactive)
  (setq claude-code-ide-use-side-window (not claude-code-ide-use-side-window))
  (claude-code-ide-log "Use side window %s" (if claude-code-ide-use-side-window "enabled" "disabled")))

(transient-define-suffix claude-code-ide--toggle-use-ide-diff ()
  "Toggle IDE diff viewer setting."
  (interactive)
  (setq claude-code-ide-use-ide-diff (not claude-code-ide-use-ide-diff))
  (claude-code-ide-log "IDE diff viewer %s" (if claude-code-ide-use-ide-diff "enabled" "disabled")))

(transient-define-suffix claude-code-ide--toggle-switch-tab-on-ediff ()
  "Toggle tab switching on ediff setting."
  (interactive)
  (setq claude-code-ide-switch-tab-on-ediff (not claude-code-ide-switch-tab-on-ediff))
  (claude-code-ide-log "Switch tab on ediff %s" (if claude-code-ide-switch-tab-on-ediff "enabled" "disabled")))

(transient-define-suffix claude-code-ide--toggle-cli-debug ()
  "Toggle CLI debug mode."
  (interactive)
  (setq claude-code-ide-cli-debug (not claude-code-ide-cli-debug))
  (claude-code-ide-log "CLI debug mode %s" (if claude-code-ide-cli-debug "enabled" "disabled")))

(defun claude-code-ide--save-config ()
  "Save current configuration to custom file."
  (interactive)
  (customize-save-variable 'claude-code-ide-window-side claude-code-ide-window-side)
  (customize-save-variable 'claude-code-ide-window-width claude-code-ide-window-width)
  (customize-save-variable 'claude-code-ide-window-height claude-code-ide-window-height)
  (customize-save-variable 'claude-code-ide-focus-on-open claude-code-ide-focus-on-open)
  (customize-save-variable 'claude-code-ide-focus-claude-after-ediff claude-code-ide-focus-claude-after-ediff)
  (customize-save-variable 'claude-code-ide-show-claude-window-in-ediff claude-code-ide-show-claude-window-in-ediff)
  (customize-save-variable 'claude-code-ide-use-ide-diff claude-code-ide-use-ide-diff)
  (customize-save-variable 'claude-code-ide-switch-tab-on-ediff claude-code-ide-switch-tab-on-ediff)
  (customize-save-variable 'claude-code-ide-use-side-window claude-code-ide-use-side-window)
  (customize-save-variable 'claude-code-ide-cli-path claude-code-ide-cli-path)
  (customize-save-variable 'claude-code-ide-cli-extra-flags claude-code-ide-cli-extra-flags)
  (customize-save-variable 'claude-code-ide-system-prompt claude-code-ide-system-prompt)
  (claude-code-ide-log "Configuration saved to custom file"))

;;; Transient Menus

;;;###autoload (autoload 'claude-code-ide-menu "claude-code-ide-transient" "Claude Code IDE main menu." t)
(transient-define-prefix claude-code-ide-menu ()
  "Claude Code IDE main menu."
  [:description claude-code-ide--session-status]
  ["Claude Code IDE" :description claude-code-ide--session-status
   ["Session Management"
    ("s" claude-code-ide--start-if-no-session :description claude-code-ide--start-description)
    ("S" claude-code-ide--start-skip-permissions :description claude-code-ide--start-skip-description)
    ("d" claude-code-ide--current-directory-if-no-session :description claude-code-ide--current-directory-description)
    ("D" claude-code-ide--current-directory-skip-permissions :description claude-code-ide--current-directory-skip-description)
    ("c" claude-code-ide--continue-if-no-session :description claude-code-ide--continue-description)
    ("C" claude-code-ide--continue-skip-permissions :description claude-code-ide--continue-skip-description)
    ("r" claude-code-ide--resume-if-no-session :description claude-code-ide--resume-description)
    ("R" claude-code-ide--resume-skip-permissions :description claude-code-ide--resume-skip-description)
    ("N" "New session" claude-code-ide-new-session)
    ("q" "Stop current session" claude-code-ide-stop)
    ("l" "List related sessions" claude-code-ide-list-related-sessions)
    ("L" "List all sessions" claude-code-ide-list-sessions)]
   ["Manager"
    ("t" "Toggle default manager" claude-code-ide-manager-toggle-sidebar)
    ("T" "Toggle global manager" claude-code-ide-manager-toggle-global-sidebar)
    ("o" "Open from visible manager" claude-code-ide-transient-manager-open)
    ("w" "Toggle repo manager" claude-code-ide-manager-toggle-repo-sidebar)
    ("n" "Next manager session" claude-code-ide-manager-next-line)
    ("p" "Previous manager session" claude-code-ide-manager-previous-line)
    ("v" "Rename manager session" claude-code-ide-manager-rename-at-point)
    ("P" "Pin current manager session" claude-code-ide-manager-toggle-current-session-pin)
    ("1" "Manager slot 1" (lambda () (interactive) (claude-code-ide-manager-switch-by-slot 1)))
    ("2" "Manager slot 2" (lambda () (interactive) (claude-code-ide-manager-switch-by-slot 2)))
    ("3" "Manager slot 3" (lambda () (interactive) (claude-code-ide-manager-switch-by-slot 3)))
    ("4" "Manager slot 4" (lambda () (interactive) (claude-code-ide-manager-switch-by-slot 4)))
    ("5" "Manager slot 5" (lambda () (interactive) (claude-code-ide-manager-switch-by-slot 5)))
    ("6" "Manager slot 6" (lambda () (interactive) (claude-code-ide-manager-switch-by-slot 6)))
    ("7" "Manager slot 7" (lambda () (interactive) (claude-code-ide-manager-switch-by-slot 7)))
    ("8" "Manager slot 8" (lambda () (interactive) (claude-code-ide-manager-switch-by-slot 8)))
    ("9" "Manager slot 9" (lambda () (interactive) (claude-code-ide-manager-switch-by-slot 9)))
    ("0" "Manager slot 10" (lambda () (interactive) (claude-code-ide-manager-switch-by-slot 10)))
    ("M" "Focus manager" claude-code-ide-manager-focus)
    ("g" "Refresh manager" claude-code-ide-manager-refresh)]
   ["Navigation"
    ("b" "Switch to Claude buffer" claude-code-ide-switch-to-buffer)
    ;; ("w" "Toggle window visibility" claude-code-ide-toggle-window)
    ;; ("W" "Toggle recent window" claude-code-ide-toggle-recent)
    ]
   ["Interaction"
    ("i" "Implement TODO" claude-code-ide-implement-todo)
    ("@" "Send current file @path" claude-code-ide-send-current-file)
    ("#" "Send current file path[:range]" claude-code-ide-send-current-file-line-reference)
    ("f" "Send file @path" claude-code-ide-send-file)
    ("F" "Send file @path (from root)" claude-code-ide-send-file-from-root)
    ("e" "Send escape key" claude-code-ide-send-escape)
    ("x" "Clear (double escape)" claude-code-ide-send-double-escape)]
   ["Submenus"
    ("<f12>" "Configuration" claude-code-ide-config-menu)
    ("<f11>" "Debugging" claude-code-ide-debug-menu)]])

(transient-define-prefix claude-code-ide-config-menu ()
  "Claude Code configuration menu."
  ["Claude Code Configuration"
   ["Window Settings"
    ("s" "Set window side" claude-code-ide--set-window-side)
    ("w" "Set window width" claude-code-ide--set-window-width)
    ("h" "Set window height" claude-code-ide--set-window-height)
    ("f" "Toggle focus on open" claude-code-ide--toggle-focus-on-open
     :description (lambda () (format "Focus on open (%s)"
                                     (if claude-code-ide-focus-on-open "ON" "OFF"))))
    ("e" "Toggle focus after ediff" claude-code-ide--toggle-focus-after-ediff
     :description (lambda () (format "Focus after ediff (%s)"
                                     (if claude-code-ide-focus-claude-after-ediff "ON" "OFF"))))
    ("E" "Toggle show Claude in ediff" claude-code-ide--toggle-show-claude-in-ediff
     :description (lambda () (format "Show Claude in ediff (%s)"
                                     (if claude-code-ide-show-claude-window-in-ediff "ON" "OFF"))))
    ("i" "Toggle IDE diff viewer" claude-code-ide--toggle-use-ide-diff
     :description (lambda () (format "IDE diff viewer (%s)"
                                     (if claude-code-ide-use-ide-diff "ON" "OFF"))))
    ("t" "Toggle tab switching on ediff" claude-code-ide--toggle-switch-tab-on-ediff
     :description (lambda () (format "Tab switch on ediff (%s)"
                                     (if claude-code-ide-switch-tab-on-ediff "ON" "OFF"))))
    ("u" "Toggle side window" claude-code-ide--toggle-use-side-window
     :description (lambda () (format "Use side window (%s)"
                                     (if claude-code-ide-use-side-window "ON" "OFF"))))]
   ["CLI Settings"
    ("p" "Set CLI path" claude-code-ide--set-cli-path)
    ("P" "Set project agent" claude-code-ide--set-project-agent)
    ("c" "Clear project agent" claude-code-ide--clear-project-agent)
    ("x" "Set extra CLI flags" claude-code-ide--set-cli-extra-flags)
    ("a" "Set system prompt" claude-code-ide--set-system-prompt)]]
  ["Save"
   ("S" "Save configuration" claude-code-ide--save-config)])

(transient-define-prefix claude-code-ide-debug-menu ()
  "Claude Code debug menu."
  ["Claude Code Debug"
   ["Status"
    ("S" "Check CLI status" claude-code-ide-check-status)
    ("v" "Show version info" claude-code-ide-show-version-info)]
   ["Debug Settings"
    ("d" "Toggle debug mode" claude-code-ide-toggle-debug-mode
     :description (lambda () (format "Debug mode (%s)"
                                     (if claude-code-ide-debug "ON" "OFF"))))
    ("D" "Toggle CLI debug mode" claude-code-ide--toggle-cli-debug
     :description (lambda () (format "CLI debug mode (%s)"
                                     (if claude-code-ide-cli-debug "ON" "OFF"))))]
   ["Debug Logs"
    ("l" "Show debug log" claude-code-ide-show-debug)
    ("c" "Clear debug log" claude-code-ide-clear-debug)]
   ["MCP Server"
    ("m" "Show MCP sessions" claude-code-ide-show-mcp-sessions)
    ("p" "Show active ports" claude-code-ide-show-active-ports)]])

(provide 'claude-code-ide-transient)

;;; claude-code-ide-transient.el ends here
