;;; betterlinear-agenda-capture-test.el --- Agenda parent selection -*- lexical-binding: t; -*-
(require 'ert)
(require 'cl-lib)
(require 'betterlinear)

(defmacro betterlinear-agenda-test--with-files (&rest body)
  (declare (indent 0) (debug t))
  `(let* ((directory (make-temp-file "betterlinear-agenda-" t))
          (first-file (expand-file-name "first.org" directory))
          (second-file (expand-file-name "second.org" directory))
          (other-file (expand-file-name "outside.org" directory))
          (org-agenda-files (list first-file second-file)))
     (unwind-protect
         (progn
           (with-temp-file first-file
             (insert "* TODO First\n:PROPERTIES:\n:LINEAR_ID: first\n:LINEAR_IDENTIFIER: ENG-1\n:TEAM_ID: first-team\n:END:\n** Ordinary notes\nNot another issue\n** TODO Local draft\n* DONE Same title\n:PROPERTIES:\n:LINEAR_ID: duplicate-title\n:END:\n"))
           (with-temp-file second-file
             (insert "* Chosen\n:PROPERTIES:\n:LINEAR_ID: selected\n:LINEAR_IDENTIFIER: ENG-2\n:TEAM_ID: selected-team\n:END:\n* Same title\n:PROPERTIES:\n:LINEAR_ID: other-title\n:END:\n"))
           (with-temp-file other-file
             (insert "* Not in agenda\n:PROPERTIES:\n:LINEAR_ID: outside\n:END:\n"))
           ,@body)
       (dolist (file (list first-file second-file other-file))
         (when-let* ((buffer (get-file-buffer file)))
           (with-current-buffer buffer (set-buffer-modified-p nil))
           (kill-buffer buffer)))
       (delete-directory directory t))))

(ert-deftest betterlinear-agenda-candidates-only-own-ids-and-use-live-buffer-content ()
  (betterlinear-agenda-test--with-files
    (let ((buffer (find-file-noselect first-file)) candidates)
      (find-file-noselect other-file)
      (with-current-buffer buffer
        (goto-char (point-min))
        (end-of-line)
        (insert " unsaved edit")
        (org-narrow-to-subtree)
        (let ((position (point))
              (org-use-property-inheritance t))
          (setq candidates (betterlinear--agenda-issue-candidates))
          (should (= position (point)))
          (should (buffer-narrowed-p))))
      (unwind-protect
          (progn
            (should (= 4 (length candidates)))
            (should (string-match-p "ENG-1 — First unsaved edit" (caar candidates)))
            (should (string-match-p "first.org:1" (caar candidates)))
            (should-not (seq-find (lambda (c) (string-match-p "outside.org" (car c))) candidates))
            (should (= 2 (length (seq-filter (lambda (c) (string-match-p "Same title" (car c))) candidates)))))
        (dolist (candidate candidates) (set-marker (cdr candidate) nil))))))

(ert-deftest betterlinear-agenda-capture-prompts-from-any-buffer-and-inserts-in-selected-file ()
  (betterlinear-agenda-test--with-files
    (let (capture sent prompted)
      (unwind-protect
          (cl-letf (((symbol-function 'completing-read)
                     (lambda (prompt candidates &rest _)
                       (setq prompted prompt)
                       (car (seq-find (lambda (c) (string-match-p "ENG-2 — Chosen" (car c))) candidates))))
                    ((symbol-function 'pop-to-buffer) (lambda (&rest _) nil))
                    ((symbol-function 'betterlinear--state-id-for-todo-keyword) (lambda (&rest _) nil))
                    ((symbol-function 'betterlinear-create-issue)
                     (lambda (&rest args)
                       (setq sent args)
                       '((id . "new-child") (title . "Captured child") (state . ((name . "Todo")))))))
            (with-temp-buffer
              (fundamental-mode)
              (call-interactively #'betterlinear-capture-sub-issue)
              ;; Find the live capture through its source-bound parent metadata.
              (setq capture (seq-find
                             (lambda (buffer)
                               (with-current-buffer buffer
                                 (equal "selected" (alist-get 'id betterlinear--capture-parent-issue))))
                             (buffer-list))))
            (should (equal "Parent Linear issue: " prompted))
            (should (buffer-live-p capture))
            (with-current-buffer capture
              (betterlinear--goto-capture-heading)
              (end-of-line)
              (insert "Captured child")
              (betterlinear-capture-finalize))
            (should (equal "selected-team" (nth 0 sent)))
            (should (equal "selected" (nth 4 sent)))
            (with-current-buffer (find-file-noselect second-file)
              (should (string-match-p "LINEAR_ID: new-child" (buffer-string)))
              (should (string-match-p "LINEAR_PARENT_ID: selected" (buffer-string)))))
        (when (buffer-live-p capture)
          (with-current-buffer capture (set-buffer-modified-p nil))
          (kill-buffer capture))))))

(ert-deftest betterlinear-agenda-parent-selection-releases-markers-on-cancel ()
  (betterlinear-agenda-test--with-files
    (let (candidates cancelled)
      (cl-letf (((symbol-function 'completing-read)
                 (lambda (_prompt collection &rest _)
                   (setq candidates collection)
                   (signal 'quit nil))))
        (condition-case nil
            (betterlinear--read-agenda-issue)
          (quit (setq cancelled t))))
      (should cancelled)
      (should candidates)
      (dolist (candidate candidates)
        (should-not (marker-buffer (cdr candidate)))))))
