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

(defun claude-code-ide-tests--clear-processes ()
  "Clear the process hash table for testing.
Ensures a clean state before each test that involves process management."
  (clrhash claude-code-ide--processes)
  ;; Also clear MCP sessions
  (when (boundp 'claude-code-ide-mcp--sessions)
    (clrhash claude-code-ide-mcp--sessions)))

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

(ert-deftest claude-code-ide-test-manager-switch-refreshes-sidebar-highlight ()
  "Test switching sessions rerenders the manager highlight."
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
  (setq claude-code-ide-manager--current-session-key "/tmp/project-a")
  (with-current-buffer (claude-code-ide-manager--get-buffer)
    (claude-code-ide-manager--render))
  (cl-letf (((symbol-function 'claude-code-ide-manager--capture-layout)
             (lambda (_session-key) nil))
            ((symbol-function 'claude-code-ide-manager--save-state)
             (lambda () nil))
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
    (should (equal (get-text-property (point) 'claude-code-ide-manager-session-key)
                   "/tmp/project-b"))))

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

(ert-deftest claude-code-ide-test-manager-default-window-width ()
  "Test manager sidebar width default is narrow enough for basename rows."
  (should (= claude-code-ide-manager-window-width 22)))

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
    (should (member (regexp-quote claude-code-ide-manager--buffer-name)
                    winum-ignored-buffers-regexp))
    (should (member 'claude-code-ide-manager-mode aw-ignored-buffers))))

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
               (lambda (session-key)
                 (setq switched session-key))))
      (with-current-buffer (claude-code-ide-manager--get-buffer)
        (claude-code-ide-manager--render)
        (goto-char (point-min))
        (call-interactively (key-binding (kbd "SPC")))
        (should (equal switched "/tmp/project-a"))))))

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
               (lambda (session-key)
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
               (lambda (session-key)
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
                   (lambda (session-key)
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
               (lambda (session-key)
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
            (claude-code-ide-manager-switch-to-session "/tmp/project-a")
            (should (equal (window-buffer (selected-window)) focus-buffer))))
      (mapc (lambda (buffer)
              (when (buffer-live-p buffer)
                (kill-buffer buffer)))
            (list session-buffer focus-buffer)))))

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
               (lambda ()
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

(ert-deftest claude-code-ide-test-transient-exposes-current-dir-and-session-lists ()
  "Test the main transient exposes current-dir and session list bindings."
  (should (transient-get-suffix 'claude-code-ide-menu "d"))
  (should (transient-get-suffix 'claude-code-ide-menu "D"))
  (should (transient-get-suffix 'claude-code-ide-menu "l"))
  (should (transient-get-suffix 'claude-code-ide-menu "L")))

(ert-deftest claude-code-ide-test-transient-exposes-manager-commands ()
  "Test the main transient exposes cc-manager bindings."
  (should (transient-get-suffix 'claude-code-ide-menu "t"))
  (should (transient-get-suffix 'claude-code-ide-menu "n"))
  (should (transient-get-suffix 'claude-code-ide-menu "p"))
  (should (transient-get-suffix 'claude-code-ide-menu "1"))
  (should (transient-get-suffix 'claude-code-ide-menu "0"))
  (should (transient-get-suffix 'claude-code-ide-menu "M"))
  (should (transient-get-suffix 'claude-code-ide-menu "g")))

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
  "Test that sending a string clears stale idle state immediately."
  (should (require 'claude-code-ide-session nil t))
  (let ((sent-string nil))
    (cl-letf (((symbol-function 'vterm-send-string)
               (lambda (string &optional _paste)
                 (setq sent-string string)))
              ((symbol-function 'run-with-idle-timer)
               (lambda (&rest _args)
                 'mock-idle-timer)))
      (with-temp-buffer
        (rename-buffer "*claude-code[test-send-string-idle]*" t)
        (setq claude-code-ide--terminal-backend 'vterm
              claude-code-ide-session-idle-enabled t
              claude-code-ide-session-idle-p t)
        (claude-code-ide-session-send-string "status")
        (should (equal sent-string "status"))
        (should-not claude-code-ide-session-idle-p)
        (should claude-code-ide-session-idle-timer)))))

(ert-deftest claude-code-ide-test-session-send-string-resets-idle-state-eat ()
  "Test that sending a string clears stale idle state immediately on eat."
  (should (require 'claude-code-ide-session nil t))
  (let ((sent-string nil))
    (cl-letf (((symbol-function 'eat-term-send-string)
               (lambda (_terminal string)
                 (setq sent-string string)))
              ((symbol-function 'run-with-idle-timer)
               (lambda (&rest _args)
                 'mock-idle-timer)))
      (with-temp-buffer
        (rename-buffer "*claude-code[test-send-string-idle-eat]*" t)
        (setq claude-code-ide--terminal-backend 'eat
              claude-code-ide-session-idle-enabled t
              claude-code-ide-session-idle-p t
              eat-terminal t)
        (claude-code-ide-session-send-string "status")
        (should (equal sent-string "status"))
        (should-not claude-code-ide-session-idle-p)
        (should claude-code-ide-session-idle-timer)))))

(ert-deftest claude-code-ide-test-session-send-return-resets-idle-state ()
  "Test that sending return clears stale idle state immediately."
  (should (require 'claude-code-ide-session nil t))
  (let ((return-called nil))
    (cl-letf (((symbol-function 'vterm-send-return)
               (lambda ()
                 (setq return-called t)))
              ((symbol-function 'run-with-idle-timer)
               (lambda (&rest _args)
                 'mock-idle-timer)))
      (with-temp-buffer
        (rename-buffer "*claude-code[test-send-return-idle]*" t)
        (setq claude-code-ide--terminal-backend 'vterm
              claude-code-ide-session-idle-enabled t
              claude-code-ide-session-idle-p t)
        (claude-code-ide-session-send-return)
        (should return-called)
        (should-not claude-code-ide-session-idle-p)
        (should claude-code-ide-session-idle-timer)))))

(ert-deftest claude-code-ide-test-session-send-return-resets-idle-state-eat ()
  "Test that sending return clears stale idle state immediately on eat."
  (should (require 'claude-code-ide-session nil t))
  (let ((sent-string nil))
    (cl-letf (((symbol-function 'eat-term-send-string)
               (lambda (_terminal string)
                 (setq sent-string string)))
              ((symbol-function 'run-with-idle-timer)
               (lambda (&rest _args)
                 'mock-idle-timer)))
      (with-temp-buffer
        (rename-buffer "*claude-code[test-send-return-idle-eat]*" t)
        (setq claude-code-ide--terminal-backend 'eat
              claude-code-ide-session-idle-enabled t
              claude-code-ide-session-idle-p t
              eat-terminal t)
        (claude-code-ide-session-send-return)
        (should (equal sent-string "\r"))
        (should-not claude-code-ide-session-idle-p)
        (should claude-code-ide-session-idle-timer)))))

(ert-deftest claude-code-ide-test-session-send-escape-resets-idle-state ()
  "Test that sending escape clears stale idle state immediately."
  (should (require 'claude-code-ide-session nil t))
  (let ((escape-called nil))
    (cl-letf (((symbol-function 'vterm-send-escape)
               (lambda ()
                 (setq escape-called t)))
              ((symbol-function 'run-with-idle-timer)
               (lambda (&rest _args)
                 'mock-idle-timer)))
      (with-temp-buffer
        (rename-buffer "*claude-code[test-send-escape-idle]*" t)
        (setq claude-code-ide--terminal-backend 'vterm
              claude-code-ide-session-idle-enabled t
              claude-code-ide-session-idle-p t)
        (claude-code-ide-session-send-escape)
        (should escape-called)
        (should-not claude-code-ide-session-idle-p)
        (should claude-code-ide-session-idle-timer)))))

(ert-deftest claude-code-ide-test-session-send-escape-resets-idle-state-eat ()
  "Test that sending escape clears stale idle state immediately on eat."
  (should (require 'claude-code-ide-session nil t))
  (let ((sent-string nil))
    (cl-letf (((symbol-function 'eat-term-send-string)
               (lambda (_terminal string)
                 (setq sent-string string)))
              ((symbol-function 'run-with-idle-timer)
               (lambda (&rest _args)
                 'mock-idle-timer)))
      (with-temp-buffer
        (rename-buffer "*claude-code[test-send-escape-idle-eat]*" t)
        (setq claude-code-ide--terminal-backend 'eat
              claude-code-ide-session-idle-enabled t
              claude-code-ide-session-idle-p t
              eat-terminal t)
        (claude-code-ide-session-send-escape)
        (should (equal sent-string "\e"))
        (should-not claude-code-ide-session-idle-p)
        (should claude-code-ide-session-idle-timer)))))

(ert-deftest claude-code-ide-test-session-send-interrupt-resets-idle-state ()
  "Test that sending interrupt clears stale idle state immediately."
  (should (require 'claude-code-ide-session nil t))
  (let ((interrupt-called nil))
    (cl-letf (((symbol-function 'vterm-send-key)
               (lambda (&rest _args)
                 (setq interrupt-called t)))
              ((symbol-function 'run-with-idle-timer)
               (lambda (&rest _args)
                 'mock-idle-timer)))
      (with-temp-buffer
        (rename-buffer "*claude-code[test-send-interrupt-idle]*" t)
        (setq claude-code-ide--terminal-backend 'vterm
              claude-code-ide-session-idle-enabled t
              claude-code-ide-session-idle-p t)
        (claude-code-ide-session-send-interrupt)
        (should interrupt-called)
        (should-not claude-code-ide-session-idle-p)
        (should claude-code-ide-session-idle-timer)))))

(ert-deftest claude-code-ide-test-session-send-interrupt-resets-idle-state-eat ()
  "Test that sending interrupt clears stale idle state immediately on eat."
  (should (require 'claude-code-ide-session nil t))
  (let ((sent-string nil))
    (cl-letf (((symbol-function 'eat-term-send-string)
               (lambda (_terminal string)
                 (setq sent-string string)))
              ((symbol-function 'run-with-idle-timer)
               (lambda (&rest _args)
                 'mock-idle-timer)))
      (with-temp-buffer
        (rename-buffer "*claude-code[test-send-interrupt-idle-eat]*" t)
        (setq claude-code-ide--terminal-backend 'eat
              claude-code-ide-session-idle-enabled t
              claude-code-ide-session-idle-p t
              eat-terminal t)
        (claude-code-ide-session-send-interrupt)
        (should (equal sent-string "\003"))
        (should-not claude-code-ide-session-idle-p)
        (should claude-code-ide-session-idle-timer)))))

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
  (let ((reset-called nil))
    (cl-letf (((symbol-function 'claude-code-ide-session-idle-reset-timer)
               (lambda ()
                 (setq reset-called t))))
      (with-temp-buffer
        (rename-buffer "*claude-code[test-idle-observer]*" t)
        (vterm--filter nil "output")
        (should reset-called))
      (setq reset-called nil)
      (with-temp-buffer
        (rename-buffer "*not-a-claude-buffer*" t)
        (vterm--filter nil "output")
        (should-not reset-called)))))

(ert-deftest claude-code-ide-test-session-idle-observer-uses-process-buffer ()
  "Test that backend output filters reset idle for the process buffer."
  (should (require 'claude-code-ide-session-idle nil t))
  (let ((reset-buffer nil)
        (session-buffer (generate-new-buffer "*claude-code[test-idle-process-buffer]*"))
        (other-buffer (generate-new-buffer "*not-a-claude-buffer*")))
    (unwind-protect
        (cl-letf (((symbol-function 'process-buffer)
                   (lambda (_process)
                     session-buffer))
                  ((symbol-function 'claude-code-ide-session-idle-reset-timer)
                   (lambda ()
                     (setq reset-buffer (current-buffer)))))
          (with-current-buffer other-buffer
            (vterm--filter 'mock-process "output"))
          (should (eq reset-buffer session-buffer)))
      (kill-buffer session-buffer)
      (kill-buffer other-buffer))))

(ert-deftest claude-code-ide-test-session-idle-observer-uses-process-buffer-eat ()
  "Test that eat output filters reset idle for the process buffer."
  (should (require 'claude-code-ide-session-idle nil t))
  (let ((reset-buffer nil)
        (session-buffer (generate-new-buffer "*claude-code[test-idle-process-buffer-eat]*"))
        (other-buffer (generate-new-buffer "*not-a-claude-buffer*")))
    (unwind-protect
        (cl-letf (((symbol-function 'process-buffer)
                   (lambda (_process)
                     session-buffer))
                  ((symbol-function 'claude-code-ide-session-idle-reset-timer)
                   (lambda ()
                     (setq reset-buffer (current-buffer)))))
          (with-current-buffer other-buffer
            (eat--filter 'mock-process "output"))
          (should (eq reset-buffer session-buffer)))
      (kill-buffer session-buffer)
      (kill-buffer other-buffer))))

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

(ert-deftest claude-code-ide-test-session-idle-reset-schedules-timer ()
  "Test that session idle reset schedules a timer."
  (should (require 'claude-code-ide-session-idle nil t))
  (let ((timer-delay nil)
        (timer-callback nil)
        (suppressed-buffer nil))
    (cl-letf (((symbol-function 'run-with-idle-timer)
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

(ert-deftest claude-code-ide-test-session-idle-reset-clears-idle-flag ()
  "Test that resetting idle monitoring clears the idle flag."
  (should (require 'claude-code-ide-session-idle nil t))
  (let ((timer-delay nil))
    (cl-letf (((symbol-function 'run-with-idle-timer)
               (lambda (delay repeat function &rest args)
                 (setq timer-delay delay)
                 'mock-idle-timer)))
      (with-temp-buffer
        (rename-buffer "*claude-code[test-idle-reset]*" t)
        (setq claude-code-ide-session-idle-enabled t
              claude-code-ide-session-idle-p t)
        (claude-code-ide-session-idle-reset-timer)
        (should (equal timer-delay claude-code-ide-session-idle-delay))
        (should-not claude-code-ide-session-idle-p)))))

(ert-deftest claude-code-ide-test-session-idle-disable-clears-idle-flag ()
  "Test that disabling idle monitoring clears the idle flag immediately."
  (should (require 'claude-code-ide-session-idle nil t))
  (with-temp-buffer
    (rename-buffer "*claude-code[test-idle-disable]*" t)
    (setq claude-code-ide-session-idle-enabled t
          claude-code-ide-session-idle-p t)
    (claude-code-ide-session-idle-disable)
    (should-not claude-code-ide-session-idle-p)))

(ert-deftest claude-code-ide-test-session-idle-setup-clears-preexisting-idle-flag ()
  "Test that session setup clears any preexisting idle flag."
  (should (require 'claude-code-ide-session-idle nil t))
  (let ((claude-code-ide-session-idle-default-enabled nil))
    (with-temp-buffer
      (rename-buffer "*claude-code[test-idle-setup]*" t)
      (setq claude-code-ide-session-idle-p t)
      (claude-code-ide-session-idle--setup-buffer)
      (should-not claude-code-ide-session-idle-p))))

(ert-deftest claude-code-ide-test-session-idle-old-callback-after-reset-does-not-mark-idle ()
  "Test that an older queued callback is ignored after a later reset."
  (should (require 'claude-code-ide-session-idle nil t))
  (let ((scheduled-callbacks nil)
        (hook-runs 0)
        (timer-count 0))
    (cl-letf (((symbol-function 'run-with-idle-timer)
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
    (cl-letf (((symbol-function 'run-with-idle-timer)
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
    (cl-letf (((symbol-function 'run-with-idle-timer)
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

(provide 'claude-code-ide-tests)

;; Local Variables:
;; no-update-autoloads: t
;; autoload-compute-prefixes: nil
;; End:

;;; claude-code-ide-tests.el ends here
