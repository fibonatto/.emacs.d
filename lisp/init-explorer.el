;;; init-explorer.el --- File explorer -*- lexical-binding: t; -*-

(autoload 'neotree-toggle "neotree" nil t)

(with-eval-after-load 'neotree
  (require 'nerd-icons)
  (setq neo-theme 'nerd-icons
        neo-window-position 'right))

(provide 'init-explorer)
;;; init-explorer.el ends here
