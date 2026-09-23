---
name: coverage
description: Write the test case this branch's change owes, to CLAUDE.md's Testing standards, and prove it green in the local suite. Reads the diff from the default branch, uncommitted edits included. Commits nothing, pushes nothing, posts nothing. Only when the user types /coverage, or as a step of /pr.
argument-hint: "[base ref, default the merge base with the default branch]"
disable-model-invocation: true
allowed-tools: Bash(git symbolic-ref --short refs/remotes/origin/HEAD), Bash(git merge-base *), Bash(git rev-parse *), Bash(git branch --show-current), Bash(cmake -S . -B build), Bash(cmake -S . -B build -DCMAKE_BUILD_TYPE=Release), Bash(cmake --build build -j), Bash(cmake --build build --target gpr_tools_tests), Bash(cmake --build build --target gpr_tools_tests -j), Bash(ctest --test-dir build), Bash(ctest --test-dir build --output-on-failure), Bash(ctest --test-dir build --output-on-failure -C Release), Bash(ctest --test-dir build --output-on-failure -C Debug), Bash(./build/source/test/gpr_tools_tests *)
---

# Write the case a change owes

This is the local half of CI's test-gap pass, run here before the pull
request exists instead of on the runner after it does. Where the
repository has that pass (`.github/workflows/claude-test-gap-check.yml`,
in gpraw/gpr), the two read the same brief, `brief.md` beside this file,
so what counts as coverage is decided once. The difference is what happens
to the case: the runner commits a green case to the branch and posts a
comment; this skill leaves it in the working tree for the operator to
commit with the change, and reports. Where the repository has no such
workflow (adeelabbas/gpr), this is the only pass a change gets, and the
case it writes is the only one the pull request will carry.

Why here: the runner starts cold, and a pass that has to write the case
configures, builds, finds the path the change moved and runs the suite
before it can write anything. On gpraw/gpr#38 that reached the job's
100-turn cap at 18m43s with no comment posted; the cap is 200 since. The
session that made the change already knows most of what those turns are
spent learning. When the case is already in the pull request, that pass
reads the diff, says the coverage is adequate, and is done.

All paths below are relative to the repository root.

## 1. Find the change

The base is `$ARGUMENTS` when given, otherwise the merge base with the
default branch (`master` in adeelabbas/gpr, `main` in gpraw/gpr). Ask git
which that is rather than assuming it:

    git symbolic-ref --short refs/remotes/origin/HEAD
    git merge-base HEAD origin/<default>

The first prints `origin/<default>`. When it fails, in a clone whose
`origin/HEAD` was never set, `gh repo view --json defaultBranchRef --jq
.defaultBranchRef.name` names the branch. The merge base is taken with
origin's copy, which `/pr` fetches first; a local one may not have been
pulled.

The change is everything from there to the working tree, uncommitted edits
included: `git diff --name-status <base>` lists it, and `git status
--short` adds the new files git does not track yet. That `git diff` will
prompt, which is fine: a rule wide enough to take any base would also take
`--output=<file>`, which writes wherever it points. Read the changed files
themselves rather than a diff dump; the diff says what moved, the file says
what it now does. If nothing is listed, say so and stop.

## 2. Decide what the change owes

Read `brief.md`, then CLAUDE.md's "Testing standards" section. The rule is
there: the paragraph that says which changes add or extend a case in the
same pull request. A pure refactor that keeps output byte-identical owes
nothing here, and neither does a change under `scripts/`, `.github/` or
`.claude/` alone.

Look for the case before writing one. The change may already be covered by
a case that reads the same path. When it is, the answer is "already
adequate", with the case named.

## 3. Write it, and prove it

Follow the brief: the right `run_*` group function, the existing validator,
the neighbors' naming, determinism, an independent ground truth, and,
where CLAUDE.md keeps this repository in sync with another, a case written
so that it carries across and needs no fixture that lives only there.

Then build and run with the commands in CLAUDE.md's "Build and test"
section. The two gpr repositories spell the configure and the build
differently; `brief.md` gives both, and this skill pre-approves both,
spelled as there and in CLAUDE.md. Another spelling may prompt: a wildcard
on `cmake` or `ctest` would also admit the flags that write outside the
tree. Run the suite binary directly, as the brief says: it prints the
tally, which a green `ctest` run does not. Iterate until the suite is
green, and keep the tally line.

If the case will not go green, do not leave it red in the tree, and do not
revert any file: the operator's own edits may be in it. Take out only the
lines you added, then describe the case you would have written and why it
did not pass. That is a finding for the report, and sometimes for the
change itself, when the test found a defect. Say which.

## 4. Do not

Do not commit, push, label or post anything; `/pr` commits the case with
the change, and CI's pass, where there is one, posts its own result. Do not
re-run the suite after it has gone green to be sure, and do not run the
build-flag matrix: CI's `build-flags.yml` runs it on the pull request. Do
not review the change against CLAUDE.md's review standards; that is
`/review`.

## 5. Report

Short, and in this order:

- what the change owes, in a sentence: a case, or nothing;
- the case: its name as `run_case` records it, the group function it sits
  in, and what it asserts against what ground truth; or the existing case
  that already covers the change;
- the suite's tally line as printed (`Cases run: N failed: 0 ...`);
- a case that did not go green: what it asserted and what it saw.

Then the operator commits it, or `/pr` does.
