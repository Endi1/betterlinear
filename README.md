# betterlinear.el

An Emacs package for working with [Linear](https://linear.app) issues from Org mode.

`betterlinear.el` lets you pull Linear stories into an Org buffer, update Linear from Org entries, create Linear stories from Org entries, and copy generated git branch names.

## Features

- Fetch all Linear issues assigned to you into an Org-mode buffer.
- Render each Linear issue as an Org heading with a property drawer.
- Use Linear workflow state names as Org TODO keywords.
  - Example: `In Progress` becomes `IN-PROGRESS`.
- Refresh a single Org entry from Linear in place while preserving heading level.
- Change the Linear state for the issue at point.
- Set the Linear project for the issue at point.
- Assign the issue at point to yourself.
- Create a Linear issue from an Org entry.
- Copy the Linear/git branch name for the issue at point.
- Convert descriptions between Markdown and Org.
  - Uses Pandoc when available.
  - Falls back to a small built-in converter for links, headings, and code blocks.

## Requirements

- Emacs 27.1 or newer
- Org mode
- A Linear API key
- Optional: [`pandoc`](https://pandoc.org/) for better Markdown ↔ Org conversion

## Installation

Clone this repository somewhere on your `load-path`:

```sh
git clone https://github.com/esukaj/betterlinear.git
```

Then configure Emacs:

```elisp
(add-to-list 'load-path "/path/to/betterlinear")
(require 'betterlinear)
```

Or with `use-package`:

```elisp
(use-package betterlinear
  :load-path "/path/to/betterlinear"
  :custom
  (betterlinear-api-key nil)) ;; use LINEAR_API_KEY
```

## Configuration

### API key

Create a Linear API key in Linear under **Settings → API**.

You can either set it in Emacs:

```elisp
(setq betterlinear-api-key "lin_api_...")
```

or set an environment variable:

```sh
export LINEAR_API_KEY="lin_api_..."
```

If `betterlinear-api-key` is nil, BetterLinear uses `LINEAR_API_KEY`.

### Optional settings

```elisp
(setq betterlinear-my-issues-buffer-name "*Linear My Issues*")
(setq betterlinear-issues-page-size 100)
```

Branch name fallback format:

```elisp
(setq betterlinear-branch-name-format "%i-%t")
```

Supported placeholders:

- `%i` lower-case issue identifier, e.g. `eng-123`
- `%I` original issue identifier, e.g. `ENG-123`
- `%t` slugified issue title, e.g. `fix-login-bug`

Markdown/Org conversion:

```elisp
(setq betterlinear-use-pandoc t)
(setq betterlinear-pandoc-command "pandoc")
```

When Pandoc is unavailable, BetterLinear falls back to a basic converter.

## Usage

### Show my assigned Linear issues

```elisp
M-x betterlinear-my-issues-org
```

This creates or refreshes a buffer named `*Linear My Issues*` containing your assigned Linear issues as Org entries.

Example output:

```org
#+TITLE: Linear issues assigned to me
#+DATE: 2026-04-27 12:00:00 CEST
#+TODO: TODO IN-PROGRESS DONE
#+STARTUP: overview

* IN-PROGRESS [[https://linear.app/acme/issue/ENG-123][ENG-123]] Fix login bug
:PROPERTIES:
:LINEAR_ID: abc123
:LINEAR_IDENTIFIER: ENG-123
:LINEAR_URL: https://linear.app/acme/issue/ENG-123
:LINEAR_BRANCH: eng-123-fix-login-bug
:STATE_ID: state123
:STATE: In Progress
:STATE_TYPE: started
:ASSIGNEE_ID: user123
:ASSIGNEE: Jane Developer
:TEAM_ID: team123
:TEAM: ENG
:TEAM_NAME: Engineering
:PROJECT_ID: project123
:PROJECT: Website
:PROJECT_URL: https://linear.app/acme/project/website
:PRIORITY: Medium
:CREATED: 2026-04-01T10:00:00.000Z
:UPDATED: 2026-04-27T12:00:00.000Z
:END:

Description converted from Linear Markdown into Org.
```

The generated buffer uses `betterlinear-org-mode`, derived from `org-mode`. You can refresh it with `revert-buffer`.

### Refresh the issue at point

```elisp
M-x betterlinear-refresh-issue-at-point
```

Fetches the latest Linear issue for the current Org entry and replaces the subtree in place.

The heading level is preserved. For example, a `***` entry remains a `***` entry.

### Change issue state at point

```elisp
M-x betterlinear-set-issue-state-at-point
```

Prompts for a workflow state from the issue's Linear team and updates Linear.

The Org TODO keyword is updated to match the Linear state name:

- `Todo` → `TODO`
- `In Progress` → `IN-PROGRESS`
- `In Review` → `IN-REVIEW`

### Set project at point

```elisp
M-x betterlinear-set-project-at-point
```

Prompts for a Linear project and sets it on the current issue.

The Org entry is then replaced with the updated Linear issue, preserving heading level.

### Assign the issue to yourself

```elisp
M-x betterlinear-set-me-as-owner-at-point
```

Sets the authenticated Linear user as the issue assignee/owner.

Linear calls this field `assignee`; this package uses “owner” in the command name for convenience.

### Copy git branch name

```elisp
M-x betterlinear-copy-git-branch-at-point
```

Copies the issue branch name to the kill ring.

If Linear returns `branchName`, that value is used. If Linear does not return a branch name, BetterLinear generates one from the issue identifier and title using `betterlinear-branch-name-format`.

### Create a Linear issue from an Org entry

```elisp
M-x betterlinear-create-issue-from-org-entry
```

The current Org entry becomes a Linear story:

- Org heading → Linear title
- Org body → Linear description, converted to Markdown
- `TEAM_ID`, `LINEAR_TEAM_ID`, or `TEAM` property → Linear team, when present
- Otherwise, BetterLinear prompts for a team

After creation, the Org entry is replaced in place with the created Linear issue and keeps the same heading level.

Example source Org entry:

```org
** TODO Add billing webhook retries
:PROPERTIES:
:TEAM: ENG
:END:

We should retry failed billing webhooks.

- Retry transient failures
- Add logging
- Add tests
```

Running `betterlinear-create-issue-from-org-entry` creates the Linear issue and replaces the entry with a Linear-backed entry containing `LINEAR_ID` and related properties.

## Commands

Interactive commands:

| Command | Description |
| --- | --- |
| `betterlinear-my-issues-org` | Show assigned Linear issues in an Org buffer. |
| `betterlinear-refresh-issue-at-point` | Refresh current Org entry from Linear. |
| `betterlinear-set-issue-state-at-point` | Change the Linear workflow state for the issue at point. |
| `betterlinear-set-project-at-point` | Set the Linear project for the issue at point. |
| `betterlinear-set-me-as-owner-at-point` | Assign the issue at point to yourself. |
| `betterlinear-copy-git-branch-at-point` | Copy the issue branch name. |
| `betterlinear-create-issue-from-org-entry` | Create a Linear issue from the current Org entry. |

Lower-level functions:

| Function | Description |
| --- | --- |
| `betterlinear-my-issues` | Return assigned issues as Lisp data. |
| `betterlinear-issue` | Fetch a single issue. |
| `betterlinear-projects` | Fetch visible projects. |
| `betterlinear-teams` | Fetch visible teams. |
| `betterlinear-viewer` | Fetch authenticated Linear user. |
| `betterlinear-create-issue` | Create an issue. |
| `betterlinear-set-issue-state` | Set issue state by state id. |
| `betterlinear-set-issue-project` | Set issue project by project id. |
| `betterlinear-set-issue-assignee` | Set issue assignee by user id. |
| `betterlinear-markdown-to-org` | Convert Markdown to Org. |
| `betterlinear-org-to-markdown` | Convert Org to Markdown. |

## Org property drawer

BetterLinear stores Linear metadata in Org properties, including:

```org
:LINEAR_ID:
:LINEAR_IDENTIFIER:
:LINEAR_URL:
:LINEAR_BRANCH:
:STATE_ID:
:STATE:
:STATE_TYPE:
:ASSIGNEE_ID:
:ASSIGNEE:
:TEAM_ID:
:TEAM:
:TEAM_NAME:
:PROJECT_ID:
:PROJECT:
:PROJECT_URL:
:PRIORITY:
:ESTIMATE:
:DUE:
:CREATED:
:UPDATED:
```

Commands that operate on an existing Linear story require `LINEAR_ID` on the current Org entry.

## Markdown and Org conversion

Linear descriptions are Markdown. Org entry bodies are Org. BetterLinear converts between the two:

- Linear → Org when pulling or refreshing issues
- Org → Markdown when creating issues from Org entries

Pandoc is recommended for best results:

```sh
brew install pandoc
```

or disable Pandoc usage:

```elisp
(setq betterlinear-use-pandoc nil)
```

The built-in fallback converter is intentionally small and only handles common basics.

## Development

Byte-compile check:

```sh
emacs -Q --batch -f batch-byte-compile betterlinear.el
rm -f betterlinear.elc
```

## License

No license has been specified yet.
