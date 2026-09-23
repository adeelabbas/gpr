#!/bin/bash
# Review a GPR pull request with several models at once, independently, each
# against CLAUDE.md's review standards, then have one Claude model reconcile
# their reviews into one report, headless, and post it to the PR.
#
# Who reviews is a parameter, not code. A reviewer is <cli>:<model>, where
# <cli> is one of the drivers below and <model> is whatever that CLI takes
# for --model:
#   claude:<model>   the claude CLI          (claude:claude-opus-5-5)
#   grok:<model>     the grok CLI            (grok:grok-4.7)
#   gemini:<model>   Antigravity's agy CLI   (gemini:gemini-3.8-flash-high)
# The default is the Claude and the Gemini reviewer (DEFAULT_REVIEWERS).
# Others review only when named in --reviewers: grok:grok-4.7, or another
# model of a CLI already in the list - claude:claude-fable-5-1 beside
# claude:claude-opus-5-5 is two Claude reviews, each in its own files. A
# newer model from any of the three companies is only a different string on
# the command line. A CLI with no
# driver here needs one, because each spells "read files and nothing else"
# its own way (the notes above each run_* below).
#
# The reconciler is a Claude model, named here rather than left to whichever
# session runs /review: a session cannot change its model partway through a
# review, and a reconciler that is "the current session" writes a different
# report depending on which model the operator happened to start. There is
# no fallback reconciler by default: it would be the same model on the same
# spent allowance.
#
# Any reviewer can drop out without stopping the rest. One whose CLI is not
# installed, or whose subscription allowance is spent, is skipped and says
# so; one that fails otherwise is a failure, which /review re-runs once. The
# reconcile runs on whatever finished.
#
# Usage:  scripts/review_pr.sh [<pr>] [--reviewers <list>] [--reconciler <model>]
#                                     [--reconcile-fallback <model>]
#                                                 review, reconcile
#         scripts/review_pr.sh [<pr>] --only <reviewer>
#                                                 re-run one reviewer, reconcile
#         scripts/review_pr.sh --reconcile [<pr>] [--reconciler <model>] ...
#                                                 reconcile again only
#         scripts/review_pr.sh --post [<pr>] [-]  post, label, clean up
#         scripts/review_pr.sh --label-rule <pr.json> <runs.json>
#                                                 the label rule, offline
#
# <pr> is a number, '#number', URL or branch; the default is this branch's PR.
# Quote a #number or a URL: an unquoted # starts a shell comment, which takes
# the number and every option after it along, so the script would see no
# arguments at all and review this branch's PR instead.
# A URL naming another repository's pull request is refused before anything
# is checked out. <list> is reviewers separated by commas. --only names one
# reviewer of the last run by its <cli>:<model>, its model or its CLI, and
# re-runs only that one against the same head commit, then reconciles again.
# --reconcile re-runs only the reconciler, on the reviews already there, so a
# reconcile that failed costs one reconcile to repeat and not the reviews.
#
# /review (.claude/skills/review/SKILL.md) runs the first form, then --post,
# which posts build/review/pr-<n>/summary.md. With `-`, --post takes the
# summary from stdin instead, for a report written by hand.
#
#   1. build/review/pr-<n>/input/, the only directory any reviewer can see:
#        code/        the PR head, detached, with the instruction files Grok
#                     would load as rules taken out of it
#        CLAUDE.md    the base branch's copy, the standard
#        head-CLAUDE.md  the head's CLAUDE.md, when the head still has one
#        pr.md        title, description, base, head, merge base, and files
#        diff.patch   merge base to head
#        commits.md   every commit in the PR with its message
#        checks.md    what write_checks ran for the reviewers, since they
#                     cannot: each changed shell or Python file parsed
#   2. Every reviewer on one prompt - reviewer-brief.md behind a line naming
#      the PR - so any difference between the reviews comes from the model.
#      None can run a command or write a file. Each one's files are named by
#      a slug of its model (review-<slug>.md, <slug>.meta.json, ...), listed
#      in build/review/pr-<n>/reviewers.
#   3. Each review is refused unless its run finished cleanly and the text
#      ends with END OF REVIEW. Checked here, not taken on the agent's word.
#   4. The reconciler (reconciler-brief.md, beside the reviewer's) reads the
#      reviews that finished and only the code a finding points to, and
#      replies with the report, which lands in summary.md only if it ends with
#      END OF REPORT. It is started in build/review/pr-<n>/, under the same
#      --restricted read-only flags as a Claude reviewer, and it reads
#      input/checks.md, as the reviewers do.
#   5. --post: one standing comment on the PR, edited in place when a later
#      run posts again, and the needs-coverage label - but only when the PR's
#      current head has no result from claude-test-gap-check.yml and no pass
#      on the way. That workflow runs by itself when a PR opens, and applying
#      the label is what starts it again, so a head that is covered or being
#      covered is left alone, and so is a PR that edits that workflow, where
#      no pass can run. One that is owed a pass gets the label, taken off first
#      when an earlier run left it on, since only applying it starts anything.
#      A repository whose base branch has no such workflow (adeelabbas/gpr;
#      gpraw/gpr has one) has no pass to start, and its label is not touched.
#      coverage_verdict, below, is the rule and what it was measured against;
#      --label-rule runs it alone on two files of saved `gh` output (absolute
#      paths, or relative to the repository root) and touches nothing.
#      Then the checkouts are removed; the reviews and inputs stay.
#
# Environment: GPR_REVIEW_REVIEWERS (default: $DEFAULT_REVIEWERS, below) is
# the reviewer list when --reviewers is not given, and
# GPR_REVIEW_RECONCILE_MODEL (default: claude-opus-5-5) the reconciler when
# --reconciler is not. GPR_REVIEW_RECONCILE_FALLBACK_MODEL (default: none),
# or --reconcile-fallback, names another Claude model to reconcile with when
# the first reports its subscription allowance spent.
# GPR_CLAUDE, GPR_GROK and GPR_AGY name the CLIs (default: claude, grok,
# agy). GPR_REVIEW_CLAUDE_EFFORT (default: medium, the effort the GPRaw
# app's reviews and CI coverage pass run Opus at) is every Claude reviewer's
# effort; a Gemini model carries its effort in its name.
# GPR_REVIEW_CLAUDE_TIMEOUT, GPR_REVIEW_GROK_TIMEOUT and
# GPR_REVIEW_GEMINI_TIMEOUT (default: 30m each; seconds, or with an s, m or
# h suffix) bound each reviewer.
# GPR_REVIEW_RECONCILE_EFFORT (default: high) and
# GPR_REVIEW_RECONCILE_TIMEOUT (default: 20m) pick the reconciler's run.
# GPR_REVIEW_NO_POST=1 makes --post a rehearsal: it assembles the comment
# and says what it would do, and changes nothing on GitHub or on disk beyond
# comment.json. With -, the report from stdin goes to summary-draft.md, and
# summary.md and the reconciler's credit stay as they were.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

fail() { echo "error: $*" >&2; exit 1; }

# Exit 0 when a `claude -p` run stopped because the subscription allowance
# is spent. $1 is the run's stdout (stream-json), $2 its stderr. A finished
# run is never this: a stream whose result is not an error is kept even if
# its text mentions a limit. In a stream only the result row's text and the
# stderr are searched: the stream also carries every file the agent read,
# and a run that timed out or ran out of turns after reading one that
# quotes a limit - this script does, and so does any diff of it - would
# otherwise read as spent, and not be retried (a review of the GPRaw app's
# copy found it). The phrases are Claude Code 2.1.278's own wording
# (2026-09-21), copied with the rest of this function from the GPRaw app's
# release scripts, which share it.
# "Rate limited. Please wait and retry." and "API overloaded" are not among
# them: those are a retry of Claude, not a reason to skip a reviewer or to
# spend the fallback reconciler.
claude_subscription_exhausted() {
    python3 - "$1" "$2" <<'PY'
import json, sys
def slurp(path):
    try:
        return open(path, encoding="utf-8").read()
    except OSError:
        return ""
stdout = slurp(sys.argv[1])
stderr = slurp(sys.argv[2]) if len(sys.argv) > 2 else ""
rows = []
for line in stdout.splitlines():
    try:
        rows.append(json.loads(line))
    except ValueError:
        pass
result = next((r for r in reversed(rows) if r.get("type") == "result"), None)
if (result is not None and not result.get("is_error")
        and (result.get("result") or "").strip()):
    sys.exit(1)
if rows:
    said = str((result or {}).get("result") or "")
else:
    said = stdout
blob = (said + "\n" + stderr).lower()
phrases = (
    "you've hit your",
    "usage limit reached",
    "reached your specified",
    "weekly usage limit",
    "credit balance too low",
    "credit balance is too low",
    "you're out of extra usage",
    "spend limit reached",
    "usage limit is set to $0",
)
sys.exit(0 if any(p in blob for p in phrases) else 1)
PY
}

# Names Grok treats as instructions, from its project-rules discovery: the
# AGENTS/CLAUDE filenames, the .claude copies of those, and the three rules
# directories. CLAUDE.md itself is moved aside by the caller before this runs,
# because the reviewer still has to read the head's copy. Removed from the
# checkout only; the diff was written first.
strip_loaded_instructions() {
    local root="$1"
    rm -f "$root/AGENTS.md" "$root/Agents.md" "$root/AGENT.md" \
          "$root/Claude.md" "$root/CLAUDE.local.md" \
          "$root/.claude/CLAUDE.md" "$root/.claude/CLAUDE.local.md"
    rm -rf "$root/.claude/rules" "$root/.grok/rules" "$root/.cursor/rules"
}

