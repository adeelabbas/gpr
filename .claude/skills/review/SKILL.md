---
name: review
description: Review a GPR pull request with several models at once, against CLAUDE.md's review standards - by default Claude Opus 5.5 and Gemini 3.8 Flash, or whichever <cli>:<model> reviewers are named (Grok 4.7 and Claude Fable 5.1 among them when asked for) - then have a Claude model (default Opus 5.5) reconcile the reviews into one report, headless. The report is posted on the PR, and CI's test-gap pass starts when the repository has one and the PR's head has not had one. Only when the user types /review.
argument-hint: "[PR number or URL, default this branch's PR] [--reviewers <cli>:<model>,...] [--reconciler <model>] [--reconcile-fallback <model>]"
disable-model-invocation: true
allowed-tools: Bash(scripts/review_pr.sh), Bash(scripts/review_pr.sh *)
---

# Review a pull request with several models

`scripts/review_pr.sh` does the work. It checks out the PR's head under
`build/review/pr-<n>/`, runs every reviewer on the same brief
(`reviewer-brief.md`, beside this file) in parallel, and throws out any
review that did not finish. No reviewer can run a command or write a file.
Then it has a Claude model reconcile the reviews that finished into one
report, headless, on `reconciler-brief.md`, and writes it to
`build/review/pr-<n>/summary.md`. The reconciler is named by the script,
not by this session, so the report is the same whichever model or tool runs
`/review`. Do not reconcile the reviews yourself, and do not review the
diff.

## Who reviews

Reviewers and the reconciler are arguments, so a new model is a new string
here and not a change to the script. A reviewer is `<cli>:<model>`: `claude`
for the Claude CLI, `grok` for the Grok CLI, `gemini` for Antigravity's
`agy`, and `<model>` whatever that CLI takes for `--model`. With none named
the script's own defaults apply - `DEFAULT_REVIEWERS` and the reconciler
default in `scripts/review_pr.sh`, which own them; today

    claude:claude-opus-5-5,gemini:gemini-3.8-flash-high

reconciled by `claude-opus-5-5`. Two more are ready and not in the default,
reviewing only when named: Grok 4.7 (`grok:grok-4.7`) and Claude Fable 5.1
(`claude:claude-fable-5-1`). A CLI can review with more than one model at
once, so Fable beside Opus is two Claude reviews:

    /review 42 --reviewers claude:claude-opus-5-5,claude:claude-fable-5-1,grok:grok-4.7,gemini:gemini-3.8-flash-high

Pass what the user asked for, as they wrote it:

    /review 42 --reviewers claude:claude-opus-6,gemini:gemini-4-pro-high
    /review 42 --reconciler claude-opus-6

The reconciler has to be a Claude model: only the Claude CLI can run it
read-only the way the script needs. A company whose CLI is not one of the
three needs a driver in the script first; say so rather than guessing at a
prefix.

All paths below are relative to the repository root.

## 1. Review and reconcile

Start the script in the background. Do not wait for it in the foreground:

    scripts/review_pr.sh $ARGUMENTS

Write the PR as a bare number - `42`, never `#42`, whatever the user typed -
and put a URL in single quotes. An unquoted `#` starts a comment in the
shell, which takes the number and every option after it along, so
`scripts/review_pr.sh #42 --reviewers ...` reaches the script as no
arguments at all and reviews this branch's PR with the default reviewers.

This takes several minutes, more on a large PR. Wait for the completion
notification. Do not poll it.

A URL can name a pull request in another repository. The script refuses
that before it checks anything out (`error: #NN is a pull request of ...`).
Tell the user that line. Do not review the foreign pull request from this
checkout.

Its last lines give each reviewer as `<cli>:<model>`, with its verdict and
review file, `skipped` and why, or `FAILED` and why, then the reconcile's
line: the model that reconciled and the path of `summary.md`, `FAILED` and
why, or `skipped` when no review finished. Exit status 1 means a reviewer
failed or the reconcile wrote no `summary.md`; a skipped reviewer on its
own leaves it 0. Which case it is, the lines say:

