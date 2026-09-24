---
name: merge
description: Merge a GPR pull request into the default branch by the method CLAUDE.md implies (a rebase merge where it keeps README, CLAUDE.md and workflow edits in commits of their own, as adeelabbas/gpr's does, a squash otherwise), then delete its branch on origin and locally, switch this checkout to the default branch and pull everything new. Only when the user types /merge.
argument-hint: "[--dry-run] [--squash|--rebase] [PR number, URL or branch, default this branch's PR]"
disable-model-invocation: true
allowed-tools: Bash(scripts/merge_pr.sh), Bash(scripts/merge_pr.sh *)
---

# Merge a pull request and clean up after it

`scripts/merge_pr.sh` does all of it, in an order that keeps it safe. Your
part is to run it with the right merge method, and to report what it did or
why it stopped.

All paths below are relative to the repository root.

The PR merges into the default branch (`master` in adeelabbas/gpr, `main`
in gpraw/gpr). The script asks GitHub which branch that is and prints its
real name wherever a line names it; `<default>` below stands for it.

The repository is origin's. The script asks GitHub about origin's url and
pins every later `gh` call to that repository (`GH_REPO`). In a clone of a
GitHub fork that also has an `upstream` remote - what `gh repo clone
adeelabbas/gpr` makes - gh resolves a bare number to the parent: there
`gh pr view 11` answered gopro/gpr#11 (2026-09-23). A checkout with no
`origin` stops the script before it asks GitHub about any repository or
PR.

## 1. Run it

### The method

Pass `--rebase` or `--squash`, the one CLAUDE.md implies. Read CLAUDE.md
for it on every run rather than remembering which repository this is; this
file is the same in both.
- `--rebase` where CLAUDE.md keeps README, CLAUDE.md and workflow edits in
  commits of their own, so that they can be cherry-picked apart
  (adeelabbas/gpr, whose code commits are cherry-picked into gpraw/gpr). A
  rebase merge lands each commit as it is, with its own message; a squash
  would fold them into one.
- `--squash` otherwise (gpraw/gpr). GitHub's default squash message is the
  title with `(#NN)` and every commit's message below it.

If the user named a method, pass theirs, and say so when CLAUDE.md implies
the other.

The script does not guess. GitHub's own hint, the method its merge button
offers the gh user (`viewerDefaultMergeMethod`), is per user - the method
that user last clicked on the repository - so one merge by hand, or
another operator, turns it, and a merge by the wrong method cannot be
undone. With no option the script takes the one of squash and rebase that
the repository's settings allow when they allow exactly one, and otherwise
refuses an open PR before anything changes. Both repositories' settings
allowed every method on 2026-09-23, so there it needs the option.

### The command

    scripts/merge_pr.sh [--dry-run] [--squash|--rebase] [<pr>]

Pass the method, `--dry-run` when the user asked for one, and the PR if the
user named one. The options count before the PR or after it. Pass nothing
else: the script reads every argument before it does anything, and an
option it does not know, both methods, a second PR or an empty argument
stops it there (`error: unrecognized option ...`) with nothing changed.
That is deliberate. `--dry-run` used to count only in first place, and a
dry run asked for as `<n> --dry-run` merged the PR. So if the user asked
for a dry run, check that the output ends `Dry run: nothing was changed.`
before saying it was one.

Write the PR as a bare number: `195`, never `#195`, whatever the user typed.
An unquoted `#` starts a comment in the shell and takes the rest of the line
with it, so `scripts/merge_pr.sh #195 --dry-run` reaches the script as no
arguments at all, which is a real merge of this branch's PR. The script
cannot see what the shell threw away. Put a URL in single quotes for the
same reason (`&`, `#`, `?`).

With no PR named it merges this branch's PR. It prints the PR it found
(number, title, branch, head commit, state), any open PRs stacked on it, and
then each step.

### What it checks first

The script checks everything that can stop a merge before it changes
anything:
- the PR is this repository's own. A URL can name a PR anywhere, and the
  script would otherwise bring that PR's number and branch name back to this
  repository's PRs and branches (`error: #NN is a pull request of ...`). It
  is to be merged from a checkout of its own repository;
- the PR is open, not a draft, into the default branch, from a branch of
  this repository, and GitHub reports it mergeable (`CLEAN`, or
  `HAS_HOOKS`): no conflicts, no failing or pending required checks, and not
  behind the default branch where its protection requires branches to be up
  to date. Which checks are required, and whether that requirement is on,
  are the default branch's protection settings, which can change without
  this file changing; read them at run time, from the merge state the
  script prints and from `gh pr checks <n> --required -R <owner>/<repo>`
  (origin's repository, as in the PR url the script printed). Where the
  requirement is off, GitHub reports a branch behind the default branch as
  mergeable, and the merge goes through on a combination CI never built;
- the open PRs based on its branch (stacked PRs) can be listed, and none is
  a PR from the default branch itself, which could not be retargeted to
  the default branch;
- the working tree has no uncommitted changes to tracked files;
- the local default branch can fast-forward to origin's;
- a local copy of the branch sits exactly at the PR's head;
- the method is settled: the one passed, when the settings allow it, or
  with none passed the only one of squash and rebase the settings allow.

### What it does

It merges pinned to that head commit, and the merge line says by which
method and where it came from: `Rebase-merging #NN at <sha> (asked for with
--rebase)`, or `(the only one the settings allow)` with no option. Check
that it names the method you meant; in a dry run, stop on one that does
not.

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
keeps it and says so (`Keeping origin/<branch>: it is still the base of
...`). Deleting a branch closes the open PRs whose head it is as well, so
it also keeps the branch while an open PR other than the merged one comes
from it (`Keeping origin/<branch>: it is the head of open #NN ...`).

The delete is leased on the head that was merged
(`git push --force-with-lease=refs/heads/<branch>:<head> origin --delete
<branch>`). A push that landed on the branch after the merge - CI's
test-gap pass, where the repository has one, pushes to PR branches - is on
origin's branch alone, and deleting the branch would lose it. So the script
keeps the branch when it has moved off that head (`Keeping origin/<branch>:
it is at <sha>, not at <sha>, the head that was merged ...`), and a push
that lands between that check and the delete makes git refuse it (`warning:
could not delete origin/<branch>; if it moved off ..., the lease kept
it`). The lines git printed follow that warning, indented: `(stale info)`
among them is the lease refusing; any other failure (the network,
permissions) left the branch where the check found it, at the merged head.

After each retarget the script prints what that PR now needs before it
merges:

    then, before #NN merges, in a checkout with nothing uncommitted:
      git fetch origin
      git switch <its branch>
      git merge --ff-only origin/<its branch>
      git rebase --onto origin/<default> <merged PR's head> <its branch>
      git push --force-with-lease=refs/heads/<its branch>:<its head> origin <its branch>

Its branch still carries the merged PR's original commits, and the default
branch has only their squash or their rebased copies. The rebase replays
only its own commits onto the default branch. GitHub reports the PR BEHIND
or DIRTY only where branch protection or a conflict says so; on a default
branch without that protection it reports it mergeable, and merging it can
land the merged PR's commits a second time. An update from the default
branch (a merge commit) does not help: it conflicts wherever the PR's own
changes touch lines the merged PR changed.

The lines before the rebase make the local branch origin's. `git switch`
creates it from origin's where there is none, the usual case for another
session's branch, and refuses where another worktree has it checked out,
which is then where to run them. `git merge --ff-only` catches up a local
copy that is behind, and stops where the two have diverged, which is the
user's to settle. The lease names `<its head>`, the PR's head as the script
listed it, so a push that lands on the branch after that is refused rather
than lost; a bare `--force-with-lease` leases on `origin/<its branch>`,
which every fetch moves. The fetch comes first because the script's own
came before it listed that head. Measured in scratch repositories
(2026-09-23): the rebase alone, which the script printed before, stopped
where the branch was only on origin (`fatal: no such branch/commit`), and
over a stale local copy it exited 0 without a commit only origin had,
which the force-push then dropped; without the fetch, a push that landed
between the script's fetch and its listing was dropped too. `/next` gives
the same four lines after its own `git fetch origin`. All of them are the
user's to run; pass them on as the script printed them.

For a PR from a fork the script prints one line instead, naming its owner
(`its branch is in a fork, so the rebase is its owner's, in their clone:
...`). That branch is not in this checkout, and in the owner's clone
`origin` is the fork, so the rebase goes onto this repository's default
branch under whatever name their clone gives it, and the force-push goes
to the fork.

A repository can be set to delete head branches itself (`Automatically
delete head branches`); both had it off on 2026-09-23, and it is a
setting, which changes without this file changing. There GitHub deletes
the branch at the merge and retargets the stacked PRs to the default
branch on its own. The script then prints `origin/<branch> is already
gone` and, for each PR it listed before the merge, `GitHub retargeted #NN
(<its branch>) to <default> when it deleted <branch>` with the same lines:
those PRs carry the merged PR's commits just the same.

A PR that is already merged skips straight to that cleanup, the retargeting
included, and needs no method (`--rebase goes unused: ...` when one was
passed).

## 2. If it stops

When the script stops, its last line starts `error:` and names what
stopped it, and nothing after that point ran. Tell the user that line and
what would clear it. A line starting `error:` or `fatal:` above the last is
git's or gh's own: it may say more about why, but it is not where the
script stopped. Do not work around it yourself:
- no `gh pr merge --admin` past a failing or pending check;
- no force-push or rebase to catch a branch up;
- no discarding local changes or local commits to get a clean tree;
- no switching to the other merge method to get past a refusal: which
  method lands is the repository's rule, and its settings are the user's;
- no `git push origin --delete` of a branch the script kept. That closes the
  PRs still based on it or coming from it, which is the one thing here that
  cannot be undone with a click, or loses a push the merge did not take.

Each of those is the user's decision. Two refusals are yours to clear:
- a merge state GitHub had not worked out yet (`not mergeable yet (merge
  state UNKNOWN)`) clears on its own; running the script once more after a
  moment is fine;
- `allows both squash and rebase merges; pass --squash or --rebase` means
  no method was passed. Run it again with the one CLAUDE.md implies.

`--rebase asks for a rebase merge, and <repo>'s settings do not allow one`
(or the same for `--squash`) is the user's: the method CLAUDE.md implies is
turned off in the repository's settings.

If it stopped after the merge (`could not switch to ...`, `could not
fetch <default>`, `could not fast-forward <default>`, or a warning about
retargeting a PR or deleting a branch), the PR is merged. Say that
plainly, then say which cleanup step is left. When it kept origin's
branch, the last line reads `Done except origin/<branch>: ...`, and the
`Keeping origin/<branch>:` line above it, or the `warning: could not
delete origin/<branch>` line with git's own lines under it, says why. The
step left is the user's:
- still the base of a PR: retarget the PRs the line names (`gh pr edit <n>
  --base <default> -R <owner>/<repo>`), then run the script on the merged
  PR again, which deletes the branch;
- the head of an open PR: once that PR is merged or closed, running the
  script on the merged PR again deletes the branch;
- origin's branches could not be listed: nothing was retargeted or
  deleted; once origin answers, running the script on the merged PR again
  does the rest of the cleanup;
- moved off the merged head (`it is at <sha>, not at <sha>`), or the lease
  refused the delete (`(stale info)` in git's lines): the branch holds a
  push the merge did not take. What becomes of it is the user's call, and
  a second run keeps it;
- the delete failed for another reason, which git's lines under the warning
  name (the network, permissions), with the branch still at the merged
  head: once that is cleared, running the script on the merged PR again
  deletes it.

## 3. Tell the user

Keep it short:
- the PR merged, squashed or rebased, with where the method came from
  (`asked for with --rebase`), and its merge commit (`merged as ...`), or
  that it was already merged;
- each stacked PR it retargeted to the default branch, or that GitHub
  retargeted when it deleted the branch (`GitHub retargeted #NN ...`), by
  number, with the lines the script printed for it, and that they are
  theirs to run (the fork's owner's, for a PR from a fork) before that PR
  merges;
- which branches were deleted, and any the script kept and why (it keeps a
  local branch that is checked out in another worktree, and origin's branch
  while an open PR is still based on it or comes from it, when a push
  landed on it after the merge, when origin's branches could not be
  listed, or when the delete failed);
- when it detached this checkout, that the default branch is still to be
  pulled in the worktree the line names;
- the line `Done: <default> at ...` (`Done: origin/<default> at ...` when
  detached), or `Done except origin/<branch>: ...` when it kept origin's
  branch, with what the user has to do about it.

For a dry run, say that nothing changed and list what it would have done,
the method, the PRs it would retarget and the lines each would need
included.
