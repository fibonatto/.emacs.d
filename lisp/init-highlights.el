;;; init-highlights.el --- Tree-sitter highlighting -*- lexical-binding: t; -*-

(require 'treesit-x)

(dolist (mapping
         '(("@character"            . "@font-lock-string-face")
           ("@string.escape"        . "@font-lock-escape-face")
           ("@string.special.path"  . "@font-lock-string-face")
           ("@number.float"         . "@font-lock-number-face")
           ("@constant.builtin"     . "@font-lock-constant-face")
           ("@type.builtin"         . "@font-lock-builtin-face")
           ("@attribute"            . "@font-lock-preprocessor-face")
           ("@keyword.conditional"  . "@font-lock-keyword-face")
           ("@keyword.import"       . "@font-lock-keyword-face")
           ("@keyword.return"       . "@font-lock-keyword-face")
           ("@punctuation.bracket"  . "@font-lock-bracket-face")
           ("@punctuation.delimiter" . "@font-lock-delimiter-face")))
  (setf (alist-get (car mapping) treesit-generic-mode-font-lock-map
                   nil nil #'string=)
        (cdr mapping)))

(setq treesit-generic-mode-font-lock-map
      (sort treesit-generic-mode-font-lock-map
            (lambda (a b)
              (> (length (car a))
                 (length (car b))))))

(provide 'init-highlights)
;;; init-highlights.el ends here