- **A reviewer was skipped** - its CLI is not installed, or a Claude or
  Grok reviewer's subscription allowance is spent. That is not a failure and
  is not re-run; the reconcile ran on the others and the report says who was
  missing. (What `agy` prints for a spent Gemini quota has not been seen,
  so a spent Gemini shows as a failure.) When every reviewer was skipped
  there is nothing to reconcile or post: stop and report the lines.
- **A reviewer failed.** The reconcile still ran on the others. Re-run the
  failed one once, on its own, in the background:
  `scripts/review_pr.sh <n> --only <cli>:<model>`, with the same
  `--reconciler` and `--reconcile-fallback` the first run was given, since
  it reconciles again, with it, and without them it would reconcile on the
  default model. If the re-run fails too, carry on without it: the report
  already says it did not finish.
- **Only the reconcile failed.** Re-run it once, on its own, in the
  background: `scripts/review_pr.sh --reconcile <n>`, with the same
  `--reconciler` and `--reconcile-fallback` if they were given. It re-uses
  the reviews and costs one reconcile, not the reviews. If it fails again,
  stop and report the reason line as printed; do not post. The exception is
  a reconcile the script says is out of its subscription token limit: do
  not re-run it, since it would draw on the same spent allowance. Stop,
  report that line, and do not post; `--reconcile <n>` repeats it once the
  allowance refills, or at once with `--reconcile-fallback <another Claude
  model>` if the user names one.

Open a run's stream log only if it failed and the reason line does not
explain why.

## 2. Post

    scripts/review_pr.sh --post <n>

It posts `summary.md` behind a header (the commit reviewed, every reviewer
with its model and verdict, or why it did not finish, and which model
reconciled) and every full review in a collapsed section. It edits the
earlier comment from this command if one exists, otherwise posts a new one.
Then it settles the `needs-coverage` label and removes the checkouts.

The label is the script's decision, not yours. It exists for CI's test-gap
pass, `claude-test-gap-check.yml`, which gpraw/gpr has and adeelabbas/gpr
does not. The script looks for that workflow on the PR's base branch; where
it is not there, the script leaves the label alone and its `label:` line
says there is no test-gap pass to start.

Where the base branch has it, applying `needs-coverage` is what starts
`claude-test-gap-check.yml`, which already ran once by itself when the PR
opened, and starting it again cancels a pass still on the runner. So the
script asks GitHub whether the PR's **current head** has a test-gap result,
or a pass queued or in progress, and leaves the label alone when it does.
It applies the label only when the head has none: the workflow never ran,
its last pass failed or was cancelled, it went green without posting a
result, or someone has pushed since the last result. A commit the pass
pushed itself does not count as a push. When the label is still on from an
earlier run the script takes it off and puts it back, because only applying
it starts anything. A PR that edits `claude-test-gap-check.yml` is left
alone whatever its runs say: the action skips itself there, so no pass can
run until it merges. Never add or remove the label yourself to force a pass.

The script also respells the test-gap workflow's comment marker wherever
the report or a review quotes it, and the marker of CI's own single-model
review (`claude-review.yml`, in gpraw/gpr) too, because each of those
workflows deletes every comment containing its marker except its own
newest. That review is a different comment from this one, and this command
never edits it. Do not work around the respelling, and do not edit the
review files or `summary.md` yourself.

## 3. Tell the user

Read `build/review/pr-<n>/summary.md` - only that file - and keep the reply
short:

- the comment URL
- which reviewers finished, and which were skipped or failed and why
- which model reconciled
- each blocking and each design finding, one line apiece
- the `label:` line the script printed, with the indented line under it
  when there is one - or, when it printed a `warning:` about the label
  instead, that line

That line says whether `claude-test-gap-check.yml`, CI's test-gap pass, was
started and why: the head already has a result, a pass is already queued or
in progress for it, the PR edits the workflow so none can run, the label was
added (or removed and re-added) and for what reason, or this repository has
no such workflow, so there is no pass to start. Pass it on as printed. The
full report is already on the PR, so do not repeat it here.
