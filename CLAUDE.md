# CLAUDE.md

Project context and standards for Claude Code sessions and PR reviews in this
repository.

## What this repo is

A public fork of [gopro/gpr](https://github.com/gopro/gpr), the GoPro RAW
(GPR) SDK: the VC-5 wavelet codec, a C API that converts between GPR / DNG /
RAW / VC5 / RGB, a patched copy of the Adobe DNG SDK 1.4, and the `gpr_tools`
CLI.

The fork carries a deliberately **minimal** set of changes on top of upstream,
all of them in service of writing GPR and DNG files well:

- **enhancements** so capture formats from other sensors encode correctly
  (the BGGR mosaic, large black level and `ActiveArea` crop of an iPhone DNG,
  for example) and so the DNGs the SDK writes render correctly in Apple, Adobe
  and other readers (equalized green gain maps, thumbnails in IFD 0, faithful
  `WarpRectilinear`, lens profiles, embedded previews);
- **bug fixes** (VC-5 memory streams that wrote past their buffer, a fixed
  thumbnail buffer, an out-of-bounds read in the Bayer phase shift, DNG SDK
  exceptions escaping the C API, XMP toolkit data races);
- **code cleanups** that make the API easier to integrate (CMake feature
  options, `gpr_parameters_parse_dng`, one `RGB_PARAMETERS` struct shared by
  encoder and decoder, a contiguous output stream, `gpr_convert_gpr_to_gpr`,
  a test suite and CI).

It is **pure C/C++**: C is pinned to C99 (`CMakeLists.txt`), C++ builds at the
compiler default, and there is no application code. The GPRaw macOS app that
consumes this SDK lives in its own repository and is never reviewed here.

## The three repositories, and keeping them in sync

| Repository | Role |
|---|---|
| `gopro/gpr` (upstream) | Where everything here comes from. This fork must read as a small, reviewable delta on top of its `master`. |
| `adeelabbas/gpr` (this repository) | The public fork: encoder and DNG-writer work meant for GoPro, Apple and other adopters. |
| `gpraw/gpr` (downstream, private) | The GPRaw app's SDK. Carries everything here plus private-only work (multithreaded decoding, a VLC lookup cursor, extra sample fixtures, its own CI). |

**Changes here must stay minimal against both neighbours**, and every change
has to be carried across so the three do not drift. The rules:

- **Land it here first.** Anything that changes what the SDK writes, keeps the
  writer safe, or makes the API easier to use is a PR against `master` here,
  then a cherry-pick into `gpraw/gpr`. Write the commit so that the cherry-pick
  applies without conflicts: touch only lines the two trees share (downstream
  differs in the `thread_count` argument on every `gpr_convert_*`, in
  `source/lib/vc5_decoder/decoder.c` and `vlc.c`, in its sample list and its
  CI), keep README, CLAUDE.md and workflow edits in their own commits, and
  write new tests against the `gpr_tools` conversion layer (`dng_convert_main`)
  rather than against the `gpr_convert_*` signatures. Before opening the PR,
  cherry-pick the code commits onto a scratch branch of a local `gpraw/gpr`
  clone, build, run its suite, and say so in the PR body.
- **The shared tooling moves both ways.** The tracked files under
  `.claude/`, with `scripts/review_pr.sh` and `scripts/merge_pr.sh`, are
  the same in `gpraw/gpr` byte for byte, and they are an exception to
  landing here first: a change to them can start on either side, and is
  made in both repositories in the same bytes, so that it cherry-picks
  cleanly either way. An edit made in one alone makes the two drift. Of
  CI they state only what the routines act on: the three workflow files
  (`build-flags.yml`, `claude-review.yml`, `claude-test-gap-check.yml`)
  and which repository has which, the two Claude workflows' comment
  markers, the `needs-coverage` label and what the test-gap pass does that
  the label rule depends on (when it runs, what cancels it, that it
  commits as `claude[bot]`), and each repository's default branch by name,
  though the scripts ask GitHub for it. Settings they cite, such as the
  merge methods both repositories allowed, carry the date they were read.
  A change to any of those in a workflow is a change to the shared files
  too, made in both. No job or check name, runner, path filter, turn cap
  or branch protection rule is in them: the routines read those at run
  time, from the workflow file's `name:`, `jobs:` and `on:`, from
  `gh pr checks --required` and from the pull request's
  `mergeStateStatus`, so such a CI change in one repository does not touch
  them.
- **Borrow from downstream.** Patterns that already exist in `gpraw/gpr` and
  apply to GPR file writing (encoder features, DNG metadata handling, writer
  robustness, test cases, review findings) belong here as well. Port them
  rather than re-deriving them, and prove the port: build both trees and
  compare `gpr_tools` output over `data/samples` with `cmp`; outputs are
  expected to be byte-identical unless the PR says which ones change and why.
- **Do not bring decoder-only work here** (threading, the VLC cursor, render
  changes that do not affect what the encoder writes) unless a PR says
  explicitly that it does and why.
- **Track upstream.** When `gopro/gpr` `master` moves, merge it into `master`
  here first; downstream then merges this repository.
- **The private fixtures stay private.** `data/samples` holds upstream's six
  files and the suite must pass on exactly those. The HERO13, MISSION 1 PRO
  and iPhone fixtures, and `lena.jpg`, live only in `gpraw/gpr`; a test that
  needs them has to degrade to what ships here (the MISSION 1 PRO lens profile
  is checked through the table lookup, for example).

## README.md: the "About this fork" section is the contract

The section at the top of `README.md` headed **About this fork** lists what
this repository does that upstream does not. **It must always match the
actual delta against `gopro/gpr` `master`.** A PR that adds, removes or
changes a user-visible behaviour, a public API entry point, a `gpr_tools`
option or a build switch updates that section in the same PR, and a reviewer
treats a stale section as a blocking finding. Keep it a list of behaviours in
plain language, grouped the way it is now, not a changelog of commits.

## Layout and ownership

| Path | Status |
|---|---|
| `source/lib/gpr_sdk/public` | First-party. The public C API (`gpr.h`, `gpr_tuning_info.h`, `gpr_lens_profiles.h`, ...). |
| `source/lib/gpr_sdk/private` | First-party. Conversion matrix, DNG bridging, the render helpers, the flat write stream, the lens profile table. |
| `source/lib/common` | First-party. `gpr_platform.h`, the allocator, buffers, log, timer, `jpeg.h`, and the public types shared with the codec (`gpr_rgb_buffer.h`). |
| `source/lib/vc5_common`, `vc5_decoder`, `vc5_encoder` | First-party. The codec. NEON kernels are encoder-only. |
| `source/app/gpr_tools` | First-party. The CLI and `dng_convert_main`, which the test suite also drives. |
| `source/app/vc5_encoder_app`, `vc5_decoder_app` | First-party upstream samples; kept building, otherwise untouched. |
| `source/test` | First-party. The whole test suite, one file. |
| `source/lib/dng_sdk` | **Vendored and forked.** Adobe DNG SDK 1.4 with upstream's patches plus this fork's in `dng_shared.cpp`, `dng_xmp_sdk.cpp`, `dng_image_writer.cpp` and the added `dng_stage1_negative.*`. Edits are legitimate but must be surgical and justified in the PR body. |
| `source/lib/xmp_core`, `expat_lib`, `md5_lib`, `tiny_jpeg`, `source/app/common/cJSON` | Vendored. `xmp_core` carries the locking fix and `tiny_jpeg` the batched writer and 4:2:0 path; otherwise keep diffs minimal and never restyle. |
| `source/app/common/argument_parser` | Mixed: `program_options_lite.*` is vendored ITU/ISO BSD; `argument_parser.*` is first-party. |
| `scripts` | First-party. The build-flag matrix, the conversion pipeline over a folder of samples, the lens-profile fitting tool, and `review_pr.sh` and `merge_pr.sh`, which `/review` and `/merge` run (shared with `gpraw/gpr`). |
| `.github/workflows` | The build-flag matrix on hosted Ubuntu x86_64 and macOS arm64 runners. |
| `.claude/skills`, `.claude/settings.json` | First-party, tracked, and shared with `gpraw/gpr`. The routines Claude Code and Cursor load (`/review`, `/merge`, `/coverage`, `/pr`, `/next`) and the reviewed allowlist. |

Ignore entirely: `build/` (gitignored), anything under `scripts/out` or
`out/`, and `.claude/worktrees/` (other sessions' checkouts, holding their
own copies of the tree: greps will hit them, and they are not the live
source).

## Build and test

```sh
cmake -S . -B build -DCMAKE_BUILD_TYPE=Release
cmake --build build -j
ctest --test-dir build --output-on-failure
```

Add `-C Release` (or `-C Debug`) to the `ctest` line for multi-config
generators (Xcode, MSVC). The test binary also runs directly and takes an
optional sample directory as `argv[1]`:
`./build/source/test/gpr_tools_tests data/samples` (Xcode puts it under a
`Release/` or `Debug/` subdirectory). It prints a per-case log and a final
`Cases run: N failed: 0 ...` line, exiting non-zero if any non-xfail case
failed or crashed.

`scripts/test_build_flags.sh` builds the baseline, each of `GPR_NEON`,
`GPR_READING`, `GPR_WRITING`, `GPR_JPEG_AVAILABLE` and `GPR_TIMING` off on its
own, and all off: seven configure-and-build passes. CI
(`.github/workflows/build-flags.yml`) runs it on `ubuntu-latest` (x86_64,
scalar) and `macos-latest` (arm64, NEON) and then `ctest` on the baseline
build. It is the check most PRs actually trip; reason about the matrix when
reviewing.

## Cursor and Claude Code

`.claude/skills/` and `.claude/settings.json` are tracked;
`.claude/settings.local.json` (per-machine approvals) and
`.claude/worktrees/` are not. Cursor and Claude Code both load
`.claude/skills/`, and Cursor does not load `.claude/commands/`, so the
routines live there and the slash names are the same in either tool. Leave
`CLAUDE.md` under this name: both tools read it, and `scripts/review_pr.sh`
looks it up by this filename.

These files, and `scripts/review_pr.sh` and `scripts/merge_pr.sh`, are the
same in `gpraw/gpr`, byte for byte, so nothing in them assumes which of the
two repositories it is in. What differs is asked at run time: the
repository is origin's (below); git or GitHub names the default branch
(`master` here, `main` there); `.github/workflows/` shows which workflows
exist, and each workflow file its own jobs and triggers; GitHub says which
checks branch protection requires; and this file says what else a change
owes, the merge method included, its sections found by heading, never by
number (the two files number their review standards differently). This
repository has no Claude workflow in CI. `gpraw/gpr` has two, a
single-model review and a test-gap pass, and the routines name them only
to say what happens where they exist.

Every routine works on origin's repository and names it to `gh`. This
repository is a GitHub fork of `gopro/gpr`, and `gh repo clone
adeelabbas/gpr` adds `gopro/gpr` as an `upstream` remote. In such a clone
a bare `gh` resolves to the parent: `gh pr view 11` answered
`gopro/gpr#11` (2026-09-23), so `/review 11 --post` would have reviewed,
and commented on, GoPro's public pull request, and `gh pr create` would
open the pull request there. Both scripts ask `gh repo view` about
origin's url and export `GH_REPO` before they look up a pull request, and
every `gh` command a skill runs on this repository names it, as
`<owner>/<repo>` from `git remote get-url origin` (with `-R`, or as
`gh repo view`'s argument). A checkout with no `origin` stops both
scripts.

- **`/review <pr>`** has `scripts/review_pr.sh` review the PR's head with
  several models at once, on one brief
  (`.claude/skills/review/reviewer-brief.md`), against the review standards
  below. Who reviews is an argument, not code: a reviewer is `<cli>:<model>`
  for one of the three CLIs the script drives (`claude`, `grok`, and
  `gemini` through Antigravity's `agy`), and `--reviewers` takes a list of
  them. With none named the script's `DEFAULT_REVIEWERS` apply, today
  `claude:claude-opus-5-5,gemini:gemini-3.8-flash-high`; Grok 4.7 and
  Claude Fable 5.1 review only when named. The standard is the base
  branch's `CLAUDE.md`. The head's copy is moved to `head-CLAUDE.md`
  before any reviewer runs, and every other file or directory the three
  CLIs load as instructions (`AGENTS.md`, `GEMINI.md`, `CLAUDE.md` and
  their variants, and rules directories such as `.claude/rules` and
  `.gemini`) is taken out of the checkout at every depth, because Grok
  loads one it finds while reading and a deeper file overrides the one it
  was given. Every symbolic link is taken out as well, whatever its name:
  a link in the head can reach any directory on the machine, and through
  it a reviewer could read, and quote in a posted review, whatever is
  there. A link goes as a link, never followed to what it points at, and
  the diff still carries every edit and each link's target. No reviewer
  can run a command or write a file, so before they start the script
  checks that each changed shell or Python file still parses and hands
  the answers over as `checks.md`. A changed path that is a symbolic link
  is named there and not parsed, since the parser would read whatever it
  points at, and one inside a directory taken out above is named as taken
  out, not parsed. The brief has each reviewer search the tree for
  every other copy of a fact the diff changes (a stale "About this fork"
  section among them), and read the change a second time against "Minimal
  diff, and in sync" for design findings, each of which needs a precedent
  at `file:line` and a named cost.

  A reviewer whose CLI is not installed, or a Claude or Grok reviewer whose
  subscription allowance is spent, is skipped and says so, and the rest go
  on; one that fails otherwise is a failure, which `--only <cli>:<model>`
  re-runs alone against the same head before reconciling again. After
  every run a Claude model reconciles the reviews that finished, headless
  and read-only (`claude -p` under
  `--restricted`, with Read, Grep and Glob only, on
  `.claude/skills/review/reconciler-brief.md`), trying to refute every
  blocking finding before it confirms one, a finding every reviewer agrees
  on included. That model is `claude-opus-5-5` unless `--reconciler` names
  another, with no fallback unless `--reconcile-fallback` names one, since a
  second run of the same model would draw on the same spent allowance. Its
  report becomes `summary.md` only when the run finished on the model asked
  for, has a Blocking section and ends with `END OF REPORT`;
  `--reconcile <pr>` repeats only that step, on the reviews already there.
  `--post` posts the report as one standing comment
  (`<!-- gpr-dual-review -->`), with every full review collapsed below it,
  and a later run edits it in place: the newest comment that starts with
  the marker and was written by the account `gh` runs as. On a public
  repository anyone can post a comment that starts with the marker, and
  one by another account is neither edited nor taken for this command's.
  `GPR_REVIEW_NO_POST=1` makes `--post` a rehearsal that changes nothing
  on GitHub. The `needs-coverage` label it settles in `gpraw/gpr` starts
  `claude-test-gap-check.yml`, which this repository does not have: the
  script finds no such workflow on the base branch, leaves the label
  alone, and its `label:` line says there is no test-gap pass to start.
  The script is not in the allowlist: it posts to GitHub and sends the
  diff to every reviewer's company (Anthropic and Google by default, xAI
  when Grok is named). The skill pre-approves it only while `/review`
  runs. It pins `gh` to origin's repository before it looks up the PR, so
  a number is always one of this repository's pull requests; a URL still
  takes `gh` wherever it points, and one that names a pull request in
  another repository is refused before anything is checked out.
- **`/merge <pr>`** has `scripts/merge_pr.sh` merge the PR into the default
  branch and clean up after it. Its one `gh repo view` call, on origin's
  url, names the repository and its default branch, and pins every later
  `gh` call to that repository before any PR is looked up; every message
  prints the default branch GitHub gave. The method is an option,
  `--rebase` or `--squash`, and the skill passes the one this file
  implies: here `--rebase`, since "Land it here first" keeps README,
  CLAUDE.md and workflow edits in commits of their own, and a rebase merge
  lands each commit with its own message where a squash would fold them
  into the code commits `gpraw/gpr` cherry-picks. With no option the
  script takes the one of the two the repository's settings allow when
  they allow exactly one, and otherwise refuses an open PR; both
  repositories allowed every method on 2026-09-23. GitHub's merge-button
  default (`viewerDefaultMergeMethod`) does not decide it: that is per
  user, the method the `gh` user last clicked, and a merge by the wrong
  method cannot be undone. The merge line says which method and where it
  came from. Every check that can stop it runs before anything changes.
  The first is that the PR is this repository's: a URL can name one
  anywhere, and every later step would bring its number and branch name
  back here. Then the PR must be open, not a draft, into the default
  branch from a branch of this repository, and mergeable; no uncommitted
  changes to tracked files; the local default branch able to fast-forward;
  any local copy of the branch exactly at the PR's head; the method
  settled. On the default branch with no PR named it refuses. The merge is
  pinned to that head with `--match-head-commit`. Only once GitHub reports
  the PR merged does it retarget the open PRs stacked on the branch to the
  default branch, delete the branch on origin, switch to the default
  branch, fast-forward it and delete the local branch. A retargeted PR's
  branch still carries the merged PR's original commits, and the default
  branch has only their rebased or squashed copies; GitHub reports it
  `BEHIND` or `DIRTY` only where branch protection or a conflict says so,
  and otherwise can land those commits a second time. So for each one the
  script prints the lines it needs before it merges, all the user's to
  run: `git fetch origin`, then `git switch` to its branch and `git merge
  --ff-only origin/<its branch>` (the local branch made origin's), `git
  rebase --onto origin/<default> <merged head> <its branch>`, and a push
  leased on the PR's head as the script listed it
  (`--force-with-lease=refs/heads/<its branch>:<its head>`), so a push
  that landed after that is refused rather than lost. The lines are
  chained with `&&`, so a block pasted at once stops where one fails.
  Deleting a branch with a push closes every open PR based on it or coming
  from it, and a closed PR whose base branch is gone can be neither
  reopened nor retargeted, so origin's branch goes only once GitHub lists
  no open PR based on it and none but
  the merged one from it. The delete is leased on the head that was
  merged (`--force-with-lease`): a push that landed on the branch after
  the merge keeps the branch, with a line saying so, rather than being
  deleted with it. When another worktree has the default branch checked
  out, this checkout is detached at origin's default branch instead, and
  the default branch is left to be pulled there. `--dry-run` runs every
  check and changes nothing. The options count before the PR or after it;
  an option the script does not know, both methods, a second PR or an
  empty argument stops it with nothing changed. An unquoted `#195` starts
  a shell comment, so the skill passes the bare number. The script is out
  of the allowlist for the same reason as `review_pr.sh`, and the skill
  pre-approves it only while `/merge` runs.
- **`/coverage`** writes the case the branch's change owes, against the
  Testing standards below, the way `.claude/skills/coverage/brief.md` says.
  It reads the diff from the merge base with the default branch,
  uncommitted edits included, looks for a case that already covers it, and
  otherwise writes one, then builds and runs the suite with the commands in
  "Build and test" until it is green. The brief applies this file's two
  rules for tests that must carry across: a case goes against the
  `gpr_tools` conversion layer so that it cherry-picks, and one that would
  need a fixture private to `gpraw/gpr` degrades to what ships here. It
  commits, pushes and posts nothing; a case that will not go green is taken
  back out and reported, and no file is reverted, since the operator's own
  edits may be in it. In `gpraw/gpr` the same brief is read into CI's
  `claude-test-gap-check.yml`; this repository has no such workflow, so
  `/coverage` is the only test-gap pass a change gets here.
- **`/pr`** opens the pull request in the order the pieces depend on: the
  suite's tally is the body's verification line, so the case comes before
  the body, and the body before the push, since the push starts CI. It
  refuses to run on the default branch, and stops on an open pull request
  for the branch or on uncommitted edits that are not the case. Two of its
  steps come from this file. First the README contract: when the change is
  one the "About this fork" section must describe and the branch does not
  update it, `/pr` stops before anything is committed and says what the
  section is missing; it does not write it. Then, after `/coverage` has run
  and the case is committed on its own, the cherry-pick "Land it here first"
  asks for: in a detached scratch worktree of a local `gpraw/gpr` clone
  (found beside this checkout's main worktree by the `origin` its
  `.git/config` names, or asked for), at that repository's default branch
  as origin has it and under `build/carry/`, it cherry-picks the code
  commits (every commit that is not only `README.md`, `CLAUDE.md` or
  `.github/` edits), builds and runs that repository's suite as its
  CLAUDE.md says, makes the byte-for-byte comparison this file asks of a
  port or of a change that should leave output unchanged while both builds
  are at hand, and removes the worktree. A conflict is aborted and
  reported, not resolved, and neither it nor a red suite there stops the
  pull request. Nothing is pushed from that worktree, the clone's own
  checkout is not touched, and the `git -C` commands prompt. The body,
  drafted to the PR conventions below and written to
  `build/pr/<branch>.md`, states the README outcome and the cherry-pick
  outcome either way. Then a plain push and `gh pr create` against the
  default branch, with `-R <owner>/<repo>` so that the pull request opens
  on origin's repository and not on `gopro/gpr`. It says when the branch
  is behind the default branch and leaves catching up to the operator.
  Nothing in it force-pushes or rebases.
- **`/next`** says what has to be done next, in order. It reads the
  session's own conversation first (what was set out to do, decisions made
  and still open, what was promised and not done), then the working tree,
  the branch's pull request (the flag matrix, with the checks branch
  protection requires as GitHub reports them, and whether the `/review`
  comment is of the current head), the other open pull requests, and what
  the sync rules above leave owing: a merged change's cherry-pick into
  `gpraw/gpr`, looked for there by title; an upstream `gopro/gpr` `master`
  this repository has not merged, read from upstream's own URL and never
  from `origin/gopro/gpr`, which is this fork's delta replayed for GoPro;
  the README section a change must update; and, as a decision rather than
  a step, a change merged in `gpraw/gpr` that "Borrow from downstream" may
  want here. Every `gh` command it runs on this repository names it with
  `-R`. The `/review` comment it trusts is the newest that starts with
  `<!-- gpr-dual-review -->` and was written by the account
  `gh auth status` names; one by anyone else is named, with its author, as
  not taken for a review. An open PR that `/merge` retargeted and that
  still carries a merged PR's commits, which `git cherry` against the
  default branch shows, gets the `git rebase --onto` and force-push it
  needs as the user's step, ahead of its review and merge. It answers with
  steps in dependency order, each with its command and the evidence that
  makes it next, and stops at a decision that is the operator's. It runs
  none of them: it changes no file and nothing on GitHub, and what it
  pre-approves only reads or fetches.

`/coverage`, `/pr` and `/next` have no script: the work is judgment, and the
mechanical half is a few commands each skill's `allowed-tools` pre-approves
while it runs, `git push -u origin HEAD` and `gh pr create` among them for
`/pr`.

`.claude/settings.json` is the reviewed allowlist, one file for both
repositories: the configure, build and test loop in both repositories'
spellings, each command exactly as "Build and test" writes it (the
configure with and without `-DCMAKE_BUILD_TYPE=Release`, the build alone,
with `-j` or with `--target gpr_tools_tests`, `ctest` with and without
`--output-on-failure` and `-C`) and the test binary under `build/` with
its arguments, `bash -n` on a script, read-only `gh` and read-only `git`.
Every rule is project-relative, so it holds in any checkout. Two rules for
editing it. A prefix rule is a string match with no flag-level analysis, so
a wildcard admits every flag form of the command it names: that is why
`git log *` and `git diff --stat *` are not in it (`--output=` writes an
arbitrary file), why `cmake` and `ctest` are named whole rather than with
a trailing wildcard (`-B`, `--graphviz`, `ctest -O` and `--output-junit`
write anywhere, `ctest -S` runs a script, and a build's `-- -f <makefile>`
runs arbitrary shell; each was run to check), and why there is no `gh api`
rule at all, a GET being inexpressible as a prefix.
And the line is where a command's effects land, not whether it has any:
inside the working tree is in, outside it is out. So `gh pr create`,
pushes and both scripts stay out and prompt, except while a skill that
pre-approves them runs.

## Review standards

Order findings by the sections below. Report a finding only after reading the
code that proves it, cite `file:line`, and give the concrete failure scenario
(inputs or state -> wrong output or crash). Say plainly when nothing blocking
was found.

### 1. Memory safety and crash behaviour: blocking

- **Allocator pairing.** `Alloc*` fills a caller-owned struct and pairs with
  `Release*`; `Create*` allocates the struct too and pairs with `Delete*`.
  Codec functions take `gpr_allocator *allocator` first and call
  `allocator->Alloc` / `->Free`.
- **`gpr_buffer` carries no ownership**; whoever receives one frees it.
- **`gpr_buffer_auto` has three traps** (`source/lib/common/private/gpr_buffer_auto.h`):
  `resize()` only rewrites `.size` and does not reallocate, `set()` adopts a
  pointer non-owning by default, and `allocate()` asserts the buffer is
  currently NULL.
- **Two allocation domains.** `gpr_allocator` and the DNG SDK's
  `dng_memory_allocator` / `dng_memory_block` are separate; freeing across
  them is a defect. `AutoPtr<T>::Release()` transfers ownership.
- **No exception may escape the C API.** The DNG SDK throws `dng_exception`
  on malformed input; every C-linkage `gpr_*` entry point that reaches it has
  a `catch( ... )` returning `false`. An `assert(0)` on a reachable
  malformed-input path is itself a crash in Debug builds.
- **Pointer aliases into a buffer are the recurring bug class.** A helper that
  returns an interior pointer must be checked against the callee's stride and
  length assumptions (the old `adjust_bayer_phase` read past the allocation).
- **Fixed-size buffers are a defect** when the payload has no bound: VC-5
  output and JPEG thumbnails both grew past "reasonable" sizes on large
  frames. Size from the input or grow on demand.

### 2. Build-flag correctness

Five flags, defaulted in `source/lib/common/public/gpr_platform.h` and exposed
as CMake options: `GPR_READING`, `GPR_WRITING`, `GPR_JPEG_AVAILABLE`,
`GPR_TIMING`, `GPR_NEON`. `GPR_NEON` defaults to 0 in the header and is
injected project-wide by CMake on arm64; that disagreement is deliberate.

- `GPR_READING` / `GPR_WRITING` guards run through the public header, so those
  configurations change the API surface. A declaration added outside the
  right `#if` silently breaks them; a struct field must exist in every
  configuration (`gpr_parameters` keeps one layout).
- Anything the public API needs from the codec (an enum, a constant) lives in
  `source/lib/common/public`, never in `vc5_encoder` or `vc5_decoder`, whose
  directories and include paths exist only when their flag is on.
- New `#if GPR_*` regions need `#else` fallbacks, or the all-off build fails.
- `source/lib/dng_sdk/CMakeLists.txt` does not set these symbols, so a
  flag-guarded region that changes a struct or class layout in `dng_sdk` is an
  ODR skew across translation units.

### 3. Format and interop correctness

- OpcodeList payloads are big-endian regardless of the TIFF container's byte
  order (DNG spec).
- Apple's ImageIO/CIRAWFilter drops the entire OpcodeList2 gain map unless the
  two green CFA planes carry byte-identical gains. The greens are identified
  from each opcode's own `dng_area_spec` (the `(top,left)` parity names its
  cell in the 2x2 CFA tile), never by position in the opcode list.
