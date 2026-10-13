;;; early-init.el --- Early initialization -*- lexical-binding: t; -*-

(add-to-list 'warning-suppress-types '(files missing-lexbind-cookie))

(setq gc-cons-threshold most-positive-fixnum
      package-enable-at-startup nil
      frame-inhibit-implied-resize t)

;;; early-init.el ends here
