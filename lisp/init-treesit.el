;;; init-treesit.el --- Tree-sitter configuration -*- lexical-binding: t; -*-

(require 'treesit)
(require 'treesit-x)

(setq treesit-font-lock-level 4)

(setq treesit-language-source-alist
      '((c          "https://github.com/tree-sitter/tree-sitter-c")
        (cpp        "https://github.com/tree-sitter/tree-sitter-cpp")
        (rust       "https://github.com/tree-sitter/tree-sitter-rust")
        (json       "https://github.com/tree-sitter/tree-sitter-json")
        (bash       "https://github.com/tree-sitter/tree-sitter-bash")
        (typescript "https://github.com/tree-sitter/tree-sitter-typescript"
                    "master" "typescript/src")
        (tsx        "https://github.com/tree-sitter/tree-sitter-typescript"
                    "master" "tsx/src")
        (bend2      "https://github.com/nicolas-abril/tree-sitter-bend2"
                    "main")))

(setq major-mode-remap-alist
      '((c-mode          . c-ts-mode)
        (c++-mode        . c++-ts-mode)
        (c-or-c++-mode   . c-or-c++-ts-mode)
        (js-json-mode    . json-ts-mode)
        (sh-mode         . bash-ts-mode)))

(add-to-list 'auto-mode-alist '("\\.rs\\'"  . rust-ts-mode))
(add-to-list 'auto-mode-alist '("\\.ts\\'"  . typescript-ts-mode))
(add-to-list 'auto-mode-alist '("\\.tsx\\'" . tsx-ts-mode))

(define-derived-mode bend-ts-mode prog-mode "Bend"
  "Major mode for Bend 2 using Tree-sitter."
  (treesit-generic-mode-setup 'bend2)
  (treesit-major-mode-setup))

(add-to-list 'auto-mode-alist '("\\.bend\\'" . bend-ts-mode))

(provide 'init-treesit)
;;; init-treesit.el ends here