- A written DNG carries a JPEG thumbnail in IFD 0; without one, readers that
  show IFD 0 display the raw CFA data as black.
- Check bit depth and pixel format against the declared range
  (`PIXEL_FORMAT_RGGB_12` ... `PIXEL_FORMAT_BGGR_14`), black and white levels,
  and white-balance gains. A changed encoder default changes every file
  written without an explicit setting; the PR must say so with measured sizes.

### 4. Minimal diff, and in sync

- The change is the smallest that fixes the root cause. Special cases layered
  on shared infrastructure are the sign that a fix is too shallow.
- The cherry-pick rules above hold: shared lines only, documentation and CI
  in separate commits, tests on the CLI layer, verified downstream.
- **The README "About this fork" section reflects the change.**
- **The customer API speaks GPR, the codec stays as upstream has it.** Nothing
  in `source/lib/gpr_sdk/public` exposes a `VC5_*` name, and no codec type
  moves out of `vc5_encoder.h` / `vc5_decoder.h` to make that possible: a
  codec header that matches upstream is what lets GoPro absorb a change. When
  the SDK needs a codec enum, declare its own `GPR_*` enum in the SDK header
  and tie the two together in `gpr.cpp` with a compile-time check, as
  `GPR_QUALITY_SETTING` does for `VC5_ENCODER_QUALITY_SETTING` (and as
  `GPR_PIXEL_FORMAT` stands for `VC5_ENCODER_PIXEL_FORMAT`). `gpr.h` cannot
  include the codec headers in any case: they exist only when the matching
  `GPR_READING` / `GPR_WRITING` switch is on.
