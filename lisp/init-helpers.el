;;; init-helpers.el --- sb/ helper functions -*- lexical-binding: t; -*-

(require 'cl-lib)

;;; Compatibility

(unless (fboundp 'derived-mode-all-parents)
  (defun derived-mode-all-parents (mode)
    (let (parents)
      (while mode
        (push mode parents)
        (setq mode (get mode 'derived-mode-parent)))
      (nreverse parents))))

;;; Logging

(defconst sb/logs-directory
  (expand-file-name "logs" user-emacs-directory)
  "Directory where log files are written.")

(defun sb/log (file fmt &rest args)
  "Append a timestamped line to FILE inside `sb/logs-directory'.
FMT and ARGS are passed to `format'. The directory is created if missing."
  (make-directory sb/logs-directory t)
  (write-region
   (format "%s %s\n"
           (format-time-string "%Y-%m-%d %H:%M:%S")
           (apply #'format fmt args))
   nil
   (expand-file-name file sb/logs-directory)
   'append
   'silent))

;;; Leader keys

(defun sb/leader (key def &optional states)
  "Bind leader (,) KEY to DEF in STATES (default: normal)."
  (evil-define-key (or states 'normal) 'global
    (kbd (concat "," key))
    def))

(defun sb/leader-pair (short-cmd extras)
  "Emulate nvim's `timeoutlen' for a leader key that is also a prefix.
Run SHORT-CMD unless, within 0.3s, one of the keys in EXTRAS (an alist of
KEY-STRING . COMMAND) is pressed."
  (lambda ()
    (interactive)
    (let* ((ev (read-event nil nil 0.3))
           (extra (and (characterp ev)
                       (cdr (assoc (char-to-string ev) extras)))))
      (if extra
          (call-interactively extra)
        (when ev (push ev unread-command-events))
        (call-interactively short-cmd)))))

;;; External commands

(defvar vterm-shell)
(declare-function vterm "vterm")

(defun sb/external (cmd &optional nfile)
  "Run CMD in the shell like nvim's :!CMD, passing the file NFILE times.
Log the command and its exit status to logs/commands.log."
  (let* ((file (shell-quote-argument (or (buffer-file-name) "")))
         (args (and nfile (make-list nfile file)))
         (full (string-join (cons cmd args) " "))
         (status (shell-command full)))
    (sb/log "commands.log" "external exit=%s dir=%s cmd=%s"
            status default-directory full)
    status))

(defun sb/external-command (cmd &optional nfile)
  (lambda ()
    (interactive)
    (sb/external cmd nfile)))

(defun sb/chatsh ()
  (interactive)
  (let ((vterm-shell "chatsh"))
    (vterm "*chatsh*")))

;;; Editing

(defun sb/comment-toggle ()
  "Toggle linewise comments on the current line or visual selection."
  (interactive)
  (let* ((visual (evil-visual-state-p))
         (beg (if visual (region-beginning) (point)))
         (end (if visual (region-end) (point))))
    (when visual (evil-normal-state))
    (when (and (> end beg) (save-excursion (goto-char end) (bolp)))
      (setq end (1- end)))
    (save-excursion
      (comment-or-uncomment-region
       (progn (goto-char beg) (line-beginning-position))
       (progn (goto-char end) (line-end-position))))))

(defun sb/shift-left-keep ()
  "Like nvim's `<gv' in visual mode."
  (interactive)
  (evil-shift-left (region-beginning) (region-end))
  (evil-normal-state)
  (evil-visual-restore))

(defun sb/shift-right-keep ()
  "Like nvim's `>gv' in visual mode."
  (interactive)
  (evil-shift-right (region-beginning) (region-end))
  (evil-normal-state)
  (evil-visual-restore))

(defun sb/dedent-line ()
  (interactive)
  (evil-shift-left (line-beginning-position) (line-end-position)))

(defun sb/indent-line ()
  (interactive)
  (evil-shift-right (line-beginning-position) (line-end-position)))

(defun sb/visual-sort ()
  "Like nvim's visual `:sort'."
  (interactive)
  (let ((beg (region-beginning)) (end (region-end)))
    (evil-normal-state)
    (sort-lines nil beg end)))

;;; Navigation

(defun sb/smart-jump (step)
  "Jump to the next (STEP = 1) or previous (STEP = -1) code block."
  (evil-set-jump)
  (let* ((total (count-lines (point-min) (point-max)))
         (cur (line-number-at-pos))
         (target (+ cur step)))
    (cl-flet ((blank-p (n)
                (save-excursion
                  (goto-char (point-min))
                  (forward-line (1- n))
                  (looking-at-p "[ \t]*$"))))
      (if (blank-p cur)
          ;; From a blank line, jump to the next line with content.
          (while (and (>= target 1) (<= target total) (blank-p target))
            (setq target (+ target step)))
        ;; From a block, jump after the next blank-line separator.
        (let ((found-blank nil) (done nil))
          (while (and (not done) (>= target 1) (<= target total))
            (cond ((blank-p target) (setq found-blank t))
                  (found-blank (setq done t)))
            (unless done (setq target (+ target step)))))))
    (setq target (max 1 (min total target)))
    (goto-char (point-min))
    (forward-line (1- target))
    (back-to-indentation)))

;;; Build

(defun sb/make ()
  "nvim's :make. Log the start to logs/commands.log."
  (interactive)
  (sb/log "commands.log" "make START dir=%s cmd=%s"
          default-directory compile-command)
  (compile compile-command))

(defun sb/log-compilation-finish (buffer msg)
  "Log the result of a compilation in BUFFER (MSG is the status string)."
  (when (string= (buffer-name buffer) "*compilation*")
    (sb/log "commands.log" "make FINISH %s" (string-trim msg))))

(add-hook 'compilation-finish-functions #'sb/log-compilation-finish)

(defun sb/copen ()
  "nvim's :copen."
  (interactive)
  (pop-to-buffer (get-buffer-create "*compilation*")))

;;; Files

(defun sb/save-and-quit ()
  "nvim's :x."
  (interactive)
  (save-buffer)
  (evil-quit))

;;; Tree-sitter

(defvar treesit-language-source-alist)

(defun sb/treesit-install-all ()
  "Install every grammar listed in `treesit-language-source-alist'.
Continue past failures. Each step is logged to logs/treesit.log.
A grammar that builds but cannot be loaded (e.g. ABI mismatch) is
reported as a failure."
  (interactive)
  (let ((langs (mapcar #'car treesit-language-source-alist))
        (failed nil))
    (sb/log "treesit.log" "START installing %d grammars: %S"
            (length langs) langs)
    (dolist (lang langs)
      (sb/log "treesit.log" "BEGIN %s" lang)
      (condition-case err
          (progn
            (treesit-install-language-grammar lang)
            (if (treesit-language-available-p lang)
                (sb/log "treesit.log" "OK %s" lang)
              (push (cons lang "built but not loadable") failed)
              (sb/log "treesit.log" "FAIL %s: built but not loadable" lang)))
        (error
         (push (cons lang (error-message-string err)) failed)
         (sb/log "treesit.log" "FAIL %s: %s" lang (error-message-string err)))))
    (setq failed (nreverse failed))
    (sb/log "treesit.log" "DONE ok=%d failed=%d%s"
            (- (length langs) (length failed))
            (length failed)
            (if failed (format " %S" failed) ""))
    (message "Tree-sitter install finished: %d ok, %d failed (see %s)"
             (- (length langs) (length failed))
             (length failed)
             (expand-file-name "treesit.log" sb/logs-directory))))

(provide 'init-helpers)
;;; init-helpers.el ends here
