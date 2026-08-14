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

(defcustom betterlinear-my-non-done-issues-buffer-name "*Linear My Non-Done Issues*"
  "Name of the Org buffer used by `betterlinear-my-non-done-issues-org'."
  :type 'string
  :group 'betterlinear)

(defcustom betterlinear-my-current-cycle-non-done-issues-buffer-name "*Linear My Current Cycle Issues*"
  "Buffer for `betterlinear-my-current-cycle-non-done-issues-org'."
  :type 'string
  :group 'betterlinear)

(defcustom betterlinear-project-stories-buffer-name "*Linear Project Stories*"
  "Name of the Org buffer used by `betterlinear-project-stories-org'."
  :type 'string
  :group 'betterlinear)

(defcustom betterlinear-team-search-buffer-name "*Linear Team Search*"
  "Name of the Org buffer used by `betterlinear-search-team-issues-org'."
  :type 'string
  :group 'betterlinear)

(defcustom betterlinear-team-current-cycle-issues-buffer-name "*Linear Team Current Cycle*"
  "Name of the Org buffer used by `betterlinear-team-current-cycle-issues-org'."
  :type 'string
  :group 'betterlinear)

(defcustom betterlinear-team-project-issues-buffer-name "*Linear Team Project Issues*"
  "Name of the Org buffer used by `betterlinear-team-project-issues-org'."
  :type 'string
  :group 'betterlinear)

(defcustom betterlinear-needs-review-pull-requests-buffer-name "*Linear Needs Your Review*"
  "Name of the Org buffer used by `betterlinear-needs-review-pull-requests-org'."
  :type 'string
  :group 'betterlinear)

(defcustom betterlinear-capture-buffer-name "*Linear Issue Capture*"
  "Base name of the temporary Org buffer used by `betterlinear-capture-issue'."
  :type 'string
  :group 'betterlinear)

(defcustom betterlinear-captured-issue-buffer-name "*Linear Captured Issue*"
  "Base name of the Org buffer shown after `betterlinear-capture-finalize'."
  :type 'string
  :group 'betterlinear)

(defcustom betterlinear-issues-page-size 100
  "Number of issues to request per Linear API page."
  :type 'integer
  :group 'betterlinear)

(defcustom betterlinear-default-team nil
  "Default Linear team used by team-picking commands.

When non-nil, a string matching either a team key (for example \"AISHBE\")
or a team id.  Commands that would normally prompt for a team use this team
instead, without prompting.  Resolution first looks at the teams returned by
`betterlinear-teams' and, when the team is not in that list, falls back to a
direct Linear lookup by key or id, so a default still works even when the
team list is truncated by the Linear API.

Set to nil to always prompt.  With a prefix argument, team-picking commands
prompt even when this is set."
  :type '(choice (const :tag "Always prompt" nil)
                 (string :tag "Team key or id"))
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

(defcustom betterlinear-state-keyword-map nil
  "Alist mapping Linear state names to Org TODO keywords.

Each entry is a cons cell (STATE-NAME . KEYWORD), where STATE-NAME is the
exact Linear workflow state name and KEYWORD is the Org TODO keyword to use
instead of the default (uppercased state name with spaces replaced by hyphens).

Example:

  ((\"Ready\" . \"TODO\")
   (\"In Review\" . \"REVIEWING\")
   (\"Blocked\" . \"WAITING\"))"
  :type '(alist :key-type (string :tag "Linear state name")
                :value-type (string :tag "Org TODO keyword"))
  :group 'betterlinear)

(provide 'betterlinear-core)