- Reuse what exists rather than adding a parallel implementation:
  `gpr_buffer_auto`, `gpr_flat_write_stream`, `read_from_file` /
  `write_to_file`, the `Alloc` / `Create` pairs, `dng_stage1_negative`, and in
  tests `validate_dng_like`, `validate_raw`, `validate_rgb`,
  `tiff_parse_gain_maps`, `tiff_find_jpeg_preview`, `preview_cli_params`,
  `scratch_path`.
- Keep the diff readable: no drive-by reformatting, no unrelated renames, no
  whole-file reindentation. There is no `.clang-format`; the codec is
  tab-indented and the SDK space-indented, both deliberately.
- Do not report whitespace, brace or formatting nits at all, and do not flag
  style inside vendored directories.

## Code style: match the file you are in

Two dialects coexist. Follow whichever the file already uses.

- **Codec** (`vc5_*`): `PascalCase` functions, `ALL_CAPS` typedefs declared as
  `typedef struct _lower_name { ... } UPPER_NAME;`, tab indentation,
  `CODEC_ERROR` return codes.
- **SDK / public API** (`gpr_sdk`, `common`, `gpr_tools`): `snake_case`
  functions and types, anonymous `typedef struct { ... } gpr_thing;`, 4-space
  indentation, `bool` returns, `int` return codes in the tool (`0` = success).

