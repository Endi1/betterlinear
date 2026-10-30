;;; betterlinear-capture-sub-issue-test.el --- Sub-issue capture -*- lexical-binding: t; -*-
(require 'ert)
(require 'cl-lib)
(require 'betterlinear)

(defmacro betterlinear-capture-sub-test--with-source (&rest body)
  (declare (indent 0) (debug t))
  `(let ((source (generate-new-buffer " *sub-capture-source*")) capture)
     (unwind-protect
         (cl-letf (((symbol-function 'pop-to-buffer) (lambda (&rest _) nil))
                   ((symbol-function 'betterlinear--read-agenda-issue)
                    (lambda ()
                      (with-current-buffer source
                        (copy-marker (point-min) t))))
                   ((symbol-function 'betterlinear--state-id-for-todo-keyword)
                    (lambda (&rest _) "state")))
           (with-current-buffer source
             (org-mode)
             (insert "* Parent\n:PROPERTIES:\n:LINEAR_ID: p\n:LINEAR_IDENTIFIER: ENG-1\n:TEAM_ID: team\n:END:\nParent body\n** TODO Existing draft\nKeep this\n* Sibling\nKeep sibling\n")
             (goto-char (point-min)))
           ,@body)
       (when (buffer-live-p capture)
         (with-current-buffer capture (set-buffer-modified-p nil))
         (kill-buffer capture))
       (when (buffer-live-p source) (kill-buffer source)))))

(defun betterlinear-capture-sub-test--fill (capture)
  (with-current-buffer capture
    (betterlinear--goto-capture-heading)
    (end-of-line)
    (insert "New child")
    (goto-char (point-max))
    (insert "Child description\n** TODO Grandchild draft\nKeep nested draft\n")))

(defun betterlinear-capture-sub-test--created ()
  '((id . "c") (identifier . "ENG-2") (title . "New child")
    (state . ((name . "In Progress"))) (team . ((id . "team")))))

(ert-deftest betterlinear-capture-sub-issue-creates-and-inserts-beneath-original-parent ()
  (betterlinear-capture-sub-test--with-source
    (with-current-buffer source
      (setq buffer-read-only t)
      (setq capture (betterlinear-capture-sub-issue)))
    (should (with-current-buffer capture (derived-mode-p 'betterlinear-capture-mode)))
    (should (with-current-buffer capture (equal "team" betterlinear--capture-team-id)))
    (betterlinear-capture-sub-test--fill capture)
    (let (sent)
      (cl-letf (((symbol-function 'betterlinear-create-issue)
                 (lambda (&rest args)
                   (setq sent args)
                   (betterlinear-capture-sub-test--created))))
        (with-current-buffer capture (betterlinear-capture-finalize)))
      (should (equal "team" (nth 0 sent)))
      (should (equal "New child" (nth 1 sent)))
      (should (equal "p" (nth 4 sent)))
      (should (string-match-p "Child description" (nth 2 sent)))
      (should-not (string-match-p "Grandchild" (nth 2 sent))))
    (should-not (buffer-live-p capture))
    (with-current-buffer source
      (should buffer-read-only)
      (should (buffer-modified-p))
      (should (equal "c" (org-entry-get (point) "LINEAR_ID" nil)))
      (should (equal "p" (org-entry-get (point) "LINEAR_PARENT_ID" nil)))
      (should (= 2 (org-outline-level)))
      (dolist (text '("Parent body" "** TODO Existing draft\nKeep this"
                      "*** TODO Grandchild draft\nKeep nested draft"
                      "* Sibling\nKeep sibling"))
        (should (string-match-p (regexp-quote text) (buffer-string)))))))

(ert-deftest betterlinear-capture-sub-issue-abort-does-not-change-source ()
  (betterlinear-capture-sub-test--with-source
    (let ((original (with-current-buffer source (buffer-string))))
      (with-current-buffer source (setq capture (betterlinear-capture-sub-issue)))
      (let ((marker (with-current-buffer capture betterlinear--capture-parent-marker)))
        (betterlinear-capture-sub-test--fill capture)
        (cl-letf (((symbol-function 'betterlinear-create-issue)
                   (lambda (&rest _) (ert-fail "Abort must not create an issue"))))
          (with-current-buffer capture (betterlinear-capture-abort)))
        (should-not (marker-buffer marker)))
      (should-not (buffer-live-p capture))
      (should (equal original (with-current-buffer source (buffer-string)))))))

(ert-deftest betterlinear-capture-sub-issue-rejects-missing-source-before-creation ()
  (betterlinear-capture-sub-test--with-source
    (with-current-buffer source (setq capture (betterlinear-capture-sub-issue)))
    (betterlinear-capture-sub-test--fill capture)
    (kill-buffer source)
    (cl-letf (((symbol-function 'betterlinear-create-issue)
               (lambda (&rest _) (ert-fail "Must validate source before creation"))))
      (with-current-buffer capture
        (should-error (betterlinear-capture-finalize) :type 'user-error)))
    (should (buffer-live-p capture))))

(ert-deftest betterlinear-capture-sub-issue-network-failure-keeps-capture-and-source ()
  (betterlinear-capture-sub-test--with-source
    (let ((original (with-current-buffer source (buffer-string))))
      (with-current-buffer source (setq capture (betterlinear-capture-sub-issue)))
      (betterlinear-capture-sub-test--fill capture)
      (cl-letf (((symbol-function 'betterlinear-create-issue)
                 (lambda (&rest _) (error "Network failure"))))
        (with-current-buffer capture (should-error (betterlinear-capture-finalize))))
      (should (buffer-live-p capture))
      (should (equal original (with-current-buffer source (buffer-string)))))))

(ert-deftest betterlinear-capture-sub-issue-local-insertion-retry-does-not-create-twice ()
  (betterlinear-capture-sub-test--with-source
    (with-current-buffer source (setq capture (betterlinear-capture-sub-issue)))
    (betterlinear-capture-sub-test--fill capture)
    (let ((calls 0) (original (with-current-buffer source (buffer-string))))
      (cl-letf (((symbol-function 'betterlinear-create-issue)
                 (lambda (&rest _)
                   (cl-incf calls)
                   (betterlinear-capture-sub-test--created))))
        (cl-letf (((symbol-function 'betterlinear--insert-issue)
                   (lambda (&rest _) (error "Render failed"))))
          (with-current-buffer capture (should-error (betterlinear-capture-finalize))))
        (should (equal original (with-current-buffer source (buffer-string))))
        (should (with-current-buffer capture betterlinear--capture-created-sub-issue))
        (with-current-buffer capture (betterlinear-capture-finalize)))
      (should (= 1 calls)))))

(ert-deftest betterlinear-capture-sub-issue-changed-parent-is-rejected-before-creation ()
  (betterlinear-capture-sub-test--with-source
    (with-current-buffer source (setq capture (betterlinear-capture-sub-issue)))
    (betterlinear-capture-sub-test--fill capture)
    (with-current-buffer source
      (goto-char (point-min))
      (org-entry-put (point) "LINEAR_ID" "different-parent"))
    (cl-letf (((symbol-function 'betterlinear-create-issue)
               (lambda (&rest _) (ert-fail "Must not attach to a different parent"))))
      (with-current-buffer capture
        (should-error (betterlinear-capture-finalize) :type 'user-error)))
    (should (buffer-live-p capture))))

(ert-deftest betterlinear-capture-sub-issue-resolves-parent-team-when-not-stored-locally ()
  (betterlinear-capture-sub-test--with-source
    (with-current-buffer source
      (goto-char (point-min))
      (org-entry-delete (point) "TEAM_ID")
      (cl-letf (((symbol-function 'betterlinear-issue)
                 (lambda (id)
                   (should (equal "p" id))
                   '((id . "p") (team . ((id . "remote-team")))))))
        (setq capture (betterlinear-capture-sub-issue))))
    (with-current-buffer capture
      (should (equal "remote-team" betterlinear--capture-team-id))
      (betterlinear--goto-capture-heading)
      (should (equal "remote-team" (org-entry-get (point) "TEAM_ID" nil))))))

(ert-deftest betterlinear-capture-sub-issue-requires-agenda-linear-entry ()
  (let ((org-agenda-files nil))
    (with-temp-buffer
      (should-error (betterlinear-capture-sub-issue) :type 'user-error)
      (org-mode)
      (insert "* TODO Local draft\n")
      (goto-char (point-min))
      (should-error (betterlinear-capture-sub-issue) :type 'user-error))))
