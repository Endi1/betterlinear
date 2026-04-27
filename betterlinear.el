;;; betterlinear.el --- Talk to Linear from Emacs -*- lexical-binding: t; -*-

;; Copyright (C) 2026

;; Author: betterlinear contributors
;; Version: 0.1.0
;; Package-Requires: ((emacs "27.1") (org "9.0"))
;; Keywords: tools, projectmanagement
;; URL: https://github.com/esukaj/betterlinear

;;; Commentary:

;; Utilities for viewing Linear issues in Emacs.
;;
;; Set `betterlinear-api-key' or the LINEAR_API_KEY environment variable, then run:
;;
;;   M-x betterlinear-my-issues-org

;;; Code:

(require 'json)
(require 'org)
(require 'seq)
(require 'subr-x)
(require 'url)
(require 'url-http)

(defgroup betterlinear nil
  "Talk to Linear from Emacs."
  :group 'tools
  :prefix "betterlinear-")

(defcustom betterlinear-api-key nil
  "Linear API key.

If nil, `betterlinear-api-key' falls back to the LINEAR_API_KEY environment
variable. Create an API key in Linear under Settings > API."
  :type '(choice (const :tag "Use LINEAR_API_KEY environment variable" nil)
                 (string :tag "API key"))
  :group 'betterlinear)