Common to both: header guards as `#ifndef NAME_H` / `#define` / `#endif`; no
`#pragma once`; public headers wrap declarations in `extern "C"`; C++ stays
conservative (`NULL` not `nullptr`, no `auto`, no `std::unique_ptr`, no
in-house templates). Doxygen file headers (`/*! @file ... @brief ...`)
followed by the dual Apache/MIT license block. Comments explain *why*, with
the measurement that settled a number. Code comments and commit messages are
plain ASCII: write `->` and `--` rather than arrows or em dashes.

## Testing standards

There is one test file, `source/test/gpr_conversion_tests.cpp`, built as
target `gpr_tools_tests` and registered as the single ctest entry
`gpr_conversion_tests`. It uses a **hand-rolled harness: no gtest, no Catch2,
no golden images, no checksums.** New tests follow its patterns exactly.

- `run_case( "name", []{ ... } )` runs one case, forked on POSIX so a segfault
  is a failed case rather than a dead suite. Assertions are
  `check( cond, "message" )`, which records and continues. Case bodies are
  **capture-less lambdas** reading file-scope globals (`g_gpr`, `g_params`,
  `g_W`/`g_H`, `g_sample_path`, `g_cli_sample`, `g_cli_W`/`g_cli_H`) set up in
  the parent before the fork. `Buffer` and `RgbBuffer` are the RAII wrappers
  for SDK-allocated memory. `run_case(..., expect_fail=true)` marks a known
  broken path: XFAIL passes, XPASS fails the suite.
