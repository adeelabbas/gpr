---
name: next
description: Say what has to be done next, in order, from the whole context - this conversation, the working tree, the branch's pull request and its CI, the other open pull requests, and what CLAUDE.md says is owed to the repositories this one is kept in sync with. Reads only; runs no step itself. Only when the user types /next.
argument-hint: "[focus, optional - e.g. a PR number, 'sync', or a question]"
disable-model-invocation: true
allowed-tools: Bash(git branch --show-current), Bash(git symbolic-ref --short refs/remotes/origin/HEAD), Bash(git fetch origin master), Bash(git fetch origin main), Bash(git fetch --quiet https://github.com/gopro/gpr.git master), Bash(git merge-base *)
---

# What comes next

The operator wants the next steps, ordered, with the reason for each and
the exact command to run it. `$ARGUMENTS`, when given, narrows the focus
(a PR, the sync with another repository, a question), but still read the
whole state: a step elsewhere can block the one asked about.

This skill **reads only**. It runs no step it recommends: no commit, push,
merge, cherry-pick, label, review, build, or anything else that changes a
file or GitHub. The operator's `/next` is a question, and the answer is a
list. When a recommended step is itself a slash command (`/coverage`,
`/pr`, `/review`, `/merge`), name it; the operator types it.

This file is the same in adeelabbas/gpr and gpraw/gpr. What differs
between them - the default branch, which workflows exist, which
repositories this one is kept in sync with - is read at run time from the
checkout, from GitHub and from CLAUDE.md, never assumed.

All paths below are relative to the repository root.

## 1. The conversation comes first

Before running anything, reread this session from the start. It holds what
no command can show:

- what the operator set out to do, and whether it is finished;
- decisions they made or left open ("no backup model for now", "keep the
  variable"), and anything asked of them that they have not answered;
- what this session said it would do, or offered to do, and has not;
- caveats already raised (a check that goes green with nothing behind it, a
  branch behind the default branch, a skipped step, a cherry-pick not yet
  tried), which still apply until resolved;
- work that was done but not verified, or verified on a different tree
  than the one that will ship.

A step the conversation already settled is not re-proposed, and a decision
the operator already made is not reopened.

When the session is fresh and there is no conversation, say so and work
from the state alone.

## 2. Read the state

Run these; each is read-only. The `gh` and `git status`-style reads are
already in `.claude/settings.json`, and this skill pre-approves only what
that allowlist lacks, so the two never have to be edited together. The
rest will prompt, which is fine. Do not use `git log` with a bare wildcard
of flags; name the range and the format.

Read CLAUDE.md too, for two things: whether it names repositories this one
is kept in sync with, and whether it makes a section of README.md a
contract. Find both by heading, never by number; the two gpr repositories
number their CLAUDE.md sections differently.

**Default branch and workflows**

- `git symbolic-ref --short refs/remotes/origin/HEAD` prints
  `origin/<default>`: `origin/master` in adeelabbas/gpr, `origin/main` in
  gpraw/gpr. In a clone where `origin/HEAD` was never set it fails; then
  `gh repo view --json defaultBranchRef --jq .defaultBranchRef.name`.
  `<default>` below is that name.
- Which of `build-flags.yml`, `claude-review.yml` and
  `claude-test-gap-check.yml` this repository has is a listing of
  `.github/workflows/`; read it with the file tools. gpraw/gpr has all
  three, adeelabbas/gpr only the first. A result from a workflow the
  repository does not have is not missing; it is not owed.

**Working tree and branch**

- `git branch --show-current`, `git status` (ahead/behind its upstream),
  `git status --short`.
- `git fetch origin <default>`, typed exactly as `git fetch origin master`
  or `git fetch origin main`, which is what the pre-approval matches. Then
  `git merge-base --is-ancestor origin/<default> HEAD`: when it fails the
  branch is behind the default branch. Where the default branch requires
  branches to be up to date (gpraw/gpr's `main`), GitHub reports `BEHIND`
  and `/merge` refuses; where it does not (adeelabbas/gpr's `master` has no
  branch protection), the merge would go through on a tree CI never built.
- `git worktree list`: other sessions' worktrees live under
  `.claude/worktrees/`. Another checkout on the same branch, or files
  changing that this session never touched, means another session is
  working here. It also prints each checkout's commit, which is what to
  compare with the PR's `headRefOid` below.

**This branch's pull request**, when there is one:

    gh pr view --json number,title,url,state,isDraft,baseRefName,headRefOid,mergeable,mergeStateStatus,statusCheckRollup,labels,files,comments,body

- **CI**: the gate is `.github/workflows/build-flags.yml`, the flag
  matrix: every check whose `workflowName` is `Build flag matrix`. Today
  that is `build-flags (ubuntu-latest)` and `build-flags (macos-latest)` in
  adeelabbas/gpr, `build-flags-x86` and `build-flags-arm64` in gpraw/gpr.
  `gh pr checks <n> --required` names the ones branch protection requires
  (`build-flags-arm64` in gpraw/gpr, none in adeelabbas/gpr); it exits
  non-zero when there are none, when one failed, and while one is pending,
  so read what it prints. `/merge` merges only on `CLEAN` (or
  `HAS_HOOKS`): a required check that failed or is still pending makes it
  `BLOCKED`, and any other check that has not passed makes it `UNSTABLE`. For a failure,
  `gh run view <id> --log-failed` shows why; read it before recommending a
  fix.
- **A matrix that never starts**: it runs only on the paths it watches (C
  and C++ sources and headers, a `CMakeLists.txt`,
  `scripts/test_build_flags.sh`, and `build-flags.yml` itself - every
  workflow, in gpraw/gpr), since nothing else can break a flag
  configuration. Where no check is required, a PR that touches none of
  them has no matrix check at all, and that is neither a failure nor a
  wait. Where one is required, such a PR never gets it and sits `BLOCKED`
  for good - `build-flags.yml`'s comment on its paths tells how gpraw/gpr#39
  did - so that is a decision for the operator, not something to wait out.
- **Divergence**: when `headRefOid` is not this checkout's commit, the two
  have moved apart. A head ahead of the checkout, typically a case the
  test-gap pass committed, means pulling it (`git pull --ff-only`) is the
  first step to recommend, before any edit. A checkout ahead of the head
  means commits not pushed yet.
- **Test gap**: only where the repository has
  `claude-test-gap-check.yml` (gpraw/gpr). Its result is the one comment
  whose body starts with `<!-- gpr-claude-test-gap -->`; a comment that
  only quotes the marker is not a result. Its check is `test-check`, and it
  runs only when the PR touches C or C++ sources, a `CMakeLists.txt` or
  `.claude/skills/coverage/brief.md`. If the PR's `files` include
  `.github/workflows/claude-test-gap-check.yml`, no comment will come and a
  green check means nothing: the action skips itself on a PR that edits its
  own workflow. `/review` settles the `needs-coverage` label, so do not
  recommend it by hand. `test-check` skipped on a commit the pass pushed
  itself is expected; the run that pushed it already said what it covers.
  Where the repository has no such workflow (adeelabbas/gpr) there is
  nothing to wait for: `/coverage` is the only test-gap pass a change gets
  there.
- **CI's review**: only where `claude-review.yml` exists (gpraw/gpr). Its
  check is `review` and its comment starts with `<!-- gpr-claude-review -->`,
  and it skips itself the same way on a PR that edits its own workflow. It
  is one model's read of the diff, with nothing that tries to refute it, so
  it does not stand in for `/review`. Name a blocking finding it raises;
  the `/review` comment is still the one the merge waits on.
- **Review**: the `/review` comment starts with `<!-- gpr-dual-review -->`.
  Its heading, "Review of `<sha>` by N models", names the reviewed commit by
  its first seven characters, so compare that prefix with `headRefOid`, not
  the whole sha. When the head moved while the review ran, the script has
  already said so in the comment ("The pull request has moved to ...
  since"); no comment, that sentence, or a heading that is not the head's
  prefix means the head is unreviewed. Blocking findings in it come before
  the merge; design findings are the operator's call, so list them as a
  decision, not as a step.
- **Mergeability**: `mergeStateStatus` other than `CLEAN` or `HAS_HOOKS`
  (`BEHIND`, `BLOCKED`, `DIRTY`, `UNSTABLE`), a draft, or a base other than the
  default branch each stop `/merge`.

**Everything else open**

    gh pr list --state open --json number,title,headRefName,baseRefName,isDraft,updatedAt

- PRs stacked on this branch (base is this branch) land after it; `/merge`
  retargets them to the default branch once this one is in.
- Where the default branch is strict (gpraw/gpr's `main` requires
  `build-flags-arm64` on an up-to-date branch, and that leg is one
  self-hosted runner), several ready PRs land one at a time, each catching
  up to `main` and rerunning the matrix before its merge.

**Keeping the repositories in sync**

Only when CLAUDE.md names repositories this one is kept in sync with, or
makes a section of README.md a contract; when it does neither, skip this
part. Each of its rules that a merge here, or a move in one of those
repositories, can leave owing is a step. In adeelabbas/gpr it does both
(`The three repositories, and keeping them in sync`, and `README.md: the
"About this fork" section is the contract`), and they owe four things:

- **A merged change owes its cherry-pick downstream.** List what merged
  here:

      gh pr list --state merged --limit 10 --json number,title,mergedAt,files

  Leave out a PR whose files are only README.md, CLAUDE.md or under
  `.github/`; those edits stay here by the same rule. For the rest, newest
  merge first, look for each in gpraw/gpr by title:

      gh pr list -R gpraw/gpr --state all --search "<title> in:title" --json number,title,state

  and stop at the first one found. Cherry-picks go across in merge order,
  and an older change can have come the other way, borrowed from
  downstream, which a title search would read as owed. A cherry-pick can
  also carry another title, or several changes in one PR, so before
  calling one owed, read the titles gpraw/gpr opened since it merged here
  (`--search "created:>=<mergedAt date>"`). The step, once owed: in a
  gpraw/gpr checkout, on a new branch from its `origin/main`, fetch the
  PR's own commits (`git fetch <this repository's url> pull/<n>/head`) and
  cherry-pick those that are not only README.md, CLAUDE.md or `.github/`
  edits - the selection `/pr` makes in its carry-across step - then `/pr`
  there. They are taken from the PR rather than from `<default>` so the
  step is the same however `/merge` merged it: a rebase merge puts each
  commit on `<default>` as it was, but a squash would fold the README edit
  into the code. gpraw/gpr is private; when `gh` cannot read it, say so and
  leave this unchecked.
- **A change downstream can be owed here.** CLAUDE.md's "Borrow from
  downstream" rule: what merged in gpraw/gpr and applies to writing GPR
  files (the encoder, the DNG writer, their robustness, their tests)
  belongs here as well. List what merged there recently:

      gh pr list -R gpraw/gpr --state merged --limit 10 --json number,title,mergedAt,files

  and look for each here by title, the same way as above. One not found
  here is a decision for the operator, not a step: whether it is about
  writing files, rather than decoder-only work CLAUDE.md keeps out, is
  theirs to say. Name it, with its files.
- **Upstream moving owes a merge here first.** Read upstream from its own
  URL: `git fetch --quiet https://github.com/gopro/gpr.git master`, then,
  before any other fetch rewrites `FETCH_HEAD`,
  `git merge-base --is-ancestor FETCH_HEAD origin/<default>`. When it
  fails, upstream has commits this repository has not merged, and
  `git log --format='%h %s' origin/<default>..FETCH_HEAD` lists them. Never
  read upstream from a branch of `origin` named after it: adeelabbas/gpr's
  `origin/gopro/gpr` is this fork's delta replayed as a clean series onto
  upstream's `master`, the branch offered to GoPro, and it moves only when
  someone pushes it here. The merge goes into `<default>` here first;
  gpraw/gpr then merges this repository.
- **This branch's PR owes the README contract and the cherry-pick
  record.** When the PR adds, removes or changes what the contract
  section covers (in adeelabbas/gpr: a user-visible behaviour, a public API
  entry point, a `gpr_tools` option or a build switch), its `files` must
  include README.md with that section updated. A reviewer treats a stale
  section as blocking, so the update is an edit, and comes ahead of
  `/review`. CLAUDE.md's PR conventions there also want the body to say
  what the cherry-pick onto gpraw/gpr did before the PR opened, and that
  the README section was updated or needed no update. A body that says the
  cherry-pick was not run owes it before the merge: the carry-across check
  `/pr` runs (`.claude/skills/pr/SKILL.md`), by hand, then an edit to the
  body.

Skip what `$ARGUMENTS` makes irrelevant only when it cannot block the
focus. If `gh` is unauthenticated or offline (`gh auth status`), say which
half could not be read rather than guessing at it.

## 3. Decide the order

Put the steps in dependency order, the way CLAUDE.md's routines do:

    edit -> /coverage -> /pr -> CI green (+ the test-gap comment where there is one)
         -> /review -> fix blocking findings -> /merge -> stacked PRs
         -> carry across (cherry-pick downstream, merge upstream)

- Something failing or blocking comes before something new.
- Waiting on CI is a state, not a step: say what is running and what to do
  once it finishes. Do not recommend polling.
- A cherry-pick owed downstream is a step once its PR has merged here. An
  upstream merge is owed too, but it moves the base of every open branch,
  so when to take it is the operator's decision; never put it ahead of an
  open fix the operator is still landing.
- Where the next move is a decision only the operator can make, stop the
  list there and ask it plainly, with the options. Do not plan past a fork.
- Recommend; do not survey. One way forward per step, with the reason.

## 4. Answer

Keep it short:

1. **Where things stand**: two or three sentences - the branch, its PR
   and CI, and anything left over from the conversation.
2. **Next**: a numbered list, most urgent first, usually no more than five.
   Each item: what to do, the exact command or slash command, and the
   evidence that makes it next (the failing check, the unreviewed sha, the
   search that found no cherry-pick, the decision still open).
3. **Decisions for you**, when there are any: what they are and the
   options. Otherwise leave this out.

Cite what you read (PR as a markdown link, `file:line`, a check name), so
each recommendation can be checked without rerunning this.
