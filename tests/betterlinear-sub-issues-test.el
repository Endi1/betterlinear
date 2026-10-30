;;; betterlinear-sub-issues-test.el --- Sub-issue regression tests -*- lexical-binding: t; -*-

(require 'ert)
(require 'cl-lib)
(require 'betterlinear)

(defmacro betterlinear-sub-test--with-org (text &rest body)
  "Evaluate BODY in an Org buffer containing TEXT, without Pandoc."
  (declare (indent 1) (debug t))
  `(with-temp-buffer
     ;; Org rebuilds keyword regexps from the default value when no #+TODO
     ;; header exists.  Restore that source explicitly rather than dynamically
     ;; let-binding a variable which production code makes buffer-local.
     (let ((saved-keywords (default-value 'org-todo-keywords)))
       (unwind-protect
           (progn
             (set-default 'org-todo-keywords
                          '((sequence "TODO" "WAIT" "|" "DONE")))
             (org-mode)
             (insert ,text)
             (goto-char (point-min))
             (cl-letf (((symbol-function 'betterlinear-org-to-markdown) #'identity)
                       ((symbol-function 'betterlinear-markdown-to-org) #'identity))
               ,@body))
         (set-default 'org-todo-keywords saved-keywords)))))

(defun betterlinear-sub-test--issue (id &optional parent)
  "Return a small issue fixture with ID and optional PARENT id."
  `((id . ,id) (identifier . ,(concat "ENG-" id))
    (title . ,(concat "Issue " id))
    (url . ,(concat "https://linear.example/" id))
    (team . ((id . "team") (key . "ENG")))
    (state . ((id . "todo-state") (name . "Todo")))
    ,@(when parent
        `((parent . ((id . ,parent)
                     (url . ,(concat "https://linear.example/" parent))))))))

(defun betterlinear-sub-test--outline ()
  "Return (ID LEVEL) pairs for all local issue properties in buffer order."
  (save-excursion
    (goto-char (point-min))
    (let (entries)
      (while (re-search-forward org-heading-regexp nil t)
        (beginning-of-line)
        (when-let ((id (org-entry-get (point) "LINEAR_ID" nil)))
          (push (list id (org-outline-level)) entries))
        (forward-line 1))
      (nreverse entries))))

(ert-deftest betterlinear-sub-description-skips-issues-and-all-todo-subtrees ()
  (betterlinear-sub-test--with-org
      "* Parent\n:PROPERTIES:\n:LINEAR_ID: parent\n:END:\nParent body\n** Notes before\nKeep before\n** Existing\n:PROPERTIES:\n:LINEAR_ID: child\n:END:\nHidden existing body\n*** Ordinary inside issue\nHidden nested body\n** TODO Draft\nHidden draft body\n*** Ordinary inside draft\nHidden draft nested body\n** DONE Finished draft\nHidden done body\n** WAIT Waiting draft\nHidden waiting body\n** Notes after\nKeep after\n*** Detail\nKeep detail\n* Outside\nOutside body\n"
    ;; Inherited LINEAR_ID must not turn ordinary children into issues.
    (let* ((org-use-property-inheritance t)
           (original (buffer-string))
           (description (betterlinear--current-org-entry-description)))
      (dolist (text '("Parent body" "* Notes before" "Keep before"
                      "* Notes after" "Keep after" "** Detail" "Keep detail"))
        (should (string-match-p (regexp-quote text) description)))
      (dolist (text '("Hidden" "Existing" "Draft" "Finished draft"
                      "Waiting draft" "Outside" "LINEAR_ID"))
        (should-not (string-match-p (regexp-quote text) description)))
      (should (equal original (buffer-string))))))

(ert-deftest betterlinear-sub-description-only-subissues-is-empty ()
  (betterlinear-sub-test--with-org
      "* Parent\nSCHEDULED: <2026-06-01 Mon>\n:PROPERTIES:\n:LINEAR_ID: parent\n:END:\n** TODO Draft\nDraft body\n** Child\n:PROPERTIES:\n:LINEAR_ID: child\n:END:\nChild body\n"
    (should-not (betterlinear--current-org-entry-description))))

(ert-deftest betterlinear-sub-description-normalizes-relative-to-current-entry ()
  (betterlinear-sub-test--with-org
      "* Outer\n** Parent\nBody\n*** Notes\nKeep\n*** TODO Draft\nHidden\n*** Later notes\nKeep later\n"
    (search-forward "** Parent")
    (let ((description (betterlinear--current-org-entry-description)))
      (should (string-match-p "^\\* Notes$" description))
      (should (string-match-p "^\\* Later notes$" description))
      (should-not (string-match-p "Hidden" description)))))

(ert-deftest betterlinear-sub-replacement-preserves-protected-descendants ()
  (let ((child "*** Existing child\nDEADLINE: <2026-06-03 Wed>\n:PROPERTIES:\n:LINEAR_ID: child\n:END:\nChild local text\n**** Notes\nChild notes\n")
        (draft "*** DONE Draft\nCLOSED: [2026-06-02 Tue]\nDraft local text\n**** TODO Nested draft\nNested text\n"))
    (betterlinear-sub-test--with-org
        (concat "* Outer\n** Old parent\nSCHEDULED: <2026-06-01 Mon>\n:PROPERTIES:\n:LINEAR_ID: parent\n:END:\nOld parent body\n*** Old description heading\nOld description text\n"
                child draft "*** Ordinary tail\nOld tail\n* Sibling\nKeep sibling\n")
      (search-forward "** Old parent")
      (betterlinear--replace-current-entry-with-issue
       (append (betterlinear-sub-test--issue "parent")
               '((description . "Fresh parent body"))))
      (let ((text (buffer-string)))
        (dolist (preserved (list child draft "SCHEDULED: <2026-06-01 Mon>"
                                "* Sibling\nKeep sibling" "Fresh parent body"))
          (should (string-match-p (regexp-quote preserved) text)))
        (dolist (removed '("Old parent body" "Old description heading"
                           "Old description text" "Old tail"))
          (should-not (string-match-p (regexp-quote removed) text)))
        (should (equal '(("parent" 2) ("child" 3))
                       (betterlinear-sub-test--outline)))))))

(ert-deftest betterlinear-sub-properties-record-parent-id-and-url ()
  (betterlinear-sub-test--with-org "* Child\n"
    (goto-char (point-max))
    (betterlinear--insert-issue-properties (betterlinear-sub-test--issue "c" "p"))
    (goto-char (point-min))
    (should (equal "p" (org-entry-get nil "LINEAR_PARENT_ID")))
    (should (equal "https://linear.example/p"
                   (org-entry-get nil "LINEAR_PARENT_URL")))))

(ert-deftest betterlinear-sub-render-flat-input-as-stable-deduplicated-tree ()
  (betterlinear-sub-test--with-org ""
    ;; Child precedes parent; duplicate child is non-adjacent.  Only parent.id
    ;; determines nesting, and a missing parent must not discard an issue.
    (betterlinear--insert-my-issues-org
     (list (betterlinear-sub-test--issue "c2" "p")
           (betterlinear-sub-test--issue "orphan" "absent")
           (betterlinear-sub-test--issue "p")
           (betterlinear-sub-test--issue "c1" "p")
           (betterlinear-sub-test--issue "grand" "c2")
           (betterlinear-sub-test--issue "c2" "p")
           (betterlinear-sub-test--issue "last")))
    (should (equal '(("orphan" 1) ("p" 1) ("c2" 2) ("grand" 3)
                     ("c1" 2) ("last" 1))
                   (betterlinear-sub-test--outline)))))

(ert-deftest betterlinear-sub-render-parent-url-alone-does-not-nest ()
  (betterlinear-sub-test--with-org ""
    (betterlinear--insert-my-issues-org
     (list (betterlinear-sub-test--issue "p")
           (append (betterlinear-sub-test--issue "c")
                   '((parent . ((url . "https://linear.example/p")))))))
    (should (equal '(("p" 1) ("c" 1))
                   (betterlinear-sub-test--outline)))))

(ert-deftest betterlinear-sub-create-api-sends-parent-id ()
  (let (sent)
    (cl-letf (((symbol-function 'betterlinear--graphql)
               (lambda (_query variables)
                 (setq sent variables)
                 `((issueCreate . ((success . t)
                                    (issue . ,(betterlinear-sub-test--issue "c" "p"))))))))
      (should (equal "c" (alist-get 'id
                                   (betterlinear-create-issue
                                    "team" "Title" "Body" "state" "p"))))
      (should (equal "p" (alist-get 'parentId sent)))
      (should (equal "team" (alist-get 'teamId sent)))
      (should (equal "state" (alist-get 'stateId sent))))))

(ert-deftest betterlinear-sub-create-api-old-call-omits-parent-id ()
  (let (sent)
    (cl-letf (((symbol-function 'betterlinear--graphql)
               (lambda (_query variables)
                 (setq sent variables)
                 `((issueCreate . ((success . t)
                                    (issue . ,(betterlinear-sub-test--issue "c"))))))))
      (betterlinear-create-issue "team" "Title" "Body")
      (should-not (assq 'parentId sent)))))

(ert-deftest betterlinear-sub-create-command-uses-nearest-parent-and-preserves-drafts ()
  (betterlinear-sub-test--with-org
      "* Outer\n:PROPERTIES:\n:LINEAR_ID: outer\n:TEAM_ID: outer-team\n:END:\n** Parent\n:PROPERTIES:\n:LINEAR_ID: parent\n:TEAM_ID: team\n:END:\n*** Notes\nOrdinary wrapper\n**** TODO Selected\nSCHEDULED: <2026-06-01 Mon>\nSelected body\n***** Notes\nKeep in description\n***** TODO Descendant draft\nDo not send\n**** TODO Sibling\nUntouched\n"
    (search-forward "**** TODO Selected")
    (let (created state-request)
      (cl-letf (((symbol-function 'betterlinear--state-id-for-todo-keyword)
                 (lambda (team keyword)
                   (setq state-request (list team keyword)) "todo-state"))
                ((symbol-function 'betterlinear-create-issue)
                 (lambda (&rest args)
                   (setq created args)
                   (betterlinear-sub-test--issue "created" "parent"))))
        (call-interactively #'betterlinear-create-sub-issue-from-org-entry))
      (should (equal '("team" "TODO") state-request))
      (should (equal "team" (nth 0 created)))
      (should (equal "Selected" (nth 1 created)))
      (should (equal "todo-state" (nth 3 created)))
      (should (equal "parent" (nth 4 created)))
      (should (string-match-p "Selected body" (nth 2 created)))
      (should (string-match-p "Keep in description" (nth 2 created)))
      (should-not (string-match-p "Do not send" (nth 2 created)))
      (should-not (string-match-p "SCHEDULED" (nth 2 created)))
      (should (string-match-p
               (regexp-quote "***** TODO Descendant draft\nDo not send")
               (buffer-string)))
      (should (string-match-p (regexp-quote "**** TODO Sibling\nUntouched")
                              (buffer-string)))
      (should (equal '(("outer" 1) ("parent" 2) ("created" 4))
                     (betterlinear-sub-test--outline))))))

(ert-deftest betterlinear-sub-create-command-rejects-existing-or-unlinked-parent ()
  (dolist (text '("* TODO No parent\nBody\n"
                  "* Parent\n:PROPERTIES:\n:LINEAR_ID: p\n:TEAM_ID: team\n:END:\n** TODO Draft parent\n*** TODO Selected\n"
                  "* Parent\n:PROPERTIES:\n:LINEAR_ID: p\n:TEAM_ID: team\n:END:\n** DONE Draft parent\n*** TODO Selected\n"
                  "* Parent\n:PROPERTIES:\n:LINEAR_ID: p\n:TEAM_ID: team\n:END:\n** Selected\n:PROPERTIES:\n:LINEAR_ID: existing\n:END:\n"))
    (betterlinear-sub-test--with-org text
      (goto-char (point-max))
      (org-back-to-heading t)
      (let ((original (buffer-string)))
        (cl-letf (((symbol-function 'betterlinear-create-issue)
                   (lambda (&rest _) (ert-fail "Must reject before creating"))))
          (should-error (call-interactively #'betterlinear-create-sub-issue-from-org-entry)
                        :type 'user-error))
        (should (equal original (buffer-string)))))))

(ert-deftest betterlinear-sub-add-draft-is-child-of-existing-issue ()
  (betterlinear-sub-test--with-org
      "* Parent\n:PROPERTIES:\n:LINEAR_ID: p\n:TEAM_ID: team\n:END:\nParent body\n** Existing\n:PROPERTIES:\n:LINEAR_ID: c\n:END:\nChild body\n* Sibling\nKeep\n"
    (cl-letf (((symbol-function 'read-string) (lambda (&rest _) "New draft")))
      (call-interactively #'betterlinear-add-sub-issue))
    (should (equal "TODO" (org-get-todo-state)))
    (should (= 2 (org-outline-level)))
    (should-not (org-entry-get nil "LINEAR_ID" nil))
    (save-excursion
      (should (org-up-heading-safe))
      (should (equal "p" (org-entry-get nil "LINEAR_ID" nil))))
    (should (equal '(("p" 1) ("c" 2)) (betterlinear-sub-test--outline)))
    (should (string-match-p (regexp-quote ":LINEAR_ID: c\n:END:\nChild body\n")
                            (buffer-string)))
    (should (string-match-p "^\\* Sibling\nKeep" (buffer-string)))))

(ert-deftest betterlinear-sub-replacement-finds-protected-entries-under-description-headings ()
  (betterlinear-sub-test--with-org
      "* Parent\n:PROPERTIES:\n:LINEAR_ID: p\n:END:\n** Description section\nDiscard this\n*** WAIT Nested draft\nDEADLINE: <2026-06-03 Wed>\nKeep draft\n*** Remote nested child\n:PROPERTIES:\n:LINEAR_ID: c\n:END:\nKeep child\n** Tail section\nDiscard tail\n"
    (betterlinear--replace-current-entry-with-issue
     (betterlinear-sub-test--issue "p"))
    (should (equal '(("p" 1) ("c" 3)) (betterlinear-sub-test--outline)))
    (should (string-match-p
             (regexp-quote "*** WAIT Nested draft\nDEADLINE: <2026-06-03 Wed>\nKeep draft")
             (buffer-string)))
    (should-not (string-match-p "Discard" (buffer-string)))))

(ert-deftest betterlinear-sub-add-draft-requires-existing-linear-issue ()
  (betterlinear-sub-test--with-org "* TODO Unlinked draft\nBody\n"
    (let ((original (buffer-string)))
      (cl-letf (((symbol-function 'read-string) (lambda (&rest _) "Child")))
        (should-error (call-interactively #'betterlinear-add-sub-issue)
                      :type 'user-error))
      (should (equal original (buffer-string))))))

(ert-deftest betterlinear-sub-create-command-does-not-inherit-current-linear-id ()
  (betterlinear-sub-test--with-org
      "* Parent\n:PROPERTIES:\n:LINEAR_ID: p\n:TEAM_ID: team\n:END:\n** TODO Selected\nBody\n"
    (search-forward "** TODO Selected")
    (let ((org-use-property-inheritance t) created)
      (cl-letf (((symbol-function 'betterlinear--state-id-for-todo-keyword)
                 (lambda (&rest _) nil))
                ((symbol-function 'betterlinear-create-issue)
                 (lambda (&rest args)
                   (setq created args)
                   (betterlinear-sub-test--issue "created" "p"))))
        (call-interactively #'betterlinear-create-sub-issue-from-org-entry))
      (should (equal "p" (nth 4 created)))
      (should (equal '(("p" 1) ("created" 2))
                     (betterlinear-sub-test--outline))))))

(ert-deftest betterlinear-sub-description-keeps-source-block-fake-issue-metadata ()
  (betterlinear-sub-test--with-org
      "* Parent\nBody\n#+begin_src org\n,** TODO Example draft\n:PROPERTIES:\n:LINEAR_ID: example-only\n:END:\nExample body\n#+end_src\n** TODO Real draft\nDo not send\n** Later notes\nKeep later\n"
    ;; Org requires a comma escape for literal headings in source blocks.
    ;; The drawer-looking text is source content, not issue metadata.
    (let ((description (betterlinear--current-org-entry-description)))
      (dolist (expected '("Example draft" "Example body" "example-only"
                          "#+end_src" "Keep later"))
        (should (string-match-p (regexp-quote expected) description)))
      (should-not (string-match-p "Do not send" description)))))

(ert-deftest betterlinear-sub-add-draft-adds-missing-keyword-header-at-parent-point-min ()
  (betterlinear-sub-test--with-org
      "* Parent\n:PROPERTIES:\n:LINEAR_ID: p\n:TEAM_ID: team\n:END:\nParent body\n* Sibling\nKeep sibling\n"
    ;; Configure the real keyword source, not only Org's derived keyword list:
    ;; moving to a heading may cause Org to recompute its cached regexps.
    ;; Org derives these regexps from the default value.  The fixture restores
    ;; this source after the test, including on failure.
    (set-default 'org-todo-keywords '((sequence "WAIT" "|" "DONE")))
    (org-set-regexps-and-options)
    (should-not (member "TODO" org-todo-keywords-1))
    (goto-char (point-min))
    (call-interactively #'betterlinear-add-sub-issue)
    (should (equal "TODO" (org-get-todo-state)))
    (should (= 2 (org-outline-level)))
    (save-excursion
      (should (org-up-heading-safe))
      (should (equal "p" (org-entry-get nil "LINEAR_ID" nil))))
    (should (string-match-p "^#\\+TODO: .*TODO" (buffer-string)))
    (should (string-match-p "^\\* Sibling\nKeep sibling" (buffer-string)))
    (should (equal '(("p" 1)) (betterlinear-sub-test--outline)))))

(provide 'betterlinear-sub-issues-test)
;;; betterlinear-sub-issues-test.el ends here