BRIEF="$REPO_ROOT/.claude/skills/review/reviewer-brief.md"
RECONCILER_BRIEF="$REPO_ROOT/.claude/skills/review/reconciler-brief.md"
# Deliberately not claude-test-gap-check.yml's <!-- gpr-claude-test-gap -->:
# that workflow deletes every comment carrying its marker except its own newest.
# And deliberately not claude-review.yml's <!-- gpr-claude-review -->: that
# one is CI's single-model review, a different comment.
MARKER='<!-- gpr-dual-review -->'
LABEL='needs-coverage'
# The workflow that label starts, the marker on the one comment it posts, and
# the git name claude-code-action commits the cases it writes under.
# Read only, all three.
WORKFLOW='claude-test-gap-check.yml'
COVERAGE_MARKER='<!-- gpr-claude-test-gap -->'
COVERAGE_AUTHOR='claude[bot]'
CLAUDE="${GPR_CLAUDE:-claude}"
GROK="${GPR_GROK:-grok}"
AGY="${GPR_AGY:-agy}"
DEFAULT_REVIEWERS='claude:claude-opus-5-5,gemini:gemini-3.8-flash-high'
REVIEWERS_SPEC="${GPR_REVIEW_REVIEWERS:-$DEFAULT_REVIEWERS}"
CLAUDE_EFFORT="${GPR_REVIEW_CLAUDE_EFFORT:-medium}"
CLAUDE_TIMEOUT="${GPR_REVIEW_CLAUDE_TIMEOUT:-30m}"
GROK_TIMEOUT="${GPR_REVIEW_GROK_TIMEOUT:-30m}"
GEMINI_TIMEOUT="${GPR_REVIEW_GEMINI_TIMEOUT:-30m}"
RECONCILE_MODEL="${GPR_REVIEW_RECONCILE_MODEL:-claude-opus-5-5}"
RECONCILE_FALLBACK_MODEL="${GPR_REVIEW_RECONCILE_FALLBACK_MODEL:-}"
RECONCILE_EFFORT="${GPR_REVIEW_RECONCILE_EFFORT:-high}"
RECONCILE_TIMEOUT="${GPR_REVIEW_RECONCILE_TIMEOUT:-20m}"
USAGE="usage: scripts/review_pr.sh [<pr>] [--reviewers <cli>:<model>,...] [--reconciler <model>]
                                   [--reconcile-fallback <model>]
       scripts/review_pr.sh [<pr>] --only <reviewer>
       scripts/review_pr.sh --reconcile [<pr>] [--reconciler <model>] [--reconcile-fallback <model>]
       scripts/review_pr.sh --post [<pr>] [-]   (- reads summary.md from stdin)
       scripts/review_pr.sh --label-rule <pr.json> <runs.json>
<cli> is claude, grok or gemini; the default reviewers are
$DEFAULT_REVIEWERS"

# --- whether this head still needs CI's test-coverage pass --------------------------------
# claude-test-gap-check.yml runs by itself when a PR opens or updates, so by
# the time /review posts there is usually a pass on the runner or a result on
# the PR. Applying needs-coverage starts another pass, and that workflow's
# concurrency group cancels the one in progress when the actor is not
# claude[bot]. So the label is applied only when the current head has no
# result and none coming.
#
# Which head a result belongs to comes from the workflow run, because nothing
# else records it. The result comment names no commit. A pass that writes a
# case pushes it, and the check then sits on the commit the run was started
# for, which is no longer the head. Hence the rule: a run speaks for the head
# when it was started for it, or when every commit since is one the pass
# pushed itself (COVERAGE_AUTHOR). A commit from anyone else means the head
# has moved, and a moved head is worth a fresh pass.
#
# A green run counts only with a result comment posted since it started: a
# green check is not by itself evidence the job ran (the workflow says as
# much above its last step). It is nearly the test that step applies, and
# not quite. That step reads `updated_at`, so a pass that edits its comment
# still counts as having spoken; `gh pr view --json comments` carries
# `createdAt` and no update time, so here such a pass reads as no result.
# The prompt tells the agent to post, not edit, and the error is toward one
# extra pass, never toward a head left uncovered.
#
# A comment is a result when it STARTS with the marker, which is where the
# workflow's prompt puts it. `contains` would also count /review's own
# comment whenever a review quotes the marker. (The assembler below respells
# it for the other half of that hazard.)
#
# A PR that edits claude-test-gap-check.yml cannot have a pass at all:
# claude-code-action skips itself there, and the run goes green with nothing
# behind it. The workflow's last step recognises that from the PR's files and
# asks for nothing; so does this, as its own state - `cannot`. Reading it as
# "no result" instead would re-apply the label on every /review, each time
# starting a run that checks out, configures and builds the test target
# before the action skips, and promising a test-coverage pass that will
# not happen.
#
# A pass still on the runner for an earlier head is replaced, not waited for:
# by the rule above its result could never count for this head, so letting it
# finish spends the runner on an answer the next /review would set aside.
#
# The rule takes its facts rather than fetching them - the PR as `gh pr view
# --json headRefOid,headRefName,labels,files,commits,comments` prints it on stdin,
# the runs as `gh run list --json headSha,status,conclusion,startedAt` prints
# them in $1 - so --label-rule can put any state in front of it from two
# files, with no PR that has to be in that state and nothing sent to GitHub.
#
# Prints three lines: covered, running, wanted or cannot; 1 or 0 for whether
# the label is on the PR; and why, as a clause that reads on its own. Only
# `wanted` applies the label.
coverage_verdict() {
    jq -r --argjson runs "$1" --arg label "$LABEL" --arg workflow "$WORKFLOW" \
          --arg marker "$COVERAGE_MARKER" --arg author "$COVERAGE_AUTHOR" '
        def short: .[0:7];
        def ended: if . == "cancelled" then "was cancelled"
                   elif . == "failure" then "failed"
                   elif . == "timed_out" then "timed out"
                   else "ended \(.)" end;
        .headRefOid as $head
        | [.commits[] | {oid, own: (.authors[0].name == $author)}] as $commits
        # The head, and each commit with nothing between it and the head but
        # commits the pass pushed.
        | ([range(0; $commits | length) as $i
            | select($commits[$i + 1:] | all(.own)) | $commits[$i].oid] + [$head]) as $same
        | [.comments[] | select(.body | sub("^\\s+"; "") | startswith($marker)) | .createdAt] as $results
        # `files` is the net diff of the PR, the same list the last step of the
        # workflow asks for; saved output without the field reads as a PR that
        # does not edit it. (No apostrophes in here: this is a quoted string.)
        | ([.files[]?.path] | index(".github/workflows/\($workflow)") != null) as $edits
        # A run an unrelated label started skips itself at the job; it is not a pass.
        | ($runs | map(select(.conclusion != "skipped")) | sort_by(.startedAt) | reverse) as $all
        | ($all | map(select(.headSha as $sha | $same | index($sha) != null))) as $mine
        | ($all - $mine) as $older
        | ($mine | map(select(.status != "completed")) | first) as $active
        | ($mine | map(select(.conclusion == "success"))) as $green
        | ($green | map(select(.startedAt as $t | $results | any(. >= $t))) | first) as $done
        | ($older | map(select(.status != "completed")) | first) as $stale
        | ($older | map(select(.conclusion == "success")) | first) as $last
        | def via($run): if $run.headSha == $head then ""
                         else " (started for \($run.headSha | short); only commits the pass pushed came after)" end;
          ( if $edits then
                ["cannot", "this PR edits \($workflow), so claude-code-action skips itself and no pass can run on it; ask for one on any PR it affects once it merges"]
            elif $active then
                ["running", "\($workflow) is already \($active.status | gsub("_"; " ")) for \($head | short)" + via($active)]
            elif $done then
                ["covered", "\($workflow) already has a result for \($head | short)" + via($done)]
            elif ($green | length) > 0 then
                ["wanted", "\($workflow) went green for \($head | short) with no result comment posted since it started"]
            elif ($mine | length) > 0 then
                ["wanted", "the coverage pass for \($head | short) \($mine[0].conclusion | ended)"]
            elif $stale then
                ["wanted", "the coverage pass \($stale.status | gsub("_"; " ")) is for \($stale.headSha | short), and the head has moved to \($head | short) since; a new pass replaces it"]
            elif $last then
                ["wanted", "the last coverage result is for \($last.headSha | short), and the head has moved to \($head | short) since"]
            elif ($all | length) > 0 then
                ["wanted", "no coverage pass has succeeded on this PR (the last, for \($all[0].headSha | short), \($all[0].conclusion | ended))"]
            else
                ["wanted", "\($workflow) has not run on this PR"]
            end ) as [$state, $why]
        | $state, (if [.labels[].name] | index($label) != null then 1 else 0 end), $why
    '
}

# The facts, from GitHub. `gh pr view` and `gh run list` answer all of it, so
# there is no `gh api` here.
coverage_state() {
    local pr runs
    pr="$(gh pr view "$N" --json headRefOid,headRefName,labels,files,commits,comments)" || return 1
    runs="$(gh run list --workflow "$WORKFLOW" --branch "$(jq -r .headRefName <<<"$pr")" \
            --limit 100 --json headSha,status,conclusion,startedAt)" || return 1
    coverage_verdict "$runs" <<<"$pr"
}

