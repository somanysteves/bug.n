# Claude Code Rules

## Separately authorize each step

Plan agreement is not execution authorization. "Sounds reasonable" / "seems fine" on a
proposed approach is discussion-stage agreement, not a go-ahead. Each of these needs
its own explicit "go":
- Committing
- Pushing to any remote
- Opening/merging PRs, or posting comments on any issue/PR (our fork OR upstream)

Do not chain these in one pass. Approval for step N is not approval for step N+1.

## Before Committing
1. Run `build.bat` and confirm it succeeds with no errors
2. Run any unit tests and confirm they pass
3. Get explicit verbal confirmation from the user that they are ready to commit

Never commit without completing all three steps.

## Before Pushing
Approval to commit is not approval to push. Get explicit verbal "push it" first.

## Before Posting
Show proposed wording before posting any comment or PR body. Applies to our fork and upstream alike.
