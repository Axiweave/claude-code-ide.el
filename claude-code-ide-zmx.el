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

(require 'cl-lib)
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

(defcustom claude-code-ide-remote-hosts nil
  "SSH destinations available for explicit remote Agent attachment.
SSH configuration supplies authentication, ports, and jump hosts.
The package never discovers destinations or connects automatically."
  :type '(repeat string)
  :group 'claude-code-ide)

(defconst claude-code-ide-zmx--ssh-options
  '("-o" "BatchMode=yes" "-o" "StrictHostKeyChecking=yes"
    "-o" "ConnectTimeout=10" "-o" "ConnectionAttempts=1"
    "-o" "RemoteCommand=none")
  "SSH options shared by control requests and terminal attachment.")

(defun claude-code-ide-zmx--valid-host-p (host)
  "Return non-nil if HOST is a safe SSH destination string."
  (and (stringp host) (not (string-empty-p host))
       (not (string-prefix-p "-" host))
       (not (string-match-p "[[:space:][:cntrl:]]" host))))

(defun claude-code-ide-zmx--validate-host (host)
  "Reject unsafe or unconfigured HOST before dispatch."
  (unless (claude-code-ide-zmx--valid-host-p host)
    (user-error "Invalid SSH destination: %S" host))
  (unless (member host claude-code-ide-remote-hosts)
    (user-error "Host %s is not configured in `claude-code-ide-remote-hosts'" host))
  host)

(defun claude-code-ide-zmx--valid-name-p (name)
  "Return non-nil if NAME identifies one exact zmx target."
  (and (stringp name) (not (string-empty-p name))
       (not (string-prefix-p "-" name)) (not (equal name "."))
       (not (string-suffix-p "*" name))
       (not (string-match-p "[/[:cntrl:]]" name))))

(defun claude-code-ide-zmx--validate-name (name)
  "Reject NAME if zmx could interpret it as anything but one target."
  (unless (claude-code-ide-zmx--valid-name-p name)
    (user-error "Unsupported zmx session name: %S" name))
  name)

(defun claude-code-ide-zmx--valid-directory-p (directory)
  "Return non-nil if DIRECTORY is absolute remote path metadata."
  (and (stringp directory) (string-prefix-p "/" directory)
       (not (string-match-p "[[:cntrl:]]" directory))))

(defun claude-code-ide-zmx--quote (argument)
  "Quote ARGUMENT for a POSIX shell without expansion."
  (concat "'" (replace-regexp-in-string "'" "'\\''" argument t t) "'"))

(defun claude-code-ide-zmx--remote-command (args)
  "Return a POSIX command for remote zmx ARGS."
  (concat "exec "
          (mapconcat #'claude-code-ide-zmx--quote
                     (append '("env" "-u" "ZMX_SESSION"
                               "-u" "ZMX_SESSION_PREFIX" "zmx") args)
                     " ")))

