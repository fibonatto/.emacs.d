;;; init-keymaps.el --- Key bindings -*- lexical-binding: t; -*-

;;; Windows

(windmove-default-keybindings 'control)

(evil-define-key 'normal 'global
  (kbd "C-h") #'windmove-left
  (kbd "C-j") #'windmove-down
  (kbd "C-k") #'windmove-up
  (kbd "C-l") #'windmove-right
  (kbd "<left>")  (lambda () (interactive) (enlarge-window-horizontally -4))
  (kbd "<right>") (lambda () (interactive) (enlarge-window-horizontally 4))
  (kbd "<up>")    (lambda () (interactive) (enlarge-window 2))
  (kbd "<down>")  (lambda () (interactive) (enlarge-window -2)))

;;; Editing

(evil-define-key 'normal 'global
  (kbd "U") #'evil-redo
  (kbd "m") #'evil-jump-item
  (kbd "(") #'sb/dedent-line
  (kbd ")") #'sb/indent-line)

(evil-define-key 'visual 'global
  (kbd "<") #'sb/shift-left-keep
  (kbd ">") #'sb/shift-right-keep
  (kbd "S") #'sb/visual-sort)

(evil-define-key '(normal visual) 'global
  (kbd "!") #'sb/comment-toggle)

;;; Movement

(evil-define-key '(normal visual) 'global
  (kbd "J") (lambda () (interactive) (sb/smart-jump 1))
  (kbd "K") (lambda () (interactive) (sb/smart-jump -1))
  (kbd "H") #'evil-backward-WORD-begin
  (kbd "L") #'evil-forward-WORD-begin)

;;; Leader (,)

(sb/leader "w" #'save-buffer)
(sb/leader "q" #'evil-quit)
(sb/leader "b" #'consult-buffer)
(sb/leader "rg" #'consult-ripgrep)
(sb/leader "gs" #'magit-status)
(sb/leader "gc" #'magit-log-current)
(sb/leader "/" #'sb/comment-toggle '(normal visual))

(sb/leader "lh" #'eldoc-doc-buffer)
(sb/leader "rn" #'eglot-rename)
(sb/leader "d" #'xref-find-definitions)
(sb/leader "u" #'xref-go-back)

(sb/leader "k" (sb/external-command "kindcoder"))
(sb/leader "t" (sb/external-command "ts-deps"))
(sb/leader "h" (sb/external-command "holefill" 2))
(sb/leader "a" (sb/external-command "agda2kind" 1))

;; Keys that are both a command and a prefix. nvim resolves these with
;; timeoutlen = 300; Emacs has no such timeout, so `sb/leader-pair' emulates it.
(sb/leader "c" (sb/leader-pair #'sb/comment-toggle
                               '(("a" . eglot-code-actions)))
           '(normal visual))
(sb/leader "f" (sb/leader-pair (sb/external-command "refactor" 1)
                               '(("f" . vertico-repeat)
                                 ("m" . eglot-format-buffer))))
(sb/leader "s" (sb/leader-pair #'sb/chatsh
                               '(("d" . consult-imenu)
                                 ("w" . xref-find-apropos))))
(sb/leader "x" (sb/leader-pair #'sb/save-and-quit
                               '(("x" . consult-flymake))))

;;; Build and quickfix

(evil-define-key 'normal 'global
  (kbd "<f5>")  #'sb/make
  (kbd "<f6>")  #'sb/copen
  (kbd "<f7>")  #'next-error
  (kbd "<f10>") #'previous-error
  (kbd "<f9>")  (lambda () (interactive) (shell-command "./main")))

;;; LSP

(evil-define-key 'normal 'global
  (kbd "gd") #'xref-find-definitions
  (kbd "gr") #'xref-find-references
  (kbd "[d") #'flymake-goto-prev-error
  (kbd "]d") #'flymake-goto-next-error)

(with-eval-after-load 'eglot
  (evil-define-key 'normal eglot-mode-map
    (kbd "gi") #'eglot-find-implementation))

;;; Navigation panels

(evil-define-key 'normal 'global
  (kbd "C-p") #'project-find-file
  (kbd "M-a") #'neotree-toggle
  (kbd "<f8>") #'imenu-list-smart-toggle)

(global-set-key [f8] #'neotree-toggle)

(with-eval-after-load 'neotree
  (evil-define-key 'normal neotree-mode-map
    (kbd "RET")
    (lambda (&optional arg)
      (interactive "P")
      (neo-global--select-window)
      (neo-buffer--execute arg 'neo-open-file 'neo-open-dir))))

;;; Appearance

(evil-define-key 'normal 'global
  (kbd "M-t") #'terrazzo-toggle)

(provide 'init-keymaps)
;;; init-keymaps.el ends here
