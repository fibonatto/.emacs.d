;;; init-lisp.el --- Common Lisp (SLIME) -*- lexical-binding: t; -*-

(defun sb/setup-slime ()
  (require 'slime-autoloads)
  (setq inferior-lisp-program "sbcl")
  (slime-setup '(slime-fancy))
  (with-suppressed-warnings
      ((files missing-lexical-binding-cookie))
    (load (expand-file-name "~/.quicklisp/slime-helper.el"))))

(run-with-idle-timer 1 nil #'sb/setup-slime)

(provide 'init-lisp)
;;; init-lisp.el ends here
