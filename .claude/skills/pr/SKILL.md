---
name: pr
description: Open a pull request for this branch, in order - check the README contract where CLAUDE.md sets one, write the case the change owes (the coverage skill), run the suite, commit the case, carry the change across to a repository CLAUDE.md keeps in sync, draft the title and body to CLAUDE.md's PR conventions with the suite's tally, push the branch, open the pull request. Only when the user types /pr.
argument-hint: "[title, optional]"
disable-model-invocation: true
allowed-tools: Bash(git symbolic-ref --short refs/remotes/origin/HEAD), Bash(git fetch origin master), Bash(git fetch origin main), Bash(git merge-base *), Bash(git rev-parse *), Bash(git branch --show-current), Bash(git remote get-url origin), Bash(git status --short), Bash(git add source/test/gpr_conversion_tests.cpp), Bash(git commit -F build/pr/case-msg.txt -- source/test/gpr_conversion_tests.cpp), Bash(git push -u origin HEAD), Bash(gh pr list *), Bash(gh pr create -R *), Bash(cmake -S . -B build), Bash(cmake -S . -B build -DCMAKE_BUILD_TYPE=Release), Bash(cmake --build build -j), Bash(cmake --build build --target gpr_tools_tests), Bash(cmake --build build --target gpr_tools_tests -j), Bash(ctest --test-dir build), Bash(ctest --test-dir build --output-on-failure), Bash(ctest --test-dir build --output-on-failure -C Release), Bash(ctest --test-dir build --output-on-failure -C Debug)
---

# Open a pull request, with its test already in it

Opening a pull request here has an order, and the pieces depend on each
other: the case the change owes is written first, because the suite's tally
after it is the verification line the body has to carry, and the body is
written before the push, because the push is what starts CI. Done as
separate steps from memory, the case is the one that gets skipped. Where CI
has a test-gap pass (gpraw/gpr), that pass then spends its turn budget on
the runner writing it; with the case in the branch, it reads the diff and
says so. Where there is none (adeelabbas/gpr), the case is simply missing.

Two steps apply only where CLAUDE.md asks for them, and adeelabbas/gpr's
does: a README section kept as a contract with the code, and the
cherry-pick into gpraw/gpr before the pull request opens. Both are read
from CLAUDE.md, never assumed, so in a repository whose CLAUDE.md asks for
neither they do nothing.

The judgment - the case, the title, the body - is the session's. The
mechanical half is small enough to be a few commands. Nothing here is
force-pushed, rebased or admin-merged: where a check below fails, stop and
say so, and leave the decision to the operator.

All paths below are relative to the repository root.

## 1. Check before anything changes

- This repository on GitHub: `git remote get-url origin` prints
  `git@github.com:<owner>/<repo>.git` or
  `https://github.com/<owner>/<repo>.git`, and `<owner>/<repo>` below is
  that pair without `.git` (`<host>/<owner>/<repo>` when the host is not
  github.com). Every `gh` command here names it with `-R`, because in a
  clone of a fork a bare `gh` resolves to the fork's parent: from a
  `gh repo clone adeelabbas/gpr` checkout, which adds gopro/gpr as
  `upstream`, `gh pr create` would open the pull request on gopro/gpr.
- The default branch (`master` in adeelabbas/gpr, `main` in gpraw/gpr):
  `git symbolic-ref --short refs/remotes/origin/HEAD` prints
  `origin/<default>`. When it fails, `gh repo view <owner>/<repo> --json
  defaultBranchRef --jq .defaultBranchRef.name` names it. `<default>`
  below is that name.
- On a branch, and not the default branch: `git branch --show-current`.
  On the default branch, or on no branch at all, stop.
- `git fetch origin <default>`. Then `git merge-base --is-ancestor
  origin/<default> HEAD`. When it fails the branch is behind the default
  branch. That does not stop the pull request, but say so in the report:
  where branch protection requires branches to be up to date, GitHub
  reports the pull request `BEHIND` and `/merge` refuses it; where it does
  not, the merge would go through on a combination CI never built. Which
  it is, the pull request's `mergeStateStatus` says once it is open.
  Catching it up is the operator's call, not this skill's. `<base>` below
  is `git merge-base HEAD origin/<default>`.
- No open pull request for this branch already: `gh pr list -R
  <owner>/<repo> --head <branch> --state open`. When there is one, stop
  and name it; edit it rather than open a second.
