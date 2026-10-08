;;; init-lisp.el --- Common Lisp (SLIME) -*- lexical-binding: t; -*-

(require 'slime-autoloads)

(setq inferior-lisp-program "sbcl")
(slime-setup '(slime-fancy))

(with-suppressed-warnings
    ((files missing-lexical-binding-cookie))
  (load (expand-file-name "~/.quicklisp/slime-helper.el")))

(provide 'init-lisp)
;;; init-lisp.el ends here
