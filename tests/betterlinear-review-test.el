;;; betterlinear-review-test.el --- Review regressions -*- lexical-binding: t; -*-
(require 'ert)
(require 'cl-lib)
(require 'betterlinear)

(ert-deftest betterlinear-drawer-parser-does-not-run-user-hooks ()
  (let ((org-mode-hook (list (lambda () (insert "HOOK")))))
    (should (equal "Body\n"
                   (betterlinear--org-body-without-drawers "Body\n")))))

(ert-deftest betterlinear-priority-values-and-custom-map ()
  (let ((betterlinear-priority-map '((1 . ?A) (2 . ?B) (3 . ?C) (4 . ?D))))
    (dolist (pair '((1 . ?A) ("2" . ?B) (3 . ?C) (4 . ?D)
                    (0) (nil) (:null) ("invalid") (5)))
      (should (eq (cdr pair)
                  (betterlinear--issue-org-priority
                   `((priority . ,(car pair)))))))
    (let ((betterlinear-priority-map '((2 . ?Z))))
      (should (eq ?Z (betterlinear--issue-org-priority '((priority . 2))))))))

(ert-deftest betterlinear-replacement-priority-precedence ()
  (dolist (case '((((priority . 2)) . ?B)
                  (((priority . 0)))
                  (((priority . nil)))
                  (nil . ?A)))
    (with-temp-buffer
      (org-mode)
      (insert "* TODO [#A] Local\n")
      (goto-char (point-min))
      (betterlinear--replace-current-entry-with-issue
       (append (car case) '((id . "test") (identifier . "ENG-1")
                            (title . "Remote") (url . "https://example.com/1"))))
      (should (eq (cdr case) (betterlinear--current-org-entry-priority))))))

(ert-deftest betterlinear-graphql-decodes-utf8-and-cleans-up ()
  (let ((response (generate-new-buffer " *linear-response-test*")))
    (unwind-protect
        (progn
          (with-current-buffer response
            (set-buffer-multibyte nil)
            (insert (encode-coding-string "{\"data\":{\"title\":\"Café 日本語 😀\"}}" 'utf-8))
            (setq-local url-http-response-status 200)
            (setq-local url-http-end-of-headers (point-min)))
          (cl-letf (((symbol-function 'betterlinear--api-key) (lambda () "test"))
                    ((symbol-function 'url-retrieve-synchronously)
                     (lambda (&rest _) response)))
            (should (equal "Café 日本語 😀"
                           (alist-get 'title (betterlinear--graphql "query {}")))))
          (should-not (buffer-live-p response)))
      (when (buffer-live-p response) (kill-buffer response)))))
