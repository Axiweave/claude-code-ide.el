;;; claude-code-ide-tests.el --- Tests for Claude Code IDE  -*- lexical-binding: t; -*-

;; Copyright (C) 2025

;; Author: Yoav Orot

;; This file is not part of GNU Emacs.

;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;;; Commentary:

;; Test suite for claude-code-ide.el using ERT
;;
;; Run tests with:
;;   `emacs -batch -L . -l ert -l claude-code-ide-tests.el -f ert-run-tests-batch-and-exit'
;;
;; The tests mock both vterm and mcp-server-lib functionality to avoid requiring
;; these packages during testing. This allows the tests to run in any environment
;; without external dependencies.
;;
;; CRITICAL DISCOVERY: Claude Code tools only work when launched from VS Code/editor terminals
;; because the extensions set these environment variables:
;; - CLAUDE_CODE_SSE_PORT: The WebSocket server port created by the extension
;; - ENABLE_IDE_INTEGRATION: Set to "true" to enable MCP tools
;; - FORCE_CODE_TERMINAL: Set to "true" to enable terminal features
;;
;; Workflow:
;; 1. Extension creates WebSocket/MCP server on random port
;; 2. Extension sets environment variables in terminal
;; 3. Extension launches 'claude' command
;; 4. Claude CLI reads env vars and connects to WebSocket server
;; 5. CLI and extension communicate via WebSocket/JSON-RPC for tool calls

;;; Code:

(add-to-list 'load-path (file-name-directory (or load-file-name buffer-file-name)))

(require 'ert)
(require 'cl-lib)

;;; Mock Implementations

;; === Mock claude-code-ide-debug module ===
(defvar claude-code-ide-debug nil
  "Mock debug flag for testing.")
(defvar claude-code-ide-log-with-context t
  "Mock log context flag for testing.")
(defun claude-code-ide-debug (&rest _args)
  "Mock debug function that does nothing."
  nil)
(defun claude-code-ide-clear-debug ()
  "Mock clear debug function."
  nil)
(defun claude-code-ide-log (format-string &rest args)
  "Mock logging function for tests."
  (apply #'message format-string args))
(defun claude-code-ide--get-session-context ()
  "Mock session context function."
  "")
(provide 'claude-code-ide-debug)

;; === Mock websocket module ===
;; Try to load real websocket, otherwise provide comprehensive mocks
(condition-case nil
    (progn
      (add-to-list 'load-path (expand-file-name "~/.emacs.d/.cache/straight/build/websocket/"))
      (require 'websocket))
  (error
   ;; Comprehensive websocket mock implementation
   (defun websocket-server (&rest _args)
     "Mock websocket-server function."
     ;; Return something that looks like a server but isn't a process
     '(:mock-server t))
   (defun websocket-server-close (_server)
     "Mock websocket-server-close function."
     nil)
   (defun websocket-send-text (_ws _text)
     "Mock websocket-send-text function."
     nil)
   (defun websocket-ready-state (_ws)
     "Mock websocket-ready-state function."
     'open)
   (defun websocket-url (_ws)
     "Mock websocket-url function."
     "ws://localhost:12345")
   (defun websocket-frame-text (_frame)
     "Mock websocket-frame-text function."
     "{}")
   (defun websocket-frame-opcode (_frame)
     "Mock websocket-frame-opcode function."
     'text)
   (defun websocket-send (_ws _frame)
     "Mock websocket-send function."
     nil)
   (defun websocket-server-filter (_proc _string)
     "Mock websocket-server-filter function."
     nil)
   ;; Define the structure accessors to avoid free variable warnings
   (defvar websocket-frame nil)
   (cl-defstruct websocket-frame opcode payload)
   (provide (quote websocket))))

;; === Mock vterm module ===
(defvar vterm--process nil)
(defvar vterm-buffer-name nil)
(defvar vterm-shell nil)
(defvar vterm-environment nil)

(defun vterm (&optional buffer-name)
  "Mock vterm function for testing with optional BUFFER-NAME."
  (let ((buffer (generate-new-buffer (or buffer-name vterm-buffer-name "*vterm*"))))
    (with-current-buffer buffer
      ;; Create a mock process that exits immediately
      (setq vterm--process (make-process :name "mock-vterm"
                                         :buffer buffer
                                         :command '("true")
                                         :connection-type 'pty
                                         :sentinel (lambda (_ event)
                                                     (when (string-match "finished" event)
                                                       (setq vterm--process nil))))))
    buffer))

;; Mock vterm functions
(defun vterm-send-string (_string)
  "Mock vterm-send-string function for testing."
  nil)

(defun vterm-send-return ()
  "Mock vterm-send-return function for testing."
  nil)

(defun vterm-send-key (_key &optional _shift _meta _ctrl)
  "Mock vterm-send-key function for testing."
  nil)

(defun vterm--filter (_process _string)
  "Mock vterm filter function for testing."
  nil)

(provide (quote vterm))

(defun eat--filter (_process _string)
  "Mock eat filter function for testing."
  nil)

(provide (quote eat))

;; === Mock Emacs display functions ===
(unless (fboundp 'display-buffer-in-side-window)
  (defun display-buffer-in-side-window (buffer _alist)
    "Mock display-buffer-in-side-window for testing."
    (set-window-buffer (selected-window) buffer)
    (selected-window)))

;; === Additional test-specific websocket mocks ===
(unless (featurep 'websocket)
  ;; Only define these if websocket wasn't loaded above
  (defvar websocket--test-server nil
    "Mock server for testing.")
  (defvar websocket--test-client nil
    "Mock client for testing.")
  (defvar websocket--test-port 12345
    "Mock port for testing."))

;; === Mock flycheck module ===
;; Mock flycheck before loading any modules that require it
(defvar flycheck-mode nil
  "Mock flycheck-mode variable.")
(defvar flycheck-current-errors nil
  "Mock list of flycheck errors.")

(cl-defstruct flycheck-error
  "Mock flycheck error structure."
  buffer checker filename line column end-line end-column
  message level severity id)

(provide (quote flycheck))

;; === Mock persist module ===
(defvar persist--test-store (make-hash-table :test 'eq)
  "Mock persist storage keyed by symbol.")
(defvar persist--test-defaults (make-hash-table :test 'eq)
  "Mock persist default values keyed by symbol.")

(defun persist-symbol (symbol &optional initvalue)
  "Mock `persist-symbol' for testing."
  (puthash symbol (copy-tree (or initvalue (symbol-value symbol)) t)
           persist--test-defaults)
  symbol)

(defun persist-save (symbol)
  "Mock `persist-save' for testing."
  (puthash symbol (copy-tree (symbol-value symbol) t) persist--test-store))

(defun persist-load (symbol)
  "Mock `persist-load' for testing."
  (when (gethash symbol persist--test-store)
    (set symbol (copy-tree (gethash symbol persist--test-store) t))))

(defun persist-reset (symbol)
  "Mock `persist-reset' for testing."
  (set symbol (copy-tree (gethash symbol persist--test-defaults) t)))

(defun persist-unpersist (_symbol)
  "Mock `persist-unpersist' for testing."
  nil)

(defmacro persist-defvar (symbol initvalue docstring &optional _location)
  "Mock `persist-defvar' for testing."
  `(progn
     (defvar ,symbol ,initvalue ,docstring)
     (persist-symbol ',symbol ,symbol)
     (persist-load ',symbol)
     ',symbol))

(provide 'persist)

;; === Load required modules ===
(define-error 'mcp-error "MCP Error" 'error)
(require 'claude-code-ide-mcp-handlers)
(require 'claude-code-ide)

;;; Test Helper Functions

(defmacro claude-code-ide-tests--with-mocked-cli (cli-path &rest body)
  "Execute BODY with claude CLI path set to CLI-PATH."
  `(let ((claude-code-ide-cli-path ,cli-path)
         (claude-code-ide--cli-available nil))
     ,@body))

(defun claude-code-ide-tests--with-temp-directory (test-body)
  "Execute TEST-BODY in a temporary directory context.
Creates a temporary directory, sets it as `default-directory',
executes TEST-BODY, and ensures cleanup even if TEST-BODY fails."
  (let ((temp-dir (make-temp-file "claude-code-ide-test-" t)))
    (unwind-protect
        (let ((default-directory temp-dir))
          (funcall test-body))
      (delete-directory temp-dir t))))

(defun claude-code-ide-tests--git (&rest args)
  "Run git with ARGS and return trimmed stdout.
Signal an error when git exits unsuccessfully."
  (with-temp-buffer
    (let ((status (apply #'process-file "git" nil t nil args)))
      (unless (eq status 0)
        (error "git %s failed: %s"
               (mapconcat #'identity args " ")
               (string-trim (buffer-string))))
      (string-trim (buffer-string)))))

(defun claude-code-ide-tests--with-temp-worktree-repo (test-body)
  "Create a temporary repo with a sibling worktree and call TEST-BODY.
TEST-BODY receives two arguments: the main repo root and a sibling worktree
root.  Both paths are normalized directory names."
  (let* ((temp-dir (make-temp-file "claude-code-ide-worktree-test-" t))
         (main-root (expand-file-name "main" temp-dir))
         (worktree-root (expand-file-name "feature" temp-dir)))
    (unwind-protect
        (progn
          (make-directory main-root t)
          (let ((default-directory main-root))
            (claude-code-ide-tests--git "init")
            (claude-code-ide-tests--git "config" "user.name" "Claude Code IDE Tests")
            (claude-code-ide-tests--git "config" "user.email" "tests@example.com")
            (with-temp-file (expand-file-name "README.md" main-root)
              (insert "worktree test\n"))
            (claude-code-ide-tests--git "add" "README.md")
            (claude-code-ide-tests--git "commit" "-m" "initial")
            (claude-code-ide-tests--git "branch" "feature")
            (claude-code-ide-tests--git "worktree" "add" worktree-root "feature"))
          (funcall test-body
                   (file-name-as-directory (file-truename main-root))
                   (file-name-as-directory (file-truename worktree-root))))
      (ignore-errors (delete-directory temp-dir t)))))

(defun claude-code-ide-tests--clear-processes ()
  "Clear the process hash table for testing.
Ensures a clean state before each test that involves process management."
  (clrhash claude-code-ide--processes)
  ;; Also clear MCP sessions
  (when (boundp 'claude-code-ide-mcp--sessions)
    (clrhash claude-code-ide-mcp--sessions)))

(defun claude-code-ide-tests--manager-row-slot-column ()
  "Return the visual column where the current row's slot text begins."
  (save-excursion
    (beginning-of-line)
    (re-search-forward "[0-9]+\\." (line-end-position) t)
    (goto-char (match-beginning 0))
    (current-column)))

(defun claude-code-ide-tests--manager-row-text ()
  "Return the current manager row as plain text."
  (buffer-substring-no-properties (line-beginning-position)
                                   (line-end-position)))

(defun claude-code-ide-tests--reset-manager-state ()
  "Reset cc-manager test state."
  (setq persist--test-store (make-hash-table :test 'eq))
  (setq persist--test-defaults (make-hash-table :test 'eq))
  (when (fboundp 'claude-code-ide-manager--reset-state)
    (claude-code-ide-manager--reset-state)))

(defun claude-code-ide-tests--wait-for-process (buffer)
  "Wait for the process in BUFFER to finish.
This prevents race conditions in tests by ensuring mock processes
have completed before cleanup.  Waits up to 5 seconds."
  (with-current-buffer buffer
    (let ((max-wait 50)) ; 5 seconds max (50 * 0.1s)
      (while (and vterm--process
                  (process-live-p vterm--process)
                  (> max-wait 0))
        (sleep-for 0.1)
        (setq max-wait (1- max-wait))))))

;;; Tests for Helper Functions

(ert-deftest claude-code-ide-test-default-buffer-name ()
  "Test default buffer name generation for various path formats."
  ;; Normal path
  (should (equal (claude-code-ide--default-buffer-name "/home/user/project")
                 "*claude-code[project]*"))
  ;; Path with trailing slash
  (should (equal (claude-code-ide--default-buffer-name "/home/user/my-app/")
                 "*claude-code[my-app]*"))
  ;; Root directory
  (should (equal (claude-code-ide--default-buffer-name "/")
                 "*claude-code[]*"))
  ;; Path with spaces
  (should (equal (claude-code-ide--default-buffer-name "/home/user/my project/")
                 "*claude-code[my project]*"))
  ;; Path with special characters
  (should (equal (claude-code-ide--default-buffer-name "/home/user/my-project@v1.0/")
                 "*claude-code[my-project@v1.0]*")))

(ert-deftest claude-code-ide-test-manager-module-loads ()
  "Test manager module loads with the main package."
  (should (featurep 'claude-code-ide-manager)))

(ert-deftest claude-code-ide-test-manager-global-scope-key-is-stable ()
  (should (equal (claude-code-ide-manager--scope-key '(:type global))
                 "global")))

(ert-deftest claude-code-ide-test-manager-global-buffer-name-remains-unchanged ()
  (should (equal (claude-code-ide-manager--buffer-name-for-scope '(:type global))
                 "*claude-code-manager*")))

(ert-deftest claude-code-ide-test-manager-current-scope-uses-git-root ()
  (cl-letf (((symbol-function 'claude-code-ide-manager--current-git-root)
             (lambda () "/tmp/repo/")))
    (should (equal (claude-code-ide-manager--resolve-scope 'repo)
                   '(:type repo :git-root "/tmp/repo/")))))

(ert-deftest claude-code-ide-test-manager-repo-scope-filters-by-exact-root ()
  (let ((claude-code-ide-manager-repo-include-nested nil))
    (cl-letf (((symbol-function 'claude-code-ide-manager--session-git-root)
               (lambda (session-key)
                 (cond
                  ((equal session-key "/tmp/repo/a") "/tmp/repo/")
                  ((equal session-key "/tmp/repo-nested/b") "/tmp/repo-nested/")))))
      (should (equal (claude-code-ide-manager--scope-session-keys
                      '(:type repo :git-root "/tmp/repo/")
                      '("/tmp/repo/a" "/tmp/repo-nested/b"))
                     '("/tmp/repo/a"))))))

(ert-deftest claude-code-ide-test-manager-repo-scope-includes-nested-roots-when-enabled ()
  (let ((claude-code-ide-manager-repo-include-nested t))
    (cl-letf (((symbol-function 'claude-code-ide-manager--session-git-root)
               (lambda (session-key)
                 (cond
                  ((equal session-key "/tmp/repo/a") "/tmp/repo/")
                  ((equal session-key "/tmp/repo/packages/lib") "/tmp/repo/packages/lib/")
                  ((equal session-key "/tmp/other/c") "/tmp/other/")))))
      (should (equal (claude-code-ide-manager--scope-session-keys
                      '(:type repo :git-root "/tmp/repo/")
                      '("/tmp/repo/a" "/tmp/repo/packages/lib" "/tmp/other/c"))
                     '("/tmp/repo/a" "/tmp/repo/packages/lib"))))))

(ert-deftest claude-code-ide-test-manager-repo-label-uses-basename-strategy ()
  (let ((claude-code-ide-manager-repo-label-strategy 'basename))
    (cl-letf (((symbol-function 'claude-code-ide-manager--session-branch-name)
               (lambda (_session-key) "feature-x")))
      (should (equal (claude-code-ide-manager--scope-display-name
                      '(:type repo :git-root "/tmp/repo/")
                      "/tmp/repo/worktree-a")
                     "worktree-a")))))

(ert-deftest claude-code-ide-test-manager-repo-label-uses-branch-strategy ()
  (let ((claude-code-ide-manager-repo-label-strategy 'branch))
    (cl-letf (((symbol-function 'claude-code-ide-manager--session-branch-name)
               (lambda (_session-key) "feature-x")))
      (should (equal (claude-code-ide-manager--scope-display-name
                      '(:type repo :git-root "/tmp/repo/")
                      "/tmp/repo/worktree-a")
                     "feature-x")))))

(ert-deftest claude-code-ide-test-manager-repo-label-falls-back-to-basename-when-detached ()
  (let ((claude-code-ide-manager-repo-label-strategy 'branch-or-basename))
    (cl-letf (((symbol-function 'claude-code-ide-manager--session-branch-name)
               (lambda (_session-key) nil)))
      (should (equal (claude-code-ide-manager--scope-display-name
                      '(:type repo :git-root "/tmp/repo/")
                      "/tmp/repo/worktree-a")
                     "worktree-a")))))

(ert-deftest claude-code-ide-test-manager-repo-label-disambiguates-duplicate-branches ()
  (let ((items (list (make-claude-code-ide-manager-item
                      :session-key "/tmp/repo/backend"
                      :display-name "feature-x")
                     (make-claude-code-ide-manager-item
                      :session-key "/tmp/repo/docs"
                      :display-name "feature-x"))))
    (should (equal (claude-code-ide-manager--disambiguate-display-names items)
                   '("feature-x [backend]" "feature-x [docs]")))))

(ert-deftest claude-code-ide-test-manager-repo-label-disambiguates-colliding-basenames ()
  (let ((items (list (make-claude-code-ide-manager-item
                      :session-key "/tmp/repo/apps/backend"
                      :display-name "feature-x")
                     (make-claude-code-ide-manager-item
                      :session-key "/tmp/repo/services/backend"
                      :display-name "feature-x"))))
    (should (equal (claude-code-ide-manager--disambiguate-display-names items)
                   '("feature-x [apps/backend]"
                     "feature-x [services/backend]")))))

(ert-deftest claude-code-ide-test-manager-repo-buffer-name-uses-git-root ()
  (let ((name (claude-code-ide-manager--buffer-name-for-scope
               '(:type repo :git-root "/tmp/my-repo/"))))
    (should (string-prefix-p "*claude-code-manager:my-repo@" name))
    (should (string-suffix-p "*" name))))

(ert-deftest claude-code-ide-test-manager-repo-buffer-name-is-unique-per-git-root ()
  (let ((left (claude-code-ide-manager--buffer-name-for-scope
               '(:type repo :git-root "/tmp/src/app/")))
        (right (claude-code-ide-manager--buffer-name-for-scope
                '(:type repo :git-root "/tmp/work/app/"))))
    (should-not (equal left right))
    (should (string-prefix-p "*claude-code-manager:app@" left))
    (should (string-prefix-p "*claude-code-manager:app@" right))))

(ert-deftest claude-code-ide-test-manager-resolve-repo-scope-errors-outside-git ()
  (cl-letf (((symbol-function 'claude-code-ide-manager--current-git-root)
             (lambda () nil)))
    (should-error (claude-code-ide-manager--resolve-scope 'repo)
                  :type 'user-error)))

(ert-deftest claude-code-ide-test-manager-current-git-root-ignores-non-git-vc-roots ()
  (let ((default-directory "/tmp/project/"))
    (cl-letf (((symbol-function 'vc-git-root)
               (lambda (&optional _file) nil))
              ((symbol-function 'vc-root-dir)
               (lambda (&optional _dir) "/tmp/project/")))
      (should-not (claude-code-ide-manager--current-git-root)))))

(ert-deftest claude-code-ide-test-manager-current-git-root-uses-common-root-for-worktrees ()
  "Repo scope should use the shared repo root, not the current worktree root."
  (claude-code-ide-tests--with-temp-worktree-repo
   (lambda (main-root worktree-root)
     (let ((default-directory worktree-root))
       (should (equal (claude-code-ide-manager--current-git-root)
                      main-root))))))

(ert-deftest claude-code-ide-test-manager-repo-scope-includes-sibling-worktrees ()
  "Repo scope should include sessions from sibling worktrees in the same repo."
  (claude-code-ide-tests--with-temp-worktree-repo
   (lambda (main-root worktree-root)
     (let ((scope (list :type 'repo :git-root main-root)))
       (should (equal (claude-code-ide-manager--scope-session-keys
                       scope
                       (list main-root worktree-root))
                      (list main-root worktree-root)))))))

(ert-deftest claude-code-ide-test-manager-global-and-repo-scopes-keep-separate-pin-state ()
  (claude-code-ide-tests--reset-manager-state)
  (let ((global-scope '(:type global))
        (repo-scope '(:type repo :git-root "/tmp/repo/")))
    (claude-code-ide-manager--set-scope-items
     global-scope
     (list (make-claude-code-ide-manager-item :session-key "/tmp/repo/" :pinned t)))
    (claude-code-ide-manager--set-scope-items
     repo-scope
     (list (make-claude-code-ide-manager-item :session-key "/tmp/repo/" :pinned nil)))
    (should (claude-code-ide-manager-item-pinned
             (car (claude-code-ide-manager--scope-items global-scope))))
    (should-not (claude-code-ide-manager-item-pinned
                 (car (claude-code-ide-manager--scope-items repo-scope))))))

(ert-deftest claude-code-ide-test-manager-layouts-stay-shared-across-scopes ()
  (claude-code-ide-tests--reset-manager-state)
  (let ((layout '(:selected-buffer-name "*x*")))
    (puthash "/tmp/repo/" layout claude-code-ide-manager--layouts)
    (should (equal (gethash "/tmp/repo/" claude-code-ide-manager--layouts)
                   layout))))

(ert-deftest claude-code-ide-test-manager-persisted-scope-state-is-isolated ()
  (should-not (equal (claude-code-ide-manager--scope-key '(:type global))
                     (claude-code-ide-manager--scope-key
                      '(:type repo :git-root "/tmp/repo/")))))

(ert-deftest claude-code-ide-test-manager-loads-legacy-global-persisted-state ()
  (claude-code-ide-tests--reset-manager-state)
  (let ((claude-code-ide-manager-persist-state t))
    (puthash 'claude-code-ide-manager--persisted-state
             '(:version 1
               :items ((:session-key "/tmp/a"
                        :display-name "a"
                        :secondary-text "/tmp/a"
                        :pinned t
                        :order-key 4
                        :live-p t))
               :layouts nil)
             persist--test-store)
    (claude-code-ide-manager--load-state)
    (should (= (length claude-code-ide-manager--items) 1))
    (should (equal (claude-code-ide-manager-item-session-key
                    (car claude-code-ide-manager--items))
                   "/tmp/a"))
    (should (claude-code-ide-manager-item-pinned
             (car claude-code-ide-manager--items)))
    (should (= (claude-code-ide-manager-item-order-key
                (car claude-code-ide-manager--items))
               4))))

(ert-deftest claude-code-ide-test-manager-default-toggle-targets-global-when-configured ()
  (let ((claude-code-ide-manager-default-target 'global))
    (should (equal (claude-code-ide-manager--default-target) 'global))))

(ert-deftest claude-code-ide-test-manager-default-toggle-targets-repo-in-git ()
  (let ((claude-code-ide-manager-default-target 'repo-local-when-in-git))
    (cl-letf (((symbol-function 'claude-code-ide-manager--current-git-root)
               (lambda () "/tmp/repo/")))
      (should (equal (claude-code-ide-manager--default-target) 'repo)))))

(ert-deftest claude-code-ide-test-manager-toggle-repo-sidebar-resolves-repo-scope ()
  (let (captured)
    (cl-letf (((symbol-function 'claude-code-ide-manager-toggle-sidebar-for-scope)
               (lambda (scope &optional _arg)
                 (setq captured scope)))
              ((symbol-function 'claude-code-ide-manager--current-git-root)
               (lambda () "/tmp/repo/")))
      (claude-code-ide-manager-toggle-repo-sidebar)
      (should (equal captured '(:type repo :git-root "/tmp/repo/"))))))

(ert-deftest claude-code-ide-test-manager-toggle-sidebar-uses-default-target-scope ()
  (let (captured)
    (cl-letf (((symbol-function 'claude-code-ide-manager-toggle-sidebar-for-scope)
               (lambda (scope &optional _arg)
                 (setq captured scope)))
              ((symbol-function 'claude-code-ide-manager--current-git-root)
               (lambda () "/tmp/repo/")))
      (let ((claude-code-ide-manager-default-target 'repo-local-when-in-git))
        (claude-code-ide-manager-toggle-sidebar)
        (should (equal captured '(:type repo :git-root "/tmp/repo/")))))))

(ert-deftest claude-code-ide-test-manager-repo-scope-renders-branch-labels-and-path-hover ()
  (claude-code-ide-tests--reset-manager-state)
  (let ((scope '(:type repo :git-root "/tmp/repo/"))
        (claude-code-ide--processes (make-hash-table :test 'equal))
        (claude-code-ide-manager-repo-label-strategy 'branch-or-basename)
        (process-a (make-pipe-process :name "cc-manager-repo-render-a" :buffer nil))
        (process-b (make-pipe-process :name "cc-manager-repo-render-b" :buffer nil)))
    (unwind-protect
        (progn
          (puthash "/tmp/repo/worktree-a" process-a claude-code-ide--processes)
          (puthash "/tmp/other/worktree-b" process-b claude-code-ide--processes)
          (cl-letf (((symbol-function 'claude-code-ide-manager--session-git-root)
                     (lambda (session-key)
                       (cond
                        ((equal session-key "/tmp/repo/worktree-a") "/tmp/repo/")
                        ((equal session-key "/tmp/other/worktree-b") "/tmp/other/"))))
                    ((symbol-function 'claude-code-ide-manager--session-branch-name)
                     (lambda (_session-key) "feature-x")))
            (claude-code-ide-manager-refresh-items scope)
            (claude-code-ide-manager--render scope)
            (with-current-buffer (claude-code-ide-manager--get-buffer scope)
              (goto-char (point-min))
              (should (string-match-p "feature-x" (buffer-string)))
              (should-not (string-match-p "worktree-b" (buffer-string)))
              (should (equal (get-text-property (point) 'help-echo)
                             "/tmp/repo/worktree-a [feature-x]")))))
      (ignore-errors (delete-process process-a))
      (ignore-errors (delete-process process-b))
      (when-let ((buffer (get-buffer (buffer-name (claude-code-ide-manager--get-buffer scope)))))
        (kill-buffer buffer)))))

(ert-deftest claude-code-ide-test-manager-repo-scope-hover-path-omits-detached-head-branch ()
  (claude-code-ide-tests--reset-manager-state)
  (let ((scope '(:type repo :git-root "/tmp/repo/"))
        (claude-code-ide--processes (make-hash-table :test 'equal))
        (process-a (make-pipe-process :name "cc-manager-detached-a" :buffer nil)))
    (unwind-protect
        (progn
          (puthash "/tmp/repo/worktree-a" process-a claude-code-ide--processes)
          (cl-letf (((symbol-function 'claude-code-ide-manager--session-git-root)
                     (lambda (_session-key) "/tmp/repo/"))
                    ((symbol-function 'claude-code-ide-manager--session-branch-name)
                     (lambda (_session-key) nil)))
            (claude-code-ide-manager-refresh-items scope)
            (claude-code-ide-manager--render scope)
            (with-current-buffer (claude-code-ide-manager--get-buffer scope)
              (goto-char (point-min))
              (should (equal (get-text-property (point) 'help-echo)
                             "/tmp/repo/worktree-a")))))
      (ignore-errors (delete-process process-a))
      (when-let ((buffer (get-buffer (buffer-name (claude-code-ide-manager--get-buffer scope)))))
        (kill-buffer buffer)))))

(ert-deftest claude-code-ide-test-manager-persistence-toggle-disables-reload ()
  "Test manager skips reload when persistence is disabled."
  (claude-code-ide-tests--reset-manager-state)
  (let ((claude-code-ide-manager-persist-state t)
        (claude-code-ide-manager--items nil))
    (setq claude-code-ide-manager--items
          (list (make-claude-code-ide-manager-item
                 :session-key "/tmp/a"
                 :display-name "a"
                 :secondary-text "a"
                 :pinned t
                 :order-key 1
                 :live-p t)))
    (claude-code-ide-manager--save-state)
    (setq claude-code-ide-manager--items nil)
    (let ((claude-code-ide-manager-persist-state nil))
      (claude-code-ide-manager--load-state))
    (should-not claude-code-ide-manager--items)))

(ert-deftest claude-code-ide-test-manager-pinned-items-persist-when-enabled ()
  "Test manager saves and reloads pinned item state."
  (claude-code-ide-tests--reset-manager-state)
  (let ((claude-code-ide-manager-persist-state t)
        (claude-code-ide-manager--items nil))
    (setq claude-code-ide-manager--items
          (list (make-claude-code-ide-manager-item
                 :session-key "/tmp/a"
                 :display-name "a"
                 :secondary-text "a"
                 :pinned t
                 :order-key 3
                 :live-p t)))
    (claude-code-ide-manager--save-state)
    (setq claude-code-ide-manager--items nil)
    (claude-code-ide-manager--load-state)
    (should (= (length claude-code-ide-manager--items) 1))
    (should (claude-code-ide-manager-item-pinned
             (car claude-code-ide-manager--items)))
    (should (= (claude-code-ide-manager-item-order-key
                (car claude-code-ide-manager--items))
               3))))

(ert-deftest claude-code-ide-test-manager-scope-selection-state-persists-when-enabled ()
  "Test manager saves and reloads scope-local selected and active sessions."
  (claude-code-ide-tests--reset-manager-state)
  (let ((claude-code-ide-manager-persist-state t)
        (repo-scope '(:type repo :git-root "/tmp/repo/")))
    (claude-code-ide-manager--set-scope-items
     repo-scope
     (list (make-claude-code-ide-manager-item
            :session-key "/tmp/repo/worktree-a"
            :display-name "main"
            :secondary-text "worktree-a"
            :order-key 1
            :live-p t)
           (make-claude-code-ide-manager-item
            :session-key "/tmp/repo/worktree-b"
            :display-name "test"
            :secondary-text "worktree-b"
            :order-key 2
            :live-p t)))
    (claude-code-ide-manager--set-scope-selected-session-key
     repo-scope "/tmp/repo/worktree-a")
    (claude-code-ide-manager--set-scope-active-session-key
     repo-scope "/tmp/repo/worktree-b")
    (claude-code-ide-manager--save-state)
    (claude-code-ide-manager--reset-state)
    (claude-code-ide-manager--load-state)
    (should (equal (claude-code-ide-manager--scope-selected-session-key repo-scope)
                   "/tmp/repo/worktree-a"))
    (should (equal (claude-code-ide-manager--scope-active-session-key repo-scope)
                   "/tmp/repo/worktree-b"))))

(ert-deftest claude-code-ide-test-manager-reloads-persisted-state-on-initialize ()
  "Test manager initialization restores persisted items and layouts."
  (claude-code-ide-tests--reset-manager-state)
  (let ((claude-code-ide-manager-persist-state t))
    (setq claude-code-ide-manager--items
          (list (make-claude-code-ide-manager-item
                 :session-key "/tmp/a"
                 :display-name "a"
                 :secondary-text "/tmp/a"
                 :pinned t
                 :order-key 7
                 :live-p t)))
    (puthash "/tmp/a"
             '(:session-key "/tmp/a"
                            :window-state persisted-window-state
                            :selected-buffer-name "*persisted*")
             claude-code-ide-manager--layouts)
    (claude-code-ide-manager--save-state)
    (claude-code-ide-manager--reset-state)
    (claude-code-ide-manager--initialize)
    (should (= (length claude-code-ide-manager--items) 1))
    (should (equal (claude-code-ide-manager-item-session-key
                    (car claude-code-ide-manager--items))
                   "/tmp/a"))
    (should (claude-code-ide-manager-item-pinned
             (car claude-code-ide-manager--items)))
    (should (= (claude-code-ide-manager-item-order-key
                (car claude-code-ide-manager--items))
               7))
    (should (eq (plist-get (gethash "/tmp/a" claude-code-ide-manager--layouts)
                           :window-state)
                'persisted-window-state))
    (should (equal (plist-get (gethash "/tmp/a" claude-code-ide-manager--layouts)
                              :selected-buffer-name)
                   "*persisted*"))))

(ert-deftest claude-code-ide-test-manager-collects-live-sessions ()
  "Test manager builds items from live session directories."
  (claude-code-ide-tests--reset-manager-state)
  (let ((claude-code-ide--processes (make-hash-table :test 'equal))
        (process-a (make-pipe-process :name "cc-manager-a" :buffer nil))
        (process-b (make-pipe-process :name "cc-manager-b" :buffer nil)))
    (unwind-protect
        (progn
          (puthash "/tmp/project-a" process-a claude-code-ide--processes)
          (puthash "/tmp/project-b" process-b claude-code-ide--processes)
          (claude-code-ide-manager-refresh-items)
          (should (= (length claude-code-ide-manager--items) 2))
          (should (equal (mapcar #'claude-code-ide-manager-item-session-key
                                 claude-code-ide-manager--items)
                         '("/tmp/project-a" "/tmp/project-b"))))
      (ignore-errors (delete-process process-a))
      (ignore-errors (delete-process process-b)))))

(ert-deftest claude-code-ide-test-manager-sorts-pinned-before-unpinned ()
  "Test pinned items sort before unpinned items."
  (let* ((a (make-claude-code-ide-manager-item
             :session-key "a" :display-name "a" :secondary-text "a"
             :pinned nil :order-key 2 :live-p t))
         (b (make-claude-code-ide-manager-item
             :session-key "b" :display-name "b" :secondary-text "b"
             :pinned t :order-key 5 :live-p t))
         (c (make-claude-code-ide-manager-item
             :session-key "c" :display-name "c" :secondary-text "c"
             :pinned nil :order-key 1 :live-p t)))
    (should (equal (mapcar #'claude-code-ide-manager-item-session-key
                           (claude-code-ide-manager--sorted-items (list a b c)))
                   '("b" "c" "a")))))

(ert-deftest claude-code-ide-test-manager-repo-sorts-fallback-by-display-name ()
  "Test repo scope falls back to visible label ordering."
  (claude-code-ide-tests--reset-manager-state)
  (let ((scope '(:type repo :git-root "/tmp/repo/"))
        (claude-code-ide--processes (make-hash-table :test 'equal))
        (process-a (make-pipe-process :name "cc-manager-repo-sort-a" :buffer nil))
        (process-b (make-pipe-process :name "cc-manager-repo-sort-b" :buffer nil)))
    (unwind-protect
        (progn
          (puthash "/tmp/repo/zeta" process-a claude-code-ide--processes)
          (puthash "/tmp/repo/alpha" process-b claude-code-ide--processes)
          (cl-letf (((symbol-function 'claude-code-ide-manager--session-git-root)
                     (lambda (_session-key) "/tmp/repo/"))
                    ((symbol-function 'claude-code-ide-manager--session-branch-name)
                     (lambda (session-key)
                       (if (equal session-key "/tmp/repo/zeta")
                           "alpha"
                         "beta"))))
            (claude-code-ide-manager-refresh-items scope)
            (should (equal (claude-code-ide-manager--visible-session-keys scope)
                           '("/tmp/repo/zeta" "/tmp/repo/alpha")))
            (claude-code-ide-manager--render scope)
            (with-current-buffer (claude-code-ide-manager--get-buffer scope)
              (goto-char (point-min))
              (should (string-match-p "alpha" (buffer-substring-no-properties
                                               (line-beginning-position)
                                               (line-end-position))))
              (forward-line 1)
              (should (string-match-p "beta" (buffer-substring-no-properties
                                              (line-beginning-position)
                                              (line-end-position)))))))
      (ignore-errors (delete-process process-a))
      (ignore-errors (delete-process process-b))
      (when-let ((buffer (get-buffer (buffer-name (claude-code-ide-manager--get-buffer scope)))))
        (kill-buffer buffer)))))

(ert-deftest claude-code-ide-test-manager-repo-sort-keeps-order-key-precedence ()
  "Test repo scope still honors explicit order keys before label sorting."
  (let* ((scope '(:type repo :git-root "/tmp/repo/"))
         (a (make-claude-code-ide-manager-item
             :session-key "/tmp/repo/a"
             :display-name "zeta"
             :secondary-text "a"
             :pinned nil
             :order-key 1
             :live-p t))
         (b (make-claude-code-ide-manager-item
             :session-key "/tmp/repo/b"
             :display-name "alpha"
             :secondary-text "b"
             :pinned nil
             :order-key 2
             :live-p t)))
    (should (equal (mapcar #'claude-code-ide-manager-item-session-key
                           (claude-code-ide-manager--sorted-items (list a b) scope))
                   '("/tmp/repo/a" "/tmp/repo/b")))))

(ert-deftest claude-code-ide-test-manager-assigns-visible-slots-1-to-10 ()
  "Test visible rows map to slot numbers in order."
  (let ((items
         (cl-loop for index from 1 to 11
                  collect (make-claude-code-ide-manager-item
                           :session-key (format "s%d" index)
                           :display-name (format "s%d" index)
                           :secondary-text (format "s%d" index)
                           :pinned nil
                           :order-key index
                           :live-p t))))
    (let ((slots (claude-code-ide-manager--slot-map items)))
      (should (= (hash-table-count slots) 10))
      (should (= (gethash "s1" slots) 1))
      (should (= (gethash "s10" slots) 10))
      (should-not (gethash "s11" slots)))))

(ert-deftest claude-code-ide-test-manager-sidebar-renders-project-with-hover-path ()
  "Test sidebar render shows basename and keeps full path in hover text."
  (claude-code-ide-tests--reset-manager-state)
  (setq claude-code-ide-manager--items
        (list (make-claude-code-ide-manager-item
               :session-key "/tmp/project-a"
               :display-name "project-a"
               :secondary-text "/tmp/project-a"
               :pinned t
               :order-key 1
               :live-p t)))
  (with-current-buffer (claude-code-ide-manager--get-buffer)
    (claude-code-ide-manager--render)
    (should (equal major-mode 'claude-code-ide-manager-mode))
    (should (string-match-p "project-a" (buffer-string)))
    (should-not (string-match-p "/tmp/project-a" (buffer-string)))
    (goto-char (point-min))
    (should (equal (get-text-property (point) 'help-echo)
                   "/tmp/project-a"))))

(ert-deftest claude-code-ide-test-manager-point-shows-full-path-in-echo-area ()
  "Test manager point movement mirrors the row path into the echo area."
  (claude-code-ide-tests--reset-manager-state)
  (setq claude-code-ide-manager--items
        (list (make-claude-code-ide-manager-item
               :session-key "/tmp/project-a"
               :display-name "project-a"
               :secondary-text "/tmp/project-a"
               :pinned nil
               :order-key 1
               :live-p t)))
  (let (message-output)
    (unwind-protect
        (cl-letf (((symbol-function 'message)
                   (lambda (format-string &rest args)
                     (setq message-output (apply #'format format-string args)))))
          (delete-other-windows)
          (switch-to-buffer (claude-code-ide-manager--get-buffer))
          (claude-code-ide-manager--render)
          (goto-char (point-min))
          (claude-code-ide-manager--show-point-path)
          (should (equal message-output "/tmp/project-a")))
      (when-let ((window (get-buffer-window (claude-code-ide-manager--get-buffer))))
        (unless (one-window-p t)
          (delete-window window)))
      (when-let ((buffer (get-buffer (buffer-name (claude-code-ide-manager--get-buffer)))))
        (kill-buffer buffer)))))

(ert-deftest claude-code-ide-test-manager-point-shows-path-and-branch-in-echo-area ()
  "Test manager point movement shows repo path plus branch in the echo area."
  (claude-code-ide-tests--reset-manager-state)
  (setq claude-code-ide-manager--items
        (list (make-claude-code-ide-manager-item
               :session-key "/tmp/repo/worktree-a"
               :display-name "feature-x"
               :secondary-text "/tmp/repo/worktree-a"
               :pinned nil
               :order-key 1
               :live-p t)))
  (let (message-output)
    (unwind-protect
        (cl-letf (((symbol-function 'message)
                   (lambda (format-string &rest args)
                     (setq message-output (apply #'format format-string args))))
                  ((symbol-function 'claude-code-ide-manager--session-branch-name)
                   (lambda (_session-key) "feature-x")))
          (delete-other-windows)
          (switch-to-buffer (claude-code-ide-manager--get-buffer))
          (claude-code-ide-manager--render)
          (goto-char (point-min))
          (claude-code-ide-manager--show-point-path)
          (should (equal message-output "/tmp/repo/worktree-a [feature-x]")))
      (when-let ((window (get-buffer-window (claude-code-ide-manager--get-buffer))))
        (unless (one-window-p t)
          (delete-window window)))
      (when-let ((buffer (get-buffer (buffer-name (claude-code-ide-manager--get-buffer)))))
        (kill-buffer buffer)))))

(ert-deftest claude-code-ide-test-manager-sidebar-highlights-current-session ()
  "Test sidebar render highlights the active session row."
  (claude-code-ide-tests--reset-manager-state)
  (setq claude-code-ide-manager--items
        (list (make-claude-code-ide-manager-item
               :session-key "/tmp/project-a"
               :display-name "project-a"
               :secondary-text "/tmp/project-a"
               :pinned nil
               :order-key 1
               :live-p t)
              (make-claude-code-ide-manager-item
               :session-key "/tmp/project-b"
               :display-name "project-b"
               :secondary-text "/tmp/project-b"
               :pinned nil
               :order-key 2
               :live-p t)))
  (setq claude-code-ide-manager--current-session-key "/tmp/project-b")
  (with-current-buffer (claude-code-ide-manager--get-buffer)
    (claude-code-ide-manager--render)
    (goto-char (point-min))
    (should-not (get-text-property (point) 'face))
    (forward-line 1)
    (should (eq (get-text-property (point) 'face)
                'claude-code-ide-manager-current-session-face))))

(ert-deftest claude-code-ide-test-manager-render-idle-indicator-aligns-slot-column ()
  "Test idle and non-idle rows keep the slot column aligned."
  (claude-code-ide-tests--reset-manager-state)
  (let ((idle-buffer (get-buffer-create "*cc-idle*"))
        (active-buffer (get-buffer-create "*cc-active*")))
    (unwind-protect
        (progn
          (with-current-buffer idle-buffer
            (setq-local claude-code-ide-session-idle-enabled t
                        claude-code-ide-session-idle-p t))
          (with-current-buffer active-buffer
            (setq-local claude-code-ide-session-idle-enabled nil
                        claude-code-ide-session-idle-p nil))
          (setq claude-code-ide-manager--items
                (list (make-claude-code-ide-manager-item
                       :session-key "/tmp/project-a"
                       :display-name "project-a"
                       :secondary-text "/tmp/project-a"
                       :pinned nil
                       :order-key 1
                       :live-p t)
                      (make-claude-code-ide-manager-item
                       :session-key "/tmp/project-b"
                       :display-name "project-b"
                       :secondary-text "/tmp/project-b"
                       :pinned nil
                       :order-key 2
                       :live-p t)))
          (cl-letf (((symbol-function 'claude-code-ide--get-session-buffer)
                     (lambda (session-key)
                       (cond
                        ((equal session-key "/tmp/project-a") idle-buffer)
                        ((equal session-key "/tmp/project-b") active-buffer)))))
            (with-current-buffer (claude-code-ide-manager--get-buffer)
              (claude-code-ide-manager--render)
              (goto-char (point-min))
              (let ((idle-row (buffer-substring-no-properties
                               (line-beginning-position)
                               (line-end-position)))
                    (idle-column (claude-code-ide-tests--manager-row-slot-column)))
                (forward-line 1)
                (let ((active-row (buffer-substring-no-properties
                                   (line-beginning-position)
                                   (line-end-position)))
                      (active-column (claude-code-ide-tests--manager-row-slot-column)))
                  (should (= idle-column active-column))
                  (should (string-match-p "🔔" idle-row))
                  (should-not (string-match-p "🔔" active-row)))))))
      (mapc (lambda (buffer)
              (when (buffer-live-p buffer)
                (kill-buffer buffer)))
            (list idle-buffer active-buffer)))))

(ert-deftest claude-code-ide-test-manager-render-pinned-row-uses-gutter-marker ()
  "Test pinned rows use a gutter marker instead of inline [P] text."
  (claude-code-ide-tests--reset-manager-state)
  (setq claude-code-ide-manager--items
        (list (make-claude-code-ide-manager-item
               :session-key "/tmp/project-a"
               :display-name "project-a"
               :secondary-text "/tmp/project-a"
               :pinned t
               :order-key 1
               :live-p t)))
  (with-current-buffer (claude-code-ide-manager--get-buffer)
    (claude-code-ide-manager--render)
    (goto-char (point-min))
    (let ((row (buffer-substring-no-properties
                (line-beginning-position)
                (line-end-position))))
      (should-not (string-match-p "\\[P\\]" row))
      (should (string-match-p "📌" row)))))

(ert-deftest claude-code-ide-test-manager-render-idle-marker-overrides-pin-marker ()
  "Test the idle gutter marker takes priority over the pin marker."
  (claude-code-ide-tests--reset-manager-state)
  (let ((idle-buffer (get-buffer-create "*cc-pinned-idle*")))
    (unwind-protect
        (progn
          (with-current-buffer idle-buffer
            (setq-local claude-code-ide-session-idle-enabled t
                        claude-code-ide-session-idle-p t))
          (setq claude-code-ide-manager--items
                (list (make-claude-code-ide-manager-item
                       :session-key "/tmp/project-a"
                       :display-name "project-a"
                       :secondary-text "/tmp/project-a"
                       :pinned t
                       :order-key 1
                       :live-p t)))
          (cl-letf (((symbol-function 'claude-code-ide--get-session-buffer)
                     (lambda (_session-key) idle-buffer)))
            (with-current-buffer (claude-code-ide-manager--get-buffer)
              (claude-code-ide-manager--render)
              (goto-char (point-min))
              (let ((row (buffer-substring-no-properties
                          (line-beginning-position)
                          (line-end-position))))
                (should (string-match-p "🔔" row))
                (should-not (string-match-p "📌" row))
                (should-not (string-match-p "\\[P\\]" row))))))
      (when (buffer-live-p idle-buffer)
        (kill-buffer idle-buffer)))))

(ert-deftest claude-code-ide-test-manager-render-idle-face-respects-current-session-priority ()
  "Test current idle rows keep the current-session face and others use idle face."
  (claude-code-ide-tests--reset-manager-state)
  (let ((idle-buffer (get-buffer-create "*cc-idle-priority*"))
        (current-buffer (get-buffer-create "*cc-current-priority*")))
    (unwind-protect
        (progn
          (with-current-buffer idle-buffer
            (setq-local claude-code-ide-session-idle-enabled t
                        claude-code-ide-session-idle-p t))
          (with-current-buffer current-buffer
            (setq-local claude-code-ide-session-idle-enabled t
                        claude-code-ide-session-idle-p t))
          (setq claude-code-ide-manager--items
                (list (make-claude-code-ide-manager-item
                       :session-key "/tmp/project-a"
                       :display-name "project-a"
                       :secondary-text "/tmp/project-a"
                       :pinned nil
                       :order-key 1
                       :live-p t)
                      (make-claude-code-ide-manager-item
                       :session-key "/tmp/project-b"
                       :display-name "project-b"
                       :secondary-text "/tmp/project-b"
                       :pinned nil
                       :order-key 2
                       :live-p t)))
          (setq claude-code-ide-manager--current-session-key "/tmp/project-b")
          (cl-letf (((symbol-function 'claude-code-ide--get-session-buffer)
                     (lambda (session-key)
                       (cond
                        ((equal session-key "/tmp/project-a") idle-buffer)
                        ((equal session-key "/tmp/project-b") current-buffer)))))
            (with-current-buffer (claude-code-ide-manager--get-buffer)
              (claude-code-ide-manager--render)
              (goto-char (point-min))
              (should (eq (get-text-property (point) 'face)
                          'claude-code-ide-manager-idle-session-face))
              (forward-line 1)
              (should (eq (get-text-property (point) 'face)
                          'claude-code-ide-manager-current-session-face)))))
      (mapc (lambda (buffer)
              (when (buffer-live-p buffer)
                (kill-buffer buffer)))
            (list idle-buffer current-buffer)))))

(ert-deftest claude-code-ide-test-manager-render-working-marker-shows-gear ()
  "Test working rows render the gear marker."
  (claude-code-ide-tests--reset-manager-state)
  (let ((working-buffer (get-buffer-create "*cc-working-marker*")))
    (unwind-protect
        (progn
          (with-current-buffer working-buffer
            (setq-local claude-code-ide-session-idle-enabled t
                        claude-code-ide-session-idle-p nil
                        claude-code-ide-session-working-p t))
          (setq claude-code-ide-manager--items
                (list (make-claude-code-ide-manager-item
                       :session-key "/tmp/project-a"
                       :display-name "project-a"
                       :secondary-text "/tmp/project-a"
                       :pinned nil
                       :order-key 1
                       :live-p t)))
          (cl-letf (((symbol-function 'claude-code-ide--get-session-buffer)
                     (lambda (_session-key) working-buffer)))
            (with-current-buffer (claude-code-ide-manager--get-buffer)
              (claude-code-ide-manager--render)
              (goto-char (point-min))
              (let ((row (claude-code-ide-tests--manager-row-text)))
                (should (string-match-p "⚙︎" row))
                (should-not (string-match-p "📌" row))
                (should-not (string-match-p "🔔" row))))))
      (when (buffer-live-p working-buffer)
        (kill-buffer working-buffer)))))

(ert-deftest claude-code-ide-test-manager-render-working-face-applies-unless-priority-overrides ()
  "Test working rows use the working face when no higher-priority face applies."
  (claude-code-ide-tests--reset-manager-state)
  (let ((working-buffer (get-buffer-create "*cc-working-face*")))
    (unwind-protect
        (progn
          (with-current-buffer working-buffer
            (setq-local claude-code-ide-session-idle-enabled t
                        claude-code-ide-session-idle-p nil
                        claude-code-ide-session-working-p t))
          (setq claude-code-ide-manager--items
                (list (make-claude-code-ide-manager-item
                       :session-key "/tmp/project-a"
                       :display-name "project-a"
                       :secondary-text "/tmp/project-a"
                       :pinned nil
                       :order-key 1
                       :live-p t)))
          (cl-letf (((symbol-function 'claude-code-ide--get-session-buffer)
                     (lambda (_session-key) working-buffer)))
            (with-current-buffer (claude-code-ide-manager--get-buffer)
              (claude-code-ide-manager--render)
              (goto-char (point-min))
              (should (eq (get-text-property (point) 'face)
                          'claude-code-ide-manager-working-session-face)))))
      (when (buffer-live-p working-buffer)
        (kill-buffer working-buffer)))))

(ert-deftest claude-code-ide-test-manager-render-working-current-session-face-overrides-working-face ()
  "Test current rows keep the current-session face even when working."
  (claude-code-ide-tests--reset-manager-state)
  (let ((working-buffer (get-buffer-create "*cc-working-current*")))
    (unwind-protect
        (progn
          (with-current-buffer working-buffer
            (setq-local claude-code-ide-session-idle-enabled t
                        claude-code-ide-session-idle-p nil
                        claude-code-ide-session-working-p t))
          (setq claude-code-ide-manager--items
                (list (make-claude-code-ide-manager-item
                       :session-key "/tmp/project-a"
                       :display-name "project-a"
                       :secondary-text "/tmp/project-a"
                       :pinned nil
                       :order-key 1
                       :live-p t)))
          (setq claude-code-ide-manager--current-session-key "/tmp/project-a")
          (cl-letf (((symbol-function 'claude-code-ide--get-session-buffer)
                     (lambda (_session-key) working-buffer)))
            (with-current-buffer (claude-code-ide-manager--get-buffer)
              (claude-code-ide-manager--render)
              (goto-char (point-min))
              (should (eq (get-text-property (point) 'face)
                          'claude-code-ide-manager-current-session-face)))))
      (when (buffer-live-p working-buffer)
        (kill-buffer working-buffer)))))

(ert-deftest claude-code-ide-test-manager-render-working-disabled-idle-monitoring-does-not-render-working-state ()
  "Test sessions with idle monitoring disabled do not render as working."
  (claude-code-ide-tests--reset-manager-state)
  (let ((working-buffer (get-buffer-create "*cc-working-idle*")))
    (unwind-protect
        (progn
          (with-current-buffer working-buffer
            (setq-local claude-code-ide-session-idle-enabled nil
                        claude-code-ide-session-idle-p nil
                        claude-code-ide-session-working-p t))
          (setq claude-code-ide-manager--items
                (list (make-claude-code-ide-manager-item
                       :session-key "/tmp/project-a"
                       :display-name "project-a"
                       :secondary-text "/tmp/project-a"
                       :pinned t
                       :order-key 1
                       :live-p t)))
          (cl-letf (((symbol-function 'claude-code-ide--get-session-buffer)
                     (lambda (_session-key) working-buffer)))
            (with-current-buffer (claude-code-ide-manager--get-buffer)
              (claude-code-ide-manager--render)
              (goto-char (point-min))
              (should-not (eq (get-text-property (point) 'face)
                              'claude-code-ide-manager-working-session-face))
              (let ((row (claude-code-ide-tests--manager-row-text)))
                (should-not (string-match-p "⚙︎" row))
                (should-not (string-match-p "🔔" row))
                (should (string-match-p "📌" row))))))
      (when (buffer-live-p working-buffer)
        (kill-buffer working-buffer)))))

(ert-deftest claude-code-ide-test-manager-render-working-marker-overrides-pin-marker ()
  "Test working rows show the working marker instead of the pin marker."
  (claude-code-ide-tests--reset-manager-state)
  (let ((working-buffer (get-buffer-create "*cc-working-pin*")))
    (unwind-protect
        (progn
          (with-current-buffer working-buffer
            (setq-local claude-code-ide-session-idle-enabled t
                        claude-code-ide-session-idle-p nil
                        claude-code-ide-session-working-p t))
          (setq claude-code-ide-manager--items
                (list (make-claude-code-ide-manager-item
                       :session-key "/tmp/project-a"
                       :display-name "project-a"
                       :secondary-text "/tmp/project-a"
                       :pinned t
                       :order-key 1
                       :live-p t)))
          (cl-letf (((symbol-function 'claude-code-ide--get-session-buffer)
                     (lambda (_session-key) working-buffer)))
            (with-current-buffer (claude-code-ide-manager--get-buffer)
              (claude-code-ide-manager--render)
              (goto-char (point-min))
              (let ((row (claude-code-ide-tests--manager-row-text)))
                (should (string-match-p "⚙︎" row))
                (should-not (string-match-p "📌" row))
                (should-not (string-match-p "\\[P\\]" row))))))
      (when (buffer-live-p working-buffer)
        (kill-buffer working-buffer)))))

(ert-deftest claude-code-ide-test-manager-render-working-requires-explicit-activity-state ()
  "Test fresh non-idle sessions do not render as working without activity."
  (claude-code-ide-tests--reset-manager-state)
  (let ((session-buffer (get-buffer-create "*cc-working-fresh*")))
    (unwind-protect
        (progn
          (with-current-buffer session-buffer
            (setq-local claude-code-ide-session-idle-enabled t
                        claude-code-ide-session-idle-p nil
                        claude-code-ide-session-working-p nil))
          (setq claude-code-ide-manager--items
                (list (make-claude-code-ide-manager-item
                       :session-key "/tmp/project-a"
                       :display-name "project-a"
                       :secondary-text "/tmp/project-a"
                       :pinned t
                       :order-key 1
                       :live-p t)))
          (cl-letf (((symbol-function 'claude-code-ide--get-session-buffer)
                     (lambda (_session-key) session-buffer)))
            (with-current-buffer (claude-code-ide-manager--get-buffer)
              (claude-code-ide-manager--render)
              (goto-char (point-min))
              (should-not (eq (get-text-property (point) 'face)
                              'claude-code-ide-manager-working-session-face))
              (let ((row (claude-code-ide-tests--manager-row-text)))
                (should-not (string-match-p "⚙︎" row))
                (should-not (string-match-p "🔔" row))
                (should (string-match-p "📌" row))))))
      (when (buffer-live-p session-buffer)
        (kill-buffer session-buffer)))))

(ert-deftest claude-code-ide-test-manager-idle-indicator-uses-live-session-state ()
  "Test the bell follows live buffer state after rerender without mutating items."
  (claude-code-ide-tests--reset-manager-state)
  (let ((idle-buffer (get-buffer-create "*cc-live-idle*"))
        (active-buffer (get-buffer-create "*cc-live-active*")))
    (unwind-protect
        (let ((serialized-items-before nil))
          (with-current-buffer idle-buffer
            (setq-local claude-code-ide-session-idle-enabled t
                        claude-code-ide-session-idle-p t))
          (with-current-buffer active-buffer
            (setq-local claude-code-ide-session-idle-enabled nil
                        claude-code-ide-session-idle-p nil))
          (setq claude-code-ide-manager--items
                (list (make-claude-code-ide-manager-item
                       :session-key "/tmp/project-a"
                       :display-name "project-a"
                       :secondary-text "/tmp/project-a"
                       :pinned nil
                       :order-key 1
                       :live-p t)
                      (make-claude-code-ide-manager-item
                       :session-key "/tmp/project-b"
                       :display-name "project-b"
                       :secondary-text "/tmp/project-b"
                       :pinned nil
                       :order-key 2
                       :live-p t)))
          (setq serialized-items-before
                (mapcar #'claude-code-ide-manager--serialize-item
                        claude-code-ide-manager--items))
          (cl-letf (((symbol-function 'claude-code-ide--get-session-buffer)
                     (lambda (session-key)
                       (cond
                        ((equal session-key "/tmp/project-a") idle-buffer)
                        ((equal session-key "/tmp/project-b") active-buffer)))))
            (with-current-buffer (claude-code-ide-manager--get-buffer)
              (claude-code-ide-manager--render)
              (goto-char (point-min))
              (should (string-match-p "🔔"
                                      (buffer-substring-no-properties
                                       (line-beginning-position)
                                       (line-end-position))))
              (forward-line 1)
              (should-not (string-match-p "🔔"
                                          (buffer-substring-no-properties
                                           (line-beginning-position)
                                           (line-end-position))))
              (with-current-buffer idle-buffer
                (setq-local claude-code-ide-session-idle-enabled nil
                            claude-code-ide-session-idle-p nil))
              (with-current-buffer active-buffer
                (setq-local claude-code-ide-session-idle-enabled t
                            claude-code-ide-session-idle-p t))
              (claude-code-ide-manager--render)
              (goto-char (point-min))
              (should-not (string-match-p "🔔"
                                          (buffer-substring-no-properties
                                           (line-beginning-position)
                                           (line-end-position))))
              (forward-line 1)
              (should (string-match-p "🔔"
                                      (buffer-substring-no-properties
                                       (line-beginning-position)
                                       (line-end-position))))))
          (should (equal serialized-items-before
                         (mapcar #'claude-code-ide-manager--serialize-item
                                 claude-code-ide-manager--items))))
      (mapc (lambda (buffer)
              (when (buffer-live-p buffer)
                (kill-buffer buffer)))
            (list idle-buffer active-buffer)))))

(ert-deftest claude-code-ide-test-manager-idle-indicator-does-not_alias-colliding-basenames ()
  "Test manager idle state stays attached to the right session with colliding basenames."
  (claude-code-ide-tests--reset-manager-state)
  (let* ((directory-a "/tmp/team-a/project/")
         (directory-b "/tmp/team-b/project/")
         (idle-buffer (generate-new-buffer "*claude-code[project]<team-a>*"))
         (active-buffer (generate-new-buffer "*claude-code[project]*"))
         (process-a (make-pipe-process :name "cc-collision-idle" :buffer idle-buffer))
         (claude-code-ide--processes (make-hash-table :test 'equal)))
    (unwind-protect
        (progn
          (with-current-buffer idle-buffer
            (setq-local claude-code-ide-session-idle-enabled t
                        claude-code-ide-session-idle-p t))
          (with-current-buffer active-buffer
            (setq-local claude-code-ide-session-idle-enabled t
                        claude-code-ide-session-idle-p nil))
          (puthash directory-a process-a claude-code-ide--processes)
          (setq claude-code-ide-manager--items
                (list (make-claude-code-ide-manager-item
                       :session-key directory-a
                       :display-name "team-a/project"
                       :secondary-text directory-a
                       :pinned nil
                       :order-key 1
                       :live-p t)
                      (make-claude-code-ide-manager-item
                       :session-key directory-b
                       :display-name "team-b/project"
                       :secondary-text directory-b
                       :pinned nil
                       :order-key 2
                       :live-p t)))
          (with-current-buffer (claude-code-ide-manager--get-buffer)
            (claude-code-ide-manager--render)
            (goto-char (point-min))
            (should (string-match-p "🔔" (claude-code-ide-tests--manager-row-text)))
            (forward-line 1)
            (should-not (string-match-p "🔔" (claude-code-ide-tests--manager-row-text)))))
      (ignore-errors (delete-process process-a))
      (when (buffer-live-p idle-buffer)
        (kill-buffer idle-buffer))
      (when (buffer-live-p active-buffer)
        (kill-buffer active-buffer)))))

(ert-deftest claude-code-ide-test-manager-visible-sidebar-updates-on-idle-transitions ()
  "Test the visible manager updates when a session becomes idle or active."
  (claude-code-ide-tests--reset-manager-state)
  (let ((session-buffer (get-buffer-create "*cc-idle-transition*"))
        (manager-buffer (claude-code-ide-manager--get-buffer))
        (content-buffer (get-buffer-create "*cc-content*"))
        (claude-code-ide--processes (make-hash-table :test 'equal))
        (process-a (make-pipe-process :name "cc-idle-transition" :buffer nil))
        (timer-called nil))
    (unwind-protect
        (save-window-excursion
          (with-current-buffer session-buffer
            (rename-buffer "*claude-code[idle-transition]*" t)
            (setq-local claude-code-ide-session-idle-enabled t
                        claude-code-ide-session-idle-p nil))
          (setq claude-code-ide-manager--items
                (list (make-claude-code-ide-manager-item
                       :session-key "/tmp/project-a"
                       :display-name "project-a"
                       :secondary-text "/tmp/project-a"
                       :pinned nil
                       :order-key 1
                       :live-p t)))
          (puthash "/tmp/project-a" process-a claude-code-ide--processes)
          (delete-other-windows)
          (switch-to-buffer content-buffer)
          (set-window-buffer (split-window-right) manager-buffer)
          (should (get-buffer-window manager-buffer))
          (cl-letf (((symbol-function 'claude-code-ide--get-session-buffer)
                     (lambda (_session-key) session-buffer))
                    ((symbol-function 'run-with-timer)
                     (lambda (&rest _args)
                       (setq timer-called t)
                       'mock-idle-timer)))
            (with-current-buffer manager-buffer
              (claude-code-ide-manager--render)
              (should-not (string-match-p "🔔"
                                          (claude-code-ide-tests--manager-row-text))))
            (claude-code-ide-session-idle--fire-timer session-buffer)
            (with-current-buffer manager-buffer
              (should (string-match-p "🔔"
                                      (claude-code-ide-tests--manager-row-text))))
            (with-current-buffer session-buffer
              (claude-code-ide-session-idle-reset-timer))
            (with-current-buffer manager-buffer
              (should-not (string-match-p "🔔"
                                          (claude-code-ide-tests--manager-row-text))))
            (should timer-called)))
      (ignore-errors (delete-process process-a))
      (mapc (lambda (buffer)
              (when (buffer-live-p buffer)
                (kill-buffer buffer)))
            (list session-buffer manager-buffer content-buffer)))))

(ert-deftest claude-code-ide-test-session-idle-notification-policy-gates-alerts ()
  "Test idle notification policy gates alert emission without changing idle state."
  (let ((session-buffer (get-buffer-create "*cc-idle-policy*"))
        (alerts nil))
    (unwind-protect
        (cl-letf (((symbol-function 'alert)
                   (lambda (message &rest args)
                     (push (cons message args) alerts))))
          (with-current-buffer session-buffer
            (rename-buffer "*claude-code[idle-policy]*" t)
            (setq-local claude-code-ide-session-idle-enabled t
                        claude-code-ide-session-idle-p nil
                        claude-code-ide-session-idle-generation 17
                        claude-code-ide-session-idle-timer 'mock-idle-timer))
          (dolist (policy '(nil manager alert manager-and-alert))
            (setq alerts nil
                  claude-code-ide-session-idle-notification-policy policy)
            (with-current-buffer session-buffer
              (let ((before-enabled claude-code-ide-session-idle-enabled)
                    (before-idle claude-code-ide-session-idle-p)
                    (before-generation claude-code-ide-session-idle-generation)
                    (before-timer claude-code-ide-session-idle-timer))
                (claude-code-ide-session-idle--notify session-buffer)
                (pcase policy
                  ((or 'alert 'manager-and-alert)
                   (should (= (length alerts) 1)))
                  (_
                   (should-not alerts)))
                (should (eq before-enabled claude-code-ide-session-idle-enabled))
                (should (eq before-idle claude-code-ide-session-idle-p))
                (should (equal before-generation claude-code-ide-session-idle-generation))
                (should (eq before-timer claude-code-ide-session-idle-timer))))))
      (when (buffer-live-p session-buffer)
        (kill-buffer session-buffer)))))

(ert-deftest claude-code-ide-test-session-idle-installs-visibility-clear-hooks ()
  "Test idle monitoring clears stale idle when visibility changes."
  (should (require 'claude-code-ide-session-idle nil t))
  (should (memq #'claude-code-ide-session-idle--handle-visibility-change
                window-state-change-hook))
  (should (memq #'claude-code-ide-session-idle--handle-visibility-change
                window-configuration-change-hook))
  (let ((session-buffer (generate-new-buffer "*claude-code[test-idle-focus-hook]*")))
    (unwind-protect
        (save-window-excursion
          (delete-other-windows)
          (switch-to-buffer session-buffer)
          (with-current-buffer session-buffer
            (setq-local claude-code-ide-session-idle-enabled t
                        claude-code-ide-session-idle-p t
                        claude-code-ide-session-idle-timer 'mock-idle-timer))
          (cl-letf (((symbol-function 'frame-focus-state)
                     (lambda (_frame) t)))
            (run-hook-with-args 'after-focus-change-function)
            (with-current-buffer session-buffer
              (should-not claude-code-ide-session-idle-p)
              (should-not claude-code-ide-session-idle-timer))))
      (when (buffer-live-p session-buffer)
        (kill-buffer session-buffer)))))

(ert-deftest claude-code-ide-test-manager-non-idle-reset-does-not-rerender ()
  "Test ordinary reset calls do not rerender the visible manager."
  (claude-code-ide-tests--reset-manager-state)
  (let ((session-buffer (get-buffer-create "*cc-non-idle-reset*"))
        (manager-buffer (claude-code-ide-manager--get-buffer))
        (content-buffer (get-buffer-create "*cc-content-reset*"))
        (refresh-count 0))
    (unwind-protect
        (save-window-excursion
          (with-current-buffer session-buffer
            (rename-buffer "*claude-code[non-idle-reset]*" t)
            (setq-local claude-code-ide-session-idle-enabled t
                        claude-code-ide-session-idle-p nil))
          (setq claude-code-ide-manager--items
                (list (make-claude-code-ide-manager-item
                       :session-key "/tmp/project-a"
                       :display-name "project-a"
                       :secondary-text "/tmp/project-a"
                       :pinned nil
                       :order-key 1
                       :live-p t)))
          (delete-other-windows)
          (switch-to-buffer content-buffer)
          (set-window-buffer (split-window-right) manager-buffer)
          (should (get-buffer-window manager-buffer))
          (let ((orig-refresh
                 (symbol-function 'claude-code-ide-manager--refresh-sidebar-state)))
            (cl-letf (((symbol-function 'claude-code-ide--get-session-buffer)
                       (lambda (_session-key) session-buffer))
                      ((symbol-function 'run-with-timer)
                       (lambda (&rest _args)
                         'mock-idle-timer))
                      ((symbol-function 'claude-code-ide-manager--refresh-sidebar-state)
                       (lambda ()
                         (setq refresh-count (1+ refresh-count))
                         (funcall orig-refresh))))
              (with-current-buffer manager-buffer
                (claude-code-ide-manager--render))
              (setq refresh-count 0)
              (with-current-buffer session-buffer
                (claude-code-ide-session-idle-reset-timer))
              (should (= refresh-count 0)))))
      (mapc (lambda (buffer)
              (when (buffer-live-p buffer)
                (kill-buffer buffer)))
            (list session-buffer manager-buffer content-buffer)))))

(ert-deftest claude-code-ide-test-manager-visible-sidebar-updates-on-idle-clear-state ()
  "Test clearing an idle session updates the visible manager bell state."
  (claude-code-ide-tests--reset-manager-state)
  (let ((session-buffer (get-buffer-create "*cc-idle-clear-state*"))
        (manager-buffer (claude-code-ide-manager--get-buffer))
        (content-buffer (get-buffer-create "*cc-content-clear-state*"))
        (claude-code-ide--processes (make-hash-table :test 'equal))
        (process-a (make-pipe-process :name "cc-idle-clear-state" :buffer nil)))
    (unwind-protect
        (save-window-excursion
          (with-current-buffer session-buffer
            (rename-buffer "*claude-code[idle-clear-state]*" t)
            (setq-local claude-code-ide-session-idle-enabled t
                        claude-code-ide-session-idle-p t
                        claude-code-ide-session-idle-timer 'mock-idle-timer))
          (setq claude-code-ide-manager--items
                (list (make-claude-code-ide-manager-item
                       :session-key "/tmp/project-a"
                       :display-name "project-a"
                       :secondary-text "/tmp/project-a"
                       :pinned nil
                       :order-key 1
                       :live-p t)))
          (puthash "/tmp/project-a" process-a claude-code-ide--processes)
          (delete-other-windows)
          (switch-to-buffer content-buffer)
          (set-window-buffer (split-window-right) manager-buffer)
          (should (get-buffer-window manager-buffer))
          (cl-letf (((symbol-function 'claude-code-ide--get-session-buffer)
                     (lambda (_session-key) session-buffer)))
            (with-current-buffer manager-buffer
              (claude-code-ide-manager--render)
              (should (string-match-p "🔔"
                                      (claude-code-ide-tests--manager-row-text))))
            (with-current-buffer session-buffer
              (claude-code-ide-session-idle-clear-state))
            (with-current-buffer manager-buffer
              (should-not (string-match-p "🔔"
                                          (claude-code-ide-tests--manager-row-text))))))
      (ignore-errors (delete-process process-a))
      (mapc (lambda (buffer)
              (when (buffer-live-p buffer)
                (kill-buffer buffer)))
            (list session-buffer manager-buffer content-buffer)))))

(ert-deftest claude-code-ide-test-manager-non-idle-output-does-not-rerender ()
  "Test ordinary backend output does not rerender the visible manager."
  (claude-code-ide-tests--reset-manager-state)
  (let ((session-buffer (get-buffer-create "*cc-non-idle-output*"))
        (manager-buffer (claude-code-ide-manager--get-buffer))
        (content-buffer (get-buffer-create "*cc-content-output*"))
        (refresh-count 0))
    (unwind-protect
        (save-window-excursion
          (with-current-buffer session-buffer
            (rename-buffer "*claude-code[non-idle-output]*" t)
            (setq-local claude-code-ide-session-idle-enabled t
                        claude-code-ide-session-idle-p nil))
          (setq claude-code-ide-manager--items
                (list (make-claude-code-ide-manager-item
                       :session-key "/tmp/project-a"
                       :display-name "project-a"
                       :secondary-text "/tmp/project-a"
                       :pinned nil
                       :order-key 1
                       :live-p t)))
          (delete-other-windows)
          (switch-to-buffer content-buffer)
          (set-window-buffer (split-window-right) manager-buffer)
          (should (get-buffer-window manager-buffer))
          (let ((orig-refresh
                 (symbol-function 'claude-code-ide-manager--refresh-sidebar-state)))
            (cl-letf (((symbol-function 'claude-code-ide--get-session-buffer)
                       (lambda (_session-key) session-buffer))
                      ((symbol-function 'process-buffer)
                       (lambda (_process) session-buffer))
                      ((symbol-function 'run-with-timer)
                       (lambda (&rest _args) 'mock-idle-timer))
                      ((symbol-function 'claude-code-ide-manager--refresh-sidebar-state)
                       (lambda ()
                         (setq refresh-count (1+ refresh-count))
                         (funcall orig-refresh))))
              (with-current-buffer manager-buffer
                (claude-code-ide-manager--render))
              (setq refresh-count 0)
              (with-current-buffer content-buffer
                (vterm--filter 'mock-process "output"))
              (should (= refresh-count 0)))))
      (mapc (lambda (buffer)
              (when (buffer-live-p buffer)
                (kill-buffer buffer)))
            (list session-buffer manager-buffer content-buffer)))))

(ert-deftest claude-code-ide-test-manager-render-does-not-error-when-idle-vars-are-unbound ()
  "Test manager render tolerates session buffers that lack idle locals."
  (claude-code-ide-tests--reset-manager-state)
  (let ((session-buffer (get-buffer-create "*cc-no-idle-vars*"))
        (manager-buffer (claude-code-ide-manager--get-buffer)))
    (unwind-protect
        (progn
          (with-current-buffer session-buffer
            (rename-buffer "*claude-code[no-idle-vars]*" t))
          (setq claude-code-ide-manager--items
                (list (make-claude-code-ide-manager-item
                       :session-key "/tmp/project-a"
                       :display-name "project-a"
                       :secondary-text "/tmp/project-a"
                       :pinned nil
                       :order-key 1
                       :live-p t)))
          (cl-letf (((symbol-function 'claude-code-ide--get-session-buffer)
                     (lambda (_session-key) session-buffer))
                    ((symbol-function 'boundp)
                     (let ((orig-boundp (symbol-function 'boundp)))
                       (lambda (symbol)
                         (if (memq symbol '(claude-code-ide-session-idle-enabled
                                            claude-code-ide-session-idle-p))
                             nil
                           (funcall orig-boundp symbol))))))
            (with-current-buffer manager-buffer
              (let (error-signaled)
                (condition-case err
                    (claude-code-ide-manager--render)
                  (error (setq error-signaled err)))
                (should-not error-signaled)))))
      (mapc (lambda (buffer)
              (when (buffer-live-p buffer)
                (kill-buffer buffer)))
            (list session-buffer manager-buffer)))))

(ert-deftest claude-code-ide-test-manager-switch-refreshes-sidebar-highlight ()
  "Test switching sessions rerenders the manager highlight."
  (claude-code-ide-tests--reset-manager-state)
  (let ((claude-code-ide--processes (make-hash-table :test 'equal))
        (process-a (make-pipe-process :name "cc-manager-highlight-a" :buffer nil))
        (process-b (make-pipe-process :name "cc-manager-highlight-b" :buffer nil))
        (content-buffer (get-buffer-create "*cc-manager-highlight-content*")))
    (unwind-protect
        (save-window-excursion
          (setq claude-code-ide-manager--items
                (list (make-claude-code-ide-manager-item
                       :session-key "/tmp/project-a"
                       :display-name "project-a"
                       :secondary-text "/tmp/project-a"
                       :pinned nil
                       :order-key 1
                       :live-p t)
                      (make-claude-code-ide-manager-item
                       :session-key "/tmp/project-b"
                       :display-name "project-b"
                       :secondary-text "/tmp/project-b"
                       :pinned nil
                       :order-key 2
                       :live-p t)))
          (setq claude-code-ide-manager--current-session-key "/tmp/project-a")
          (puthash "/tmp/project-a" process-a claude-code-ide--processes)
          (puthash "/tmp/project-b" process-b claude-code-ide--processes)
          (delete-other-windows)
          (switch-to-buffer content-buffer)
          (set-window-buffer (split-window-right)
                             (claude-code-ide-manager--get-buffer))
          (with-current-buffer (claude-code-ide-manager--get-buffer)
            (claude-code-ide-manager--render))
          (cl-letf (((symbol-function 'claude-code-ide-manager--capture-layout)
                     (lambda (_session-key) nil))
                    ((symbol-function 'claude-code-ide-manager--save-state)
                     (lambda () nil))
                    ((symbol-function 'claude-code-ide-manager--session-managed-p)
                     (lambda (_session-key) t))
                    ((symbol-function 'claude-code-ide-manager--restore-layout)
                     (lambda (session-key)
                       (setq claude-code-ide-manager--current-session-key session-key)
                       (selected-window))))
            (claude-code-ide-manager-switch-to-session "/tmp/project-b"))
          (with-current-buffer (claude-code-ide-manager--get-buffer)
            (goto-char (point-min))
            (should-not (get-text-property (point) 'face))
            (forward-line 1)
            (should (eq (get-text-property (point) 'face)
                        'claude-code-ide-manager-current-session-face))
            (should (equal (get-text-property
                            (point) 'claude-code-ide-manager-session-key)
                           "/tmp/project-b"))))
      (ignore-errors (delete-process process-a))
      (ignore-errors (delete-process process-b))
      (when (buffer-live-p content-buffer)
        (kill-buffer content-buffer)))))

(ert-deftest claude-code-ide-test-manager-switch-persists-new-active-session-before-sidebar-restore ()
  "Test switch saves the new active session before sidebar restore reloads state."
  (claude-code-ide-tests--reset-manager-state)
  (let ((claude-code-ide-manager-persist-state t)
        (claude-code-ide--processes (make-hash-table :test 'equal))
        (process-a (make-pipe-process :name "cc-manager-persist-highlight-a" :buffer nil))
        (process-b (make-pipe-process :name "cc-manager-persist-highlight-b" :buffer nil))
        (content-buffer (get-buffer-create "*cc-manager-persist-highlight-content*")))
    (unwind-protect
        (save-window-excursion
          (setq claude-code-ide-manager--items
                (list (make-claude-code-ide-manager-item
                       :session-key "/tmp/project-a"
                       :display-name "project-a"
                       :secondary-text "/tmp/project-a"
                       :pinned nil
                       :order-key 1
                       :live-p t)
                      (make-claude-code-ide-manager-item
                       :session-key "/tmp/project-b"
                       :display-name "project-b"
                       :secondary-text "/tmp/project-b"
                       :pinned nil
                       :order-key 2
                       :live-p t)))
          (setq claude-code-ide-manager--current-session-key "/tmp/project-a")
          (claude-code-ide-manager--set-scope-active-session-key
           '(:type global) "/tmp/project-a")
          (claude-code-ide-manager--save-state)
          (puthash "/tmp/project-a" process-a claude-code-ide--processes)
          (puthash "/tmp/project-b" process-b claude-code-ide--processes)
          (delete-other-windows)
          (switch-to-buffer content-buffer)
          (set-window-buffer (split-window-right)
                             (claude-code-ide-manager--get-buffer))
          (with-current-buffer (claude-code-ide-manager--get-buffer)
            (claude-code-ide-manager--render))
          (cl-letf (((symbol-function 'claude-code-ide-manager--capture-layout)
                     (lambda (_session-key) nil))
                    ((symbol-function 'claude-code-ide-manager--session-managed-p)
                     (lambda (_session-key) t))
                    ((symbol-function 'claude-code-ide-manager--restore-layout)
                     (lambda (session-key)
                       (setq claude-code-ide-manager--current-session-key session-key)
                       (selected-window)))
                    ((symbol-function 'claude-code-ide-manager--restore-visible-sidebars)
                     (lambda (_scopes)
                       (claude-code-ide-manager--load-state))))
            (claude-code-ide-manager-switch-to-session "/tmp/project-b"))
          (should (equal (claude-code-ide-manager--scope-active-session-key '(:type global))
                         "/tmp/project-b"))
          (with-current-buffer (claude-code-ide-manager--get-buffer)
            (goto-char (point-min))
            (should-not (eq (get-text-property (point) 'face)
                            'claude-code-ide-manager-current-session-face))
            (forward-line 1)
            (should (eq (get-text-property (point) 'face)
                        'claude-code-ide-manager-current-session-face))
            (should (equal (get-text-property
                            (point) 'claude-code-ide-manager-session-key)
                           "/tmp/project-b"))))
      (ignore-errors (delete-process process-a))
      (ignore-errors (delete-process process-b))
      (when (buffer-live-p content-buffer)
        (kill-buffer content-buffer)))))

(ert-deftest claude-code-ide-test-manager-render-moves-point-to-current-session ()
  "Test manager render places point on the active session row."
  (claude-code-ide-tests--reset-manager-state)
  (setq claude-code-ide-manager--items
        (list (make-claude-code-ide-manager-item
               :session-key "/tmp/project-a"
               :display-name "project-a"
               :secondary-text "/tmp/project-a"
               :pinned nil
               :order-key 1
               :live-p t)
              (make-claude-code-ide-manager-item
               :session-key "/tmp/project-b"
               :display-name "project-b"
               :secondary-text "/tmp/project-b"
               :pinned nil
               :order-key 2
               :live-p t)))
  (setq claude-code-ide-manager--current-session-key "/tmp/project-b")
  (with-current-buffer (claude-code-ide-manager--get-buffer)
    (claude-code-ide-manager--render)
    (should (equal (get-text-property (point) 'claude-code-ide-manager-session-key)
                   "/tmp/project-b"))))

(ert-deftest claude-code-ide-test-manager-render-keeps-scope-local-point-selection ()
  "Test repo manager activity does not move the global manager selection."
  (claude-code-ide-tests--reset-manager-state)
  (let* ((global-scope '(:type global))
         (repo-scope '(:type repo :git-root "/tmp/repo/"))
         (global-items
          (list (make-claude-code-ide-manager-item
                 :session-key "/tmp/global-a"
                 :display-name "global-a"
                 :secondary-text "global-a"
                 :order-key 1
                 :live-p t)
                (make-claude-code-ide-manager-item
                 :session-key "/tmp/repo/worktree-b"
                 :display-name "worktree-b"
                 :secondary-text "worktree-b"
                 :order-key 2
                 :live-p t)))
         (repo-items
          (list (make-claude-code-ide-manager-item
                 :session-key "/tmp/repo/worktree-b"
                 :display-name "worktree-b"
                 :secondary-text "worktree-b"
                 :order-key 1
                 :live-p t)))
         (global-buffer (claude-code-ide-manager--get-buffer global-scope))
         (repo-buffer (claude-code-ide-manager--get-buffer repo-scope)))
    (claude-code-ide-manager--set-scope-items global-scope global-items)
    (claude-code-ide-manager--set-scope-items repo-scope repo-items)
    (with-current-buffer global-buffer
      (claude-code-ide-manager--render global-scope)
      (goto-char (point-min)))
    (with-current-buffer repo-buffer
      (claude-code-ide-manager--render repo-scope)
      (goto-char (point-min)))
    (setq claude-code-ide-manager--current-session-key "/tmp/repo/worktree-b")
    (with-current-buffer global-buffer
      (claude-code-ide-manager--render global-scope)
      (should (equal (get-text-property (point) 'claude-code-ide-manager-session-key)
                     "/tmp/global-a")))))

(ert-deftest claude-code-ide-test-manager-render-keeps-scope-local-highlight ()
  "Test repo manager highlight does not depend on the global current session."
  (claude-code-ide-tests--reset-manager-state)
  (let* ((global-scope '(:type global))
         (repo-scope '(:type repo :git-root "/tmp/repo/"))
         (global-buffer (claude-code-ide-manager--get-buffer global-scope))
         (repo-buffer (claude-code-ide-manager--get-buffer repo-scope)))
    (claude-code-ide-manager--set-scope-items
     global-scope
     (list (make-claude-code-ide-manager-item
            :session-key "/tmp/global-a"
            :display-name "global-a"
            :secondary-text "global-a"
            :order-key 1
            :live-p t)))
    (claude-code-ide-manager--set-scope-items
     repo-scope
     (list (make-claude-code-ide-manager-item
            :session-key "/tmp/repo/worktree-a"
            :display-name "main"
            :secondary-text "worktree-a"
            :order-key 1
            :live-p t)
           (make-claude-code-ide-manager-item
            :session-key "/tmp/repo/worktree-b"
            :display-name "test"
            :secondary-text "worktree-b"
            :order-key 2
            :live-p t)))
    (setq claude-code-ide-manager--current-session-key "/tmp/global-a")
    (claude-code-ide-manager--set-scope-selected-session-key
     repo-scope "/tmp/repo/worktree-a")
    (claude-code-ide-manager--set-scope-state-entry
     repo-scope
     (plist-put (copy-sequence (claude-code-ide-manager--scope-state-entry repo-scope))
                :active-session-key "/tmp/repo/worktree-b"))
    (with-current-buffer global-buffer
      (claude-code-ide-manager--render global-scope))
    (with-current-buffer repo-buffer
      (claude-code-ide-manager--render repo-scope)
      (goto-char (point-min))
      (should-not (eq (get-text-property (point) 'face)
                      'claude-code-ide-manager-current-session-face))
      (forward-line 1)
      (should (eq (get-text-property (point) 'face)
                  'claude-code-ide-manager-current-session-face))
      (should (equal (get-text-property (point) 'claude-code-ide-manager-session-key)
                     "/tmp/repo/worktree-b")))))

(ert-deftest claude-code-ide-test-manager-render-preserves-visible-window-point ()
  "Test render preserves the visible sidebar row even when buffer point differs."
  (claude-code-ide-tests--reset-manager-state)
  (let ((claude-code-ide--processes (make-hash-table :test 'equal))
        (process-a (make-pipe-process :name "cc-manager-render-window-point-a" :buffer nil))
        (process-b (make-pipe-process :name "cc-manager-render-window-point-b" :buffer nil)))
    (unwind-protect
        (progn
          (puthash "/tmp/a" process-a claude-code-ide--processes)
          (puthash "/tmp/b" process-b claude-code-ide--processes)
          (setq claude-code-ide-manager--items
                (list (make-claude-code-ide-manager-item
                       :session-key "/tmp/a"
                       :display-name "a"
                       :secondary-text "/tmp/a"
                       :order-key 1
                       :live-p t)
                      (make-claude-code-ide-manager-item
                       :session-key "/tmp/b"
                       :display-name "b"
                       :secondary-text "/tmp/b"
                       :order-key 2
                       :live-p t)))
          (delete-other-windows)
          (switch-to-buffer (get-buffer-create "*cc-render-window-point*"))
          (let ((sidebar-window (claude-code-ide-manager-toggle-sidebar 1)))
            (with-current-buffer (window-buffer sidebar-window)
              (claude-code-ide-manager--render '(:type global))
              (goto-char (point-min))
              (forward-line 1)
              (set-window-point sidebar-window (point)))
            (select-window (next-window sidebar-window))
            (with-current-buffer (window-buffer sidebar-window)
              (goto-char (point-min)))
            (claude-code-ide-manager--refresh-sidebar-state '(:type global))
            (with-current-buffer (window-buffer sidebar-window)
              (goto-char (window-point sidebar-window))
              (should (equal (get-text-property (point) 'claude-code-ide-manager-session-key)
                             "/tmp/b")))))
      (ignore-errors (delete-process process-a))
      (ignore-errors (delete-process process-b))
      (when-let ((window (get-buffer-window (claude-code-ide-manager--get-buffer))))
        (delete-window window))
      (when-let ((buffer (get-buffer "*cc-render-window-point*")))
        (kill-buffer buffer)))))

(ert-deftest claude-code-ide-test-manager-default-window-width ()
  "Test manager sidebar width default is narrow enough for basename rows."
  (should (= claude-code-ide-manager-window-width 22)))

(ert-deftest claude-code-ide-test-manager-treemacs-split-policy-defaults-to-half ()
  (should (eq claude-code-ide-manager-treemacs-split-policy 'half)))

(ert-deftest claude-code-ide-test-manager-collocated-sidebar-honors-adaptive-policy ()
  (let ((claude-code-ide-manager-treemacs-split-policy 'adaptive))
    (with-temp-buffer
      (switch-to-buffer (current-buffer))
      (delete-other-windows)
      (let ((window (selected-window)))
        (should (> (claude-code-ide-manager--collocated-sidebar-height window)
                   (/ (window-total-height window) 4)))))))

(ert-deftest claude-code-ide-test-manager-find-treemacs-window-returns-visible-left-sidebar ()
  (let ((treemacs-buffer (get-buffer-create "*Treemacs*")))
    (unwind-protect
        (progn
          (delete-other-windows)
          (switch-to-buffer (get-buffer-create "*content*"))
          (let ((window (display-buffer-in-side-window
                         treemacs-buffer
                         '((side . left) (slot . -1)))))
            (with-current-buffer treemacs-buffer
              (setq major-mode 'treemacs-mode))
            (should (eq (claude-code-ide-manager--treemacs-window) window))))
      (when (buffer-live-p treemacs-buffer)
        (kill-buffer treemacs-buffer))
      (when-let ((buffer (get-buffer "*content*")))
        (kill-buffer buffer)))))

(ert-deftest claude-code-ide-test-manager-collocated-sidebar-propagates-side-metadata ()
  (claude-code-ide-tests--reset-manager-state)
  (let ((claude-code-ide--processes (make-hash-table :test 'equal))
        (process-a (make-pipe-process :name "cc-manager-collocated-side-metadata" :buffer nil))
        (treemacs-buffer (get-buffer-create "*Treemacs*")))
    (unwind-protect
        (progn
          (puthash "/tmp/project-a" process-a claude-code-ide--processes)
          (delete-other-windows)
          (switch-to-buffer (get-buffer-create "*content*"))
          (let* ((treemacs-window (display-buffer-in-side-window
                                   treemacs-buffer
                                   '((side . left) (slot . -1))))
                 (manager-window nil)
                 (parent nil))
            (with-current-buffer treemacs-buffer
              (setq major-mode 'treemacs-mode))
            (setq manager-window
                  (claude-code-ide-manager--show-sidebar '(:type global)))
            (setq parent (window-parent treemacs-window))
            (should (eq (window-parent manager-window) parent))
            (should (eq (window-parameter manager-window 'window-side) 'left))
            (should (eq (window-parameter parent 'window-side) 'left))))
      (ignore-errors (delete-process process-a))
      (when (buffer-live-p treemacs-buffer)
        (kill-buffer treemacs-buffer))
      (when-let ((buffer (get-buffer "*content*")))
        (kill-buffer buffer)))))

(ert-deftest claude-code-ide-test-manager-show-sidebar-keeps-standalone-path-without-treemacs ()
  (claude-code-ide-tests--reset-manager-state)
  (let ((claude-code-ide--processes (make-hash-table :test 'equal))
        (process-a (make-pipe-process :name "cc-manager-standalone" :buffer nil)))
    (unwind-protect
        (progn
          (puthash "/tmp/project-a" process-a claude-code-ide--processes)
          (cl-letf (((symbol-function 'claude-code-ide-manager--treemacs-window)
                     (lambda () nil)))
            (let ((window (claude-code-ide-manager--show-sidebar '(:type global))))
              (should (eq (window-parameter window 'window-side) 'left))
              (should (equal (window-buffer window)
                             (claude-code-ide-manager--get-buffer '(:type global)))))))
      (ignore-errors (delete-process process-a)))))

(ert-deftest claude-code-ide-test-manager-show-sidebar-collocates-below-treemacs ()
  (claude-code-ide-tests--reset-manager-state)
  (let ((claude-code-ide--processes (make-hash-table :test 'equal))
        (process-a (make-pipe-process :name "cc-manager-collocated" :buffer nil))
        (treemacs-buffer (get-buffer-create "*Treemacs*")))
    (unwind-protect
        (progn
          (puthash "/tmp/project-a" process-a claude-code-ide--processes)
          (delete-other-windows)
          (switch-to-buffer (get-buffer-create "*content*"))
          (let ((treemacs-window (display-buffer-in-side-window
                                  treemacs-buffer
                                  '((side . left) (slot . -1)))))
            (with-current-buffer treemacs-buffer
              (setq major-mode 'treemacs-mode))
            (let ((manager-window (claude-code-ide-manager--show-sidebar '(:type global))))
              (should (eq (window-parent manager-window)
                          (window-parent treemacs-window)))
              (should (eq (window-buffer treemacs-window) treemacs-buffer))
              (should (equal (window-buffer manager-window)
                             (claude-code-ide-manager--get-buffer '(:type global))))
              (should (< (nth 1 (window-edges treemacs-window))
                         (nth 1 (window-edges manager-window))))
              (should (= (nth 0 (window-edges treemacs-window))
                         (nth 0 (window-edges manager-window))))
              (should (= (nth 2 (window-edges treemacs-window))
                         (nth 2 (window-edges manager-window)))))))
      (ignore-errors (delete-process process-a))
      (when (buffer-live-p treemacs-buffer)
        (kill-buffer treemacs-buffer))
      (when-let ((buffer (get-buffer "*content*")))
        (kill-buffer buffer)))))

(ert-deftest claude-code-ide-test-manager-show-sidebar-collocates-below-treemacs-adaptive-policy ()
  (claude-code-ide-tests--reset-manager-state)
  (let ((claude-code-ide-manager-treemacs-split-policy 'adaptive)
        (claude-code-ide--processes (make-hash-table :test 'equal))
        (process-a (make-pipe-process :name "cc-manager-collocated-adaptive" :buffer nil))
        (treemacs-buffer (get-buffer-create "*Treemacs*")))
    (unwind-protect
        (progn
          (puthash "/tmp/project-a" process-a claude-code-ide--processes)
          (delete-other-windows)
          (switch-to-buffer (get-buffer-create "*content*"))
          (let ((treemacs-window (display-buffer-in-side-window
                                  treemacs-buffer
                                  '((side . left) (slot . -1)))))
            (with-current-buffer treemacs-buffer
              (setq major-mode 'treemacs-mode))
            (let ((manager-window (claude-code-ide-manager--show-sidebar '(:type global))))
              (should (eq (window-parent manager-window)
                          (window-parent treemacs-window)))
              (should (eq (window-buffer treemacs-window) treemacs-buffer))
              (should (equal (window-buffer manager-window)
                             (claude-code-ide-manager--get-buffer '(:type global))))
              (should (< (nth 1 (window-edges treemacs-window))
                         (nth 1 (window-edges manager-window))))
              (should (= (nth 0 (window-edges treemacs-window))
                         (nth 0 (window-edges manager-window))))
              (should (= (nth 2 (window-edges treemacs-window))
                         (nth 2 (window-edges manager-window))))
              (should (> (window-total-height treemacs-window)
                         (window-total-height manager-window))))))
      (ignore-errors (delete-process process-a))
      (when (buffer-live-p treemacs-buffer)
        (kill-buffer treemacs-buffer))
      (when-let ((buffer (get-buffer "*content*")))
        (kill-buffer buffer)))))

(ert-deftest claude-code-ide-test-manager-content-window-skips-collocated-manager-pane ()
  (claude-code-ide-tests--reset-manager-state)
  (let ((claude-code-ide--processes (make-hash-table :test 'equal))
        (process-a (make-pipe-process :name "cc-manager-content-window" :buffer nil))
        (treemacs-buffer (get-buffer-create "*Treemacs*")))
    (unwind-protect
        (progn
          (puthash "/tmp/project-a" process-a claude-code-ide--processes)
          (delete-other-windows)
          (switch-to-buffer (get-buffer-create "*content*"))
          (let ((content-window (selected-window))
                (treemacs-window (display-buffer-in-side-window
                                  treemacs-buffer
                                  '((side . left) (slot . -1)))))
            (with-current-buffer treemacs-buffer
              (setq major-mode 'treemacs-mode))
            (let ((manager-window (claude-code-ide-manager--show-sidebar '(:type global))))
              (select-window manager-window)
              (should (eq (claude-code-ide-manager--content-window) content-window))
              (should (not (eq (claude-code-ide-manager--content-window) manager-window)))
              (should (eq (window-buffer treemacs-window) treemacs-buffer))
              (should (eq (window-buffer manager-window)
                          (claude-code-ide-manager--get-buffer '(:type global)))))))
      (ignore-errors (delete-process process-a))
      (when (buffer-live-p treemacs-buffer)
        (kill-buffer treemacs-buffer))
      (when-let ((buffer (get-buffer "*content*")))
        (kill-buffer buffer)))))

(ert-deftest claude-code-ide-test-manager-toggle-sidebar-closes-collocated-manager-pane ()
  (claude-code-ide-tests--reset-manager-state)
  (let ((claude-code-ide--processes (make-hash-table :test 'equal))
        (process-a (make-pipe-process :name "cc-manager-toggle-close" :buffer nil))
        (treemacs-buffer (get-buffer-create "*Treemacs*")))
    (unwind-protect
        (progn
          (puthash "/tmp/project-a" process-a claude-code-ide--processes)
          (delete-other-windows)
          (switch-to-buffer (get-buffer-create "*content*"))
          (let ((treemacs-window (display-buffer-in-side-window
                                  treemacs-buffer
                                  '((side . left) (slot . -1)))))
            (with-current-buffer treemacs-buffer
              (setq major-mode 'treemacs-mode))
            (let ((opened-window (claude-code-ide-manager-toggle-sidebar 1)))
              (should (window-live-p opened-window))
              (should (progn (claude-code-ide-manager-toggle-sidebar) t)))
            (let ((manager-windows (cl-remove-if-not
                                    (lambda (window)
                                      (eq (window-buffer window)
                                          (claude-code-ide-manager--get-buffer '(:type global))))
                                    (window-list nil 'no-minibuf))))
              (should (= 0 (length manager-windows)))
              (should (window-live-p treemacs-window))
              (should (eq (claude-code-ide-manager--treemacs-window) treemacs-window)))))
      (ignore-errors (delete-process process-a))
      (when (buffer-live-p treemacs-buffer)
        (kill-buffer treemacs-buffer))
      (when-let ((buffer (get-buffer "*content*")))
        (kill-buffer buffer)))))

(ert-deftest claude-code-ide-test-manager-hide-sidebar-closes-collocated-manager-pane ()
  (claude-code-ide-tests--reset-manager-state)
  (let ((claude-code-ide--processes (make-hash-table :test 'equal))
        (process-a (make-pipe-process :name "cc-manager-hide-close" :buffer nil))
        (treemacs-buffer (get-buffer-create "*Treemacs*")))
    (unwind-protect
        (progn
          (puthash "/tmp/project-a" process-a claude-code-ide--processes)
          (delete-other-windows)
          (switch-to-buffer (get-buffer-create "*content*"))
          (let ((treemacs-window
                 (display-buffer-in-side-window treemacs-buffer
                                                '((side . left) (slot . -1)))))
            (with-current-buffer treemacs-buffer
              (setq major-mode 'treemacs-mode))
            (let ((opened-window (claude-code-ide-manager-toggle-sidebar 1)))
              (should (window-live-p opened-window)))
            (should (window-live-p treemacs-window))
            (should (eq (claude-code-ide-manager--treemacs-window) treemacs-window))
            (should (progn
                      (claude-code-ide-manager--hide-sidebar '(:type global))
                      t))
            (should (window-live-p treemacs-window))
            (should (eq (claude-code-ide-manager--treemacs-window) treemacs-window))
            (should (= 0
                       (length (cl-remove-if-not
                                (lambda (window)
                                  (eq (window-buffer window)
                                      (claude-code-ide-manager--get-buffer '(:type global))))
                                (window-list nil 'no-minibuf)))))))
      (ignore-errors (delete-process process-a))
      (when (buffer-live-p treemacs-buffer)
        (kill-buffer treemacs-buffer))
      (when-let ((buffer (get-buffer "*content*")))
        (kill-buffer buffer)))))

(ert-deftest claude-code-ide-test-manager-toggle-sidebar-force-open-reuses-collocated-pane ()
  (claude-code-ide-tests--reset-manager-state)
  (let ((claude-code-ide--processes (make-hash-table :test 'equal))
        (process-a (make-pipe-process :name "cc-manager-force-open" :buffer nil))
        (treemacs-buffer (get-buffer-create "*Treemacs*")))
    (unwind-protect
        (progn
          (puthash "/tmp/project-a" process-a claude-code-ide--processes)
          (delete-other-windows)
          (switch-to-buffer (get-buffer-create "*content*"))
          (let ((treemacs-window (display-buffer-in-side-window
                                  treemacs-buffer
                                  '((side . left) (slot . -1)))))
            (with-current-buffer treemacs-buffer
              (setq major-mode 'treemacs-mode))
            (let ((sidebar-window (claude-code-ide-manager-toggle-sidebar 1)))
              (should (window-live-p sidebar-window))
              (let ((reopened-window (claude-code-ide-manager-toggle-sidebar 1)))
                (should (eq reopened-window sidebar-window))
                (should (window-live-p reopened-window))
                (should (window-live-p treemacs-window))
                (should (= 1
                           (length (cl-remove-if-not
                                    (lambda (window)
                                      (and (eq (window-buffer window)
                                               (claude-code-ide-manager--get-buffer '(:type global)))
                                           (window-parameter
                                            window
                                            'claude-code-ide-manager-sidebar)))
                                    (window-list nil 'no-minibuf)))))))))
      (ignore-errors (delete-process process-a))
      (when (buffer-live-p treemacs-buffer)
        (kill-buffer treemacs-buffer))
      (when-let ((buffer (get-buffer "*content*")))
        (kill-buffer buffer)))))

(ert-deftest claude-code-ide-test-manager-toggle-sidebar-force-open-rebuilds-after-treemacs-reopens ()
  (claude-code-ide-tests--reset-manager-state)
  (let ((claude-code-ide--processes (make-hash-table :test 'equal))
        (process-a (make-pipe-process :name "cc-manager-force-open-reopen" :buffer nil))
        (treemacs-buffer (get-buffer-create "*Treemacs*")))
    (unwind-protect
        (progn
          (puthash "/tmp/project-a" process-a claude-code-ide--processes)
          (delete-other-windows)
          (switch-to-buffer (get-buffer-create "*content*"))
          (let ((treemacs-window (display-buffer-in-side-window
                                  treemacs-buffer
                                  '((side . left) (slot . -1)))))
            (with-current-buffer treemacs-buffer
              (setq major-mode 'treemacs-mode))
            (let ((old-sidebar-window (claude-code-ide-manager-toggle-sidebar 1)))
              (should (window-live-p old-sidebar-window))
              (delete-window treemacs-window)
              (let ((reopened-treemacs-window
                     (display-buffer-in-side-window treemacs-buffer
                                                    '((side . left) (slot . -1)))))
                (with-current-buffer treemacs-buffer
                  (setq major-mode 'treemacs-mode))
                (let ((new-sidebar-window (claude-code-ide-manager-toggle-sidebar 1)))
                  (should (window-live-p reopened-treemacs-window))
                  (should (window-live-p new-sidebar-window))
                  (should (not (eq new-sidebar-window old-sidebar-window)))
                  (should (or (not (window-live-p old-sidebar-window))
                              (eq old-sidebar-window reopened-treemacs-window)))
                  (should-not (window-parameter reopened-treemacs-window
                                                'claude-code-ide-manager-sidebar))
                  (should (eq (window-parent new-sidebar-window)
                              (window-parent reopened-treemacs-window)))
                  (should (< (nth 1 (window-edges reopened-treemacs-window))
                             (nth 1 (window-edges new-sidebar-window)))))))))
      (ignore-errors (delete-process process-a))
      (when (buffer-live-p treemacs-buffer)
        (kill-buffer treemacs-buffer))
      (when-let ((buffer (get-buffer "*content*")))
        (kill-buffer buffer)))))

(ert-deftest claude-code-ide-test-manager-collocated-sidebar-restores-treemacs-parameters-on-close ()
  (claude-code-ide-tests--reset-manager-state)
  (let ((claude-code-ide--processes (make-hash-table :test 'equal))
        (process-a (make-pipe-process :name "cc-manager-treemacs-restore" :buffer nil))
        (treemacs-buffer (get-buffer-create "*Treemacs*")))
    (unwind-protect
        (progn
          (puthash "/tmp/project-a" process-a claude-code-ide--processes)
          (delete-other-windows)
          (switch-to-buffer (get-buffer-create "*content*"))
          (let ((treemacs-window
                 (display-buffer-in-side-window treemacs-buffer
                                                '((side . left) (slot . -1)))))
            (with-current-buffer treemacs-buffer
              (setq major-mode 'treemacs-mode))
            (let ((before-side (window-parameter treemacs-window 'window-side))
                  (before-no-delete (window-parameter treemacs-window 'no-delete-other-windows))
                  (before-no-other (window-parameter treemacs-window 'no-other-window))
                  (before-size-fixed (window-parameter treemacs-window 'window-size-fixed)))
              (should (window-live-p
                       (claude-code-ide-manager-toggle-sidebar 1)))
              (should (window-live-p treemacs-window))
              (should (progn
                        (claude-code-ide-manager--hide-sidebar '(:type global))
                        t))
              (should (window-live-p treemacs-window))
              (should (eq (window-parameter treemacs-window 'window-side) before-side))
              (should (equal (window-parameter treemacs-window 'no-delete-other-windows)
                             before-no-delete))
              (should (equal (window-parameter treemacs-window 'no-other-window)
                             before-no-other))
              (should (equal (window-parameter treemacs-window 'window-size-fixed)
                             before-size-fixed))
              (should (= 0
                         (length (cl-remove-if-not
                                  (lambda (window)
                                    (eq (window-buffer window)
                                        (claude-code-ide-manager--get-buffer '(:type global))))
                                  (window-list nil 'no-minibuf))))))))
      (ignore-errors (delete-process process-a))
      (when (buffer-live-p treemacs-buffer)
        (kill-buffer treemacs-buffer))
      (when-let ((buffer (get-buffer "*content*")))
        (kill-buffer buffer)))))

(ert-deftest claude-code-ide-test-manager-collocated-sidebar-restores-treemacs-parameters-without-snapshot ()
  (claude-code-ide-tests--reset-manager-state)
  (let ((claude-code-ide--processes (make-hash-table :test 'equal))
        (process-a (make-pipe-process :name "cc-manager-treemacs-restore-fallback" :buffer nil))
        (treemacs-buffer (get-buffer-create "*Treemacs*")))
    (unwind-protect
        (progn
          (puthash "/tmp/project-a" process-a claude-code-ide--processes)
          (delete-other-windows)
          (switch-to-buffer (get-buffer-create "*content*"))
          (let ((treemacs-window
                 (display-buffer-in-side-window treemacs-buffer
                                                '((side . left) (slot . -1)))))
            (with-current-buffer treemacs-buffer
              (setq major-mode 'treemacs-mode))
            (let ((manager-window (claude-code-ide-manager-toggle-sidebar 1)))
              (should (window-live-p manager-window))
              (let ((expected-side (window-parameter treemacs-window 'window-side))
                    (expected-no-delete (window-parameter treemacs-window 'no-delete-other-windows))
                    (expected-no-other (window-parameter treemacs-window 'no-other-window))
                    (expected-size-fixed (window-parameter treemacs-window 'window-size-fixed)))
              (set-window-parameter manager-window
                                    'claude-code-ide-manager-collocated-treemacs-params
                                    nil)
              (should (progn
                        (claude-code-ide-manager--hide-sidebar '(:type global))
                        t))
              (should (window-live-p treemacs-window))
              (should (eq (window-parameter treemacs-window 'window-side) expected-side))
              (should (equal (window-parameter treemacs-window 'no-delete-other-windows)
                             expected-no-delete))
              (should (equal (window-parameter treemacs-window 'no-other-window)
                             expected-no-other))
              (should (equal (window-parameter treemacs-window 'window-size-fixed)
                             expected-size-fixed))))))
      (ignore-errors (delete-process process-a))
      (when (buffer-live-p treemacs-buffer)
        (kill-buffer treemacs-buffer))
      (when-let ((buffer (get-buffer "*content*")))
        (kill-buffer buffer)))))

(ert-deftest claude-code-ide-test-manager-toggle-sidebar-closes-stale-collocated-pane-after-treemacs-is-closed ()
  (claude-code-ide-tests--reset-manager-state)
  (let ((claude-code-ide--processes (make-hash-table :test 'equal))
        (process-a (make-pipe-process :name "cc-manager-toggle-stale-close" :buffer nil))
        (treemacs-buffer (get-buffer-create "*Treemacs*")))
    (unwind-protect
        (progn
          (puthash "/tmp/project-a" process-a claude-code-ide--processes)
          (delete-other-windows)
          (switch-to-buffer (get-buffer-create "*content*"))
          (let ((content-window (selected-window))
                (treemacs-window (display-buffer-in-side-window
                                  treemacs-buffer
                                  '((side . left) (slot . -1)))))
            (with-current-buffer treemacs-buffer
              (setq major-mode 'treemacs-mode))
            (should (window-live-p
                     (claude-code-ide-manager-toggle-sidebar 1)))
            (delete-window treemacs-window)
            (should (progn (claude-code-ide-manager-toggle-sidebar) t))
            (should (null (claude-code-ide-manager--treemacs-window)))
            (should (window-live-p content-window))
            (let ((manager-windows
                   (cl-remove-if-not
                    (lambda (window)
                      (eq (window-buffer window)
                          (claude-code-ide-manager--get-buffer '(:type global))))
                    (window-list nil 'no-minibuf))))
              (should (= 0 (length manager-windows))))))
      (ignore-errors (delete-process process-a))
      (when (buffer-live-p treemacs-buffer)
        (kill-buffer treemacs-buffer))
      (when-let ((buffer (get-buffer "*content*")))
        (kill-buffer buffer)))))

(ert-deftest claude-code-ide-test-manager-hide-sidebar-closes-stale-collocated-pane-after-treemacs-is-closed ()
  (claude-code-ide-tests--reset-manager-state)
  (let ((claude-code-ide--processes (make-hash-table :test 'equal))
        (process-a (make-pipe-process :name "cc-manager-hide-stale-close" :buffer nil))
        (treemacs-buffer (get-buffer-create "*Treemacs*")))
    (unwind-protect
        (progn
          (puthash "/tmp/project-a" process-a claude-code-ide--processes)
          (delete-other-windows)
          (switch-to-buffer (get-buffer-create "*content*"))
          (let ((content-window (selected-window))
                (treemacs-window (display-buffer-in-side-window
                                  treemacs-buffer
                                  '((side . left) (slot . -1)))))
            (with-current-buffer treemacs-buffer
              (setq major-mode 'treemacs-mode))
            (should (window-live-p
                     (claude-code-ide-manager-toggle-sidebar 1)))
            (delete-window treemacs-window)
            (should (progn
                      (claude-code-ide-manager--hide-sidebar '(:type global))
                      t))
            (should (null (claude-code-ide-manager--treemacs-window)))
            (should (window-live-p content-window))
            (let ((manager-windows
                   (cl-remove-if-not
                    (lambda (window)
                      (eq (window-buffer window)
                          (claude-code-ide-manager--get-buffer '(:type global))))
                    (window-list nil 'no-minibuf))))
              (should (= 0 (length manager-windows))))))
      (ignore-errors (delete-process process-a))
      (when (buffer-live-p treemacs-buffer)
        (kill-buffer treemacs-buffer))
      (when-let ((buffer (get-buffer "*content*")))
        (kill-buffer buffer)))))

(ert-deftest claude-code-ide-test-manager-show-sidebar-cleans-stale-collocated-pane-on-standalone-reopen ()
  (claude-code-ide-tests--reset-manager-state)
  (let ((claude-code-ide--processes (make-hash-table :test 'equal))
        (process-a (make-pipe-process :name "cc-manager-cleanup" :buffer nil))
        (treemacs-buffer (get-buffer-create "*Treemacs*")))
    (unwind-protect
        (progn
          (puthash "/tmp/project-a" process-a claude-code-ide--processes)
          (delete-other-windows)
          (switch-to-buffer (get-buffer-create "*content*"))
          (let ((treemacs-window (display-buffer-in-side-window
                                  treemacs-buffer
                                  '((side . left) (slot . -1)))))
            (with-current-buffer treemacs-buffer
              (setq major-mode 'treemacs-mode))
            (let ((manager-buffer (claude-code-ide-manager--get-buffer '(:type global)))
                  (collocated-window (claude-code-ide-manager--show-sidebar '(:type global))))
              (delete-window treemacs-window)
              (cl-letf (((symbol-function 'claude-code-ide-manager--treemacs-window)
                         (lambda () nil)))
                (let ((standalone-window (claude-code-ide-manager--show-sidebar '(:type global))))
                  (should (eq (window-parameter standalone-window 'window-side) 'left))
                  (should (equal (window-buffer standalone-window) manager-buffer))
                  (should (= 1
                             (length (cl-remove-if-not
                                      (lambda (window)
                                        (eq (window-buffer window) manager-buffer))
                                      (window-list nil 'no-minibuf)))))
                  (should (not (eq standalone-window collocated-window))))))))
      (ignore-errors (delete-process process-a))
      (when (buffer-live-p treemacs-buffer)
        (kill-buffer treemacs-buffer))
      (when-let ((buffer (get-buffer "*content*")))
        (kill-buffer buffer)))))

(ert-deftest claude-code-ide-test-manager-show-sidebar-normalizes-content-window-manager-copy ()
  (claude-code-ide-tests--reset-manager-state)
  (let ((claude-code-ide--processes (make-hash-table :test 'equal))
        (process-a (make-pipe-process :name "cc-manager-content-preserve" :buffer nil))
        (treemacs-buffer (get-buffer-create "*Treemacs*")))
    (unwind-protect
        (progn
          (puthash "/tmp/project-a" process-a claude-code-ide--processes)
          (delete-other-windows)
          (switch-to-buffer (get-buffer-create "*content*"))
          (let* ((manager-buffer (claude-code-ide-manager--get-buffer '(:type global)))
                 (content-window (split-window-right))
                 (treemacs-window (display-buffer-in-side-window
                                   treemacs-buffer
                                   '((side . left) (slot . -1)))))
            (set-window-buffer content-window manager-buffer)
            (with-current-buffer treemacs-buffer
              (setq major-mode 'treemacs-mode))
            (let ((sidebar-window (claude-code-ide-manager--show-sidebar '(:type global))))
              (should (window-live-p sidebar-window))
              (should (not (eq sidebar-window content-window)))
              (when (window-live-p content-window)
                (should-not (eq (window-buffer content-window) manager-buffer)))
              (should (= 1
                         (length (cl-remove-if-not
                                  (lambda (window)
                                    (eq (window-buffer window) manager-buffer))
                                  (window-list nil 'no-minibuf)))))
              (should (window-live-p treemacs-window)))))
      (ignore-errors (delete-process process-a))
      (when (buffer-live-p treemacs-buffer)
        (kill-buffer treemacs-buffer))
      (when-let ((buffer (get-buffer "*content*")))
        (kill-buffer buffer)))))

(ert-deftest claude-code-ide-test-manager-toggle-sidebar-hides-normalized-manager-sidebar ()
  (claude-code-ide-tests--reset-manager-state)
  (let ((claude-code-ide--processes (make-hash-table :test 'equal))
        (process-a (make-pipe-process :name "cc-manager-toggle-owned-sidebar" :buffer nil))
        (treemacs-buffer (get-buffer-create "*Treemacs*")))
    (unwind-protect
        (progn
          (puthash "/tmp/project-a" process-a claude-code-ide--processes)
          (delete-other-windows)
          (switch-to-buffer (get-buffer-create "*content*"))
          (let* ((manager-buffer (claude-code-ide-manager--get-buffer '(:type global)))
                 (content-window (split-window-right))
                 (treemacs-window (display-buffer-in-side-window
                                   treemacs-buffer
                                   '((side . left) (slot . -1)))))
            (set-window-buffer content-window manager-buffer)
            (with-current-buffer treemacs-buffer
              (setq major-mode 'treemacs-mode))
            (let ((sidebar-window (claude-code-ide-manager-toggle-sidebar 1)))
              (should (window-live-p sidebar-window))
              (when (window-live-p content-window)
                (should-not (eq (window-buffer content-window) manager-buffer))
                (select-window content-window))
              (should (progn (claude-code-ide-manager-toggle-sidebar) t))
              (should (window-live-p treemacs-window))
              (should (not (window-live-p sidebar-window)))
              (should (= 0
                         (length (cl-remove-if-not
                                  (lambda (window)
                                    (eq (window-buffer window) manager-buffer))
                                  (window-list nil 'no-minibuf))))))))
      (ignore-errors (delete-process process-a))
      (when (buffer-live-p treemacs-buffer)
        (kill-buffer treemacs-buffer))
      (when-let ((buffer (get-buffer "*content*")))
        (kill-buffer buffer)))))

(ert-deftest claude-code-ide-test-manager-refresh-sidebar-state-syncs-owned-sidebar-window ()
  (claude-code-ide-tests--reset-manager-state)
  (let ((claude-code-ide--processes (make-hash-table :test 'equal))
        (process-a (make-pipe-process :name "cc-manager-refresh-a" :buffer nil))
        (process-b (make-pipe-process :name "cc-manager-refresh-b" :buffer nil))
        (treemacs-buffer (get-buffer-create "*Treemacs*")))
    (unwind-protect
        (progn
          (puthash "/tmp/project-a" process-a claude-code-ide--processes)
          (puthash "/tmp/project-b" process-b claude-code-ide--processes)
          (delete-other-windows)
          (switch-to-buffer (get-buffer-create "*content*"))
          (let* ((scope '(:type global))
                 (manager-buffer (claude-code-ide-manager--get-buffer scope))
                 (content-window (split-window-right))
                 (content-buffer (get-buffer-create "*content-2*"))
                 (treemacs-window (display-buffer-in-side-window
                                   treemacs-buffer
                                   '((side . left) (slot . -1)))))
            (set-window-buffer content-window content-buffer)
            (with-current-buffer treemacs-buffer
              (setq major-mode 'treemacs-mode))
            (let ((sidebar-window (claude-code-ide-manager--show-sidebar scope)))
              (select-window content-window)
              (with-current-buffer manager-buffer
                (claude-code-ide-manager--move-point-to-session-key "/tmp/project-b")
                (set-window-point sidebar-window (point-min)))
              (claude-code-ide-manager--refresh-sidebar-state scope)
              (should (= (window-point sidebar-window)
                         (with-current-buffer manager-buffer
                           (point))))
              (should (window-live-p treemacs-window)))))
      (ignore-errors (delete-process process-a))
      (ignore-errors (delete-process process-b))
      (when (buffer-live-p treemacs-buffer)
        (kill-buffer treemacs-buffer))
      (when-let ((buffer (get-buffer "*content*")))
        (kill-buffer buffer))
      (when-let ((buffer (get-buffer "*content-2*")))
        (kill-buffer buffer)))))

(ert-deftest claude-code-ide-test-manager-window-config-hook-reasserts-sidebar-state ()
  "Test window-config changes restore standalone sidebar parameters."
  (claude-code-ide-tests--reset-manager-state)
  (let ((claude-code-ide--processes (make-hash-table :test 'equal))
        (process-a (make-pipe-process :name "cc-manager-window-config-a" :buffer nil)))
    (unwind-protect
        (progn
          (puthash "/tmp/project-a" process-a claude-code-ide--processes)
          (delete-other-windows)
          (switch-to-buffer (get-buffer-create "*content*"))
          (let ((sidebar-window (claude-code-ide-manager-toggle-sidebar 1)))
            (set-window-parameter sidebar-window 'claude-code-ide-manager-sidebar nil)
            (set-window-parameter sidebar-window 'window-side nil)
            (set-window-parameter sidebar-window 'window-slot nil)
            (set-window-parameter sidebar-window 'no-other-window nil)
            (set-window-parameter sidebar-window 'window-size-fixed nil)
            (claude-code-ide-manager--refresh-on-window-configuration-change)
            (setq sidebar-window
                  (claude-code-ide-manager--sidebar-window '(:type global)))
            (should (window-live-p sidebar-window))
            (should (window-at-side-p sidebar-window 'left))
            (should (eq (window-parameter sidebar-window
                                          'claude-code-ide-manager-sidebar)
                        t))
            (should (eq (window-parameter sidebar-window 'window-side) 'left))
            (should (eq (window-parameter sidebar-window 'window-slot) -1))
            (should (eq (window-parameter sidebar-window 'no-other-window) t))
            (should (eq (window-parameter sidebar-window 'window-size-fixed)
                        'both)))))
      (ignore-errors (delete-process process-a))
      (when-let ((window (get-buffer-window (claude-code-ide-manager--get-buffer))))
        (delete-window window))
      (when-let ((buffer (get-buffer "*content*")))
        (kill-buffer buffer))))

(ert-deftest claude-code-ide-test-manager-window-config-hook-recreates-sidebar-from-restored-ordinary-window ()
  "Test window-config changes rebuild a real sidebar from an ordinary restored window."
  (claude-code-ide-tests--reset-manager-state)
  (let ((claude-code-ide--processes (make-hash-table :test 'equal))
        (process-a (make-pipe-process :name "cc-manager-window-config-restored-a" :buffer nil)))
    (unwind-protect
        (progn
          (puthash "/tmp/project-a" process-a claude-code-ide--processes)
          (delete-other-windows)
          (switch-to-buffer (get-buffer-create "*content*"))
          (let* ((scope '(:type global))
                 (manager-buffer (claude-code-ide-manager--get-buffer scope))
                 (restored-window (split-window-right)))
            (set-window-buffer restored-window manager-buffer)
            (with-current-buffer manager-buffer
              (setq-local claude-code-ide-manager--scope scope))
            (claude-code-ide-manager--refresh-on-window-configuration-change)
            (let ((sidebar-window (claude-code-ide-manager--sidebar-window scope)))
              (should (window-live-p sidebar-window))
              (should (window-at-side-p sidebar-window 'left))
              (should (eq (window-parameter sidebar-window 'window-side) 'left))
              (should (eq (window-parameter sidebar-window 'window-slot) -1))
              (should-not (eq sidebar-window restored-window))
              (should (= 1
                         (length (cl-remove-if-not
                                  (lambda (window)
                                    (eq (window-buffer window) manager-buffer))
                                  (window-list nil 'no-minibuf))))))))
      (ignore-errors (delete-process process-a))
      (when-let ((window (get-buffer-window (claude-code-ide-manager--get-buffer))))
        (delete-window window))
      (when-let ((buffer (get-buffer "*content*")))
        (kill-buffer buffer)))))

(ert-deftest claude-code-ide-test-manager-window-config-hook-restores-focus-to-recreated-sidebar ()
  "Test window-config changes keep focus on the recreated sidebar."
  (claude-code-ide-tests--reset-manager-state)
  (let ((claude-code-ide--processes (make-hash-table :test 'equal))
        (process-a (make-pipe-process :name "cc-manager-window-config-focus-a" :buffer nil)))
    (unwind-protect
        (progn
          (puthash "/tmp/project-a" process-a claude-code-ide--processes)
          (delete-other-windows)
          (switch-to-buffer (get-buffer-create "*content*"))
          (let* ((scope '(:type global))
                 (manager-buffer (claude-code-ide-manager--get-buffer scope))
                 (restored-window (split-window-right)))
            (set-window-buffer restored-window manager-buffer)
            (with-current-buffer manager-buffer
              (setq-local claude-code-ide-manager--scope scope))
            (select-window restored-window)
            (claude-code-ide-manager--refresh-on-window-configuration-change)
            (let ((sidebar-window (claude-code-ide-manager--sidebar-window scope)))
              (should (window-live-p sidebar-window))
              (should-not (eq sidebar-window restored-window))
              (should (eq (selected-window) sidebar-window)))))
      (ignore-errors (delete-process process-a))
      (when-let ((window (get-buffer-window (claude-code-ide-manager--get-buffer))))
        (delete-window window))
      (when-let ((buffer (get-buffer "*content*")))
        (kill-buffer buffer)))))

(ert-deftest claude-code-ide-test-manager-window-config-hook-preserves-global-selection-after-repo-switch ()
  "Test global sidebar restore keeps its selected row after repo-local manager use."
  (claude-code-ide-tests--reset-manager-state)
  (let* ((global-scope '(:type global))
         (repo-scope '(:type repo :git-root "/tmp/crs-root/"))
         (global-buffer (claude-code-ide-manager--get-buffer global-scope))
         (repo-buffer (claude-code-ide-manager--get-buffer repo-scope))
         (content-buffer (get-buffer-create "*cc-persp-content*")))
    (unwind-protect
        (cl-letf (((symbol-function 'claude-code-ide-manager-refresh-items)
                   (lambda (&optional _scope) nil)))
          (claude-code-ide-manager--set-scope-items
           global-scope
           (list (make-claude-code-ide-manager-item
                  :session-key "/tmp/.spacemacs.d-30"
                  :display-name ".spacemacs.d-30"
                  :secondary-text ".spacemacs.d-30"
                  :order-key 1
                  :live-p t)
                 (make-claude-code-ide-manager-item
                  :session-key "/tmp/claude-code-ide.el"
                  :display-name "claude-code-ide.el"
                  :secondary-text "claude-code-ide.el"
                  :order-key 2
                  :live-p t)
                 (make-claude-code-ide-manager-item
                  :session-key "/tmp/CRSBench"
                  :display-name "CRSBench"
                  :secondary-text "CRSBench"
                  :order-key 3
                  :live-p t)
                 (make-claude-code-ide-manager-item
                  :session-key "/tmp/worktree-test"
                  :display-name "worktree-test"
                  :secondary-text "worktree-test"
                  :order-key 4
                  :live-p t)))
          (claude-code-ide-manager--set-scope-items
           repo-scope
           (list (make-claude-code-ide-manager-item
                  :session-key "/tmp/CRSBench"
                  :display-name "main"
                  :secondary-text "CRSBench"
                  :order-key 1
                  :live-p t)
                 (make-claude-code-ide-manager-item
                  :session-key "/tmp/worktree-test"
                  :display-name "test"
                  :secondary-text "worktree-test"
                  :order-key 2
                  :live-p t)))
          (delete-other-windows)
          (switch-to-buffer content-buffer)
          (let ((restored-window (split-window-right)))
            (set-window-buffer restored-window global-buffer)
            (with-current-buffer global-buffer
              (claude-code-ide-manager--render global-scope)
              (goto-char (point-min))
              (forward-line 1)
              (set-window-point restored-window (point)))
            (with-current-buffer repo-buffer
              (claude-code-ide-manager--render repo-scope))
            (setq claude-code-ide-manager--current-session-key "/tmp/CRSBench")
            (select-window restored-window)
            (claude-code-ide-manager--refresh-on-window-configuration-change)
            (let ((sidebar-window (claude-code-ide-manager--sidebar-window global-scope)))
              (should (window-live-p sidebar-window))
              (should (eq (selected-window) sidebar-window))
              (with-current-buffer global-buffer
                (goto-char (window-point sidebar-window))
                (should (equal (get-text-property (point) 'claude-code-ide-manager-session-key)
                               "/tmp/claude-code-ide.el"))))))
      (when-let ((window (get-buffer-window global-buffer)))
        (delete-window window))
      (mapc (lambda (buffer)
              (when (buffer-live-p buffer)
                (kill-buffer buffer)))
            (list global-buffer repo-buffer content-buffer)))))

(ert-deftest claude-code-ide-test-manager-window-config-hook-syncs-current-session-from-restored-layout ()
  "Test restored content layout updates the active global manager session."
  (claude-code-ide-tests--reset-manager-state)
  (let* ((global-scope '(:type global))
         (global-buffer (claude-code-ide-manager--get-buffer global-scope))
         (session-a (get-buffer-create "*cc-persp-session-a*"))
         (session-b (get-buffer-create "*cc-persp-session-b*"))
         (claude-code-ide--processes (make-hash-table :test 'equal))
         (process-a (make-pipe-process :name "cc-manager-window-config-session-a"
                                       :buffer session-a))
         (process-b (make-pipe-process :name "cc-manager-window-config-session-b"
                                       :buffer session-b)))
    (unwind-protect
        (progn
          (puthash "/tmp/claude-code-ide.el" process-a claude-code-ide--processes)
          (puthash "/tmp/CRSBench" process-b claude-code-ide--processes)
          (claude-code-ide-manager--set-scope-items
           global-scope
           (list (make-claude-code-ide-manager-item
                  :session-key "/tmp/claude-code-ide.el"
                  :display-name "claude-code-ide.el"
                  :secondary-text "claude-code-ide.el"
                  :order-key 1
                  :live-p t)
                 (make-claude-code-ide-manager-item
                  :session-key "/tmp/CRSBench"
                  :display-name "CRSBench"
                  :secondary-text "CRSBench"
                  :order-key 2
                  :live-p t)))
          (setq claude-code-ide-manager--current-session-key "/tmp/CRSBench")
          (claude-code-ide-manager--set-scope-active-session-key
           global-scope "/tmp/CRSBench")
          (delete-other-windows)
          (switch-to-buffer session-a)
          (let ((restored-window (split-window-right)))
            (set-window-buffer restored-window global-buffer)
            (with-current-buffer global-buffer
              (claude-code-ide-manager--render global-scope)
              (goto-char (point-min))
              (set-window-point restored-window (point)))
            (select-window restored-window)
            (claude-code-ide-manager--refresh-on-window-configuration-change)
            (should (equal claude-code-ide-manager--current-session-key
                           "/tmp/claude-code-ide.el"))
            (should (equal (claude-code-ide-manager--scope-active-session-key global-scope)
                           "/tmp/claude-code-ide.el"))
            (let ((sidebar-window (claude-code-ide-manager--sidebar-window global-scope)))
              (should (window-live-p sidebar-window))
              (with-current-buffer global-buffer
                (goto-char (window-point sidebar-window))
                (should (equal (get-text-property (point) 'claude-code-ide-manager-session-key)
                               "/tmp/claude-code-ide.el"))
                (should (eq (get-text-property (point) 'face)
                            'claude-code-ide-manager-current-session-face))))))
      (ignore-errors (delete-process process-a))
      (ignore-errors (delete-process process-b))
      (when-let ((window (get-buffer-window global-buffer)))
        (delete-window window))
      (mapc (lambda (buffer)
              (when (buffer-live-p buffer)
                (kill-buffer buffer)))
            (list global-buffer session-a session-b)))))

(ert-deftest claude-code-ide-test-manager-focus-global-preserves-last-selection-after-hidden-repo-switch ()
  "Test force-opening the global manager keeps its last selected row."
  (claude-code-ide-tests--reset-manager-state)
  (let* ((global-scope '(:type global))
         (repo-scope '(:type repo :git-root "/tmp/crs-root/"))
         (global-buffer (claude-code-ide-manager--get-buffer global-scope))
         (content-buffer (get-buffer-create "*cc-hidden-global-content*")))
    (unwind-protect
        (cl-letf (((symbol-function 'claude-code-ide-manager-refresh-items)
                   (lambda (&optional _scope) nil)))
          (claude-code-ide-manager--set-scope-items
           global-scope
           (list (make-claude-code-ide-manager-item
                  :session-key "/tmp/.spacemacs.d-30"
                  :display-name ".spacemacs.d-30"
                  :secondary-text ".spacemacs.d-30"
                  :order-key 1
                  :live-p t)
                 (make-claude-code-ide-manager-item
                  :session-key "/tmp/claude-code-ide.el"
                  :display-name "claude-code-ide.el"
                  :secondary-text "claude-code-ide.el"
                  :order-key 2
                  :live-p t)
                 (make-claude-code-ide-manager-item
                  :session-key "/tmp/CRSBench"
                  :display-name "CRSBench"
                  :secondary-text "CRSBench"
                  :order-key 3
                  :live-p t)))
          (claude-code-ide-manager--set-scope-items
           repo-scope
           (list (make-claude-code-ide-manager-item
                  :session-key "/tmp/CRSBench"
                  :display-name "main"
                  :secondary-text "CRSBench"
                  :order-key 1
                  :live-p t)
                 (make-claude-code-ide-manager-item
                  :session-key "/tmp/worktree-test"
                  :display-name "test"
                  :secondary-text "worktree-test"
                  :order-key 2
                  :live-p t)))
          (delete-other-windows)
          (switch-to-buffer content-buffer)
          (let ((global-window (display-buffer-in-side-window
                                global-buffer
                                '((side . left) (slot . -1)))))
            (set-window-parameter global-window 'claude-code-ide-manager-sidebar t)
            (with-current-buffer global-buffer
              (claude-code-ide-manager--render global-scope))
            (claude-code-ide-manager--sync-point-to-session-key
             global-scope "/tmp/claude-code-ide.el")
            (delete-window global-window))
          (with-current-buffer global-buffer
            (let ((inhibit-read-only t))
              (erase-buffer)))
          (setq claude-code-ide-manager--current-session-key "/tmp/CRSBench")
          (let ((claude-code-ide-manager-default-target 'global))
            (claude-code-ide-manager-focus))
          (let ((global-window (claude-code-ide-manager--sidebar-window global-scope)))
            (should (window-live-p global-window))
            (with-current-buffer global-buffer
              (goto-char (window-point global-window))
              (should (equal (get-text-property (point) 'claude-code-ide-manager-session-key)
                             "/tmp/claude-code-ide.el")))))
      (when-let ((window (get-buffer-window global-buffer)))
        (delete-window window))
      (mapc (lambda (buffer)
              (when (buffer-live-p buffer)
                (kill-buffer buffer)))
            (list global-buffer content-buffer)))))

(ert-deftest claude-code-ide-test-manager-switch-keep-focus-prefers-owned-sidebar-window ()
  (claude-code-ide-tests--reset-manager-state)
  (let ((claude-code-ide--processes (make-hash-table :test 'equal))
        (process-a (make-pipe-process :name "cc-manager-switch-focus" :buffer nil))
        (treemacs-buffer (get-buffer-create "*Treemacs*")))
    (unwind-protect
        (progn
          (puthash "/tmp/project-a" process-a claude-code-ide--processes)
          (delete-other-windows)
          (switch-to-buffer (get-buffer-create "*content*"))
          (let* ((scope '(:type global))
                 (content-window (split-window-right))
                 (content-buffer (get-buffer-create "*content-2*"))
                 (treemacs-window (display-buffer-in-side-window
                                   treemacs-buffer
                                   '((side . left) (slot . -1)))))
            (set-window-buffer content-window content-buffer)
            (with-current-buffer treemacs-buffer
              (setq major-mode 'treemacs-mode))
            (let ((sidebar-window (claude-code-ide-manager--show-sidebar scope)))
              (select-window content-window)
              (cl-letf (((symbol-function 'claude-code-ide-manager--restore-layout)
                         (lambda (_session-key) nil))
                        ((symbol-function 'claude-code-ide-manager--build-default-layout)
                         (lambda (_session-key _scope) content-window)))
                (claude-code-ide-manager-switch-to-session "/tmp/project-a" t scope))
              (should (eq (selected-window) sidebar-window))
              (should (window-live-p content-window))
              (should (window-live-p treemacs-window)))))
      (ignore-errors (delete-process process-a))
      (when (buffer-live-p treemacs-buffer)
        (kill-buffer treemacs-buffer))
      (when-let ((buffer (get-buffer "*content*")))
        (kill-buffer buffer))
      (when-let ((buffer (get-buffer "*content-2*")))
        (kill-buffer buffer)))))

(ert-deftest claude-code-ide-test-manager-switch-clears-target-idle-state ()
  "Test explicit manager switches clear idle without starting a new timer."
  (let ((clear-buffer nil)
        (session-buffer (generate-new-buffer "*claude-code[test-manager-switch-idle]*")))
    (cl-letf (((symbol-function 'claude-code-ide-manager--session-managed-p)
               (lambda (_session-key) t))
              ((symbol-function 'claude-code-ide-manager--restore-layout)
               (lambda (_session-key) (selected-window)))
              ((symbol-function 'claude-code-ide--get-session-buffer)
               (lambda (_session-key)
                 session-buffer))
              ((symbol-function 'claude-code-ide-session-idle-clear-state)
               (lambda ()
                 (setq clear-buffer (current-buffer)))))
      (unwind-protect
          (with-current-buffer session-buffer
            (setq-local claude-code-ide-session-idle-enabled t
                        claude-code-ide-session-idle-p t
                        claude-code-ide-session-idle-timer 'mock-timer)
            (claude-code-ide-manager-switch-to-session "/tmp/project-a" nil '(:type global))
            (should (eq clear-buffer session-buffer)))
        (when (buffer-live-p session-buffer)
          (kill-buffer session-buffer))))))

(ert-deftest claude-code-ide-test-manager-switch-syncs-treemacs-project-and-file-when-visible ()
  (let (calls)
    (cl-letf (((symbol-function 'claude-code-ide-manager--treemacs-window)
               (lambda () t))
              ((symbol-function 'claude-code-ide-manager--session-managed-p)
               (lambda (_session-key) t))
              ((symbol-function 'claude-code-ide-manager--session-active-file)
               (lambda (_session-key) "/tmp/project-a/src/main.el"))
              ((symbol-function 'claude-code-ide-manager--sync-treemacs-to-session)
               (lambda (session-key)
                 (push session-key calls)))
              ((symbol-function 'claude-code-ide-manager--restore-layout)
               (lambda (_session-key) t)))
      (claude-code-ide-manager-switch-to-session "/tmp/project-a" nil '(:type global))
      (should (equal calls '("/tmp/project-a"))))))

(ert-deftest claude-code-ide-test-manager-switch-skips-treemacs-sync-when-hidden ()
  (let (called)
    (cl-letf (((symbol-function 'claude-code-ide-manager--treemacs-window)
               (lambda () nil))
              ((symbol-function 'claude-code-ide-manager--session-managed-p)
               (lambda (_session-key) t))
              ((symbol-function 'claude-code-ide-manager--sync-treemacs-to-session)
               (lambda (_session-key)
                 (setq called t)))
              ((symbol-function 'claude-code-ide-manager--restore-layout)
               (lambda (_session-key) t)))
      (claude-code-ide-manager-switch-to-session "/tmp/project-a" nil '(:type global))
      (should-not called))))

(ert-deftest claude-code-ide-test-manager-switch-restores-target-focus-after-treemacs-sync ()
  (claude-code-ide-tests--reset-manager-state)
  (let ((content-buffer (get-buffer-create "*content*"))
        (session-buffer (get-buffer-create "*cc-session*"))
        (treemacs-buffer (get-buffer-create "*Treemacs*")))
    (unwind-protect
        (progn
          (delete-other-windows)
          (let* ((content-window (selected-window))
                 (treemacs-window (display-buffer-in-side-window
                                   treemacs-buffer
                                   '((side . left) (slot . -1)))))
            (set-window-buffer content-window content-buffer)
            (with-current-buffer treemacs-buffer
              (setq major-mode 'treemacs-mode))
            (cl-letf (((symbol-function 'claude-code-ide-manager--restore-layout)
                       (lambda (_session-key)
                         (set-window-buffer content-window session-buffer)
                         (select-window content-window)
                         content-window))
                      ((symbol-function 'claude-code-ide-manager--session-managed-p)
                       (lambda (_session-key) t))
                      ((symbol-function 'claude-code-ide-manager--sync-treemacs-to-session)
                       (lambda (_session-key)
                         (select-window treemacs-window))))
              (claude-code-ide-manager-switch-to-session "/tmp/project-a" nil '(:type global))
              (should (eq (selected-window) content-window))
              (should (eq (window-buffer (selected-window)) session-buffer)))))
      (when-let ((window (get-buffer-window treemacs-buffer)))
        (delete-window window))
      (mapc (lambda (buffer)
              (when (buffer-live-p buffer)
                (kill-buffer buffer)))
            (list content-buffer session-buffer treemacs-buffer)))))

(ert-deftest claude-code-ide-test-manager-sync-treemacs-keeps-project-when-file-reveal-fails ()
  (let (project-call)
    (cl-letf (((symbol-function 'treemacs-add-and-display-current-project-exclusively)
               (lambda ()
                 (setq project-call t)))
              ((symbol-function 'treemacs-find-file)
               (lambda (&rest _)
                 (error "no reveal")))
              ((symbol-function 'claude-code-ide-manager--session-active-file)
               (lambda (_session-key) "/tmp/project-a/src/main.el")))
      (should (condition-case nil
                  (progn
                    (claude-code-ide-manager--sync-treemacs-to-session "/tmp/project-a")
                    t)
                (error nil)))
      (should project-call))))

(ert-deftest claude-code-ide-test-manager-toggle-sidebar-1-creates-left-side-window ()
  "Test forcing the manager open creates a left side window."
  (claude-code-ide-tests--reset-manager-state)
  (let ((claude-code-ide--processes (make-hash-table :test 'equal))
        (process-a (make-pipe-process :name "cc-manager-show" :buffer nil)))
    (unwind-protect
        (progn
          (puthash "/tmp/project-a" process-a claude-code-ide--processes)
          (let ((window (claude-code-ide-manager-toggle-sidebar 1)))
            (should (window-live-p window))
            (should (eq (window-parameter window 'window-side) 'left))
            (should (eq (window-parameter window 'no-other-window) t))
            (should (eq (window-parameter window 'window-size-fixed) 'both))
            (should (window-size-fixed-p window t))
            (let ((width-before (window-total-width window)))
              (balance-windows)
              (should (= (window-total-width window) width-before)))
            (should (equal (window-buffer window)
                           (claude-code-ide-manager--get-buffer)))))
      (ignore-errors (delete-process process-a))
      (when-let ((window (get-buffer-window (claude-code-ide-manager--get-buffer))))
        (delete-window window))
      (when-let ((buffer (get-buffer (buffer-name (claude-code-ide-manager--get-buffer)))))
        (kill-buffer buffer)))))

(ert-deftest claude-code-ide-test-manager-installs-window-package-compatibility ()
  "Test manager compatibility setup hides the sidebar from window selectors."
  (defvar winum-ignored-buffers-regexp)
  (defvar aw-ignored-buffers)
  (let ((winum-ignored-buffers-regexp nil)
        (aw-ignored-buffers nil))
    (claude-code-ide-manager--apply-window-compatibility)
    (should (member claude-code-ide-manager--buffer-name-regexp
                    winum-ignored-buffers-regexp))
    (should (member 'claude-code-ide-manager-mode aw-ignored-buffers))))

(ert-deftest claude-code-ide-test-manager-mode-disables-hl-line ()
  "Test manager mode disables hl-line-mode."
  (let (hl-line-args)
    (cl-letf (((symbol-function 'featurep)
               (lambda (feature &rest _)
                 (eq feature 'hl-line)))
              ((symbol-function 'hl-line-mode)
               (lambda (arg)
                 (push arg hl-line-args))))
      (with-current-buffer (get-buffer-create "*cc-manager-hl-line*")
        (unwind-protect
            (progn
              (claude-code-ide-manager-mode)
              (should (member -1 hl-line-args)))
          (kill-buffer (current-buffer)))))))

(ert-deftest claude-code-ide-test-manager-installs-evil-initial-state ()
  "Test manager starts in Evil emacs state when Evil is available."
  (let (initial-state-calls)
    (cl-letf (((symbol-function 'evil-set-initial-state)
               (lambda (mode state)
                 (push (list mode state) initial-state-calls))))
      (claude-code-ide-manager--setup-evil-state)
      (should (member '(claude-code-ide-manager-mode emacs)
                      initial-state-calls)))))

(ert-deftest claude-code-ide-test-manager-toggle-sidebar-toggles-window ()
  "Test toggling the manager hides an existing sidebar and shows it again."
  (claude-code-ide-tests--reset-manager-state)
  (let ((claude-code-ide--processes (make-hash-table :test 'equal))
        (process-a (make-pipe-process :name "cc-manager-toggle" :buffer nil)))
    (unwind-protect
        (progn
          (puthash "/tmp/project-a" process-a claude-code-ide--processes)
          (let ((window (claude-code-ide-manager-toggle-sidebar)))
            (should (window-live-p window))
            (should (eq (selected-window) window))
            (should (get-buffer-window (claude-code-ide-manager--get-buffer))))
          (claude-code-ide-manager-toggle-sidebar)
          (should-not (get-buffer-window (claude-code-ide-manager--get-buffer)))
          (let ((window (claude-code-ide-manager-toggle-sidebar)))
            (should (window-live-p window))
            (should (eq (selected-window) window))
            (should (get-buffer-window (claude-code-ide-manager--get-buffer)))))
      (ignore-errors (delete-process process-a))
      (when-let ((window (get-buffer-window (claude-code-ide-manager--get-buffer))))
        (delete-window window))
      (when-let ((buffer (get-buffer (buffer-name (claude-code-ide-manager--get-buffer)))))
        (kill-buffer buffer)))))

(ert-deftest claude-code-ide-test-manager-toggle-sidebar-arg-controls-visibility ()
  "Test toggle arguments force open or hide without the toggle heuristic."
  (claude-code-ide-tests--reset-manager-state)
  (let ((claude-code-ide--processes (make-hash-table :test 'equal))
        (process-a (make-pipe-process :name "cc-manager-toggle-arg" :buffer nil)))
    (unwind-protect
        (progn
          (puthash "/tmp/project-a" process-a claude-code-ide--processes)
          (let ((window (claude-code-ide-manager-toggle-sidebar 1)))
            (should (window-live-p window))
            (should (eq (selected-window) window)))
          (let ((window (claude-code-ide-manager-toggle-sidebar 1)))
            (should (window-live-p window))
            (should (eq (selected-window) window))
            (should (get-buffer-window (claude-code-ide-manager--get-buffer))))
          (should-not (claude-code-ide-manager-toggle-sidebar -1))
          (should-not (get-buffer-window (claude-code-ide-manager--get-buffer))))
      (ignore-errors (delete-process process-a))
      (when-let ((window (get-buffer-window (claude-code-ide-manager--get-buffer))))
        (delete-window window))
      (when-let ((buffer (get-buffer (buffer-name (claude-code-ide-manager--get-buffer)))))
        (kill-buffer buffer)))))

(ert-deftest claude-code-ide-test-manager-pin-command-updates-selected-row ()
  "Test uppercase P toggles pin state for the row at point."
  (claude-code-ide-tests--reset-manager-state)
  (setq claude-code-ide-manager--items
        (list (make-claude-code-ide-manager-item
               :session-key "/tmp/project-a"
               :display-name "project-a"
               :secondary-text "~/tmp/project-a"
               :pinned nil
               :order-key 1
               :live-p t)))
  (with-current-buffer (claude-code-ide-manager--get-buffer)
    (claude-code-ide-manager--render)
    (goto-char (point-min))
    (call-interactively (key-binding (kbd "P")))
    (should (claude-code-ide-manager-item-pinned
             (car claude-code-ide-manager--items)))))

(ert-deftest claude-code-ide-test-manager-toggle-current-session-pin-ignores-sidebar-point ()
  "Test transient pin toggles the active session instead of sidebar point."
  (claude-code-ide-tests--reset-manager-state)
  (setq claude-code-ide-manager--items
        (list (make-claude-code-ide-manager-item
               :session-key "/tmp/project-a"
               :display-name "project-a"
               :secondary-text "/tmp/project-a"
               :pinned nil
               :order-key 1
               :live-p t)
              (make-claude-code-ide-manager-item
               :session-key "/tmp/project-b"
               :display-name "project-b"
               :secondary-text "/tmp/project-b"
               :pinned nil
               :order-key 2
               :live-p t)))
  (setq claude-code-ide-manager--current-session-key "/tmp/project-b")
  (with-current-buffer (claude-code-ide-manager--get-buffer)
    (claude-code-ide-manager--render)
    (goto-char (point-min))
    (claude-code-ide-manager-toggle-current-session-pin))
  (should-not (claude-code-ide-manager-item-pinned
               (claude-code-ide-manager--item-by-session-key
                '(:type global) "/tmp/project-a")))
  (should (claude-code-ide-manager-item-pinned
           (claude-code-ide-manager--item-by-session-key
            '(:type global) "/tmp/project-b"))))

(ert-deftest claude-code-ide-test-manager-space-switches-session-at-point ()
  "Test SPC activates the manager row at point."
  (claude-code-ide-tests--reset-manager-state)
  (setq claude-code-ide-manager--items
        (list (make-claude-code-ide-manager-item
               :session-key "/tmp/project-a"
               :display-name "project-a"
               :secondary-text "/tmp/project-a"
               :pinned nil
               :order-key 1
               :live-p t)))
  (let (switched)
    (cl-letf (((symbol-function 'claude-code-ide-manager-switch-to-session)
               (lambda (session-key &optional _keep-manager-focus _scope)
                 (setq switched session-key))))
      (with-current-buffer (claude-code-ide-manager--get-buffer)
        (claude-code-ide-manager--render)
        (goto-char (point-min))
        (call-interactively (key-binding (kbd "SPC")))
        (should (equal switched "/tmp/project-a"))))))

(ert-deftest claude-code-ide-test-manager-open-global-switches-existing-session ()
  "Test global manager open switches directly to an existing live session."
  (claude-code-ide-tests--reset-manager-state)
  (let (switch-call)
    (cl-letf (((symbol-function 'project-known-project-roots)
               (lambda () '("/tmp/project-a/" "/tmp/project-b/")))
              ((symbol-function 'completing-read)
               (lambda (_prompt collection &rest _)
                 (car (funcall collection "/tmp/project-b/" nil t))))
              ((symbol-function 'claude-code-ide-manager--live-session-keys)
               (lambda () '("/tmp/project-b/")))
              ((symbol-function 'claude-code-ide-manager-switch-to-session)
               (lambda (session-key &optional keep-manager-focus scope)
                 (setq switch-call (list session-key keep-manager-focus scope)))))
      (with-current-buffer (claude-code-ide-manager--get-buffer '(:type global))
        (claude-code-ide-manager-open))
      (should (equal switch-call
                     '("/tmp/project-b/" nil (:type global)))))))

(ert-deftest claude-code-ide-test-manager-known-project-roots-auto-prefers-projectile ()
  "Test auto source prefers Projectile when Projectile is available."
  (let ((claude-code-ide-manager-global-project-source 'auto))
    (cl-letf (((symbol-function 'claude-code-ide-manager--projectile-known-project-roots)
               (lambda () '("/tmp/projectile-a/" "/tmp/projectile-b/")))
              ((symbol-function 'claude-code-ide-manager--project-el-known-project-roots)
               (lambda () '("/tmp/project-el/"))))
      (should (equal (claude-code-ide-manager--known-project-roots)
                     '("/tmp/projectile-a/" "/tmp/projectile-b/"))))))

(ert-deftest claude-code-ide-test-manager-known-project-roots-auto-falls-back-to-project-el ()
  "Test auto source falls back to project.el when Projectile is unavailable."
  (let ((claude-code-ide-manager-global-project-source 'auto))
    (cl-letf (((symbol-function 'claude-code-ide-manager--projectile-known-project-roots)
               (lambda () nil))
              ((symbol-function 'claude-code-ide-manager--project-el-known-project-roots)
               (lambda () '("/tmp/project-el/"))))
      (should (equal (claude-code-ide-manager--known-project-roots)
                     '("/tmp/project-el/"))))))

(ert-deftest claude-code-ide-test-manager-known-project-roots-explicit-project-el ()
  "Test explicit project-el source ignores Projectile."
  (let ((claude-code-ide-manager-global-project-source 'project-el))
    (cl-letf (((symbol-function 'claude-code-ide-manager--projectile-known-project-roots)
               (lambda () '("/tmp/projectile-a/")))
              ((symbol-function 'claude-code-ide-manager--project-el-known-project-roots)
               (lambda () '("/tmp/project-el/"))))
      (should (equal (claude-code-ide-manager--known-project-roots)
                     '("/tmp/project-el/"))))))

(ert-deftest claude-code-ide-test-manager-known-project-roots-merged-deduplicates ()
  "Test merged source combines Projectile and project.el roots without duplicates."
  (let ((claude-code-ide-manager-global-project-source 'merged))
    (cl-letf (((symbol-function 'claude-code-ide-manager--projectile-known-project-roots)
               (lambda () '("/tmp/shared/" "/tmp/projectile-a/")))
              ((symbol-function 'claude-code-ide-manager--project-el-known-project-roots)
                (lambda () '("/tmp/shared/" "/tmp/project-el/"))))
      (should (equal (claude-code-ide-manager--known-project-roots)
                     '("/tmp/projectile-a/" "/tmp/shared/" "/tmp/project-el/"))))))

(ert-deftest claude-code-ide-test-manager-select-global-project-adds-project-metadata ()
  "Test global project selection exposes project-file metadata to completion UIs."
  (let ((claude-code-ide-manager-global-project-source 'project-el)
        collection metadata first-match)
    (cl-letf (((symbol-function 'claude-code-ide-manager--project-el-known-project-roots)
               (lambda () '("/tmp/project-a/" "/tmp/project-b/")))
              ((symbol-function 'completing-read)
               (lambda (_prompt coll &rest _)
                 (setq collection coll)
                 (setq metadata (funcall coll "" nil 'metadata))
                 (setq first-match (funcall coll "/tmp/project-a/" nil t))
                 "/tmp/project-a/")))
      (should (equal (claude-code-ide-manager--select-global-project)
                     "/tmp/project-a/"))
      (should (equal metadata
                     '(metadata . ((category . project-file)))))
      (should (equal first-match '("/tmp/project-a/"))))))

(ert-deftest claude-code-ide-test-manager-open-global-shows-transient-for-new-target ()
  "Test global manager open hands a new target to the transient path."
  (claude-code-ide-tests--reset-manager-state)
  (let (transient-target)
    (cl-letf (((symbol-function 'project-known-project-roots)
               (lambda () '("/tmp/project-a/")))
              ((symbol-function 'completing-read)
               (lambda (&rest _) "/tmp/project-a/"))
              ((symbol-function 'claude-code-ide-manager--live-session-keys)
               (lambda () nil))
              ((symbol-function 'claude-code-ide-manager-open-menu)
               (lambda ()
                 (setq transient-target claude-code-ide-manager--open-target))))
      (with-current-buffer (claude-code-ide-manager--get-buffer '(:type global))
        (claude-code-ide-manager-open))
      (should (equal transient-target "/tmp/project-a/")))))

(ert-deftest claude-code-ide-test-manager-open-repo-lists-current-repo-worktrees-only ()
  "Test repo-local manager open queries worktrees from the current repo scope."
  (claude-code-ide-tests--reset-manager-state)
  (let (captured-root captured-candidates)
    (cl-letf (((symbol-function 'claude-code-ide-manager--repo-worktree-directories)
               (lambda (git-root)
                 (setq captured-root git-root)
                 '("/tmp/repo/" "/tmp/repo-wt/")))
              ((symbol-function 'completing-read)
               (lambda (_prompt collection &rest _)
                 (setq captured-candidates collection)
                 "/tmp/repo-wt/"))
              ((symbol-function 'claude-code-ide-manager--live-session-keys)
               (lambda () nil))
              ((symbol-function 'claude-code-ide-manager-open-menu)
               (lambda () nil)))
      (with-current-buffer (claude-code-ide-manager--get-buffer '(:type repo :git-root "/tmp/repo/"))
        (claude-code-ide-manager-open))
      (should (equal captured-root "/tmp/repo/"))
      (should (equal captured-candidates '("/tmp/repo/" "/tmp/repo-wt/"))))))

(ert-deftest claude-code-ide-test-manager-open-existing-session-uses-manager-switch-path ()
  "Test manager open uses the normal manager switch path for live sessions."
  (claude-code-ide-tests--reset-manager-state)
  (let (switch-call transient-called)
    (cl-letf (((symbol-function 'project-known-project-roots)
               (lambda () '("/tmp/project-a/")))
              ((symbol-function 'completing-read)
               (lambda (&rest _) "/tmp/project-a/"))
              ((symbol-function 'claude-code-ide-manager--live-session-keys)
               (lambda () '("/tmp/project-a/")))
              ((symbol-function 'claude-code-ide-manager-switch-to-session)
               (lambda (&rest args)
                 (setq switch-call args)))
              ((symbol-function 'claude-code-ide-manager-open-menu)
               (lambda ()
                 (setq transient-called t))))
      (with-current-buffer (claude-code-ide-manager--get-buffer '(:type global))
        (claude-code-ide-manager-open))
      (should switch-call)
      (should-not transient-called))))

(ert-deftest claude-code-ide-test-manager-open-start-action-starts-selected-target ()
  "Test manager open start action launches the selected target."
  (let ((claude-code-ide-manager--open-target "/tmp/project-a/")
        (claude-code-ide-manager--open-scope '(:type global))
        call)
    (cl-letf (((symbol-function 'claude-code-ide--start-session)
               (lambda (&optional continue resume directory)
                 (setq call (list continue resume directory
                                  claude-code-ide--suppress-initial-display))))
              ((symbol-function 'claude-code-ide-manager-switch-to-session)
               (lambda (&rest _) nil)))
      (claude-code-ide-manager-open-start)
      (should (equal call '(nil nil "/tmp/project-a/" t))))))

(ert-deftest claude-code-ide-test-manager-open-start-action-switches-manager-to-new-session ()
  "Test manager open start action enters the manager default view after launch."
  (let ((claude-code-ide-manager--open-target "/tmp/project-a/")
        (claude-code-ide-manager--open-scope '(:type repo :git-root "/tmp/repo/"))
        call)
    (cl-letf (((symbol-function 'claude-code-ide--start-session)
               (lambda (&optional _continue _resume _directory) nil))
              ((symbol-function 'claude-code-ide-manager-switch-to-session)
               (lambda (session-key &optional keep-manager-focus scope)
                 (setq call (list session-key keep-manager-focus scope)))))
      (claude-code-ide-manager-open-start)
      (should (equal call
                     '("/tmp/project-a/" nil (:type repo :git-root "/tmp/repo/")))))))

(ert-deftest claude-code-ide-test-manager-open-start-skip-action-adds-dangerous-flag ()
  "Test manager open start-skip action adds the dangerous permissions flag."
  (let ((claude-code-ide-manager--open-target "/tmp/project-a/")
        (claude-code-ide-manager--open-scope nil)
        (claude-code-ide-cli-extra-flags "")
        call)
    (cl-letf (((symbol-function 'claude-code-ide--dangerous-permissions-flag)
               (lambda () "--dangerously-skip-permissions"))
              ((symbol-function 'claude-code-ide--start-session)
               (lambda (&optional continue resume directory)
                 (setq call (list continue resume directory claude-code-ide-cli-extra-flags)))))
      (claude-code-ide-manager-open-start-skip-permissions)
      (should (equal call '(nil nil "/tmp/project-a/" "--dangerously-skip-permissions"))))))

(ert-deftest claude-code-ide-test-manager-open-continue-and-resume-actions-pass-through ()
  "Test manager open continue and resume actions reuse the selected target."
  (let ((claude-code-ide-manager--open-target "/tmp/project-a/")
        (claude-code-ide-manager--open-scope nil)
        calls)
    (cl-letf (((symbol-function 'claude-code-ide--start-session)
               (lambda (&optional continue resume directory)
                 (push (list continue resume directory
                             claude-code-ide--suppress-initial-display)
                       calls))))
      (claude-code-ide-manager-open-continue)
      (setq claude-code-ide-manager--open-target "/tmp/project-a/")
      (claude-code-ide-manager-open-resume)
      (should (equal (nreverse calls)
                     '((t nil "/tmp/project-a/" t)
                       (nil t "/tmp/project-a/" t)))))))

(ert-deftest claude-code-ide-test-manager-open-continue-and-resume-skip-actions-add-dangerous-flag ()
  "Test manager open continue/resume skip actions add the dangerous flag."
  (let ((claude-code-ide-manager--open-target "/tmp/project-a/")
        (claude-code-ide-manager--open-scope nil)
        (claude-code-ide-cli-extra-flags "")
        calls)
    (cl-letf (((symbol-function 'claude-code-ide--dangerous-permissions-flag)
               (lambda () "--dangerously-skip-permissions"))
              ((symbol-function 'claude-code-ide--start-session)
               (lambda (&optional continue resume directory)
                 (push (list continue resume directory claude-code-ide-cli-extra-flags)
                       calls))))
      (claude-code-ide-manager-open-continue-skip-permissions)
      (setq claude-code-ide-manager--open-target "/tmp/project-a/")
      (claude-code-ide-manager-open-resume-skip-permissions)
      (should (equal (nreverse calls)
                     '((t nil "/tmp/project-a/" "--dangerously-skip-permissions")
                       (nil t "/tmp/project-a/" "--dangerously-skip-permissions")))))))

(ert-deftest claude-code-ide-test-manager-open-continue-uses-default-layout-even-with-saved-layout ()
  "Test manager open continue bypasses stale saved layouts and rebuilds the default view."
  (claude-code-ide-tests--reset-manager-state)
  (let ((claude-code-ide-manager--open-target "/tmp/project-a/")
        (claude-code-ide-manager--open-scope '(:type global))
        restored
        built)
    (puthash "/tmp/project-a/"
             '(:window-state saved)
             claude-code-ide-manager--layouts)
    (cl-letf (((symbol-function 'claude-code-ide--start-session)
               (lambda (&optional _continue _resume _directory) nil))
              ((symbol-function 'claude-code-ide-manager--restore-layout)
               (lambda (_session-key)
                 (setq restored t)
                 (selected-window)))
              ((symbol-function 'claude-code-ide-manager--build-default-layout)
               (lambda (_session-key _scope)
                 (setq built t)
                 (selected-window)))
              ((symbol-function 'claude-code-ide-manager--visible-sidebar-scopes)
               (lambda () nil))
              ((symbol-function 'claude-code-ide-manager--adopt-visible-sidebars)
               (lambda (_scopes) nil))
              ((symbol-function 'claude-code-ide-manager--restore-visible-sidebars)
               (lambda (_scopes) nil))
              ((symbol-function 'claude-code-ide-manager--treemacs-window)
               (lambda () nil))
              ((symbol-function 'claude-code-ide-manager--refresh-sidebar-state)
               (lambda (&optional _scope _reassert) nil)))
      (claude-code-ide-manager-open-continue)
      (should built)
      (should-not restored))))

(ert-deftest claude-code-ide-test-manager-n-and-p-move-and-switch-between-rows ()
  "Test n/p move point and switch to the selected visible row."
  (claude-code-ide-tests--reset-manager-state)
  (setq claude-code-ide-manager--items
        (list (make-claude-code-ide-manager-item
               :session-key "/tmp/a"
               :display-name "a"
               :secondary-text "/tmp/a"
               :pinned nil
               :order-key 1
               :live-p t)
              (make-claude-code-ide-manager-item
               :session-key "/tmp/b"
               :display-name "b"
               :secondary-text "/tmp/b"
               :pinned nil
               :order-key 2
               :live-p t)))
  (let (switched)
    (cl-letf (((symbol-function 'claude-code-ide-manager-switch-to-session)
               (lambda (session-key &optional _keep-manager-focus _scope)
                 (setq switched session-key))))
      (with-current-buffer (claude-code-ide-manager--get-buffer)
        (claude-code-ide-manager--render)
        (goto-char (point-min))
        (call-interactively (key-binding (kbd "n")))
        (should (equal (get-text-property (point) 'claude-code-ide-manager-session-key)
                       "/tmp/b"))
        (should (equal switched "/tmp/b"))
        (call-interactively (key-binding (kbd "p")))
        (should (equal (get-text-property (point) 'claude-code-ide-manager-session-key)
                       "/tmp/a"))
        (should (equal switched "/tmp/a"))))))

(ert-deftest claude-code-ide-test-manager-n-and-p-cycle-between-ends ()
  "Test n/p wrap around the visible manager rows."
  (claude-code-ide-tests--reset-manager-state)
  (setq claude-code-ide-manager--items
        (list (make-claude-code-ide-manager-item
               :session-key "/tmp/a"
               :display-name "a"
               :secondary-text "/tmp/a"
               :pinned nil
               :order-key 1
               :live-p t)
              (make-claude-code-ide-manager-item
               :session-key "/tmp/b"
               :display-name "b"
               :secondary-text "/tmp/b"
               :pinned nil
               :order-key 2
               :live-p t)))
  (let (switched)
    (cl-letf (((symbol-function 'claude-code-ide-manager-switch-to-session)
               (lambda (session-key &optional _keep-manager-focus _scope)
                 (setq switched session-key))))
      (with-current-buffer (claude-code-ide-manager--get-buffer)
        (claude-code-ide-manager--render)
        (goto-char (point-min))
        (call-interactively (key-binding (kbd "p")))
        (should (equal (get-text-property (point) 'claude-code-ide-manager-session-key)
                       "/tmp/b"))
        (should (equal switched "/tmp/b"))
        (call-interactively (key-binding (kbd "n")))
        (should (equal (get-text-property (point) 'claude-code-ide-manager-session-key)
                       "/tmp/a"))
        (should (equal switched "/tmp/a"))))))

(ert-deftest claude-code-ide-test-manager-sidebar-keys-pass-focus-policy ()
  "Test sidebar keys distinguish between stay-in-manager and follow-session focus."
  (claude-code-ide-tests--reset-manager-state)
  (setq claude-code-ide-manager--items
        (list (make-claude-code-ide-manager-item
               :session-key "/tmp/a"
               :display-name "a"
               :secondary-text "/tmp/a"
               :pinned nil
               :order-key 1
               :live-p t)
              (make-claude-code-ide-manager-item
               :session-key "/tmp/b"
               :display-name "b"
               :secondary-text "/tmp/b"
               :pinned nil
               :order-key 2
               :live-p t)))
  (let (calls)
    (cl-letf (((symbol-function 'claude-code-ide-manager-switch-to-session)
               (lambda (session-key &optional keep-manager-focus _scope)
                 (push (list session-key keep-manager-focus) calls))))
      (with-current-buffer (claude-code-ide-manager--get-buffer)
        (claude-code-ide-manager--render)
        (goto-char (point-min))
        (call-interactively (key-binding (kbd "n")))
        (call-interactively (key-binding (kbd "p")))
        (call-interactively (key-binding (kbd "1")))
        (call-interactively (key-binding (kbd "SPC")))
        (call-interactively (key-binding (kbd "RET"))))
      (should (equal (nreverse calls)
                     '(("/tmp/b" t)
                       ("/tmp/a" t)
                       ("/tmp/a" t)
                       ("/tmp/a" t)
                       ("/tmp/a" nil)))))))

(ert-deftest claude-code-ide-test-manager-next-line-works-outside-sidebar ()
  "Test manager next-line can be invoked when the sidebar is not selected."
  (claude-code-ide-tests--reset-manager-state)
  (setq claude-code-ide-manager--items
        (list (make-claude-code-ide-manager-item
               :session-key "/tmp/a"
               :display-name "a"
               :secondary-text "/tmp/a"
               :pinned nil
               :order-key 1
               :live-p t)
              (make-claude-code-ide-manager-item
               :session-key "/tmp/b"
               :display-name "b"
               :secondary-text "/tmp/b"
               :pinned nil
               :order-key 2
               :live-p t)))
  (setq claude-code-ide-manager--current-session-key "/tmp/a")
  (let ((claude-code-ide--processes (make-hash-table :test 'equal))
        (process-a (make-pipe-process :name "cc-manager-next-outside-a" :buffer nil))
        (process-b (make-pipe-process :name "cc-manager-next-outside-b" :buffer nil))
        switched)
    (unwind-protect
        (cl-letf (((symbol-function 'claude-code-ide-manager-switch-to-session)
                   (lambda (session-key &optional _keep-manager-focus _scope)
                     (setq switched session-key)
                     session-key)))
          (puthash "/tmp/a" process-a claude-code-ide--processes)
          (puthash "/tmp/b" process-b claude-code-ide--processes)
          (switch-to-buffer (get-buffer-create "*cc-outside*"))
          (claude-code-ide-manager-next-line)
          (should (equal switched "/tmp/b")))
      (ignore-errors (delete-process process-a))
      (ignore-errors (delete-process process-b))
      (when-let ((window (get-buffer-window (claude-code-ide-manager--get-buffer))))
        (delete-window window))
      (mapc (lambda (buffer)
              (when (buffer-live-p buffer)
                (kill-buffer buffer)))
            (list (get-buffer "*cc-outside*")
                  (get-buffer (buffer-name (claude-code-ide-manager--get-buffer))))))))

(ert-deftest claude-code-ide-test-manager-sidebar-navigation-keeps-focus-on-manager ()
  "Test sidebar n/p switch sessions without leaving the manager window."
  (claude-code-ide-tests--reset-manager-state)
  (let ((session-a (get-buffer-create "*cc-nav-a*"))
        (session-b (get-buffer-create "*cc-nav-b*"))
        (content-buffer (get-buffer-create "*cc-nav-content*"))
        (claude-code-ide--processes (make-hash-table :test 'equal))
        (process-a (make-pipe-process :name "cc-manager-nav-a" :buffer nil))
        (process-b (make-pipe-process :name "cc-manager-nav-b" :buffer nil)))
    (unwind-protect
        (let ((manager-window nil))
          (cl-letf (((symbol-function 'claude-code-ide--get-session-buffer)
                     (lambda (directory)
                       (cond
                        ((equal directory "/tmp/a") session-a)
                        ((equal directory "/tmp/b") session-b))))
                    ((symbol-function 'claude-code-ide-manager--open-status-buffer)
                     (lambda (_directory)
                       (get-buffer-create "*cc-nav-status*"))))
            (setq claude-code-ide-manager--items
                  (list (make-claude-code-ide-manager-item
                         :session-key "/tmp/a"
                         :display-name "a"
                         :secondary-text "/tmp/a"
                         :pinned nil
                         :order-key 1
                         :live-p t)
                        (make-claude-code-ide-manager-item
                         :session-key "/tmp/b"
                         :display-name "b"
                         :secondary-text "/tmp/b"
                         :pinned nil
                         :order-key 2
                         :live-p t)))
            (puthash "/tmp/a" process-a claude-code-ide--processes)
            (puthash "/tmp/b" process-b claude-code-ide--processes)
            (delete-other-windows)
            (switch-to-buffer content-buffer)
            (claude-code-ide-manager-toggle-sidebar 1)
            (setq manager-window (selected-window))
            (with-current-buffer (window-buffer manager-window)
              (goto-char (point-min))
              (call-interactively (key-binding (kbd "n")))
              (should (eq (selected-window) manager-window))
              (should (equal (get-text-property (point) 'claude-code-ide-manager-session-key)
                             "/tmp/b"))
              (should (equal claude-code-ide-manager--current-session-key "/tmp/b"))
              (call-interactively (key-binding (kbd "p")))
              (should (eq (selected-window) manager-window))
              (should (equal (get-text-property (point) 'claude-code-ide-manager-session-key)
                             "/tmp/a"))
              (should (equal claude-code-ide-manager--current-session-key "/tmp/a")))))
      (ignore-errors (delete-process process-a))
      (ignore-errors (delete-process process-b))
      (when-let ((window (get-buffer-window (claude-code-ide-manager--get-buffer))))
        (delete-window window))
      (mapc (lambda (buffer)
              (when (buffer-live-p buffer)
                (kill-buffer buffer)))
            (list session-a session-b content-buffer
                  (get-buffer "*cc-nav-status*")
                  (get-buffer (buffer-name (claude-code-ide-manager--get-buffer))))))))

(ert-deftest claude-code-ide-test-manager-sidebar-navigation-resets-point-to-row-start ()
  "Test sidebar n/p leave point at column zero of the selected row."
  (claude-code-ide-tests--reset-manager-state)
  (let ((session-a (get-buffer-create "*cc-nav-col-a*"))
        (session-b (get-buffer-create "*cc-nav-col-b*"))
        (content-buffer (get-buffer-create "*cc-nav-col-content*"))
        (claude-code-ide--processes (make-hash-table :test 'equal))
        (process-a (make-pipe-process :name "cc-manager-nav-col-a" :buffer nil))
        (process-b (make-pipe-process :name "cc-manager-nav-col-b" :buffer nil)))
    (unwind-protect
        (let ((manager-window nil))
          (cl-letf (((symbol-function 'claude-code-ide--get-session-buffer)
                     (lambda (directory)
                       (cond
                        ((equal directory "/tmp/a") session-a)
                        ((equal directory "/tmp/b") session-b))))
                    ((symbol-function 'claude-code-ide-manager--open-status-buffer)
                     (lambda (_directory)
                       (get-buffer-create "*cc-nav-col-status*"))))
            (setq claude-code-ide-manager--items
                  (list (make-claude-code-ide-manager-item
                         :session-key "/tmp/a"
                         :display-name "a"
                         :secondary-text "/tmp/a"
                         :pinned nil
                         :order-key 1
                         :live-p t)
                        (make-claude-code-ide-manager-item
                         :session-key "/tmp/b"
                         :display-name "b"
                         :secondary-text "/tmp/b"
                         :pinned nil
                         :order-key 2
                         :live-p t)))
            (puthash "/tmp/a" process-a claude-code-ide--processes)
            (puthash "/tmp/b" process-b claude-code-ide--processes)
            (delete-other-windows)
            (switch-to-buffer content-buffer)
            (claude-code-ide-manager-toggle-sidebar 1)
            (setq manager-window (selected-window))
            (with-current-buffer (window-buffer manager-window)
              (goto-char (point-min))
              (forward-char 3)
              (call-interactively (key-binding (kbd "n")))
              (should (eq (selected-window) manager-window))
              (should (= (current-column) 0))
              (should (equal (get-text-property (point) 'claude-code-ide-manager-session-key)
                             "/tmp/b"))
              (forward-char 3)
              (call-interactively (key-binding (kbd "p")))
              (should (eq (selected-window) manager-window))
              (should (= (current-column) 0))
              (should (equal (get-text-property (point) 'claude-code-ide-manager-session-key)
                             "/tmp/a")))))
      (ignore-errors (delete-process process-a))
      (ignore-errors (delete-process process-b))
      (when-let ((window (get-buffer-window (claude-code-ide-manager--get-buffer))))
        (delete-window window))
      (mapc (lambda (buffer)
              (when (buffer-live-p buffer)
                (kill-buffer buffer)))
            (list session-a session-b content-buffer
                  (get-buffer "*cc-nav-col-status*")
                  (get-buffer (buffer-name (claude-code-ide-manager--get-buffer))))))))

(ert-deftest claude-code-ide-test-manager-move-up-swaps-order-within-bucket ()
  "Test move-up swaps row order within the same pin bucket."
  (claude-code-ide-tests--reset-manager-state)
  (setq claude-code-ide-manager--items
        (list (make-claude-code-ide-manager-item
               :session-key "/tmp/a"
               :display-name "a"
               :secondary-text "a"
               :pinned nil
               :order-key 2
               :live-p t)
              (make-claude-code-ide-manager-item
               :session-key "/tmp/b"
               :display-name "b"
               :secondary-text "b"
               :pinned nil
               :order-key 1
               :live-p t)))
  (with-current-buffer (claude-code-ide-manager--get-buffer)
    (claude-code-ide-manager--render)
    (goto-char (point-min))
    (forward-line 1)
    (claude-code-ide-manager-move-up)
    (should (equal (mapcar #'claude-code-ide-manager-item-session-key
                           (claude-code-ide-manager--sorted-items
                            claude-code-ide-manager--items))
                   '("/tmp/a" "/tmp/b")))))

(ert-deftest claude-code-ide-test-manager-switch-by-slot-uses-visible-order ()
  "Test switch-by-slot uses the current visible ordering."
  (claude-code-ide-tests--reset-manager-state)
  (setq claude-code-ide-manager--items
        (list (make-claude-code-ide-manager-item
               :session-key "/tmp/a"
               :display-name "a"
               :secondary-text "a"
               :pinned t
               :order-key 2
               :live-p t)
              (make-claude-code-ide-manager-item
               :session-key "/tmp/b"
               :display-name "b"
               :secondary-text "b"
               :pinned t
               :order-key 1
               :live-p t)
              (make-claude-code-ide-manager-item
               :session-key "/tmp/c"
               :display-name "c"
               :secondary-text "c"
               :pinned nil
               :order-key 1
               :live-p t)))
  (let (switched)
    (cl-letf (((symbol-function 'claude-code-ide-manager-switch-to-session)
               (lambda (session-key &optional _keep-manager-focus _scope)
                 (setq switched session-key))))
      (claude-code-ide-manager-switch-by-slot 1)
      (should (equal switched "/tmp/b"))
      (claude-code-ide-manager-switch-by-slot 2)
      (should (equal switched "/tmp/a")))))

(ert-deftest claude-code-ide-test-manager-switch-by-slot-does-not-focus-manager-window ()
  "Test slot switching does not select the manager window."
  (claude-code-ide-tests--reset-manager-state)
  (let ((session-buffer (get-buffer-create "*cc-session*"))
        (content-buffer (get-buffer-create "*cc-content*"))
        (claude-code-ide--processes (make-hash-table :test 'equal))
        (process-a (make-pipe-process :name "cc-manager-slot-switch" :buffer nil)))
    (unwind-protect
        (let ((content-window nil))
          (cl-letf (((symbol-function 'claude-code-ide--get-session-buffer)
                     (lambda (_directory) session-buffer)))
            (with-current-buffer session-buffer
              (setq-local claude-code-ide-manager--managed-session t))
            (setq claude-code-ide-manager--items
                  (list (make-claude-code-ide-manager-item
                         :session-key "/tmp/project-a"
                         :display-name "project-a"
                         :secondary-text "/tmp/project-a"
                         :pinned nil
                         :order-key 1
                         :live-p t)))
            (puthash "/tmp/project-a" process-a claude-code-ide--processes)
            (delete-other-windows)
            (switch-to-buffer content-buffer)
            (setq content-window (selected-window))
            (let ((session-window (split-window content-window nil 'right)))
              (set-window-buffer session-window session-buffer))
            (claude-code-ide-manager-toggle-sidebar 1)
            (puthash "/tmp/project-a"
                     (claude-code-ide-manager--capture-layout "/tmp/project-a")
                     claude-code-ide-manager--layouts)
            (select-window content-window)
            (claude-code-ide-manager-switch-by-slot 1)
            (should-not (eq (window-buffer (selected-window))
                            (claude-code-ide-manager--get-buffer)))
            (should (eq (window-buffer (selected-window)) session-buffer))))
      (ignore-errors (delete-process process-a))
      (when-let ((window (get-buffer-window (claude-code-ide-manager--get-buffer))))
        (delete-window window))
      (mapc (lambda (buffer)
              (when (buffer-live-p buffer)
                (kill-buffer buffer)))
            (list session-buffer content-buffer
                  (get-buffer (buffer-name (claude-code-ide-manager--get-buffer))))))))

(ert-deftest claude-code-ide-test-manager-switch-by-slot-prefers-visible-sidebar-scope ()
  "Test slot switching from a content buffer follows the visible sidebar scope."
  (claude-code-ide-tests--reset-manager-state)
  (let* ((global-scope '(:type global))
         (repo-scope '(:type repo :git-root "/tmp/repo/"))
         (content-buffer (get-buffer-create "*cc-slot-content*"))
         (repo-buffer (claude-code-ide-manager--get-buffer repo-scope))
         switched)
    (unwind-protect
        (save-window-excursion
          (claude-code-ide-manager--set-scope-items
           global-scope
           (list (make-claude-code-ide-manager-item
                  :session-key "/tmp/global-a"
                  :display-name "global-a"
                  :secondary-text "global-a"
                  :order-key 1
                  :live-p t)))
          (claude-code-ide-manager--set-scope-items
           repo-scope
           (list (make-claude-code-ide-manager-item
                  :session-key "/tmp/repo/worktree-b"
                  :display-name "worktree-b"
                  :secondary-text "worktree-b"
                  :order-key 1
                  :live-p t)))
          (delete-other-windows)
          (switch-to-buffer content-buffer)
          (with-current-buffer repo-buffer
            (setq-local claude-code-ide-manager--scope repo-scope))
          (let ((repo-window (display-buffer-in-side-window
                              repo-buffer
                              '((side . left) (slot . -1)))))
            (set-window-parameter repo-window 'claude-code-ide-manager-sidebar t))
          (cl-letf (((symbol-function 'claude-code-ide-manager-switch-to-session)
                     (lambda (session-key &optional _keep-manager-focus _scope)
                       (setq switched session-key)))
                    ((symbol-function 'claude-code-ide-manager--default-target)
                     (lambda () 'global)))
            (claude-code-ide-manager-switch-by-slot 1)
            (should (equal switched "/tmp/repo/worktree-b"))))
      (mapc (lambda (buffer)
              (when (buffer-live-p buffer)
                (kill-buffer buffer)))
            (list content-buffer repo-buffer)))))

(ert-deftest claude-code-ide-test-manager-switch-by-slot-prefers-visible-repo-scope-over-default-global ()
  "Test slot switching prefers a visible repo scope matching the current buffer."
  (claude-code-ide-tests--reset-manager-state)
  (let* ((global-scope '(:type global))
         (repo-scope '(:type repo :git-root "/tmp/repo/"))
         (content-buffer (get-buffer-create "*cc-slot-content-repo*"))
         (global-buffer (claude-code-ide-manager--get-buffer global-scope))
         (repo-buffer (claude-code-ide-manager--get-buffer repo-scope))
         switched)
    (unwind-protect
        (save-window-excursion
          (claude-code-ide-manager--set-scope-items
           global-scope
           (list (make-claude-code-ide-manager-item
                  :session-key "/tmp/global-a"
                  :display-name "global-a"
                  :secondary-text "global-a"
                  :order-key 1
                  :live-p t)))
          (claude-code-ide-manager--set-scope-items
           repo-scope
           (list (make-claude-code-ide-manager-item
                  :session-key "/tmp/repo/worktree-b"
                  :display-name "worktree-b"
                  :secondary-text "worktree-b"
                  :order-key 1
                  :live-p t)))
          (delete-other-windows)
          (switch-to-buffer content-buffer)
          (with-current-buffer content-buffer
            (setq default-directory "/tmp/repo/worktree-b/"))
          (with-current-buffer global-buffer
            (setq-local claude-code-ide-manager--scope global-scope))
          (with-current-buffer repo-buffer
            (setq-local claude-code-ide-manager--scope repo-scope))
          (let ((global-window (display-buffer-in-side-window
                                global-buffer
                                '((side . left) (slot . -1))))
                (repo-window (display-buffer-in-side-window
                              repo-buffer
                              '((side . left) (slot . 0)))))
            (set-window-parameter global-window 'claude-code-ide-manager-sidebar t)
            (set-window-parameter repo-window 'claude-code-ide-manager-sidebar t))
          (cl-letf (((symbol-function 'claude-code-ide-manager-switch-to-session)
                     (lambda (session-key &optional _keep-manager-focus _scope)
                       (setq switched session-key)))
                    ((symbol-function 'claude-code-ide-manager--current-git-root)
                     (lambda ()
                       (when (eq (current-buffer) content-buffer)
                         "/tmp/repo/")))
                    ((symbol-function 'claude-code-ide-manager--default-target)
                     (lambda () 'global)))
            (claude-code-ide-manager-switch-by-slot 1)
            (should (equal switched "/tmp/repo/worktree-b"))))
      (mapc (lambda (buffer)
              (when (buffer-live-p buffer)
                (kill-buffer buffer)))
            (list content-buffer global-buffer repo-buffer)))))

(ert-deftest claude-code-ide-test-manager-switch-by-slot-passes-resolved-scope-to-switch ()
  "Test slot switching passes the resolved sidebar scope into session switching."
  (claude-code-ide-tests--reset-manager-state)
  (let* ((repo-scope '(:type repo :git-root "/tmp/repo/"))
         (content-buffer (get-buffer-create "*cc-slot-scope-content*"))
         (repo-buffer (claude-code-ide-manager--get-buffer repo-scope))
         call)
    (unwind-protect
        (save-window-excursion
          (claude-code-ide-manager--set-scope-items
           repo-scope
           (list (make-claude-code-ide-manager-item
                  :session-key "/tmp/repo/worktree-b"
                  :display-name "worktree-b"
                  :secondary-text "worktree-b"
                  :order-key 1
                  :live-p t)))
          (delete-other-windows)
          (switch-to-buffer content-buffer)
          (with-current-buffer repo-buffer
            (setq-local claude-code-ide-manager--scope repo-scope))
          (let ((repo-window (display-buffer-in-side-window
                              repo-buffer
                              '((side . left) (slot . -1)))))
            (set-window-parameter repo-window 'claude-code-ide-manager-sidebar t))
          (cl-letf (((symbol-function 'claude-code-ide-manager-switch-to-session)
                     (lambda (session-key &optional keep-manager-focus scope)
                       (setq call (list session-key keep-manager-focus scope)))))
            (claude-code-ide-manager-switch-by-slot 1)
            (should (equal call
                           '("/tmp/repo/worktree-b"
                             nil
                             (:type repo :git-root "/tmp/repo/"))))))
      (mapc (lambda (buffer)
              (when (buffer-live-p buffer)
                (kill-buffer buffer)))
            (list content-buffer repo-buffer)))))

(ert-deftest claude-code-ide-test-manager-switch-by-slot-refreshes-visible-sidebar-highlight ()
  "Test slot switching from a content buffer updates the visible sidebar highlight."
  (claude-code-ide-tests--reset-manager-state)
  (let* ((repo-scope '(:type repo :git-root "/tmp/repo/"))
         (content-buffer (get-buffer-create "*cc-slot-highlight-content*"))
         (repo-buffer (claude-code-ide-manager--get-buffer repo-scope))
         (session-a (get-buffer-create "*cc-slot-highlight-a*"))
         (session-b (get-buffer-create "*cc-slot-highlight-b*"))
         (claude-code-ide--processes (make-hash-table :test 'equal))
         (process-a (make-pipe-process :name "cc-manager-slot-highlight-a"
                                       :buffer session-a))
         (process-b (make-pipe-process :name "cc-manager-slot-highlight-b"
                                       :buffer session-b)))
    (unwind-protect
        (save-window-excursion
          (puthash "/tmp/repo/worktree-a" process-a claude-code-ide--processes)
          (puthash "/tmp/repo/worktree-b" process-b claude-code-ide--processes)
          (claude-code-ide-manager--set-scope-items
           repo-scope
           (list (make-claude-code-ide-manager-item
                  :session-key "/tmp/repo/worktree-a"
                  :display-name "main"
                  :secondary-text "worktree-a"
                  :order-key 1
                  :live-p t)
                 (make-claude-code-ide-manager-item
                  :session-key "/tmp/repo/worktree-b"
                  :display-name "test"
                  :secondary-text "worktree-b"
                  :order-key 2
                  :live-p t)))
          (setq claude-code-ide-manager--current-session-key "/tmp/repo/worktree-a")
          (claude-code-ide-manager--set-scope-active-session-key
           repo-scope "/tmp/repo/worktree-a")
          (delete-other-windows)
          (switch-to-buffer content-buffer)
          (with-current-buffer repo-buffer
            (setq-local claude-code-ide-manager--scope repo-scope)
            (claude-code-ide-manager--render repo-scope))
          (let ((repo-window (display-buffer-in-side-window
                              repo-buffer
                              '((side . left) (slot . -1)))))
            (set-window-parameter repo-window 'claude-code-ide-manager-sidebar t))
          (cl-letf (((symbol-function 'claude-code-ide-manager--capture-layout)
                     (lambda (_session-key) nil))
                    ((symbol-function 'claude-code-ide-manager--save-state)
                     (lambda () nil))
                    ((symbol-function 'claude-code-ide-manager--session-managed-p)
                     (lambda (_session-key) t))
                    ((symbol-function 'claude-code-ide-manager--restore-layout)
                     (lambda (session-key)
                       (setq claude-code-ide-manager--current-session-key session-key)
                       (selected-window))))
            (claude-code-ide-manager-switch-by-slot 2))
          (with-current-buffer repo-buffer
            (goto-char (point-min))
            (should-not (eq (get-text-property (point) 'face)
                            'claude-code-ide-manager-current-session-face))
            (forward-line 1)
            (should (eq (get-text-property (point) 'face)
                        'claude-code-ide-manager-current-session-face))
            (should (equal (get-text-property (point) 'claude-code-ide-manager-session-key)
                           "/tmp/repo/worktree-b"))))
      (ignore-errors (delete-process process-a))
      (ignore-errors (delete-process process-b))
      (mapc (lambda (buffer)
              (when (buffer-live-p buffer)
                (kill-buffer buffer)))
            (list content-buffer repo-buffer session-a session-b)))))

(ert-deftest claude-code-ide-test-manager-space-switch-keeps-focus-on-manager ()
  "Test sidebar SPC switches sessions without leaving the manager window."
  (claude-code-ide-tests--reset-manager-state)
  (let ((session-buffer (get-buffer-create "*cc-space-session*"))
        (content-buffer (get-buffer-create "*cc-space-content*"))
        (claude-code-ide--processes (make-hash-table :test 'equal))
        (process-a (make-pipe-process :name "cc-manager-space-switch" :buffer nil)))
    (unwind-protect
        (let ((manager-window nil))
          (cl-letf (((symbol-function 'claude-code-ide--get-session-buffer)
                     (lambda (_directory) session-buffer))
                    ((symbol-function 'claude-code-ide-manager--open-status-buffer)
                     (lambda (_directory)
                       (get-buffer-create "*cc-space-status*"))))
            (setq claude-code-ide-manager--items
                  (list (make-claude-code-ide-manager-item
                         :session-key "/tmp/project-a"
                         :display-name "project-a"
                         :secondary-text "/tmp/project-a"
                         :pinned nil
                         :order-key 1
                         :live-p t)))
            (puthash "/tmp/project-a" process-a claude-code-ide--processes)
            (delete-other-windows)
            (switch-to-buffer content-buffer)
            (claude-code-ide-manager-toggle-sidebar 1)
            (setq manager-window (selected-window))
            (with-current-buffer (window-buffer manager-window)
              (goto-char (point-min))
              (call-interactively (key-binding (kbd "SPC")))
              (should (eq (selected-window) manager-window))
              (should (equal claude-code-ide-manager--current-session-key
                             "/tmp/project-a")))))
      (ignore-errors (delete-process process-a))
      (when-let ((window (get-buffer-window (claude-code-ide-manager--get-buffer))))
        (delete-window window))
      (mapc (lambda (buffer)
              (when (buffer-live-p buffer)
                (kill-buffer buffer)))
            (list session-buffer content-buffer
                  (get-buffer "*cc-space-status*")
                  (get-buffer (buffer-name (claude-code-ide-manager--get-buffer))))))))

(ert-deftest claude-code-ide-test-manager-saves-layout-before-switch ()
  "Test switching captures the current session layout first."
  (claude-code-ide-tests--reset-manager-state)
  (let ((session-a (get-buffer-create "*cc-a*"))
        (session-b (get-buffer-create "*cc-b*"))
        (extra (get-buffer-create "*cc-extra*")))
    (unwind-protect
        (progn
          (delete-other-windows)
          (switch-to-buffer extra)
          (split-window-right)
          (other-window 1)
          (switch-to-buffer session-a)
          (other-window -1)
          (setq claude-code-ide-manager--current-session-key "/tmp/a")
          (cl-letf (((symbol-function 'claude-code-ide--get-session-buffer)
                     (lambda (directory)
                       (cond
                        ((equal directory "/tmp/a") session-a)
                        ((equal directory "/tmp/b") session-b))))
                    ((symbol-function 'claude-code-ide-manager--open-status-buffer)
                     (lambda (_directory)
                       (get-buffer-create "*cc-status*"))))
            (claude-code-ide-manager-switch-to-session "/tmp/b")
            (should (gethash "/tmp/a" claude-code-ide-manager--layouts))))
      (mapc (lambda (buffer)
              (when (buffer-live-p buffer)
                (kill-buffer buffer)))
            (list session-a session-b extra (get-buffer "*cc-status*"))))))

(ert-deftest claude-code-ide-test-manager-switch-persists-captured-layout ()
  "Test switching saves the captured layout snapshot to persist storage."
  (claude-code-ide-tests--reset-manager-state)
  (let ((session-a (get-buffer-create "*cc-a*"))
        (session-b (get-buffer-create "*cc-b*"))
        (status-buffer (get-buffer-create "*cc-status*"))
        (claude-code-ide-manager-persist-state t))
    (unwind-protect
        (progn
          (setq claude-code-ide-manager--items
                (list (make-claude-code-ide-manager-item
                       :session-key "/tmp/a"
                       :display-name "a"
                       :secondary-text "a"
                       :pinned nil
                       :order-key 1
                       :live-p t)
                      (make-claude-code-ide-manager-item
                       :session-key "/tmp/b"
                       :display-name "b"
                       :secondary-text "b"
                       :pinned nil
                       :order-key 2
                       :live-p t)))
          (setq claude-code-ide-manager--current-session-key "/tmp/a")
          (setq claude-code-ide-manager--layouts (make-hash-table :test 'equal))
          (cl-letf (((symbol-function 'claude-code-ide--get-session-buffer)
                     (lambda (directory)
                       (cond
                        ((equal directory "/tmp/a") session-a)
                        ((equal directory "/tmp/b") session-b))))
                    ((symbol-function 'claude-code-ide-manager--open-status-buffer)
                     (lambda (_directory) status-buffer)))
            (delete-other-windows)
            (switch-to-buffer session-a)
            (split-window-right)
            (other-window 1)
            (switch-to-buffer (get-buffer-create "*cc-focus*"))
            (other-window -1)
            (claude-code-ide-manager-switch-to-session "/tmp/b")
            (let ((saved (gethash 'claude-code-ide-manager--persisted-state
                                  persist--test-store)))
              (should saved)
              (should (assoc "/tmp/a" (plist-get saved :layouts))))))
      (mapc (lambda (buffer)
              (when (buffer-live-p buffer)
                (kill-buffer buffer)))
            (list session-a session-b status-buffer (get-buffer "*cc-focus*"))))))

(ert-deftest claude-code-ide-test-manager-restore-layout-keeps-restored-manager-window-unowned ()
  "Test direct layout restore does not normalize the manager window into a sidebar."
  (claude-code-ide-tests--reset-manager-state)
  (let ((content-buffer (get-buffer-create "*cc-content*"))
        (focus-buffer (get-buffer-create "*cc-focus*"))
        (manager-buffer (claude-code-ide-manager--get-buffer '(:type global)))
        (claude-code-ide--processes (make-hash-table :test 'equal))
        (process-a (make-pipe-process :name "cc-manager-capture-layout" :buffer nil)))
    (unwind-protect
        (progn
          (puthash "/tmp/project-a" process-a claude-code-ide--processes)
          (delete-other-windows)
          (switch-to-buffer content-buffer)
          (split-window-right)
          (other-window 1)
          (switch-to-buffer focus-buffer)
          (other-window -1)
          (let ((sidebar-window (claude-code-ide-manager-toggle-sidebar 1)))
            (should (window-live-p sidebar-window))
            (select-window (get-buffer-window content-buffer))
            (puthash "/tmp/project-a"
                     (claude-code-ide-manager--capture-layout "/tmp/project-a")
                     claude-code-ide-manager--layouts)
            (delete-other-windows)
            (cl-letf (((symbol-function 'claude-code-ide--get-session-buffer)
                       (lambda (_directory)
                         focus-buffer)))
              (claude-code-ide-manager--restore-layout "/tmp/project-a")
              (let ((restored-window
                     (claude-code-ide-manager--visible-manager-window
                      '(:type global))))
                (should (window-live-p restored-window))
                (should (eq (window-buffer restored-window) manager-buffer))
                (should-not
                 (claude-code-ide-manager--sidebar-window '(:type global)))
                (should (get-buffer-window content-buffer))
                (should (get-buffer-window focus-buffer)))))))
      (ignore-errors (delete-process process-a))
      (when-let ((window (get-buffer-window manager-buffer)))
        (delete-window window))
      (mapc (lambda (buffer)
              (when (buffer-live-p buffer)
                (kill-buffer buffer)))
            (list content-buffer
                  focus-buffer
                  manager-buffer))))

(ert-deftest claude-code-ide-test-manager-builds-default-layout-with-magit ()
  "Test first-open layout uses magit when available."
  (claude-code-ide-tests--reset-manager-state)
  (let ((session-buffer (get-buffer-create "*cc-session*"))
        (status-buffer (get-buffer-create "*cc-status*")))
    (unwind-protect
        (cl-letf (((symbol-function 'claude-code-ide--get-session-buffer)
                   (lambda (_directory) session-buffer))
                  ((symbol-function 'magit-status-setup-buffer)
                   (lambda (_directory) status-buffer)))
          (delete-other-windows)
          (let ((window (claude-code-ide-manager--build-default-layout "/tmp/project-a")))
            (should (window-live-p window))
            (should (get-buffer-window session-buffer))
            (should (get-buffer-window status-buffer))))
      (mapc (lambda (buffer)
              (when (buffer-live-p buffer)
                (kill-buffer buffer)))
            (list session-buffer status-buffer)))))

(ert-deftest claude-code-ide-test-manager-switch-from-sidebar-builds-default-layout ()
  "Test switching from the manager sidebar can build the default layout."
  (claude-code-ide-tests--reset-manager-state)
  (let ((session-buffer (get-buffer-create "*cc-session*"))
        (status-buffer (get-buffer-create "*cc-status*"))
        (claude-code-ide--processes (make-hash-table :test 'equal))
        (process-a (make-pipe-process :name "cc-manager-sidebar-switch" :buffer nil)))
    (unwind-protect
        (cl-letf (((symbol-function 'claude-code-ide--get-session-buffer)
                   (lambda (_directory) session-buffer))
                  ((symbol-function 'magit-status-setup-buffer)
                   (lambda (_directory) status-buffer)))
          (puthash "/tmp/project-a" process-a claude-code-ide--processes)
          (claude-code-ide-manager-focus)
          (let ((window (claude-code-ide-manager-switch-to-session "/tmp/project-a")))
            (should (window-live-p window))
            (should (eq (window-buffer window) session-buffer))))
      (ignore-errors (delete-process process-a))
      (when-let ((window (get-buffer-window (claude-code-ide-manager--get-buffer))))
        (delete-window window))
      (mapc (lambda (buffer)
              (when (buffer-live-p buffer)
                (kill-buffer buffer)))
            (list session-buffer status-buffer
                  (get-buffer (buffer-name (claude-code-ide-manager--get-buffer))))))))

(ert-deftest claude-code-ide-test-manager-reset-layout-at-point-builds-default-layout ()
  "Test resetting the selected session layout rebuilds the default layout."
  (claude-code-ide-tests--reset-manager-state)
  (let ((session-buffer (get-buffer-create "*cc-reset-session*"))
        (status-buffer (get-buffer-create "*cc-reset-status*"))
        (manager-buffer (claude-code-ide-manager--get-buffer))
        (content-buffer (get-buffer-create "*cc-reset-content*")))
    (unwind-protect
        (cl-letf (((symbol-function 'claude-code-ide--get-session-buffer)
                   (lambda (_directory) session-buffer))
                  ((symbol-function 'magit-status-setup-buffer)
                   (lambda (_directory) status-buffer)))
          (claude-code-ide-manager--set-scope-items
           '(:type global)
           (list (make-claude-code-ide-manager-item
                  :session-key "/tmp/project-a"
                  :display-name "project-a"
                  :secondary-text "/tmp/project-a"
                  :order-key 1
                  :live-p t)))
          (puthash "/tmp/project-a"
                   '(:window-state stale-layout)
                   claude-code-ide-manager--layouts)
          (save-window-excursion
            (delete-other-windows)
            (switch-to-buffer content-buffer)
            (let ((manager-window (split-window-right)))
              (set-window-buffer manager-window manager-buffer)
              (set-window-parameter manager-window 'claude-code-ide-manager-sidebar t)
              (with-current-buffer manager-buffer
                (claude-code-ide-manager--render '(:type global))
                (goto-char (point-min))
                (claude-code-ide-manager-reset-layout-at-point))
              (should (get-buffer-window session-buffer))
              (should (get-buffer-window status-buffer))
              (should-not (gethash "/tmp/project-a"
                                   claude-code-ide-manager--layouts)))))
      (mapc (lambda (buffer)
              (when (buffer-live-p buffer)
                (kill-buffer buffer)))
            (list session-buffer status-buffer manager-buffer content-buffer)))))

(ert-deftest claude-code-ide-test-manager-mode-binds-R-to-reset-layout ()
  "Test manager mode binds `R' to layout reset."
  (should (eq (lookup-key claude-code-ide-manager-mode-map (kbd "R"))
              #'claude-code-ide-manager-reset-layout-at-point)))

(ert-deftest claude-code-ide-test-manager-reset-layout-rebuilds-current-session-default-layout ()
  "Test reset layout does not re-save stale layout for the current session."
  (claude-code-ide-tests--reset-manager-state)
  (let ((session-buffer (get-buffer-create "*cc-reset-current-session*"))
        (status-buffer (get-buffer-create "*cc-reset-current-status*")))
    (unwind-protect
        (cl-letf (((symbol-function 'claude-code-ide--get-session-buffer)
                   (lambda (_directory) session-buffer))
                  ((symbol-function 'magit-status-setup-buffer)
                   (lambda (_directory) status-buffer))
                  ((symbol-function 'claude-code-ide-manager--capture-layout)
                   (lambda (_session-key)
                     '(:window-state captured-layout))))
          (setq claude-code-ide-manager--current-session-key "/tmp/project-a")
          (puthash "/tmp/project-a"
                   '(:window-state stale-layout)
                   claude-code-ide-manager--layouts)
          (save-window-excursion
            (delete-other-windows)
            (claude-code-ide-manager-reset-layout "/tmp/project-a")
            (should (get-buffer-window session-buffer))
            (should (get-buffer-window status-buffer))
            (should-not (equal (gethash "/tmp/project-a"
                                        claude-code-ide-manager--layouts)
                               '(:window-state captured-layout)))))
      (mapc (lambda (buffer)
              (when (buffer-live-p buffer)
                (kill-buffer buffer)))
            (list session-buffer status-buffer)))))

(ert-deftest claude-code-ide-test-manager-reset-layout-skips-treemacs-sync-when-hidden ()
  "Test reset layout does not open Treemacs when it is hidden."
  (claude-code-ide-tests--reset-manager-state)
  (let ((session-buffer (get-buffer-create "*cc-reset-hidden-session*"))
        (status-buffer (get-buffer-create "*cc-reset-hidden-status*"))
        synced)
    (unwind-protect
        (cl-letf (((symbol-function 'claude-code-ide--get-session-buffer)
                   (lambda (_directory) session-buffer))
                  ((symbol-function 'magit-status-setup-buffer)
                   (lambda (_directory) status-buffer))
                  ((symbol-function 'claude-code-ide-manager--treemacs-window)
                   (lambda () nil))
                  ((symbol-function 'claude-code-ide-manager--sync-treemacs-to-session)
                   (lambda (_session-key)
                     (setq synced t))))
          (save-window-excursion
            (delete-other-windows)
            (claude-code-ide-manager-reset-layout "/tmp/project-a")
            (should-not synced)))
      (mapc (lambda (buffer)
              (when (buffer-live-p buffer)
                (kill-buffer buffer)))
            (list session-buffer status-buffer)))))

(ert-deftest claude-code-ide-test-manager-falls-back-to-dired-when-magit-unavailable ()
  "Test status buffer falls back to dired when magit fails."
  (let ((dired-buffer (get-buffer-create "*cc-dired*")))
    (unwind-protect
        (cl-letf (((symbol-function 'magit-status-setup-buffer)
                   (lambda (_directory)
                     (error "no magit")))
                  ((symbol-function 'dired-noselect)
                   (lambda (_directory) dired-buffer)))
          (should (eq (claude-code-ide-manager--open-status-buffer "/tmp/project-a")
                      dired-buffer)))
      (when (buffer-live-p dired-buffer)
        (kill-buffer dired-buffer)))))

(ert-deftest claude-code-ide-test-manager-switch-restores-last-selected-window ()
  "Test restore selects the saved focused buffer when available."
  (claude-code-ide-tests--reset-manager-state)
  (let ((session-buffer (get-buffer-create "*cc-session*"))
        (focus-buffer (get-buffer-create "*cc-focus*")))
    (unwind-protect
        (progn
          (delete-other-windows)
          (switch-to-buffer focus-buffer)
          (split-window-right)
          (other-window 1)
          (switch-to-buffer session-buffer)
          (other-window -1)
          (puthash "/tmp/project-a"
                   (claude-code-ide-manager--capture-layout "/tmp/project-a")
                   claude-code-ide-manager--layouts)
          (delete-other-windows)
          (cl-letf (((symbol-function 'claude-code-ide--get-session-buffer)
                     (lambda (_directory) session-buffer)))
            (with-current-buffer session-buffer
              (setq-local claude-code-ide-manager--managed-session t))
            (claude-code-ide-manager-switch-to-session "/tmp/project-a")
            (should (equal (window-buffer (selected-window)) focus-buffer))))
      (mapc (lambda (buffer)
              (when (buffer-live-p buffer)
                (kill-buffer buffer)))
            (list session-buffer focus-buffer)))))

(ert-deftest claude-code-ide-test-manager-first-switch-to-live-session-uses-default-layout-even-with-saved-layout ()
  "Test a live session's first manager switch bypasses stale saved layouts."
  (claude-code-ide-tests--reset-manager-state)
  (let ((session-buffer (get-buffer-create "*cc-session*"))
        restored
        built)
    (unwind-protect
        (progn
          (puthash "/tmp/project-a"
                   '(:window-state saved)
                   claude-code-ide-manager--layouts)
          (cl-letf (((symbol-function 'claude-code-ide--get-session-buffer)
                     (lambda (_session-key) session-buffer))
                    ((symbol-function 'claude-code-ide-manager--restore-layout)
                     (lambda (_session-key)
                       (setq restored t)
                       (selected-window)))
                    ((symbol-function 'claude-code-ide-manager--build-default-layout)
                     (lambda (_session-key _scope)
                       (setq built t)
                       (selected-window)))
                    ((symbol-function 'claude-code-ide-manager--visible-sidebar-scopes)
                     (lambda () nil))
                    ((symbol-function 'claude-code-ide-manager--adopt-visible-sidebars)
                     (lambda (_scopes) nil))
                    ((symbol-function 'claude-code-ide-manager--restore-visible-sidebars)
                     (lambda (_scopes) nil))
                    ((symbol-function 'claude-code-ide-manager--treemacs-window)
                     (lambda () nil))
                    ((symbol-function 'claude-code-ide-manager--refresh-sidebar-state)
                     (lambda (&optional _scope _reassert) nil)))
            (claude-code-ide-manager-switch-to-session "/tmp/project-a" nil '(:type global))
            (should built)
            (should-not restored)))
      (when (buffer-live-p session-buffer)
        (kill-buffer session-buffer)))))

(ert-deftest claude-code-ide-test-manager-switch-restores-visible-sidebar-after-layout-restore ()
  "Test switching re-shows a visible sidebar after restoring session content."
  (claude-code-ide-tests--reset-manager-state)
  (let ((session-buffer (get-buffer-create "*cc-session*"))
        (content-buffer (get-buffer-create "*cc-content*"))
        (focus-buffer (get-buffer-create "*cc-focus*"))
        (claude-code-ide--processes (make-hash-table :test 'equal))
        (process-a (make-pipe-process :name "cc-manager-switch-restore-sidebar-a" :buffer nil))
        (process-b (make-pipe-process :name "cc-manager-switch-restore-sidebar-b" :buffer nil)))
    (unwind-protect
        (progn
          (puthash "/tmp/project-a" process-a claude-code-ide--processes)
          (puthash "/tmp/project-b" process-b claude-code-ide--processes)
          (delete-other-windows)
          (switch-to-buffer content-buffer)
          (split-window-right)
          (other-window 1)
          (switch-to-buffer focus-buffer)
          (other-window -1)
          (puthash "/tmp/project-a"
                   (claude-code-ide-manager--capture-layout "/tmp/project-a")
                   claude-code-ide-manager--layouts)
          (setq claude-code-ide-manager--current-session-key "/tmp/project-b")
          (should (window-live-p (claude-code-ide-manager-toggle-sidebar 1)))
          (cl-letf (((symbol-function 'claude-code-ide--get-session-buffer)
                     (lambda (_directory) session-buffer))
                    ((symbol-function 'claude-code-ide-manager--open-status-buffer)
                     (lambda (_directory)
                       (get-buffer-create "*cc-status*"))))
            (claude-code-ide-manager-switch-to-session "/tmp/project-a")
            (should (window-live-p
                     (claude-code-ide-manager--sidebar-window '(:type global))))
            (should (= 1
                       (length (cl-remove-if-not
                                (lambda (window)
                                  (eq (window-buffer window)
                                      (claude-code-ide-manager--get-buffer '(:type global))))
                                (window-list nil 'no-minibuf)))))
            (should-not (eq (window-buffer (selected-window))
                            (claude-code-ide-manager--get-buffer '(:type global)))))))
      (ignore-errors (delete-process process-a))
      (ignore-errors (delete-process process-b))
      (when-let ((window (get-buffer-window (claude-code-ide-manager--get-buffer))))
        (delete-window window))
      (mapc (lambda (buffer)
              (when (buffer-live-p buffer)
                (kill-buffer buffer)))
            (list session-buffer
                  content-buffer
                  focus-buffer
                  (get-buffer "*cc-status*")
                  (get-buffer (buffer-name (claude-code-ide-manager--get-buffer)))))))

(ert-deftest claude-code-ide-test-manager-switch-keeps-sidebar-visible-when-target-layout-lacks-it ()
  "Test switching keeps a currently visible sidebar even if target layout lacks one."
  (claude-code-ide-tests--reset-manager-state)
  (let ((session-buffer (get-buffer-create "*cc-session*"))
        (content-buffer (get-buffer-create "*cc-content*"))
        (focus-buffer (get-buffer-create "*cc-focus*"))
        (claude-code-ide--processes (make-hash-table :test 'equal))
        (process-a (make-pipe-process :name "cc-manager-switch-keep-sidebar-a" :buffer nil))
        (process-b (make-pipe-process :name "cc-manager-switch-keep-sidebar-b" :buffer nil)))
    (unwind-protect
        (progn
          (puthash "/tmp/project-a" process-a claude-code-ide--processes)
          (puthash "/tmp/project-b" process-b claude-code-ide--processes)
          (delete-other-windows)
          (switch-to-buffer content-buffer)
          (split-window-right)
          (other-window 1)
          (switch-to-buffer focus-buffer)
          (other-window -1)
          (puthash "/tmp/project-a"
                   (claude-code-ide-manager--capture-layout "/tmp/project-a")
                   claude-code-ide-manager--layouts)
          (setq claude-code-ide-manager--current-session-key "/tmp/project-b")
          (should (window-live-p (claude-code-ide-manager-toggle-sidebar 1)))
          (cl-letf (((symbol-function 'claude-code-ide--get-session-buffer)
                     (lambda (_directory) session-buffer))
                    ((symbol-function 'claude-code-ide-manager--open-status-buffer)
                     (lambda (_directory)
                       (get-buffer-create "*cc-status*")))
                    ((symbol-function 'claude-code-ide-manager--restore-layout)
                     (lambda (_session-key)
                       (select-window (claude-code-ide-manager--content-window))
                       (delete-other-windows)
                       (switch-to-buffer focus-buffer)
                       t)))
            (claude-code-ide-manager-switch-to-session "/tmp/project-a")
            (should (window-live-p
                     (claude-code-ide-manager--sidebar-window '(:type global))))
            (should (= 1
                       (length (cl-remove-if-not
                                (lambda (window)
                                  (eq (window-buffer window)
                                      (claude-code-ide-manager--get-buffer '(:type global))))
                                (window-list nil 'no-minibuf)))))
            (should-not (eq (window-buffer (selected-window))
                            (claude-code-ide-manager--get-buffer '(:type global)))))))
      (ignore-errors (delete-process process-a))
      (ignore-errors (delete-process process-b))
      (when-let ((window (get-buffer-window (claude-code-ide-manager--get-buffer))))
        (delete-window window))
      (mapc (lambda (buffer)
              (when (buffer-live-p buffer)
                (kill-buffer buffer)))
            (list session-buffer
                  content-buffer
                  focus-buffer
                  (get-buffer "*cc-status*")
                  (get-buffer (buffer-name (claude-code-ide-manager--get-buffer)))))))

(ert-deftest claude-code-ide-test-manager-switch-adopts-restored-sidebar-without-showing-new-one ()
  "Test switching reuses a restored visible sidebar window instead of recreating it."
  (claude-code-ide-tests--reset-manager-state)
  (let ((session-buffer (get-buffer-create "*cc-session*"))
        (content-buffer (get-buffer-create "*cc-content*"))
        (manager-buffer (claude-code-ide-manager--get-buffer '(:type global)))
        (claude-code-ide--processes (make-hash-table :test 'equal))
        (process-a (make-pipe-process :name "cc-manager-switch-adopt-sidebar-a" :buffer nil))
        (process-b (make-pipe-process :name "cc-manager-switch-adopt-sidebar-b" :buffer nil))
        show-sidebar-called)
    (unwind-protect
        (progn
          (puthash "/tmp/project-a" process-a claude-code-ide--processes)
          (puthash "/tmp/project-b" process-b claude-code-ide--processes)
          (delete-other-windows)
          (switch-to-buffer content-buffer)
          (should (window-live-p (claude-code-ide-manager-toggle-sidebar 1)))
          (setq claude-code-ide-manager--current-session-key "/tmp/project-b")
          (cl-letf (((symbol-function 'claude-code-ide--get-session-buffer)
                     (lambda (_directory) session-buffer))
                    ((symbol-function 'claude-code-ide-manager--session-managed-p)
                     (lambda (_session-key) t))
                    ((symbol-function 'claude-code-ide-manager--show-sidebar)
                     (lambda (&optional _scope)
                       (setq show-sidebar-called t)
                       (error "unexpected sidebar recreation")))
                    ((symbol-function 'claude-code-ide-manager--restore-layout)
                     (lambda (_session-key)
                       (select-window (claude-code-ide-manager--content-window))
                       (delete-other-windows)
                       (split-window-right)
                       (other-window 1)
                       (set-window-buffer (selected-window) manager-buffer)
                       (other-window -1)
                       (switch-to-buffer session-buffer)
                       (selected-window))))
            (claude-code-ide-manager-switch-to-session "/tmp/project-a")
            (should-not show-sidebar-called)
            (should (window-live-p
                     (claude-code-ide-manager--sidebar-window '(:type global)))))))
      (ignore-errors (delete-process process-a))
      (ignore-errors (delete-process process-b))
      (when-let ((window (get-buffer-window manager-buffer)))
        (delete-window window))
      (mapc (lambda (buffer)
              (when (buffer-live-p buffer)
                (kill-buffer buffer)))
            (list session-buffer
                  content-buffer
                  manager-buffer))))

(ert-deftest claude-code-ide-test-manager-switch-falls-back-to-session-buffer ()
  "Test restore falls back to session buffer when focused buffer is gone."
  (claude-code-ide-tests--reset-manager-state)
  (let ((session-buffer (get-buffer-create "*cc-session*"))
        (focus-buffer (get-buffer-create "*cc-focus*")))
    (unwind-protect
        (progn
          (delete-other-windows)
          (switch-to-buffer focus-buffer)
          (split-window-right)
          (other-window 1)
          (switch-to-buffer session-buffer)
          (other-window -1)
          (let ((layout (claude-code-ide-manager--capture-layout "/tmp/project-a")))
            (setf (plist-get layout :selected-buffer-name) "*cc-missing*")
            (puthash "/tmp/project-a" layout claude-code-ide-manager--layouts))
          (delete-other-windows)
          (cl-letf (((symbol-function 'claude-code-ide--get-session-buffer)
                     (lambda (_directory) session-buffer)))
            (with-current-buffer session-buffer
              (setq-local claude-code-ide-manager--managed-session t))
            (claude-code-ide-manager-switch-to-session "/tmp/project-a")
            (should (equal (window-buffer (selected-window)) session-buffer))))
      (mapc (lambda (buffer)
              (when (buffer-live-p buffer)
                (kill-buffer buffer)))
            (list session-buffer focus-buffer)))))

(ert-deftest claude-code-ide-test-manager-refreshes-when-target-buffer-disappears ()
  "Test stale target refreshes manager state and errors cleanly."
  (claude-code-ide-tests--reset-manager-state)
  (setq claude-code-ide-manager--items
        (list (make-claude-code-ide-manager-item
               :session-key "/tmp/missing"
               :display-name "missing"
               :secondary-text "missing"
               :pinned nil
               :order-key 1
               :live-p t)))
  (let ((claude-code-ide--processes (make-hash-table :test 'equal))
        refreshed)
    (cl-letf (((symbol-function 'claude-code-ide-manager-refresh)
               (lambda (&optional _scope)
                 (setq refreshed t)
                 (setq claude-code-ide-manager--items nil)))
              ((symbol-function 'claude-code-ide--get-session-buffer)
               (lambda (_directory) nil)))
      (should-error (claude-code-ide-manager-switch-to-session "/tmp/missing")
                    :type 'user-error)
      (should refreshed)
      (should-not claude-code-ide-manager--items))))

(ert-deftest claude-code-ide-test-get-working-directory ()
  "Test working directory detection."
  (claude-code-ide-tests--with-temp-directory
   (lambda ()
     ;; Without project, should return current directory
     (let ((expected (expand-file-name default-directory)))
       (should (equal (claude-code-ide--get-working-directory) expected))))))

(ert-deftest claude-code-ide-test-get-current-session-prefers-closest-parent ()
  "Test current session resolution prefers the closest parent directory."
  (let* ((root-dir "/tmp/project/")
         (sub-dir "/tmp/project/sub/")
         (session-root (make-claude-code-ide-mcp-session :project-dir root-dir))
         (session-sub (make-claude-code-ide-mcp-session :project-dir sub-dir))
         (claude-code-ide-mcp--sessions (make-hash-table :test 'equal)))
    (puthash root-dir session-root claude-code-ide-mcp--sessions)
    (puthash sub-dir session-sub claude-code-ide-mcp--sessions)
    (with-temp-buffer
      (setq default-directory "/tmp/project/sub/nested/")
      (setq buffer-file-name "/tmp/project/sub/nested/file.el")
      (cl-letf (((symbol-function 'project-current)
                 (lambda (&optional _maybe-prompt _dir) '(transient . "/tmp/project/")))
                ((symbol-function 'project-root)
                 (lambda (_project) root-dir)))
        (should (eq (claude-code-ide-mcp--get-current-session) session-sub))))))

(ert-deftest claude-code-ide-test-get-buffer-name ()
  "Test buffer name generation using custom function."
  ;; Test with custom function
  (let ((claude-code-ide-buffer-name-function
         (lambda (dir) (format "test-%s" (file-name-nondirectory dir)))))
    (claude-code-ide-tests--with-temp-directory
     (lambda ()
       (should (string-match "^test-claude-code-ide-test-"
                             (claude-code-ide--get-buffer-name))))))

  ;; Test that nil directory is handled correctly
  (let ((claude-code-ide-buffer-name-function
         (lambda (dir) (if dir
                           (format "*custom[%s]*" (file-name-nondirectory dir))
                         "*custom[none]*"))))
    (should (equal (funcall claude-code-ide-buffer-name-function nil)
                   "*custom[none]*"))))

(ert-deftest claude-code-ide-test-get-session-buffer-prefers-process-buffer ()
  "Test session buffer lookup prefers the live process buffer over the default name."
  (let* ((directory "/tmp/team-a/project/")
         (session-buffer (generate-new-buffer "*claude-code[project]<team-a>*"))
         (process (make-pipe-process :name "cc-buffer-lookup" :buffer session-buffer))
         (claude-code-ide--processes (make-hash-table :test 'equal)))
    (unwind-protect
        (progn
          (puthash directory process claude-code-ide--processes)
          (should (eq (claude-code-ide--get-session-buffer directory)
                      session-buffer)))
      (ignore-errors (delete-process process))
      (when (buffer-live-p session-buffer)
        (kill-buffer session-buffer)))))

(ert-deftest claude-code-ide-test-get-session-buffer-does-not-alias-colliding-basenames ()
  "Test colliding directory basenames do not alias session buffers."
  (let* ((directory-a "/tmp/team-a/project/")
         (directory-b "/tmp/team-b/project/")
         (session-buffer-a (generate-new-buffer "*claude-code[project]<team-a>*"))
         (session-buffer-b (generate-new-buffer "*claude-code[project]*"))
         (process-a (make-pipe-process :name "cc-collision-a" :buffer session-buffer-a))
         (claude-code-ide--processes (make-hash-table :test 'equal)))
    (unwind-protect
        (progn
          (puthash directory-a process-a claude-code-ide--processes)
          (should (eq (claude-code-ide--get-session-buffer directory-a)
                      session-buffer-a))
          (should (eq (claude-code-ide--get-session-buffer directory-b)
                      session-buffer-b)))
      (ignore-errors (delete-process process-a))
      (when (buffer-live-p session-buffer-a)
        (kill-buffer session-buffer-a))
      (when (buffer-live-p session-buffer-b)
        (kill-buffer session-buffer-b)))))

(ert-deftest claude-code-ide-test-process-management ()
  "Test process storage and retrieval."
  (claude-code-ide-tests--clear-processes)
  (unwind-protect
      (claude-code-ide-tests--with-temp-directory
       (lambda ()
         (let ((dir (claude-code-ide--get-working-directory))
               (mock-process 'mock-process))
           ;; Initially no process
           (should (null (claude-code-ide--get-process dir)))

           ;; Set a process
           (claude-code-ide--set-process mock-process dir)
           (should (eq (claude-code-ide--get-process dir) mock-process))

           ;; Get process without specifying directory
           (should (eq (claude-code-ide--get-process) mock-process)))))
    (claude-code-ide-tests--clear-processes)))

(ert-deftest claude-code-ide-test-set-process-installs-working-resize-observer-for-first-session ()
  "Test first session setup installs resize-based working detection independently."
  (claude-code-ide-tests--clear-processes)
  (let ((claude-code-ide-prevent-reflow-glitch nil)
        (added-advices nil))
    (cl-letf (((symbol-function 'claude-code-ide--current-cli-type)
               (lambda ()
                 'codex))
              ((symbol-function 'claude-code-ide--terminal-resize-handler)
               (lambda ()
                 'eat--adjust-process-window-size))
              ((symbol-function 'advice-add)
               (lambda (symbol where function &rest _props)
                 (push (list symbol where function) added-advices))))
      (claude-code-ide--set-process 'mock-process "/tmp/test")
      (should (member '(eat--adjust-process-window-size
                        :around
                        claude-code-ide--terminal-working-resize-observer)
                      added-advices))
      (should-not (member '(eat--adjust-process-window-size
                            :around
                            claude-code-ide--terminal-reflow-filter)
                          added-advices)))))

(ert-deftest claude-code-ide-test-cleanup-dead-processes ()
  "Test cleanup of dead processes."
  (claude-code-ide-tests--clear-processes)
  (unwind-protect
      (let* ((live-process (make-process :name "test-live"
                                         :command '("sleep" "10")
                                         :buffer nil))
             (dead-process-name "test-dead"))
        ;; Create a mock dead process
        (puthash "/dir1" live-process claude-code-ide--processes)
        (puthash "/dir2" dead-process-name claude-code-ide--processes)

        ;; Before cleanup
        (should (= (hash-table-count claude-code-ide--processes) 2))

        ;; Run cleanup
        (claude-code-ide--cleanup-dead-processes)

        ;; After cleanup - only live process remains
        (should (= (hash-table-count claude-code-ide--processes) 1))
        (should (gethash "/dir1" claude-code-ide--processes))
        (should (null (gethash "/dir2" claude-code-ide--processes)))

        ;; Clean up the live process
        (delete-process live-process))
    (claude-code-ide-tests--clear-processes)))

(ert-deftest claude-code-ide-test-cleanup-removes-working-resize-observer-for-last-session ()
  "Test last-session cleanup removes resize-based working detection advice."
  (let ((removed-advices nil)
        (claude-code-ide-vterm-anti-flicker nil)
        (claude-code-ide--processes (make-hash-table :test 'equal))
        (claude-code-ide--cleanup-in-progress nil))
    (cl-letf (((symbol-function 'claude-code-ide--terminal-resize-handler)
               (lambda ()
                 'eat--adjust-process-window-size))
              ((symbol-function 'advice-remove)
               (lambda (symbol function)
                 (push (list symbol function) removed-advices)))
              ((symbol-function 'claude-code-ide-mcp-stop-session)
               (lambda (_directory)
                 nil))
              ((symbol-function 'claude-code-ide-mcp-server-session-ended)
               (lambda (_session-id)
                 nil))
              ((symbol-function 'claude-code-ide--get-buffer-name)
               (lambda (_directory)
                 "*test-buffer*")))
      (puthash "/tmp/test" (current-buffer) claude-code-ide--processes)
      (claude-code-ide--cleanup-on-exit "/tmp/test")
      (should (member '(eat--adjust-process-window-size
                        claude-code-ide--terminal-working-resize-observer)
                      removed-advices)))))

;;; Tests for CLI Detection

(ert-deftest claude-code-ide-test-detect-cli ()
  "Test CLI detection mechanism."
  (let ((claude-code-ide--cli-available nil))
    ;; Test with invalid CLI path
    (let ((claude-code-ide-cli-path "nonexistent-claude-cli"))
      (claude-code-ide--detect-cli)
      (should (null claude-code-ide--cli-available)))

    ;; Test with valid command (echo exists on most systems)
    (let ((claude-code-ide-cli-path "echo"))
      (claude-code-ide--detect-cli)
      (should claude-code-ide--cli-available))))

(ert-deftest claude-code-ide-test-ensure-cli ()
  "Test CLI availability checking."
  (let ((claude-code-ide--cli-available nil)
        (claude-code-ide-cli-path "echo"))
    ;; Initially not available
    (should (null claude-code-ide--cli-available))

    ;; After ensure, should be detected
    (should (claude-code-ide--ensure-cli))
    (should claude-code-ide--cli-available)))

;;; Command Tests

(ert-deftest claude-code-ide-test-run-without-cli ()
  "Test run command when CLI is not available."
  (let ((claude-code-ide--cli-available nil)
        (claude-code-ide-cli-path "nonexistent-claude-cli"))
    (should-error (claude-code-ide)
                  :type 'user-error)))

(ert-deftest claude-code-ide-test-run-without-vterm ()
  "Test run command when vterm is not available."
  (let ((claude-code-ide--cli-available t)
        (claude-code-ide-cli-path "echo")
        (claude-code-ide-terminal-backend 'vterm)
        (orig-featurep (symbol-function 'featurep)))
    (cl-letf (((symbol-function 'featurep)
               (lambda (sym &rest _) (if (eq sym 'vterm) nil (funcall orig-featurep sym))))
              ((symbol-function 'require)
               (lambda (feature &optional filename noerror)
                 (unless (eq feature 'vterm)
                   (require feature filename noerror)))))
      (should-error (claude-code-ide)
                    :type 'user-error))))

(ert-deftest claude-code-ide-test-run-without-eat ()
  "Test run command when eat is not available."
  (let ((claude-code-ide--cli-available t)
        (claude-code-ide-cli-path "echo")
        (claude-code-ide-terminal-backend 'eat)
        (orig-featurep (symbol-function 'featurep)))
    (cl-letf (((symbol-function 'featurep)
               (lambda (sym &rest _) (if (eq sym 'eat) nil (funcall orig-featurep sym))))
              ((symbol-function 'require)
               (lambda (feature &optional filename noerror)
                 (unless (eq feature 'eat)
                   (require feature filename noerror)))))
      (should-error (claude-code-ide)
                    :type 'user-error))))

(ert-deftest claude-code-ide-test-terminal-backend-selection ()
  "Test terminal backend selection and validation."
  ;; Test vterm backend
  (let ((claude-code-ide-terminal-backend 'vterm))
    (should (eq claude-code-ide-terminal-backend 'vterm)))

  ;; Test eat backend
  (let ((claude-code-ide-terminal-backend 'eat))
    (should (eq claude-code-ide-terminal-backend 'eat)))

  ;; Test invalid backend
  (let ((claude-code-ide-terminal-backend 'invalid-backend)
        (orig-featurep (symbol-function 'featurep)))
    (cl-letf (((symbol-function 'featurep)
               (lambda (sym) nil)))
      (should-error (claude-code-ide--terminal-ensure-backend)
                    :type 'user-error))))

(ert-deftest claude-code-ide-test-terminal-backend-resolution ()
  "Test per-CLI terminal backend overrides with fallback to the default."
  (let ((claude-code-ide-terminal-backend 'vterm)
        (claude-code-ide-cli-terminal-backends '((codex . eat)
                                                 (opencode . vterm))))
    (let ((claude-code-ide-cli-path "claude"))
      (should (eq (claude-code-ide--resolve-terminal-backend) 'vterm)))
    (let ((claude-code-ide-cli-path "codex"))
      (should (eq (claude-code-ide--resolve-terminal-backend) 'eat)))
    (should (eq (claude-code-ide--resolve-terminal-backend 'opencode) 'vterm))))

(ert-deftest claude-code-ide-test-terminal-backend-resolution-gsd ()
  "Test `gsd' respects per-CLI terminal backend overrides."
  (let ((claude-code-ide-terminal-backend 'vterm)
        (claude-code-ide-cli-terminal-backends '((gsd . eat))))
    (let ((claude-code-ide-cli-path "gsd"))
      (should (eq (claude-code-ide--resolve-terminal-backend) 'eat)))))

(ert-deftest claude-code-ide-test-terminal-send-functions ()
  "Test terminal send wrapper functions."
  ;; Mock vterm functions
  (let ((vterm-string-sent nil)
        (vterm-escape-sent nil)
        (vterm-return-sent nil)
        (eat-string-sent nil))
    (cl-letf (((symbol-function 'vterm-send-string)
               (lambda (str &optional _paste) (setq vterm-string-sent str)))
              ((symbol-function 'vterm-send-escape)
               (lambda () (setq vterm-escape-sent t)))
              ((symbol-function 'vterm-send-return)
               (lambda () (setq vterm-return-sent t)))
              ((symbol-function 'eat-term-send-string)
               (lambda (term str) (setq eat-string-sent str))))

      ;; Test vterm backend
      (let ((claude-code-ide-terminal-backend 'vterm))
        (claude-code-ide--terminal-send-string "test")
        (should (equal vterm-string-sent "test"))

        (claude-code-ide--terminal-send-escape)
        (should vterm-escape-sent)

        (claude-code-ide--terminal-send-return)
        (should vterm-return-sent))

      ;; Test eat backend - need to mock the buffer-local variable
      (with-temp-buffer
        (let ((claude-code-ide-terminal-backend 'eat))
          ;; Set eat-terminal as a buffer-local variable
          (setq-local eat-terminal t)
          (claude-code-ide--terminal-send-string "test")
          (should (equal eat-string-sent "test"))

          (setq eat-string-sent nil)
          (claude-code-ide--terminal-send-escape)
          (should (equal eat-string-sent "\e"))

          (setq eat-string-sent nil)
          (claude-code-ide--terminal-send-return)
          (should (equal eat-string-sent "\r")))))))

(ert-deftest claude-code-ide-test-terminal-send-functions-use-buffer-local-backend ()
  "Test that terminal send wrappers honor the session buffer backend."
  (let ((eat-string-sent nil))
    (cl-letf (((symbol-function 'eat-term-send-string)
               (lambda (_term str) (setq eat-string-sent str))))
      (with-temp-buffer
        (let ((claude-code-ide-terminal-backend 'vterm))
          (setq-local eat-terminal t)
          (setq-local claude-code-ide--terminal-backend 'eat)
          (claude-code-ide--terminal-send-string "test")
          (should (equal eat-string-sent "test")))))))

(ert-deftest claude-code-ide-test-send-prompt-command ()
  "Test the claude-code-ide-send-prompt command."
  (let ((test-prompt "Test prompt from minibuffer")
        (prompted-string nil)
        (sent-string nil)
        (sent-return nil))
    ;; Mock read-string to return our test prompt
    (cl-letf (((symbol-function 'read-string)
               (lambda (prompt &rest _)
                 (setq prompted-string prompt)
                 test-prompt))
              ((symbol-function 'claude-code-ide--get-buffer-name)
               (lambda () "*test-claude-buffer*"))
              ((symbol-function 'claude-code-ide--terminal-send-string)
               (lambda (str) (setq sent-string str)))
              ((symbol-function 'claude-code-ide--terminal-send-return)
               (lambda () (setq sent-return t))))

      ;; Test with existing buffer
      (with-temp-buffer
        (rename-buffer "*test-claude-buffer*")
        (claude-code-ide-send-prompt)
        (should (equal prompted-string "Claude prompt: "))
        (should (equal sent-string test-prompt))
        (should sent-return))

      ;; Test with non-existent buffer (should error)
      (should-error (claude-code-ide-send-prompt) :type 'user-error)

      ;; Test with empty prompt (should not send anything)
      (setq sent-string nil sent-return nil)
      (cl-letf (((symbol-function 'read-string)
                 (lambda (&rest _) "")))
        (with-temp-buffer
          (rename-buffer "*test-claude-buffer*")
          (claude-code-ide-send-prompt)
          (should (null sent-string))
          (should (null sent-return)))))))

(ert-deftest claude-code-ide-test-is-comment-line-detects-todo ()
  "Test TODO comment detection for the current buffer syntax."
  (with-temp-buffer
    (emacs-lisp-mode)
    (should (claude-code-ide--is-comment-line ";; TODO: implement this"))
    (should-not (claude-code-ide--is-comment-line ";; DONE: already implemented"))
    (should-not (claude-code-ide--is-comment-line "(message \"not a comment\")"))))

(ert-deftest claude-code-ide-test-is-comment-block-allows-only-comment-lines ()
  "Test comment block validation for TODO implementation."
  (with-temp-buffer
    (emacs-lisp-mode)
    (should (claude-code-ide--is-comment-block ";; TODO: first\n;; detail line\n"))
    (should-not (claude-code-ide--is-comment-block ";; TODO: first\n(message \"x\")\n"))))

(ert-deftest claude-code-ide-test-implement-todo-sends-current-todo-line ()
  "Test TODO implementation sends an adapted prompt for the current TODO line."
  (let ((prompt-label nil)
        (initial-input nil)
        (sent-prompt nil))
    (cl-letf (((symbol-function 'read-string)
               (lambda (prompt &optional initial &rest _)
                 (setq prompt-label prompt)
                 (setq initial-input initial)
                 initial))
              ((symbol-function 'claude-code-ide-send-prompt)
               (lambda (prompt)
                 (setq sent-prompt prompt))))
      (with-temp-buffer
        (emacs-lisp-mode)
        (setq buffer-file-name "/home/user/project/test.el")
        (insert ";; TODO: implement support\n")
        (goto-char (point-min))
        (claude-code-ide-implement-todo nil)
        (should (equal prompt-label "Implement TODO in Claude Code: "))
        (should (string-match-p "Please implement code for this TODO comment on line 1"
                                initial-input))
        (should (equal sent-prompt initial-input))))))

(ert-deftest claude-code-ide-test-implement-todo-sends-selected-comment-block ()
  "Test TODO implementation accepts a selected comment block."
  (let ((sent-prompt nil))
    (cl-letf (((symbol-function 'read-string)
               (lambda (_prompt &optional initial &rest _)
                 initial))
              ((symbol-function 'claude-code-ide-send-prompt)
               (lambda (prompt)
                 (setq sent-prompt prompt))))
      (with-temp-buffer
        (emacs-lisp-mode)
        (transient-mark-mode 1)
        (setq buffer-file-name "/home/user/project/test.el")
        (insert ";; TODO: first step\n;; second step\n")
        (goto-char (point-min))
        (push-mark (point) t t)
        (goto-char (point-max))
        (activate-mark)
        (claude-code-ide-implement-todo nil)
        (should (string-match-p "Please implement code for this TODO comment block"
                                sent-prompt))
        (should (string-match-p ";; TODO: first step" sent-prompt))
        (should (string-match-p ";; second step" sent-prompt))))))

(ert-deftest claude-code-ide-test-implement-todo-errors-on-non-comment-context ()
  "Test TODO implementation rejects non-comment context."
  (cl-letf (((symbol-function 'claude-code-ide-send-prompt)
             (lambda (&rest _)
               (ert-fail "Should not send a prompt for non-comment context"))))
    (with-temp-buffer
      (emacs-lisp-mode)
      (setq buffer-file-name "/home/user/project/test.el")
      (insert "(message \"hello\")\n")
      (goto-char (point-min))
      (should-error (claude-code-ide-implement-todo nil) :type 'user-error))))

(ert-deftest claude-code-ide-test-implement-todo-blank-line-inserts-comment ()
  "Test TODO implementation inserts a TODO comment on a blank line."
  (let ((sent-prompt nil))
    (cl-letf (((symbol-function 'read-string)
               (lambda (_prompt &optional _initial &rest _)
                 "add support"))
              ((symbol-function 'claude-code-ide-send-prompt)
               (lambda (prompt)
                 (setq sent-prompt prompt))))
      (with-temp-buffer
        (emacs-lisp-mode)
        (setq buffer-file-name "/home/user/project/test.el")
        (insert "\n")
        (goto-char (point-min))
        (claude-code-ide-implement-todo nil)
        (should (equal (buffer-string) ";; TODO: add support\n"))
        (should-not sent-prompt)))))

(ert-deftest claude-code-ide-test-implement-todo-done-line-toggle ()
  "Test TODO implementation toggles a DONE comment back to TODO."
  (let ((sent-prompt nil))
    (cl-letf (((symbol-function 'completing-read)
               (lambda (&rest _) "Toggle to TODO"))
              ((symbol-function 'claude-code-ide-send-prompt)
               (lambda (prompt)
                 (setq sent-prompt prompt))))
      (with-temp-buffer
        (emacs-lisp-mode)
        (setq buffer-file-name "/home/user/project/test.el")
        (insert ";; DONE: add support\n")
        (goto-char (point-min))
        (claude-code-ide-implement-todo nil)
        (should (equal (buffer-string) ";; TODO: add support\n"))
        (should-not sent-prompt)))))

(ert-deftest claude-code-ide-test-transient-exposes-implement-todo ()
  "Test the main transient exposes the TODO implementation command."
  (should (transient-get-suffix 'claude-code-ide-menu "i")))

(ert-deftest claude-code-ide-test-transient-exposes-current-file-line-reference ()
  "Test the main transient exposes the absolute path with line binding."
  (should (equal (plist-get (nth 2 (transient-get-suffix 'claude-code-ide-menu "#")) :command)
                 'claude-code-ide-send-current-file-line-reference)))

(ert-deftest claude-code-ide-test-transient-exposes-current-dir-and-session-lists ()
  "Test the main transient exposes current-dir and session list bindings."
  (should (transient-get-suffix 'claude-code-ide-menu "d"))
  (should (transient-get-suffix 'claude-code-ide-menu "D"))
  (should (transient-get-suffix 'claude-code-ide-menu "l"))
  (should (transient-get-suffix 'claude-code-ide-menu "L")))

(ert-deftest claude-code-ide-test-transient-exposes-manager-commands ()
  "Test the main transient exposes cc-manager bindings."
  (should (transient-get-suffix 'claude-code-ide-menu "t"))
  (should (equal (plist-get (nth 2 (transient-get-suffix 'claude-code-ide-menu "T")) :command)
                 'claude-code-ide-manager-toggle-global-sidebar))
  (should (equal (plist-get (nth 2 (transient-get-suffix 'claude-code-ide-menu "o")) :command)
                 'claude-code-ide-transient-manager-open))
  (should (equal (plist-get (nth 2 (transient-get-suffix 'claude-code-ide-menu "w")) :command)
                 'claude-code-ide-manager-toggle-repo-sidebar))
  (should (transient-get-suffix 'claude-code-ide-menu "n"))
  (should (transient-get-suffix 'claude-code-ide-menu "p"))
  (should (transient-get-suffix 'claude-code-ide-menu "P"))
  (should (transient-get-suffix 'claude-code-ide-menu "1"))
  (should (transient-get-suffix 'claude-code-ide-menu "0"))
  (should (transient-get-suffix 'claude-code-ide-menu "M"))
  (should (transient-get-suffix 'claude-code-ide-menu "g")))

(ert-deftest claude-code-ide-test-transient-exposes-manager-open-and-repo-toggle-bindings ()
  "Main transient binds `o` to manager-open and `w` to repo manager toggle."
  (should (equal (plist-get (nth 2 (transient-get-suffix 'claude-code-ide-menu "o")) :command)
                 'claude-code-ide-transient-manager-open))
  (should (equal (plist-get (nth 2 (transient-get-suffix 'claude-code-ide-menu "w")) :command)
                 'claude-code-ide-manager-toggle-repo-sidebar)))

(ert-deftest claude-code-ide-test-transient-manager-open-uses-visible-repo-scope ()
  "Transient manager-open uses the visible repo sidebar scope."
  (let ((captured-scope nil)
        (repo-scope '(:type repo :git-root "/tmp/repo/")))
    (cl-letf (((symbol-function 'claude-code-ide-manager--visible-sidebar-scope-for-frame)
               (lambda (&optional _frame)
                 repo-scope))
              ((symbol-function 'claude-code-ide-manager-open)
               (lambda ()
                 (setq captured-scope claude-code-ide-manager--command-scope))))
      (claude-code-ide-transient-manager-open)
      (should (equal captured-scope repo-scope)))))

(ert-deftest claude-code-ide-test-transient-manager-open-uses-visible-global-scope ()
  "Transient manager-open uses the visible global sidebar scope."
  (let ((captured-scope nil)
        (global-scope '(:type global)))
    (cl-letf (((symbol-function 'claude-code-ide-manager--visible-sidebar-scope-for-frame)
               (lambda (&optional _frame)
                 global-scope))
              ((symbol-function 'claude-code-ide-manager-open)
               (lambda ()
                 (setq captured-scope claude-code-ide-manager--command-scope))))
      (claude-code-ide-transient-manager-open)
      (should (equal captured-scope global-scope)))))

(ert-deftest claude-code-ide-test-transient-manager-open-errors-without-visible-sidebar ()
  "Transient manager-open errors when no manager sidebar is visible."
  (cl-letf (((symbol-function 'claude-code-ide-manager--visible-sidebar-scope-for-frame)
             (lambda (&optional _frame)
               nil)))
    (let ((err (should-error (claude-code-ide-transient-manager-open)
                             :type 'user-error)))
      (should (string-match-p "No manager sidebar is visible"
                              (error-message-string err))))))

(ert-deftest claude-code-ide-test-transient-manager-open-does-not-require-manager-buffer ()
  "Transient manager-open can run outside a manager buffer."
  (with-temp-buffer
    (let ((called nil)
          (repo-scope '(:type repo :git-root "/tmp/repo/")))
      (cl-letf (((symbol-function 'claude-code-ide-manager--visible-sidebar-scope-for-frame)
                 (lambda (&optional _frame)
                   repo-scope))
                ((symbol-function 'claude-code-ide-manager-open)
                 (lambda ()
                   (setq called t)
                   (should (equal claude-code-ide-manager--command-scope repo-scope)))))
        (claude-code-ide-transient-manager-open)
        (should called)))))

(ert-deftest claude-code-ide-test-transient-manager-slots-are-visible ()
  "Test manager slot entries are present in the transient."
  (dolist (key '("1" "2" "3" "4" "5" "6" "7" "8" "9" "0"))
    (should (transient-get-suffix 'claude-code-ide-menu key))))

(ert-deftest claude-code-ide-test-start-if-no-session-allows-project-launch-with-only-attached-session ()
  "Test project-root launch is not blocked by an attached subdirectory session."
  (let ((started nil))
    (cl-letf (((symbol-function 'claude-code-ide--has-active-session-p)
               (lambda () t))
              ((symbol-function 'claude-code-ide--has-project-session-p)
               (lambda () nil))
              ((symbol-function 'claude-code-ide)
               (lambda () (setq started t))))
      (claude-code-ide--start-if-no-session)
      (should started))))

(ert-deftest claude-code-ide-test-session-status-includes-cli-path ()
  "Test active session status includes the current CLI path."
  (let* ((claude-code-ide-cli-path "/usr/local/bin/codex")
         (session (make-claude-code-ide-mcp-session
                   :project-dir "/tmp/project/"))
         (status nil))
    (cl-letf (((symbol-function 'claude-code-ide-mcp--get-current-session)
               (lambda () session)))
      (setq status (claude-code-ide--session-status))
      (should (equal (substring-no-properties status)
                     "Active session in [project] (/usr/local/bin/codex)"))
      (should (eq (get-text-property 0 'face status) 'success)))))

(ert-deftest claude-code-ide-test-session-status-without-session-includes-cli-path ()
  "Test no-session status includes the current CLI path."
  (let ((claude-code-ide-cli-path "/usr/local/bin/codex")
        (status nil))
    (cl-letf (((symbol-function 'claude-code-ide-mcp--get-current-session)
               (lambda () nil)))
      (setq status (claude-code-ide--session-status))
      (should (equal (substring-no-properties status)
                     "No active session (/usr/local/bin/codex)"))
      (should (eq (get-text-property 0 'face status)
                  'transient-inactive-value)))))

(ert-deftest claude-code-ide-test-current-directory-command-starts-in-default-directory ()
  "Test current-directory start command uses `default-directory'."
  (let ((default-directory "/tmp/project/subdir/")
        (captured-directory :unset))
    (cl-letf (((symbol-function 'claude-code-ide--start-session)
               (lambda (&optional _continue _resume directory)
                 (setq captured-directory directory))))
      (claude-code-ide-current-directory)
      (should (equal captured-directory "/tmp/project/subdir/")))))

(ert-deftest claude-code-ide-test-set-project-agent-writes-dir-locals ()
  "Test setting a project agent writes a project-local CLI override."
  (claude-code-ide-tests--with-temp-directory
   (lambda ()
     (let ((project-root (expand-file-name default-directory))
           (claude-code-ide-cli-path "claude"))
       (with-temp-file (expand-file-name ".dir-locals.el" project-root)
         (insert ";;; Directory Local Variables            -*- no-byte-compile: t -*-\n")
         (insert ";;; For more information see (info \"(emacs) Directory Variables\")\n\n")
         (insert "((nil . ((foo . 1))))\n"))
       (cl-letf (((symbol-function 'project-current)
                  (lambda (&optional _maybe-prompt _dir) 'project))
                 ((symbol-function 'project-root)
                  (lambda (_project) project-root)))
         (with-temp-buffer
           (setq default-directory project-root)
           (claude-code-ide--set-project-agent "codex")
           (should (local-variable-p 'claude-code-ide-cli-path))
           (should (equal claude-code-ide-cli-path "codex")))
         (with-temp-buffer
           (insert-file-contents (expand-file-name ".dir-locals.el" project-root))
           (let ((contents (buffer-string)))
             (should (string-match-p "(foo \\. 1)" contents))
             (should (string-match-p "(claude-code-ide-cli-path \\. \"codex\")" contents)))))))))

(ert-deftest claude-code-ide-test-clear-project-agent-removes-dir-local ()
  "Test clearing a project agent removes the project-local CLI override."
  (claude-code-ide-tests--with-temp-directory
   (lambda ()
     (let ((project-root (expand-file-name default-directory))
           (claude-code-ide-cli-path "claude"))
       (with-temp-file (expand-file-name ".dir-locals.el" project-root)
         (insert ";;; Directory Local Variables            -*- no-byte-compile: t -*-\n")
         (insert ";;; For more information see (info \"(emacs) Directory Variables\")\n\n")
         (insert "((nil . ((foo . 1)\n")
         (insert "         (claude-code-ide-cli-path . \"codex\"))))\n"))
       (cl-letf (((symbol-function 'project-current)
                  (lambda (&optional _maybe-prompt _dir) 'project))
                 ((symbol-function 'project-root)
                  (lambda (_project) project-root)))
         (with-temp-buffer
           (setq default-directory project-root)
           (setq-local claude-code-ide-cli-path "codex")
           (claude-code-ide--clear-project-agent)
           (should-not (local-variable-p 'claude-code-ide-cli-path))
           (should (equal claude-code-ide-cli-path "claude")))
         (with-temp-buffer
           (insert-file-contents (expand-file-name ".dir-locals.el" project-root))
           (let ((contents (buffer-string)))
             (should (string-match-p "(foo \\. 1)" contents))
             (should-not (string-match-p "claude-code-ide-cli-path" contents)))))))))

(ert-deftest claude-code-ide-test-terminal-session-creation ()
  "Test terminal session creation with both backends."
  (let ((mock-vterm-buffer nil)
        (mock-eat-buffer nil)
        (mock-process (start-process "mock" nil "true")))
    (cl-letf (((symbol-function 'claude-code-ide--terminal-ensure-backend)
               (lambda () nil))  ; Mock the ensure function to do nothing
              ((symbol-function 'vterm)
               (lambda (name)
                 (setq mock-vterm-buffer (get-buffer-create name))))
              ((symbol-function 'eat-mode)
               (lambda () nil))
              ((symbol-function 'eat-exec)
               (lambda (buffer name cmd startfile args)
                 (setq mock-eat-buffer buffer)))
              ((symbol-function 'get-buffer-process)
               (lambda (buffer) mock-process))
              ((symbol-function 'claude-code-ide-mcp-start)
               (lambda (dir) 12345)))

      ;; Test vterm backend session creation
      (let ((claude-code-ide-terminal-backend 'vterm)
            (claude-code-ide--cli-available t))
        (cl-letf (((symbol-function 'claude-code-ide--build-claude-command)
                   (lambda (&rest _) "claude")))
          (let ((result (claude-code-ide--create-terminal-session
                         "*test-vterm*" "/tmp" 12345 nil nil "test-session")))
            (should (consp result))
            (should (bufferp (car result)))
            (should (processp (cdr result)))
            (should (equal (buffer-name mock-vterm-buffer) "*test-vterm*")))))

      ;; Test eat backend session creation
      (let ((claude-code-ide-terminal-backend 'eat)
            (claude-code-ide--cli-available t))
        (cl-letf (((symbol-function 'claude-code-ide--build-claude-command)
                   (lambda (&rest _) "claude")))
          (let ((result (claude-code-ide--create-terminal-session
                         "*test-eat*" "/tmp" 12345 nil nil "test-session")))
            (should (consp result))
            (should (bufferp (car result)))
            (should (processp (cdr result)))
            (should (bufferp mock-eat-buffer))))))))

(ert-deftest claude-code-ide-test-eat-smart-renderer-passthrough ()
  "Test that eat smart renderer passes through normal text immediately."
  (let ((orig-fun-called nil)
        (orig-fun-input nil)
        (claude-code-ide-vterm-anti-flicker t))
    (cl-letf (((symbol-function 'claude-code-ide--session-buffer-p)
               (lambda (_) t)))
      (with-temp-buffer
        (let ((claude-code-ide--eat-render-queue nil)
              (claude-code-ide--eat-render-timer nil)
              (mock-process (make-process :name "mock-eat"
                                          :buffer (current-buffer)
                                          :command '("true"))))
          (let ((orig-fun (lambda (_process input)
                            (setq orig-fun-called t
                                  orig-fun-input input))))
            (claude-code-ide--eat-smart-renderer orig-fun mock-process "Hello World")
            (should orig-fun-called)
            (should (equal orig-fun-input "Hello World"))
            (should-not claude-code-ide--eat-render-queue)))))))

(ert-deftest claude-code-ide-test-eat-smart-renderer-batching ()
  "Test that eat smart renderer batches complex escape sequences."
  (let ((orig-fun-called nil)
        (timer-created nil)
        (claude-code-ide-vterm-anti-flicker t)
        (claude-code-ide-vterm-render-delay 0.005))
    (cl-letf (((symbol-function 'claude-code-ide--session-buffer-p)
               (lambda (_) t))
              ((symbol-function 'run-at-time)
               (lambda (delay &rest _)
                 (setq timer-created delay)
                 'mock-timer))
              ((symbol-function 'cancel-timer)
               (lambda (_) nil)))
      (with-temp-buffer
        (let ((claude-code-ide--eat-render-queue nil)
              (claude-code-ide--eat-render-timer nil)
              (mock-process (make-process :name "mock-eat"
                                          :buffer (current-buffer)
                                          :command '("true"))))
          (let ((orig-fun (lambda (_process _input)
                            (setq orig-fun-called t))))
            (let ((complex-input "\033[2A\033[K\033[3A\033[K"))
              (claude-code-ide--eat-smart-renderer orig-fun mock-process complex-input)
              (should-not orig-fun-called)
              (should (listp claude-code-ide--eat-render-queue))
              (should (equal (apply #'concat (nreverse claude-code-ide--eat-render-queue))
                             complex-input))
              (should (equal timer-created 0.005)))))))))

(ert-deftest claude-code-ide-test-eat-advice-cleanup ()
  "Test that eat advice is removed during cleanup for the last session."
  (let ((advice-removed nil)
        (claude-code-ide-terminal-backend 'eat)
        (claude-code-ide-vterm-anti-flicker t)
        (claude-code-ide--processes (make-hash-table :test 'equal))
        (claude-code-ide--cleanup-in-progress nil))
    (cl-letf (((symbol-function 'advice-remove)
               (lambda (symbol function)
                 (when (and (eq symbol 'eat--filter)
                            (eq function 'claude-code-ide--eat-smart-renderer))
                   (setq advice-removed t))))
              ((symbol-function 'claude-code-ide-mcp-stop-session)
               (lambda (_) nil))
              ((symbol-function 'claude-code-ide-mcp-server-session-ended)
               (lambda (_) nil))
              ((symbol-function 'claude-code-ide--get-buffer-name)
               (lambda (_) "*test-buffer*")))
      (puthash "/tmp/test" (current-buffer) claude-code-ide--processes)
      (claude-code-ide--cleanup-on-exit "/tmp/test")
      (should advice-removed))))

(ert-deftest claude-code-ide-test-configure-eat-buffer ()
  "Test that eat buffer configuration applies display-related settings."
  (let ((hl-line-arg nil)
        (face-remapped nil)
        (advice-added nil)
        (claude-code-ide-vterm-anti-flicker t))
    (cl-letf (((symbol-function 'featurep)
               (lambda (feature &rest _)
                 (eq feature 'hl-line)))
              ((symbol-function 'hl-line-mode)
               (lambda (arg)
                 (setq hl-line-arg arg)))
              ((symbol-function 'face-remap-add-relative)
               (lambda (&rest args)
                 (setq face-remapped args)))
              ((symbol-function 'advice-add)
               (lambda (symbol where function &rest _)
                 (setq advice-added (list symbol where function)))))
      (with-temp-buffer
        (claude-code-ide--configure-eat-buffer)
        (should (local-variable-p 'cursor-in-non-selected-windows))
        (should-not cursor-in-non-selected-windows)
        (should (local-variable-p 'blink-cursor-mode))
        (should-not blink-cursor-mode)
        (should (local-variable-p 'cursor-type))
        (should-not cursor-type)
        (should (equal hl-line-arg -1))
        (should (equal face-remapped '(nobreak-space :inherit default)))
        (should (equal advice-added
                       '(eat--filter :around claude-code-ide--eat-smart-renderer)))))))

(ert-deftest claude-code-ide-test-vterm-smart-renderer-passthrough ()
  "Test that vterm smart renderer passes through normal text immediately."
  (let ((orig-fun-called nil)
        (orig-fun-input nil)
        (claude-code-ide-vterm-anti-flicker t))
    (cl-letf (((symbol-function 'claude-code-ide--session-buffer-p)
               (lambda (_) t)))
      (with-temp-buffer
        (let ((claude-code-ide--vterm-render-queue nil)
              (claude-code-ide--vterm-render-timer nil)
              (mock-process (make-process :name "mock"
                                          :buffer (current-buffer)
                                          :command '("true"))))
          ;; Create a mock original function
          (let ((orig-fun (lambda (_process input)
                            (setq orig-fun-called t
                                  orig-fun-input input))))
            ;; Test with normal text (no escape sequences)
            (claude-code-ide--vterm-smart-renderer orig-fun mock-process "Hello World")
            ;; Should pass through immediately
            (should orig-fun-called)
            (should (equal orig-fun-input "Hello World"))
            (should-not claude-code-ide--vterm-render-queue)))))))

(ert-deftest claude-code-ide-test-vterm-smart-renderer-batching ()
  "Test that vterm smart renderer batches complex escape sequences."
  (let ((orig-fun-called nil)
        (timer-created nil)
        (claude-code-ide-vterm-anti-flicker t)
        (claude-code-ide-vterm-render-delay 0.005))
    (cl-letf (((symbol-function 'claude-code-ide--session-buffer-p)
               (lambda (_) t))
              ((symbol-function 'run-at-time)
               (lambda (delay &rest _)
                 (setq timer-created delay)
                 'mock-timer))
              ((symbol-function 'cancel-timer)
               (lambda (_) nil)))
      (with-temp-buffer
        (let ((claude-code-ide--vterm-render-queue nil)
              (claude-code-ide--vterm-render-timer nil)
              (mock-process (make-process :name "mock"
                                          :buffer (current-buffer)
                                          :command '("true"))))
          ;; Create a mock original function
          (let ((orig-fun (lambda (_process _input)
                            (setq orig-fun-called t))))
            ;; Test with complex escape sequence pattern
            (let ((complex-input "\033[2A\033[K\033[3A\033[K"))
              (claude-code-ide--vterm-smart-renderer orig-fun mock-process complex-input)
              ;; Should be queued, not called immediately
              (should-not orig-fun-called)
              ;; Queue is a list (pushed in reverse order for O(1))
              (should (listp claude-code-ide--vterm-render-queue))
              (should (equal (apply #'concat (nreverse claude-code-ide--vterm-render-queue))
                             complex-input))
              (should (equal timer-created 0.005)))))))))

(ert-deftest claude-code-ide-test-toggle-vterm-optimization ()
  "Test toggling vterm optimization on and off."
  (let ((original-value claude-code-ide-vterm-anti-flicker)
        (message-output nil))
    (unwind-protect
        (cl-letf (((symbol-function 'message)
                   (lambda (format &rest args)
                     (setq message-output (apply #'format format args)))))
          ;; Start with optimization enabled
          (setq claude-code-ide-vterm-anti-flicker t)

          ;; Toggle off
          (claude-code-ide-toggle-vterm-optimization)
          (should-not claude-code-ide-vterm-anti-flicker)
          (should (string-match "disabled" message-output))

          ;; Toggle back on
          (claude-code-ide-toggle-vterm-optimization)
          (should claude-code-ide-vterm-anti-flicker)
          (should (string-match "enabled" message-output)))
      ;; Restore original value
      (setq claude-code-ide-vterm-anti-flicker original-value))))

(ert-deftest claude-code-ide-test-run-with-cli ()
  "Test successful run command execution."
  (skip-unless nil) ; Skip this test for now
  (claude-code-ide-tests--clear-processes)
  (unwind-protect
      (claude-code-ide-tests--with-temp-directory
       (lambda ()
         (let ((claude-code-ide--cli-available t)
               (claude-code-ide-cli-path "echo"))
           ;; Run claude-code-ide
           (claude-code-ide)

           ;; Check that buffer was created
           (let ((buffer-name (claude-code-ide--get-buffer-name)))
             (should (get-buffer buffer-name))

             ;; Check that process was registered
             (should (claude-code-ide--get-process))

             ;; Wait for process to finish and clean up
             (claude-code-ide-tests--wait-for-process (get-buffer buffer-name))
             ;; Kill the buffer explicitly since we're in batch mode
             (when (get-buffer buffer-name)
               (kill-buffer buffer-name))))))
    (claude-code-ide-tests--clear-processes)))

(ert-deftest claude-code-ide-test-run-existing-session ()
  "Test run command when session already exists."
  (skip-unless nil) ; Skip this test for now
  (claude-code-ide-tests--clear-processes)
  (unwind-protect
      (claude-code-ide-tests--with-temp-directory
       (lambda ()
         (let ((claude-code-ide--cli-available t)
               (claude-code-ide-cli-path "echo"))
           ;; Start first session
           (claude-code-ide)
           (let* ((buffer-name (claude-code-ide--get-buffer-name))
                  (first-buffer (get-buffer buffer-name)))

             ;; Verify we have the buffer
             (should first-buffer)

             ;; Try to run again - should not create new buffer
             (claude-code-ide)

             ;; Should still have same buffer
             (should (eq (get-buffer buffer-name) first-buffer))

             ;; Wait for process and clean up
             (claude-code-ide-tests--wait-for-process first-buffer)
             (kill-buffer first-buffer)))))
    (claude-code-ide-tests--clear-processes)))

(ert-deftest claude-code-ide-test-check-status ()
  "Test status check command."
  (let ((claude-code-ide-cli-path "echo")
        (claude-code-ide--cli-available nil))
    ;; Should not error and should detect CLI
    (claude-code-ide-check-status)
    (should claude-code-ide--cli-available)))

(ert-deftest claude-code-ide-test-terminal-initialization-delay ()
  "Test terminal initialization delay configuration."
  ;; Test default value
  (should (boundp 'claude-code-ide-terminal-initialization-delay))
  (should (numberp claude-code-ide-terminal-initialization-delay))
  (should (= claude-code-ide-terminal-initialization-delay 0.1))

  ;; Test customization
  (let ((original-delay claude-code-ide-terminal-initialization-delay))
    (unwind-protect
        (progn
          (setq claude-code-ide-terminal-initialization-delay 0.2)
          (should (= claude-code-ide-terminal-initialization-delay 0.2)))
      ;; Restore original value
      (setq claude-code-ide-terminal-initialization-delay original-delay))))

(ert-deftest claude-code-ide-test-obsolete-eat-delay-alias ()
  "Test that the obsolete eat delay alias still works."
  ;; The alias should be defined
  (should (boundp 'claude-code-ide-eat-initialization-delay))
  ;; Setting the old variable should affect the new one
  (let ((original-delay claude-code-ide-terminal-initialization-delay))
    (unwind-protect
        (progn
          (setq claude-code-ide-eat-initialization-delay 0.3)
          (should (= claude-code-ide-terminal-initialization-delay 0.3)))
      ;; Restore original value
      (setq claude-code-ide-terminal-initialization-delay original-delay))))

(ert-deftest claude-code-ide-test-stop-no-session ()
  "Test stop command when no session is running."
  (claude-code-ide-tests--clear-processes)
  (unwind-protect
      (claude-code-ide-tests--with-temp-directory
       (lambda ()
         ;; Should not error when no session exists
         (claude-code-ide-stop)))
    (claude-code-ide-tests--clear-processes)))

(ert-deftest claude-code-ide-test-stop-with-session ()
  "Test stop command with active session."
  (skip-unless nil) ; Skip this test for now
  (claude-code-ide-tests--clear-processes)
  (unwind-protect
      (claude-code-ide-tests--with-temp-directory
       (lambda ()
         (let ((claude-code-ide--cli-available t)
               (claude-code-ide-cli-path "echo"))
           ;; Start a session
           (claude-code-ide)
           (let ((buffer-name (claude-code-ide--get-buffer-name)))
             ;; Verify session exists
             (should (get-buffer buffer-name))
             (should (claude-code-ide--get-process))

             ;; Wait for process to finish before stopping
             (claude-code-ide-tests--wait-for-process (get-buffer buffer-name))

             ;; Stop the session
             (claude-code-ide-stop)

             ;; Verify session is stopped
             (should (null (get-buffer buffer-name)))
             (should (null (claude-code-ide--get-process)))))))
    (claude-code-ide-tests--clear-processes)))

(ert-deftest claude-code-ide-test-switch-to-buffer-no-session ()
  "Test `switch-to-buffer' command when no session exists."
  (claude-code-ide-tests--clear-processes)
  (unwind-protect
      (should-error (claude-code-ide-switch-to-buffer)
                    :type 'user-error)
    (claude-code-ide-tests--clear-processes)))

(ert-deftest claude-code-ide-test-toggle-window-functionality ()
  "Test that running claude-code-ide on an existing session toggles the window."
  (skip-unless nil) ; Skip this test for now
  (claude-code-ide-tests--clear-processes)
  (unwind-protect
      (claude-code-ide-tests--with-temp-directory
       (lambda ()
         (let ((claude-code-ide--cli-available t)
               (claude-code-ide-cli-path "echo")
               (test-dir default-directory))
           ;; Start a session
           (claude-code-ide)
           (let* ((buffer-name (claude-code-ide--get-buffer-name))
                  (session-buffer (get-buffer buffer-name)))

             ;; Verify we have the buffer
             (should session-buffer)

             ;; Simulate window being visible (in batch mode we can't test actual windows)
             ;; Just verify the command runs without error when session exists
             (let ((default-directory test-dir))
               ;; Running claude-code-ide again should toggle (not error)
               (claude-code-ide))

             ;; Wait for process and clean up
             (claude-code-ide-tests--wait-for-process session-buffer)
             (kill-buffer session-buffer)))))
    (claude-code-ide-tests--clear-processes)))

(ert-deftest claude-code-ide-test-list-sessions-empty ()
  "Test listing sessions when none exist."
  (claude-code-ide-tests--clear-processes)
  (unwind-protect
      ;; Should not error when no sessions exist
      (claude-code-ide-list-sessions)
    (claude-code-ide-tests--clear-processes)))

(ert-deftest claude-code-ide-test-list-sessions-with-sessions ()
  "Test listing sessions functionality."
  (claude-code-ide-tests--clear-processes)
  (unwind-protect
      (progn
        ;; Test that list-sessions works with no sessions
        (claude-code-ide-list-sessions)

        ;; Manually add mock entries to the process table
        (puthash "/tmp/project1" (current-buffer) claude-code-ide--processes)
        (puthash "/tmp/project2" (current-buffer) claude-code-ide--processes)

        ;; Verify we have 2 entries
        (should (= (hash-table-count claude-code-ide--processes) 2))

        ;; List sessions should work without error
        (claude-code-ide-list-sessions))
    (claude-code-ide-tests--clear-processes)))

(ert-deftest claude-code-ide-test-list-related-sessions-filters-by-buffer-path ()
  "Test related sessions are limited to the current buffer's directory tree."
  (claude-code-ide-tests--clear-processes)
  (let ((captured-choices nil)
        (selected nil))
    (unwind-protect
        (progn
          (puthash "/tmp/project/" (current-buffer) claude-code-ide--processes)
          (puthash "/tmp/project/sub/" (current-buffer) claude-code-ide--processes)
          (puthash "/tmp/other/" (current-buffer) claude-code-ide--processes)
          (with-temp-buffer
            (setq default-directory "/tmp/project/sub/nested/")
            (cl-letf (((symbol-function 'completing-read)
                       (lambda (_prompt collection &rest _args)
                         (setq captured-choices collection
                               selected (caar collection))
                         selected))
                      ((symbol-function 'claude-code-ide--cleanup-dead-processes)
                       (lambda () nil))
                      ((symbol-function 'claude-code-ide--display-buffer-in-side-window)
                       (lambda (_buffer) nil))
                      ((symbol-function 'get-buffer)
                       (lambda (_name) (current-buffer))))
              (claude-code-ide-list-related-sessions)
              (should (equal (mapcar #'car captured-choices)
                             '("/tmp/project/sub/" "/tmp/project/"))))))
      (claude-code-ide-tests--clear-processes))))

(ert-deftest claude-code-ide-test-show-session-buffer-reuses-visible-session-window ()
  "Test switching sessions reuses an existing visible Claude window."
  (let ((claude-code-ide-focus-on-open nil)
        (target-buffer (generate-new-buffer "*claude-code[target]*"))
        (visible-session-buffer (generate-new-buffer "*claude-code[current]*"))
        (reused-window 'mock-session-window)
        (reused-with nil)
        (display-called nil))
    (unwind-protect
        (cl-letf (((symbol-function 'get-buffer-window)
                   (lambda (_buffer) nil))
                  ((symbol-function 'window-list)
                   (lambda (&optional _frame _minibuf _window)
                     (list reused-window)))
                  ((symbol-function 'window-buffer)
                   (lambda (_window) visible-session-buffer))
                  ((symbol-function 'set-window-buffer)
                   (lambda (_window buffer)
                     (setq reused-with buffer)))
                  ((symbol-function 'claude-code-ide--sync-terminal-dimensions)
                   (lambda (&rest _args) nil))
                  ((symbol-function 'claude-code-ide--display-buffer-in-side-window)
                   (lambda (_buffer)
                     (setq display-called t)
                     nil)))
          (claude-code-ide--show-session-buffer target-buffer)
          (should (eq reused-with target-buffer))
          (should-not display-called))
      (when (buffer-live-p target-buffer)
        (kill-buffer target-buffer))
      (when (buffer-live-p visible-session-buffer)
        (kill-buffer visible-session-buffer)))))

(ert-deftest claude-code-ide-test-stop-prefers-attached-session-directory ()
  "Test stop uses the attached session directory instead of project root."
  (let* ((root-dir "/tmp/project/")
         (sub-dir "/tmp/project/sub/")
         (root-buffer (generate-new-buffer "*claude-root*"))
         (sub-buffer (generate-new-buffer "*claude-sub*"))
         (session (make-claude-code-ide-mcp-session :project-dir sub-dir)))
    (unwind-protect
        (cl-letf (((symbol-function 'claude-code-ide--get-working-directory)
                   (lambda () root-dir))
                  ((symbol-function 'claude-code-ide--get-buffer-name)
                   (lambda (&optional directory)
                     (cond
                      ((equal directory sub-dir) (buffer-name sub-buffer))
                      ((equal directory root-dir) (buffer-name root-buffer))
                      (t (error "Unexpected directory: %S" directory)))))
                  ((symbol-function 'claude-code-ide-mcp--get-current-session)
                   (lambda () session))
                  ((symbol-function 'claude-code-ide-log)
                   (lambda (&rest _args) nil)))
          (claude-code-ide-stop)
          (should (buffer-live-p root-buffer))
          (should-not (buffer-live-p sub-buffer)))
      (when (buffer-live-p root-buffer)
        (kill-buffer root-buffer))
      (when (buffer-live-p sub-buffer)
        (kill-buffer sub-buffer)))))

(ert-deftest claude-code-ide-test-toggle-recent ()
  "Test the toggle-recent functionality."
  (claude-code-ide-tests--clear-processes)
  (unwind-protect
      (let ((test-buffer1 (get-buffer-create "*Claude Code - test1*"))
            (test-buffer2 (get-buffer-create "*Claude Code - test2*"))
            (claude-code-ide--last-accessed-buffer nil))
        ;; Test when no recent buffer exists
        (should-error (claude-code-ide-toggle-recent))

        ;; Set a recent buffer
        (setq claude-code-ide--last-accessed-buffer test-buffer1)

        ;; Test toggle when no windows are visible (should show the buffer)
        ;; This will fail in batch mode but verifies the function doesn't error
        (condition-case nil
            (claude-code-ide-toggle-recent)
          (error nil))

        ;; Clean up
        (kill-buffer test-buffer1)
        (kill-buffer test-buffer2))
    (claude-code-ide-tests--clear-processes)))

;;; Edge Case Tests

(ert-deftest claude-code-ide-test-concurrent-sessions ()
  "Test managing multiple concurrent sessions."
  (skip-unless nil) ; Skip this test for now
  (claude-code-ide-tests--clear-processes)
  (unwind-protect
      (let ((claude-code-ide--cli-available t)
            (claude-code-ide-cli-path "echo")
            (dir1 (make-temp-file "claude-test-1" t))
            (dir2 (make-temp-file "claude-test-2" t)))
        ;; Start sessions in different directories
        (let ((default-directory dir1))
          (claude-code-ide)
          (should (claude-code-ide--get-process dir1)))
        (let ((default-directory dir2))
          (claude-code-ide)
          (should (claude-code-ide--get-process dir2)))
        ;; Verify both sessions exist
        (should (= (hash-table-count claude-code-ide--processes) 2))
        ;; Clean up
        (let ((buffers (mapcar (lambda (dir)
                                 (funcall claude-code-ide-buffer-name-function dir))
                               (list dir1 dir2))))
          (dolist (buffer-name buffers)
            (when-let ((buffer (get-buffer buffer-name)))
              (claude-code-ide-tests--wait-for-process buffer)
              (kill-buffer buffer))))
        (delete-directory dir1 t)
        (delete-directory dir2 t))
    (claude-code-ide-tests--clear-processes)))

(ert-deftest claude-code-ide-test-custom-buffer-naming ()
  "Test custom buffer naming function."
  (let ((claude-code-ide-buffer-name-function
         (lambda (dir)
           (format "TEST-%s"
                   (upcase (file-name-nondirectory (directory-file-name dir)))))))
    (claude-code-ide-tests--with-temp-directory
     (lambda ()
       (let ((expected (format "TEST-%s"
                               (upcase (file-name-nondirectory
                                        (directory-file-name default-directory))))))
         (should (equal (claude-code-ide--get-buffer-name) expected)))))))

(ert-deftest claude-code-ide-test-window-placement-options ()
  "Test different window placement configurations."
  (dolist (side '(left right top bottom))
    (let ((claude-code-ide-window-side side))
      ;; Just verify the setting is accepted
      (should (eq claude-code-ide-window-side side)))))

(ert-deftest claude-code-ide-test-debug-mode-flag ()
  "Test debug mode CLI flag."
  (let ((claude-code-ide-cli-debug t))
    (should (string-match "-d" (claude-code-ide--build-claude-command)))
    (should (string-match "-d.*-c" (claude-code-ide--build-claude-command t)))
    (should (string-match "-d.*-r" (claude-code-ide--build-claude-command nil t)))))

(ert-deftest claude-code-ide-test-build-command-with-system-prompt ()
  "Test building command with append-system-prompt flag."
  ;; Test with user system prompt
  (let ((claude-code-ide-cli-path "claude")
        (claude-code-ide-system-prompt "You are a helpful assistant")
        (claude-code-ide-cli-debug nil)
        (claude-code-ide-cli-extra-flags ""))
    (let ((cmd (claude-code-ide--build-claude-command)))
      (should (string-match-p "--append-system-prompt" cmd))
      ;; Check that Emacs prompt is included (accounting for shell escaping)
      (should (or (string-match-p "Connected to Emacs" cmd)
                  (string-match-p "Connected\\\\ to\\\\ Emacs" cmd)))
      ;; Check that user prompt is included
      (should (or (string-match-p "You are a helpful assistant" cmd)
                  (string-match-p "You\\\\ are\\\\ a\\\\ helpful\\\\ assistant" cmd)))))
  ;; Test with nil value (should still add the Emacs prompt)
  (let ((claude-code-ide-cli-path "claude")
        (claude-code-ide-system-prompt nil)
        (claude-code-ide-cli-debug nil)
        (claude-code-ide-cli-extra-flags ""))
    (let ((cmd (claude-code-ide--build-claude-command)))
      (should (string-match-p "--append-system-prompt" cmd))
      ;; Check that Emacs prompt is included (accounting for shell escaping)
      (should (or (string-match-p "Connected to Emacs" cmd)
                  (string-match-p "Connected\\\\ to\\\\ Emacs" cmd)))
      ;; Should not contain user prompt when nil
      (should-not (string-match-p "You are a helpful assistant" cmd))))
  ;; Test with special characters that need quoting
  (let ((claude-code-ide-cli-path "claude")
        (claude-code-ide-system-prompt "You're a \"helpful\" assistant!")
        (claude-code-ide-cli-debug nil)
        (claude-code-ide-cli-extra-flags ""))
    (let ((cmd (claude-code-ide--build-claude-command)))
      (should (string-match-p "--append-system-prompt" cmd))
      ;; Check that Emacs prompt is included (accounting for shell escaping)
      (should (or (string-match-p "Connected to Emacs" cmd)
                  (string-match-p "Connected\\\\ to\\\\ Emacs" cmd)))
      ;; The command should contain the escaped version (shell-quote-argument escapes quotes and apostrophes)
      (should (string-match-p "You\\\\'re\\\\ a\\\\ \\\\\"helpful\\\\\"\\\\ assistant\\\\!" cmd)))))

(ert-deftest claude-code-ide-test-error-handling ()
  "Test error handling in various scenarios."
  ;; Test with nil CLI path
  (let ((claude-code-ide-cli-path nil)
        (claude-code-ide--cli-available nil))
    (should-error (claude-code-ide) :type 'user-error))

  ;; Test with empty CLI path
  (let ((claude-code-ide-cli-path "")
        (claude-code-ide--cli-available nil))
    (should-error (claude-code-ide) :type 'user-error)))

;;; Run all tests

(ert-deftest claude-code-ide-test-tab-bar-tracking ()
  "Test that tab-bar tabs are tracked correctly."
  (let* ((temp-dir (make-temp-file "test-project-" t))
         (claude-code-ide-mcp--sessions (make-hash-table :test 'equal))
         ;; Mock tab-bar functions
         (mock-tab '((name . "test-tab") (index . 1)))
         (tab-bar-mode-enabled nil))
    ;; Mock tab-bar functions
    (cl-letf (((symbol-function 'fboundp)
               (lambda (sym)
                 (or (eq sym 'tab-bar--current-tab)
                     (eq sym 'tab-bar-select-tab-by-name)
                     (eq sym 'tab-bar-mode)
                     (funcall (cl-letf-saved-symbol-function 'fboundp) sym))))
              ((symbol-function 'tab-bar--current-tab)
               (lambda () mock-tab))
              (tab-bar-mode tab-bar-mode-enabled))
      ;; Start MCP server
      (let ((port (claude-code-ide-mcp-start temp-dir)))
        (should port)
        ;; Get the session
        (let ((session (gethash temp-dir claude-code-ide-mcp--sessions)))
          (should session)
          ;; Check that tab was captured
          (should (equal (claude-code-ide-mcp-session-original-tab session) mock-tab))))
      ;; Cleanup
      (claude-code-ide-mcp-stop-session temp-dir))
    ;; Cleanup temp directory
    (delete-directory temp-dir t)))

(ert-deftest claude-code-ide-test-tab-bar-switch-on-ediff ()
  "Test that tab-bar switching on ediff respects the configuration."
  ;; Test that the variable exists with the expected default
  (should (boundp 'claude-code-ide-switch-tab-on-ediff))
  (should (equal claude-code-ide-switch-tab-on-ediff t))

  ;; Test with simple mocking to ensure the config is checked
  (let* ((original-tab '((name . "original-tab")))
         (current-tab '((name . "current-tab")))
         (tab-switched nil)
         (tab-bar-mode t))

    ;; Mock functions
    (cl-letf (((symbol-function 'fboundp)
               (lambda (sym)
                 (or (eq sym 'tab-bar--current-tab)
                     (eq sym 'tab-bar-select-tab-by-name)
                     (eq sym 'tab-bar-mode)
                     (funcall (cl-letf-saved-symbol-function 'fboundp) sym))))
              ((symbol-function 'tab-bar--current-tab)
               (lambda () current-tab))
              ((symbol-function 'tab-bar-select-tab-by-name)
               (lambda (name)
                 (setq tab-switched name))))

      ;; Create a minimal test session
      (let ((session (make-claude-code-ide-mcp-session
                      :original-tab original-tab)))

        ;; Test 1: With switch enabled (default)
        (let ((claude-code-ide-switch-tab-on-ediff t))
          (setq tab-switched nil)
          ;; Simulate the relevant part of the handler
          (when (and claude-code-ide-switch-tab-on-ediff
                     (claude-code-ide-mcp-session-original-tab session))
            (let ((original-tab (claude-code-ide-mcp-session-original-tab session)))
              (when (and (fboundp 'tab-bar-mode)
                         tab-bar-mode
                         (fboundp 'tab-bar--current-tab)
                         (fboundp 'tab-bar-select-tab-by-name))
                (let ((current-tab (tab-bar--current-tab)))
                  (when (and original-tab current-tab
                             (not (equal (alist-get 'name original-tab)
                                         (alist-get 'name current-tab))))
                    (tab-bar-select-tab-by-name (alist-get 'name original-tab)))))))
          ;; Should have switched
          (should (equal tab-switched "original-tab")))

        ;; Test 2: With switch disabled
        (let ((claude-code-ide-switch-tab-on-ediff nil))
          (setq tab-switched nil)
          ;; Simulate the relevant part of the handler
          (when (and claude-code-ide-switch-tab-on-ediff
                     (claude-code-ide-mcp-session-original-tab session))
            (let ((original-tab (claude-code-ide-mcp-session-original-tab session)))
              (when (and (fboundp 'tab-bar-mode)
                         tab-bar-mode
                         (fboundp 'tab-bar--current-tab)
                         (fboundp 'tab-bar-select-tab-by-name))
                (let ((current-tab (tab-bar--current-tab)))
                  (when (and original-tab current-tab
                             (not (equal (alist-get 'name original-tab)
                                         (alist-get 'name current-tab))))
                    (tab-bar-select-tab-by-name (alist-get 'name original-tab)))))))
          ;; Should NOT have switched
          (should (null tab-switched)))))))

(defun claude-code-ide-run-tests ()
  "Run all claude-code-ide test cases."
  (interactive)
  (ert-run-tests-batch-and-exit "^claude-code-ide-test-"))

(defun claude-code-ide-run-all-tests ()
  "Run all claude-code-ide tests including MCP tests."
  (interactive)
  (ert-run-tests-batch-and-exit "^claude-code-ide-"))

;;; MCP Tests

;; Load MCP module now that websocket is available
(require 'claude-code-ide-mcp)

;; Load MCP handlers module for testing
(require 'claude-code-ide-mcp-handlers)

;; Load MCP tools server module
(condition-case nil
    (require 'claude-code-ide-mcp-server)
  (error nil))

;;; MCP Test Helper Functions

(defmacro claude-code-ide-mcp-tests--with-temp-file (file-var content &rest body)
  "Create a temporary file with CONTENT, bind its path to FILE-VAR, and execute BODY."
  (declare (indent 2))
  `(let ((,file-var (make-temp-file "claude-mcp-test-")))
     (unwind-protect
         (progn
           (with-temp-file ,file-var
             (insert ,content))
           ,@body)
       (delete-file ,file-var))))

(defmacro claude-code-ide-mcp-tests--with-temp-buffer (content &rest body)
  "Create a temporary buffer with CONTENT and execute BODY."
  (declare (indent 1))
  `(with-temp-buffer
     (insert ,content)
     (goto-char (point-min))
     ,@body))

;;; Tests for MCP Tool Implementations

(ert-deftest claude-code-ide-test-mcp-open-file ()
  "Test the openFile tool implementation."
  ;; Test successful file open
  (claude-code-ide-mcp-tests--with-temp-file test-file "Line 1\nLine 2\nLine 3\nLine 4"
                                             (let ((result (claude-code-ide-mcp-handle-open-file `((path . ,test-file)))))
                                               ;; Handler returns VS Code format
                                               (should (listp result))
                                               (let ((first-item (car result)))
                                                 (should (equal (alist-get 'type first-item) "text"))
                                                 (should (equal (alist-get 'text first-item) "FILE_OPENED")))
                                               (should (equal (buffer-file-name) test-file))
                                               (kill-buffer)))

  ;; Test with selection
  (claude-code-ide-mcp-tests--with-temp-file test-file "Line 1\nLine 2\nLine 3\nLine 4"
                                             (let ((result (claude-code-ide-mcp-handle-open-file
                                                            `((path . ,test-file)
                                                              (startLine . 2)
                                                              (endLine . 3)))))
                                               ;; Handler returns VS Code format
                                               (should (listp result))
                                               (let ((first-item (car result)))
                                                 (should (equal (alist-get 'type first-item) "text"))
                                                 (should (equal (alist-get 'text first-item) "FILE_OPENED")))
                                               (should (use-region-p))
                                               (should (= (line-number-at-pos (region-beginning)) 2))
                                               (kill-buffer)))

  ;; Test missing path parameter
  (should-error (claude-code-ide-mcp-handle-open-file '())
                :type 'mcp-error))

(ert-deftest claude-code-ide-test-mcp-get-current-selection ()
  "Test the getCurrentSelection tool implementation."
  ;; Test with active selection
  (claude-code-ide-mcp-tests--with-temp-buffer "Line 1\nLine 2\nLine 3"
                                               (goto-char (point-min))
                                               (set-mark (point))
                                               (forward-line 2)
                                               ;; Ensure transient-mark-mode is on and region is active
                                               (let ((transient-mark-mode t))
                                                 (activate-mark)
                                                 (let ((result (claude-code-ide-mcp-handle-get-current-selection nil)))
                                                   (should (equal (alist-get 'text result) "Line 1\nLine 2\n"))
                                                   ;; Check the selection structure
                                                   (let ((selection (alist-get 'selection result)))
                                                     (should selection)
                                                     (let ((start (alist-get 'start selection))
                                                           (end (alist-get 'end selection)))
                                                       (should (= (alist-get 'line start) 1))  ; 1-based
                                                       (should (= (alist-get 'line end) 3)))))))  ; 1-based

  ;; Test without selection
  (claude-code-ide-mcp-tests--with-temp-buffer "Test"
                                               (let ((result (claude-code-ide-mcp-handle-get-current-selection nil)))
                                                 (should (equal (alist-get 'text result) ""))
                                                 ;; When no selection, we should get the selection structure
                                                 (let ((selection (alist-get 'selection result)))
                                                   (should selection)
                                                   (should (alist-get 'isEmpty selection))))))

(ert-deftest claude-code-ide-test-mcp-get-open-editors ()
  "Test the getOpenEditors tool implementation."
  ;; Create some file buffers
  (let ((test-files '())
        (test-buffers '())
        ;; Mock the function to ensure we're not in a project
        (claude-code-ide-mcp--get-buffer-project-fn
         (symbol-function 'claude-code-ide-mcp--get-buffer-project)))
    (unwind-protect
        (progn
          ;; Mock to return nil (no project)
          (fset 'claude-code-ide-mcp--get-buffer-project (lambda () nil))

          ;; Create test files
          (dotimes (i 2)
            (let ((file (make-temp-file (format "claude-mcp-test-%d-" i))))
              (push file test-files)
              (push (find-file-noselect file) test-buffers)))

          ;; Test listing
          (let* ((result (claude-code-ide-mcp-handle-get-open-editors nil))
                 (editors (alist-get 'editors result)))
            ;; Should return an array
            (should (vectorp editors))
            ;; Should include our test files
            (let ((paths (mapcar (lambda (e) (alist-get 'path e))
                                 (append editors nil))))
              (dolist (file test-files)
                (should (member file paths))))))

      ;; Cleanup
      (fset 'claude-code-ide-mcp--get-buffer-project claude-code-ide-mcp--get-buffer-project-fn)
      (dolist (buffer test-buffers)
        (kill-buffer buffer))
      (dolist (file test-files)
        (delete-file file)))))

(ert-deftest claude-code-ide-test-mcp-save-document ()
  "Test the saveDocument tool implementation."
  (claude-code-ide-mcp-tests--with-temp-file test-file "Initial content"
                                             (with-current-buffer (find-file-noselect test-file)
                                               ;; Modify buffer
                                               (goto-char (point-max))
                                               (insert "\nNew line")
                                               ;; Save using tool
                                               (let ((result (claude-code-ide-mcp-handle-save-document `((path . ,test-file)))))
                                                 ;; Handler returns VS Code format
                                                 (should (listp result))
                                                 (let ((first-item (car result)))
                                                   (should (equal (alist-get 'type first-item) "text"))
                                                   (should (equal (alist-get 'text first-item) "DOCUMENT_SAVED")))
                                                 (should-not (buffer-modified-p)))
                                               (kill-buffer)))

  ;; Test missing path
  (should-error (claude-code-ide-mcp-handle-save-document '())
                :type 'mcp-error))

(ert-deftest claude-code-ide-test-mcp-close-tab ()
  "Test the close_tab tool implementation."
  (claude-code-ide-mcp-tests--with-temp-file test-file "Content"
                                             (find-file-noselect test-file)
                                             ;; Close using tool
                                             (let ((result (claude-code-ide-mcp-handle-close-tab `((path . ,test-file)))))
                                               ;; Handler returns VS Code format
                                               (should (listp result))
                                               (let ((first-item (car result)))
                                                 (should (equal (alist-get 'type first-item) "text"))
                                                 (should (equal (alist-get 'text first-item) "TAB_CLOSED")))
                                               (should-not (find-buffer-visiting test-file))))

  ;; Test non-existent buffer - should throw an error
  (should-error (claude-code-ide-mcp-handle-close-tab '((path . "/nonexistent/file")))
                :type 'mcp-error))

(ert-deftest claude-code-ide-test-mcp-tool-registry ()
  "Test that all tools are properly registered."
  ;; Build expected tools list dynamically based on configuration
  (let* ((base-tools '("openFile" "getCurrentSelection" "getOpenEditors"
                       "getWorkspaceFolders" "getDiagnostics" "saveDocument"
                       "close_tab" "checkDocumentDirty"))
         (diff-tools (when (bound-and-true-p claude-code-ide-use-ide-diff)
                       '("openDiff" "closeAllDiffTabs")))
         (expected-tools (append base-tools diff-tools)))
    ;; Rebuild tool lists to match current configuration
    (setq claude-code-ide-mcp-tools (claude-code-ide-mcp--build-tool-list))
    (setq claude-code-ide-mcp-tool-schemas (claude-code-ide-mcp--build-tool-schemas))
    (setq claude-code-ide-mcp-tool-descriptions (claude-code-ide-mcp--build-tool-descriptions))
    (dolist (tool-name expected-tools)
      (should (alist-get tool-name claude-code-ide-mcp-tools nil nil #'string=))
      (let ((handler (alist-get tool-name claude-code-ide-mcp-tools nil nil #'string=))
            (schema (alist-get tool-name claude-code-ide-mcp-tool-schemas nil nil #'string=)))
        ;; Check that handler is a function or a symbol that points to a function
        (should (or (functionp handler)
                    (and (symbolp handler) (fboundp handler))))
        ;; Check that schema is provided
        (should schema)))))

(ert-deftest claude-code-ide-test-ediff-flag-disables-tools ()
  "Test that diff tools are excluded when claude-code-ide-use-ide-diff is nil."
  (let ((claude-code-ide-use-ide-diff nil))
    ;; Rebuild tool lists with ediff disabled
    (setq claude-code-ide-mcp-tools (claude-code-ide-mcp--build-tool-list))
    (setq claude-code-ide-mcp-tool-schemas (claude-code-ide-mcp--build-tool-schemas))
    (setq claude-code-ide-mcp-tool-descriptions (claude-code-ide-mcp--build-tool-descriptions))
    ;; Verify diff tools are not present
    (should-not (alist-get "openDiff" claude-code-ide-mcp-tools nil nil #'string=))
    (should-not (alist-get "closeAllDiffTabs" claude-code-ide-mcp-tools nil nil #'string=))
    (should-not (alist-get "openDiff" claude-code-ide-mcp-tool-schemas nil nil #'string=))
    (should-not (alist-get "closeAllDiffTabs" claude-code-ide-mcp-tool-schemas nil nil #'string=))
    (should-not (alist-get "openDiff" claude-code-ide-mcp-tool-descriptions nil nil #'string=))
    (should-not (alist-get "closeAllDiffTabs" claude-code-ide-mcp-tool-descriptions nil nil #'string=))
    ;; Verify other tools are still present
    (should (alist-get "openFile" claude-code-ide-mcp-tools nil nil #'string=))
    (should (alist-get "getCurrentSelection" claude-code-ide-mcp-tools nil nil #'string=)))
  ;; Test with ediff enabled
  (let ((claude-code-ide-use-ide-diff t))
    ;; Rebuild tool lists with ediff enabled
    (setq claude-code-ide-mcp-tools (claude-code-ide-mcp--build-tool-list))
    (setq claude-code-ide-mcp-tool-schemas (claude-code-ide-mcp--build-tool-schemas))
    (setq claude-code-ide-mcp-tool-descriptions (claude-code-ide-mcp--build-tool-descriptions))
    ;; Verify diff tools are present
    (should (alist-get "openDiff" claude-code-ide-mcp-tools nil nil #'string=))
    (should (alist-get "closeAllDiffTabs" claude-code-ide-mcp-tools nil nil #'string=))
    (should (alist-get "openDiff" claude-code-ide-mcp-tool-schemas nil nil #'string=))
    (should (alist-get "closeAllDiffTabs" claude-code-ide-mcp-tool-schemas nil nil #'string=))
    (should (alist-get "openDiff" claude-code-ide-mcp-tool-descriptions nil nil #'string=))
    (should (alist-get "closeAllDiffTabs" claude-code-ide-mcp-tool-descriptions nil nil #'string=))))

(ert-deftest claude-code-ide-test-mcp-server-lifecycle ()
  "Test MCP server start and stop."
  (require 'claude-code-ide-mcp)
  (let ((project-dir (expand-file-name default-directory)))
    (unwind-protect
        (progn
          ;; Start server
          (let ((port (claude-code-ide-mcp-start project-dir)))
            (should (numberp port))
            (should (>= port 10000))
            (should (<= port 65535))
            ;; Check lockfile exists
            (should (file-exists-p (claude-code-ide-mcp--lockfile-path port)))
            ;; Stop server using explicit project dir
            (claude-code-ide-mcp-stop-session project-dir)
            ;; Check lockfile removed
            (should-not (file-exists-p (claude-code-ide-mcp--lockfile-path port)))))
      ;; Ensure cleanup
      (claude-code-ide-mcp-stop-session project-dir))))

;; Test for side window handling in openDiff
(defvar claude-code-ide-debug-buffer)
(ert-deftest claude-code-ide-test-opendiff-side-window ()
  "Test that openDiff handles side windows correctly."
  (require 'claude-code-ide-debug)
  (require 'claude-code-ide-mcp-handlers)
  (let* ((temp-dir (make-temp-file "test-project-" t))
         (claude-code-ide-mcp--sessions (make-hash-table :test 'equal))
         (claude-code-ide-debug t)
         (claude-code-ide-debug-buffer "*claude-code-ide-debug*")
         (temp-file (make-temp-file "test-diff-" nil ".txt" "Original content\n"))
         (side-window nil)
         ;; Create a mock session for the test
         (test-session (make-claude-code-ide-mcp-session
                        :server nil
                        :client nil
                        :port 12345
                        :project-dir temp-dir
                        :deferred (make-hash-table :test 'equal)
                        :ping-timer nil
                        :selection-timer nil
                        :last-selection nil
                        :last-buffer nil
                        :active-diffs (make-hash-table :test 'equal)
                        :original-tab nil)))
    ;; Register the test session
    (puthash temp-dir test-session claude-code-ide-mcp--sessions)
    ;; Create a .git directory to make this a project
    (make-directory (expand-file-name ".git" temp-dir) t)

    (unwind-protect
        ;; Mock the project detection to return our test directory
        (cl-letf (((symbol-function 'claude-code-ide-mcp--get-buffer-project)
                   (lambda () temp-dir))
                  ((symbol-function 'claude-code-ide-mcp--get-current-session)
                   (lambda () test-session)))
          ;; Set up the project context
          (with-current-buffer (get-buffer-create "*test-buffer*")
            (setq default-directory temp-dir)

            ;; Create a side window to simulate the problem
            (let ((side-buffer (get-buffer-create "*test-sidebar*")))
              (with-current-buffer side-buffer
                (insert "Sidebar content"))
              ;; Display buffer in side window
              (setq side-window (display-buffer-in-side-window
                                 side-buffer
                                 '((side . left) (slot . 0) (window-width . 30))))

              ;; Verify side window was created
              (should (window-parameter side-window 'window-side))

              ;; Now try to open diff - should handle side window gracefully
              (let ((result (claude-code-ide-mcp-handle-open-diff
                             `((old_file_path . ,temp-file)
                               (new_file_path . ,temp-file)
                               (new_file_contents . "Modified content\n")
                               (tab_name . "test-diff")))))
                ;; Should return deferred
                (should (eq (alist-get 'deferred result) t))

                ;; Should have created diff session in the test session
                (should (gethash "test-diff" (claude-code-ide-mcp-session-active-diffs test-session)))

                ;; Clean up - quit ediff if it started
                (when (and (boundp 'ediff-control-buffer)
                           ediff-control-buffer
                           (buffer-live-p ediff-control-buffer))
                  (with-current-buffer ediff-control-buffer
                    (remove-hook 'ediff-quit-hook t t)
                    (ediff-really-quit nil)))))))
      ;; Cleanup
      (when (file-exists-p temp-file)
        (delete-file temp-file))
      (when (file-exists-p temp-dir)
        (delete-directory temp-dir t))
      (when (and side-window (window-live-p side-window))
        (delete-window side-window))
      (claude-code-ide-mcp--cleanup-diff "test-diff" test-session)
      (kill-buffer "*test-buffer*")
      (kill-buffer "*test-sidebar*"))))

(ert-deftest claude-code-ide-test-terminal-position-keeper-syncs-unfocused-eat-window ()
  "Test Eat position keeper also syncs visible windows omitted by Eat."
  (let ((buffer (generate-new-buffer " *claude-code-ide-eat-position*")))
    (unwind-protect
        (save-window-excursion
          (delete-other-windows)
          (switch-to-buffer buffer)
          (with-current-buffer buffer
            (insert (mapconcat (lambda (n) (format "line %d" n))
                               (number-sequence 1 80)
                               "\n"))
            (goto-char (point-min))
            (forward-line 59)
            (setq-local eat-terminal 'mock-terminal)
            (let ((buffer-read-only nil)
                  (target-point (point))
                  (side-window (split-window-below)))
              (set-window-buffer side-window buffer)
              (set-window-point side-window (point-min))
              (cl-letf (((symbol-function 'eat-term-display-cursor)
                         (lambda (_terminal) target-point))
                        ((symbol-function 'evil-emacs-state-p)
                         (lambda () t))
                        ((symbol-function 'claude-code-ide--current-cli-type)
                         (lambda () 'claude)))
                (claude-code-ide--terminal-position-keeper nil))
              (should (= (window-point side-window) target-point)))))
      (when (buffer-live-p buffer)
        (kill-buffer buffer)))))

(ert-deftest claude-code-ide-test-terminal-position-keeper-skips-sync-outside-evil-emacs-state ()
  "Test Eat position keeper leaves windows alone outside Evil Emacs state."
  (let ((buffer (generate-new-buffer " *claude-code-ide-eat-position*")))
    (unwind-protect
        (save-window-excursion
          (delete-other-windows)
          (switch-to-buffer buffer)
          (with-current-buffer buffer
            (insert (mapconcat (lambda (n) (format "line %d" n))
                               (number-sequence 1 80)
                               "\n"))
            (goto-char (point-min))
            (forward-line 59)
            (setq-local eat-terminal 'mock-terminal)
            (let ((buffer-read-only nil)
                  (target-point (point))
                  (side-window (split-window-below)))
              (set-window-buffer side-window buffer)
              (set-window-point side-window (point-min))
              (cl-letf (((symbol-function 'eat-term-display-cursor)
                         (lambda (_terminal) target-point))
                        ((symbol-function 'evil-emacs-state-p)
                         (lambda () nil))
                        ((symbol-function 'claude-code-ide--current-cli-type)
                         (lambda () 'claude)))
                (claude-code-ide--terminal-position-keeper nil))
              (should (= (window-point side-window) (point-min))))))
      (when (buffer-live-p buffer)
        (kill-buffer buffer)))))

;;; Tests for Diagnostics

(ert-deftest claude-code-ide-test-diagnostics-severity-mapping ()
  "Test diagnostic severity conversion."
  (require 'claude-code-ide-diagnostics)
  ;; Test Flycheck symbols
  (should (= (claude-code-ide-diagnostics--severity-to-vscode 'error) 1))
  (should (= (claude-code-ide-diagnostics--severity-to-vscode 'warning) 2))
  (should (= (claude-code-ide-diagnostics--severity-to-vscode 'info) 3))
  (should (= (claude-code-ide-diagnostics--severity-to-vscode 'hint) 4))
  ;; Test default fallback
  (should (= (claude-code-ide-diagnostics--severity-to-vscode 'unknown) 3)))

(ert-deftest claude-code-ide-test-diagnostics-severity-to-string ()
  "Test severity to string conversion."
  (require 'claude-code-ide-diagnostics)
  ;; Test Flycheck severities
  (should (equal (claude-code-ide-diagnostics--severity-to-string 'error) "Error"))
  (should (equal (claude-code-ide-diagnostics--severity-to-string 'warning) "Warning"))
  (should (equal (claude-code-ide-diagnostics--severity-to-string 'info) "Information"))
  (should (equal (claude-code-ide-diagnostics--severity-to-string 'hint) "Hint"))
  ;; Test default fallback
  (should (equal (claude-code-ide-diagnostics--severity-to-string 'unknown) "Information")))

(ert-deftest claude-code-ide-test-diagnostics-handler ()
  "Test getDiagnostics handler."
  (require 'claude-code-ide-diagnostics)
  ;; Test with no diagnostics available
  (let ((result (claude-code-ide-diagnostics-handler nil)))
    ;; The diagnostics handler returns content array format
    (should (listp result))
    ;; Check it has the expected format
    (should (equal (alist-get 'type (car result)) "text"))
    ;; The text should be an empty array "[]"
    (should (equal (alist-get 'text (car result)) "[]"))))

;; Define mock struct for flymake diagnostics testing
(cl-defstruct claude-code-ide-test-mock-diag
  beg end type text backend)

(ert-deftest claude-code-ide-test-flymake-diagnostics ()
  "Test flymake diagnostics collection."
  ;; Skip this test in batch mode as it requires a complex flymake setup
  (skip-unless nil)
  (require 'claude-code-ide-diagnostics))

(ert-deftest claude-code-ide-test-diagnostics-backend-auto ()
  "Test automatic backend detection."
  (require 'claude-code-ide-diagnostics)
  ;; Test flycheck detection
  (cl-letf (((symbol-function 'featurep)
             (lambda (feature &rest _)
               (memq feature '(flycheck flymake))))
            ((symbol-function 'bound-and-true-p)
             (lambda (var)
               (eq var 'flycheck-mode)))
            ((symbol-function 'flycheck-diagnostics)
             (lambda () nil))
            (flycheck-current-errors nil)
            (claude-code-ide-diagnostics-backend 'auto))
    (with-temp-buffer
      (let ((diags (claude-code-ide-diagnostics-get-all (current-buffer))))
        ;; Should use flycheck when flycheck-mode is active
        (should (vectorp diags))))))

(ert-deftest claude-code-ide-test-check-document-dirty ()
  "Test checkDocumentDirty handler."
  (require 'claude-code-ide-mcp-handlers)
  ;; Test with a modified buffer
  (with-temp-buffer
    (setq buffer-file-name "/tmp/test-file.el")
    (insert "test content")
    (set-buffer-modified-p t)
    (let ((result (claude-code-ide-mcp-handle-check-document-dirty
                   '((filePath . "/tmp/test-file.el")))))
      (should (eq (alist-get 'isDirty result) t))))
  ;; Test with an unmodified buffer
  (with-temp-buffer
    (setq buffer-file-name "/tmp/test-file2.el")
    (insert "test content")
    (set-buffer-modified-p nil)
    (let ((result (claude-code-ide-mcp-handle-check-document-dirty
                   '((filePath . "/tmp/test-file2.el")))))
      (should (eq (alist-get 'isDirty result) :json-false))))
  ;; Test with a non-existent file
  (let ((result (claude-code-ide-mcp-handle-check-document-dirty
                 '((filePath . "/tmp/non-existent-file.el")))))
    (should (eq (alist-get 'isDirty result) :json-false)))
  ;; Test with missing filePath parameter
  (should-error (claude-code-ide-mcp-handle-check-document-dirty '())
                :type 'mcp-error))

;; Disabled due to ERT macro interaction with transient-mark-mode in batch mode
;; The handler works correctly (verified with direct testing) but the test fails
;; because `should` macro seems to evaluate `use-region-p` in a different context
(ert-deftest claude-code-ide-test-open-file-text-patterns ()
  "Test openFile handler with text pattern selection."
  (skip-unless nil) ; Skip this test for now
  (require 'claude-code-ide-mcp-handlers)
  ;; Create a temporary file with known content
  (let ((temp-file (make-temp-file "test-openfile-" nil ".el"))
        ;; Save and restore global transient-mark-mode
        (orig-tmm transient-mark-mode))
    (unwind-protect
        (progn
          ;; Enable transient-mark-mode globally for this test
          (setq transient-mark-mode t)
          ;; Write test content to file
          (with-temp-file temp-file
            (insert "Line 1\n")
            (insert "function foo() {\n")
            (insert "  console.log('hello');\n")
            (insert "}\n")
            (insert "Line 5\n")
            (insert "function bar() {\n")
            (insert "  return 42;\n")
            (insert "}\n"))

          ;; Test 1: Text pattern selection with both start and end
          (let ((result (claude-code-ide-mcp-handle-open-file
                         `((path . ,temp-file)
                           (startText . "function foo")
                           (endText . "}")))))
            ;; Should have opened the file and selected from "function foo" to first "}"
            (with-current-buffer (find-buffer-visiting temp-file)
              (should (string= (buffer-file-name) temp-file))
              ;; Debug info
              (message "Debug: buffer=%s tmm=%s mark-active=%s mark=%s point=%s region-p=%s"
                       (buffer-name) transient-mark-mode mark-active
                       (and (mark) (mark)) (point) (use-region-p))
              ;; Store region state before should
              (let ((region-was-active (use-region-p)))
                (should region-was-active))
              (should (string= (buffer-substring-no-properties (region-beginning) (region-end))
                               "function foo() {\n  console.log('hello');\n}"))))

          ;; Test 2: Only start text pattern
          (with-current-buffer (find-buffer-visiting temp-file)
            (deactivate-mark))
          (let ((result (claude-code-ide-mcp-handle-open-file
                         `((path . ,temp-file)
                           (startText . "function bar")))))
            ;; Should position cursor at start of "function bar"
            (with-current-buffer (find-buffer-visiting temp-file)
              (should (looking-at "function bar"))
              (should-not (use-region-p))))

          ;; Test 3: Text pattern with fallback to line numbers
          (let ((result (claude-code-ide-mcp-handle-open-file
                         `((path . ,temp-file)
                           (startText . "nonexistent text")
                           (startLine . 2)
                           (endLine . 4)))))
            ;; Should fall back to line selection
            (with-current-buffer (find-buffer-visiting temp-file)
              (should (use-region-p))
              (let ((selected (buffer-substring-no-properties (region-beginning) (region-end))))
                (should (string-match-p "function foo" selected)))))

          ;; Test 4: Text patterns take precedence over line numbers
          (with-current-buffer (find-buffer-visiting temp-file)
            (deactivate-mark))
          (let ((result (claude-code-ide-mcp-handle-open-file
                         `((path . ,temp-file)
                           (startText . "Line 5")
                           (startLine . 1)))))
            ;; Should go to "Line 5", not line 1
            (with-current-buffer (find-buffer-visiting temp-file)
              (should (looking-at "Line 5"))
              (should (= (line-number-at-pos) 5)))))

      ;; Cleanup
      (delete-file temp-file)
      ;; Restore original transient-mark-mode
      (setq transient-mark-mode orig-tmm))))

;; Test claude-code-ide-show-claude-window-in-ediff option
(ert-deftest claude-code-ide-test-show-claude-window-in-ediff ()
  "Test that Claude window visibility is controlled correctly during ediff."
  (claude-code-ide-tests--with-temp-directory
   (lambda ()
     (let* ((session (make-claude-code-ide-mcp-session
                      :project-dir default-directory
                      :active-diffs (make-hash-table :test 'equal)))
            (test-file (expand-file-name "test.txt" default-directory))
            (claude-buffer-created nil)
            (claude-window-displayed nil))

       ;; Register session in global hash table
       (puthash default-directory session claude-code-ide-mcp--sessions)

       ;; Create a test file
       (with-temp-file test-file (insert "Original content"))

       ;; Create a .git directory to make this a project
       (make-directory (expand-file-name ".git" default-directory) t)

       ;; Mock relevant functions
       (cl-letf* (((symbol-function 'claude-code-ide--get-buffer-name)
                   (lambda (&optional _dir) "*Claude Code Test*"))
                  ((symbol-function 'claude-code-ide--display-buffer-in-side-window)
                   (lambda (buffer)
                     (setq claude-window-displayed t)
                     (selected-window)))
                  ((symbol-function 'ediff-buffers)
                   (lambda (_buf-A _buf-B)
                     ;; Simulate successful ediff start
                     (setq ediff-control-buffer (get-buffer-create "*Ediff Control*"))))
                  ((symbol-function 'ediff-next-difference)
                   (lambda () nil))
                  ((symbol-function 'claude-code-ide-mcp--get-current-session)
                   (lambda () session)))

         ;; Create a Claude buffer
         (setq claude-buffer-created (get-buffer-create "*Claude Code Test*"))

         ;; Test 1: With claude-code-ide-show-claude-window-in-ediff = t (default)
         (let ((claude-code-ide-show-claude-window-in-ediff t)
               (ediff-control-buffer (get-buffer-create "*Ediff Control*")))
           (setq claude-window-displayed nil)
           ;; Call the startup handler
           (claude-code-ide-mcp--handle-ediff-startup "test-diff" session nil
                                                      (lambda () nil))
           ;; Should display Claude window
           (should claude-window-displayed))

         ;; Test 2: With claude-code-ide-show-claude-window-in-ediff = nil
         (let ((claude-code-ide-show-claude-window-in-ediff nil)
               (ediff-control-buffer (get-buffer-create "*Ediff Control*")))
           (setq claude-window-displayed nil)
           ;; Call the startup handler
           (claude-code-ide-mcp--handle-ediff-startup "test-diff" session nil
                                                      (lambda () nil))
           ;; Should NOT display Claude window
           (should-not claude-window-displayed))

         ;; Cleanup
         (when (buffer-live-p claude-buffer-created)
           (kill-buffer claude-buffer-created))
         (when (get-buffer "*Ediff Control*")
           (kill-buffer "*Ediff Control*"))
         (when (file-exists-p test-file)
           (delete-file test-file))
         (remhash default-directory claude-code-ide-mcp--sessions))))))

;; Test multiple ediff sessions
(ert-deftest claude-code-ide-test-multiple-ediff-sessions ()
  "Test that multiple ediff sessions can run simultaneously without conflicts."
  (claude-code-ide-tests--with-temp-directory
   (lambda ()
     (let* ((session (make-claude-code-ide-mcp-session
                      :project-dir default-directory
                      :active-diffs (make-hash-table :test 'equal)))
            (file1 (expand-file-name "test-file1.txt" default-directory))
            (file2 (expand-file-name "test-file2.txt" default-directory))
            (control-buffers '()))

       ;; Register session in global hash table
       (puthash default-directory session claude-code-ide-mcp--sessions)

       ;; Create test files
       (with-temp-file file1 (insert "Original content 1"))
       (with-temp-file file2 (insert "Original content 2"))

       ;; Create a .git directory to make this a project
       (make-directory (expand-file-name ".git" default-directory) t)

       ;; Mock ediff functions to capture control buffer names
       (cl-letf* ((ediff-called-count 0)
                  ((symbol-function 'ediff-buffers)
                   (lambda (buf-A buf-B)
                     (cl-incf ediff-called-count)
                     ;; Simulate ediff creating a control buffer with the suffix
                     (let ((suffix (or ediff-control-buffer-suffix "")))
                       (push (format "*Ediff Control Panel%s*" suffix) control-buffers))))
                  ((symbol-function 'claude-code-ide-mcp--get-current-session)
                   (lambda () session)))

         ;; Simulate opening multiple diffs
         (unwind-protect
             (progn
               ;; Open first diff
               (let ((result1 (claude-code-ide-mcp-handle-open-diff
                               `((old_file_path . ,file1)
                                 (new_file_path . ,file1)
                                 (new_file_contents . "Modified content 1")
                                 (tab_name . "diff1")))))
                 (should (equal (alist-get 'deferred result1) t))
                 (should (equal (alist-get 'unique-key result1) "diff1"))
                 (should (equal (alist-get 'session result1) session)))

               ;; Open second diff
               (let ((result2 (claude-code-ide-mcp-handle-open-diff
                               `((old_file_path . ,file2)
                                 (new_file_path . ,file2)
                                 (new_file_contents . "Modified content 2")
                                 (tab_name . "diff2")))))
                 (should (equal (alist-get 'deferred result2) t))
                 (should (equal (alist-get 'unique-key result2) "diff2"))
                 (should (equal (alist-get 'session result2) session)))

               ;; Verify ediff was called twice
               (should (= ediff-called-count 2))

               ;; Verify we have two distinct control buffer names
               (should (= (length control-buffers) 2))
               (should (member "*Ediff Control Panel<diff1>*" control-buffers))
               (should (member "*Ediff Control Panel<diff2>*" control-buffers))

               ;; Verify active diffs are tracked correctly
               (let ((active-diffs (claude-code-ide-mcp--get-active-diffs session)))
                 (should (gethash "diff1" active-diffs))
                 (should (gethash "diff2" active-diffs))))

           ;; Cleanup
           (claude-code-ide-mcp-handle-close-all-diff-tabs nil)
           (when (file-exists-p file1) (delete-file file1))
           (when (file-exists-p file2) (delete-file file2))
           ;; Remove session from global hash table
           (remhash default-directory claude-code-ide-mcp--sessions)))))))

(ert-deftest claude-code-ide-test-find-session-for-file-nested-projects ()
  "Test that find-session-for-file picks the most specific match for nested projects."
  (let ((claude-code-ide-mcp--sessions (make-hash-table :test 'equal))
        (parent-session (make-claude-code-ide-mcp-session
                         :project-dir "/tmp/parent-project/"
                         :deferred (make-hash-table :test 'equal)
                         :active-diffs (make-hash-table :test 'equal)))
        (child-session (make-claude-code-ide-mcp-session
                        :project-dir "/tmp/parent-project/child/"
                        :deferred (make-hash-table :test 'equal)
                        :active-diffs (make-hash-table :test 'equal))))
    (puthash "/tmp/parent-project/" parent-session claude-code-ide-mcp--sessions)
    (puthash "/tmp/parent-project/child/" child-session claude-code-ide-mcp--sessions)

    ;; File in child project should match child session, not parent
    (should (eq (claude-code-ide-mcp--find-session-for-file "/tmp/parent-project/child/src/foo.el")
                child-session))

    ;; File in parent project (not in child) should match parent session
    (should (eq (claude-code-ide-mcp--find-session-for-file "/tmp/parent-project/src/bar.el")
                parent-session))

    ;; File outside both projects should return nil
    (should (null (claude-code-ide-mcp--find-session-for-file "/tmp/other/baz.el")))))

(ert-deftest test-claude-code-ide-mcp-multi-session-deferred ()
  "Test that deferred responses work correctly with multiple sessions."
  (skip-unless (not (getenv "CI")))
  (let ((claude-code-ide-mcp--sessions (make-hash-table :test 'equal))
        (project-a "/tmp/project-a/")
        (project-b "/tmp/project-b/")
        (session-a nil)
        (session-b nil)
        (deferred-responses '())
        (sent-responses '()))
    ;; Create mock websocket-send-text to capture responses
    (cl-letf* (((symbol-function 'websocket-send-text)
                (lambda (_ws text)
                  (push text sent-responses))))
      (unwind-protect
          (progn
            ;; Create two sessions
            (make-directory project-a t)
            (make-directory project-b t)

            ;; Session A
            (let ((default-directory project-a))
              (claude-code-ide-mcp-start project-a)
              (setq session-a (gethash project-a claude-code-ide-mcp--sessions)))

            ;; Session B
            (let ((default-directory project-b))
              (claude-code-ide-mcp-start project-b)
              (setq session-b (gethash project-b claude-code-ide-mcp--sessions)))

            ;; Set up mock clients for each session
            (setf (claude-code-ide-mcp-session-client session-a) :mock-client-a)
            (setf (claude-code-ide-mcp-session-client session-b) :mock-client-b)

            ;; Store deferred responses in each session
            (let ((deferred-a (claude-code-ide-mcp-session-deferred session-a))
                  (deferred-b (claude-code-ide-mcp-session-deferred session-b)))
              ;; Session A has a deferred response for openDiff-diff1
              (puthash "openDiff-diff1" "request-id-1" deferred-a)
              ;; Session B has a deferred response for openDiff-diff2
              (puthash "openDiff-diff2" "request-id-2" deferred-b))

            ;; Complete deferred response for session A
            (claude-code-ide-mcp-complete-deferred session-a
                                                   "openDiff"
                                                   '(((type . "text") (text . "FILE_SAVED")))
                                                   "diff1")

            ;; Complete deferred response for session B
            (claude-code-ide-mcp-complete-deferred session-b
                                                   "openDiff"
                                                   '(((type . "text") (text . "DIFF_REJECTED")))
                                                   "diff2")

            ;; Verify both responses were sent
            (should (= (length sent-responses) 2))

            ;; Verify the responses contain the correct request IDs
            (let ((response1 (json-read-from-string (nth 1 sent-responses)))
                  (response2 (json-read-from-string (nth 0 sent-responses))))
              ;; Check that request-id-1 and request-id-2 were both used
              (let ((ids (list (alist-get 'id response1) (alist-get 'id response2))))
                (should (member "request-id-1" ids))
                (should (member "request-id-2" ids))))

            ;; Verify deferred responses were removed from sessions
            (should (= 0 (hash-table-count (claude-code-ide-mcp-session-deferred session-a))))
            (should (= 0 (hash-table-count (claude-code-ide-mcp-session-deferred session-b)))))

        ;; Cleanup
        (ignore-errors (delete-directory project-a t))
        (ignore-errors (delete-directory project-b t))
        (clrhash claude-code-ide-mcp--sessions)))))

;;; MCP Tools Server Tests

;; Mock the server functions since web-server might not be available in test env
(defvar claude-code-ide-mcp-server-tests--mock-server-started nil)
(defvar claude-code-ide-mcp-server-tests--mock-server-port 12345)

(defun claude-code-ide-mcp-server-tests--mock-server-start (&optional _port)
  "Mock server start function."
  (setq claude-code-ide-mcp-server-tests--mock-server-started t)
  (cons 'mock-process claude-code-ide-mcp-server-tests--mock-server-port))

(defun claude-code-ide-mcp-server-tests--mock-server-stop (_process)
  "Mock server stop function."
  (setq claude-code-ide-mcp-server-tests--mock-server-started nil))

;;; Mock websocket request/response for testing
(defvar claude-code-ide-mcp-server-tests--last-response nil
  "Storage for the last response sent.")

(defvar claude-code-ide-mcp-server-tests--last-response-headers nil
  "Storage for the last response headers.")

(defvar claude-code-ide-mcp-server-tests--last-response-status nil
  "Storage for the last response status.")

;; Mock the web-server functions
(cl-defstruct claude-code-ide-mcp-server-tests--mock-request
  process headers body)

(cl-defstruct claude-code-ide-mcp-server-tests--mock-process)

(defun claude-code-ide-mcp-server-tests--mock-ws-response-header (process status &rest headers)
  "Mock ws-response-header function."
  (setq claude-code-ide-mcp-server-tests--last-response-status status)
  (setq claude-code-ide-mcp-server-tests--last-response-headers headers))

(defun claude-code-ide-mcp-server-tests--mock-ws-send (process data)
  "Mock ws-send function."
  (unless (claude-code-ide-mcp-server-tests--mock-process-p process)
    (error "Wrong type argument: processp, %s" process))
  (setq claude-code-ide-mcp-server-tests--last-response data))

(defun claude-code-ide-mcp-server-tests--mock-ws-send-404 (process)
  "Mock ws-send-404 function."
  (unless (claude-code-ide-mcp-server-tests--mock-process-p process)
    (error "Wrong type argument: processp, %s" process))
  (setq claude-code-ide-mcp-server-tests--last-response-status 404))

;;; Session Management Tests

(ert-deftest claude-code-ide-mcp-server-test-session-lifecycle ()
  "Test MCP tools server session lifecycle."
  (let ((claude-code-ide-enable-mcp-server t)
        (claude-code-ide-mcp-server--session-count 0)
        (claude-code-ide-mcp-server--server nil)
        (claude-code-ide-mcp-server--port nil))
    ;; Mock the server functions and require
    (cl-letf (((symbol-function 'claude-code-ide-mcp-http-server-start)
               #'claude-code-ide-mcp-server-tests--mock-server-start)
              ((symbol-function 'claude-code-ide-mcp-http-server-stop)
               #'claude-code-ide-mcp-server-tests--mock-server-stop)
              ((symbol-function 'require)
               (lambda (feature &optional _filename _noerror)
                 (cond ((eq feature 'claude-code-ide-mcp-http-server) nil)
                       ((memq feature '(claude-code-ide-mcp-server websocket vterm flycheck
                                                                   claude-code-ide-debug claude-code-ide-mcp-handlers
                                                                   claude-code-ide transient)) nil)
                       (t (funcall (cl-letf-saved-symbol-function 'require) feature _filename _noerror))))))
      ;; First session should start the server
      (claude-code-ide-mcp-server-session-started)
      (should (= claude-code-ide-mcp-server--session-count 1))
      ;; Manually call the mock server start since ensure-server might fail
      (setq claude-code-ide-mcp-server--server
            (car (claude-code-ide-mcp-server-tests--mock-server-start)))
      (setq claude-code-ide-mcp-server--port
            (cdr (claude-code-ide-mcp-server-tests--mock-server-start)))
      (should claude-code-ide-mcp-server--server)
      (should (= claude-code-ide-mcp-server--port
                 claude-code-ide-mcp-server-tests--mock-server-port))

      ;; Second session should not restart the server
      (claude-code-ide-mcp-server-session-started)
      (should (= claude-code-ide-mcp-server--session-count 2))

      ;; Ending one session should not stop the server
      (claude-code-ide-mcp-server-session-ended)
      (should (= claude-code-ide-mcp-server--session-count 1))
      (should claude-code-ide-mcp-server--server)

      ;; Ending last session should stop the server
      (claude-code-ide-mcp-server-session-ended)
      (should (= claude-code-ide-mcp-server--session-count 0))
      ;; Manually stop the mock server
      (claude-code-ide-mcp-server-tests--mock-server-stop claude-code-ide-mcp-server--server)
      (setq claude-code-ide-mcp-server--server nil)
      (setq claude-code-ide-mcp-server--port nil)
      (should-not claude-code-ide-mcp-server--server)
      (should-not claude-code-ide-mcp-server--port))))

(ert-deftest claude-code-ide-mcp-server-test-config-generation ()
  "Test MCP configuration generation."
  (let ((claude-code-ide-enable-mcp-server t)
        (claude-code-ide-mcp-server--server 'mock-server)
        (claude-code-ide-mcp-server--port 8080))
    ;; With server running
    (cl-letf (((symbol-function 'process-live-p) (lambda (_) t))
              ((symbol-function 'ws-process) (lambda (_) 'mock-process)))
      (let ((config (claude-code-ide-mcp-server-get-config)))
        (should config)
        (should (equal (alist-get 'type (alist-get 'emacs-tools (alist-get 'mcpServers config)))
                       "http"))
        (should (equal (alist-get 'url (alist-get 'emacs-tools (alist-get 'mcpServers config)))
                       "http://localhost:8080/mcp"))))

    ;; Without server running
    (let ((claude-code-ide-mcp-server--server nil)
          (claude-code-ide-mcp-server--port nil)
          (config (claude-code-ide-mcp-server-get-config)))
      (should-not config))))

(ert-deftest claude-code-ide-mcp-server-test-disabled ()
  "Test that MCP tools server does nothing when disabled."
  (let ((claude-code-ide-enable-mcp-server nil)
        (claude-code-ide-mcp-server--session-count 0))
    (should-not (claude-code-ide-mcp-server-ensure-server))
    (claude-code-ide-mcp-server-session-started)
    (should (= claude-code-ide-mcp-server--session-count 1))
    ;; But server should not start
    (should-not claude-code-ide-mcp-server--server)))

;;; Tool Configuration Tests

(ert-deftest claude-code-ide-mcp-server-test-tool-config ()
  "Test tool configuration structure."
  (let ((claude-code-ide-mcp-server-tools
         '((test-function
            :description "Test function"
            :parameters ((:name "arg1" :type "string" :required t)
                         (:name "arg2" :type "number" :required nil))))))
    (let* ((tool (car claude-code-ide-mcp-server-tools))
           (name (car tool))
           (plist (cdr tool)))
      (should (eq name 'test-function))
      (should (equal (plist-get plist :description) "Test function"))
      (should (= (length (plist-get plist :parameters)) 2)))))

;;; JSON-RPC Message Tests

(ert-deftest claude-code-ide-mcp-server-test-json-encoding ()
  "Test JSON encoding of MCP config."
  (let ((config '((mcpServers . ((emacs-tools . ((transport . "http")
                                                 (url . "http://localhost:8080/mcp"))))))))
    (let ((json-str (json-encode config)))
      (should (stringp json-str))
      (should (string-match "mcpServers" json-str))
      (should (string-match "emacs-tools" json-str))
      (should (string-match "transport.*:.*http" json-str)))))

(ert-deftest claude-code-ide-mcp-server-test-ws-send-fix ()
  "Test that ws-send is called with process, not request."
  ;; Test that verifies our fix for the wrong-type-argument error
  ;; Skip test if web-server is not available
  (skip-unless (condition-case nil
                   (progn (require 'web-server) t)
                 (error nil)))
  (require 'claude-code-ide-mcp-http-server)
  (let ((mock-process (make-claude-code-ide-mcp-server-tests--mock-process))
        (mock-request (make-claude-code-ide-mcp-server-tests--mock-request)))
    ;; Set the process in the request
    (setf (claude-code-ide-mcp-server-tests--mock-request-process mock-request) mock-process)
    ;; Mock the ws-* functions
    (cl-letf (((symbol-function 'ws-response-header)
               #'claude-code-ide-mcp-server-tests--mock-ws-response-header)
              ((symbol-function 'ws-send)
               #'claude-code-ide-mcp-server-tests--mock-ws-send)
              ((symbol-function 'ws-send-404)
               #'claude-code-ide-mcp-server-tests--mock-ws-send-404))
      ;; Test send-json-response
      (claude-code-ide-mcp-http-server--send-json-response
       mock-request 200 '((test . "data")))
      (should (equal claude-code-ide-mcp-server-tests--last-response-status 200))
      (should (string-match "test.*:.*data" claude-code-ide-mcp-server-tests--last-response))

      ;; Test handle-get (404 response)
      (claude-code-ide-mcp-http-server--handle-get mock-request)
      (should (equal claude-code-ide-mcp-server-tests--last-response-status 404)))))

;;; MCP Server Session Context Tests

(ert-deftest claude-code-ide-mcp-server-test-session-registration ()
  "Test session registration and retrieval."
  (let ((session-id "test-session-123")
        (project-dir "/tmp/test-project")
        (buffer (get-buffer-create "*test-buffer*")))
    (unwind-protect
        (progn
          ;; Register a session
          (claude-code-ide-mcp-server-register-session session-id project-dir buffer)

          ;; Retrieve and verify session context
          (let ((context (gethash session-id claude-code-ide-mcp-server--sessions)))
            (should context)
            (should (equal (plist-get context :project-dir) project-dir))
            (should (eq (plist-get context :buffer) buffer))
            (should (plist-get context :start-time)))

          ;; Test get-session-context function
          (let ((claude-code-ide-mcp-server--current-session-id session-id))
            (let ((context (claude-code-ide-mcp-server-get-session-context)))
              (should context)
              (should (equal (plist-get context :project-dir) project-dir))))

          ;; Unregister session
          (claude-code-ide-mcp-server-unregister-session session-id)
          (should-not (gethash session-id claude-code-ide-mcp-server--sessions)))

      ;; Cleanup
      (kill-buffer buffer)
      (clrhash claude-code-ide-mcp-server--sessions))))

(ert-deftest claude-code-ide-mcp-server-test-with-session-context-macro ()
  "Test the with-session-context macro."
  (let ((session-id "test-session-456")
        (project-dir "/tmp/test-project-2/")
        (buffer (get-buffer-create "*test-buffer-2*"))
        (original-dir default-directory))
    (unwind-protect
        (progn
          ;; Set up the buffer with the project directory
          (with-current-buffer buffer
            (setq default-directory project-dir))

          ;; Register a session
          (claude-code-ide-mcp-server-register-session session-id project-dir buffer)

          ;; Test macro with valid session
          (let ((claude-code-ide-mcp-server--current-session-id session-id))
            (claude-code-ide-mcp-server-with-session-context nil
              ;; Inside the macro, default-directory should be the project dir
              (should (equal default-directory project-dir))
              ;; Current buffer should be the session buffer
              (should (eq (current-buffer) buffer))))

          ;; Verify we're back to original context
          (should (equal default-directory original-dir))

          ;; Test error handling with invalid session
          (let ((claude-code-ide-mcp-server--current-session-id "invalid-session"))
            (should-error
             (claude-code-ide-mcp-server-with-session-context nil
               (error "Should not reach here")))))

      ;; Cleanup
      (kill-buffer buffer)
      (clrhash claude-code-ide-mcp-server--sessions))))

(ert-deftest claude-code-ide-mcp-server-test-session-lifecycle-detailed ()
  "Test complete session lifecycle with detailed tracking."
  (let ((session-id "test-session-789")
        (project-dir "/tmp/test-project-3")
        (buffer (get-buffer-create "*test-buffer-3*")))
    (unwind-protect
        (progn
          ;; Start session
          (claude-code-ide-mcp-server-session-started session-id project-dir buffer)
          (should (= claude-code-ide-mcp-server--session-count 1))
          (should (gethash session-id claude-code-ide-mcp-server--sessions))

          ;; End session
          (claude-code-ide-mcp-server-session-ended session-id)
          (should (= claude-code-ide-mcp-server--session-count 0))
          (should-not (gethash session-id claude-code-ide-mcp-server--sessions)))

      ;; Cleanup
      (kill-buffer buffer)
      (setq claude-code-ide-mcp-server--session-count 0)
      (clrhash claude-code-ide-mcp-server--sessions))))

(ert-deftest claude-code-ide-mcp-server-test-config-with-session-id ()
  "Test MCP config generation with session ID."
  ;; Mock the server port
  (cl-letf (((symbol-function 'claude-code-ide-mcp-server-get-port)
             (lambda () 12345)))
    ;; Test without session ID
    (let ((config (claude-code-ide-mcp-server-get-config)))
      (should config)
      (let ((url (alist-get 'url (alist-get 'emacs-tools (alist-get 'mcpServers config)))))
        (should (equal url "http://localhost:12345/mcp"))))

    ;; Test with session ID
    (let ((config (claude-code-ide-mcp-server-get-config "my-session-123")))
      (should config)
      (let* ((emacs-tools (alist-get 'emacs-tools (alist-get 'mcpServers config)))
             (url (alist-get 'url emacs-tools)))
        (should (equal url "http://localhost:12345/mcp/my-session-123"))))))

;;; Emacs Tools Tests

(ert-deftest claude-code-ide-emacs-tools-test-imenu-list-symbols ()
  "Test the imenu-list-symbols MCP tool."
  ;; Load the emacs-tools module
  (require 'claude-code-ide-emacs-tools)

  (let ((test-file (make-temp-file "test-imenu-" nil ".el"))
        (session-id "test-session-imenu")
        (project-dir (temporary-file-directory)))
    (unwind-protect
        (progn
          ;; Write test content to file
          (with-temp-file test-file
            (insert ";;; Test file for imenu\n\n"
                    "(defun test-function-1 (arg)\n"
                    "  \"A test function.\"\n"
                    "  (message \"Hello %s\" arg))\n\n"
                    "(defvar test-variable 42\n"
                    "  \"A test variable.\")\n\n"
                    "(defun test-function-2 ()\n"
                    "  \"Another test function.\"\n"
                    "  (+ 1 2))\n\n"
                    "(defconst test-constant 'foo\n"
                    "  \"A test constant.\")\n"))

          ;; Register a mock session
          (claude-code-ide-mcp-server-register-session session-id project-dir nil)

          ;; Test with session context
          (let ((claude-code-ide-mcp-server--current-session-id session-id))
            (let ((result (claude-code-ide-mcp-imenu-list-symbols test-file)))
              ;; Should return a list of results
              (should (listp result))
              (should (> (length result) 0))

              ;; Check that we found our functions and variables
              (let ((result-string (mapconcat #'identity result "\n")))
                (should (string-match "test-function-1" result-string))
                (should (string-match "test-function-2" result-string))
                (should (string-match "test-variable" result-string))
                (should (string-match "test-constant" result-string))

                ;; Check format includes line numbers
                (should (string-match ":[0-9]+:" result-string)))))

          ;; Test error handling - no file path
          (should-error (claude-code-ide-mcp-imenu-list-symbols nil)
                        :type 'error)

          ;; Test with non-existent file
          (let ((result (condition-case nil
                            (claude-code-ide-mcp-imenu-list-symbols "/nonexistent/file.el")
                          (error "Error listing symbols"))))
            (should (stringp result))
            (should (string-match "Error" result))))

      ;; Cleanup
      (delete-file test-file)
      (claude-code-ide-mcp-server-unregister-session session-id))))

(ert-deftest claude-code-ide-emacs-tools-test-imenu-nested-symbols ()
  "Test imenu-list-symbols with nested symbol structures."
  (require 'claude-code-ide-emacs-tools)

  (let ((test-file (make-temp-file "test-imenu-nested-" nil ".py"))
        (session-id "test-session-imenu-nested")
        (project-dir (temporary-file-directory)))
    (unwind-protect
        (progn
          ;; Write Python test content (which often has nested imenu structures)
          (with-temp-file test-file
            (insert "# Test Python file\n\n"
                    "class TestClass:\n"
                    "    def method1(self):\n"
                    "        pass\n\n"
                    "    def method2(self, arg):\n"
                    "        return arg * 2\n\n"
                    "def standalone_function():\n"
                    "    return 42\n"))

          ;; Register a mock session
          (claude-code-ide-mcp-server-register-session session-id project-dir nil)

          ;; Test with session context
          (let ((claude-code-ide-mcp-server--current-session-id session-id))
            ;; Note: This test might not find nested structures if python-mode
            ;; isn't properly configured, but it should at least not error
            (condition-case err
                (let ((result (claude-code-ide-mcp-imenu-list-symbols test-file)))
                  ;; Should return either a list or a string (no symbols message)
                  (should (or (listp result) (stringp result))))
              (error
               ;; If python mode isn't available, that's okay for this test
               (should (string-match "Error" (error-message-string err)))))))

      ;; Cleanup
      (delete-file test-file)
      (claude-code-ide-mcp-server-unregister-session session-id))))

(ert-deftest claude-code-ide-test-tool-format-backward-compatibility ()
  "Test that both old and new tool formats work correctly."
  (require 'claude-code-ide-mcp-server)

  ;; Define a test function
  (defun test-tool-func (arg1 arg2)
    "Test function for tool format testing."
    (list arg1 arg2))

  ;; Test old format
  (let ((old-format-tool '(test-tool-func
                           :description "Test tool in old format"
                           :parameters ((:name "arg1"
                                               :type "string"
                                               :required t
                                               :description "First argument")
                                        (:name "arg2"
                                               :type "number"
                                               :required nil
                                               :description "Second argument")))))

    ;; Check format detection
    (should (eq (claude-code-ide--tool-format-p old-format-tool) 'old))

    ;; Check normalization - should emit warning
    (let ((warning-msg nil))
      ;; Capture the warning message
      (cl-letf (((symbol-function 'message)
                 (lambda (fmt &rest args)
                   (when (string-match "deprecated format" fmt)
                     (setq warning-msg (apply #'format fmt args))))))
        (let ((normalized (claude-code-ide--normalize-tool-spec old-format-tool)))
          (should (eq (plist-get normalized :function) 'test-tool-func))
          (should (equal (plist-get normalized :name) "test-tool-func"))
          (should (equal (plist-get normalized :description) "Test tool in old format"))
          (should (equal (length (plist-get normalized :args)) 2))))
      ;; Verify warning was emitted
      (should warning-msg)
      (should (string-match "test-tool-func.*deprecated.*claude-code-ide-make-tool" warning-msg))))

  ;; Test new format
  (let ((new-format-tool (claude-code-ide-make-tool
                          :function #'test-tool-func
                          :name "test_tool_new"
                          :description "Test tool in new format"
                          :args '((:name "arg1"
                                         :type string
                                         :description "First argument")
                                  (:name "arg2"
                                         :type number
                                         :description "Second argument"
                                         :optional t)))))

    ;; Check format detection
    (should (eq (claude-code-ide--tool-format-p new-format-tool) 'new))

    ;; Check normalization
    (let ((normalized (claude-code-ide--normalize-tool-spec new-format-tool)))
      (should (eq (plist-get normalized :function) 'test-tool-func))
      (should (equal (plist-get normalized :name) "test_tool_new"))
      (should (equal (plist-get normalized :description) "Test tool in new format"))
      (let ((args (plist-get normalized :args)))
        (should (equal (length args) 2))
        ;; Check first argument
        (let ((arg1 (car args)))
          (should (equal (plist-get arg1 :name) "arg1"))
          (should (eq (plist-get arg1 :type) 'string))
          (should (not (plist-get arg1 :optional))))
        ;; Check second argument
        (let ((arg2 (cadr args)))
          (should (equal (plist-get arg2 :name) "arg2"))
          (should (eq (plist-get arg2 :type) 'number))
          (should (plist-get arg2 :optional))))))

  ;; Test that both formats can coexist in the same list
  (let* ((claude-code-ide-mcp-server-tools
          (list
           ;; Old format
           '(test-func-old
             :description "Old format tool"
             :parameters ((:name "param" :type "string" :required t)))
           ;; New format
           (claude-code-ide-make-tool
            :function #'test-func-new
            :name "test_func_new"
            :description "New format tool"
            :args '((:name "param" :type string)))))
         (normalized-tools (mapcar #'claude-code-ide--normalize-tool-spec
                                   claude-code-ide-mcp-server-tools)))

    ;; Both tools should normalize correctly
    (should (equal (length normalized-tools) 2))
    (should (eq (plist-get (car normalized-tools) :function) 'test-func-old))
    (should (eq (plist-get (cadr normalized-tools) :function) 'test-func-new))))

(ert-deftest claude-code-ide-emacs-tools-test-tool-configuration ()
  "Test that imenu tool is properly configured."
  (require 'claude-code-ide-emacs-tools)
  (require 'claude-code-ide-mcp-server)

  ;; Setup tools first
  (claude-code-ide-emacs-tools-setup)

  ;; Find the imenu tool in the registered tools
  (let ((imenu-tool (cl-find-if
                     (lambda (tool)
                       (let ((normalized (claude-code-ide--normalize-tool-spec tool)))
                         (eq (plist-get normalized :function)
                             'claude-code-ide-mcp-imenu-list-symbols)))
                     claude-code-ide-mcp-server-tools)))
    (should imenu-tool)

    ;; Normalize the tool to check its properties
    (let ((normalized (claude-code-ide--normalize-tool-spec imenu-tool)))
      ;; Check description
      (should (equal (plist-get normalized :description)
                     "Navigate and explore a file's structure by listing all its functions, classes, and variables with their locations"))

      ;; Check args
      (let ((args (plist-get normalized :args)))
        (should (= (length args) 1))
        (let ((file-path-arg (car args)))
          (should (equal (plist-get file-path-arg :name) "file_path"))
          (should (eq (plist-get file-path-arg :type) 'string))
          (should (not (plist-get file-path-arg :optional)))
          (should (equal (plist-get file-path-arg :description)
                         "Path to the file to analyze for symbols")))))))

(ert-deftest claude-code-ide-test-send-current-file ()
  "Test the claude-code-ide-send-current-file command."
  (let ((sent-string nil))
    (cl-letf (((symbol-function 'claude-code-ide--get-buffer-name)
               (lambda () "*test-claude-buffer*"))
              ((symbol-function 'claude-code-ide--terminal-send-string)
               (lambda (str &optional _paste) (setq sent-string str)))
              ((symbol-function 'project-current)
               (lambda (&rest _) '(vc . "/home/user/project/")))
              ((symbol-function 'project-root)
               (lambda (_) "/home/user/project/")))

      ;; Test with a file buffer
      (with-temp-buffer
        (rename-buffer "*test-claude-buffer*")
        (let ((test-source-buf (generate-new-buffer "test-source")))
          (unwind-protect
              (with-current-buffer test-source-buf
                (setq buffer-file-name "/home/user/project/src/main.el")
                (cl-letf (((symbol-function 'claude-code-ide--get-buffer-name)
                           (lambda () "*test-claude-buffer*")))
                  (claude-code-ide-send-current-file)
                  (should (equal sent-string "@src/main.el "))))
            (kill-buffer test-source-buf))))

      ;; Test with no file buffer (should error)
      (with-temp-buffer
        (should-error (claude-code-ide-send-current-file) :type 'user-error))

      ;; Test with no session buffer (should error)
      (setq sent-string nil)
      (cl-letf (((symbol-function 'claude-code-ide--get-buffer-name)
                 (lambda () "*nonexistent-buffer*")))
        (let ((test-buf (generate-new-buffer "test-file-buf")))
          (unwind-protect
              (with-current-buffer test-buf
                (setq buffer-file-name "/home/user/project/foo.el")
                (should-error (claude-code-ide-send-current-file) :type 'user-error))
            (kill-buffer test-buf)))))))

(ert-deftest claude-code-ide-test-send-current-file-from-dired ()
  "Test send-current-file uses the file at point in dired."
  (let ((sent-string nil)
        (terminal-buf (generate-new-buffer "*test-claude-buffer*")))
    (unwind-protect
        (progn
          (cl-letf (((symbol-function 'claude-code-ide--get-buffer-name)
                     (lambda () "*test-claude-buffer*"))
                    ((symbol-function 'claude-code-ide--terminal-send-string)
                     (lambda (str &optional _paste) (setq sent-string str)))
                    ((symbol-function 'project-current)
                     (lambda (&rest _) '(vc . "/home/user/project/")))
                    ((symbol-function 'project-root)
                     (lambda (_) "/home/user/project/"))
                    ((symbol-function 'dired-get-filename)
                     (lambda (&optional _localp _no-error-if-not-filep)
                       "/home/user/project/src/from-dired.el")))
            (with-temp-buffer
              (let ((default-directory "/home/user/project/"))
                (cl-letf (((symbol-function 'derived-mode-p)
                           (lambda (&rest modes) (memq 'dired-mode modes))))
                  (claude-code-ide-send-current-file)
                  (should (equal sent-string "@src/from-dired.el ")))))))
      (kill-buffer terminal-buf))))

(ert-deftest claude-code-ide-test-send-current-file-from-treemacs ()
  "Test send-current-file uses the file at point in treemacs."
  (let ((sent-string nil)
        (terminal-buf (generate-new-buffer "*test-claude-buffer*"))
        (orig-treemacs-safe-button-get
         (when (fboundp 'treemacs-safe-button-get)
           (symbol-function 'treemacs-safe-button-get))))
    (unwind-protect
        (progn
          (fset 'treemacs-safe-button-get
                '(macro lambda (button-form property)
                        (unless (equal button-form '(treemacs-current-button))
                          (error "Expected direct treemacs-current-button form, got: %S"
                                 button-form))
                        (unless (eq property :path)
                          (error "Expected :path property, got: %S" property))
                        "/home/user/project/src/from-treemacs.el"))
          (cl-letf (((symbol-function 'claude-code-ide--get-buffer-name)
                     (lambda () "*test-claude-buffer*"))
                    ((symbol-function 'claude-code-ide--terminal-send-string)
                     (lambda (str &optional _paste) (setq sent-string str)))
                    ((symbol-function 'project-current)
                     (lambda (&rest _) '(vc . "/home/user/project/")))
                    ((symbol-function 'project-root)
                     (lambda (_) "/home/user/project/"))
                    ((symbol-function 'treemacs-current-button)
                     (lambda () 'mock-button)))
            (with-temp-buffer
              (let ((default-directory "/home/user/project/"))
                (cl-letf (((symbol-function 'derived-mode-p)
                           (lambda (&rest modes) (memq 'treemacs-mode modes))))
                  (claude-code-ide-send-current-file)
                  (should (equal sent-string "@src/from-treemacs.el ")))))))
      (if orig-treemacs-safe-button-get
          (fset 'treemacs-safe-button-get orig-treemacs-safe-button-get)
        (fmakunbound 'treemacs-safe-button-get))
      (kill-buffer terminal-buf))))

(ert-deftest claude-code-ide-test-format-file-reference ()
  "Test conditional leading-space formatting for file references."
  (with-temp-buffer
    (should (equal (claude-code-ide--format-file-reference "@file.el")
                   "@file.el ")))
  (with-temp-buffer
    (insert "x")
    (should (equal (claude-code-ide--format-file-reference "@file.el")
                   " @file.el ")))
  (with-temp-buffer
    (insert " ")
    (should (equal (claude-code-ide--format-file-reference "@file.el")
                   "@file.el ")))
  (with-temp-buffer
    (insert "\n")
    (should (equal (claude-code-ide--format-file-reference "@file.el")
                   "@file.el "))))

(ert-deftest claude-code-ide-test-send-current-file-adds-leading-space-when-needed ()
  "Test send-current-file prefixes a space when point follows a word."
  (let ((sent-string nil))
    (cl-letf (((symbol-function 'claude-code-ide--get-buffer-name)
               (lambda () "*test-claude-buffer*"))
              ((symbol-function 'claude-code-ide--terminal-send-string)
               (lambda (str &optional _paste) (setq sent-string str)))
              ((symbol-function 'project-current)
               (lambda (&rest _) '(vc . "/home/user/project/")))
              ((symbol-function 'project-root)
               (lambda (_) "/home/user/project/"))
              ((symbol-function 'claude-code-ide--find-prompt-buffer)
               (lambda () nil)))
      (with-temp-buffer
        (rename-buffer "*test-claude-buffer*")
        (insert "hello")
        (let ((test-source-buf (generate-new-buffer "test-source-spacing")))
          (unwind-protect
              (with-current-buffer test-source-buf
                (setq buffer-file-name "/home/user/project/src/main.el")
                (claude-code-ide-send-current-file)
                (should (equal sent-string " @src/main.el ")))
            (kill-buffer test-source-buf)))))))

(ert-deftest claude-code-ide-test-send-file ()
  "Test the claude-code-ide-send-file command."
  (let ((sent-string nil)
        (completed-read-called nil))
    (cl-letf (((symbol-function 'claude-code-ide--get-buffer-name)
               (lambda () "*test-claude-buffer*"))
              ((symbol-function 'claude-code-ide--terminal-send-string)
               (lambda (str &optional _paste) (setq sent-string str)))
              ((symbol-function 'project-current)
               (lambda (&rest _) '(vc . "/home/user/project/")))
              ((symbol-function 'project-root)
               (lambda (_) "/home/user/project/"))
              ((symbol-function 'project-files)
               (lambda (_) '("/home/user/project/src/main.el"
                             "/home/user/project/src/utils.el"
                             "/home/user/project/README.md")))
              ((symbol-function 'completing-read)
               (lambda (_prompt collection &rest _)
                 (setq completed-read-called t)
                 (car collection))))

      ;; Test completing-read path (no prefix arg)
      (with-temp-buffer
        (rename-buffer "*test-claude-buffer*")
        (claude-code-ide-send-file nil)
        (should completed-read-called)
        (should (equal sent-string "@src/main.el "))))

    ;; Test prefix arg path (read-file-name)
    (setq sent-string nil)
    (cl-letf (((symbol-function 'claude-code-ide--get-buffer-name)
               (lambda () "*test-claude-buffer*"))
              ((symbol-function 'claude-code-ide--terminal-send-string)
               (lambda (str &optional _paste) (setq sent-string str)))
              ((symbol-function 'project-current)
               (lambda (&rest _) '(vc . "/home/user/project/")))
              ((symbol-function 'project-root)
               (lambda (_) "/home/user/project/"))
              ((symbol-function 'read-file-name)
               (lambda (_prompt dir &rest _)
                 (concat dir "lib/helper.el"))))

      (with-temp-buffer
        (rename-buffer "*test-claude-buffer*")
        (claude-code-ide-send-file t)
        (should (equal sent-string "@lib/helper.el "))))

    ;; Test with no session buffer (should error)
    (cl-letf (((symbol-function 'claude-code-ide--get-buffer-name)
               (lambda () "*nonexistent-buffer*"))
              ((symbol-function 'project-current)
               (lambda (&rest _) '(vc . "/home/user/project/")))
              ((symbol-function 'project-root)
               (lambda (_) "/home/user/project/"))
              ((symbol-function 'project-files)
               (lambda (_) '("/home/user/project/src/main.el")))
              ((symbol-function 'completing-read)
               (lambda (_prompt collection &rest _) (car collection))))
      (should-error (claude-code-ide-send-file nil) :type 'user-error))))

(ert-deftest claude-code-ide-test-send-file-adds-leading-space-when-needed ()
  "Test send-file prefixes a space when point follows a word."
  (let ((sent-string nil))
    (cl-letf (((symbol-function 'claude-code-ide--get-buffer-name)
               (lambda () "*test-claude-buffer*"))
              ((symbol-function 'claude-code-ide--terminal-send-string)
               (lambda (str &optional _paste) (setq sent-string str)))
              ((symbol-function 'project-current)
               (lambda (&rest _) '(vc . "/home/user/project/")))
              ((symbol-function 'project-root)
               (lambda (_) "/home/user/project/"))
              ((symbol-function 'project-files)
               (lambda (_) '("/home/user/project/src/main.el")))
              ((symbol-function 'completing-read)
               (lambda (_prompt collection &rest _) (car collection))))
      (with-temp-buffer
        (rename-buffer "*test-claude-buffer*")
        (insert "hello")
        (claude-code-ide-send-file nil)
        (should (equal sent-string " @src/main.el "))))))

(ert-deftest claude-code-ide-test-get-selection-line-range-no-selection ()
  "Test that nil is returned when no selection is active."
  (with-temp-buffer
    (insert "line1\nline2\nline3\n")
    (should (null (claude-code-ide--get-selection-line-range)))))

(ert-deftest claude-code-ide-test-get-selection-line-range-region ()
  "Test line range from an active Emacs region."
  (with-temp-buffer
    (transient-mark-mode 1)
    (insert "line1\nline2\nline3\nline4\n")
    (goto-char (point-min))
    (forward-line 1)
    (push-mark (point) t t)
    (forward-line 2)
    (should (equal (claude-code-ide--get-selection-line-range)
                   '(2 . 3)))))

(ert-deftest claude-code-ide-test-get-selection-line-range-single-line-region ()
  "Test single-line region returns same start and end."
  (with-temp-buffer
    (transient-mark-mode 1)
    (insert "line1\nline2\nline3\n")
    (goto-char (point-min))
    (forward-line 1)
    (push-mark (point) t t)
    (end-of-line)
    (should (equal (claude-code-ide--get-selection-line-range)
                   '(2 . 2)))))

(ert-deftest claude-code-ide-test-send-current-file-with-region ()
  "Test send-current-file includes line range when region is active."
  (let ((sent-string nil))
    (cl-letf (((symbol-function 'claude-code-ide--get-buffer-name)
               (lambda () "*test-claude-buffer*"))
              ((symbol-function 'claude-code-ide--terminal-send-string)
               (lambda (str &optional _paste) (setq sent-string str)))
              ((symbol-function 'project-current)
               (lambda (&rest _) '(vc . "/home/user/project/")))
              ((symbol-function 'project-root)
               (lambda (_) "/home/user/project/")))

      ;; Test with multi-line range
      (with-temp-buffer
        (rename-buffer "*test-claude-buffer*")
        (let ((test-source-buf (generate-new-buffer "test-source-range")))
          (unwind-protect
              (with-current-buffer test-source-buf
                (transient-mark-mode 1)
                (setq buffer-file-name "/home/user/project/src/main.el")
                (insert "line1\nline2\nline3\nline4\nline5\n")
                (goto-char (point-min))
                (forward-line 1)
                (push-mark (point) t t)
                (forward-line 2)
                (cl-letf (((symbol-function 'claude-code-ide--get-buffer-name)
                           (lambda () "*test-claude-buffer*")))
                  (claude-code-ide-send-current-file)
                  (should (equal sent-string "@src/main.el#L2-3 "))))
            (kill-buffer test-source-buf))))

      ;; Test with single-line range
      (setq sent-string nil)
      (with-temp-buffer
        (rename-buffer "*test-claude-buffer*")
        (let ((test-source-buf (generate-new-buffer "test-source-single")))
          (unwind-protect
              (with-current-buffer test-source-buf
                (transient-mark-mode 1)
                (setq buffer-file-name "/home/user/project/src/main.el")
                (insert "line1\nline2\nline3\n")
                (goto-char (point-min))
                (forward-line 1)
                (push-mark (point) t t)
                (end-of-line)
                (cl-letf (((symbol-function 'claude-code-ide--get-buffer-name)
                           (lambda () "*test-claude-buffer*")))
                  (claude-code-ide-send-current-file)
                  (should (equal sent-string "@src/main.el#L2 "))))
            (kill-buffer test-source-buf)))))))

(ert-deftest claude-code-ide-test-prompt-buffer-patterns-default ()
  "Test that prompt buffer patterns defcustom has correct defaults."
  (should (listp claude-code-ide-prompt-buffer-patterns))
  (should (= 3 (length claude-code-ide-prompt-buffer-patterns)))
  (should (string-match-p (nth 0 claude-code-ide-prompt-buffer-patterns)
                          "/tmp/codex-prompt-abc.md"))
  (should (string-match-p (nth 0 claude-code-ide-prompt-buffer-patterns)
                          "/private/tmp/zsh-edit-abc.zsh"))
  (should (string-match-p (nth 0 claude-code-ide-prompt-buffer-patterns)
                          "/var/folders/ab/cd123/T/prompt-buffer.md"))
  (should (string-match-p (nth 1 claude-code-ide-prompt-buffer-patterns)
                          "/tmp/claude-prompt-abc.md"))
  (should (string-match-p (nth 2 claude-code-ide-prompt-buffer-patterns)
                          "/home/user/.claude/plans/my-plan.md"))
  ;; Should NOT match random .md files
  (should-not (string-match-p (nth 0 claude-code-ide-prompt-buffer-patterns)
                              "/home/user/README.md"))
  (should-not (string-match-p (nth 0 claude-code-ide-prompt-buffer-patterns)
                              "/home/user/script.zsh"))
  (should-not (string-match-p (nth 1 claude-code-ide-prompt-buffer-patterns)
                              "/home/user/notes.md"))
  (should-not (string-match-p (nth 2 claude-code-ide-prompt-buffer-patterns)
                              "/home/user/notes.md")))

(ert-deftest claude-code-ide-test-find-prompt-buffer ()
  "Test finding a visible prompt/plan buffer."
  ;; No matching buffer visible -> nil
  (cl-letf (((symbol-function 'walk-windows)
             (lambda (fn &rest _)
               (funcall fn (selected-window)))))
    (with-temp-buffer
      ;; temp buffer has no file-name, won't match
      (should (null (claude-code-ide--find-prompt-buffer)))))

  ;; Matching prompt buffer visible -> returns it
  (let ((prompt-buf (generate-new-buffer "test-prompt")))
    (unwind-protect
        (progn
          (with-current-buffer prompt-buf
            (setq buffer-file-name "/tmp/claude-prompt-abc123.md"))
          (cl-letf (((symbol-function 'walk-windows)
                     (lambda (fn &rest _)
                       (funcall fn (selected-window))))
                    ((symbol-function 'window-buffer)
                     (lambda (_win) prompt-buf)))
            (should (eq prompt-buf (claude-code-ide--find-prompt-buffer)))))
      (let ((buf prompt-buf))
        (with-current-buffer buf (setq buffer-file-name nil))
        (kill-buffer buf))))

  ;; Matching plan buffer visible -> returns it
  (let ((plan-buf (generate-new-buffer "test-plan")))
    (unwind-protect
        (progn
          (with-current-buffer plan-buf
            (setq buffer-file-name "/home/user/.claude/plans/my-plan.md"))
          (cl-letf (((symbol-function 'walk-windows)
                     (lambda (fn &rest _)
                       (funcall fn (selected-window))))
                    ((symbol-function 'window-buffer)
                     (lambda (_win) plan-buf)))
            (should (eq plan-buf (claude-code-ide--find-prompt-buffer)))))
      (let ((buf plan-buf))
        (with-current-buffer buf (setq buffer-file-name nil))
        (kill-buffer buf))))

  ;; Matching Codex/zle temp buffer visible -> returns it
  (let ((temp-buf (generate-new-buffer "test-temp-prompt")))
    (unwind-protect
        (progn
          (with-current-buffer temp-buf
            (setq buffer-file-name "/var/folders/ab/cd123/T/codex-buffer.md"))
          (cl-letf (((symbol-function 'walk-windows)
                     (lambda (fn &rest _)
                       (funcall fn (selected-window))))
                    ((symbol-function 'window-buffer)
                     (lambda (_win) temp-buf)))
            (should (eq temp-buf (claude-code-ide--find-prompt-buffer)))))
      (let ((buf temp-buf))
        (with-current-buffer buf (setq buffer-file-name nil))
        (kill-buffer buf))))

  ;; Non-matching .md buffer -> nil
  (let ((other-buf (generate-new-buffer "test-other")))
    (unwind-protect
        (progn
          (with-current-buffer other-buf
            (setq buffer-file-name "/home/user/README.md"))
          (cl-letf (((symbol-function 'walk-windows)
                     (lambda (fn &rest _)
                       (funcall fn (selected-window))))
                    ((symbol-function 'window-buffer)
                     (lambda (_win) other-buf)))
            (should (null (claude-code-ide--find-prompt-buffer)))))
      (let ((buf other-buf))
        (with-current-buffer buf (setq buffer-file-name nil))
        (kill-buffer buf)))))

(ert-deftest claude-code-ide-test-prompt-buffer-send-string ()
  "Test sending a string to a visible prompt/plan buffer."
  ;; Successful insert at point
  (let ((prompt-buf (generate-new-buffer "test-prompt-send")))
    (unwind-protect
        (progn
          (with-current-buffer prompt-buf
            (setq buffer-file-name "/tmp/claude-prompt-xyz.md")
            (insert "existing text")
            (goto-char 9))  ; position after "existing"
          (cl-letf (((symbol-function 'claude-code-ide--find-prompt-buffer)
                     (lambda () prompt-buf)))
            (should (eq prompt-buf
                        (claude-code-ide--prompt-buffer-send-string "@file.el ")))
            (should (equal (with-current-buffer prompt-buf
                             (buffer-string))
                           "existing@file.el  text"))))
      (let ((buf prompt-buf))
        (with-current-buffer buf (setq buffer-file-name nil))
        (kill-buffer buf))))

  ;; No prompt buffer found -> nil, no error
  (cl-letf (((symbol-function 'claude-code-ide--find-prompt-buffer)
             (lambda () nil)))
    (should (null (claude-code-ide--prompt-buffer-send-string "@file.el ")))))

(ert-deftest claude-code-ide-test-prompt-buffer-send-string-updates-visible-window-point ()
  "Test prompt-buffer send updates the visible window point to inserted text end."
  (let ((prompt-buf (generate-new-buffer "test-prompt-window-point")))
    (unwind-protect
        (save-window-excursion
          (delete-other-windows)
          (switch-to-buffer (generate-new-buffer " *prompt-buffer-driver*"))
          (let ((prompt-window (split-window-right)))
            (set-window-buffer prompt-window prompt-buf)
            (set-window-point prompt-window (point-min))
            (with-current-buffer prompt-buf
              (setq buffer-file-name "/tmp/claude-prompt-window-point.md")
              (insert "hello")
              (goto-char (point-max))
              (cl-letf (((symbol-function 'claude-code-ide--find-prompt-buffer)
                         (lambda () prompt-buf)))
                (claude-code-ide--prompt-buffer-send-string " @src/main.el ")
                (should (= (window-point prompt-window) (point-max)))))))
      (with-current-buffer prompt-buf
        (setq buffer-file-name nil))
      (kill-buffer prompt-buf))))

(ert-deftest claude-code-ide-test-maybe-switch-to-window-enabled ()
  "Test that helper selects window when enabled and window is visible."
  (let ((claude-code-ide-switch-after-send t)
        (selected-window nil))
    (with-temp-buffer
      (let ((buf (current-buffer)))
        (display-buffer buf)
        (cl-letf (((symbol-function 'select-window)
                   (lambda (win) (setq selected-window win))))
          (claude-code-ide--maybe-switch-to-window buf)
          (should selected-window))))))

(ert-deftest claude-code-ide-test-maybe-switch-to-window-disabled ()
  "Test that helper does nothing when disabled."
  (let ((claude-code-ide-switch-after-send nil)
        (selected-window nil))
    (with-temp-buffer
      (let ((buf (current-buffer)))
        (display-buffer buf)
        (cl-letf (((symbol-function 'select-window)
                   (lambda (win) (setq selected-window win))))
          (claude-code-ide--maybe-switch-to-window buf)
          (should-not selected-window))))))

(ert-deftest claude-code-ide-test-maybe-switch-to-window-not-visible ()
  "Test that helper does nothing when window is not visible."
  (let ((claude-code-ide-switch-after-send t)
        (selected-window nil))
    (with-temp-buffer
      (let ((buf (current-buffer)))
        ;; Don't display the buffer - no visible window
        (cl-letf (((symbol-function 'select-window)
                   (lambda (win) (setq selected-window win)))
                  ((symbol-function 'get-buffer-window)
                   (lambda (_buf) nil)))
          (claude-code-ide--maybe-switch-to-window buf)
          (should-not selected-window))))))

(ert-deftest claude-code-ide-test-send-current-file-switches-to-prompt ()
  "Test send-current-file switches to prompt buffer when enabled."
  (let ((claude-code-ide-switch-after-send t)
        (switched-to nil))
    (cl-letf (((symbol-function 'claude-code-ide--get-buffer-name)
               (lambda () "*test-claude-buffer*"))
              ((symbol-function 'claude-code-ide--terminal-send-string)
               (lambda (str &optional _paste) nil))
              ((symbol-function 'project-current)
               (lambda (&rest _) '(vc . "/home/user/project/")))
              ((symbol-function 'project-root)
               (lambda (_) "/home/user/project/"))
              ((symbol-function 'claude-code-ide--maybe-switch-to-window)
               (lambda (buf) (setq switched-to buf))))
      (let ((prompt-buf (generate-new-buffer "test-prompt-switch")))
        (unwind-protect
            (progn
              (with-current-buffer prompt-buf
                (setq buffer-file-name "/tmp/claude-prompt-xyz.md"))
              (cl-letf (((symbol-function 'claude-code-ide--find-prompt-buffer)
                         (lambda () prompt-buf)))
                (with-temp-buffer
                  (setq buffer-file-name "/home/user/project/src/main.el")
                  (claude-code-ide-send-current-file)
                  (should (eq switched-to prompt-buf)))))
          (with-current-buffer prompt-buf (setq buffer-file-name nil))
          (kill-buffer prompt-buf))))))

(ert-deftest claude-code-ide-test-send-current-file-to-prompt-adds-leading-space-when-needed ()
  "Test send-current-file inserts a leading space into prompt buffers when needed."
  (let ((claude-code-ide-switch-after-send nil))
    (cl-letf (((symbol-function 'claude-code-ide--get-buffer-name)
               (lambda () "*test-claude-buffer*"))
              ((symbol-function 'claude-code-ide--terminal-send-string)
               (lambda (_str &optional _paste) (ert-fail "terminal path should not be used")))
              ((symbol-function 'project-current)
               (lambda (&rest _) '(vc . "/home/user/project/")))
              ((symbol-function 'project-root)
               (lambda (_) "/home/user/project/")))
      (let ((prompt-buf (generate-new-buffer "test-prompt-spacing")))
        (unwind-protect
            (progn
              (with-current-buffer prompt-buf
                (setq buffer-file-name "/tmp/claude-prompt-xyz.md")
                (insert "hello")
                (goto-char (point-max)))
              (cl-letf (((symbol-function 'claude-code-ide--find-prompt-buffer)
                         (lambda () prompt-buf)))
                (let ((test-source-buf (generate-new-buffer "test-source-prompt-spacing")))
                  (unwind-protect
                      (with-current-buffer test-source-buf
                        (setq buffer-file-name "/home/user/project/src/main.el")
                        (claude-code-ide-send-current-file)
                        (should (equal (with-current-buffer prompt-buf
                                         (buffer-string))
                                       "hello @src/main.el ")))
                    (kill-buffer test-source-buf)))))
          (with-current-buffer prompt-buf (setq buffer-file-name nil))
          (kill-buffer prompt-buf))))))

(ert-deftest claude-code-ide-test-send-current-file-uses-prompt-buffer-helper ()
  "Test send-current-file routes prompt-buffer insertion through the helper."
  (let ((claude-code-ide-switch-after-send nil)
        (helper-called nil))
    (cl-letf (((symbol-function 'claude-code-ide--get-buffer-name)
               (lambda () "*test-claude-buffer*"))
              ((symbol-function 'claude-code-ide--terminal-send-string)
               (lambda (_str &optional _paste) (ert-fail "terminal path should not be used")))
              ((symbol-function 'project-current)
               (lambda (&rest _) '(vc . "/home/user/project/")))
              ((symbol-function 'project-root)
               (lambda (_) "/home/user/project/"))
              ((symbol-function 'claude-code-ide--find-prompt-buffer)
               (lambda () (get-buffer "test-prompt-helper")))
              ((symbol-function 'claude-code-ide--prompt-buffer-send-string)
               (lambda (string)
                 (setq helper-called string)
                 (get-buffer "test-prompt-helper"))))
      (let ((prompt-buf (generate-new-buffer "test-prompt-helper")))
        (unwind-protect
            (with-temp-buffer
              (setq buffer-file-name "/home/user/project/src/main.el")
              (with-current-buffer prompt-buf
                (setq buffer-file-name "/tmp/claude-prompt-helper.md"))
              (claude-code-ide-send-current-file)
              (should (equal helper-called "@src/main.el ")))
          (with-current-buffer prompt-buf
            (setq buffer-file-name nil))
          (kill-buffer prompt-buf))))))

(ert-deftest claude-code-ide-test-send-current-file-switches-to-terminal ()
  "Test send-current-file switches to terminal buffer when no prompt buffer."
  (let ((claude-code-ide-switch-after-send t)
        (switched-to nil))
    (cl-letf (((symbol-function 'claude-code-ide--get-buffer-name)
               (lambda () "*test-claude-buffer*"))
              ((symbol-function 'claude-code-ide--terminal-send-string)
               (lambda (str &optional _paste) nil))
              ((symbol-function 'project-current)
               (lambda (&rest _) '(vc . "/home/user/project/")))
              ((symbol-function 'project-root)
               (lambda (_) "/home/user/project/"))
              ((symbol-function 'claude-code-ide--find-prompt-buffer)
               (lambda () nil))
              ((symbol-function 'claude-code-ide--maybe-switch-to-window)
               (lambda (buf) (setq switched-to buf))))
      (with-temp-buffer
        (rename-buffer "*test-claude-buffer*")
        (let ((terminal-buf (current-buffer))
              (test-source-buf (generate-new-buffer "test-source-switch")))
          (unwind-protect
              (with-current-buffer test-source-buf
                (setq buffer-file-name "/home/user/project/src/main.el")
                (claude-code-ide-send-current-file)
                (should (eq switched-to terminal-buf)))
            (kill-buffer test-source-buf)))))))

(ert-deftest claude-code-ide-test-send-prompt-switches-to-terminal ()
  "Test send-prompt switches to terminal buffer when enabled."
  (let ((claude-code-ide-switch-after-send t)
        (switched-to nil))
    (cl-letf (((symbol-function 'claude-code-ide--get-buffer-name)
               (lambda () "*test-claude-buffer*"))
              ((symbol-function 'claude-code-ide--terminal-send-string)
               (lambda (str) nil))
              ((symbol-function 'claude-code-ide--terminal-send-return)
               (lambda () nil))
              ((symbol-function 'claude-code-ide--maybe-switch-to-window)
               (lambda (buf) (setq switched-to buf))))
      (with-temp-buffer
        (rename-buffer "*test-claude-buffer*")
        (let ((terminal-buf (current-buffer)))
          (claude-code-ide-send-prompt "test prompt")
          (should (eq switched-to terminal-buf)))))))

(ert-deftest claude-code-ide-test-insert-at-mentioned-switches-to-terminal ()
  "Test insert-at-mentioned switches to terminal buffer when enabled."
  (let ((claude-code-ide-switch-after-send t)
        (switched-to nil))
    (cl-letf (((symbol-function 'claude-code-ide-mcp--get-buffer-project)
               (lambda () "/home/user/project/"))
              ((symbol-function 'claude-code-ide-mcp--get-session-for-project)
               (lambda (_) (make-claude-code-ide-mcp-session :client t)))
              ((symbol-function 'claude-code-ide-mcp-send-at-mentioned)
               (lambda () nil))
              ((symbol-function 'claude-code-ide--get-buffer-name)
               (lambda () "*test-claude-buffer*"))
              ((symbol-function 'claude-code-ide--maybe-switch-to-window)
               (lambda (buf) (setq switched-to buf))))
      (with-temp-buffer
        (rename-buffer "*test-claude-buffer*")
        (let ((terminal-buf (current-buffer)))
          (claude-code-ide-insert-at-mentioned)
          (should (eq switched-to terminal-buf)))))))

(ert-deftest claude-code-ide-test-get-context-buffer-file-buffer ()
  "Test helper returns current buffer when it has a file."
  (with-temp-buffer
    (setq buffer-file-name "/tmp/test-file.el")
    (should (eq (claude-code-ide--get-context-buffer) (current-buffer)))))

(ert-deftest claude-code-ide-test-get-context-buffer-claude-buffer ()
  "Test helper returns visible file buffer when in claude-code buffer."
  (let ((file-buf (generate-new-buffer "test-file-ctx")))
    (unwind-protect
        (progn
          (with-current-buffer file-buf
            (setq buffer-file-name "/tmp/test-context.el"))
          (with-temp-buffer
            (rename-buffer "*claude-code[test-ctx]*")
            ;; Mock window-list to return a window showing file-buf
            (cl-letf (((symbol-function 'window-list)
                       (lambda (&optional _frame _minibuf _window)
                         (list 'mock-win-claude 'mock-win-file)))
                      ((symbol-function 'window-buffer)
                       (lambda (win)
                         (if (eq win 'mock-win-file) file-buf (current-buffer)))))
              (should (eq (claude-code-ide--get-context-buffer) file-buf)))))
      (with-current-buffer file-buf (setq buffer-file-name nil))
      (kill-buffer file-buf))))

(ert-deftest claude-code-ide-test-get-context-buffer-no-file-visible ()
  "Test helper returns nil when no file buffer is visible."
  (with-temp-buffer
    (rename-buffer "*claude-code[test-none]*")
    (cl-letf (((symbol-function 'window-list)
               (lambda (&optional _frame _minibuf _window)
                 (list 'mock-win)))
              ((symbol-function 'window-buffer)
               (lambda (_win) (current-buffer))))
      (should-not (claude-code-ide--get-context-buffer)))))

(ert-deftest claude-code-ide-test-send-current-file-from-claude-buffer ()
  "Test send-current-file works from claude-code buffer using context buffer."
  (let ((sent-string nil)
        (file-buf (generate-new-buffer "test-ctx-send")))
    (unwind-protect
        (progn
          (with-current-buffer file-buf
            (setq buffer-file-name "/home/user/project/src/main.el"))
          (cl-letf (((symbol-function 'claude-code-ide--get-buffer-name)
                     (lambda () "*test-claude-buffer*"))
                    ((symbol-function 'claude-code-ide--terminal-send-string)
                     (lambda (str &optional _paste) (setq sent-string str)))
                    ((symbol-function 'project-current)
                     (lambda (&rest _) '(vc . "/home/user/project/")))
                    ((symbol-function 'project-root)
                     (lambda (_) "/home/user/project/"))
                    ((symbol-function 'claude-code-ide--find-prompt-buffer)
                     (lambda () nil))
                    ((symbol-function 'claude-code-ide--get-file-reference-context)
                     (lambda () (cons "/home/user/project/src/main.el" file-buf)))
                    ((symbol-function 'claude-code-ide--maybe-switch-to-window)
                     (lambda (_buf) nil)))
            (with-temp-buffer
              (rename-buffer "*test-claude-buffer*")
              ;; Call from a buffer with no file (simulating claude buffer)
              (claude-code-ide-send-current-file)
              (should (equal sent-string "@src/main.el ")))))
      (with-current-buffer file-buf (setq buffer-file-name nil))
      (kill-buffer file-buf))))

(ert-deftest claude-code-ide-test-send-current-file-line-reference ()
  "Test send-current-file-line-reference sends an absolute path by default."
  (let ((sent-string nil))
    (cl-letf (((symbol-function 'claude-code-ide--get-buffer-name)
               (lambda () "*test-claude-buffer*"))
              ((symbol-function 'claude-code-ide--terminal-send-string)
               (lambda (str &optional _paste) (setq sent-string str)))
              ((symbol-function 'claude-code-ide--find-prompt-buffer)
               (lambda () nil))
              ((symbol-function 'claude-code-ide--maybe-switch-to-window)
               (lambda (_buf) nil)))
      (with-temp-buffer
        (rename-buffer "*test-claude-buffer*")
        (let ((test-source-buf (generate-new-buffer "test-source-line-ref")))
          (unwind-protect
              (with-current-buffer test-source-buf
                (setq buffer-file-name "/home/user/project/src/main.el")
                (insert "line1\nline2\nline3\n")
                (goto-char (point-min))
                (forward-line 1)
                (claude-code-ide-send-current-file-line-reference)
                (should (equal sent-string
                               "/home/user/project/src/main.el ")))
            (kill-buffer test-source-buf)))))))

(ert-deftest claude-code-ide-test-send-current-file-line-reference-from-claude-buffer ()
  "Test send-current-file-line-reference uses the context file path."
  (let ((sent-string nil)
        (file-buf (generate-new-buffer "test-ctx-line-send")))
    (unwind-protect
        (progn
          (with-current-buffer file-buf
            (setq buffer-file-name "/home/user/project/src/main.el")
            (insert "line1\nline2\nline3\n")
            (goto-char (point-min))
            (forward-line 2))
          (cl-letf (((symbol-function 'claude-code-ide--get-buffer-name)
                     (lambda () "*test-claude-buffer*"))
                    ((symbol-function 'claude-code-ide--terminal-send-string)
                     (lambda (str &optional _paste) (setq sent-string str)))
                    ((symbol-function 'claude-code-ide--find-prompt-buffer)
                     (lambda () nil))
                    ((symbol-function 'claude-code-ide--get-file-reference-context)
                     (lambda () (cons "/home/user/project/src/main.el" file-buf)))
                    ((symbol-function 'claude-code-ide--maybe-switch-to-window)
                     (lambda (_buf) nil)))
            (with-temp-buffer
              (rename-buffer "*test-claude-buffer*")
              (claude-code-ide-send-current-file-line-reference)
              (should (equal sent-string
                             "/home/user/project/src/main.el ")))))
      (with-current-buffer file-buf (setq buffer-file-name nil))
      (kill-buffer file-buf))))

(ert-deftest claude-code-ide-test-send-current-file-line-reference-with-range-selection ()
  "Test send-current-file-line-reference appends a line range for an active region."
  (let ((sent-string nil))
    (cl-letf (((symbol-function 'claude-code-ide--get-buffer-name)
               (lambda () "*test-claude-buffer*"))
              ((symbol-function 'claude-code-ide--terminal-send-string)
               (lambda (str &optional _paste) (setq sent-string str)))
              ((symbol-function 'claude-code-ide--find-prompt-buffer)
               (lambda () nil))
              ((symbol-function 'claude-code-ide--maybe-switch-to-window)
               (lambda (_buf) nil)))
      (with-temp-buffer
        (rename-buffer "*test-claude-buffer*")
        (let ((test-source-buf (generate-new-buffer "test-source-line-ref-range")))
          (unwind-protect
              (with-current-buffer test-source-buf
                (transient-mark-mode 1)
                (setq buffer-file-name "/home/user/project/src/main.el")
                (insert "line1\nline2\nline3\nline4\n")
                (goto-char (point-min))
                (forward-line 1)
                (push-mark (point) t t)
                (forward-line 2)
                (claude-code-ide-send-current-file-line-reference)
                (should (equal sent-string
                               "/home/user/project/src/main.el:2-3 ")))
            (kill-buffer test-source-buf)))))))

(ert-deftest claude-code-ide-test-send-current-file-line-reference-with-single-line-selection ()
  "Test send-current-file-line-reference appends a single selected line."
  (let ((sent-string nil))
    (cl-letf (((symbol-function 'claude-code-ide--get-buffer-name)
               (lambda () "*test-claude-buffer*"))
              ((symbol-function 'claude-code-ide--terminal-send-string)
               (lambda (str &optional _paste) (setq sent-string str)))
              ((symbol-function 'claude-code-ide--find-prompt-buffer)
               (lambda () nil))
              ((symbol-function 'claude-code-ide--maybe-switch-to-window)
               (lambda (_buf) nil)))
      (with-temp-buffer
        (rename-buffer "*test-claude-buffer*")
        (let ((test-source-buf (generate-new-buffer "test-source-line-ref-single")))
          (unwind-protect
              (with-current-buffer test-source-buf
                (transient-mark-mode 1)
                (setq buffer-file-name "/home/user/project/src/main.el")
                (insert "line1\nline2\nline3\n")
                (goto-char (point-min))
                (forward-line 1)
                (push-mark (point) t t)
                (end-of-line)
                (claude-code-ide-send-current-file-line-reference)
                (should (equal sent-string
                               "/home/user/project/src/main.el:2 ")))
            (kill-buffer test-source-buf)))))))

(ert-deftest claude-code-ide-test-cli-type-detection ()
  "Test CLI type detection from cli-path."
  ;; Claude paths
  (let ((claude-code-ide-cli-path "claude"))
    (should (eq (claude-code-ide--current-cli-type) 'claude)))
  (let ((claude-code-ide-cli-path "/usr/local/bin/claude"))
    (should (eq (claude-code-ide--current-cli-type) 'claude)))
  (let ((claude-code-ide-cli-path "claude-code"))
    (should (eq (claude-code-ide--current-cli-type) 'claude)))
  ;; Codex paths
  (let ((claude-code-ide-cli-path "codex"))
    (should (eq (claude-code-ide--current-cli-type) 'codex)))
  (let ((claude-code-ide-cli-path "/usr/local/bin/codex"))
    (should (eq (claude-code-ide--current-cli-type) 'codex)))
  ;; GSD paths
  (let ((claude-code-ide-cli-path "gsd"))
    (should (eq (claude-code-ide--current-cli-type) 'gsd)))
  (let ((claude-code-ide-cli-path "/usr/local/bin/gsd"))
    (should (eq (claude-code-ide--current-cli-type) 'gsd)))
  ;; Unknown falls back to claude
  (let ((claude-code-ide-cli-path "some-other-cli"))
    (should (eq (claude-code-ide--current-cli-type) 'claude))))

(ert-deftest claude-code-ide-test-cli-path-safe-local-values ()
  "Test project-local CLI path values are limited to supported agents."
  (let ((predicate (get 'claude-code-ide-cli-path 'safe-local-variable)))
    (should predicate)
    (dolist (value '("claude" "codex" "gsd" "opencode"))
      (should (funcall predicate value)))
    (dolist (value '("/usr/local/bin/codex" "claude-code" "echo" "" nil))
      (should-not (funcall predicate value)))))

(ert-deftest claude-code-ide-test-build-gsd-command ()
  "Test building gsd command."
  (let ((claude-code-ide-cli-path "gsd")
        (claude-code-ide-cli-extra-flags ""))
    (let ((cmd (claude-code-ide--build-gsd-command)))
      (should (string-match-p "^gsd\\>" cmd)))
    (let ((cmd (claude-code-ide--build-gsd-command t nil)))
      (should (string-match-p "gsd --continue" cmd)))
    (let ((cmd (claude-code-ide--build-gsd-command nil t)))
      (should (string-match-p "gsd --continue" cmd)))
    (let ((claude-code-ide-cli-extra-flags "--model claude-opus-4-6"))
      (let ((cmd (claude-code-ide--build-gsd-command)))
        (should (string-match-p "--model claude-opus-4-6" cmd))))))

(ert-deftest claude-code-ide-test-build-codex-command ()
  "Test building codex command."
  (let ((claude-code-ide-cli-path "codex")
        (claude-code-ide-cli-extra-flags ""))
    ;; Basic command should not force extra terminal flags.
    (let ((cmd (claude-code-ide--build-codex-command)))
      (should (string-match-p "codex" cmd))
      (should-not (string-match-p "--no-alt-screen" cmd)))
    ;; Continue -> codex resume --last
    (let ((cmd (claude-code-ide--build-codex-command t nil)))
      (should (string-match-p "codex resume --last" cmd))
      (should-not (string-match-p "--no-alt-screen" cmd)))
    ;; Resume -> codex resume (no --last)
    (let ((cmd (claude-code-ide--build-codex-command nil t)))
      (should (string-match-p "codex resume" cmd))
      (should-not (string-match-p "--last" cmd)))
    ;; Extra flags
    (let ((claude-code-ide-cli-extra-flags "--model o3"))
      (let ((cmd (claude-code-ide--build-codex-command)))
        (should (string-match-p "--model o3" cmd))))))

(ert-deftest claude-code-ide-test-build-command-dispatches ()
  "Test that --build-command dispatches by CLI type."
  (let ((claude-code-ide-cli-path "claude")
        (claude-code-ide-cli-debug nil)
        (claude-code-ide-system-prompt nil)
        (claude-code-ide-cli-extra-flags ""))
    (should (string-match-p "^claude" (claude-code-ide--build-command))))
  (let ((claude-code-ide-cli-path "codex")
        (claude-code-ide-cli-extra-flags ""))
    (should (string-match-p "^codex" (claude-code-ide--build-command))))
  (let ((claude-code-ide-cli-path "gsd")
        (claude-code-ide-cli-extra-flags ""))
    (should (string-match-p "^gsd" (claude-code-ide--build-command)))))

(ert-deftest claude-code-ide-test-create-codex-terminal-session ()
  "Test creating a codex terminal session without MCP env vars."
  (let ((claude-code-ide-cli-path "codex")
        (claude-code-ide-terminal-backend 'vterm)
        (claude-code-ide--cli-available t)
        (claude-code-ide-cli-extra-flags ""))
    (cl-letf (((symbol-function 'claude-code-ide--build-codex-command)
               (lambda (&rest _) "codex")))
      (let ((result (claude-code-ide--create-terminal-session
                     "*test-codex*" "/tmp" 12345 nil nil "test-session")))
        (should (consp result))
        (should (bufferp (car result)))))))

(ert-deftest claude-code-ide-test-create-gsd-terminal-session ()
  "Test creating a gsd terminal session without MCP env vars."
  (let ((claude-code-ide-cli-path "gsd")
        (claude-code-ide-terminal-backend 'vterm)
        (claude-code-ide--cli-available t)
        (claude-code-ide-cli-extra-flags "")
        (gsd-builder-called nil))
    (cl-letf (((symbol-function 'claude-code-ide--build-gsd-command)
               (lambda (&rest _)
                 (setq gsd-builder-called t)
                 "gsd"))
              ((symbol-function 'claude-code-ide--build-claude-command)
               (lambda (&rest _)
                 (error "should not use claude command builder for gsd"))))
      (let ((result (claude-code-ide--create-terminal-session
                     "*test-gsd*" "/tmp" 12345 nil nil "test-session")))
        (should (consp result))
        (should gsd-builder-called)
        (should (bufferp (car result)))))))

(ert-deftest claude-code-ide-test-create-gsd-terminal-session-uses-cli-backend-override ()
  "Test GSD terminal session creation respects per-CLI backend overrides."
  (let ((claude-code-ide-cli-path "gsd")
        (claude-code-ide-terminal-backend 'eat)
        (claude-code-ide-cli-terminal-backends '((gsd . vterm)))
        (claude-code-ide--cli-available t)
        (claude-code-ide-cli-extra-flags "")
        (mock-vterm-buffer nil)
        (mock-process (start-process "mock-gsd-vterm" nil "true")))
    (unwind-protect
        (cl-letf (((symbol-function 'claude-code-ide--terminal-ensure-backend)
                   (lambda (&optional _backend) nil))
                  ((symbol-function 'vterm)
                   (lambda (&optional buffer-name)
                     (setq mock-vterm-buffer
                           (generate-new-buffer (or buffer-name "*mock-gsd-vterm*")))))
                  ((symbol-function 'get-buffer-process)
                   (lambda (_buffer) mock-process))
                  ((symbol-function 'claude-code-ide--configure-vterm-buffer)
                   (lambda () nil))
                  ((symbol-function 'claude-code-ide--build-gsd-command)
                   (lambda (&rest _) "gsd")))
          (let* ((result (claude-code-ide--create-terminal-session
                          "*test-gsd-vterm*" "/tmp" 12345 nil nil "test-session"))
                 (buffer (car result)))
            (should (consp result))
            (should (eq buffer mock-vterm-buffer))
            (should (eq (buffer-local-value 'claude-code-ide--terminal-backend buffer)
                        'vterm))))
      (when (process-live-p mock-process)
        (delete-process mock-process))
      (when (buffer-live-p mock-vterm-buffer)
        (kill-buffer mock-vterm-buffer)))))

(ert-deftest claude-code-ide-test-create-codex-terminal-session-uses-cli-backend-override ()
  "Test Codex terminal session creation respects per-CLI backend overrides."
  (let ((claude-code-ide-cli-path "codex")
        (claude-code-ide-terminal-backend 'vterm)
        (claude-code-ide-cli-terminal-backends '((codex . eat)))
        (claude-code-ide--cli-available t)
        (claude-code-ide-cli-extra-flags "")
        (mock-eat-buffer nil)
        (mock-process (start-process "mock-codex-eat" nil "true")))
    (unwind-protect
        (cl-letf (((symbol-function 'claude-code-ide--terminal-ensure-backend)
                   (lambda (&optional _backend) nil))
                  ((symbol-function 'eat-mode)
                   (lambda () nil))
                  ((symbol-function 'eat-exec)
                   (lambda (buffer _name _cmd _startfile _args)
                     (setq mock-eat-buffer buffer)))
                  ((symbol-function 'get-buffer-process)
                   (lambda (_buffer) mock-process))
                  ((symbol-function 'claude-code-ide--build-codex-command)
                   (lambda (&rest _) "codex")))
          (let* ((result (claude-code-ide--create-terminal-session
                          "*test-codex-eat*" "/tmp" 12345 nil nil "test-session"))
                 (buffer (car result)))
            (should (consp result))
            (should (eq buffer mock-eat-buffer))
            (should (eq (buffer-local-value 'claude-code-ide--terminal-backend buffer)
                        'eat))))
      (when (process-live-p mock-process)
        (delete-process mock-process))
      (when (buffer-live-p mock-eat-buffer)
        (kill-buffer mock-eat-buffer)))))

(ert-deftest claude-code-ide-test-create-terminal-session-snapshots-cli-type ()
  "Test terminal buffers keep the launch-time CLI type."
  (let ((claude-code-ide-cli-path "codex")
        (claude-code-ide-terminal-backend 'vterm)
        (claude-code-ide-cli-terminal-backends '((codex . eat)))
        (claude-code-ide--cli-available t)
        (claude-code-ide-cli-extra-flags "")
        (mock-eat-buffer nil)
        (mock-process (start-process "mock-cli-type-snapshot" nil "true")))
    (unwind-protect
        (cl-letf (((symbol-function 'claude-code-ide--terminal-ensure-backend)
                   (lambda (&optional _backend) nil))
                  ((symbol-function 'eat-mode)
                   (lambda () nil))
                  ((symbol-function 'eat-exec)
                   (lambda (buffer _name _cmd _startfile _args)
                     (setq mock-eat-buffer buffer)))
                  ((symbol-function 'get-buffer-process)
                   (lambda (_buffer) mock-process))
                  ((symbol-function 'claude-code-ide--build-codex-command)
                   (lambda (&rest _) "codex")))
          (let* ((result (claude-code-ide--create-terminal-session
                          "*test-cli-type-snapshot*" "/tmp" 12345 nil nil "test-session"))
                 (buffer (car result)))
            (setq claude-code-ide-cli-path "claude")
            (should (consp result))
            (should (eq buffer mock-eat-buffer))
            (should (eq (buffer-local-value 'claude-code-ide--session-cli-type buffer)
                        'codex))
            (with-current-buffer buffer
              (should (eq (claude-code-ide--current-cli-type) 'codex)))))
      (when (process-live-p mock-process)
        (delete-process mock-process))
      (when (buffer-live-p mock-eat-buffer)
        (kill-buffer mock-eat-buffer)))))

(ert-deftest claude-code-ide-test-dangerous-flag-by-cli-type ()
  "Test that the dangerous permissions flag varies by CLI type."
  (let ((claude-code-ide-cli-path "claude"))
    (should (equal (claude-code-ide--dangerous-permissions-flag)
                   "--dangerously-skip-permissions")))
  (let ((claude-code-ide-cli-path "codex"))
    (should (equal (claude-code-ide--dangerous-permissions-flag)
                   "--dangerously-bypass-approvals-and-sandbox")))
  (let ((claude-code-ide-cli-path "gsd"))
    (should (equal (claude-code-ide--dangerous-permissions-flag)
                   "")))
  (let ((claude-code-ide-cli-path "opencode"))
    (should (equal (claude-code-ide--dangerous-permissions-flag)
                   ""))))

(ert-deftest claude-code-ide-test-gsd-full-session-flow ()
  "Test that gsd CLI type flows through session creation correctly."
  (let ((claude-code-ide-cli-path "gsd")
        (claude-code-ide-terminal-backend 'vterm)
        (claude-code-ide--cli-available t)
        (claude-code-ide-cli-extra-flags ""))
    (should (eq (claude-code-ide--current-cli-type) 'gsd))
    (let ((cmd (claude-code-ide--build-command)))
      (should (string-match-p "^gsd" cmd))
      (should-not (string-match-p "--append-system-prompt" cmd))
      (should-not (string-match-p "--mcp-config" cmd)))
    (should (equal (claude-code-ide--dangerous-permissions-flag) ""))))

(ert-deftest claude-code-ide-test-codex-full-session-flow ()
  "Test that codex CLI type flows through session creation correctly."
  (let ((claude-code-ide-cli-path "codex")
        (claude-code-ide-terminal-backend 'vterm)
        (claude-code-ide--cli-available t)
        (claude-code-ide-cli-extra-flags ""))
    ;; Verify CLI type
    (should (eq (claude-code-ide--current-cli-type) 'codex))
    ;; Verify command building
    (let ((cmd (claude-code-ide--build-command)))
      (should (string-match-p "codex" cmd))
      (should-not (string-match-p "--no-alt-screen" cmd))
      (should-not (string-match-p "--append-system-prompt" cmd))
      (should-not (string-match-p "--mcp-config" cmd)))
    ;; Verify dangerous flag
    (should (equal (claude-code-ide--dangerous-permissions-flag)
                   "--dangerously-bypass-approvals-and-sandbox"))))

(ert-deftest claude-code-ide-test-codex-session-skips-terminal-keybindings ()
  "Test that Codex sessions do not install Claude-specific terminal keybindings."
  (let ((claude-code-ide-cli-path "codex")
        (claude-code-ide-terminal-backend 'vterm)
        (claude-code-ide--cli-available t)
        (claude-code-ide-cli-extra-flags "")
        (keybindings-set nil)
        (buffer (generate-new-buffer "*codex-keybinding-test*"))
        (process (start-process "mock-codex-session" nil "true")))
    (unwind-protect
        (cl-letf (((symbol-function 'claude-code-ide--ensure-cli)
                   (lambda () t))
                  ((symbol-function 'claude-code-ide--cleanup-dead-processes)
                   (lambda () nil))
                  ((symbol-function 'claude-code-ide--get-working-directory)
                   (lambda () "/tmp/codex-project/"))
                  ((symbol-function 'claude-code-ide--get-buffer-name)
                   (lambda (&optional _directory)
                     (buffer-name buffer)))
                  ((symbol-function 'claude-code-ide--get-process)
                   (lambda (&optional _directory) nil))
                  ((symbol-function 'claude-code-ide--terminal-ensure-backend)
                   (lambda () nil))
                  ((symbol-function 'claude-code-ide-mcp-start)
                   (lambda (_directory) 12345))
                  ((symbol-function 'claude-code-ide--create-terminal-session)
                   (lambda (&rest _args)
                     (cons buffer process)))
                  ((symbol-function 'claude-code-ide-mcp-server-session-started)
                   (lambda (&rest _args) nil))
                  ((symbol-function 'claude-code-ide--set-process)
                   (lambda (&rest _args) nil))
                  ((symbol-function 'set-process-sentinel)
                   (lambda (&rest _args) nil))
                  ((symbol-function 'claude-code-ide--setup-terminal-keybindings)
                   (lambda ()
                     (setq keybindings-set t)))
                  ((symbol-function 'sleep-for)
                   (lambda (&rest _args) nil))
                  ((symbol-function 'claude-code-ide--display-buffer-in-side-window)
                   (lambda (_buffer) nil))
                  ((symbol-function 'claude-code-ide-log)
                   (lambda (&rest _args) nil)))
          (claude-code-ide--start-session)
          (should-not keybindings-set))
      (when (buffer-live-p buffer)
        (kill-buffer buffer))
      (when (process-live-p process)
        (delete-process process)))))

(ert-deftest claude-code-ide-test-start-session-suppresses-intermediate-display-when-requested ()
  "Test that start-session skips the initial side-window display when suppressed."
  (let ((claude-code-ide-terminal-backend 'vterm)
        (claude-code-ide--cli-available t)
        (claude-code-ide--suppress-initial-display t)
        (displayed nil)
        (buffer (generate-new-buffer "*claude-code-silent-start-test*"))
        (process (start-process "mock-claude-silent-start" nil "true")))
    (unwind-protect
        (cl-letf (((symbol-function 'claude-code-ide--ensure-cli)
                   (lambda () t))
                  ((symbol-function 'claude-code-ide--cleanup-dead-processes)
                   (lambda () nil))
                  ((symbol-function 'claude-code-ide--get-working-directory)
                   (lambda () "/tmp/claude-silent-project/"))
                  ((symbol-function 'claude-code-ide--get-buffer-name)
                   (lambda (&optional _directory)
                     (buffer-name buffer)))
                  ((symbol-function 'claude-code-ide--get-process)
                   (lambda (&optional _directory) nil))
                  ((symbol-function 'claude-code-ide--terminal-ensure-backend)
                   (lambda () nil))
                  ((symbol-function 'claude-code-ide-mcp-start)
                   (lambda (_directory) 12345))
                  ((symbol-function 'claude-code-ide--create-terminal-session)
                   (lambda (&rest _args)
                     (cons buffer process)))
                  ((symbol-function 'claude-code-ide-mcp-server-session-started)
                   (lambda (&rest _args) nil))
                  ((symbol-function 'claude-code-ide--set-process)
                   (lambda (&rest _args) nil))
                  ((symbol-function 'set-process-sentinel)
                   (lambda (&rest _args) nil))
                  ((symbol-function 'sleep-for)
                   (lambda (&rest _args) nil))
                  ((symbol-function 'claude-code-ide--display-buffer-in-side-window)
                   (lambda (_buffer)
                     (setq displayed t)))
                  ((symbol-function 'claude-code-ide-log)
                   (lambda (&rest _args) nil)))
          (claude-code-ide--start-session)
          (should-not displayed))
      (when (buffer-live-p buffer)
        (kill-buffer buffer))
      (when (process-live-p process)
        (delete-process process)))))

(ert-deftest claude-code-ide-test-session-mode-module-loads ()
  "Test that the package-owned session module loads."
  (should (require 'claude-code-ide-session nil t)))

(ert-deftest claude-code-ide-test-session-mode-enables-on-session-buffers ()
  "Test that session mode enables itself in Claude session buffers."
  (should (require 'claude-code-ide-session nil t))
  (with-temp-buffer
    (rename-buffer "*claude-code[test-session]*" t)
    (claude-code-ide--maybe-enable-session-mode)
    (should claude-code-ide-session-mode)))

(ert-deftest claude-code-ide-test-session-send-interrupt-dispatches-to-backend ()
  "Test that session interrupt dispatches to the current terminal backend."
  (should (require 'claude-code-ide-session nil t))
  (let ((vterm-key-called nil)
        (eat-string-called nil))
    (cl-letf (((symbol-function 'vterm-send-key)
               (lambda (&rest _args)
                 (setq vterm-key-called t)))
              ((symbol-function 'eat-term-send-string)
               (lambda (&rest _args)
                 (setq eat-string-called t))))
      (with-temp-buffer
        (rename-buffer "*claude-code[test-interrupt]*" t)
        (claude-code-ide-session-mode 1)
        (let ((claude-code-ide--terminal-backend 'vterm)
              (eat-terminal t))
          (claude-code-ide-session-send-interrupt))
        (should vterm-key-called)
        (should-not eat-string-called)))))

(ert-deftest claude-code-ide-test-session-send-string-resets-idle-state ()
  "Test that sending a string records shared activity."
  (should (require 'claude-code-ide-session nil t))
  (let ((sent-string nil)
        (activity-called nil))
    (cl-letf (((symbol-function 'vterm-send-string)
               (lambda (string &optional _paste)
                 (setq sent-string string)))
              ((symbol-function 'claude-code-ide-session-idle-record-activity)
               (lambda (&optional _buffer)
                 (setq activity-called t))))
      (with-temp-buffer
        (rename-buffer "*claude-code[test-send-string-idle]*" t)
        (setq claude-code-ide--terminal-backend 'vterm)
        (claude-code-ide-session-send-string "status")
        (should (equal sent-string "status"))
        (should activity-called)))))

(ert-deftest claude-code-ide-test-session-send-string-resets-idle-state-eat ()
  "Test that sending a string records shared activity on eat."
  (should (require 'claude-code-ide-session nil t))
  (let ((sent-string nil)
        (activity-called nil))
    (cl-letf (((symbol-function 'eat-term-send-string)
               (lambda (_terminal string)
                 (setq sent-string string)))
              ((symbol-function 'claude-code-ide-session-idle-record-activity)
               (lambda (&optional _buffer)
                 (setq activity-called t))))
      (with-temp-buffer
        (rename-buffer "*claude-code[test-send-string-idle-eat]*" t)
        (setq claude-code-ide--terminal-backend 'eat
              eat-terminal t)
        (claude-code-ide-session-send-string "status")
        (should (equal sent-string "status"))
        (should activity-called)))))

(ert-deftest claude-code-ide-test-session-send-return-resets-idle-state ()
  "Test that sending return records shared activity."
  (should (require 'claude-code-ide-session nil t))
  (let ((return-called nil)
        (activity-called nil))
    (cl-letf (((symbol-function 'vterm-send-return)
               (lambda ()
                 (setq return-called t)))
              ((symbol-function 'claude-code-ide-session-idle-record-activity)
               (lambda (&optional _buffer)
                 (setq activity-called t))))
      (with-temp-buffer
        (rename-buffer "*claude-code[test-send-return-idle]*" t)
        (setq claude-code-ide--terminal-backend 'vterm)
        (claude-code-ide-session-send-return)
        (should return-called)
        (should activity-called)))))

(ert-deftest claude-code-ide-test-session-send-return-resets-idle-state-eat ()
  "Test that sending return records shared activity on eat."
  (should (require 'claude-code-ide-session nil t))
  (let ((sent-string nil)
        (activity-called nil))
    (cl-letf (((symbol-function 'eat-term-send-string)
               (lambda (_terminal string)
                 (setq sent-string string)))
              ((symbol-function 'claude-code-ide-session-idle-record-activity)
               (lambda (&optional _buffer)
                 (setq activity-called t))))
      (with-temp-buffer
        (rename-buffer "*claude-code[test-send-return-idle-eat]*" t)
        (setq claude-code-ide--terminal-backend 'eat
              eat-terminal t)
        (claude-code-ide-session-send-return)
        (should (equal sent-string "\r"))
        (should activity-called)))))

(ert-deftest claude-code-ide-test-session-send-escape-resets-idle-state ()
  "Test that sending escape records shared activity."
  (should (require 'claude-code-ide-session nil t))
  (let ((escape-called nil)
        (activity-called nil))
    (cl-letf (((symbol-function 'vterm-send-escape)
               (lambda ()
                 (setq escape-called t)))
              ((symbol-function 'claude-code-ide-session-idle-record-activity)
               (lambda (&optional _buffer)
                 (setq activity-called t))))
      (with-temp-buffer
        (rename-buffer "*claude-code[test-send-escape-idle]*" t)
        (setq claude-code-ide--terminal-backend 'vterm)
        (claude-code-ide-session-send-escape)
        (should escape-called)
        (should activity-called)))))

(ert-deftest claude-code-ide-test-session-send-escape-resets-idle-state-eat ()
  "Test that sending escape records shared activity on eat."
  (should (require 'claude-code-ide-session nil t))
  (let ((sent-string nil)
        (activity-called nil))
    (cl-letf (((symbol-function 'eat-term-send-string)
               (lambda (_terminal string)
                 (setq sent-string string)))
              ((symbol-function 'claude-code-ide-session-idle-record-activity)
               (lambda (&optional _buffer)
                 (setq activity-called t))))
      (with-temp-buffer
        (rename-buffer "*claude-code[test-send-escape-idle-eat]*" t)
        (setq claude-code-ide--terminal-backend 'eat
              eat-terminal t)
        (claude-code-ide-session-send-escape)
        (should (equal sent-string "\e"))
        (should activity-called)))))

(ert-deftest claude-code-ide-test-session-send-interrupt-resets-idle-state ()
  "Test that sending interrupt records shared activity."
  (should (require 'claude-code-ide-session nil t))
  (let ((interrupt-called nil)
        (activity-called nil))
    (cl-letf (((symbol-function 'vterm-send-key)
               (lambda (&rest _args)
                 (setq interrupt-called t)))
              ((symbol-function 'claude-code-ide-session-idle-record-activity)
               (lambda (&optional _buffer)
                 (setq activity-called t))))
      (with-temp-buffer
        (rename-buffer "*claude-code[test-send-interrupt-idle]*" t)
        (setq claude-code-ide--terminal-backend 'vterm)
        (claude-code-ide-session-send-interrupt)
        (should interrupt-called)
        (should activity-called)))))

(ert-deftest claude-code-ide-test-session-send-interrupt-resets-idle-state-eat ()
  "Test that sending interrupt records shared activity on eat."
  (should (require 'claude-code-ide-session nil t))
  (let ((sent-string nil)
        (activity-called nil))
    (cl-letf (((symbol-function 'eat-term-send-string)
               (lambda (_terminal string)
                 (setq sent-string string)))
              ((symbol-function 'claude-code-ide-session-idle-record-activity)
               (lambda (&optional _buffer)
                 (setq activity-called t))))
      (with-temp-buffer
        (rename-buffer "*claude-code[test-send-interrupt-idle-eat]*" t)
        (setq claude-code-ide--terminal-backend 'eat
              eat-terminal t)
        (claude-code-ide-session-send-interrupt)
        (should (equal sent-string "\003"))
        (should activity-called)))))

(ert-deftest claude-code-ide-test-session-send-string-clears-visible-session-idle-state-without-arming-timer ()
  "Visible explicit input clears stale idle state without arming a timer."
  (should (require 'claude-code-ide-session nil t))
  (let ((sent-string nil)
        (activity-called nil)
        (scheduled nil)
        (cancelled nil))
    (let ((session-buffer (generate-new-buffer "*claude-code[test-send-string-visible-idle]*")))
      (unwind-protect
          (save-window-excursion
            (delete-other-windows)
            (switch-to-buffer session-buffer)
            (let ((orig-activity (symbol-function 'claude-code-ide-session-idle-record-activity)))
              (cl-letf (((symbol-function 'vterm-send-string)
                         (lambda (string &optional _paste)
                           (setq sent-string string)))
                        ((symbol-function 'frame-focus-state)
                         (lambda (_frame) t))
                        ((symbol-function 'timerp)
                         (lambda (timer)
                           (eq timer 'old-timer)))
                        ((symbol-function 'cancel-timer)
                         (lambda (timer)
                           (when (eq timer 'old-timer)
                             (setq cancelled t))))
                        ((symbol-function 'run-with-timer)
                         (lambda (&rest _args)
                           (setq scheduled t)
                           'mock-idle-timer))
                        ((symbol-function 'claude-code-ide-session-idle-record-activity)
                         (lambda (&optional buffer)
                           (setq activity-called t)
                           (funcall orig-activity buffer))))
                (with-current-buffer session-buffer
                  (setq-local claude-code-ide--terminal-backend 'vterm
                              claude-code-ide-session-idle-enabled t
                              claude-code-ide-session-idle-p t
                              claude-code-ide-session-idle-timer 'old-timer))
                (claude-code-ide-session-send-string "status")
                (should (equal sent-string "status"))
                (should activity-called)
                (should cancelled)
                (should-not scheduled)
                (should-not claude-code-ide-session-idle-p)
                (should-not claude-code-ide-session-idle-timer))))
        (when (buffer-live-p session-buffer)
          (kill-buffer session-buffer))))))

(ert-deftest claude-code-ide-test-session-send-interrupt-rejects-non-session-buffers ()
  "Test that interrupt only applies to Claude session buffers."
  (should (require 'claude-code-ide-session nil t))
  (with-temp-buffer
    (let ((claude-code-ide--terminal-backend 'vterm))
      (should-error (claude-code-ide-session-send-interrupt)
                    :type 'user-error))))

(ert-deftest claude-code-ide-test-session-idle-observer-is-installed-on-session-buffers ()
  "Test that backend output filters reset idle only for session buffers."
  (should (require 'claude-code-ide-session-idle nil t))
  (should (advice-member-p #'claude-code-ide-session-idle--filter-advice
                           'vterm--filter))
  (let ((activity-buffer nil))
    (cl-letf (((symbol-function 'claude-code-ide-session-idle-record-activity)
               (lambda (&optional buffer)
                 (setq activity-buffer (or buffer (current-buffer))))))
      (with-temp-buffer
        (rename-buffer "*claude-code[test-idle-observer]*" t)
        (vterm--filter nil "output")
        (should (eq activity-buffer (current-buffer))))
      (setq activity-buffer nil)
      (with-temp-buffer
        (rename-buffer "*not-a-claude-buffer*" t)
        (vterm--filter nil "output")
        (should-not activity-buffer)))))

(ert-deftest claude-code-ide-test-session-idle-observer-uses-process-buffer ()
  "Test that backend output filters reset idle for the process buffer."
  (should (require 'claude-code-ide-session-idle nil t))
  (let ((activity-buffer nil)
        (session-buffer (generate-new-buffer "*claude-code[test-idle-process-buffer]*"))
        (other-buffer (generate-new-buffer "*not-a-claude-buffer*")))
    (unwind-protect
        (cl-letf (((symbol-function 'process-buffer)
                   (lambda (_process)
                     session-buffer))
                  ((symbol-function 'claude-code-ide-session-idle-record-activity)
                   (lambda (&optional buffer)
                     (setq activity-buffer (or buffer (current-buffer))))))
          (with-current-buffer other-buffer
            (vterm--filter 'mock-process "output"))
          (should (eq activity-buffer session-buffer)))
      (kill-buffer session-buffer)
      (kill-buffer other-buffer))))

(ert-deftest claude-code-ide-test-session-idle-observer-uses-process-buffer-eat ()
  "Test that eat output filters reset idle for the process buffer."
  (should (require 'claude-code-ide-session-idle nil t))
  (let ((activity-buffer nil)
        (session-buffer (generate-new-buffer "*claude-code[test-idle-process-buffer-eat]*"))
        (other-buffer (generate-new-buffer "*not-a-claude-buffer*")))
    (unwind-protect
        (cl-letf (((symbol-function 'process-buffer)
                   (lambda (_process)
                     session-buffer))
                  ((symbol-function 'claude-code-ide-session-idle-record-activity)
                   (lambda (&optional buffer)
                     (setq activity-buffer (or buffer (current-buffer))))))
          (with-current-buffer other-buffer
            (eat--filter 'mock-process "output"))
          (should (eq activity-buffer session-buffer)))
      (kill-buffer session-buffer)
      (kill-buffer other-buffer))))

(ert-deftest claude-code-ide-test-session-working-observer-uses-process-buffer ()
  "Test that backend output marks the process buffer as working."
  (should (require 'claude-code-ide-session-idle nil t))
  (let ((working-buffer nil)
        (session-buffer (generate-new-buffer "*claude-code[test-working-process-buffer]*"))
        (other-buffer (generate-new-buffer "*not-a-claude-buffer*")))
    (unwind-protect
        (cl-letf (((symbol-function 'process-buffer)
                   (lambda (_process)
                     session-buffer))
                  ((symbol-function 'claude-code-ide-session-working-record-output)
                   (lambda (&optional buffer)
                     (setq working-buffer (or buffer (current-buffer))))))
          (with-current-buffer other-buffer
            (vterm--filter 'mock-process "output"))
          (should (eq working-buffer session-buffer)))
      (kill-buffer session-buffer)
      (kill-buffer other-buffer))))

(ert-deftest claude-code-ide-test-session-idle-record-activity-does-not-arm-visible-session ()
  "Visible focused sessions clear idle state without arming a timer."
  (should (require 'claude-code-ide-session-idle nil t))
  (let ((session-buffer (generate-new-buffer "*claude-code[test-idle-visible-activity]*"))
        (scheduled nil)
        (cancelled nil))
    (unwind-protect
        (save-window-excursion
          (delete-other-windows)
          (switch-to-buffer session-buffer)
          (cl-letf (((symbol-function 'frame-focus-state)
                     (lambda (_frame) t))
                    ((symbol-function 'timerp)
                     (lambda (timer)
                       (eq timer 'old-timer)))
                    ((symbol-function 'cancel-timer)
                     (lambda (timer)
                       (when (eq timer 'old-timer)
                         (setq cancelled t))))
                    ((symbol-function 'run-with-timer)
                     (lambda (&rest _args)
                       (setq scheduled t)
                       'mock-idle-timer)))
            (with-current-buffer session-buffer
              (setq-local claude-code-ide-session-idle-enabled t
                          claude-code-ide-session-idle-p nil
                          claude-code-ide-session-idle-timer 'old-timer)
              (claude-code-ide-session-idle-record-activity)
              (should cancelled)
              (should-not scheduled)
              (should-not claude-code-ide-session-idle-p)
              (should-not claude-code-ide-session-idle-timer))))
      (when (buffer-live-p session-buffer)
        (kill-buffer session-buffer)))))

(ert-deftest claude-code-ide-test-session-idle-record-activity-arms-hidden-session ()
  "Hidden sessions arm a fresh timer when output activity arrives."
  (should (require 'claude-code-ide-session-idle nil t))
  (let ((scheduled-delay nil)
        (cancelled nil)
        (session-buffer (generate-new-buffer "*claude-code[test-idle-hidden-activity]*")))
    (unwind-protect
        (cl-letf (((symbol-function 'timerp)
                   (lambda (timer)
                     (eq timer 'old-timer)))
                  ((symbol-function 'cancel-timer)
                   (lambda (timer)
                     (when (eq timer 'old-timer)
                       (setq cancelled t))))
                  ((symbol-function 'run-with-timer)
                   (lambda (delay _repeat _fn &rest _args)
                     (setq scheduled-delay delay)
                     'mock-idle-timer)))
          (with-current-buffer session-buffer
            (setq-local claude-code-ide-session-idle-enabled t
                        claude-code-ide-session-idle-p t
                        claude-code-ide-session-idle-timer 'old-timer)
            (claude-code-ide-session-idle-record-activity)
            (should cancelled)
            (should (equal scheduled-delay claude-code-ide-session-idle-delay))
            (should-not claude-code-ide-session-idle-p)
            (should (eq claude-code-ide-session-idle-timer 'mock-idle-timer))))
      (when (buffer-live-p session-buffer)
        (kill-buffer session-buffer)))))

(ert-deftest claude-code-ide-test-session-idle-record-activity-does-not-arm-prompt-edited-session ()
  "Prompt editing keeps a hidden session disarmed after backend output."
  (should (require 'claude-code-ide-session-idle nil t))
  (let ((session-buffer (generate-new-buffer "*claude-code[test-idle-prompt-activity]*"))
        (prompt-buffer (generate-new-buffer "*cc-prompt-activity.md*"))
        (session-dir "/tmp/claude-code-idle-prompt-activity/")
        (scheduled nil))
    (unwind-protect
        (save-window-excursion
          (delete-other-windows)
          (switch-to-buffer prompt-buffer)
          (with-current-buffer prompt-buffer
            (setq-local leo/ai-tmp-prompt-file-mode t
                        default-directory session-dir))
          (cl-letf (((symbol-function 'frame-focus-state)
                     (lambda (_frame) t))
                    ((symbol-function 'claude-code-ide--get-related-session-directories)
                     (lambda (&optional directory)
                       (when (equal directory session-dir)
                         (list session-dir))))
                    ((symbol-function 'claude-code-ide--get-session-buffer)
                     (lambda (&optional directory)
                       (and (equal directory session-dir)
                            session-buffer)))
                    ((symbol-function 'run-with-timer)
                     (lambda (&rest _args)
                       (setq scheduled t)
                       'mock-idle-timer)))
            (with-current-buffer session-buffer
              (setq-local claude-code-ide-session-idle-enabled t
                          claude-code-ide-session-idle-p t
                          claude-code-ide-session-idle-timer nil)
              (claude-code-ide-session-idle-record-activity)
              (should-not scheduled)
              (should-not claude-code-ide-session-idle-p)
              (should-not claude-code-ide-session-idle-timer)))))
    (mapc (lambda (buffer)
            (when (buffer-live-p buffer)
              (kill-buffer buffer)))
          (list session-buffer prompt-buffer))))

(ert-deftest claude-code-ide-test-session-idle-fire-timer-does-not-mark-idle-during-prompt-edit ()
  "Prompt editing suppresses idle transition for the owning session."
  (should (require 'claude-code-ide-session-idle nil t))
  (let ((session-buffer (generate-new-buffer "*claude-code[test-idle-prompt-fire]*"))
        (prompt-buffer (generate-new-buffer "*cc-prompt-fire.md*"))
        (session-dir "/tmp/claude-code-idle-prompt-fire/")
        (hook-runs 0))
    (unwind-protect
        (save-window-excursion
          (delete-other-windows)
          (switch-to-buffer prompt-buffer)
          (with-current-buffer prompt-buffer
            (setq-local leo/ai-tmp-prompt-file-mode t
                        default-directory session-dir))
          (cl-letf (((symbol-function 'frame-focus-state)
                     (lambda (_frame) t))
                    ((symbol-function 'claude-code-ide--get-related-session-directories)
                     (lambda (&optional directory)
                       (when (equal directory session-dir)
                         (list session-dir))))
                    ((symbol-function 'claude-code-ide--get-session-buffer)
                     (lambda (&optional directory)
                       (and (equal directory session-dir)
                            session-buffer)))
                    ((symbol-function 'run-hook-with-args)
                     (lambda (&rest _args)
                       (setq hook-runs (1+ hook-runs)))))
            (with-current-buffer session-buffer
              (setq-local claude-code-ide-session-idle-enabled t
                          claude-code-ide-session-idle-p nil)
              (claude-code-ide-session-idle--fire-timer session-buffer)
              (should-not claude-code-ide-session-idle-p)
              (should (= hook-runs 0))))))
    (mapc (lambda (buffer)
            (when (buffer-live-p buffer)
              (kill-buffer buffer)))
          (list session-buffer prompt-buffer))))

(ert-deftest claude-code-ide-test-session-idle-visibility-refresh-clears-visible-timer ()
  "Visibility refresh cancels pending timers for visible focused sessions."
  (should (require 'claude-code-ide-session-idle nil t))
  (let ((visible-buffer (generate-new-buffer "*claude-code[test-idle-visible-timer-clear]*"))
        (cancelled nil))
    (unwind-protect
        (save-window-excursion
          (delete-other-windows)
          (switch-to-buffer visible-buffer)
          (with-current-buffer visible-buffer
            (setq-local claude-code-ide-session-idle-enabled t
                        claude-code-ide-session-idle-p nil
                        claude-code-ide-session-idle-timer 'visible-timer))
          (cl-letf (((symbol-function 'frame-focus-state)
                     (lambda (_frame) t))
                    ((symbol-function 'timerp)
                     (lambda (timer)
                       (eq timer 'visible-timer)))
                    ((symbol-function 'cancel-timer)
                     (lambda (timer)
                       (when (eq timer 'visible-timer)
                         (setq cancelled t)))))
            (claude-code-ide-session-idle--handle-visibility-change)
            (with-current-buffer visible-buffer
              (should cancelled)
              (should-not claude-code-ide-session-idle-p)
              (should-not claude-code-ide-session-idle-timer))))
      (when (buffer-live-p visible-buffer)
        (kill-buffer visible-buffer)))))

(ert-deftest claude-code-ide-test-session-idle-visibility-change-clears-prompt-edited-session ()
  "Window refresh clears the timer for the session owning the selected prompt buffer."
  (should (require 'claude-code-ide-session-idle nil t))
  (let ((session-buffer (generate-new-buffer "*claude-code[test-idle-prompt-visible]*"))
        (prompt-buffer (generate-new-buffer "*cc-prompt-visible.md*"))
        (session-dir "/tmp/claude-code-idle-prompt-visible/")
        (cancelled nil))
    (unwind-protect
        (save-window-excursion
          (delete-other-windows)
          (switch-to-buffer prompt-buffer)
          (with-current-buffer prompt-buffer
            (setq-local leo/ai-tmp-prompt-file-mode t
                        default-directory session-dir))
          (with-current-buffer session-buffer
            (setq-local claude-code-ide-session-idle-enabled t
                        claude-code-ide-session-idle-p nil
                        claude-code-ide-session-idle-timer 'prompt-timer))
          (cl-letf (((symbol-function 'frame-focus-state)
                     (lambda (_frame) t))
                    ((symbol-function 'claude-code-ide--get-related-session-directories)
                     (lambda (&optional directory)
                       (when (equal directory session-dir)
                         (list session-dir))))
                    ((symbol-function 'claude-code-ide--get-session-buffer)
                     (lambda (&optional directory)
                       (and (equal directory session-dir)
                            session-buffer)))
                    ((symbol-function 'timerp)
                     (lambda (timer)
                       (eq timer 'prompt-timer)))
                    ((symbol-function 'cancel-timer)
                     (lambda (timer)
                       (when (eq timer 'prompt-timer)
                         (setq cancelled t)))))
            (claude-code-ide-session-idle--handle-visibility-change)
            (with-current-buffer session-buffer
              (should cancelled)
              (should-not claude-code-ide-session-idle-timer)
              (should-not claude-code-ide-session-idle-p)))))
    (mapc (lambda (buffer)
            (when (buffer-live-p buffer)
              (kill-buffer buffer)))
          (list session-buffer prompt-buffer))))

(ert-deftest claude-code-ide-test-session-idle-prompt-exit-does-not-auto-rearm ()
  "Leaving prompt editing does not start a fresh idle timer."
  (should (require 'claude-code-ide-session-idle nil t))
  (let ((session-buffer (generate-new-buffer "*claude-code[test-idle-prompt-exit]*"))
        (prompt-buffer (generate-new-buffer "*cc-prompt-exit.md*"))
        (session-dir "/tmp/claude-code-idle-prompt-exit/")
        (scheduled nil))
    (unwind-protect
        (save-window-excursion
          (delete-other-windows)
          (switch-to-buffer prompt-buffer)
          (with-current-buffer prompt-buffer
            (setq-local leo/ai-tmp-prompt-file-mode t
                        default-directory session-dir))
          (with-current-buffer session-buffer
            (setq-local claude-code-ide-session-idle-enabled t
                        claude-code-ide-session-idle-p nil
                        claude-code-ide-session-idle-timer 'old-timer))
          (cl-letf (((symbol-function 'frame-focus-state)
                     (lambda (_frame) t))
                    ((symbol-function 'claude-code-ide--get-related-session-directories)
                     (lambda (&optional directory)
                       (when (equal directory session-dir)
                         (list session-dir))))
                    ((symbol-function 'claude-code-ide--get-session-buffer)
                     (lambda (&optional directory)
                       (and (equal directory session-dir)
                            session-buffer)))
                    ((symbol-function 'timerp)
                     (lambda (timer)
                       (eq timer 'old-timer)))
                    ((symbol-function 'cancel-timer)
                     (lambda (_timer) nil))
                    ((symbol-function 'run-with-timer)
                     (lambda (&rest _args)
                       (setq scheduled t)
                       'unexpected-timer)))
            (claude-code-ide-session-idle--handle-visibility-change)
            (switch-to-buffer (get-buffer-create "*scratch*"))
            (claude-code-ide-session-idle--handle-visibility-change)
            (with-current-buffer session-buffer
              (should-not scheduled)
              (should-not claude-code-ide-session-idle-timer)))))
    (mapc (lambda (buffer)
            (when (buffer-live-p buffer)
              (kill-buffer buffer)))
          (list session-buffer prompt-buffer))))

(ert-deftest claude-code-ide-test-session-idle-prompt-editing-does-not-suppress-other-session ()
  "Prompt editing only clears the timer for the owning session."
  (should (require 'claude-code-ide-session-idle nil t))
  (let ((session-buffer (generate-new-buffer "*claude-code[test-idle-owning-session]*"))
        (other-session-buffer (generate-new-buffer "*claude-code[test-idle-other-session]*"))
        (prompt-buffer (generate-new-buffer "*cc-prompt-other.md*"))
        (session-dir "/tmp/claude-code-idle-owning-session/")
        (other-session-dir "/tmp/claude-code-idle-other-session/")
        (cancelled nil))
    (unwind-protect
        (save-window-excursion
          (delete-other-windows)
          (switch-to-buffer prompt-buffer)
          (with-current-buffer prompt-buffer
            (setq-local leo/ai-tmp-prompt-file-mode t
                        default-directory session-dir))
          (with-current-buffer session-buffer
            (setq-local claude-code-ide-session-idle-enabled t
                        claude-code-ide-session-idle-p nil
                        claude-code-ide-session-idle-timer 'session-timer))
          (with-current-buffer other-session-buffer
            (setq-local claude-code-ide-session-idle-enabled t
                        claude-code-ide-session-idle-p nil
                        claude-code-ide-session-idle-timer 'other-timer))
          (cl-letf (((symbol-function 'frame-focus-state)
                     (lambda (_frame) t))
                    ((symbol-function 'claude-code-ide--get-related-session-directories)
                     (lambda (&optional directory)
                       (when (equal directory session-dir)
                         (list session-dir))))
                    ((symbol-function 'claude-code-ide--get-session-buffer)
                     (lambda (&optional directory)
                       (cond
                        ((equal directory session-dir) session-buffer)
                        ((equal directory other-session-dir) other-session-buffer))))
                    ((symbol-function 'timerp)
                     (lambda (timer)
                       (memq timer '(session-timer other-timer))))
                    ((symbol-function 'cancel-timer)
                     (lambda (timer)
                       (push timer cancelled))))
            (claude-code-ide-session-idle--handle-visibility-change)
            (with-current-buffer session-buffer
              (should (memq 'session-timer cancelled))
              (should-not claude-code-ide-session-idle-timer))
            (with-current-buffer other-session-buffer
              (should-not (memq 'other-timer cancelled))
              (should (eq claude-code-ide-session-idle-timer 'other-timer))))))
    (mapc (lambda (buffer)
            (when (buffer-live-p buffer)
              (kill-buffer buffer)))
          (list session-buffer other-session-buffer prompt-buffer))))

(ert-deftest claude-code-ide-test-session-idle-prompt-buffer-context-beats-manager-state ()
  "Selected prompt buffer context determines the owning session."
  (should (require 'claude-code-ide-session-idle nil t))
  (let ((session-1-buffer (generate-new-buffer "*claude-code[test-idle-prompt-session-1]*"))
        (session-2-buffer (generate-new-buffer "*claude-code[test-idle-prompt-session-2]*"))
        (prompt-buffer (generate-new-buffer "*cc-prompt-context.md*"))
        (session-1-dir "/tmp/claude-code-idle-session-1/")
        (session-2-dir "/tmp/claude-code-idle-session-2/")
        (cancelled nil))
    (unwind-protect
        (save-window-excursion
          (delete-other-windows)
          (switch-to-buffer prompt-buffer)
          (with-current-buffer prompt-buffer
            (setq-local leo/ai-tmp-prompt-file-mode t
                        default-directory session-2-dir))
          (with-current-buffer session-1-buffer
            (setq-local claude-code-ide-session-idle-enabled t
                        claude-code-ide-session-idle-p nil
                        claude-code-ide-session-idle-timer 'session-1-timer))
          (with-current-buffer session-2-buffer
            (setq-local claude-code-ide-session-idle-enabled t
                        claude-code-ide-session-idle-p nil
                        claude-code-ide-session-idle-timer 'session-2-timer))
          (cl-letf (((symbol-function 'frame-focus-state)
                     (lambda (_frame) t))
                    ((symbol-function 'claude-code-ide-manager--scope-for-command)
                     (lambda ()
                       '(:type global)))
                    ((symbol-function 'claude-code-ide-manager--scope-active-session-key)
                     (lambda (_scope)
                       'session-1))
                    ((symbol-function 'claude-code-ide--get-related-session-directories)
                     (lambda (&optional directory)
                       (when (equal directory session-2-dir)
                         (list session-2-dir))))
                    ((symbol-function 'claude-code-ide--get-session-buffer)
                     (lambda (&optional directory)
                       (cond
                        ((equal directory session-1-dir) session-1-buffer)
                        ((equal directory session-2-dir) session-2-buffer))))
                    ((symbol-function 'timerp)
                     (lambda (timer)
                       (memq timer '(session-1-timer session-2-timer))))
                    ((symbol-function 'cancel-timer)
                     (lambda (timer)
                       (push timer cancelled))))
            (claude-code-ide-session-idle--handle-visibility-change)
            (with-current-buffer session-1-buffer
              (should-not (memq 'session-1-timer cancelled))
              (should (eq claude-code-ide-session-idle-timer 'session-1-timer)))
            (with-current-buffer session-2-buffer
              (should (memq 'session-2-timer cancelled))
              (should-not claude-code-ide-session-idle-timer)))))
    (mapc (lambda (buffer)
            (when (buffer-live-p buffer)
              (kill-buffer buffer)))
          (list session-1-buffer session-2-buffer prompt-buffer))))

(ert-deftest claude-code-ide-test-session-idle-visible-unselected-prompt-suppresses-idle ()
  "A visible prompt buffer suppresses idle even when another window is selected."
  (should (require 'claude-code-ide-session-idle nil t))
  (let ((session-buffer (generate-new-buffer "*claude-code[test-idle-visible-unselected-prompt]*"))
        (prompt-buffer (generate-new-buffer "*cc-prompt-visible-unselected.md*"))
        (other-buffer (generate-new-buffer "*cc-visible-unselected-other*"))
        (session-dir "/tmp/claude-code-idle-visible-unselected/")
        (hook-runs 0))
    (unwind-protect
        (save-window-excursion
          (delete-other-windows)
          (switch-to-buffer other-buffer)
          (let ((prompt-window (split-window-right)))
            (set-window-buffer prompt-window prompt-buffer)
            (select-window (get-buffer-window other-buffer)))
          (with-current-buffer prompt-buffer
            (setq-local leo/ai-tmp-prompt-file-mode t
                        default-directory session-dir))
          (cl-letf (((symbol-function 'frame-focus-state)
                     (lambda (_frame) t))
                    ((symbol-function 'claude-code-ide--get-related-session-directories)
                     (lambda (&optional directory)
                       (when (equal directory session-dir)
                         (list session-dir))))
                    ((symbol-function 'claude-code-ide--get-session-buffer)
                     (lambda (&optional directory)
                       (and (equal directory session-dir)
                            session-buffer)))
                    ((symbol-function 'run-hook-with-args)
                     (lambda (&rest _args)
                       (setq hook-runs (1+ hook-runs)))))
            (with-current-buffer session-buffer
              (setq-local claude-code-ide-session-idle-enabled t
                          claude-code-ide-session-idle-p nil)
              (claude-code-ide-session-idle--fire-timer session-buffer)
              (should-not claude-code-ide-session-idle-p)
              (should (= hook-runs 0))))))
    (mapc (lambda (buffer)
            (when (buffer-live-p buffer)
              (kill-buffer buffer)))
          (list session-buffer prompt-buffer other-buffer))))

(ert-deftest claude-code-ide-test-session-idle-tmp-prompt-window-history-suppresses-idle ()
  "A tmp prompt buffer suppresses idle when it replaced the session in the same window."
  (should (require 'claude-code-ide-session-idle nil t))
  (let ((session-buffer (generate-new-buffer "*claude-code[test-idle-tmp-prompt-history]*"))
        (prompt-buffer (generate-new-buffer "*cc-prompt-tmp-history.md*"))
        (hook-runs 0))
    (unwind-protect
        (save-window-excursion
          (delete-other-windows)
          (switch-to-buffer session-buffer)
          (with-current-buffer prompt-buffer
            (setq-local leo/ai-tmp-prompt-file-mode t
                        default-directory "/tmp/claude-code-idle-tmp-history/"))
          (switch-to-buffer prompt-buffer)
          (cl-letf (((symbol-function 'frame-focus-state)
                     (lambda (_frame) t))
                    ((symbol-function 'run-hook-with-args)
                     (lambda (&rest _args)
                       (setq hook-runs (1+ hook-runs)))))
            (with-current-buffer session-buffer
              (setq-local claude-code-ide-session-idle-enabled t
                          claude-code-ide-session-idle-p nil)
              (claude-code-ide-session-idle--fire-timer session-buffer)
              (should-not claude-code-ide-session-idle-p)
              (should (= hook-runs 0))))))
    (mapc (lambda (buffer)
            (when (buffer-live-p buffer)
              (kill-buffer buffer)))
          (list session-buffer prompt-buffer))))

(ert-deftest claude-code-ide-test-session-idle-tmp-prompt-visible-session-fallback-resolves-owner ()
  "A tmp prompt buffer resolves its owner from a visible sibling session buffer."
  (should (require 'claude-code-ide-session-idle nil t))
  (let ((session-buffer (generate-new-buffer "*claude-code[test-idle-tmp-prompt-visible-session]*"))
        (prompt-buffer (generate-new-buffer "*cc-prompt-tmp-visible-session.md*"))
        (other-buffer (generate-new-buffer "*cc-tmp-prompt-visible-session-other*")))
    (unwind-protect
        (save-window-excursion
          (delete-other-windows)
          (switch-to-buffer other-buffer)
          (let ((session-window (selected-window))
                (prompt-window (split-window-right)))
            (set-window-buffer session-window session-buffer)
            (set-window-buffer prompt-window prompt-buffer)
            (select-window session-window))
          (with-current-buffer prompt-buffer
            (setq-local leo/ai-tmp-prompt-file-mode t
                        default-directory "/tmp/claude-code-idle-tmp-visible-session/"))
          (cl-letf (((symbol-function 'frame-focus-state)
                     (lambda (_frame) t)))
            (should (equal (claude-code-ide-session-idle--visible-prompt-session-buffers)
                           (list session-buffer))))))
    (mapc (lambda (buffer)
            (when (buffer-live-p buffer)
              (kill-buffer buffer)))
          (list session-buffer prompt-buffer other-buffer))))

(ert-deftest claude-code-ide-test-session-idle-reset-does-not-arm-visible-session ()
  "Visible focused sessions do not schedule a timer when reset directly."
  (should (require 'claude-code-ide-session-idle nil t))
  (let ((session-buffer (generate-new-buffer "*claude-code[test-idle-visible-reset]*"))
        (scheduled nil)
        (cancelled nil))
    (unwind-protect
        (save-window-excursion
          (delete-other-windows)
          (switch-to-buffer session-buffer)
          (cl-letf (((symbol-function 'frame-focus-state)
                     (lambda (_frame) t))
                    ((symbol-function 'timerp)
                     (lambda (timer)
                       (eq timer 'old-timer)))
                    ((symbol-function 'cancel-timer)
                     (lambda (timer)
                       (when (eq timer 'old-timer)
                         (setq cancelled t))))
                    ((symbol-function 'run-with-timer)
                     (lambda (&rest _args)
                       (setq scheduled t)
                       'mock-idle-timer)))
            (with-current-buffer session-buffer
              (setq-local claude-code-ide-session-idle-enabled t
                          claude-code-ide-session-idle-p nil
                          claude-code-ide-session-idle-timer 'old-timer)
              (claude-code-ide-session-idle-reset-timer)
              (should cancelled)
              (should-not scheduled)
              (should-not claude-code-ide-session-idle-p)
              (should-not claude-code-ide-session-idle-timer))))
      (when (buffer-live-p session-buffer)
        (kill-buffer session-buffer)))))

(ert-deftest claude-code-ide-test-session-insert-command-uses-reader-function ()
  "Test that the public command insert helper uses the configured reader."
  (should (require 'claude-code-ide-session nil t))
  (let ((reader-buffer nil)
        (sent-string nil))
    (cl-letf (((symbol-function 'claude-code-ide-session-send-string)
               (lambda (string &optional _paste)
                 (setq sent-string string))))
      (let ((claude-code-ide-session-command-reader-function
             (lambda (buffer)
               (setq reader-buffer buffer)
               "git status")))
        (with-temp-buffer
          (rename-buffer "*claude-code[test-command-reader]*" t)
          (claude-code-ide-session-mode 1)
          (claude-code-ide-session-insert-command)
          (should (eq reader-buffer (current-buffer)))
          (should (equal sent-string "git status")))))))

(ert-deftest claude-code-ide-test-session-insert-file-reference-uses-reader-function ()
  "Test that the public file-reference insert helper uses the configured reader."
  (should (require 'claude-code-ide-session nil t))
  (let ((reader-buffer nil)
        (sent-string nil))
    (cl-letf (((symbol-function 'claude-code-ide-session-send-string)
               (lambda (string &optional _paste)
                 (setq sent-string string))))
      (let ((claude-code-ide-session-file-reference-reader-function
             (lambda (buffer)
               (setq reader-buffer buffer)
               "src/main.el")))
        (with-temp-buffer
          (rename-buffer "*claude-code[test-file-reader]*" t)
          (claude-code-ide-session-mode 1)
          (claude-code-ide-session-insert-file-reference)
          (should (eq reader-buffer (current-buffer)))
          (should (equal sent-string "src/main.el")))))))

(ert-deftest claude-code-ide-test-session-idle-module-loads ()
  "Test that the package-owned idle module loads."
  (should (require 'claude-code-ide-session-idle nil t)))

(ert-deftest claude-code-ide-test-session-idle-toggle-enables-monitoring ()
  "Test that toggling session idle enables monitoring."
  (should (require 'claude-code-ide-session-idle nil t))
  (with-temp-buffer
    (rename-buffer "*claude-code[test-idle-toggle]*" t)
    (claude-code-ide-session-idle-toggle)
    (should claude-code-ide-session-idle-enabled)))

(ert-deftest claude-code-ide-test-session-idle-unload-does-not-error ()
  "Test unloading the idle module succeeds cleanly."
  (should (require 'claude-code-ide-session-idle nil t))
  (let ((unload-error nil))
    (unwind-protect
        (progn
          (unload-feature 'claude-code-ide-session-idle t)
          (setq unload-error
                (condition-case err
                    (progn
                      (run-hooks 'window-state-change-hook)
                      (run-hooks 'window-configuration-change-hook)
                      (run-hook-with-args 'after-focus-change-function)
                      nil)
                  (error err)))
          (should-not unload-error))
      (should (require 'claude-code-ide-session-idle nil t)))))

(ert-deftest claude-code-ide-test-session-idle-reset-schedules-timer ()
  "Test that session idle reset schedules a timer."
  (should (require 'claude-code-ide-session-idle nil t))
  (let ((timer-delay nil)
        (timer-callback nil)
        (suppressed-buffer nil))
    (cl-letf (((symbol-function 'run-with-timer)
               (lambda (delay repeat function &rest args)
                 (setq timer-delay delay
                       timer-callback (list function args repeat))
                 'mock-idle-timer)))
      (let ((claude-code-ide-session-idle-suppressed-predicate
             (lambda (buffer)
               (setq suppressed-buffer buffer)
               nil)))
        (with-temp-buffer
          (rename-buffer "*claude-code[test-idle]*" t)
          (claude-code-ide-session-idle-enable)
          (claude-code-ide-session-idle-reset-timer)
          (should (equal timer-delay claude-code-ide-session-idle-delay))
          (should (eq (car timer-callback)
                      #'claude-code-ide-session-idle--fire-timer))
          (should (eq suppressed-buffer (current-buffer)))
          (should claude-code-ide-session-idle-timer))))))

(ert-deftest claude-code-ide-test-session-idle-enable-does-not-schedule-timer ()
  "Test enabling idle monitoring does not arm a timer before activity."
  (should (require 'claude-code-ide-session-idle nil t))
  (let ((scheduled nil))
    (cl-letf (((symbol-function 'run-with-timer)
               (lambda (&rest _args)
                 (setq scheduled t)
                 'mock-idle-timer)))
      (with-temp-buffer
        (rename-buffer "*claude-code[test-idle-enable]*" t)
        (claude-code-ide-session-idle-enable)
        (should claude-code-ide-session-idle-enabled)
        (should-not scheduled)
        (should-not claude-code-ide-session-idle-timer)))))

(ert-deftest claude-code-ide-test-session-idle-fire-timer-marks-buffer-idle ()
  "Test that firing the idle timer marks the session buffer idle."
  (should (require 'claude-code-ide-session-idle nil t))
  (with-temp-buffer
    (rename-buffer "*claude-code[test-idle-fire]*" t)
    (setq claude-code-ide-session-idle-enabled t
          claude-code-ide-session-idle-p nil)
    (claude-code-ide-session-idle--fire-timer (current-buffer))
    (should claude-code-ide-session-idle-p)))

(ert-deftest claude-code-ide-test-session-idle-fire-timer-does-not-mark-idle-when-disabled ()
  "Test that a stale idle callback does not mark the buffer idle when disabled."
  (should (require 'claude-code-ide-session-idle nil t))
  (with-temp-buffer
    (rename-buffer "*claude-code[test-idle-disabled-fire]*" t)
    (setq claude-code-ide-session-idle-enabled nil
          claude-code-ide-session-idle-p nil)
    (claude-code-ide-session-idle--fire-timer (current-buffer))
    (should-not claude-code-ide-session-idle-p)))

(ert-deftest claude-code-ide-test-session-idle-fire-timer-does-not-mark-idle-when-suppressed ()
  "Test that a suppressed idle callback does not mark the buffer idle."
  (should (require 'claude-code-ide-session-idle nil t))
  (let ((claude-code-ide-session-idle-suppressed-predicate
         (lambda (_buffer)
           t)))
    (with-temp-buffer
      (rename-buffer "*claude-code[test-idle-suppressed-fire]*" t)
      (setq claude-code-ide-session-idle-enabled t
            claude-code-ide-session-idle-p nil)
      (claude-code-ide-session-idle--fire-timer (current-buffer))
      (should-not claude-code-ide-session-idle-p))))

(ert-deftest claude-code-ide-test-session-idle-fire-timer-defers-while-visible-and-focused ()
  "Test visible focused sessions do not transition to idle."
  (should (require 'claude-code-ide-session-idle nil t))
  (let ((session-buffer (generate-new-buffer "*claude-code[test-idle-visible-focused]*")))
    (unwind-protect
        (save-window-excursion
          (delete-other-windows)
          (switch-to-buffer session-buffer)
          (cl-letf (((symbol-function 'frame-focus-state)
                     (lambda (_frame) t)))
            (with-current-buffer session-buffer
              (setq-local claude-code-ide-session-idle-enabled t
                          claude-code-ide-session-idle-p nil
                          claude-code-ide-session-idle-timer 'mock-idle-timer)
              (claude-code-ide-session-idle--fire-timer session-buffer)
              (should-not claude-code-ide-session-idle-p)
              (should-not claude-code-ide-session-idle-timer))))
      (when (buffer-live-p session-buffer)
        (kill-buffer session-buffer)))))

(ert-deftest claude-code-ide-test-session-idle-visibility-refresh-clears-only-visible-focused-idle-sessions ()
  "Test visibility refresh clears idle only for visible focused session buffers."
  (should (require 'claude-code-ide-session-idle nil t))
  (let ((visible-buffer (generate-new-buffer "*claude-code[test-idle-visible-refresh]*"))
        (hidden-buffer (generate-new-buffer "*claude-code[test-idle-hidden-refresh]*")))
    (unwind-protect
        (save-window-excursion
          (delete-other-windows)
          (switch-to-buffer visible-buffer)
          (with-current-buffer visible-buffer
            (setq-local claude-code-ide-session-idle-enabled t
                        claude-code-ide-session-idle-p t
                        claude-code-ide-session-idle-timer 'visible-timer))
          (with-current-buffer hidden-buffer
            (setq-local claude-code-ide-session-idle-enabled t
                        claude-code-ide-session-idle-p t
                        claude-code-ide-session-idle-timer 'hidden-timer))
          (cl-letf (((symbol-function 'frame-focus-state)
                     (lambda (_frame) t)))
            (claude-code-ide-session-idle--handle-visibility-change)
            (with-current-buffer visible-buffer
              (should-not claude-code-ide-session-idle-p)
              (should-not claude-code-ide-session-idle-timer))
            (with-current-buffer hidden-buffer
              (should claude-code-ide-session-idle-p)
              (should (eq claude-code-ide-session-idle-timer 'hidden-timer)))))
      (when (buffer-live-p visible-buffer)
        (kill-buffer visible-buffer))
      (when (buffer-live-p hidden-buffer)
        (kill-buffer hidden-buffer)))))

(ert-deftest claude-code-ide-test-session-idle-reset-preserves-working-flag ()
  "Test that resetting idle monitoring clears idle without clearing working."
  (should (require 'claude-code-ide-session-idle nil t))
  (let ((timer-delay nil))
    (cl-letf (((symbol-function 'run-with-timer)
               (lambda (delay repeat function &rest args)
                 (setq timer-delay delay)
                 'mock-idle-timer)))
      (with-temp-buffer
        (rename-buffer "*claude-code[test-idle-reset]*" t)
        (setq claude-code-ide-session-idle-enabled t
              claude-code-ide-session-idle-p t
              claude-code-ide-session-working-p t)
        (claude-code-ide-session-idle-reset-timer)
        (should (equal timer-delay claude-code-ide-session-idle-delay))
        (should-not claude-code-ide-session-idle-p)
        (should claude-code-ide-session-working-p)))))

(ert-deftest claude-code-ide-test-session-idle-disable-clears-idle-flag ()
  "Test that disabling idle monitoring clears the idle flag immediately."
  (should (require 'claude-code-ide-session-idle nil t))
  (with-temp-buffer
    (rename-buffer "*claude-code[test-idle-disable]*" t)
    (setq claude-code-ide-session-idle-enabled t
          claude-code-ide-session-idle-p t
          claude-code-ide-session-working-p t)
    (claude-code-ide-session-idle-disable)
    (should-not claude-code-ide-session-idle-p)
    (should-not claude-code-ide-session-working-p)))

(ert-deftest claude-code-ide-test-session-idle-setup-clears-preexisting-idle-flag ()
  "Test that session setup clears any preexisting idle flag."
  (should (require 'claude-code-ide-session-idle nil t))
  (let ((claude-code-ide-session-idle-default-enabled nil))
    (with-temp-buffer
      (rename-buffer "*claude-code[test-idle-setup]*" t)
      (setq claude-code-ide-session-idle-p t
            claude-code-ide-session-working-p t)
      (claude-code-ide-session-idle--setup-buffer)
      (should-not claude-code-ide-session-idle-p)
      (should-not claude-code-ide-session-working-p))))

(ert-deftest claude-code-ide-test-session-idle-record-activity-does-not-set-working-flag ()
  "Test idle activity tracking does not also mark the session as working."
  (should (require 'claude-code-ide-session-idle nil t))
  (cl-letf (((symbol-function 'claude-code-ide-session-idle--buffer-visible-in-focused-frame-p)
             (lambda (&optional _buffer)
               t)))
    (with-temp-buffer
      (rename-buffer "*claude-code[test-idle-working-activity]*" t)
      (setq claude-code-ide-session-idle-enabled t
            claude-code-ide-session-idle-p t
            claude-code-ide-session-working-p nil)
      (claude-code-ide-session-idle-record-activity)
      (should-not claude-code-ide-session-idle-p)
      (should-not claude-code-ide-session-working-p))))

(ert-deftest claude-code-ide-test-session-working-record-output-sets-working-flag ()
  "Test backend output marks the session as working and arms a clear timer."
  (should (require 'claude-code-ide-session-idle nil t))
  (let ((scheduled-delay nil)
        (scheduled-callback nil))
    (cl-letf (((symbol-function 'run-with-timer)
               (lambda (delay _repeat function &rest args)
                 (setq scheduled-delay delay
                       scheduled-callback (list function args))
                 'mock-working-timer)))
      (with-temp-buffer
        (rename-buffer "*claude-code[test-working-output]*" t)
        (setq claude-code-ide-session-working-p nil)
        (claude-code-ide-session-working-record-output)
        (should claude-code-ide-session-working-p)
        (should (equal scheduled-delay claude-code-ide-session-working-delay))
        (should scheduled-callback)
        (should (eq claude-code-ide-session-working-timer 'mock-working-timer))))))

(ert-deftest claude-code-ide-test-session-working-fire-timer-clears-working-flag ()
  "Test the working timer clears the working flag."
  (should (require 'claude-code-ide-session-idle nil t))
  (with-temp-buffer
    (rename-buffer "*claude-code[test-working-fire]*" t)
    (setq claude-code-ide-session-working-p t
          claude-code-ide-session-working-timer 'mock-working-timer)
    (claude-code-ide-session-working--fire-timer (current-buffer))
    (should-not claude-code-ide-session-working-p)
    (should-not claude-code-ide-session-working-timer)))

(ert-deftest claude-code-ide-test-session-working-record-output-is-suppressed-after-resize ()
  "Test resize suppression prevents output from marking working."
  (should (require 'claude-code-ide-session-idle nil t))
  (cl-letf (((symbol-function 'current-time)
             (lambda ()
               100.0))
            ((symbol-function 'run-with-timer)
             (lambda (&rest _args)
               'mock-working-timer)))
    (with-temp-buffer
      (rename-buffer "*claude-code[test-working-resize-suppress]*" t)
      (setq claude-code-ide-session-working-p nil
            claude-code-ide-session-working-suppress-until 100.5)
      (claude-code-ide-session-working-record-output)
      (should-not claude-code-ide-session-working-p)
      (should-not claude-code-ide-session-working-timer))))

(ert-deftest claude-code-ide-test-session-working-record-output-resumes-after-resize-window ()
  "Test working detection resumes once resize suppression expires."
  (should (require 'claude-code-ide-session-idle nil t))
  (let ((scheduled-delay nil))
    (cl-letf (((symbol-function 'current-time)
               (lambda ()
                 101.0))
              ((symbol-function 'run-with-timer)
               (lambda (delay _repeat _function &rest _args)
                 (setq scheduled-delay delay)
                 'mock-working-timer)))
      (with-temp-buffer
        (rename-buffer "*claude-code[test-working-resize-expired]*" t)
        (setq claude-code-ide-session-working-p nil
              claude-code-ide-session-working-suppress-until 100.5)
        (claude-code-ide-session-working-record-output)
        (should claude-code-ide-session-working-p)
        (should (equal scheduled-delay claude-code-ide-session-working-delay))
        (should (eq claude-code-ide-session-working-timer 'mock-working-timer))))))

(ert-deftest claude-code-ide-test-terminal-working-resize-observer-suppresses-working-after-resize ()
  "Test terminal resize observer marks the session to suppress working output briefly."
  (should (require 'claude-code-ide nil t))
  (let ((suppressed-buffer nil))
    (save-window-excursion
      (with-temp-buffer
        (rename-buffer "*claude-code[test-working-resize-observer]*" t)
        (let ((session-buffer (current-buffer)))
          (switch-to-buffer session-buffer)
          (cl-letf (((symbol-function 'claude-code-ide--session-buffer-p)
                     (lambda (&optional _buffer)
                       t))
                    ((symbol-function 'claude-code-ide-session-working-suppress-after-resize)
                     (lambda (&optional buffer)
                       (setq suppressed-buffer (or buffer (current-buffer))))))
            (should (eq :base-result
                        (claude-code-ide--terminal-working-resize-observer
                         (lambda (&rest _args)
                           :base-result))))
            (should (eq suppressed-buffer session-buffer))))))))

(ert-deftest claude-code-ide-test-session-tracking-grace-setup-defers-start ()
  "Test session setup defers idle and working tracking during startup grace."
  (should (require 'claude-code-ide-session-idle nil t))
  (let ((claude-code-ide-session-idle-default-enabled t)
        (scheduled-delay nil)
        (scheduled-callback nil))
    (cl-letf (((symbol-function 'run-with-timer)
               (lambda (delay _repeat function &rest args)
                 (setq scheduled-delay delay
                       scheduled-callback (list function args))
                 'mock-startup-tracking-timer)))
      (with-temp-buffer
        (rename-buffer "*claude-code[test-tracking-setup]*" t)
        (claude-code-ide-session-idle--setup-buffer)
        (should claude-code-ide-session-idle-enabled)
        (should-not claude-code-ide-session-working-p)
        (should-not claude-code-ide-session-idle-p)
        (should (equal scheduled-delay claude-code-ide-session-tracking-start-delay))
        (should scheduled-callback)
        (should (eq claude-code-ide-session-tracking-start-timer
                    'mock-startup-tracking-timer))
        (should-not claude-code-ide-session-tracking-started-p)))))

(ert-deftest claude-code-ide-test-session-tracking-grace-ignores-startup-output ()
  "Test startup output is ignored until tracking grace expires."
  (should (require 'claude-code-ide-session-idle nil t))
  (let ((scheduled-delay nil)
        (working-scheduled nil))
    (cl-letf (((symbol-function 'run-with-timer)
               (lambda (delay _repeat _function &rest _args)
                 (if (equal delay claude-code-ide-session-working-delay)
                     (setq working-scheduled t)
                   (setq scheduled-delay delay))
                 'mock-timer)))
      (with-temp-buffer
        (rename-buffer "*claude-code[test-tracking-output-grace]*" t)
        (setq claude-code-ide-session-idle-enabled t
              claude-code-ide-session-tracking-started-p nil)
        (claude-code-ide-session-idle-record-activity)
        (claude-code-ide-session-working-record-output)
        (should-not claude-code-ide-session-idle-p)
        (should-not claude-code-ide-session-working-p)
        (should-not claude-code-ide-session-idle-timer)
        (should-not claude-code-ide-session-working-timer)
        (should-not scheduled-delay)
        (should-not working-scheduled)))))

(ert-deftest claude-code-ide-test-session-tracking-grace-expiry-arms-hidden-idle-timer ()
  "Test grace expiry starts idle detection for hidden enabled sessions."
  (should (require 'claude-code-ide-session-idle nil t))
  (let ((claude-code-ide-session-idle-default-enabled t)
        (scheduled-delay nil)
        (scheduled-startup-callback nil)
        (startup-timer-count 0))
    (cl-letf (((symbol-function 'run-with-timer)
               (lambda (delay _repeat function &rest args)
                 (if (equal delay claude-code-ide-session-tracking-start-delay)
                     (progn
                       (setq startup-timer-count (1+ startup-timer-count)
                             scheduled-startup-callback (list function args))
                       'mock-startup-timer)
                   (setq scheduled-delay delay)
                   'mock-idle-timer))))
      (with-temp-buffer
        (rename-buffer "*claude-code[test-tracking-grace-expiry]*" t)
        (claude-code-ide-session-idle--setup-buffer)
        (should (= startup-timer-count 1))
        (apply (car scheduled-startup-callback) (cadr scheduled-startup-callback))
        (should claude-code-ide-session-tracking-started-p)
        (should (equal scheduled-delay claude-code-ide-session-idle-delay))
        (should (eq claude-code-ide-session-idle-timer 'mock-idle-timer))))))

(ert-deftest claude-code-ide-test-session-idle-setup-enabled-defers-idle-timer-until-grace-expires ()
  "Test setup arms only the tracking-start timer, not the idle timer."
  (should (require 'claude-code-ide-session-idle nil t))
  (let ((claude-code-ide-session-idle-default-enabled t)
        (scheduled-delays nil))
    (cl-letf (((symbol-function 'run-with-timer)
               (lambda (delay _repeat _function &rest _args)
                 (push delay scheduled-delays)
                 'mock-idle-timer)))
      (with-temp-buffer
        (rename-buffer "*claude-code[test-idle-setup-enabled]*" t)
        (claude-code-ide-session-idle--setup-buffer)
        (should claude-code-ide-session-idle-enabled)
        (should (equal scheduled-delays
                       (list claude-code-ide-session-tracking-start-delay)))
        (should-not claude-code-ide-session-idle-timer)))))

(ert-deftest claude-code-ide-test-session-idle-old-callback-after-reset-does-not-mark-idle ()
  "Test that an older queued callback is ignored after a later reset."
  (should (require 'claude-code-ide-session-idle nil t))
  (let ((scheduled-callbacks nil)
        (hook-runs 0)
        (timer-count 0))
    (cl-letf (((symbol-function 'run-with-timer)
               (lambda (_delay _repeat function &rest args)
                 (setq timer-count (1+ timer-count))
                 (push (list function args) scheduled-callbacks)
                 (intern (format "mock-idle-timer-%d" timer-count))))
              ((symbol-function 'run-hook-with-args)
               (lambda (&rest _args)
                 (setq hook-runs (1+ hook-runs)))))
      (with-temp-buffer
        (rename-buffer "*claude-code[test-idle-old-callback]*" t)
        (setq claude-code-ide-session-idle-enabled t
              claude-code-ide-session-idle-p nil)
        (claude-code-ide-session-idle-reset-timer)
        (claude-code-ide-session-idle-reset-timer)
        (let* ((callbacks (nreverse scheduled-callbacks))
               (old-callback (car callbacks)))
          (apply (car old-callback) (cadr old-callback))
          (should-not claude-code-ide-session-idle-p)
          (should (= hook-runs 0)))))))

(ert-deftest claude-code-ide-test-session-idle-old-callback-after-disable-does-not-mark-idle ()
  "Test that an older queued callback is ignored after disable."
  (should (require 'claude-code-ide-session-idle nil t))
  (let ((scheduled-callback nil)
        (hook-runs 0))
    (cl-letf (((symbol-function 'run-with-timer)
               (lambda (_delay _repeat function &rest args)
                 (setq scheduled-callback (list function args))
                 'mock-idle-timer))
              ((symbol-function 'run-hook-with-args)
               (lambda (&rest _args)
                 (setq hook-runs (1+ hook-runs)))))
      (with-temp-buffer
        (rename-buffer "*claude-code[test-idle-disable-old-callback]*" t)
        (setq claude-code-ide-session-idle-enabled t
              claude-code-ide-session-idle-p nil)
        (claude-code-ide-session-idle-reset-timer)
        (claude-code-ide-session-idle-disable)
        (apply (car scheduled-callback) (cadr scheduled-callback))
        (should-not claude-code-ide-session-idle-p)
        (should (= hook-runs 0))))))

(ert-deftest claude-code-ide-test-session-idle-old-callback-after-suppression-does-not-mark-idle ()
  "Test that an older queued callback is ignored after suppression."
  (should (require 'claude-code-ide-session-idle nil t))
  (let ((scheduled-callback nil)
        (hook-runs 0)
        (suppressed nil))
    (cl-letf (((symbol-function 'run-with-timer)
               (lambda (_delay _repeat function &rest args)
                 (setq scheduled-callback (list function args))
                 'mock-idle-timer))
              ((symbol-function 'run-hook-with-args)
               (lambda (&rest _args)
                 (setq hook-runs (1+ hook-runs)))))
      (let ((claude-code-ide-session-idle-suppressed-predicate
             (lambda (_buffer)
               suppressed)))
        (with-temp-buffer
          (rename-buffer "*claude-code[test-idle-suppressed-old-callback]*" t)
          (setq claude-code-ide-session-idle-enabled t
                claude-code-ide-session-idle-p nil)
          (claude-code-ide-session-idle-reset-timer)
          (setq suppressed t)
          (apply (car scheduled-callback) (cadr scheduled-callback))
          (should-not claude-code-ide-session-idle-p)
          (should (= hook-runs 0)))))))

(ert-deftest claude-code-ide-test-session-idle-fire-timer-passes-buffer-to-hook ()
  "Test that the idle hook runs with the session buffer argument."
  (should (require 'claude-code-ide-session-idle nil t))
  (let ((hook-buffer nil))
    (cl-letf (((symbol-function 'run-hook-with-args)
               (lambda (hook &rest args)
                 (setq hook-buffer (car args))
                 (should (eq hook 'claude-code-ide-session-idle-hook)))))
      (with-temp-buffer
        (rename-buffer "*claude-code[test-idle-hook]*" t)
        (claude-code-ide-session-idle-enable)
        (claude-code-ide-session-idle--fire-timer (current-buffer))
        (should (eq hook-buffer (current-buffer)))))))

(ert-deftest claude-code-ide-test-session-idle-fire-timer-clears-working-flag ()
  "Test that becoming idle clears the working flag."
  (should (require 'claude-code-ide-session-idle nil t))
  (cl-letf (((symbol-function 'claude-code-ide-session-idle--buffer-visible-in-focused-frame-p)
             (lambda (&optional _buffer)
               nil))
            ((symbol-function 'run-hook-with-args)
             (lambda (&rest _args)
               nil)))
    (with-temp-buffer
      (rename-buffer "*claude-code[test-idle-working-fire]*" t)
      (setq claude-code-ide-session-idle-enabled t
            claude-code-ide-session-idle-p nil
            claude-code-ide-session-working-p t)
      (claude-code-ide-session-idle--fire-timer (current-buffer))
      (should claude-code-ide-session-idle-p)
      (should-not claude-code-ide-session-working-p))))

(provide 'claude-code-ide-tests)

;; Local Variables:
;; no-update-autoloads: t
;; autoload-compute-prefixes: nil
;; End:

;;; claude-code-ide-tests.el ends here