if [[ "${1:-}" == --label-rule ]]; then
    [[ $# == 3 && -r "$2" && -r "$3" ]] || fail "$USAGE"
    command -v jq >/dev/null 2>&1 || fail "jq is not on PATH."
    coverage_verdict "$(cat "$3")" < "$2"
    exit
fi

MODE=review
if [[ "${1:-}" == --post ]]; then
    MODE=post
    shift
elif [[ "${1:-}" == --reconcile ]]; then
    MODE=reconcile
    shift
fi
PR_ARG=""
ONLY=""
SUMMARY_ON_STDIN=""
# An option's value is the next argument, or follows an =, and is never
# empty: `--only ''` would otherwise read as no --only, clear the last
# run and review again with every reviewer.
while (( $# )); do
    arg="$1"; shift
    case "$arg" in
        --reviewers=*|--reconciler=*|--reconcile-fallback=*|--only=*)
            set -- "${arg#*=}" "$@"; arg="${arg%%=*}" ;;
    esac
    case "$arg" in
        --reviewers)
            [[ "$MODE" == review && -n "${1:-}" ]] || fail "$USAGE"
            REVIEWERS_SPEC="$1"; REVIEWERS_GIVEN=1; shift ;;
        --reconciler)
            [[ "$MODE" != post && -n "${1:-}" ]] || fail "$USAGE"
            RECONCILE_MODEL="$1"; shift ;;
        --reconcile-fallback)
            [[ "$MODE" != post && -n "${1:-}" ]] || fail "$USAGE"
            RECONCILE_FALLBACK_MODEL="$1"; shift ;;
        --only)
            [[ "$MODE" == review && -n "${1:-}" ]] || fail "$USAGE"
            ONLY="$1"; shift ;;
        -)  [[ "$MODE" == post ]] || fail "$USAGE"; SUMMARY_ON_STDIN=1 ;;
        -*) fail "$USAGE" ;;
        "") fail "$USAGE" ;;
        *)  [[ -z "$PR_ARG" ]] || fail "$USAGE"; PR_ARG="${arg#\#}" ;;
    esac
done
[[ -z "$ONLY" || -z "${REVIEWERS_GIVEN:-}" ]] ||
    fail "--only re-runs a reviewer of the last run, so it takes no --reviewers."

# The reconciler is a Claude model, with or without its claude: prefix.
RECONCILE_MODEL="${RECONCILE_MODEL#claude:}"
RECONCILE_FALLBACK_MODEL="${RECONCILE_FALLBACK_MODEL#claude:}"
for m in "$RECONCILE_MODEL" ${RECONCILE_FALLBACK_MODEL:+"$RECONCILE_FALLBACK_MODEL"}; do
    [[ "$m" =~ ^[A-Za-z0-9._-]+(\[[A-Za-z0-9]+\])?$ && "$m" != *:* ]] ||
        fail "'$m' is not a Claude model id; only the claude CLI can reconcile, so
       --reconciler takes a model it accepts (claude-opus-5-5)."
done

# The reviewer list, one "<slug> <cli> <model>" line each. The slug names the
# reviewer's files, so it is the model id folded to what a file name takes;
# two reviewers on one model would share them, and are refused.
parse_reviewers() {
    local spec="$1" item cli model slug seen=" "
    [[ -n "$spec" ]] || fail "the reviewer list is empty.
$USAGE"
    IFS=',' read -r -a items <<<"$spec"
    for item in "${items[@]}"; do
        item="${item//[[:space:]]/}"
        [[ -n "$item" ]] || continue
        [[ "$item" =~ ^(claude|grok|gemini):([A-Za-z0-9._-]+(\[[A-Za-z0-9]+\])?)$ ]] ||
            fail "'$item' is not <cli>:<model> with a CLI this script drives
       (claude, grok, gemini).
$USAGE"
        cli="${BASH_REMATCH[1]}" model="${BASH_REMATCH[2]}"
        slug="$(tr 'A-Z' 'a-z' <<<"$model" | tr -c 'a-z0-9.\n-' '-' | sed 's/-*$//')"
        [[ "$seen" != *" $slug "* ]] || fail "'$model' is named twice in the reviewer list."
        seen+="$slug "
        printf '%s %s %s\n' "$slug" "$cli" "$model"
    done
}
if [[ "$MODE" == review && -z "$ONLY" ]]; then
    REVIEWER_LINES="$(parse_reviewers "$REVIEWERS_SPEC")" || exit 1
    [[ -n "$REVIEWER_LINES" ]] || fail "the reviewer list is empty.
$USAGE"
fi

# jq as well as gh: without it every field of the PR comes back empty, and
# the failure surfaced steps later as "could not fetch  from origin."
for tool in gh jq; do
    command -v "$tool" >/dev/null 2>&1 || fail "$tool is not on PATH."
done
PR_JSON="$(gh pr view ${PR_ARG:+"$PR_ARG"} --json \
           number,title,url,body,state,baseRefName,headRefName,headRefOid 2>&1)" ||
    fail "no pull request for ${PR_ARG:-this branch}: $PR_JSON"
field() { jq -r ".$1 // \"\"" <<<"$PR_JSON"; }
N="$(field number)"
# <pr> may be a URL, and gh follows one into whatever repository it names.
# Every later call hands gh the bare number, which it takes to THIS checkout.
# Reviewing over there and posting here would comment on a different PR.
REPO_JSON="$(gh repo view --json nameWithOwner,url 2>/dev/null)" ||
    fail "could not tell which GitHub repository this checkout is."
REPO="$(jq -r .nameWithOwner <<<"$REPO_JSON")"
REPO_URL="$(jq -r .url <<<"$REPO_JSON")"
[ -n "$REPO_URL" ] && [ "$REPO_URL" != null ] ||
    fail "gh did not report this repository's url."
case "$(field url)" in
    "$REPO_URL/pull/"*) ;;
    *)
        PR_REPO="$(field url)"
        PR_REPO="${PR_REPO#*://*/}"
        fail "#$N is a pull request of ${PR_REPO%/pull/*}, and this checkout is $REPO; review it from a checkout of its own repository"
        ;;
esac
WORK="$REPO_ROOT/build/review/pr-$N"
INPUT="$WORK/input"
CODE="$INPUT/code"

remove_checkouts() {
    git worktree remove --force "$CODE" >/dev/null 2>&1
    git worktree prune >/dev/null 2>&1
    git update-ref -d "refs/review/pr-$N" >/dev/null 2>&1
}

# --- --post ----------------------------------------------------------------------------
if [[ "$MODE" == post ]]; then
    [[ -d "$WORK" ]] || fail "#$N has not been reviewed here; run scripts/review_pr.sh $N first."
    # Refused before stdin is read, so a refusal replaces nothing, and an
    # older run folder is named as one whether or not it has a summary.md.
    [[ -s "$WORK/reviewers" ]] ||
        fail "$WORK comes from an older version of this script; review again:
       scripts/review_pr.sh $N"
    compgen -G "$WORK/review-*.md" >/dev/null ||
        fail "no review finished, so there is nothing to post."
    REHEARSAL=""
    [[ -n "${GPR_REVIEW_NO_POST:-}" && "${GPR_REVIEW_NO_POST}" != 0 ]] && REHEARSAL=1
    SUMMARY=summary.md
    if [[ -n "$SUMMARY_ON_STDIN" ]]; then
        # A rehearsal keeps the report in a file of its own: written over
        # summary.md, it replaced the reconciled report and its credit, and a
        # later --post without - posted the draft as "Reconciled by hand".
        [[ -z "$REHEARSAL" ]] || SUMMARY=summary-draft.md
        # Read whole and refused when empty before anything is written:
        # written straight over summary.md, an empty stdin wiped the
        # reconciled report and its credit, and was then refused as a
        # reconcile that had not finished.
        DRAFT="$(cat)"
        [[ -n "$DRAFT" ]] ||
            fail "nothing came on stdin, so there is no report to post; $WORK/summary.md is as it was."
        printf '%s\n' "$DRAFT" > "$WORK/$SUMMARY" || fail "could not write $WORK/$SUMMARY"
        # A report written by hand; the header must not credit the reconciler.
        [[ -n "$REHEARSAL" ]] || rm -f "$WORK/reconciler.meta.json"
    fi
    [[ -s "$WORK/$SUMMARY" ]] ||
        fail "there is no $WORK/summary.md: the reconcile has not run or did not
       finish. Run it again: scripts/review_pr.sh --reconcile $N"

    python3 - "$WORK" "$MARKER" "$(field headRefOid)" "$COVERAGE_MARKER" "$SUMMARY" "$SUMMARY_ON_STDIN" <<'PY' || fail "could not assemble the comment."
