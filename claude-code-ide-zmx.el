;;; claude-code-ide-zmx.el --- zmx-backed persistent sessions -*- lexical-binding: t; -*-

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

;; Thin adapter around the external `zmx' terminal-session backend.
;; When `claude-code-ide-use-zmx' is non-nil, agent CLIs run inside a
;; zmx session (`zmx attach NAME CMD...'), so the agent process
;; survives buffer kills and Emacs restarts and any terminal can
;; reattach.  Emacs is one attach client among several; zmx owns the
;; process (see docs/adr/0001-zmx-backed-agent-sessions.md).
;;
;; zmx is an optional external binary: this file never requires it at
;; load time and signals a `user-error' at the point of use when it is
;; missing.  All subprocess traffic funnels through
;; `claude-code-ide-zmx--call' so tests can mock one function.

;;; Code:

(require 'seq)
(require 'subr-x)

(defvar claude-code-ide-agent-definitions)
(defvar claude-code-ide-cli-path)
(declare-function claude-code-ide--cli-type-for-command "claude-code-ide" (command))

(defcustom claude-code-ide-use-zmx nil
  "When non-nil, run agent CLIs inside zmx sessions.
The agent process then survives buffer kills and Emacs exits.
Killing a session buffer only detaches; use `claude-code-ide-stop'
to kill the underlying zmx session.

Note: environment variables (for example MCP/SSE ports) are frozen
when the zmx session is created.  Reattaching from another Emacs
instance or a terminal keeps the original environment, so port-based
integrations break after such a switch."
  :type 'boolean
  :group 'claude-code-ide)

(defcustom claude-code-ide-zmx-program "zmx"
  "Name or path of the zmx executable."
  :type 'string
  :group 'claude-code-ide)

(defcustom claude-code-ide-zmx-session-prefix "cci-"
  "Leading component of generated zmx session names."
  :type 'string
  :group 'claude-code-ide)

(defvar claude-code-ide-zmx--pending-name nil
  "zmx session name for the terminal being created, or nil.
Let-bound around terminal creation by the session layer.")

(defvar claude-code-ide-zmx--pending-attach-only nil
  "Non-nil when the pending zmx launch reattaches without a command.
Let-bound together with `claude-code-ide-zmx--pending-name'.")

;;; Subprocess plumbing

(defun claude-code-ide-zmx--ensure ()
  "Signal a `user-error' unless the zmx executable is available."
  (unless (executable-find claude-code-ide-zmx-program)
    (user-error "Cannot find `%s'; install zmx or customize `claude-code-ide-zmx-program'"
                claude-code-ide-zmx-program)))

(defun claude-code-ide-zmx--call (&rest args)
  "Run zmx with ARGS and return trimmed stdout.
Signal an error when zmx exits nonzero."
  (with-temp-buffer
    (let ((status (apply #'call-process claude-code-ide-zmx-program
                         nil t nil args)))
      (unless (eq status 0)
        (error "zmx %s failed (%s): %s"
               (string-join args " ") status
               (string-trim (buffer-string))))
      (string-trim (buffer-string)))))

;;; Listing

(defun claude-code-ide-zmx--parse-list-line (line)
  "Parse a tab-separated key=value LINE from `zmx list' into a plist.
Return nil for lines without a name field."
  (let (plist)
    (dolist (field (split-string (string-trim line) "\t" t))
      (when (string-match "\\`\\([^=]+\\)=\\(.*\\)\\'" field)
        (setq plist (plist-put plist
                               (intern (concat ":" (match-string 1 field)))
                               (match-string 2 field)))))
    (and (plist-get plist :name) plist)))

(defun claude-code-ide-zmx-list-sessions ()
  "Return active zmx sessions as plists with at least :name.
Detailed rows also carry :start_dir, :cmd, :pid, and friends.
Older zmx builds that print bare names yield name-only plists."
  (delq nil
        (mapcar (lambda (line)
                  (or (claude-code-ide-zmx--parse-list-line line)
                      (let ((name (string-trim line)))
                        (and (not (string-empty-p name))
                             (not (string-prefix-p "no sessions found" name))
                             (list :name name)))))
                (split-string (claude-code-ide-zmx--call "list") "\n" t))))

;;; Naming

(defun claude-code-ide-zmx--sanitize (name)
  "Return NAME lowercased with non-alphanumeric runs collapsed to `-'."
  (string-trim (replace-regexp-in-string "[^a-z0-9]+" "-" (downcase name)) "-" "-"))

(defun claude-code-ide-zmx--offer-prefix (cli-type directory)
  "Return the zmx name prefix for CLI-TYPE sessions in DIRECTORY."
  (format "%s%s-%s-"
          claude-code-ide-zmx-session-prefix
          cli-type
          (claude-code-ide-zmx--sanitize
           (file-name-nondirectory (directory-file-name directory)))))

(defun claude-code-ide-zmx-session-name (cli-type directory session-id)
  "Return the zmx session name for CLI-TYPE, DIRECTORY, and SESSION-ID.
The unique suffix reuses the random tail of SESSION-ID."
  (concat (claude-code-ide-zmx--offer-prefix cli-type directory)
          (car (last (split-string session-id "-")))))

(defun claude-code-ide-zmx--eligible-sessions (cli-type directory live-names &optional orphans-only)
  "Return names of zmx sessions for CLI-TYPE in DIRECTORY, excluding LIVE-NAMES.
A session is eligible when its name carries the generated offer
prefix, or when its start_dir is DIRECTORY and its command runs the
same agent CLI (sessions started outside Emacs).  LIVE-NAMES are zmx
names already attached in this Emacs instance.  With ORPHANS-ONLY,
keep only sessions zmx reports as having zero attached clients; rows
without a clients field (older zmx builds that print bare names) are
dropped."
  (let ((prefix (claude-code-ide-zmx--offer-prefix cli-type directory))
        (dir (file-name-as-directory (expand-file-name directory))))
    (mapcar (lambda (session) (plist-get session :name))
            (seq-filter
             (lambda (session)
               (let ((name (plist-get session :name))
                     (start-dir (plist-get session :start_dir)))
                 (and (not (member name live-names))
                      (or (not orphans-only)
                          (equal (plist-get session :clients) "0"))
                      (or (string-prefix-p prefix name)
                          (and start-dir
                               (equal (file-name-as-directory
                                       (expand-file-name start-dir))
                                      dir)
                               (let ((cli (claude-code-ide-zmx-infer-cli-command
                                           (plist-get session :cmd))))
                                 (and cli
                                      (eq (claude-code-ide--cli-type-for-command cli)
                                          cli-type))))))))
             (claude-code-ide-zmx-list-sessions)))))

;;; Command wrapping

(defun claude-code-ide-zmx-wrap-command (name &optional cmd)
  "Return a shell command attaching to zmx session NAME.
With CMD (a shell command string), the session runs CMD when it does
not exist yet; without CMD the result only reattaches."
  (combine-and-quote-strings
   (append (list claude-code-ide-zmx-program "attach" name)
           (and cmd (split-string-and-unquote cmd)))))

;;; Adoption support

(defun claude-code-ide-zmx-infer-cli-command (cmd)
  "Return the agent CLI command matching zmx CMD string, or nil.
Skips shell wrapper words (command, exec, env, nohup) and VAR=value
assignments, then matches the base name of the first real word against
`claude-code-ide-agent-definitions' and `claude-code-ide-cli-path'."
  (when (and cmd (not (string-empty-p (string-trim cmd))))
    (let* ((words (seq-drop-while
                   (lambda (word)
                     (or (member word '("command" "exec" "env" "nohup"))
                         (string-match-p "\\`[A-Za-z_][A-Za-z0-9_]*=" word)))
                   (split-string-and-unquote cmd)))
           (head (and words (file-name-nondirectory (car words)))))
      (when head
        (or (car (member head (mapcar #'cdr claude-code-ide-agent-definitions)))
            (and (equal head (file-name-nondirectory claude-code-ide-cli-path))
                 claude-code-ide-cli-path))))))

;;; Control

(defun claude-code-ide-zmx-kill (name)
  "Kill zmx session NAME."
  (claude-code-ide-zmx--ensure)
  (claude-code-ide-zmx--call "kill" name))

(defun claude-code-ide-zmx-set-title (name title)
  "Set the `title' label of zmx session NAME to TITLE, asynchronously.
zmx label values only accept [a-zA-Z0-9-_.], so every other character
run is encoded as one `_'.  Fire-and-forget: errors are ignored."
  (when-let* ((name)
              (title)
              (value (string-trim
                      (replace-regexp-in-string
                       "[^a-zA-Z0-9._-]+" "_" title)
                      "_+" "_+"))
              ((not (string-empty-p value))))
    (ignore-errors
      (start-process "claude-code-ide-zmx-set-title" nil
                     claude-code-ide-zmx-program "set" name
                     (concat "title=" value)))))

(provide 'claude-code-ide-zmx)
;;; claude-code-ide-zmx.el ends here