(defun claude-code-ide-zmx--call-remote (host args callback &optional name)
  "Run remote zmx ARGS on HOST and return the owned SSH process.
Call CALLBACK once with :host, :operation, :status, :stdout, :stderr,
:cancelled, and :timeout.  NAME optionally identifies this request.
The total deadline is thirty seconds.  No request retries."
  (claude-code-ide-zmx--validate-host host)
  (when (member (car args) '("attach" "kill"))
    (claude-code-ide-zmx--validate-name (car (last args))))
  (let ((stdout (generate-new-buffer " *cci-remote-output*"))
        (stderr (generate-new-buffer " *cci-remote-error*"))
        (default-directory temporary-file-directory)
        process stderr-process timer completed)
    (cl-labels
        ((finish
          (proc)
          (unless completed
            (setq completed t)
            (when timer (cancel-timer timer))
            (while (accept-process-output stderr-process 0 nil t))
            (let* ((timeout (process-get proc 'cci-timeout))
                   (outcome
                    (list :host host :operation (car args) :process proc
                          :status (process-exit-status proc)
                          :stdout (with-current-buffer stdout (buffer-string))
                          :stderr (with-current-buffer stderr (buffer-string))
                          :cancelled (and (eq (process-status proc) 'signal)
                                          (not timeout))
                          :timeout timeout)))
              (delete-process proc)
              (when (process-live-p stderr-process) (delete-process stderr-process))
              (kill-buffer stdout)
              (kill-buffer stderr)
              (condition-case err
                  (funcall callback outcome)
                (error (message "Remote request for %s failed: %s"
                                host (error-message-string err))))))))
      (condition-case err
          (progn
            (setq stderr-process
                  (make-pipe-process :name "cci-remote-stderr" :buffer stderr
                                     :noquery t :sentinel #'ignore))
            (setq process
                  (make-process
                   :name (or name "claude-code-ide-remote")
                   :buffer stdout :stderr stderr-process :noquery t
                   :connection-type 'pipe
                   :command (append '("ssh" "-T" "-n")
                                    claude-code-ide-zmx--ssh-options
                                    (list host (claude-code-ide-zmx--remote-command args)))
                   :sentinel
                   (lambda (proc _event)
                     (when (memq (process-status proc) '(exit signal failed))
                       (finish proc)))))
            (setq timer
                  (run-at-time
                   30 nil
                   (lambda ()
                     (unless completed
                       (process-put process 'cci-timeout t)
                       (delete-process process)
                       (finish process)))))
            process)
        (error
         (when timer (cancel-timer timer))
         (when (process-live-p process) (delete-process process))
         (when (process-live-p stderr-process) (delete-process stderr-process))
         (when (buffer-live-p stdout) (kill-buffer stdout))
         (when (buffer-live-p stderr) (kill-buffer stderr))
         (user-error "Cannot start SSH for %s: %s" host (error-message-string err)))))))

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
  (let ((default-directory (if (file-directory-p default-directory)
                               default-directory
                             temporary-file-directory)))
    (with-temp-buffer
      (let ((status (apply #'call-process claude-code-ide-zmx-program
                           nil t nil args)))
        (unless (eq status 0)
          (error "zmx %s failed (%s): %s"
                 (string-join args " ") status
                 (string-trim (buffer-string))))
        (string-trim (buffer-string))))))

;;; Listing

(defun claude-code-ide-zmx--parse-list-line (line)
  "Parse a tab-separated key=value LINE from `zmx list' into a plist.
A leading `→ ' marks the caller's own session and is dropped.
Return nil for lines without a name field."
  (let (plist)
    (dolist (field (split-string (string-trim (string-remove-prefix "→ " (string-trim line)))
                                 "\t" t))
      (when (string-match "\\`\\([^=]+\\)=\\(.*\\)\\'" field)
        (setq plist (plist-put plist
                               (intern (concat ":" (match-string 1 field)))
                               (match-string 2 field)))))
    ;; zmx 0.8 replaced start_dir with cwd=file://HOST/PATH.
    (when-let* ((cwd (and (not (plist-get plist :start_dir)) (plist-get plist :cwd)))
                (path (and (string-match "\\`file://[^/]*\\(/.*\\)\\'" cwd)
                           (match-string 1 cwd))))
      (setq plist (plist-put plist :start_dir path)))
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

(defun claude-code-ide-zmx-session-pid (name)
  "Return the agent pid of zmx session NAME as an integer, or nil.
The pid is the direct child of the zmx server, which is the agent
command itself when the session was created without a shell wrapper."
  (when-let* ((entry (seq-find (lambda (entry)
                                 (equal (plist-get entry :name) name))
                               (claude-code-ide-zmx-list-sessions)))
              (pid (plist-get entry :pid)))
    (string-to-number pid)))

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

(defconst claude-code-ide-zmx--attach-guard "false"
  "Command given to stock `zmx attach' when adopting an existing session.
Stock zmx ignores the command when the session exists and only uses
it when creating one.  If the target vanished between discovery and
attach, zmx creates a session running `false', which exits at once,
so no shell or Agent is left behind and the client exits nonzero.")

(defun claude-code-ide-zmx--attach-args (name)
  "Return stock zmx arguments adopting existing session NAME without creation."
  (list "attach" name claude-code-ide-zmx--attach-guard))

(defun claude-code-ide-zmx--remote-attach-command (host name)
  "Build an interactive SSH command adopting existing session NAME on HOST."
  (claude-code-ide-zmx--validate-host host)
  (claude-code-ide-zmx--validate-name name)
  (mapconcat #'claude-code-ide-zmx--quote
             (append '("ssh" "-t") claude-code-ide-zmx--ssh-options
                     (list host (claude-code-ide-zmx--remote-command
                                 (claude-code-ide-zmx--attach-args name))))
             " "))

(defun claude-code-ide-zmx-wrap-command (name &optional cmd)
  "Return a shell command attaching to zmx session NAME.
With CMD, preserve ordinary local creation.  Without CMD, adopt the
existing session only; see `claude-code-ide-zmx--attach-guard'."
  (if cmd
      (combine-and-quote-strings
       (append (list "env" "-u" "ZMX_SESSION" claude-code-ide-zmx-program "attach" name)
               (split-string-and-unquote cmd)))
    (claude-code-ide-zmx--validate-name name)
    (claude-code-ide-zmx--ensure)
    (mapconcat #'claude-code-ide-zmx--quote
               (append (list "env" "-u" "ZMX_SESSION" "-u" "ZMX_SESSION_PREFIX"
                             claude-code-ide-zmx-program)
                       (claude-code-ide-zmx--attach-args name))
               " ")))

;;; Remote discovery

(defconst claude-code-ide-zmx--no-sessions-diagnostic "no sessions found"
  "Prefix zmx prints on `list' when the destination has no sessions.")

(defun claude-code-ide-zmx--no-sessions-line-p (text)
  "Return non-nil if TEXT is the known empty-list diagnostic."
  (string-match-p "\\`no sessions found\\(?: in [^\n\r]+\\)?\\'"
                  (string-trim (or text ""))))

(defun claude-code-ide-zmx--parse-remote-list (host stdout stderr)
  "Parse HOST's detailed `zmx list' STDOUT into named candidate plists.
Reuse `claude-code-ide-zmx--parse-list-line' for each line and add
:host to every
candidate.  STDERR supplies the known empty-list diagnostic when
STDOUT itself carries no rows.  Signal a `user-error' when STDOUT is
empty without that diagnostic, or when a line does not fit the shared
parser.  An unsupported candidate name becomes that row's own :error
instead of invalidating the rest of the response."
  (let ((lines (split-string (or stdout "") "\n" t)))
    (cond
     ((and (= (length lines) 1) (claude-code-ide-zmx--no-sessions-line-p (car lines)))
      nil)
     ((and (null lines) (claude-code-ide-zmx--no-sessions-line-p stderr))
      nil)
     ((null lines)
      (user-error "Host %s `zmx list' returned no output" host))
     (t
      (mapcar
       (lambda (line)
         (let* ((fields (split-string (string-remove-prefix "→ " (string-trim line)) "\t"))
                (name-fields (seq-filter (lambda (field) (string-prefix-p "name=" field))
                                         fields))
                (entry (and (= (length name-fields) 1)
                            (seq-every-p
                             (lambda (field) (string-match-p "\\`[^=\t]+=[^\t]*\\'" field))
                             fields)
                            (claude-code-ide-zmx--parse-list-line line))))
           (unless entry
             (user-error "Host %s `zmx list' returned an unsupported response: %s"
                         host (string-trim line)))
           (setq entry (plist-put entry :name (substring (car name-fields) 5)))
           (setq entry (plist-put entry :host host))
           (if (or (plist-get entry :error)
                   (claude-code-ide-zmx--valid-name-p (plist-get entry :name)))
               entry
             (plist-put entry :error "unsupported session name"))))
       lines)))))

(defun claude-code-ide-zmx--remote-request-ok-p (outcome)
  "Return non-nil when OUTCOME is a clean, uncancelled zero exit."
  (and (eql (plist-get outcome :status) 0)
       (not (plist-get outcome :cancelled))
       (not (plist-get outcome :timeout))))

(defun claude-code-ide-zmx--remote-request-failure (host what outcome)
  "Return a corrective error string for HOST's WHAT request from OUTCOME."
  (cond
   ((plist-get outcome :timeout) (format "Host %s timed out running zmx %s" host what))
   ((plist-get outcome :cancelled) (format "Host %s cancelled zmx %s" host what))
   (t (let ((detail (string-trim (or (plist-get outcome :stderr) ""))))
        (format "Host %s zmx %s failed (status %s)%s" host what (plist-get outcome :status)
                (if (string-empty-p detail) "" (format ": %s" detail)))))))

(defun claude-code-ide-zmx--discovery-outcome (outcome &rest extra)
  "Return a discovery-facing plist copying host/status/stdout/stderr from OUTCOME.
Append EXTRA properties, such as :sessions or :error."
  (append (list :host (plist-get outcome :host) :status (plist-get outcome :status)
                :stdout (plist-get outcome :stdout) :stderr (plist-get outcome :stderr))
          extra))

(defun claude-code-ide-zmx--discovery-list-result (host list-outcome)
  "Resolve HOST's LIST-OUTCOME into a discovery result plist."
  (if (not (claude-code-ide-zmx--remote-request-ok-p list-outcome))
      (claude-code-ide-zmx--discovery-outcome
       list-outcome
       :error (claude-code-ide-zmx--remote-request-failure host "list" list-outcome))
    (condition-case err
        (claude-code-ide-zmx--discovery-outcome
         list-outcome
         :sessions (claude-code-ide-zmx--parse-remote-list
                    host (plist-get list-outcome :stdout)
                    (plist-get list-outcome :stderr)))
      (user-error
       (claude-code-ide-zmx--discovery-outcome
        list-outcome :error (error-message-string err))))))

(defun claude-code-ide-zmx-discover-remote (host callback)
  "Discover HOST's existing zmx sessions and call CALLBACK once.
Run a detailed `zmx list' with control semantics and return the
control process.  CALLBACK receives a plist with :host, :status,
:stdout, :stderr, and either :sessions or :error."
  (claude-code-ide-zmx--call-remote
   host '("list")
   (lambda (list-outcome)
     (funcall callback (claude-code-ide-zmx--discovery-list-result host list-outcome)))
   (format "claude-code-ide-remote-list-%s" host)))

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

(defun claude-code-ide-zmx--strip-one-trailing-newline (text)
  "Return TEXT with at most one trailing newline removed, verbatim otherwise."
  (if (string-suffix-p "\n" text) (substring text 0 -1) text))

(defun claude-code-ide-zmx--stop-kill-ack-p (name outcome)
  "Return non-nil when OUTCOME is the exact `killed session NAME' reply."
  (and (claude-code-ide-zmx--remote-request-ok-p outcome)
       (equal (claude-code-ide-zmx--strip-one-trailing-newline
               (or (plist-get outcome :stdout) ""))
              (format "killed session %s" name))))

(defun claude-code-ide-zmx--short-list-names (stdout stderr)
  "Return session names from a `zmx list --short' STDOUT.
Preserve exact leading and trailing whitespace in each name.  Stock
zmx prints nothing for an empty list, so blank STDOUT is an empty
result unless STDERR carries text other than the known empty-list
diagnostic (see `claude-code-ide-zmx--no-sessions-line-p')."
  (or (split-string (or stdout "") "\n" t)
      (if (or (string-empty-p (string-trim (or stderr "")))
              (claude-code-ide-zmx--no-sessions-line-p stderr))
          nil
        (user-error "zmx list --short failed: %s" (string-trim stderr)))))

(defun claude-code-ide-zmx-require-remote-session (host name &optional request-name)
  "Require existing session NAME on HOST before starting an attach client.
REQUEST-NAME identifies the pending request.  Use the control transport's
thirty-second deadline, and cancel its process if the user quits."
  (claude-code-ide-zmx--validate-name name)
  (let (outcome process)
    (unwind-protect
        (progn
          (setq process
                (claude-code-ide-zmx--call-remote
                 host '("list" "--short")
                 (lambda (result) (setq outcome result)) request-name))
          (while (not outcome)
            (accept-process-output process 0.1))
          (unless (claude-code-ide-zmx--remote-request-ok-p outcome)
            (user-error "%s" (claude-code-ide-zmx--remote-request-failure
                              host "list --short" outcome)))
          (unless (member name (claude-code-ide-zmx--short-list-names
                                (plist-get outcome :stdout)
                                (plist-get outcome :stderr)))
            (user-error "Cannot attach %s on %s. The remote session no longer exists"
                        name host)))
      (when (process-live-p process)
        (delete-process process)))))

(defun claude-code-ide-zmx--stop-list-check (host name outcome)
  "Return t when NAME is confirmed absent from HOST's short-list OUTCOME.
Return a failure string describing what went wrong otherwise."
  (if (not (claude-code-ide-zmx--remote-request-ok-p outcome))
      (claude-code-ide-zmx--remote-request-failure host "list --short" outcome)
    (condition-case err
        (if (member name (claude-code-ide-zmx--short-list-names
                          (plist-get outcome :stdout) (plist-get outcome :stderr)))
            (format "%s is still listed on host %s" name host)
          t)
      (user-error (error-message-string err)))))

(defun claude-code-ide-zmx-stop-remote (host name callback &optional request-name)
  "Kill zmx session NAME on HOST and verify it is gone before confirming.
Validate HOST and NAME, then send one `kill NAME' without `--force'.
Require the exact `killed session NAME' acknowledgment, preserving
every character of NAME, before issuing one `list --short'
verification; never retry the kill.  Return the initial kill process.

Call CALLBACK exactly once, even if a stale reply repeats or a
callback in the chain throws, with :host, :name, :request (the
initial kill process), and either :verified t or :error a string
explaining why Stop is unconfirmed and what to do about it.

REQUEST-NAME names both requests; it defaults to a host-scoped name.
The kill process releases that name on exit, so the later
verification process can reuse it exactly, letting a caller find
whichever phase is currently pending under one stable process name.
Both processes carry a `cci-operation' property of `stop' and a
`cci-request' property naming the initial kill process, so a caller
can recover that ownership token from either phase alone."
  (claude-code-ide-zmx--validate-host host)
  (claude-code-ide-zmx--validate-name name)
  (let ((req-name (or request-name (format "claude-code-ide-remote-stop-%s" host)))
        (done nil)
        kill-process)
    (cl-labels
        ((finish
          (result)
          (unless done
            (setq done t)
            (condition-case err
                (funcall callback result)
              (error (message "Remote Stop callback for %s on %s failed: %s"
                              name host (error-message-string err))))))
         (unconfirmed
          (reason)
          (finish (list :host host :name name :request kill-process
                        :error (format (concat "Stop for %s on host %s is unconfirmed (%s). "
                                                "Check `zmx list' on %s. Retry Stop only if the target remains.")
                                       name host reason host))))
         (phase2-callback
          (list-outcome)
          (condition-case err
              (let ((check (claude-code-ide-zmx--stop-list-check host name list-outcome)))
                (if (eq check t)
                    (finish (list :host host :name name :request kill-process :verified t))
                  (unconfirmed check)))
            (error (unconfirmed (error-message-string err)))))
         (phase1-callback
          (outcome)
          (condition-case err
              (if (not (claude-code-ide-zmx--stop-kill-ack-p name outcome))
                  (unconfirmed
                   (if (claude-code-ide-zmx--remote-request-ok-p outcome)
                       "zmx did not confirm killing the exact target"
                     (claude-code-ide-zmx--remote-request-failure host "kill" outcome)))
                (let ((list-process
                       (claude-code-ide-zmx--call-remote
                        host '("list" "--short") #'phase2-callback req-name)))
                  (process-put list-process 'cci-operation 'stop)
                  (process-put list-process 'cci-request kill-process)))
            (error (unconfirmed (error-message-string err))))))
      (condition-case err
          (setq kill-process
                (claude-code-ide-zmx--call-remote
                 host (list "kill" name) #'phase1-callback req-name))
        (error (unconfirmed (format "cannot start kill: %s" (error-message-string err)))))
      (when kill-process
        (process-put kill-process 'cci-operation 'stop)
        (process-put kill-process 'cci-request kill-process))
      kill-process)))

(defun claude-code-ide-zmx--title-value (title)
  "Return TITLE encoded as a zmx-safe label value, or nil."
  (when title
    (let ((value (string-trim
                  (replace-regexp-in-string
                   "[^a-zA-Z0-9._-]+" "_" title)
                  "_+" "_+")))
      (unless (string-empty-p value)
        value))))

(defun claude-code-ide-zmx-set-title (name title)
  "Set the `title' label of zmx session NAME to TITLE, asynchronously.
zmx label values only accept [a-zA-Z0-9-_.], so every other character
run is encoded as one `_'.  Fire-and-forget: errors are ignored."
  (when-let* ((name)
              (value (claude-code-ide-zmx--title-value title)))
    (ignore-errors
      (start-process "claude-code-ide-zmx-set-title" nil
                     claude-code-ide-zmx-program "set" name
                     (concat "title=" value)))))

(provide 'claude-code-ide-zmx)
;;; claude-code-ide-zmx.el ends here