import json, os, sys
work, marker, current_head, coverage_marker = sys.argv[1:5]
# The summary's file name, and whether it came from stdin: optional, so that
# a caller passing only the first four - the GPRaw app's harness cuts this
# block out and runs it so - still assembles summary.md as it always did.
summary_name = sys.argv[5] if len(sys.argv) > 5 else "summary.md"
by_hand = len(sys.argv) > 6 and sys.argv[6] != ""
# claude-test-gap-check.yml's last step deletes every comment whose body
# CONTAINS its marker, except its own newest. A review that quotes that
# marker would be deleted when that pass finished. So it is
# respelled wherever a reviewer or the summary wrote it, with a backslash
# after the "<": that reads the same outside a code span, stays legible inside
# one, and unlike a break at the closing "-->" cannot open an HTML comment
# that swallows the rest of the body.
# claude-review.yml deletes every comment containing its marker except its
# newest, the same way the test-gap job does. A review of either workflow
# quotes the marker, and the comment carrying it would be deleted when that
# job next ran.
hide = (
    coverage_marker,
    "<!-- gpr-claude-review -->",
)
def read(name):
    try:
        text = open(os.path.join(work, name), encoding="utf-8").read().strip()
    except OSError:
        return ""
    for marker_to_hide in hide:
        text = text.replace(marker_to_hide, marker_to_hide[:1] + "\\" + marker_to_hide[1:])
    return text
reviewed = read("reviewed-sha")
# Who was asked, in the order they were asked: "<slug> <cli> <model>" lines.
reviewers = []
for line in read("reviewers").splitlines():
    parts = line.split()
    if len(parts) == 3:
        reviewers.append(dict(zip(("slug", "cli", "model"), parts)))
# Each reviewer's name and label are the checker's (below, "check what came
# back"), written into its meta file; a reviewer with no meta file never got
# that far and is named by what was asked. Finished means its review file
# exists: the checker writes one only for a review it accepted, never empty.
def meta_of(slug):
    try:
        return json.load(open(os.path.join(work, slug + ".meta.json")))
    except (OSError, ValueError):
        return {}
for r in reviewers:
    r["meta"] = meta_of(r["slug"])
    # The model the run reported, which is what reviewed, over the one asked.
    r["ran"] = r["meta"].get("model") or r["model"]
    r["name"] = r["meta"].get("name") or f"`{r['cli']}:{r['model']}`"
    r["label"] = r["meta"].get("label") or r["cli"]
    r["finished"] = os.path.exists(os.path.join(work, f"review-{r['slug']}.md"))
    r["text"] = read(f"review-{r['slug']}.md")
finished = [r for r in reviewers if r["finished"]]
# A report from stdin credits no model, even in a rehearsal, which leaves
# reconciler.meta.json in place.
try:
    reconciler = {} if by_hand else json.load(open(os.path.join(work, "reconciler.meta.json")))
except (OSError, ValueError):
    reconciler = {}
if reconciler.get("model"):
    reconciled = f"Reconciled by `{reconciler['model']}`"
    if reconciler.get("fallback_from"):
        reconciled += (f", because `{reconciler['fallback_from']}` was out "
                       "of its subscription token limit")
    reconciled += "; each review is below in full."
else:
    reconciled = "Reconciled by hand; each review is below in full."

def listed(names):
    return names[0] if len(names) == 1 else ", ".join(names[:-1]) + " and " + names[-1]

def row(r):
    m = r["meta"]
    model = f"`{r['ran']}`"
    if m.get("effort"):
        model += ", effort " + m["effort"]
    if r["finished"]:
        outcome = m.get("verdict", "?")
    elif m.get("skipped"):
        outcome = "skipped: " + m["skipped"]
    else:
        outcome = "did not finish: " + m.get("problem", "not run")
    return f"| {r['label']} | {model} | {outcome} |"

count = len(finished)
head = [
    marker,
    f"## Review of `{reviewed[:7]}` by {count} model{'s' if count != 1 else ''}",
    "",
    (f"{listed([r['name'] for r in finished])} reviewed this pull request "
     + ("independently, " if count > 1 else "")
     + f"from its merge base to `{reviewed[:7]}`, against CLAUDE.md's review standards. "
     + reconciled) if finished else "No review finished. " + reconciled,
    "",
    "| Reviewer | Model | Verdict |",
    "|---|---|---|",
] + [row(r) for r in reviewers] + [""]
if current_head and reviewed and current_head != reviewed:
    head += [f"**The pull request has moved to `{current_head[:7]}` since; this review "
             f"is of `{reviewed[:7]}`.**", ""]
tails = [(f"<details><summary>{r['name']}'s full review</summary>\n\n", r["text"], "\n\n</details>\n")
         for r in finished]

def clip(text, room):
    """At most `room` characters: the text whole, or its start and a notice of
    exactly how many characters were left out."""
    if len(text) <= room:
        return text
    # Sized for the longest the count can be, so the result never overruns.
    keep = max(room - len(f"\n\n[... {len(text)} more characters not shown]"), 0)
    return text[:keep] + f"\n\n[... {len(text) - keep} more characters not shown]"

# GitHub refuses a comment body over 65536 characters, and refuses it only at
# the post, after every reviewer has run. So the body is fitted here, under a
# margin. The summary is cut only when it would not fit on its own, leaving
# each full review RESERVE for its wrapper and its notice. The reviews then
# take the rest in turn, so room one does not use passes to the next.
LIMIT = 65000
RESERVE = 300
body = "\n".join(head) + "\n"
body += clip(read(summary_name), LIMIT - len(body) - 1 - RESERVE * len(tails)) + "\n"
for i, (opening, text, closing) in enumerate(tails):
    room = (LIMIT - len(body)) // (len(tails) - i) - len(opening) - len(closing) - 1
    body += "\n" + opening + clip(text, room) + closing
if len(body) > 65536:
    sys.exit(f"the comment came to {len(body)} characters, over GitHub's 65536")
json.dump({"body": body}, open(os.path.join(work, "comment.json"), "w"))
PY

    # Edited in place when an earlier run's comment is there, so one stands.
    EXISTING="$(gh api --paginate "repos/$REPO/issues/$N/comments" \
                --jq ".[] | select(.body | startswith(\"$MARKER\")) | .id" | tail -n 1)"
    # Asked before anything is posted, so a rehearsal reports the same answer
    # the real run would act on. When it cannot be had the label is left
    # alone: applying it blind is what cancels a pass already on the runner,
    # and a pass that was wanted after all is one click to ask for by hand.
    #
    # Asked only where the base branch has the workflow. adeelabbas/gpr has
    # no claude-test-gap-check.yml (gpraw/gpr does): there is no pass to
    # start or to cancel, and `gh run list --workflow` fails there, which
    # would read as a state that could not be had and tell the operator to
    # apply the label by hand for a pass no workflow can run. The review run
    # fetched the base into origin/<base>; a checkout without that ref asks
    # its own working tree.
    BASE="$(field baseRefName)"
    HAS_WORKFLOW=""
    if git rev-parse -q --verify "refs/remotes/origin/$BASE" >/dev/null 2>&1; then
        git cat-file -e "refs/remotes/origin/$BASE:.github/workflows/$WORKFLOW" 2>/dev/null &&
            HAS_WORKFLOW=1
    elif [[ -f "$REPO_ROOT/.github/workflows/$WORKFLOW" ]]; then
        HAS_WORKFLOW=1
    fi
    COVERAGE=unknown HAS_LABEL=0
    COVERAGE_WHY="could not read #$N's commits or its $WORKFLOW runs"
    if [[ -z "$HAS_WORKFLOW" ]]; then
        COVERAGE=none
        COVERAGE_WHY="this repository has no $WORKFLOW on $BASE, so there is no test-gap pass to start"
    elif STATE="$(coverage_state)"; then
        { read -r COVERAGE; read -r HAS_LABEL; read -r COVERAGE_WHY; } <<<"$STATE"
    fi
    if [[ -n "$REHEARSAL" ]]; then
        echo "rehearsal (GPR_REVIEW_NO_POST): nothing posted, labeled or removed."
        # Not ${EXISTING:-post a new comment} after the :+ form: that expands to
        # the id itself when there is one, and the line named the comment twice.
        COMMENT_PLAN="post a new comment"
        [[ -n "$EXISTING" ]] && COMMENT_PLAN="edit comment $EXISTING"
        echo "  comment: $WORK/comment.json, $(jq -r '.body | length' "$WORK/comment.json") characters;" \
             "would $COMMENT_PLAN on #$N"
        case "$COVERAGE:$HAS_LABEL" in
            wanted:0)  echo "  label:   would add $LABEL, starting $WORKFLOW: $COVERAGE_WHY" ;;
            wanted:1)  echo "  label:   would remove and re-add $LABEL, starting $WORKFLOW: $COVERAGE_WHY" ;;
            none:*)    echo "  label:   would not touch $LABEL: $COVERAGE_WHY" ;;
            unknown:*) echo "  label:   would leave $LABEL as it is: $COVERAGE_WHY" ;;
            *:0)       echo "  label:   would not add $LABEL: $COVERAGE_WHY" ;;
            *)         echo "  label:   would leave $LABEL on without re-applying it: $COVERAGE_WHY" ;;
        esac
        exit 0
    fi
    if [[ -n "$EXISTING" ]]; then
        URL="$(gh api -X PATCH "repos/$REPO/issues/comments/$EXISTING" \
               --input "$WORK/comment.json" --jq .html_url)" ||
            fail "could not update comment $EXISTING on #$N."
    else
        URL="$(gh api -X POST "repos/$REPO/issues/$N/comments" \
               --input "$WORK/comment.json" --jq .html_url)" ||
            fail "could not comment on #$N."
    fi
    echo "comment: $URL"

    # Every outcome is a `label:` line that reads on its own; /review passes it
    # on to the user as it stands.
    case "$COVERAGE:$HAS_LABEL" in
        wanted:*)
            # `labeled` is the only event that starts the workflow, and it
            # fires when a label goes on, not while it sits there. So a label
            # an earlier /review left on comes off first - the workflow's own
            # header gives "remove and re-apply" as the way to run again, and
            # it does not listen for `unlabeled`, so taking it off starts
            # nothing. Leaving it would make whether a moved head gets its
            # pass depend on whether some earlier run had labeled the PR,
            # which is history and not the state of the head. Two calls, so
            # the removal has landed before the label goes back on; gh
            # promises no order for the two flags given together.
            if (( HAS_LABEL )) && ! gh pr edit "$N" --remove-label "$LABEL" >/dev/null; then
                echo "warning: could not take the $LABEL label off #$N to apply it again," \
                     "so $WORKFLOW was not started" >&2
            elif gh pr edit "$N" --add-label "$LABEL" >/dev/null; then
                (( HAS_LABEL )) && VERB="removed and re-added $LABEL" || VERB="added $LABEL"
                echo "label:   $VERB, which starts $WORKFLOW's test-gap pass on #$N"
                echo "         (when the PR touches that workflow's paths): $COVERAGE_WHY"
            else
                echo "warning: could not add the $LABEL label to #$N" >&2
            fi ;;
        none:*)
            echo "label:   did not touch $LABEL: $COVERAGE_WHY" ;;
        unknown:*)
            echo "label:   left $LABEL as it is: $COVERAGE_WHY. If this head needs a pass,"
            echo "         apply the label by hand, taking it off first if it is on." ;;
        *:0)
            echo "label:   did not add $LABEL: $COVERAGE_WHY" ;;
        *)
            echo "label:   left $LABEL on without re-applying it: $COVERAGE_WHY" ;;
    esac

    remove_checkouts
    exit 0
