;;; init.el --- Entry point -*- lexical-binding: t; -*-

;;; Load path

(add-to-list 'load-path (expand-file-name "lisp" user-emacs-directory))
(add-to-list 'load-path
             (expand-file-name "themes/terrazzo-emacs" user-emacs-directory))

(let ((default-directory (expand-file-name "packages" user-emacs-directory)))
  (normal-top-level-add-subdirs-to-load-path))

;;; Compilation

(setq load-prefer-newer t)

(require 'compile-angel)
(push "/init.el" compile-angel-excluded-path-suffixes)
(push "/early-init.el" compile-angel-excluded-path-suffixes)
(setq compile-angel-enable-byte-compile nil
      compile-angel-enable-native-compile t)
(compile-angel-on-load-mode 1)

;;; Performance

(require 'gcmh)
(setq gcmh-idle-delay 5
      gcmh-high-cons-threshold (* 128 1024 1024))
(gcmh-mode 1)

(setq redisplay-skip-fontification-on-input t
      fast-but-imprecise-scrolling t
      jit-lock-defer-time 0.05
      inhibit-compacting-font-caches t
      bidi-inhibit-bpa t)
(setq-default bidi-paragraph-direction 'left-to-right)

;;; Basics

(setq ns-alternate-modifier 'meta)
(menu-bar-mode -1)

(setq backup-directory-alist
      `(("." . ,(expand-file-name "backups/" user-emacs-directory)))
      auto-save-file-name-transforms
      `((".*" ,(expand-file-name "auto-save/" user-emacs-directory) t)))

;;; Lazy packages

(autoload 'paredit-mode "paredit" nil t)
(autoload 'elisp-autofmt-mode "elisp-autofmt" nil t)
(autoload 'buffer-terminator-mode "buffer-terminator" nil t)
(autoload 'elcord-mode "elcord" nil t)

(dolist (hook '(emacs-lisp-mode-hook
                lisp-mode-hook
                lisp-interaction-mode-hook))
  (add-hook hook #'paredit-mode))
(add-hook 'emacs-lisp-mode-hook #'elisp-autofmt-mode)

(run-with-idle-timer 1 nil #'buffer-terminator-mode 1)

;;; Core

(require 'evil)
(evil-mode 1)

;; Order matters: helpers before keymaps (`sb/leader'), keymaps before run-code.
(require 'init-helpers)
(require 'init-ui)
(require 'init-explorer)
(require 'init-keymaps)
(require 'init-treesit)
(require 'init-highlights)
(require 'init-lsp)
(require 'init-lisp)

(require 'run-code)
(add-hook 'run-code-mode-hook #'evil-normalize-keymaps)
(run-code-global-mode 1)

(require 'init-start)


;;; Org source blocks

(with-eval-after-load 'org
  (require 'org-src)

  ;; Native syntax highlighting in source blocks.
  (setq org-src-fontify-natively t)

  ;; Common Lisp.
  (require 'lisp-mode)
  (add-to-list 'org-src-lang-modes '("common-lisp" . lisp))

  ;; Rust.
  (cond
   ((require 'rust-ts-mode nil t)
    (add-to-list 'org-src-lang-modes '("rust" . rust-ts)))
   ((require 'rust-mode nil t)
    (add-to-list 'org-src-lang-modes '("rust" . rust)))

   ;; Haskell.
   )
  (cond
   ((require 'haskell-mode nil t)
    (add-to-list 'org-src-lang-modes '("haskell" . haskell)))
   ((require 'haskell-ts-mode nil t)
    (add-to-list 'org-src-lang-modes '("haskell" . haskell-ts)))))

;;; Org

(add-to-list 'load-path
             (expand-file-name "packages/textui" user-emacs-directory))
(add-to-list 'load-path
             (expand-file-name "packages/org-table-widget"
                               user-emacs-directory))

(require 'org-modern)
(setq org-modern-table nil)
(global-org-modern-mode)

(require 'org-table-widget)
(add-hook 'org-mode-hook #'org-table-widget-mode)

(require 'org-appear)
(add-hook 'org-mode-hook #'org-appear-mode)
;;; init.el ends here
