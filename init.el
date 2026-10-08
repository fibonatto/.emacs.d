;;; init.el --- Entry point -*- lexical-binding: t; -*-

(add-to-list 'load-path (expand-file-name "lisp" user-emacs-directory))
(add-to-list 'load-path
             (expand-file-name "themes/terrazzo-emacs" user-emacs-directory))

(let ((default-directory (expand-file-name "packages" user-emacs-directory)))
  (normal-top-level-add-subdirs-to-load-path))

(setq ns-alternate-modifier 'meta)
(menu-bar-mode -1)

(setq backup-directory-alist
      `(("." . ,(expand-file-name "backups/" user-emacs-directory))))
(setq auto-save-file-name-transforms
      `((".*" ,(expand-file-name "auto-save/" user-emacs-directory) t)))

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

(require 'elcord)
(elcord-mode)

;;; init.el ends here