fi

# --- a checkout of the head, and what git would say about it ------------------------------
# Claude and perl in every mode: the reconciler runs after any review run. A
# reviewer's own CLI is checked when that reviewer runs, and a missing one
# skips it rather than stopping the others.
for cli in "$CLAUDE" perl; do
    command -v "$cli" >/dev/null 2>&1 || fail "'$cli' is not on PATH."
done
timeout_seconds() {
    local spec="$1" name="$2"
    [[ "$spec" =~ ^([0-9]+)([smh]?)$ ]] ||
        fail "$name must be seconds, or end in s, m or h (e.g. 30m)."
    case "${BASH_REMATCH[2]}" in
        h) echo $(( BASH_REMATCH[1] * 3600 )) ;;
        m) echo $(( BASH_REMATCH[1] * 60 )) ;;
        *) echo $(( BASH_REMATCH[1] )) ;;
    esac
}
# Zero would be no limit at all: alarm(0) cancels the alarm.
RECONCILE_TIMEOUT_S="$(timeout_seconds "$RECONCILE_TIMEOUT" GPR_REVIEW_RECONCILE_TIMEOUT)"
(( RECONCILE_TIMEOUT_S > 0 )) || fail "GPR_REVIEW_RECONCILE_TIMEOUT must be more than zero."
[[ -r "$RECONCILER_BRIEF" ]] || fail "there is no reconciler brief at $RECONCILER_BRIEF."

# What makes a Claude run read-only, for the reviewers and the reconciler
# alike: run_claude, below, says why each flag is there. One list, so the
# boundary cannot differ between the two.
CLAUDE_READ_ONLY=(--restricted --strict-mcp-config --tools Read,Grep,Glob --permission-mode dontAsk)

# --- the reconciler ------------------------------------------------------------------------
# One headless run over the reviews that finished, under the Claude reviewer's
# read-only flags (run_claude, below, says why each is there). It starts in
# $WORK rather than input/, because the reviews sit beside input/, not in it.
# When the named model reports its subscription allowance spent, the fallback
# model runs the same prompt. Any other failure stays a failure, and
# --reconcile repeats it without re-running a reviewer.
run_reconciler() {
    local model="$1" tag="$2"
    (cd "$WORK" && perl -e 'alarm shift; exec @ARGV or die "exec: $!\n"' "$RECONCILE_TIMEOUT_S" \
         "$CLAUDE" -p --model "$model" --effort "$RECONCILE_EFFORT" \
         "${CLAUDE_READ_ONLY[@]}" \
         --max-turns 60 --no-session-persistence \
         --output-format stream-json --verbose < "$WORK/reconcile-prompt.md") \
        > "$WORK/reconcile-$tag-stream.jsonl" 2> "$WORK/reconcile-$tag-stderr.log"
    echo $? > "$WORK/reconcile-$tag-exit"
}

# The brief with this run's facts filled in, on stdout: which reviewers were
# asked, which finished and where each review is, and which did not.
reconcile_prompt() {
    python3 - "$RECONCILER_BRIEF" "$WORK" "$N" "$(field title)" \
        "$(cat "$WORK/reviewed-sha")" <<'PY'
import json, os, sys
brief, work, n, title, sha = sys.argv[1:6]
# Names and "finished" as the comment assembler reads them: the checker's
# name from the meta file, and a review file that exists.
reviews, names, missing = [], [], []
for line in open(os.path.join(work, "reviewers"), encoding="utf-8").read().splitlines():
    parts = line.split()
    if len(parts) != 3:
        continue
    slug, cli, model = parts
    try:
        meta = json.load(open(os.path.join(work, slug + ".meta.json")))
    except (OSError, ValueError):
        meta = {}
    name = meta.get("name") or f"`{cli}:{model}`"
    path = os.path.join(work, f"review-{slug}.md")
    if os.path.exists(path):
        reviews.append(f"- `{path}` - {name}'s review.")
        names.append(name)
    else:
        why = meta.get("skipped") or meta.get("problem") or "it did not run"
        missing.append(f"- {name}'s review did not finish ({why}); there is no `{path}`.")
text = open(brief, encoding="utf-8").read()
for key, value in (("@WORK@", work), ("@REVIEWS@", "\n".join(reviews)),
                   ("@REVIEWERS@", ", ".join(names)), ("@MISSING@", "\n".join(missing))):
    text = text.replace(key, value)
count = len(reviews)
print(f'Reconcile the {count} review{"s" if count != 1 else ""} of pull request #{n}, '
      f'"{title}", at head commit {sha}.\n')
print(text)
PY
}

# Accepts the reconciler's reply into summary.md only when the run finished
# cleanly, on the model asked for, and the text ends with END OF REPORT.
settle_reconcile() {
    python3 - "$WORK" "$1" "$2" "$3" "$RECONCILE_EFFORT" "$RECONCILE_TIMEOUT" <<'PY'
import json, os, sys
work, tag, model, from_model, effort, limit = sys.argv[1:7]
END = "END OF REPORT"
def slurp(name):
    try:
        return open(os.path.join(work, name), encoding="utf-8").read()
    except OSError:
        return ""
rows = []
for line in slurp(f"reconcile-{tag}-stream.jsonl").splitlines():
    try:
        rows.append(json.loads(line))
    except ValueError:
        pass
init = next((r for r in rows if r.get("type") == "system" and r.get("subtype") == "init"), {})
result = next((r for r in reversed(rows) if r.get("type") == "result"), {})
ran_on = init.get("model") or model
# A closing period is tolerated: Haiku wrote "END OF REPORT." in rehearsal.
text = (result.get("result") or "").strip().removesuffix(".")
problems = []
if slurp(f"reconcile-{tag}-exit").strip() == "142":
    problems.append(f"it was stopped at its {limit} time limit (GPR_REVIEW_RECONCILE_TIMEOUT)")
elif result.get("subtype") != "success" or result.get("is_error"):
    # The CLI's own error first, as the reviewers' check reads it.
    err = (result.get("result") or "").strip().splitlines()[-1:] if result.get("is_error") else []
    err = err or slurp(f"reconcile-{tag}-stderr.log").strip().splitlines()[-1:] or [""]
    problems.append(f"the run ended {result.get('subtype') or 'without a result'} {err[0][:200]}".rstrip())
if model.startswith("claude-") and not ran_on.startswith(model):
    problems.append(f"it ran on {ran_on}, not {model}")
if not problems and not text.endswith(END):
    problems.append("the report does not end with END OF REPORT, so it is truncated or malformed")
if not problems and "### Blocking" not in text:
    problems.append("the report has no Blocking section")
if problems:
    print(f"  reconcile: FAILED - {'; '.join(problems)}", file=sys.stderr)
    print(f"  Its record is {os.path.join(work, 'reconcile-' + tag + '-stream.jsonl')}.", file=sys.stderr)
    sys.exit(1)
open(os.path.join(work, "summary.md"), "w", encoding="utf-8").write(text[: -len(END)].rstrip() + "\n")
json.dump({"model": ran_on, "effort": effort, "fallback_from": from_model or None},
          open(os.path.join(work, "reconciler.meta.json"), "w"))
minutes = (result.get("duration_ms") or 0) / 60000
print(f"  reconcile: {ran_on}, {result.get('num_turns', '?')} turns, "
      f"${float(result.get('total_cost_usd') or 0):.2f}, {minutes:.1f} min  -> {os.path.join(work, 'summary.md')}")
PY
}