- New cases go inside the matching group function (`run_sample`,
  `run_preview_cli_tests`, `run_lens_correction_cli_tests`,
  `run_argument_parser_tests`, `run_flat_write_stream_tests`); a new group needs a call in `main()`.
  `file(GLOB)` picks up new `.cpp` files, which must not define `main()`.
- **Deterministic.** No `rand`, `time`, `clock`, sleeps, network, or
  file-system state beyond `TMPDIR`. Synthetic data comes from a fixed formula
  (`src[i] = (unsigned char)( ( i * 131 + 7 ) & 0xFF )`). Scratch files go
  through `scratch_path()` and are removed inside the same case; negative
  cases assert no file was written.
- **Assert exactness** through an independent ground truth rather than the
  code under test: the TIFF Compression tag read by hand and cross-checked
  against `gpr_check_vc5()`, byte-for-byte `memcmp`, file sizes that must grow
  with a finer quantizer. The suite has one tolerance (JPEG sizes within 10%
  where quantization noise makes exactness impossible). A test that mirrors
  the implementation's assumption is a defect, not coverage.
- Guard anything using tiny_jpeg with `#if GPR_JPEG_AVAILABLE`, since CI builds
  with it off. Adding a file to `samples[]` in `main()` also requires
  classifying it in the `expect_warp` list, which names the files by their
  upstream basenames (`GOPR2657.GPR`, `GPFR7066.GPR`, `GPBK7066.GPR`).
- Case names are `"<sample>: <api_name>"`, `"--flag: behavior"`, or
  `"subject: behavior"`; check messages are short lowercase statements of the
  expected state.

A PR touching the encoder, the DNG/TIFF writer, the `gpr_convert_*` matrix, a
`gpr_tools` option or a build flag adds or extends a case in the same PR. Pure
refactors that keep output byte-identical are the accepted exception and carry
that verification in the commit message.

## PR and commit conventions

Titles are imperative sentences describing the user-visible outcome, with an
optional `component:` prefix: `Restore the VC-5 encoder's default quality to
Filmscan-X`, `README: document --quality`.

Bodies follow a three-part shape, wrapped at about 72 columns in plain ASCII:

1. What was wrong and why it mattered, at mechanism level.
2. What the change does, as bullets, including the fallback or safety
   behaviour and anything that changes for existing callers.
3. Quantitative verification: `gpr_tools_tests` case count and result, the
   build-flag matrix, measured sizes or timings, and the byte-for-byte
   comparison against the previous build or against `gpraw/gpr` where output
   is expected to be identical.

A PR body also states whether the code commits were cherry-picked onto
`gpraw/gpr` and with what result, and confirms that the README "About this
fork" section was updated or did not need to be.
