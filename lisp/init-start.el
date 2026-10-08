;;; init-start.el --- Start page -*- lexical-binding: t; -*-

(require 'seq)
(require 'cl-lib)
(require 'subr-x)

(defconst start-buffer-name "*start*")
(defconst start-width 56)

(defvar start-directory default-directory
  "Base directory for resolving typed file names.")

(defvar start-logo-file
  (expand-file-name "logo.txt" user-emacs-directory)
  "Text file printed above the table. Ignored if missing.")

(defvar start-eggs
  '((1  left  "143")
    (1  right "Fib")
    (48 left  "0x6f68696d652d6368616e")
    (48 right "thermonuclear banana"))
  "(LINE SIDE TEXT). LINE is absolute, starting at 1.")

(defvar-local start--files nil)

(defvar-local start--input "")

(defun start--home ()
  "Keep point at the end of the input field."
  (let ((p (text-property-any (point-min) (point-max) 'start-field-end t)))
    (when (and p (/= (point) p))
      (goto-char p))))

(define-derived-mode start-mode special-mode "start"
  (setq-local cursor-type nil
              truncate-lines t
              mode-line-format nil)
  (display-line-numbers-mode -1)
  (add-hook 'post-command-hook #'start--home nil t))

(defun start-field-insert ()
  (interactive)
  (when (characterp last-command-event)
    (setq start--input
          (concat start--input (char-to-string last-command-event)))
    (start-render)))

(defun start-field-yank ()
  (interactive)
  (setq start--input
        (concat start--input
                (replace-regexp-in-string "\n" "" (current-kill 0))))
  (start-render))

(defun start-field-delete ()
  (interactive)
  (when (> (length start--input) 0)
    (setq start--input (substring start--input 0 -1))
    (start-render)))

(defun start-field-clear ()
  (interactive)
  (setq start--input "")
  (start-render))

(defun start-field-open ()
  "Open recent file N, or the typed file name (created if missing)."
  (interactive)
  (let* ((name (string-trim start--input))
         (n (and (string-match-p "\\`[0-9]+\\'" name)
                 (string-to-number name)))
         (recent (and n (>= n 1) (nth (1- n) start--files))))
    (cond
     ((string-empty-p name))
     ((string-match-p "[[:space:]]" name)
      (start-field-clear))
     (recent
      (setq start--input "")
      (find-file recent))
     (n
      (start-field-clear))
     (t
      (setq start--input "")
      (find-file (expand-file-name name start-directory))))))

(defvar start--field-map
  (let ((m (make-sparse-keymap)))
    (cl-loop for c from 32 to 126
             do (define-key m (char-to-string c) #'start-field-insert))
    (define-key m [remap self-insert-command] #'start-field-insert)
    (define-key m (kbd "DEL") #'start-field-delete)
    (define-key m (kbd "<backspace>") #'start-field-delete)
    (define-key m (kbd "C-u") #'start-field-clear)
    (define-key m (kbd "C-y") #'start-field-yank)
    (define-key m (kbd "RET") #'start-field-open)
    (dolist (k '("<left>" "<right>" "<up>" "<down>"
                 "<mouse-1>" "<down-mouse-1>" "<drag-mouse-1>"
                 "C-n" "C-p" "C-f" "C-b" "C-a" "C-e"))
      (define-key m (kbd k) #'ignore))
    m)
  "Keymap attached to the field text, not to `start-mode-map'.")

(defun start--prompt ()
  (let* ((w 40)
         (s start--input)
         (shown (if (> (string-width s) w)
                    (concat "…" (substring s (- (length s) (1- w))))
                  s)))
    (concat (propertize ">_" 'face 'font-lock-keyword-face
                        'keymap start--field-map)
            (propertize " " 'keymap start--field-map)
            (propertize shown 'keymap start--field-map 'start-field t)
            (propertize " " 'keymap start--field-map 'start-field-end t))))

(defun start--logo ()
  (when (file-readable-p start-logo-file)
    (with-temp-buffer
      (insert-file-contents start-logo-file)
      (let ((ls (mapcar (lambda (l)
                          (string-trim-right
                           (replace-regexp-in-string "\t" "        " l)))
                        (split-string (buffer-string) "\n"))))
        (while (and ls (string-empty-p (car (last ls))))
          (setq ls (butlast ls)))
        ls))))

(defun start--row (label value)
  (let* ((label (upcase label))
         (value (upcase value))
         (dots (make-string
                (max 2 (- start-width (length label) (length value) 2))
                ?.)))
    (concat label " "
            (propertize dots 'face 'shadow)
            " " (propertize value 'face 'font-lock-keyword-face))))

(defun start--grammars ()
  (length (directory-files
           (expand-file-name "tree-sitter" user-emacs-directory)
           nil "\\.dylib\\'")))

(defun start--compose-row (block pad-w cols left right)
  "Build a row: left egg, centered BLOCK, right egg."
  (let* ((lead (if (and left (< (+ 2 (string-width left)) pad-w))
                   (concat "  " (propertize left 'face 'shadow))
                 ""))
         (line (concat lead
                       (make-string (- pad-w (string-width lead)) ?\s)
                       block)))
    (if (and right (<= (+ (string-width line) (string-width right) 5) cols))
        (concat line
                (make-string (- cols 4 (string-width right) (string-width line))
                             ?\s)
                (propertize right 'face 'shadow))
      line)))

(defun start-render ()
  (let ((buf (get-buffer-create start-buffer-name))
        (win (get-buffer-window start-buffer-name)))
    (with-current-buffer buf
      (unless (derived-mode-p 'start-mode) (start-mode))
      (let* ((inhibit-read-only t)
             (cols (if win (1- (window-max-chars-per-line win)) 80))
             (hgt (1- (if win (window-body-height win) 24)))
             (files (and (boundp 'recentf-list)
                         (seq-take (seq-filter #'file-exists-p recentf-list) 9)))
             (pkgs (length (directory-files
                            (expand-file-name "packages" user-emacs-directory)
                            nil "\\`[^.]")))
             (table
              (append
               (list (concat (propertize "EMACS" 'face 'bold) "  "
                             (propertize "INTERFACE READY FOR INQUIRY" 'face 'bold))
                     (propertize (make-string start-width ?─) 'face 'shadow)
                     (start--row "version" (format "%s %s" emacs-version system-configuration))
                     (start--row "native-comp" (if (native-comp-available-p) "yes" "no"))
                     (start--row "init" (emacs-init-time "%.3fs"))
                     (start--row "treesit grammars" (number-to-string (start--grammars)))
                     (start--row "features" (number-to-string (length features)))
                     (start--row "packages" (number-to-string pkgs))
                     (start--row "theme" (if custom-enabled-themes
                                             (symbol-name (car custom-enabled-themes))
                                           "default"))
                     (start--row "date" (format-time-string "%Y-%m-%d %H:%M"))
                     "")
               (when files
                 (cl-loop for f in files for i from 1
                          collect (concat (propertize (format "%d " i)
                                                      'face 'font-lock-constant-face)
                                          (truncate-string-to-width
                                           (abbreviate-file-name f)
                                           (- start-width 2) nil nil "…"))))
               (list "" (start--prompt))))
             (logo (start--logo))
             (block-w (apply #'max (mapcar #'string-width (append logo table))))
             (lines (append (mapcar (lambda (l)
                                      (concat (make-string (/ (- block-w (string-width l)) 2) ?\s)
                                              l))
                                    logo)
                            (when logo '(""))
                            table))
             (pad-w (max 0 (/ (- cols block-w) 2)))
             (pad (make-string pad-w ?\s))
             (top (max 0 (/ (- hgt (length lines)) 3)))
             (total (max hgt (+ top (length lines))))
             (egg-row (lambda (e) (min (1- (car e)) (1- total)))))
        (setq start--files files)
        (erase-buffer)
        (dotimes (r total)
          (let* ((i (- r top))
                 (b (if (and (>= i 0) (< i (length lines)))
                        (concat pad (nth i lines))
                      ""))
                 (l (cl-find-if (lambda (e) (and (eq (nth 1 e) 'left)
                                                 (= (funcall egg-row e) r)))
                                start-eggs))
                 (g (cl-find-if (lambda (e) (and (eq (nth 1 e) 'right)
                                                 (= (funcall egg-row e) r)))
                                start-eggs)))
            (insert (if (or l g)
                        (start--compose-row (if (string-empty-p b) "" (substring b pad-w))
                                            pad-w cols (nth 2 l) (nth 2 g))
                      b)
                    (if (< r (1- total)) "\n" ""))))
        (start--home)
        (set-buffer-modified-p nil)))
    buf))

(defun start--on-resize (_frame)
  (when (get-buffer-window start-buffer-name)
    (start-render)))

(recentf-mode 1)

(setq inhibit-startup-screen t
      initial-scratch-message nil
      initial-buffer-choice #'start-render)

(add-hook 'window-size-change-functions #'start--on-resize)

(provide 'init-start)
;;; init-start.el ends here