reconcile() {
    if [[ ! -s "$WORK/reviewers" ]]; then
        echo "  reconcile: FAILED - $WORK comes from an older version of this script;" \
             "review again: scripts/review_pr.sh $N" >&2
        return 1
    fi
    # Cleared after that refusal, which leaves an older run folder as it was.
    rm -f "$WORK"/reconcile-* "$WORK/summary.md" "$WORK/reconciler.meta.json"
    if ! compgen -G "$WORK/review-*.md" >/dev/null; then
        echo "  reconcile: skipped - no review finished, so there is nothing to reconcile." >&2
        return 1
    fi
    if [[ ! -d "$CODE" ]]; then
        echo "  reconcile: FAILED - the checkout of the head is gone (--post removes it);" \
             "review again: scripts/review_pr.sh $N" >&2
        return 1
    fi
    local model="$RECONCILE_MODEL" tag=primary from="" spent=""
    reconcile_prompt > "$WORK/reconcile-prompt.md" ||
        { echo "  reconcile: FAILED - could not write its prompt." >&2; return 1; }

    echo "  reconcile: $model, in $WORK"
    run_reconciler "$model" "$tag"
    if claude_subscription_exhausted "$WORK/reconcile-$tag-stream.jsonl" "$WORK/reconcile-$tag-stderr.log"; then
        if [[ -n "$RECONCILE_FALLBACK_MODEL" && "$RECONCILE_FALLBACK_MODEL" != "$model" ]]; then
            echo "  reconcile: $model is out of its subscription token limit;" \
                 "reconciling with $RECONCILE_FALLBACK_MODEL instead."
            from="$model" model="$RECONCILE_FALLBACK_MODEL" tag=fallback
            run_reconciler "$model" "$tag"
        else
            echo "  reconcile: $model is out of its subscription token limit, and" \
                 "no --reconcile-fallback names another model;" \
                 "run --reconcile again once the allowance refills." >&2
            spent=1
        fi
    fi
    settle_reconcile "$tag" "$model" "$from" || {
        # A spent allowance already said when to retry; now is not it.
        [[ -n "$spent" ]] ||
            echo "  Try the reconcile alone again: scripts/review_pr.sh --reconcile $N" >&2
        return 1
    }
}

if [[ "$MODE" == reconcile ]]; then
    [[ -d "$WORK" ]] || fail "#$N has not been reviewed here; run scripts/review_pr.sh $N first."
    reconcile || exit 1
    echo "Post it with: scripts/review_pr.sh --post $N"
    exit 0
fi

# This run's reviewers: the whole list, or the one --only names from the
# last run's list.
if [[ -n "$ONLY" ]]; then
    [[ -s "$WORK/reviewers" ]] ||
        fail "there is no earlier run of #$N to re-run one reviewer of. Review it: scripts/review_pr.sh $N"
    RUN_LINES="$(awk -v want="$ONLY" '
        want == $2 ":" $3 || want == $3 || want == $1 || want == $2 { print; n++ }
        END { exit n == 1 ? 0 : 1 }' "$WORK/reviewers")" ||
        fail "--only $ONLY does not name exactly one reviewer of the last run of #$N;
       name one of:
$(awk '{ print "         " $2 ":" $3 }' "$WORK/reviewers")"
else
    RUN_LINES="$REVIEWER_LINES"
fi
# Zero would be no limit at all: alarm(0) cancels the alarm.
for cli in $(awk '{ print $2 }' <<<"$RUN_LINES" | sort -u); do
    case "$cli" in
        claude) CLAUDE_TIMEOUT_S="$(timeout_seconds "$CLAUDE_TIMEOUT" GPR_REVIEW_CLAUDE_TIMEOUT)"
                (( CLAUDE_TIMEOUT_S > 0 )) || fail "GPR_REVIEW_CLAUDE_TIMEOUT must be more than zero." ;;
        grok)   GROK_TIMEOUT_S="$(timeout_seconds "$GROK_TIMEOUT" GPR_REVIEW_GROK_TIMEOUT)"
                (( GROK_TIMEOUT_S > 0 )) || fail "GPR_REVIEW_GROK_TIMEOUT must be more than zero." ;;
        gemini) timeout_seconds "$GEMINI_TIMEOUT" GPR_REVIEW_GEMINI_TIMEOUT >/dev/null ;;
    esac
done
[[ -r "$BRIEF" ]] || fail "there is no reviewer brief at $BRIEF."

BASE="$(field baseRefName)"
git fetch --quiet origin "refs/heads/$BASE" || fail "could not fetch $BASE from origin."
# Into a ref of this PR's own, not FETCH_HEAD: that file is one per
# checkout, so two reviews started together from one checkout read each
# other's fetch. #41 and #42 of gpraw/gpr did, on 2026-09-23: one run found
# FETCH_HEAD mid-write and stopped, and it could as well have reviewed the
# other PR's head (measured on a scratch pair: the old read took the
# other PR's head in 10 rounds of 10, this one in none of 10).
# remove_checkouts drops the ref, at the start of a full run as well as at
# --post: a commit just fetched outlives its ref by gc's two-week grace,
# and the checkout's HEAD holds it from the worktree add on.
git fetch --quiet origin "+refs/pull/$N/head:refs/review/pr-$N" ||
    fail "could not fetch the head of #$N from origin."
HEAD_SHA="$(git rev-parse --verify -q "refs/review/pr-$N^{commit}")" ||
    fail "could not read the head of #$N that was just fetched."
MB="$(git merge-base "origin/$BASE" "$HEAD_SHA")" ||
    fail "#$N's head $HEAD_SHA shares no history with origin/$BASE."

if [[ -n "$ONLY" ]]; then
    [[ -d "$CODE" && "$(cat "$WORK/reviewed-sha" 2>/dev/null)" == "$HEAD_SHA" ]] ||
        fail "there is no earlier run of #$N at its current head ${HEAD_SHA:0:7} to add
       one review to. Review it: scripts/review_pr.sh $N"
else
    remove_checkouts
    rm -rf "$WORK"
    mkdir -p "$INPUT" || fail "could not create $INPUT"
    git worktree add --quiet --detach "$CODE" "$HEAD_SHA" ||
        fail "could not check out ${HEAD_SHA:0:7} into $CODE"
    echo "$HEAD_SHA" > "$WORK/reviewed-sha"
    printf '%s\n' "$RUN_LINES" > "$WORK/reviewers"

    {
        echo "# Pull request #$N: $(field title)"
        echo ""
        echo "- URL: $(field url)"
        echo "- State: $(field state)"
        echo "- Base: \`$BASE\`, merge base \`$MB\`"
        echo "- Head: \`$(field headRefName)\` at \`$HEAD_SHA\`"
        echo ""
        echo "## Description, as the author wrote it"
        echo ""
        field body
        echo ""
        echo "## Files changed"
        echo ""
        echo '```'
        git diff -M --stat=200,150 --summary "$MB" "$HEAD_SHA"
        echo '```'
    } > "$INPUT/pr.md"
    git diff -M "$MB" "$HEAD_SHA" > "$INPUT/diff.patch"
    git log --reverse --format='## %h %s%n%n%b' "$MB..$HEAD_SHA" > "$INPUT/commits.md"
    # The standard is the base branch's CLAUDE.md, not the head's, so a PR
    # cannot loosen the rules it is judged by. claude-code-action does the
    # same in CI ("Restoring ... CLAUDE.md ... from origin/main (PR head is
    # untrusted)").
    git show "origin/$BASE:CLAUDE.md" > "$INPUT/CLAUDE.md" ||
        fail "origin/$BASE has no CLAUDE.md to review against."
    # Grok loads a CLAUDE.md, AGENTS.md, or rules directory when it reads the
    # folder that holds it, and a deeper file overrides the one from startup.
    # The nested git init below only stops the walk upward. The head checkout
    # is full of the PR's own copies, so those are lifted out after the diff
    # is written: the diff still shows the edit, and the file a reviewer reads
    # is head-CLAUDE.md, a name Grok does not treat as instructions.
    # No --trust, so this directory is not granted the project's skills or hooks.
    if [[ -f "$CODE/CLAUDE.md" ]]; then
        mv "$CODE/CLAUDE.md" "$INPUT/head-CLAUDE.md" ||
            fail "could not move the head's CLAUDE.md out of the checkout."
    fi
    strip_loaded_instructions "$CODE"
    # input/ sits inside this repository, so without its own git root the
    # upward walk would load this checkout's CLAUDE.md and the PR could loosen
    # the standard. A nested init stops the walk here. The only CLAUDE.md at
    # that root is the base-branch file above.
    git init --quiet -- "$INPUT" || fail "could not isolate $INPUT as its own git root."
fi

# --- what the reviewers cannot run, run here --------------------------------------------
# No reviewer can run a command, so a question only running something
# answers stays open however carefully it is read. The cheap one - whether
# each changed script still parses - is settled here before the reviewers
# start and handed over as input/checks.md, which the reconciler reads as
# well.
#
# Whether the CLI takes a model id the change names is not asked here,
# though that is the question both reviews of a change that moved every
# Claude job to a new model left open. A probe of it had to copy each
# reviewer's command line and tell a refusal from a spent allowance or a
# timeout a second time, and three reviews of the probe found it drifting
# from both; a reviewer whose CLI refuses its model already fails, by name,
# in the run that uses it.
#
# checks_plan decides what to check from the diff alone: every shell or
# Python file the change leaves in place.
checks_plan() {
    python3 - "$INPUT/diff.patch" <<'PY'
import re, sys
scripts = []
for line in open(sys.argv[1], encoding="utf-8", errors="replace"):
    if not line.startswith("+++ "):
        continue
    target = line[4:].strip()
    path = target[2:] if target.startswith("b/") else None
    if path and re.search(r"\.(sh|py)$", path) and path not in scripts:
        scripts.append(path)
for path in scripts:
    print(f"script {path}")
PY
}

