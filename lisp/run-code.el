;;; run-code.el --- Run source files from Emacs -*- lexical-binding: t; -*-

(require 'cl-lib)
(require 'comint)
(require 'subr-x)

(defgroup run-code nil
  "Run source files from Emacs."
  :group 'tools)

(defcustom run-code-auto-save t
  "Save the current buffer before running."
  :type 'boolean
  :group 'run-code)

(defcustom run-code-clear-terminal t
  "Clear the run-code terminal before each execution."
  :type 'boolean
  :group 'run-code)

(defcustom run-code-show-feedback t
  "Show execution feedback in the echo area."
  :type 'boolean
  :group 'run-code)

(defcustom run-code-timeout 0
  "Execution timeout in seconds.
Zero disables the timeout."
  :type 'integer
  :group 'run-code)

(defcustom run-code-temp-dir "/tmp"
  "Temporary directory used by run-code."
  :type 'directory
  :group 'run-code)

(defcustom run-code-terminal-mode t
  "Use the *run-code* terminal when non-nil.
When nil, use `compile` instead."
  :type 'boolean
  :group 'run-code)

(defcustom run-code-terminal-position 'right
  "Position of the *run-code* side window."
  :type '(choice
          (const :tag "Right" right)
          (const :tag "Left" left)
          (const :tag "Bottom" bottom)
          (const :tag "Top" top))
  :group 'run-code)

(defcustom run-code-terminal-width 40
  "Width of the *run-code* side window."
  :type 'integer
  :group 'run-code)

(defcustom run-code-terminal-height 10
  "Height of the *run-code* bottom side window."
  :type 'integer
  :group 'run-code)

(defcustom run-code-tmux-enabled t
  "Whether tmux execution is enabled."
  :type 'boolean
  :group 'run-code)

(defcustom run-code-tmux-target ""
  "tmux target used when running outside tmux.
An empty string uses the current tmux environment."
  :type 'string
  :group 'run-code)

(defcustom run-code-commands nil
  "User-defined development commands.
Keys are Emacs major mode names."
  :type '(alist :key-type string :value-type sexp)
  :group 'run-code)

(defcustom run-code-test-commands nil
  "User-defined test commands.
Keys are Emacs major mode names."
  :type '(alist :key-type string :value-type sexp)
  :group 'run-code)

(defconst run-code-buffer-name "*run-code*")

(defvar run-code-process nil)

;; =============================================================================
;; File and placeholder handling
;; =============================================================================

(defun run-code--file ()
  (or buffer-file-name ""))

(defun run-code--file-directory ()
  (or (file-name-directory (run-code--file))
      default-directory))

(defun run-code--relative-file ()
  (let ((file (expand-file-name (run-code--file)))
        (cwd (file-name-as-directory
              (expand-file-name default-directory))))
    (if (file-in-directory-p file cwd)
        (file-relative-name file cwd)
      file)))

(defun run-code--apply-modifier (file modifier)
  (pcase modifier
    ("p" (expand-file-name file))
    ("t" (file-name-nondirectory file))
    ("h" (or (file-name-directory file) "."))
    ("r" (file-name-sans-extension file))
    ("e" (or (file-name-extension file) ""))
    (_ file)))

(defun run-code--apply-modifiers (file modifiers)
  (dolist (modifier modifiers file)
    (setq file
          (run-code--apply-modifier file modifier))))

(defun run-code--placeholder-value (modifiers)
  (let ((file
         (if (member "p" modifiers)
             (expand-file-name (run-code--file))
           (run-code--relative-file))))
    (run-code--apply-modifiers file modifiers)))

(defun run-code--expand-placeholders (command)
  (let ((i 0)
        (length (length command))
        result)
    (while (< i length)
      (let ((char (aref command i)))
        (cond
         ((/= char ?%)
          (push char result)
          (setq i (1+ i)))

         ((and (< (1+ i) length)
               (= (aref command (1+ i)) ?%))
          (push ?% result)
          (setq i (+ i 2)))

         (t
          (let ((j (1+ i))
                modifiers)
            (if (and (< j length)
                     (= (aref command j) ?<))
                (progn
                  (setq modifiers '("r"))
                  (setq j (1+ j)))
              (while
                  (and (< j length)
                       (= (aref command j) ?:)
                       (< (1+ j) length)
                       (string-match-p
                        "\\`[phtre]\\'"
                        (string (aref command (1+ j)))))
                (push (string (aref command (1+ j))) modifiers)
                (setq j (+ j 2))))

            (setq modifiers (nreverse modifiers))

            (let ((value
                   (shell-quote-argument
                    (run-code--placeholder-value modifiers))))
              (dolist (c (string-to-list value))
                (push c result)))

            (setq i j))))))

    (apply #'string (nreverse result))))

;; =============================================================================
;; Helpers
;; =============================================================================

(defun run-code--buffer-text ()
  (buffer-substring-no-properties (point-min) (point-max)))

(defun run-code--makefile-p ()
  (seq-some
   #'file-readable-p
   '("Makefile" "makefile" "GNUmakefile")))

(defun run-code--c-extra-flags ()
  (if (string-match-p
       "#include[[:space:]]*<cs50\\.h>"
       (run-code--buffer-text))
      " -I/usr/local/include -L/usr/local/lib -lcs50"
    ""))

(defun run-code--filetype ()
  (symbol-name major-mode))

(defun run-code--get-c-command ()
  (if (run-code--makefile-p)
      "make run"
    (concat
     "clang %"
     (run-code--c-extra-flags)
     " -o %:r && ./%:r")))

(defun run-code--get-c-opt-command ()
  (if (run-code--makefile-p)
      "make && ./$(basename %:r)"
    (concat
     "clang -O2 %"
     (run-code--c-extra-flags)
     " -o %:r && ./%:r")))

(defun run-code--get-cpp-command (optimized)
  (let ((flags (concat
                "-std=c++17"
                (when optimized " -O2")))
        (llvm ""))
    (when (string-match-p
           "#include[[:space:]]*[<\"]llvm/"
           (run-code--buffer-text))
      (setq llvm
            " $(llvm-config --cxxflags --ldflags --system-libs --libs all)"))
    (concat
     "clang++ "
     flags
     " %"
     llvm
     " -o %:r && ./%:r")))

(defun run-code--get-haskell-opt-command ()
  (let ((exe
         (expand-file-name
          (format ".run_code_%d" (emacs-pid))
          run-code-temp-dir)))
    (concat
     "ghc -O2 -threaded % -o "
     (shell-quote-argument exe)
     " && "
     (shell-quote-argument exe)
     "; rc=$?; rm -f "
     (shell-quote-argument exe)
     " %:r.hi %:r.o; exit $rc")))

(defun run-code--get-typescript-opt-command ()
  (concat
   "tsc % --outDir "
   (shell-quote-argument run-code-temp-dir)
   " && node "
   (shell-quote-argument run-code-temp-dir)
   "/%:t:r.js"))

;; =============================================================================
;; Commands
;; =============================================================================

(defconst run-code-development-commands
  '(("agda-mode" . "agda-cli check %")
    ("bend-mode" . "bend %")
    ("c-mode" . run-code--get-c-command)
    ("c++-mode" . (lambda () (run-code--get-cpp-command nil)))
    ("c-ts-mode" . run-code--get-c-command)
    ("c++-ts-mode" . (lambda () (run-code--get-cpp-command nil)))
    ("caramel-mode" . "mel main")
    ("coc-mode" . "coc type %:r && coc norm %:r")
    ("csharp-mode" . "mcs % -out:%:r.exe && mono %:r.exe")
    ("cuda-mode" . "nvcc % -o %:r && ./%:r")
    ("dart-mode" . "dart %")
    ("dvl-mode" . "dvl run %")
    ("elm-mode" . "elm make % --output=%:r.js")
    ("erlang-mode" . "escript %")
    ("go-mode" . "go run %")
    ("haskell-mode" . "stack run")
    ("html-mode" . "npm run dev")
    ("mhtml-mode" . "npm run dev")
    ("http-mode" . "httpyac --all route.http")
    ("java-mode" . "javac % && java -cp %:h %:t:r")
    ("js-mode" . "bun run %")
    ("js-ts-mode" . "bun run %")
    ("typescript-mode" . "bun run %")
    ("typescript-ts-mode" . "bun run %")
    ("julia-mode" . "julia %")
    ("kotlin-mode" . "kotlinc % -include-runtime -d %:r.jar && java -jar %:r.jar")
    ("lua-mode" . "lua %")
    ("nim-mode" . "nim compile --run %")
    ("ocaml-mode" . "ocamlc -o %:r % && ./%:r")
    ("perl-mode" . "perl -w %")
    ("php-mode" . "php %")
    ("python-mode" . "python3 -u %")
    ("python-ts-mode" . "python3 -u %")
    ("r-mode" . "Rscript %")
    ("ruby-mode" . "ruby %")
    ("rust-mode" . "rustc -O % -o %:r && ./%:r")
    ("rust-ts-mode" . "rustc -O % -o %:r && ./%:r")
    ("scala-mode" . "scala %")
    ("scheme-mode" . "csc % && ./%:r")
    ("sh-mode" . "bash -x %")
    ("swift-mode" . "swift %")
    ("web-mode" . "npm run dev")
    ("zig-mode" . "zig run %")))

(defconst run-code-optimized-commands
  '(("agda-mode" . "agda-cli run %")
    ("bend-mode" . "bend %")
    ("c-mode" . run-code--get-c-opt-command)
    ("c++-mode" . (lambda () (run-code--get-cpp-command t)))
    ("c-ts-mode" . run-code--get-c-opt-command)
    ("c++-ts-mode" . (lambda () (run-code--get-cpp-command t)))
    ("cuda-mode" . "nvcc -O3 % -o %:r && ./%:r")
    ("dart-mode" . "dart compile exe % -o %:r && ./%:r")
    ("go-mode" . "go build -ldflags=\"-s -w\" -o %:r % && ./%:r")
    ("haskell-mode" . run-code--get-haskell-opt-command)
    ("html-mode" . "python3 -m http.server 8000")
    ("mhtml-mode" . "python3 -m http.server 8000")
    ("java-mode" . "javac % && java -server -XX:+UseG1GC -cp %:h %:t:r")
    ("js-mode" . "node %")
    ("js-ts-mode" . "node %")
    ("julia-mode" . "julia -O3 %")
    ("kotlin-mode" . "kotlinc % -include-runtime -d %:r.jar && java -server -jar %:r.jar")
    ("nim-mode" . "nim compile --opt:speed --run %")
    ("ocaml-mode" . "ocamlopt -O3 -o %:r % && ./%:r")
    ("pascal-mode" . "fpc -O3 % && ./%:r")
    ("python-mode" . "python3 -O %")
    ("python-ts-mode" . "python3 -O %")
    ("rust-mode" . "cargo run --release")
    ("rust-ts-mode" . "cargo run --release")
    ("scala-mode" . "scalac % && scala -J-server %:r")
    ("swift-mode" . "swiftc -O % -o %:r && ./%:r")
    ("typescript-mode" . run-code--get-typescript-opt-command)
    ("typescript-ts-mode" . run-code--get-typescript-opt-command)
    ("zig-mode" . "zig run -O ReleaseFast %")))

(defconst run-code-test-commands-default
  '(("c-mode" . "make test")
    ("c++-mode" . "make test")
    ("c-ts-mode" . "make test")
    ("c++-ts-mode" . "make test")
    ("dart-mode" . "dart test")
    ("go-mode" . "go test ./...")
    ("haskell-mode" . "stack test")
    ("java-mode" . "mvn test")
    ("js-mode" . "bun test")
    ("js-ts-mode" . "bun test")
    ("julia-mode" . "julia -e 'using Pkg; Pkg.test()'")
    ("kotlin-mode" . "gradle test")
    ("nim-mode" . "nimble test")
    ("ocaml-mode" . "dune test")
    ("python-mode" . "pytest")
    ("python-ts-mode" . "pytest")
    ("rust-mode" . "cargo test")
    ("rust-ts-mode" . "cargo test")
    ("scala-mode" . "sbt test")
    ("swift-mode" . "swift test")
    ("typescript-mode" . "bun test")
    ("typescript-ts-mode" . "bun test")
    ("zig-mode" . "zig build test")))

;; =============================================================================
;; Command resolution
;; =============================================================================

(defun run-code--resolve-command (commands filetype)
  (let ((entry (assoc filetype commands)))
    (when entry
      (let ((command (cdr entry)))
        (if (functionp command)
            (funcall command)
          command)))))

(defun run-code--get-command (mode)
  (let ((filetype (run-code--filetype)))
    (pcase mode
      ('test
       (or (run-code--resolve-command
            run-code-test-commands
            filetype)
           (run-code--resolve-command
            run-code-test-commands-default
            filetype)))

      ('dev
       (or (run-code--resolve-command
            run-code-commands
            filetype)
           (run-code--resolve-command
            run-code-development-commands
            filetype)))

      ('opt
       (or (run-code--resolve-command
            run-code-commands
            filetype)
           (run-code--resolve-command
            run-code-optimized-commands
            filetype))))))

(defun run-code--has-command-p (filetype)
  (or (assoc filetype run-code-development-commands)
      (assoc filetype run-code-optimized-commands)
      (assoc filetype run-code-test-commands-default)
      (assoc filetype run-code-commands)
      (assoc filetype run-code-test-commands)))

;; =============================================================================
;; Execution command
;; =============================================================================

(defun run-code--check-file ()
  (unless (and buffer-file-name
               (file-readable-p buffer-file-name))
    (user-error "File not found"))

  (when (and run-code-auto-save
             (buffer-modified-p))
    (save-buffer))

  t)

(defun run-code--build-exec-command (command backend)
  (let ((script (run-code--expand-placeholders command)))
    (when (eq backend 'tmux)
      (setq script
            (concat
             script
             "; rc=$?; printf '\\n[run-code] exit code: %s\\n' \"$rc\"; exit $rc")))

    ;; Substitui shell-quote-argument por envelopamento em aspas simples para
    ;; preservar a estrutura do pipeline quando repassado ao sh -c.
    (let* ((quoted-script (format "'%s'" (replace-regexp-in-string "'" "'\\''" script)))
           (body (concat "sh -c " quoted-script)))
      
      ;; Remoção do "clear && ". 
      ;; A limpeza nativa do shell falha no TERM=dumb do comint-mode e causava 
      ;; a interrupção da execução (short-circuit). O buffer já é limpo pelo Emacs.
      (if (> run-code-timeout 0)
          (format "time timeout %ds %s" run-code-timeout body)
        (concat "time " body)))))


;; =============================================================================
;; Emacs terminal
;; =============================================================================

(defun run-code--terminal-window ()
  (display-buffer
   (get-buffer-create run-code-buffer-name)
   `((display-buffer-in-side-window)
     (side . ,run-code-terminal-position)
     (slot . 0)
     (window-width . ,run-code-terminal-width)
     (window-height . ,run-code-terminal-height))))

(defun run-code--terminal-buffer ()
  (let ((buffer (get-buffer-create run-code-buffer-name)))
    (with-current-buffer buffer
      (unless (comint-check-proc buffer)
        (make-comint-in-buffer "run-code" buffer shell-file-name nil "-i")
        (setq-local comint-prompt-regexp comint-prompt-regexp)))
    buffer))

(defun run-code--clear-terminal ()
  (with-current-buffer run-code-buffer-name
    (let ((inhibit-read-only t))
      (erase-buffer))))

(defun run-code--run-terminal (command)
  (let* ((dir default-directory)
         (buffer (run-code--terminal-buffer)))
    (run-code--terminal-window)

    (when run-code-clear-terminal
      (with-current-buffer buffer
        (let ((inhibit-read-only t))
          (erase-buffer))))

    (with-current-buffer buffer
      (goto-char (point-max))
      (comint-send-string
       (get-buffer-process buffer)
       (concat "cd " (shell-quote-argument (expand-file-name dir))
               " && " command "\n")))

    (setq run-code-process (get-buffer-process buffer))))

;; =============================================================================
;; tmux
;; =============================================================================

(defun run-code--tmux-available-p ()
  (executable-find "tmux"))

(defun run-code--run-tmux (command)
  (unless (run-code--tmux-available-p)
    (user-error "tmux is not installed"))

  (when (and (not (getenv "TMUX"))
             (string-empty-p run-code-tmux-target))
    (user-error
     "Not running inside tmux (set run-code-tmux-target to use a session from outside)"))

  (let* ((target
          (unless (string-empty-p run-code-tmux-target)
            (list "-t" run-code-tmux-target)))
         (args
          (append
           (list
            "split-window"
            "-P"
            "-F"
            "#{pane_id}")
           target
           (list
            "-h"
            "-p" "50"
            "-c" default-directory)))
         (pane
          (with-temp-buffer
            (let ((status
                   (apply
                    #'call-process
                    "tmux"
                    nil
                    t
                    nil
                    args)))
              (unless (zerop status)
                (user-error
                 "tmux failed: %s"
                 (string-trim (buffer-string))))
              (string-trim (buffer-string))))))

    (let ((status
           (call-process
            "tmux"
            nil
            nil
            nil
            "send-keys"
            "-t"
            pane
            "-l"
            command)))
      (unless (zerop status)
        (user-error "tmux failed while sending command")))

    (let ((status
           (call-process
            "tmux"
            nil
            nil
            nil
            "send-keys"
            "-t"
            pane
            "Enter")))
      (unless (zerop status)
        (user-error "tmux failed while starting command")))))

;; =============================================================================
;; Public runner
;; =============================================================================

(defun run-code--run (mode backend)
  (when (and (eq backend 'tmux)
             (not run-code-tmux-enabled))
    (user-error "tmux execution is disabled"))

  (run-code--check-file)

  (let ((command (run-code--get-command mode)))
    (unless command
      (user-error
       "No %s command configured for filetype: %s"
       mode
       (run-code--filetype)))

    (let ((exec-command
           (run-code--build-exec-command command backend)))
      (when run-code-show-feedback
        (message
         "Running %s in %s..."
         (pcase mode
           ('dev "dev")
           ('opt "optimized")
           ('test "test")
           (_ (symbol-name mode)))
         (if (eq backend 'tmux)
             "tmux"
           "terminal")))

      (cond
       ((eq backend 'tmux)
        (run-code--run-tmux exec-command))

       (run-code-terminal-mode
        (run-code--run-terminal exec-command))

       (t
        (compile exec-command))))))

;; =============================================================================
;; Interactive commands
;; =============================================================================

;;;###autoload
(defun run-code-dev ()
  "Run the current file in development mode."
  (interactive)
  (run-code--run 'dev 'terminal))

;;;###autoload
(defun run-code-opt ()
  "Run the current file in optimized mode."
  (interactive)
  (run-code--run 'opt 'terminal))

;;;###autoload
(defun run-code-test ()
  "Run tests for the current file."
  (interactive)
  (run-code--run 'test 'terminal))

;;;###autoload
(defun run-code-tmux ()
  "Run the current file through tmux."
  (interactive)
  (run-code--run 'dev 'tmux))

;;;###autoload
(defun run-code-tmux-opt ()
  "Run the current file in optimized mode through tmux."
  (interactive)
  (run-code--run 'opt 'tmux))

;;;###autoload
(defun run-code-tmux-test ()
  "Run tests through tmux."
  (interactive)
  (run-code--run 'test 'tmux))

;; =============================================================================
;; User configuration
;; =============================================================================

;;;###autoload
(defun run-code-set (filetype command)
  "Set COMMAND for FILETYPE."
  (interactive
   (list
    (read-string "Filetype: ")
    (read-string "Command: ")))
  (setf (alist-get
         filetype
         run-code-commands
         nil
         nil
         #'equal)
        command))

;;;###autoload
(defun run-code-set-test (filetype command)
  "Set test COMMAND for FILETYPE."
  (interactive
   (list
    (read-string "Filetype: ")
    (read-string "Command: ")))
  (setf (alist-get
         filetype
         run-code-test-commands
         nil
         nil
         #'equal)
        command))

;; =============================================================================
;; Information
;; =============================================================================

;;;###autoload
(defun run-code-list ()
  "List supported filetypes."
  (interactive)
  (let (languages)
    (dolist (commands
             (list
              run-code-development-commands
              run-code-optimized-commands
              run-code-test-commands-default
              run-code-commands
              run-code-test-commands))
      (dolist (entry commands)
        (cl-pushnew
         (car entry)
         languages
         :test #'equal)))

    (setq languages (sort languages #'string<))

    (message
     "Supported filetypes: %s"
     (string-join languages ", "))))

;;;###autoload
(defun run-code-config ()
  "Display run-code configuration."
  (interactive)
  (message
   (concat
    "Run Code Config:\n"
    "  Auto-save: %s\n"
    "  Clear terminal: %s\n"
    "  Show feedback: %s\n"
    "  Timeout: %s\n"
    "  Temp dir: %s\n"
    "  Terminal mode: %s\n"
    "  Terminal position: %s\n"
    "  Terminal width: %s\n"
    "  Terminal height: %s\n"
    "  tmux enabled: %s\n"
    "  tmux target: %s")
   run-code-auto-save
   run-code-clear-terminal
   run-code-show-feedback
   run-code-timeout
   run-code-temp-dir
   run-code-terminal-mode
   run-code-terminal-position
   run-code-terminal-width
   run-code-terminal-height
   run-code-tmux-enabled
   (if (string-empty-p run-code-tmux-target)
       "<current pane>"
     run-code-tmux-target)))


;; =============================================================================
;; Keybindings
;; =============================================================================

(defvar run-code-mode-map (make-sparse-keymap)
  "Keymap for `run-code-mode`.")

(with-eval-after-load 'evil
  (evil-define-key 'normal run-code-mode-map
    (kbd "r") #'run-code-dev
    (kbd "R") #'run-code-opt
    (kbd "t") #'run-code-tmux
    (kbd "T") #'run-code-tmux-test))

;;;###autoload
(define-minor-mode run-code-mode
  "Minor mode for running source files."
  :lighter " RunCode"
  :keymap run-code-mode-map)

;;;###autoload
(define-minor-mode run-code-global-mode
  "Enable run-code-mode automatically for supported buffers."
  :global t
  :lighter ""
  (if run-code-global-mode
      (progn
        (add-hook 'after-change-major-mode-hook
                  #'run-code--enable)
        (run-code--enable))
    (remove-hook 'after-change-major-mode-hook
                 #'run-code--enable)))

(defun run-code--enable ()
  (when (and buffer-file-name
             (run-code--has-command-p
              (run-code--filetype)))
    (run-code-mode 1)))

(defun run-code-close ()
  "Close the *run-code* window."
  (interactive)
  (when-let ((win (get-buffer-window run-code-buffer-name)))
    (delete-window win)))

(defun run-code--auto-close (frame)
  "Close the *run-code* window when it loses focus."
  (let ((old (frame-old-selected-window frame))
        (new (frame-selected-window frame)))
    (when (and (window-live-p old)
               (not (eq old new))
               (not (window-minibuffer-p new))
               (equal (buffer-name (window-buffer old)) run-code-buffer-name))
      (delete-window old))))

(add-hook 'window-selection-change-functions #'run-code--auto-close)

(provide 'run-code)

;;; run-code.el ends here