(defcustom betterlinear-api-url "https://api.linear.app/graphql"
  "Linear GraphQL API URL."
  :type 'string
  :group 'betterlinear)

(defcustom betterlinear-my-issues-buffer-name "*Linear My Issues*"
  "Name of the Org buffer used by `betterlinear-my-issues-org'."
  :type 'string
  :group 'betterlinear)

(defcustom betterlinear-issues-page-size 100
  "Number of issues to request per Linear API page."
  :type 'integer
  :group 'betterlinear)

(defcustom betterlinear-branch-name-format "%i-%t"
  "Fallback git branch format when Linear does not return `branchName'.

Linear's API can return nil for `branchName' even though the UI can generate a
branch name. In that case BetterLinear generates one from this format.
Supported placeholders:

  %i  lower-case issue identifier, e.g. eng-123
  %I  original issue identifier, e.g. ENG-123
  %t  slugified issue title, e.g. fix-login"
  :type 'string
  :group 'betterlinear)

(defcustom betterlinear-pandoc-command "pandoc"
  "Pandoc executable used for Markdown/Org conversion.

When this executable is available, BetterLinear uses it to convert Linear
Markdown descriptions to Org and Org entry bodies back to Markdown. When it is
not available, BetterLinear falls back to a small built-in converter."
  :type 'string
  :group 'betterlinear)

(defcustom betterlinear-use-pandoc t
  "Whether to use Pandoc for Markdown/Org conversion when available."
  :type 'boolean
  :group 'betterlinear)

(defvar url-http-end-of-headers)
(defvar url-http-response-status)

(defvar betterlinear--my-issues-query
  "query BetterLinearMyIssues($first: Int!, $after: String) {
     viewer {
       id
       name
       assignedIssues(first: $first, after: $after) {
         nodes {
           id
           identifier
           title
           description
           descriptionState
           url
           branchName
           priority
           priorityLabel
           estimate
           createdAt
           updatedAt
           dueDate
           assignee { id name }
           team { id key name }
           state { id name type }
           project { id name url }
         }
         pageInfo { hasNextPage endCursor }
       }
     }
   }")

(defvar betterlinear--issue-query
  "query BetterLinearIssue($id: String!) {
     issue(id: $id) {
       id
       identifier
       title
       description
       descriptionState
       url
       branchName
       priority
       priorityLabel
       estimate
       createdAt
       updatedAt
       dueDate
       assignee { id name }
       team { id key name }
       state { id name type }
       project { id name url }
     }
   }")

(defvar betterlinear--issue-states-query
  "query BetterLinearIssueStates($id: String!) {
     issue(id: $id) {
       id
       identifier
       state { id name type }
       team {
         id
         name
         states {
           nodes { id name type }
         }
       }
     }
   }")

(defvar betterlinear--viewer-query
  "query BetterLinearViewer {
     viewer { id name }
   }")

(defvar betterlinear--projects-query
  "query BetterLinearProjects($first: Int!, $after: String) {
     projects(first: $first, after: $after) {
       nodes { id name url }
       pageInfo { hasNextPage endCursor }
     }
   }")

(defvar betterlinear--set-issue-project-mutation
  "mutation BetterLinearSetIssueProject($id: String!, $projectId: String!) {
     issueUpdate(id: $id, input: { projectId: $projectId }) {
       success
       issue {
         id
         identifier
         title
         description
         descriptionState
         url
         branchName
         priority
         priorityLabel
         estimate
         createdAt
         updatedAt
         dueDate
         assignee { id name }
         team { id key name }
         state { id name type }
         project { id name url }
       }
     }
   }")

(defvar betterlinear--set-issue-assignee-mutation
  "mutation BetterLinearSetIssueAssignee($id: String!, $assigneeId: String!) {
     issueUpdate(id: $id, input: { assigneeId: $assigneeId }) {
       success
       issue {
         id
         identifier
         title
         description
         descriptionState
         url
         branchName
         priority
         priorityLabel
         estimate
         createdAt
         updatedAt
         dueDate
         assignee { id name }
         team { id key name }
         state { id name type }
         project { id name url }
       }
     }
   }")

(defvar betterlinear--teams-query
  "query BetterLinearTeams {
     teams {
       nodes { id key name }
     }
   }")

(defvar betterlinear--create-issue-mutation
  "mutation BetterLinearCreateIssue($teamId: String!, $title: String!, $description: String) {
     issueCreate(input: { teamId: $teamId, title: $title, description: $description }) {
       success
       issue {
         id
         identifier
         title
         description
         descriptionState
         url
         branchName
         priority
         priorityLabel
         estimate
         createdAt
         updatedAt
         dueDate
         assignee { id name }
         team { id key name }
         state { id name type }
         project { id name url }
       }
     }
   }")

(defvar betterlinear--set-issue-state-mutation
  "mutation BetterLinearSetIssueState($id: String!, $stateId: String!) {
     issueUpdate(id: $id, input: { stateId: $stateId }) {
       success
       issue {
         id
         identifier
         updatedAt
         state { id name type }
       }
     }
   }")

(define-derived-mode betterlinear-org-mode org-mode "BetterLinear"
  "Major mode for Org buffers generated by BetterLinear."
  (setq-local revert-buffer-function #'betterlinear--revert-my-issues-buffer))

(defun betterlinear--api-key ()
  "Return the configured Linear API key, or signal an error."
  (let ((api-key (or betterlinear-api-key (getenv "LINEAR_API_KEY"))))
    (unless (and api-key (not (string-empty-p api-key)))
      (user-error "Set `betterlinear-api-key' or the LINEAR_API_KEY environment variable"))
    api-key))

(defun betterlinear--graphql (query &optional variables)
  "Run Linear GraphQL QUERY with VARIABLES and return the `data' alist."
  (let* ((url-request-method "POST")
         (url-request-extra-headers `(("Content-Type" . "application/json")
                                      ("Authorization" . ,(betterlinear--api-key))))
         (url-request-data
          (json-encode `((query . ,query)
                         (variables . ,(or variables '())))))
         (buffer (url-retrieve-synchronously betterlinear-api-url t t 30)))
    (unless buffer
      (error "Linear API request timed out"))
    (unwind-protect
        (with-current-buffer buffer
          (unless (and (boundp 'url-http-response-status) url-http-response-status)
            (error "No HTTP response from Linear API"))
          (unless (<= 200 url-http-response-status 299)
            (let ((body (buffer-substring-no-properties
                         (or url-http-end-of-headers (point-min))
                         (point-max))))
              (error "Linear API HTTP %s: %s" url-http-response-status (string-trim body))))
          (goto-char (or url-http-end-of-headers (point-min)))
          (let* ((json-object-type 'alist)
                 (json-array-type 'list)
                 (json-key-type 'symbol)
                 (response (json-read))
                 (errors (alist-get 'errors response))
                 (data (alist-get 'data response)))
            (when errors
              (error "Linear API error: %s"
                     (mapconcat (lambda (err)
                                  (or (alist-get 'message err) (format "%S" err)))
                                errors
                                "; ")))
            data))
      (kill-buffer buffer))))

(defun betterlinear--assigned-issues-page (&optional after)
  "Return one page of issues assigned to the Linear viewer after cursor AFTER."
  (let* ((variables `((first . ,betterlinear-issues-page-size)
                      (after . ,after)))
         (data (betterlinear--graphql betterlinear--my-issues-query variables))
         (viewer (alist-get 'viewer data))
         (connection (alist-get 'assignedIssues viewer)))
    (list :viewer viewer
          :nodes (alist-get 'nodes connection)
          :page-info (alist-get 'pageInfo connection))))

(defun betterlinear-my-issues ()
  "Return all Linear issues assigned to the authenticated user as a list.

This follows Linear pagination until all assigned issues have been retrieved."
  (let (after issues viewer has-next)
    (setq has-next t)
    (while has-next
      (let* ((page (betterlinear--assigned-issues-page after))
             (page-viewer (plist-get page :viewer))
             (nodes (plist-get page :nodes))
             (page-info (plist-get page :page-info)))
        (unless viewer
          (setq viewer page-viewer))
        (setq issues (nconc issues nodes))
        (setq has-next (eq (alist-get 'hasNextPage page-info) t))
        (setq after (alist-get 'endCursor page-info))))
    issues))

(defun betterlinear--string (value)
  "Return VALUE as a string, or nil for nil/JSON null."
  (cond
   ((or (null value) (eq value :null) (eq value :json-null)) nil)
   ((stringp value) value)
   (t (format "%s" value))))

(defun betterlinear--org-link (url description)
  "Return an Org link for URL with DESCRIPTION.

If URL is nil, return DESCRIPTION without link markup."
  (let ((description (or (betterlinear--string description) "")))
    (if-let* ((url (betterlinear--string url)))
        (format "[[%s][%s]]" url description)
      description)))

(defun betterlinear--todo-keyword (state-name)
  "Return the Org TODO keyword for Linear STATE-NAME.

This is the Linear state name uppercased, with spaces replaced by hyphens."
  (if-let* ((state-name (betterlinear--string state-name))
            (state-name (string-trim state-name))
            (_ (not (string-empty-p state-name))))
      (upcase (replace-regexp-in-string "[[:space:]]+" "-" state-name))
    "TODO"))

(defun betterlinear--issue-heading (issue &optional level)
  "Return an Org heading line for Linear ISSUE at Org heading LEVEL."
  (let* ((identifier (alist-get 'identifier issue))
         (title (alist-get 'title issue))
         (url (alist-get 'url issue))
         (state (alist-get 'state issue))
         (state-name (alist-get 'name state))
         (level (or level 1)))
    (format "%s %s %s %s\n"
            (make-string level ?*)
            (betterlinear--todo-keyword state-name)
            (betterlinear--org-link url identifier)
            (or (betterlinear--string title) ""))))

(defun betterlinear--insert-property (name value)
  "Insert Org property NAME with VALUE when VALUE is non-empty."
  (when-let* ((value (betterlinear--string value)))
    (unless (string-empty-p value)
      (insert (format ":%s: %s\n" name value)))))

(defun betterlinear--slugify-branch-component (value)
  "Return VALUE slugified for use in a git branch name."
  (when-let* ((value (betterlinear--string value))
              (value (downcase (string-trim value)))
              (value (replace-regexp-in-string "[^[:alnum:]]+" "-" value))
              (value (replace-regexp-in-string "\\`-+\\|-+\\'" "" value))
              (_ (not (string-empty-p value))))
    value))

(defun betterlinear--generated-branch-name (issue)
  "Generate a fallback git branch name for Linear ISSUE."
  (let* ((identifier (betterlinear--string (alist-get 'identifier issue)))
         (identifier-slug (betterlinear--slugify-branch-component identifier))
         (title-slug (betterlinear--slugify-branch-component
                      (alist-get 'title issue))))
    (when identifier-slug
      (string-replace
       "%t" (or title-slug "")
       (string-replace
        "%I" (or identifier "")
        (string-replace "%i" identifier-slug betterlinear-branch-name-format))))))

(defun betterlinear--issue-branch-name (issue)
  "Return Linear ISSUE's branch name, generating a fallback if necessary."
  (let ((branch (betterlinear--string (alist-get 'branchName issue))))
    (if (and branch (not (string-empty-p (string-trim branch))))
        branch
      (betterlinear--generated-branch-name issue))))

(defun betterlinear--insert-issue-properties (issue)
  "Insert an Org property drawer for Linear ISSUE."
  (let ((state (alist-get 'state issue))
        (assignee (alist-get 'assignee issue))
        (team (alist-get 'team issue))
        (project (alist-get 'project issue)))
    (insert ":PROPERTIES:\n")
    (betterlinear--insert-property "LINEAR_ID" (alist-get 'id issue))
    (betterlinear--insert-property "LINEAR_IDENTIFIER" (alist-get 'identifier issue))
    (betterlinear--insert-property "LINEAR_URL" (alist-get 'url issue))
    (betterlinear--insert-property "LINEAR_BRANCH" (betterlinear--issue-branch-name issue))
    (betterlinear--insert-property "STATE_ID" (alist-get 'id state))
    (betterlinear--insert-property "STATE" (alist-get 'name state))
    (betterlinear--insert-property "STATE_TYPE" (alist-get 'type state))
    (betterlinear--insert-property "ASSIGNEE_ID" (alist-get 'id assignee))
    (betterlinear--insert-property "ASSIGNEE" (alist-get 'name assignee))
    (betterlinear--insert-property "TEAM_ID" (alist-get 'id team))
    (betterlinear--insert-property "TEAM" (alist-get 'key team))
    (betterlinear--insert-property "TEAM_NAME" (alist-get 'name team))
    (betterlinear--insert-property "PROJECT_ID" (alist-get 'id project))
    (betterlinear--insert-property "PROJECT" (alist-get 'name project))
    (betterlinear--insert-property "PROJECT_URL" (alist-get 'url project))
    (betterlinear--insert-property "PRIORITY" (alist-get 'priorityLabel issue))
    (betterlinear--insert-property "ESTIMATE" (alist-get 'estimate issue))
    (betterlinear--insert-property "DUE" (alist-get 'dueDate issue))
    (betterlinear--insert-property "CREATED" (alist-get 'createdAt issue))
    (betterlinear--insert-property "UPDATED" (alist-get 'updatedAt issue))
    (insert ":END:\n")))

(defun betterlinear--json-string-value (value)
  "Parse VALUE as JSON when it is a JSON-looking string, otherwise return nil."
  (when-let* ((value (betterlinear--string value))
              (value (string-trim value))
              (_ (not (string-empty-p value)))
              (_ (memq (aref value 0) '(?{ ?\[))))
    (condition-case nil
        (let ((json-object-type 'alist)
              (json-array-type 'list)
              (json-key-type 'symbol))
          (json-read-from-string value))
      (error nil))))

(defun betterlinear--description-data-text (value)
  "Return plain text extracted from Linear rich description VALUE."
  (cond
   ((or (null value) (eq value :null) (eq value :json-null)) nil)
   ((stringp value)
    (if-let* ((parsed (betterlinear--json-string-value value)))
        (betterlinear--description-data-text parsed)
      value))
   ((vectorp value)
    (betterlinear--description-data-text (append value nil)))
   ((listp value)
    (if (and value (not (consp (car value))))
        (let (parts)
          (dolist (child value)
            (when-let* ((child-text (betterlinear--description-data-text child)))
              (push child-text parts)))
          (let ((joined (string-join (nreverse parts) "")))
            (unless (string-empty-p joined) joined)))
      (let ((type (betterlinear--string (alist-get 'type value)))
            (text (betterlinear--string (alist-get 'text value)))
            parts)
        (when text
          (push text parts))
        (dolist (key '(content children))
          (dolist (child (alist-get key value))
            (when-let* ((child-text (betterlinear--description-data-text child)))
              (push child-text parts))))
        (let ((joined (string-join (nreverse parts) "")))
          (cond
           ((string-empty-p joined) nil)
           ((member type '("paragraph" "heading" "listItem"))
            (concat joined "\n\n"))
           (t joined))))))
   (t nil)))

(defun betterlinear--issue-description (issue)
  "Return ISSUE's Markdown description text, falling back to rich description data."
  (let ((description (betterlinear--string (alist-get 'description issue))))
    (if (and description (not (string-empty-p (string-trim description))))
        description
      (betterlinear--description-data-text (alist-get 'descriptionState issue)))))

(defun betterlinear--pandoc-available-p ()
  "Return non-nil when Pandoc conversion should be used."
  (and betterlinear-use-pandoc
       (executable-find betterlinear-pandoc-command)))

(defun betterlinear--pandoc-convert (text from to)
  "Use Pandoc to convert TEXT from format FROM to format TO."
  (with-temp-buffer
    (insert text)
    (let ((status (call-process-region (point-min)
                                       (point-max)
                                       betterlinear-pandoc-command
                                       t
                                       t
                                       nil
                                       "-f" from
                                       "-t" to)))
      (unless (and (integerp status) (zerop status))
        (error "Pandoc failed converting %s to %s" from to))
      (string-trim-right (buffer-string)))))

(defun betterlinear--fallback-markdown-to-org (markdown)
  "Convert MARKDOWN to Org using a small built-in fallback converter."
  (let* ((text (replace-regexp-in-string
                "\\[\\([^]\n]+\\)\\](\\([^)]*\\))"
                "[[\\2][\\1]]"
                markdown))
         in-fence
         lines)
    (dolist (line (split-string text "\n"))
      (cond
       ((string-match "\\`[[:space:]]*\\(```\\|~~~\\)\\([^\n]*\\)\\'" line)
        (if in-fence
            (progn
              (push "#+end_src" lines)
              (setq in-fence nil))
          (let ((lang (string-trim (match-string 2 line))))
            (push (if (string-empty-p lang)
                      "#+begin_src"
                    (format "#+begin_src %s" lang))
                  lines)
            (setq in-fence t))))
       ((and (not in-fence)
             (string-match "\\`\\(#+\\)[[:space:]]+\\(.*\\)\\'" line))
        (push (format "%s %s"
                      (make-string (length (match-string 1 line)) ?*)
                      (match-string 2 line))
              lines))
       (t
        (push line lines))))
    (string-trim-right (string-join (nreverse lines) "\n"))))

(defun betterlinear--fallback-org-to-markdown (org)
  "Convert ORG to Markdown using a small built-in fallback converter."
  (let ((text org))
    (setq text (replace-regexp-in-string
                "\\[\\[\\([^]\n]+\\)\\]\\[\\([^]\n]+\\)\\]\\]"
                "[\\2](\\1)"
                text))
    (with-temp-buffer
      (insert text)
      (goto-char (point-min))
      (while (re-search-forward "^[[:space:]]*#\\+begin_src\\(?:[[:space:]]+\\([^\n]+\\)\\)?[[:space:]]*$" nil t)
        (replace-match (format "```%s" (or (match-string 1) "")) t t))
      (goto-char (point-min))
      (while (re-search-forward "^[[:space:]]*#\\+end_src[[:space:]]*$" nil t)
        (replace-match "```" t t))
      (goto-char (point-min))
      (while (re-search-forward "^\\(\\*+\\)[[:space:]]+" nil t)
        (replace-match (concat (make-string (length (match-string 1)) ?#) " ")
                       t t))
      (string-trim-right (buffer-string)))))

(defun betterlinear-markdown-to-org (markdown)
  "Convert Linear MARKDOWN text to Org text."
  (if (betterlinear--pandoc-available-p)
      (betterlinear--pandoc-convert markdown "gfm" "org")
    (betterlinear--fallback-markdown-to-org markdown)))

(defun betterlinear-org-to-markdown (org)
  "Convert ORG text to Markdown for Linear."
  (if (betterlinear--pandoc-available-p)
      (betterlinear--pandoc-convert org "org" "gfm")
    (betterlinear--fallback-org-to-markdown org)))

(defun betterlinear--insert-issue-description (issue)
  "Insert Linear ISSUE's description as the Org entry body."
  (when-let* ((description (betterlinear--issue-description issue))
              (description (string-trim description))
              (_ (not (string-empty-p description))))
    (insert "\n" (betterlinear-markdown-to-org description) "\n")))

(defun betterlinear--insert-issue (issue &optional level)
  "Insert Linear ISSUE as an Org entry at heading LEVEL."
  (insert (betterlinear--issue-heading issue level))
  (betterlinear--insert-issue-properties issue)
  (betterlinear--insert-issue-description issue)
  (insert "\n"))

(defun betterlinear--todo-keywords-for-issues (issues)
  "Return unique Org TODO keywords for the Linear state names in ISSUES."
  (let (keywords)
    (dolist (issue issues)
      (let* ((state (alist-get 'state issue))
             (keyword (betterlinear--todo-keyword (alist-get 'name state))))
        (unless (member keyword keywords)
          (setq keywords (append keywords (list keyword))))))
    (or keywords '("TODO"))))

(defun betterlinear--set-local-todo-keywords (keywords)
  "Set buffer-local Org TODO KEYWORDS for the current buffer."
  (setq-local org-todo-keywords `((sequence ,@keywords)))
  ;; `org-todo' checks `org-todo-keywords-1'. Setting only
  ;; `org-todo-keywords' after `org-mode' is enabled is not enough until Org has
  ;; parsed a #+TODO line, so keep this in sync explicitly.
  (setq-local org-todo-keywords-1 keywords)
  (save-excursion
    (org-set-regexps-and-options)))

(defun betterlinear--todo-keyword-line ()
  "Return the buffer's #+TODO line bounds, or nil if there is none."
  (save-excursion
    (goto-char (point-min))
    (when (re-search-forward "^[[:space:]]*#\\+TODO:[[:space:]].*$" nil t)
      (cons (line-beginning-position) (line-end-position)))))

(defun betterlinear--write-todo-keyword-line (keywords)
  "Write KEYWORDS to the buffer's #+TODO line."
  (let ((line (format "#+TODO: %s" (string-join keywords " "))))
    (if-let* ((bounds (betterlinear--todo-keyword-line)))
        (progn
          (goto-char (car bounds))
          (delete-region (car bounds) (cdr bounds))
          (insert line))
      (save-excursion
        (goto-char (point-min))
        (if (re-search-forward "^[[:space:]]*#\\+DATE:.*$" nil t)
            (progn (end-of-line) (insert "\n" line))
          (insert line "\n"))))))

(defun betterlinear--ensure-todo-keyword (keyword)
  "Ensure KEYWORD is a valid Org TODO keyword in the current buffer."
  (unless (member keyword org-todo-keywords-1)
    (let ((keywords (append org-todo-keywords-1 (list keyword))))
      (betterlinear--write-todo-keyword-line keywords)
      (betterlinear--set-local-todo-keywords keywords))))

(defun betterlinear--insert-my-issues-org (issues)
  "Insert ISSUES into the current buffer as Org content."
  (let ((inhibit-read-only t)
        (todo-keywords (betterlinear--todo-keywords-for-issues issues)))
    (erase-buffer)
    (insert "#+TITLE: Linear issues assigned to me\n")
    (insert (format "#+DATE: %s\n" (format-time-string "%Y-%m-%d %H:%M:%S %Z")))
    (insert (format "#+TODO: %s\n" (string-join todo-keywords " ")))
    (insert "#+STARTUP: overview\n\n")
    (if issues
        (dolist (issue issues)
          (betterlinear--insert-issue issue))
      (insert "No assigned Linear issues found.\n"))
    (betterlinear--set-local-todo-keywords todo-keywords)
    (goto-char (point-min))))

(defun betterlinear--revert-my-issues-buffer (&rest _args)
  "Refresh the current BetterLinear issues buffer."
  (betterlinear--insert-my-issues-org (betterlinear-my-issues))
  t)

(defun betterlinear--current-issue-id ()
  "Return the Linear issue id for the Org entry at point.

Signal a user error when point is not on an Org entry generated by
BetterLinear."
  (unless (derived-mode-p 'org-mode)
    (user-error "This command must be run from an Org buffer"))
  (save-excursion
    (org-back-to-heading t)
    (or (org-entry-get (point) "LINEAR_ID")
        (user-error "No LINEAR_ID property on the current Org entry"))))

(defun betterlinear--current-org-entry-title ()
  "Return the current Org entry heading text as a Linear title."
  (unless (derived-mode-p 'org-mode)
    (user-error "This command must be run from an Org buffer"))
  (save-excursion
    (org-back-to-heading t)
    (let ((title (string-trim (org-get-heading t t t t))))
      (if (string-empty-p title)
          (user-error "Current Org entry has an empty heading")
        title))))

(defun betterlinear--current-org-entry-description ()
  "Return the current Org entry body as a Linear Markdown description, or nil.

The description starts after the heading, planning line, and property drawer,
stops before the first child heading, and is converted from Org to Markdown."
  (unless (derived-mode-p 'org-mode)
    (user-error "This command must be run from an Org buffer"))
  (save-excursion
    (org-back-to-heading t)
    (let* ((subtree-end (save-excursion (org-end-of-subtree t t) (point)))
           beg end description)
      (forward-line 1)
      (while (and (< (point) subtree-end)
                  (looking-at-p org-planning-line-re))
        (forward-line 1))
      (when (and (< (point) subtree-end)
                 (looking-at-p "[[:space:]]*:PROPERTIES:[[:space:]]*$"))
        (if (re-search-forward "^[[:space:]]*:END:[[:space:]]*$" subtree-end t)
            (forward-line 1)
          (user-error "Malformed property drawer in current Org entry")))
      (setq beg (point))
      (setq end (or (save-excursion
                      (when (re-search-forward org-outline-regexp-bol subtree-end t)
                        (line-beginning-position)))
                    subtree-end))
      (setq description (string-trim (buffer-substring-no-properties beg end)))
      (unless (string-empty-p description)
        (betterlinear-org-to-markdown description)))))

(defun betterlinear--current-subtree-region-and-level ()
  "Return `(BEG END LEVEL)' for the current Org subtree."
  (save-excursion
    (org-back-to-heading t)
    (let ((beg (point))
          (level (org-outline-level)))
      (org-end-of-subtree t t)
      (list beg (point) level))))

(defun betterlinear--replace-current-entry-with-issue (issue)
  "Replace the current Org subtree with Linear ISSUE, preserving heading level."
  (pcase-let ((`(,beg ,end ,level) (betterlinear--current-subtree-region-and-level)))
    (let ((inhibit-read-only t)
          (todo-keyword (betterlinear--todo-keyword
                         (alist-get 'name (alist-get 'state issue))))
          heading-marker)
      (delete-region beg end)
      (goto-char beg)
      (betterlinear--insert-issue issue level)
      (setq heading-marker (copy-marker beg t))
      (betterlinear--ensure-todo-keyword todo-keyword)
      (goto-char heading-marker)
      (set-marker heading-marker nil))))

(defun betterlinear--projects-page (&optional after)
  "Return one page of Linear projects after cursor AFTER."
  (let* ((variables `((first . ,betterlinear-issues-page-size)
                      (after . ,after)))
         (data (betterlinear--graphql betterlinear--projects-query variables))
         (connection (alist-get 'projects data)))
    (list :nodes (alist-get 'nodes connection)
          :page-info (alist-get 'pageInfo connection))))

(defun betterlinear-projects ()
  "Return all Linear projects visible to the authenticated user."
  (let (after projects has-next)
    (setq has-next t)
    (while has-next
      (let* ((page (betterlinear--projects-page after))
             (nodes (plist-get page :nodes))
             (page-info (plist-get page :page-info)))
        (setq projects (nconc projects nodes))
        (setq has-next (eq (alist-get 'hasNextPage page-info) t))
        (setq after (alist-get 'endCursor page-info))))
    projects))

(defun betterlinear--project-candidates (projects)
  "Return completing-read candidates for Linear PROJECTS."
  (mapcar (lambda (project)
            (let ((name (betterlinear--string (alist-get 'name project)))
                  (url (betterlinear--string (alist-get 'url project))))
              (cons (if url (format "%s — %s" name url) name) project)))
          projects))

(defun betterlinear--read-project (projects &optional current-project-id)
  "Prompt for a project from PROJECTS, defaulting to CURRENT-PROJECT-ID."
  (let* ((candidates (betterlinear--project-candidates projects))
         default)
    (when current-project-id
      (dolist (candidate candidates)
        (when (string= current-project-id
                       (betterlinear--string (alist-get 'id (cdr candidate))))
          (setq default (car candidate)))))
    (cdr (assoc (completing-read "Linear project: "
                                 candidates
                                 nil
                                 t
                                 nil
                                 nil
                                 default)
                candidates))))

(defun betterlinear-set-issue-project (issue-id project-id)
  "Set Linear ISSUE-ID to PROJECT-ID and return the updated issue."
  (let* ((data (betterlinear--graphql betterlinear--set-issue-project-mutation
                                      `((id . ,issue-id)
                                        (projectId . ,project-id))))
         (payload (alist-get 'issueUpdate data)))
    (unless (eq (alist-get 'success payload) t)
      (error "Linear failed to update project for issue %s" issue-id))
    (alist-get 'issue payload)))

(defun betterlinear-viewer ()
  "Return the authenticated Linear user."
  (let ((data (betterlinear--graphql betterlinear--viewer-query)))
    (alist-get 'viewer data)))

(defun betterlinear-set-issue-assignee (issue-id assignee-id)
  "Set Linear ISSUE-ID's assignee to ASSIGNEE-ID and return the updated issue."
  (let* ((data (betterlinear--graphql betterlinear--set-issue-assignee-mutation
                                      `((id . ,issue-id)
                                        (assigneeId . ,assignee-id))))
         (payload (alist-get 'issueUpdate data)))
    (unless (eq (alist-get 'success payload) t)
      (error "Linear failed to update assignee for issue %s" issue-id))
    (alist-get 'issue payload)))

(defun betterlinear-teams ()
  "Return Linear teams visible to the authenticated user."
  (let* ((data (betterlinear--graphql betterlinear--teams-query))
         (teams (alist-get 'teams data)))
    (alist-get 'nodes teams)))

(defun betterlinear--team-candidates (teams)
  "Return completing-read candidates for Linear TEAMS."
  (mapcar (lambda (team)
            (let ((key (betterlinear--string (alist-get 'key team)))
                  (name (betterlinear--string (alist-get 'name team))))
              (cons (format "%s — %s" key name) team)))
          teams))

(defun betterlinear--read-team-id-at-point ()
  "Return a Linear team id for the current Org entry, prompting if needed."
  (save-excursion
    (org-back-to-heading t)
    (or (org-entry-get (point) "TEAM_ID")
        (org-entry-get (point) "LINEAR_TEAM_ID")
        (let* ((team-key (org-entry-get (point) "TEAM"))
               (teams (betterlinear-teams))
               (team (and team-key
                          (seq-find (lambda (candidate)
                                      (string= team-key
                                               (betterlinear--string
                                                (alist-get 'key candidate))))
                                    teams))))
          (or (betterlinear--string (alist-get 'id team))
              (let* ((candidates (betterlinear--team-candidates teams))
                     (choice (completing-read "Linear team: " candidates nil t)))
                (alist-get 'id (cdr (assoc choice candidates)))))))))

(defun betterlinear-create-issue (team-id title &optional description)
  "Create a Linear issue in TEAM-ID with TITLE and DESCRIPTION.

Return the created issue."
  (let* ((data (betterlinear--graphql betterlinear--create-issue-mutation
                                      `((teamId . ,team-id)
                                        (title . ,title)
                                        (description . ,description))))
         (payload (alist-get 'issueCreate data)))
    (unless (eq (alist-get 'success payload) t)
      (error "Linear failed to create issue"))
    (alist-get 'issue payload)))

(defun betterlinear-issue (issue-id)
  "Return the latest Linear issue data for ISSUE-ID."
  (let* ((data (betterlinear--graphql betterlinear--issue-query
                                      `((id . ,issue-id))))
         (issue (alist-get 'issue data)))
    (unless issue
      (user-error "Linear issue not found: %s" issue-id))
    issue))

(defun betterlinear--issue-with-states (issue-id)
  "Return Linear issue ISSUE-ID, including its team's workflow states."
  (let* ((data (betterlinear--graphql betterlinear--issue-states-query
                                      `((id . ,issue-id))))
         (issue (alist-get 'issue data)))
    (unless issue
      (user-error "Linear issue not found: %s" issue-id))
    issue))

(defun betterlinear--state-candidates (states)
  "Return completing-read candidates for Linear workflow STATES."
  (mapcar (lambda (state)
            (let* ((name (betterlinear--string (alist-get 'name state)))
                   (type (betterlinear--string (alist-get 'type state)))
                   (display (if type
                                (format "%s (%s)" name type)
                              name)))
              (cons display state)))
          states))

(defun betterlinear--read-state (issue)
  "Prompt for and return a new workflow state for ISSUE."
  (let* ((team (alist-get 'team issue))
         (states-connection (alist-get 'states team))
         (states (alist-get 'nodes states-connection))
         (current-state (alist-get 'state issue))
         (current-name (betterlinear--string (alist-get 'name current-state)))
         (candidates (betterlinear--state-candidates states))
         default)
    (unless states
      (user-error "No workflow states found for this issue's team"))
    (dolist (candidate candidates)
      (when (string= current-name
                     (betterlinear--string (alist-get 'name (cdr candidate))))
        (setq default (car candidate))))
    (cdr (assoc (completing-read "New Linear state: "
                                 candidates
                                 nil
                                 t
                                 nil
                                 nil
                                 default)
                candidates))))

(defun betterlinear-set-issue-state (issue-id state-id)
  "Set Linear ISSUE-ID to workflow STATE-ID and return the updated issue."
  (let* ((data (betterlinear--graphql betterlinear--set-issue-state-mutation
                                      `((id . ,issue-id)
                                        (stateId . ,state-id))))
         (payload (alist-get 'issueUpdate data)))
    (unless (eq (alist-get 'success payload) t)
      (error "Linear failed to update issue %s" issue-id))
    (alist-get 'issue payload)))

(defun betterlinear--set-heading-todo-keyword (keyword)
  "Set the current Org heading's TODO keyword to KEYWORD.

This edits the heading directly instead of calling `org-todo', because newly
created Linear state keywords may not yet be known to Org."
  (save-excursion
    (org-back-to-heading t)
    (let ((line-end (line-end-position)))
      (if (re-search-forward "^\\(\\*+[[:space:]]+\\)\\([[:upper:]][[:upper:][:digit:]_-]*\\)\\([[:space:]]+\\)" line-end t)
          (replace-match keyword t t nil 2)
        (when (re-search-forward "^\\*+\\([[:space:]]*\\)" line-end t)
          (replace-match (concat " " keyword " ") t t nil 1))))))

(defun betterlinear--update-current-entry-state (issue)
  "Update the current Org entry's state properties from Linear ISSUE."
  (let* ((state (alist-get 'state issue))
         (state-id (alist-get 'id state))
         (state-name (alist-get 'name state))
         (state-type (alist-get 'type state))
         (updated-at (alist-get 'updatedAt issue))
         (todo-keyword (betterlinear--todo-keyword state-name))
         (inhibit-read-only t))
    (save-excursion
      (org-back-to-heading t)
      (betterlinear--set-heading-todo-keyword todo-keyword)
      (when-let* ((state-id (betterlinear--string state-id)))
        (org-entry-put (point) "STATE_ID" state-id))
      (when-let* ((state-name (betterlinear--string state-name)))
        (org-entry-put (point) "STATE" state-name))
      (when-let* ((state-type (betterlinear--string state-type)))
        (org-entry-put (point) "STATE_TYPE" state-type))
      (when-let* ((updated-at (betterlinear--string updated-at)))
        (org-entry-put (point) "UPDATED" updated-at))
      ;; Do this last because inserting/updating the #+TODO line can move point
      ;; when the heading is near the top of the buffer.
      (betterlinear--ensure-todo-keyword todo-keyword))))

;;;###autoload
(defun betterlinear-set-issue-state-at-point (state)
  "Change the Linear state of the story for the Org entry at point.

The current entry must have a LINEAR_ID property, as entries generated by
`betterlinear-my-issues-org' do. Interactively, prompt with the workflow states
available to the issue's Linear team."
  (interactive
   (let* ((issue-id (betterlinear--current-issue-id))
          (issue (betterlinear--issue-with-states issue-id)))
     (list (betterlinear--read-state issue))))
  (let* ((issue-id (betterlinear--current-issue-id))
         (state-id (alist-get 'id state))
         (state-name (alist-get 'name state))
         (updated-issue (betterlinear-set-issue-state issue-id state-id)))
    (betterlinear--update-current-entry-state updated-issue)
    (message "Set %s to %s"
             (or (org-entry-get (point) "LINEAR_IDENTIFIER") issue-id)
             (betterlinear--string state-name))))

;;;###autoload
(defun betterlinear-set-project-at-point (project)
  "Set the Linear project for the Org entry at point.

The current entry must have a LINEAR_ID property, as entries generated by
`betterlinear-my-issues-org' do. Interactively, prompt for a project from the
projects visible to the authenticated Linear user, then replace the Org entry
with the updated Linear story while keeping the same heading level."
  (interactive
   (let* ((issue-id (betterlinear--current-issue-id))
          (_issue-id issue-id)
          (current-project-id (save-excursion
                                (org-back-to-heading t)
                                (org-entry-get (point) "PROJECT_ID")))
          (projects (betterlinear-projects)))
     (unless projects
       (user-error "No Linear projects found"))
     (list (betterlinear--read-project projects current-project-id))))
  (let* ((issue-id (betterlinear--current-issue-id))
         (project-id (alist-get 'id project))
         (project-name (alist-get 'name project))
         (updated-issue (betterlinear-set-issue-project issue-id project-id)))
    (betterlinear--replace-current-entry-with-issue updated-issue)
    (message "Set %s project to %s"
             (or (betterlinear--string (alist-get 'identifier updated-issue))
                 issue-id)
             (betterlinear--string project-name))))

;;;###autoload
(defun betterlinear-set-me-as-owner-at-point ()
  "Set the authenticated Linear user as owner/assignee for the story at point.

The current Org entry must have a LINEAR_ID property. Linear calls this field
`assignee'; this command uses `owner' in the command name for convenience. The
Org entry is replaced with the updated Linear story while keeping the same
heading level."
  (interactive)
  (let* ((issue-id (betterlinear--current-issue-id))
         (viewer (betterlinear-viewer))
         (viewer-id (alist-get 'id viewer))
         (viewer-name (alist-get 'name viewer))
         (updated-issue (betterlinear-set-issue-assignee issue-id viewer-id)))
    (betterlinear--replace-current-entry-with-issue updated-issue)
    (message "Set %s owner to %s"
             (or (betterlinear--string (alist-get 'identifier updated-issue))
                 issue-id)
             (betterlinear--string viewer-name))))

;;;###autoload
(defun betterlinear-copy-git-branch-at-point ()
  "Copy the Linear git branch name for the Org entry at point.

The current entry must have a LINEAR_ID property. This fetches the latest issue
from Linear so the copied branch name is current, then stores it in the kill
ring."
  (interactive)
  (let* ((issue-id (betterlinear--current-issue-id))
         (issue (betterlinear-issue issue-id))
         (branch (betterlinear--issue-branch-name issue)))
    (unless (and branch (not (string-empty-p branch)))
      (user-error "Could not determine git branch name for Linear issue: %s" issue-id))
    (kill-new branch)
    (message "Copied branch: %s%s"
             branch
             (if (betterlinear--string (alist-get 'branchName issue))
                 ""
               " (generated)"))))

;;;###autoload
(defun betterlinear-create-issue-from-org-entry (team-id)
  "Create a Linear story from the Org entry at point.

The Org heading becomes the Linear title. The entry body, after any planning
line and property drawer and before the first child heading, becomes the Linear
description. Interactively, use TEAM_ID/LINEAR_TEAM_ID/TEAM properties when
present, otherwise prompt for a Linear team.

After creation, replace the Org entry in place with the created Linear story,
keeping the same heading level."
  (interactive (list (betterlinear--read-team-id-at-point)))
  (save-excursion
    (org-back-to-heading t)
    (when (org-entry-get (point) "LINEAR_ID")
      (user-error "Current Org entry already has a LINEAR_ID property")))
  (let* ((title (betterlinear--current-org-entry-title))
         (description (betterlinear--current-org-entry-description))
         (issue (betterlinear-create-issue team-id title description)))
    (betterlinear--replace-current-entry-with-issue issue)
    (message "Created Linear issue %s"
             (or (betterlinear--string (alist-get 'identifier issue))
                 (betterlinear--string (alist-get 'id issue))))))

;;;###autoload
(defun betterlinear-refresh-issue-at-point ()
  "Fetch the latest Linear story for the Org entry at point and replace it.

The replacement keeps the current Org heading level. The current entry must have
a LINEAR_ID property, as entries generated by `betterlinear-my-issues-org' do."
  (interactive)
  (let* ((issue-id (betterlinear--current-issue-id))
         (issue (betterlinear-issue issue-id)))
    (betterlinear--replace-current-entry-with-issue issue)
    (message "Refreshed %s" (or (betterlinear--string (alist-get 'identifier issue))
                                issue-id))))

;;;###autoload
(defun betterlinear-my-issues-org ()
  "Retrieve all Linear issues assigned to you and show them in an Org buffer."
  (interactive)
  (let ((buffer (get-buffer-create betterlinear-my-issues-buffer-name)))
    (with-current-buffer buffer
      (betterlinear-org-mode)
      (betterlinear--insert-my-issues-org (betterlinear-my-issues))
      (setq buffer-read-only t))
    (pop-to-buffer buffer)))

(provide 'betterlinear)
;;; betterlinear.el ends here