# input/checks.md: what checks_plan asked for, and what running it said.
write_checks() {
    local plan kind a
    plan="$(checks_plan)" || return 1
    echo "# Checks run before the review"
    echo ""
    echo "Run by scripts/review_pr.sh against the head, because no reviewer can run"
    echo "a command. Take them as settled."
    echo ""
    echo "## Changed scripts"
    echo ""
    grep -q '^script ' <<<"$plan" || echo "None."
    while read -r kind a; do
        [[ "$kind" == script ]] || continue
        if [[ ! -f "$CODE/$a" ]]; then
            echo "- \`$a\`: not in the head checkout."
        elif [[ "$a" == *.sh ]]; then
            if err="$(bash -n "$CODE/$a" 2>&1)"; then
                echo "- \`$a\`: \`bash -n\` passes."
            else
                echo "- \`$a\`: \`bash -n\` fails: ${err//$CODE\//}"
            fi
        elif err="$(python3 -c 'import ast, sys; ast.parse(open(sys.argv[1], encoding="utf-8").read(), sys.argv[1])' "$CODE/$a" 2>&1)"; then
            echo "- \`$a\`: parses as Python."
        else
            echo "- \`$a\`: does not parse as Python: $(tail -n 1 <<<"${err//$CODE\//}")"
        fi
    done <<<"$plan"
}

# Absolute paths throughout: the brief names every file that way so a
# reviewer that can search outside input/ still has nothing to look for.
BRIEF_TEXT="$(cat "$BRIEF")"
{
    echo "Review pull request #$N, \"$(field title)\", at head commit $HEAD_SHA."
    echo ""
    printf '%s\n' "${BRIEF_TEXT//@INPUT@/$INPUT}"
} > "$WORK/prompt.md"

# --- the reviewers ------------------------------------------------------------------------
# Claude: --restricted drops every tool that runs code, ignores the user,
# project and local settings files - so neither a hook nor an allow rule
# from the PR's own .claude/settings.json applies - and confines the file
# tools to the working directory. It does not load CLAUDE.md either, which is
# why the brief has the reviewer read the base branch's copy.
#
# --strict-mcp-config because --restricted still loads MCP servers, and a
# subscription login brings its claude.ai connectors (Gmail, Drive, Calendar,
# ...). Their tool definitions came to ~30k tokens in front of every turn,
# measured with a one-word Haiku reply on 2026-09-13: 36k cached input
# without the flag, 6.4k with it - and a reviewer reading untrusted PR text
# has no business holding a Gmail tool.
#
# A wall-clock limit as well as --max-turns, which bounds turns but not a
# CLI that stops returning: the `wait` below would then block forever, and
# /review would never get the notification it waits for. Neither claude nor
# grok has a print-timeout flag, and macOS ships no `timeout`. Perl's alarm
# survives the exec, so the CLI itself is sent SIGALRM when the time is up
# and exits 142. Measured on 2026-09-13: a claude -p asked for 3000 lines of
# output died at exactly 4 s under a 4 s alarm, leaving no process behind.
#
# Every run_* takes the reviewer's slug and model, and writes <slug>-* beside
# the review.
run_claude() {
    local slug="$1" model="$2"
    (cd "$INPUT" && perl -e 'alarm shift; exec @ARGV or die "exec: $!\n"' "$CLAUDE_TIMEOUT_S" \
         "$CLAUDE" -p --model "$model" --effort "$CLAUDE_EFFORT" \
         "${CLAUDE_READ_ONLY[@]}" \
         --max-turns 80 --no-session-persistence \
         --output-format stream-json --verbose < "$WORK/prompt.md") \
        > "$WORK/$slug-stream.jsonl" 2> "$WORK/$slug-stderr.log"
    echo $? > "$WORK/$slug-exit"
}

# Grok, through grok 1.0.40's headless mode (its user-guide/14-headless-mode.md
# and 18-sandbox.md). --tools is an allowlist of internal tool ids, so the
# model never sees a shell, a write or a web tool. It is not the whole set,
# though: asked on 2026-09-21 to name its tools, a run allowlisted to the
# three below answered with search_tool and use_tool as well, the pair that
# reaches whatever MCP servers the machine has configured. None are
# configured here, but that is a fact about this Mac and not about the
# review, so both are denied by name and the same question then answers
# with the three. --disallowed-tools also takes Agent, which with
# --no-subagents blocks a subagent that would not inherit the allowlist.
# --sandbox strict confines reads to --cwd (input/) plus system
# paths and ~/.grok, so a search cannot walk the rest of the machine the
# way an early Gemini review did. --permission-mode dontAsk refuses
# anything that is not already a read-only tool.
# GROK_MEMORY=0 keeps the review from picking up another session's notes.
# The sandbox covers --prompt-file too: grok 1.0.40 refuses
# "$WORK/prompt.md" with "Operation not permitted (os error 1)", since
# $WORK is outside --cwd, and every Grok review of three pull requests in
# a row failed that way. So the prompt is staged inside input/ for the run and
# removed after, which reads fine under the same flags (checked
# 2026-09-22). Named by the slug, so two Grok reviewers cannot remove each
# other's.
run_grok() {
    local slug="$1" model="$2"
    cp "$WORK/prompt.md" "$INPUT/.$slug-prompt.md" || return 1
    (cd "$INPUT" && GROK_MEMORY=0 GROK_DISABLE_AUTOUPDATER=1 \
         perl -e 'alarm shift; exec @ARGV or die "exec: $!\n"' "$GROK_TIMEOUT_S" \
         "$GROK" --prompt-file "$INPUT/.$slug-prompt.md" --cwd "$INPUT" \
         --model "$model" \
         --tools read_file,grep,list_dir \
         --disallowed-tools Agent,search_tool,use_tool \
         --no-subagents --disable-web-search \
         --permission-mode dontAsk --max-turns 80 \
         --output-format json --sandbox strict \
         --verbatim --no-auto-update) \
        > "$WORK/$slug-run.json" 2> "$WORK/$slug-stderr.log"
    echo $? > "$WORK/$slug-exit"
    rm -f "$INPUT/.$slug-prompt.md"
}

# Gemini, through agy. What agy 1.2.2's headless mode does was
# measured on 2026-09-13, and the flags it depends on are still in 1.2.8
# (checked 2026-09-21): --model, --output-format json, --print-timeout,
# --add-dir, and -p last, because -p takes the next argument as the prompt.
#   - It cannot prompt, so it refuses every command and every file write -
#     and every READ, even inside the directory it was started in, unless
#     that directory is also passed with --add-dir. The first refusal ends
#     the whole run with an empty response, status SUCCESS and exit 0, and is
#     named only in denied_actions. One retry, reminded of the limits.
#   - Its find tool will search anywhere without asking, which is why the
#     prompt names every file by absolute path.
#   - When --print-timeout expires it returns what it has, exits 0, and says
#     so only on stderr ("[agy] print timeout ... returning partial output").
#   - The effort is part of the model name; there is no separate flag to set.
run_gemini() {
    local slug="$1" model="$2" prompt refused attempt
    prompt="$(cat "$WORK/prompt.md")"
    for attempt in 1 2; do
        (cd "$INPUT" && "$AGY" --model "$model" --output-format json \
             --print-timeout "$GEMINI_TIMEOUT" --add-dir "$INPUT" -p "$prompt" < /dev/null) \
            > "$WORK/$slug-run.json" 2> "$WORK/$slug-stderr.log"
        refused="$(jq -r '[.denied_actions[]?.display_name] | unique | join(", ")' \
                   "$WORK/$slug-run.json" 2>/dev/null)"
        [[ -n "$refused" && "$attempt" == 1 ]] || break
        mv "$WORK/$slug-run.json" "$WORK/$slug-refused-attempt.json"
        prompt="$prompt

Reminder: this run allows only reading and searching files under $INPUT, by absolute path. Any command, any file write, and any read elsewhere is refused and ends the review."
    done
}

# True when this Grok run stopped because the subscription allowance is spent.
# The phrases are grok 1.0.40's own wording for that (2026-09-21): the plan
# limit, the weekly limit, the free allowance, a spent credit balance, the
# spending cap, and a team's credit limit. The free allowance also comes as
# "You've reached your free Grok Build usage limit for now" (seen
# 2026-09-22), which "free usage limit" does not match. A
# finished review is never this, whatever its text says, and neither is a
# transient "Rate limited" / "The service is busy" - that one is a retry of
# Grok, not a reason to skip it.
grok_out_of_tokens() {
    python3 - "$WORK" "$1" <<'PY'
import json, os, sys
work, slug = sys.argv[1:3]
def slurp(name):
    try:
        return open(os.path.join(work, name), encoding="utf-8").read()
    except OSError:
        return ""
try:
    run = json.loads(slurp(f"{slug}-run.json"))
except ValueError:
    run = {}
text = (run.get("text") or "").strip()
if text.endswith("END OF REVIEW") and run.get("type") != "error":
    sys.exit(1)
blob = " ".join([
    run.get("message") or "",
    run.get("stopReason") or "",
    slurp(f"{slug}-stderr.log"),
]).lower()
phrases = (
    "rate limit for your plan",
    "weekly limit",
    "free usage limit",
    "free grok build usage limit",
    "free-usage-exhausted",
    "out of credits",
    "spending cap",
    "spending limit",
    "usage balance exhausted",
    "usage limit reached",
    "hit your team",
)
sys.exit(0 if any(p in blob for p in phrases) else 1)
PY
}

# One reviewer, from its CLI to a <slug>-skipped note when it could not run
# at all or its allowance is spent. A skip is not a failure: /review does
# not re-run it, and the reconcile goes ahead on the others.
review_with() {
    local slug="$1" cli="$2" model="$3" bin
    # By name, not $slug-*: one slug can be the start of another's.
    rm -f "$WORK/$slug"-{stream.jsonl,run.json,refused-attempt.json,stderr.log,exit,skipped} \
          "$WORK/review-$slug.md" "$WORK/$slug.meta.json"
    case "$cli" in
        claude) bin="$CLAUDE" ;;
        grok)   bin="$GROK" ;;
        gemini) bin="$AGY" ;;
    esac
    if ! command -v "$bin" >/dev/null 2>&1; then
        echo "'$bin' is not on PATH" > "$WORK/$slug-skipped"
        return
    fi
    "run_$cli" "$slug" "$model"
    case "$cli" in
        claude) claude_subscription_exhausted "$WORK/$slug-stream.jsonl" "$WORK/$slug-stderr.log" ;;
        grok)   grok_out_of_tokens "$slug" ;;
        # What agy prints when a Gemini quota is spent has not been seen yet,
        # so a spent Gemini reads as a failure (and /review re-runs it once).
        *)      false ;;
    esac && echo "out of its subscription token limit" > "$WORK/$slug-skipped"
}

