;;; betterlinear-drawers-test.el --- Drawer export tests -*- lexical-binding: t; -*-

(require 'ert)
(require 'cl-lib)
(require 'betterlinear)

(ert-deftest betterlinear-description-excludes-all-drawers ()
  (with-temp-buffer
    (org-mode)
    (insert "* Parent\nSCHEDULED: <2026-01-01 Thu>\n:PROPERTIES:\n:TEAM: ENG\n:END:\nIntro\n:LOGBOOK:\nPrivate log\n:END:\n:CUSTOM:\nPrivate note\n:END:\nMore text\n** Child\n:PROPERTIES:\n:SECRET: hidden\n:END:\nChild text\n:NOTES:\nPrivate child note\n:END:\n* Sibling\nUnrelated\n")
    (goto-char (point-min))
    (let ((original (buffer-string)))
      (cl-letf (((symbol-function 'betterlinear-org-to-markdown) #'identity))
        (should (equal (betterlinear--current-org-entry-description)
                       "Intro\nMore text\n* Child\nChild text")))
      (should (equal original (buffer-string))))))

(ert-deftest betterlinear-description-only-drawers-is-empty ()
  (with-temp-buffer
    (org-mode)
    (insert "* Parent\n:LOGBOOK:\nPrivate\n:END:\n")
    (goto-char (point-min))
    (should-not (betterlinear--current-org-entry-description))))

(ert-deftest betterlinear-drawer-removal-preserves-source-blocks ()
  (let ((body "Before\n#+begin_src text\n:NOTES:\nExample\n:END:\n#+end_src\nAfter\n"))
    (should (equal body (betterlinear--org-body-without-drawers body)))))

;;; betterlinear-drawers-test.el ends here
