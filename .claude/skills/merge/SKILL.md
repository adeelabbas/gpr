---
name: merge
description: Merge a GPR pull request into the default branch the way GitHub's merge button does on the repository (a rebase merge in adeelabbas/gpr, a squash in gpraw/gpr), then delete its branch on origin and locally, switch this checkout to the default branch and pull everything new. Only when the user types /merge.
argument-hint: "[--dry-run] [PR number, URL or branch, default this branch's PR]"
disable-model-invocation: true
allowed-tools: Bash(scripts/merge_pr.sh), Bash(scripts/merge_pr.sh *)
---

# Merge a pull request and clean up after it

`scripts/merge_pr.sh` does all of it, in an order that keeps it safe. Your
part is to run it, and to report what it did or why it stopped.

All paths below are relative to the repository root.

The PR merges into the default branch (`master` in adeelabbas/gpr, `main`
in gpraw/gpr). The script asks GitHub which branch that is and prints its
real name wherever a line names it; `<default>` below stands for it.

## 1. Run it

Pass `--dry-run` when the user asked for one, and the PR if the user named
one:

    scripts/merge_pr.sh [--dry-run] [<pr>]

`--dry-run` counts before the PR or after it. Pass nothing else: the script
reads every argument before it does anything, and an option it does not
know, a second PR or an empty argument stops it there (`error: unrecognized
option ...`) with nothing changed. That is deliberate. The flag used to count
only in first place, and a dry run asked for as `<n> --dry-run` merged the
PR. So if the user asked for a dry run, check that the output ends `Dry run:
nothing was changed.` before saying it was one.

Write the PR as a bare number: `195`, never `#195`, whatever the user typed.
An unquoted `#` starts a comment in the shell and takes the rest of the line
with it, so `scripts/merge_pr.sh #195 --dry-run` reaches the script as no
arguments at all, which is a real merge of this branch's PR. The script
cannot see what the shell threw away. Put a URL in single quotes for the
same reason (`&`, `#`, `?`).

With no PR named it merges this branch's PR. It prints the PR it found
(number, title, branch, head commit, state), any open PRs stacked on it, and
then each step.

The script checks everything that can stop a merge before it changes
anything:
- the PR is this repository's own. A URL can name a PR anywhere, and the
  script would otherwise bring that PR's number and branch name back to this
  repository's PRs and branches (`error: #NN is a pull request of ...`). It
  is to be merged from a checkout of its own repository;
- the PR is open, not a draft, into the default branch, from a branch of
  this repository, and GitHub reports it mergeable (`CLEAN`, or `HAS_HOOKS`),
  with no conflicts, no failing or pending required checks, and - where
  the default branch requires branches to be up to date, as gpraw/gpr's
  `main` does - not behind it. adeelabbas/gpr's `master` does not, so
  there GitHub reports a branch behind it as mergeable, and the merge goes
  through on a combination CI never built;
- the open PRs based on its branch (stacked PRs) can be listed, and none is
  a PR from the default branch itself, which could not be retargeted to
  the default branch;
- the working tree has no uncommitted changes to tracked files;
- the local default branch can fast-forward to origin's;
- a local copy of the branch sits exactly at the PR's head;
- the repository's settings allow a squash or a rebase merge.

It merges pinned to that head commit, by the method GitHub's merge button
offers the gh user on this repository (the one they last used there) when
that is a squash or a rebase merge the settings allow, else a squash where
they allow one, else a rebase merge. Both repositories allow every method,
so the button is what tells them apart:
- adeelabbas/gpr rebase-merges (`Rebase-merging #NN ...`), which puts each
  of the PR's commits on the default branch with its own message. It keeps
  README, CLAUDE.md and workflow edits in commits of their own so its code
  commits cherry-pick into gpraw/gpr as they are, and a squash would fold
  them into one.
- gpraw/gpr squash-merges (`Squash-merging #NN ...`), with GitHub's default
  message: the title with (#NN) and every commit's message.

A squash merge by hand in adeelabbas/gpr can turn the button, and so the
script, to squashing there; turning squash merging off in its settings
pins the rebase, and is the user's call. So a `Squash-merging` line in
adeelabbas/gpr is worth pointing out.

Only once GitHub reports the PR merged does it retarget the stacked PRs to
the default branch (`Retargeting #NN ...`), delete the branch on origin,
switch to the default branch, fast-forward it, and delete the local branch.

When the default branch is checked out in another worktree (this session
runs under `.claude/worktrees/` while the main checkout sits on it), git
will not switch to it here. The script then detaches this checkout at
origin's default branch instead (`Detaching at origin/<default>: ...`),
which still frees the local branch to be deleted, and leaves the default
branch to be pulled in the worktree that has it.

The retargeting is what keeps the stacked PRs alive. Deleting a branch with
a push closes every open PR based on it, and a closed PR whose base branch
is gone can be neither reopened nor retargeted. So the script deletes
origin's branch only once GitHub lists no open PR based on it, and otherwise
keeps it and says so (`Keeping origin/<branch>: ...`).

A PR that is already merged skips straight to that cleanup, the retargeting
included.

## 2. If it stops

A line starting `error:` names what stopped it, and nothing after that point
ran. Tell the user that line and what would clear it. Do not work around it
yourself:
- no `gh pr merge --admin` past a failing or pending check;
- no force-push or rebase to catch a branch up;
- no discarding local changes or local commits to get a clean tree;
- no `git push origin --delete` of a branch the script kept. That closes the
  PRs still based on it, which is the one thing here that cannot be undone
  with a click.

Each of those is the user's decision. The one exception is a merge state
GitHub had not worked out yet (`not mergeable yet (merge state UNKNOWN)`),
which clears on its own; running the script once more after a moment is fine.

If it stopped after the merge (`could not switch to ...`, `could not
fetch <default>`, `could not fast-forward <default>`, or a warning about
retargeting a PR or deleting a branch), the PR is merged. Say that
plainly, then say which cleanup step is left. When it kept origin's
branch for a stacked PR, the last line reads
`Done except origin/<branch>: ...` and the step left is the user's:
retarget the PRs the line names (`gh pr edit <n> --base <default>`), then
run the script on the merged PR again, which deletes the branch.

A PR the script did retarget still carries the merged PR's commits as well
as its own, and the default branch has their squash or their rebased
copies instead, so GitHub reports it behind, or in conflict where its own
changes touch lines the merged PR changed. What clears both is
`git rebase --onto <default> <merged PR's head>` on its branch, which
replays only its own commits onto a tree identical to the one they were
built on, then a force-push. An update from the default branch (a merge
commit) conflicts in the second case. Say so when you report it; the rebase
is the user's to run.

## 3. Tell the user

Keep it short:
- the PR merged, squashed or rebased, and its merge commit (`merged as
  ...`), or that it was already merged;
- each stacked PR it retargeted to the default branch, by number;
- which branches were deleted, and any the script kept and why (it keeps a
  local branch that is checked out in another worktree, and origin's branch
  while an open PR is still based on it);
- when it detached this checkout, that the default branch is still to be
  pulled in the worktree the line names;
- the line `Done: <default> at ...` (`Done: origin/<default> at ...` when
  detached), or `Done except origin/<branch>: ...` when a stacked PR kept
  the branch, with what the user has to do about it.

For a dry run, say that nothing changed and list what it would have done,
the PRs it would retarget included.
