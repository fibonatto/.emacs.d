;;; init-lsp.el --- Eglot -*- lexical-binding: t; -*-

(require 'eglot)

(setq eglot-sync-connect nil
      eglot-autoshutdown t
      eglot-events-buffer-config '(:size 0))

(add-to-list 'eglot-ignored-server-capabilities
             :workspace/didChangeWatchedFiles)

(dolist (hook '(c-ts-mode-hook
                c++-ts-mode-hook
                rust-ts-mode-hook
                typescript-ts-mode-hook
                tsx-ts-mode-hook
                json-ts-mode-hook
                bash-ts-mode-hook))
  (add-hook hook #'eglot-ensure))

(defun sb/format-buffer ()
  (when (eglot-managed-p)
    (eglot-format-buffer)))

(add-hook 'before-save-hook #'sb/format-buffer)

(provide 'init-lsp)
;;; init-lsp.el ends here