- Uncommitted edits. `git status --short` lists them. Edits to
  `source/test/gpr_conversion_tests.cpp` left by an earlier `/coverage` run
  are expected and are committed in step 4. Anything else uncommitted is
  the operator's: stop and list it, and let them commit it or say to leave
  it out. Do not commit someone's half-finished edit into a pull request.

## 2. The README contract

When CLAUDE.md makes a section of `README.md` a contract with the code -
adeelabbas/gpr's "About this fork", which must always match the delta
against upstream - decide whether this change is one CLAUDE.md says must
update it (there: a user-visible behavior, a public API entry point, a
`gpr_tools` option or a build switch added, removed or changed). Then read
the section as the branch leaves it. `git diff --name-status <base>` shows
whether the branch touched `README.md`; the section itself shows whether
what it says is now true. That `git diff` prompts, as in `/coverage`: a
rule wide enough to take any base would also take `--output=<file>`,
which writes wherever it points.

- No update needed: the body says so, with the reason, in a line.
- Updated by the branch: the body says so.
- An update needed that the branch does not make: stop here, before
  anything is committed, and say what the section is missing - which
  behavior, and which bullet it belongs under. Do not write it unasked:
  the section is the repository's public description, and its wording is
  the operator's. A reviewer treats a stale section as blocking, so the
  pull request would only come back.

When CLAUDE.md sets no such contract, skip this step.

## 3. The case

Follow `.claude/skills/coverage/SKILL.md`, steps 1 to 3, as written there,
with `<base>` from step 1 as the base: this skill's argument is a title,
not a base ref. Find the change, decide what it owes against CLAUDE.md's
"Testing standards", write the case as `brief.md` says, build, and run the
suite until green. When the change is already covered, still run the suite
once: the tally is the body's verification line. When it touches nothing
the suite compiles - `scripts/`, `.github/`, `.claude/`, the docs - do not
run it; the verification line is then what was checked instead (`bash -n`
on a changed script), as the commits on such branches already do.

Keep the tally line exactly as printed.

## 4. Commit the case

When a case was written, commit that file - and only that file - as one
commit ahead of the push. Its subject is an imperative sentence naming the
behavior now covered; its body says what the case asserts, against what
ground truth, and ends with the tally. That is the shape CI's own test-gap
commits take, and it is a code commit, so step 5 carries it across with
the rest. Write the message to `build/pr/case-msg.txt` (`build/` is
gitignored), then:

    git add source/test/gpr_conversion_tests.cpp
    git commit -F build/pr/case-msg.txt -- source/test/gpr_conversion_tests.cpp

Type the commit exactly so; it is the one form pre-approved, and any other
prompts. The pathspec is what keeps it to the case: a commit that names its
paths takes only those, whatever else is staged or edited, so the
operator's own edit stays out of it (measured with another file edited and
staged: the commit held the case alone, and the other file was still
staged after it). `-a`, `--all` or a wider pathspec would take that edit
along.

A case that did not go green is not committed. `/coverage` has already
taken it back out; the body in step 6 says what it would have asserted and
why it failed, the way CI's pass does when it cannot land one.

## 5. Carry the change across

When CLAUDE.md says a change lands here first and is cherry-picked into
another repository before its pull request opens - adeelabbas/gpr's rules
for keeping the repositories in sync, which name gpraw/gpr - do what it
says, in a scratch tree of that repository, and nothing more. When it says
nothing of the kind, skip this step.

1. The code commits. `git log --reverse --no-merges --format='%h %s'
   --name-only <base>..HEAD` lists each commit with its files. A code
   commit is any that is not only `README.md`, `CLAUDE.md` or `.github/`
   edits; those stay here, since each repository keeps its own. A commit
   that mixes the two breaks CLAUDE.md's rule to keep them apart: carry it
   with the code, and say so, since its documentation half is the likely
   conflict. With no code commits there is nothing to carry; the body says
   so, and this step ends.
2. The other repository's clone. Look beside this checkout's main worktree
   (the first line of `git worktree list`) for a directory whose
   `.git/config` gives `origin` as that repository, over ssh or https; read
   the file rather than running git in it. With none, or more than one,
   ask the operator for the path and wait. Its default branch:
   `gh repo view <its owner>/<its repo> --json defaultBranchRef --jq
   .defaultBranchRef.name`, or, when `gh` cannot read that repository,
   `git -C <clone> symbolic-ref --short refs/remotes/origin/HEAD`, which
   prints `origin/<its default>`.
