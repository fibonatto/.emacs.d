;;; init-ui.el --- Theme and visual details -*- lexical-binding: t; -*-

(require 'terrazzo-theme)

(setq-default fill-column 100)
(global-display-line-numbers-mode 1)

(defun sb/disable-line-numbers ()
  (display-line-numbers-mode 0))

(dolist (hook '(vterm-mode-hook
                imenu-list-major-mode-hook
                compilation-mode-hook
                neotree-mode-hook))
  (add-hook hook #'sb/disable-line-numbers))

(dolist (hook '(prog-mode-hook text-mode-hook))
  (add-hook hook #'display-fill-column-indicator-mode))

(unless standard-display-table
  (setq standard-display-table (make-display-table)))
(set-display-table-slot standard-display-table 'vertical-border
                        (make-glyph-code ?¦))

(defun sb/mac-system-appearance ()
  "Return the current macOS appearance as `dark' or `light'."
  (if (string= (string-trim
                (shell-command-to-string
                 "defaults read -g AppleInterfaceStyle 2>/dev/null"))
               "Dark")
      'dark
    'light))

(defun sb/apply-system-theme (&rest _)
  "Apply the current macOS appearance."
  (terrazzo-load
   (if (eq (sb/mac-system-appearance) 'dark)
       'terrazzo-dark
     'terrazzo-light)))

(sb/apply-system-theme)

(when (boundp 'ns-system-appearance-change-functions)
  (add-hook 'ns-system-appearance-change-functions
            #'sb/apply-system-theme))

(provide 'init-ui)
;;; init-ui.el ends here