# The checks run here, before any reviewer reads checks.md. A re-run of one
# reviewer keeps the checks the full run wrote.
if [[ -z "$ONLY" ]]; then
    write_checks > "$INPUT/checks.md" ||
        echo "warning: could not run the pre-review checks; the reviewers get none." >&2
fi

echo "Reviewing #$N at ${HEAD_SHA:0:7}: $(awk '{ printf "%s%s:%s", (NR > 1 ? ", " : ""), $2, $3 }' <<<"$RUN_LINES"), in $WORK"
echo "  This takes several minutes."
while read -r slug cli model; do
    review_with "$slug" "$cli" "$model" &
done <<<"$RUN_LINES"
wait

# --- check what came back -----------------------------------------------------------------
python3 - "$WORK" "$CLAUDE_EFFORT" "$CLAUDE_TIMEOUT" "$GROK_TIMEOUT" "$RUN_LINES" <<'PY'
import json, os, re, sys
work, claude_effort, claude_timeout, grok_timeout, run_lines = sys.argv[1:6]
END = "END OF REVIEW"
failed = False

def path(name):
    return os.path.join(work, name)

def slurp(name):
    try:
        return open(path(name), encoding="utf-8").read()
    except OSError:
        return ""

def verdict(text):
    m = re.search(r"^Blocking findings:\s*(\d+)", text, re.M)
    return f"{m.group(1)} blocking" if m else "no verdict line"

# The one place a reviewer is named: its CLI's label and the model that ran,
# written into its meta file for the comment and the reconcile prompt.
CLI_NAMES = {"claude": "Claude", "grok": "Grok", "gemini": "Gemini"}
def named(meta, cli, model):
    meta["label"] = CLI_NAMES.get(cli, cli)
    meta["name"] = f"{meta['label']} `{meta.get('model') or model}`"
    return meta

# Whether the model that ran is the one asked. Only a full id can be held to
# that: an alias (claude:opus) resolves to whatever the CLI calls current,
# so it is not checked - the reconciler's own check does the same.
def mismatch(cli, asked, ran_on):
    return asked.startswith(cli + "-") and ran_on and not str(ran_on).startswith(asked)

def settle(label, slug, text, problems, meta, facts):
    global failed
    text = text.strip()
    if not text.endswith(END):
        problems.append("the review does not end with END OF REVIEW, so it is truncated or malformed")
    elif not text[: -len(END)].strip():
        problems.append("the review is empty")
    if problems:
        failed = True
        meta["problem"] = "; ".join(problems)
        print(f"  {label}: FAILED - {meta['problem']}")
    else:
        text = text[: -len(END)].rstrip() + "\n"
        open(path(f"review-{slug}.md"), "w", encoding="utf-8").write(text)
        meta["verdict"] = verdict(text)
        print(f"  {label}: {meta['verdict']}, {facts}  -> {path('review-' + slug + '.md')}")
    json.dump(meta, open(path(f"{slug}.meta.json"), "w"))

# What each CLI left, read into (text, problems, meta, facts).
def read_claude(slug, model):
    rows = []
    for line in slurp(f"{slug}-stream.jsonl").splitlines():
        try:
            rows.append(json.loads(line))
        except ValueError:
            pass
    init = next((r for r in rows if r.get("type") == "system" and r.get("subtype") == "init"), {})
    result = next((r for r in reversed(rows) if r.get("type") == "result"), {})
    ran_on = init.get("model") or model
    problems = []
    if slurp(f"{slug}-exit").strip() == "142":
        problems.append(f"it was stopped at its {claude_timeout} time limit (GPR_REVIEW_CLAUDE_TIMEOUT)")
    elif result.get("subtype") != "success" or result.get("is_error"):
        err = (result.get("result") or "").strip().splitlines()[-1:] if result.get("is_error") else []
        err = err or slurp(f"{slug}-stderr.log").strip().splitlines()[-1:] or [""]
        problems.append(f"the run ended {result.get('subtype') or 'without a result'} {err[0][:200]}".rstrip())
    if mismatch("claude", model, ran_on):
        problems.append(f"it ran on {ran_on}, not {model}")
    minutes = (result.get("duration_ms") or 0) / 60000
    facts = (f"{result.get('num_turns', '?')} turns, ${float(result.get('total_cost_usd') or 0):.2f}, "
             f"{minutes:.1f} min")
    return result.get("result") or "", problems, {"model": ran_on, "effort": claude_effort}, facts

def read_grok(slug, model):
    try:
        run = json.loads(slurp(f"{slug}-run.json"))
    except ValueError:
        run = {}
    stderr = slurp(f"{slug}-stderr.log")
    problems = []
    if slurp(f"{slug}-exit").strip() == "142":
        problems.append(f"it was stopped at its {grok_timeout} time limit (GPR_REVIEW_GROK_TIMEOUT)")
    elif run.get("type") == "error" or not run.get("text"):
        err = run.get("message") or (stderr.strip().splitlines()[-1:] or [""])[0]
        problems.append(f"the run ended {run.get('stopReason') or run.get('type') or 'without JSON output'} {err[:200]}".rstrip())
    ran_on = next(iter(run.get("modelUsage") or {}), model)
    if mismatch("grok", model, ran_on):
        problems.append(f"it ran on {ran_on}, not {model}")
    tokens = run.get("usage") or {}
    facts = (f"{tokens.get('input_tokens', '?')} in / {tokens.get('output_tokens', '?')} out tokens, "
             f"{run.get('num_turns', '?')} turns")
    return run.get("text") or "", problems, {"model": ran_on or model}, facts

def read_gemini(slug, model):
    try:
        run = json.loads(slurp(f"{slug}-run.json"))
    except ValueError:
        run = {}
    stderr = slurp(f"{slug}-stderr.log")
    problems = []
    if run.get("status") != "SUCCESS":
        problems.append(f"the run ended {run.get('status') or 'without JSON output'} {stderr.strip()[-200:]}".rstrip())
    if run.get("denied_actions"):
        names = sorted({d.get("display_name", "?") for d in run["denied_actions"]})
        problems.append("agy refused " + ", ".join(names) + " twice")
    if "print timeout" in stderr or "may be truncated" in stderr:
        problems.append("agy stopped at --print-timeout and returned partial output")
    usage = run.get("usage") or {}
    facts = (f"{usage.get('input_tokens', '?')} in / {usage.get('output_tokens', '?')} out tokens, "
             f"{(run.get('duration_seconds') or 0) / 60:.1f} min")
    return run.get("response") or "", problems, {"model": model}, facts

READERS = {"claude": read_claude, "grok": read_grok, "gemini": read_gemini}
for line in run_lines.splitlines():
    slug, cli, model = line.split()
    label = f"{cli}:{model}"
    skipped = slurp(f"{slug}-skipped").strip()
    if skipped:
        json.dump(named({"model": model, "skipped": skipped}, cli, model),
                  open(path(f"{slug}.meta.json"), "w"))
        print(f"  {label}: skipped - {skipped}")
        continue
    text, problems, meta, facts = READERS[cli](slug, model)
    settle(label, slug, text, problems, named(meta, cli, model), facts)

sys.exit(1 if failed else 0)
PY
STATUS=$?
(( STATUS == 0 )) ||
    echo "Each run's full record is kept in $WORK (<reviewer>-stream.jsonl or -run.json, *-stderr.log)." >&2

# Reconciled after every run, a one-reviewer re-run included, so summary.md is
# always of the reviews on disk. With a reviewer failed or skipped it still
# runs on the others; the skill re-runs a failed one once, which reconciles
# again.
reconcile || STATUS=1
exit "$STATUS"