3. A scratch worktree of it, at its default branch as origin has it:

       git -C <clone> fetch origin
       git -C <clone> worktree add --detach <root>/build/carry/<branch> origin/<its default>

   `<root>` is this checkout's top level (`git rev-parse --show-toplevel`).
   The path must be absolute, since `-C` resolves a relative one inside the
   clone, and it sits under `build/`, which is gitignored here. `<tree>`
   below is that path.
4. Bring the commits over, and apply them oldest first:

       git -C <tree> fetch <root> <branch>
       git -C <tree> cherry-pick <sha> ...

   A conflict is a finding, not something to resolve here:
   `git -C <tree> cherry-pick --abort`, and note which commit stopped and
   on which files. CLAUDE.md asks for commits that touch only lines the
   two trees share, so a conflict usually means one does not.
5. Build and run that repository's suite in `<tree>` as its own CLAUDE.md
   says (`<tree>/CLAUDE.md`, "Build and test"), and keep its tally line as
   printed. It is a cold build: most of it is the vendored DNG SDK and XMP
   core. When the carried commits touch nothing its suite compiles, do not
   run it; that they applied cleanly is the result. When this repository's
   CLAUDE.md asks for outputs compared byte for byte (adeelabbas/gpr: a
   port from gpraw/gpr, or a change that should leave output unchanged),
   make that comparison as it says, with both builds at hand, before the
   tree goes; when it cannot be made here, the body says it is owed.
6. Remove the scratch tree: `git -C <clone> worktree remove <tree>`. It
   refuses only over files the build left that the tree does not ignore;
   then add `--force`, since the tree is this skill's own.

None of this pushes, and none of it touches the clone's own checkout or
branches. The `git -C` commands and the build in `<tree>` act on another
repository, and the search for the clone reads outside this one, so they
prompt; that is expected. So does `git log`, in step 5.1 and in step 6: a
`git log *` rule would admit `--output=<file>`, which writes anywhere, so
it is not pre-approved. A conflict or a red suite in `<tree>` does not
stop the pull request: the body states the outcome either way, and what
to do about it is the operator's call.

## 6. Title and body

Read `git log --format=%B <base>..HEAD` first: the commit bodies already
follow the three-part shape, and the pull request is a synthesis of them,
not a fourth telling.

The title is `$ARGUMENTS` when given. Otherwise write one to CLAUDE.md's
"PR and commit conventions": an imperative sentence naming the outcome,
with an optional `component:` prefix. No `(#NN)`: a squash merge adds it,
and a rebase merge lands the commits under their own subjects, not the
title.

The body follows the same section, in plain ASCII wrapped near 72 columns:

1. What was wrong and why it mattered, at mechanism level.
2. What the change does, as bullets, including the fallback or safety
   behavior and anything that changes for existing callers.
3. Verification against a reference: the tally from step 3, plus any
   measured timing, size or before/after figure the commits recorded, and
   whatever else that section asks for (adeelabbas/gpr: the build-flag
   matrix, and the byte-for-byte comparison where output should not
   change). What was not run is said to be not run - CI's `build-flags.yml`
   runs the matrix - never implied.

Then, when they apply, each in its own line: the README contract from
step 2, updated or not needed and why; the carry-across from step 5, the
commits cherry-picked onto which commit of which repository, cleanly or
where it conflicted, and that suite's tally; the case `/coverage` proposed
but could not land, with what it saw. Where CLAUDE.md's conventions require
the first two in every body, as adeelabbas/gpr's do, they are there even
when the answer is that nothing was needed.

Write the body to `build/pr/<branch>.md` - `build/` is gitignored - and
read it back once as a reviewer would.

## 7. Push and open

    git push -u origin HEAD
    gh pr create -R <owner>/<repo> --base <default> --head <branch> --title '<title>' --body-file build/pr/<branch>.md

The push is a plain push. A refusal means origin's branch has commits this
checkout does not; stop and say so rather than forcing it.

Opening the pull request starts whichever of `build-flags.yml`,
`claude-review.yml` and `claude-test-gap-check.yml` the repository has
under `.github/workflows/`, each where its own trigger (`on:`) admits the
change; adeelabbas/gpr has only the first. That is expected; where the
test-gap pass runs, with the case already in the branch it should report
the coverage adequate and commit nothing.

## 8. Tell the user

Keep it short:

- the pull request URL and its title;
- the coverage outcome: the case committed (its name), the existing case
  that already covered it, or the case proposed and why it did not go green;
- the tally line;
- the README contract, where CLAUDE.md sets one: updated, or not needed;
- the carry-across, where CLAUDE.md asks for one: applied cleanly, with the
  other suite's tally, or the commit that conflicted;
- whether the branch is behind the default branch, when it is.
