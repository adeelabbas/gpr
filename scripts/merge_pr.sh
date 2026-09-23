#!/bin/bash
# Merge a pull request into the default branch, then clean up after it:
# delete its branch on origin and locally, switch this checkout to the
# default branch and pull.
#
# Usage:  scripts/merge_pr.sh [--dry-run] [<pr>]
#
# <pr> is a number, '#number', URL or branch; the default is this branch's
# PR. --dry-run runs every check, says what it would do, and changes nothing.
# It counts before <pr> or after it.
#
# The default branch is GitHub's answer, asked once with the repository
# (step 1): master in adeelabbas/gpr, main in gpraw/gpr. This file is the
# same in both, so the code spells no branch name, and every message prints
# the one GitHub gave.
#
# How it merges is GitHub's answer too, from the same call: the method
# GitHub's merge button offers on this repository (viewerDefaultMergeMethod,
# the one the viewer last used there), when that is a squash or a rebase
# merge and the settings allow it; else a squash where they allow one, else
# a rebase merge. The settings alone cannot tell the two repositories apart
# - both allow every method - and that answer does: SQUASH in gpraw/gpr,
# which squash-merges, and REBASE in adeelabbas/gpr (2026-09-23).
# adeelabbas/gpr keeps README, CLAUDE.md and workflow edits in commits of
# their own on master, so that its code commits cherry-pick into gpraw/gpr
# as they are, and has rebase-merged its pull requests to keep them apart;
# a squash folds them into one. The answer is the viewer's: a squash merge
# by hand there, or an operator who never merged there, can turn it into a
# squash. Turning squash merging off in adeelabbas/gpr's settings makes the
# rebase independent of both, which is the operator's to decide.
#
# Write the number bare. An unquoted #195 starts a comment in the shell,
# which takes everything after it along: "merge_pr.sh #195 --dry-run" arrives
# here as no arguments at all, and that is a real merge of this branch's PR.
# The same goes for an unquoted & in a URL. No script can see what its shell
# threw away, so the '#' form is only safe in quotes.
#
# /merge (.claude/skills/merge/SKILL.md) runs it. The order is the safety:
#
#   0. The arguments are read whole before anything else runs, and one the
#      script does not know stops it: another option, a second <pr>, an empty
#      string. --dry-run used to count only as the first argument, so
#      "merge_pr.sh 195 --dry-run" dropped it without a word and merged the
#      pull request for real (2026-09-20, in the GPRaw app's repository,
#      where this script comes from). No argument that reaches the script is
#      ignored now.
#   1. Everything that can refuse, refuses before anything changes. The PR
#      must be this repository's own: a URL can name one anywhere, gh
#      follows it there, and every later step would bring that PR's number
#      and branch name back to this repository's PRs and branches. It
#      must be open (or already merged, which skips to the cleanup), not a
#      draft, into the default branch from a branch of this repository, and
#      mergeable without conflicts or failing checks. The working tree must
#      have no uncommitted changes to tracked files, the local default
#      branch must be able to fast-forward to origin's, and a local copy of
#      the branch must sit exactly at the PR's head: a commit that exists
#      only locally would be lost with the branch, and one only on origin
#      was never seen here. The open PRs stacked on the branch - the ones
#      that name it as their base - are listed here too, and one that
#      plainly cannot move onto the default branch, a PR from the default
#      branch itself, stops the script. So does a repository that allows
#      neither a squash nor a rebase merge.
#   2. The merge is pinned to the head commit checked in step 1
#      (--match-head-commit), so a push that lands in between - CI's
#      test-gap pass, where the repository has one (gpraw/gpr), commits to
#      PR branches - makes GitHub refuse the merge instead of merging a
#      commit nobody looked at. A squash takes GitHub's default message:
#      the title with (#NN), and every commit's message below it, which is
#      what this repo's pull request bodies are written from. A rebase
#      merge keeps each commit's own.
#   3. Nothing is deleted until GitHub reports the PR merged.
#   4. Then the stacked PRs are retargeted to the default branch and
#      origin's branch is deleted - only once GitHub lists no open PR based
#      on it any more.
#      Deleting a branch with a push CLOSES every open PR based on it
#      (GitHub retargets them only when it deletes the branch itself), and a
#      closed PR whose base branch is gone can be neither reopened nor
#      retargeted. Coming back from that takes recreating the base branch
#      at its old commit and putting the head back where it was at closing.
#      So when a PR is still based on the
#      branch, the branch stays on origin and the script says why.
#   5. Then the switch to the default branch, a fast-forward pull, and last
#      the local branch - with -D, since neither merge is ever an ancestor
#      of the branch (GitHub writes new commits for a rebase merge too),
#      and only after checking again that it still sits at the merged head.
#      A branch checked out in another worktree is left alone and said so.
#      When that is the default branch - a session under .claude/worktrees/
#      while the main checkout sits on it - git will not switch to it here,
#      so this checkout moves to origin's default branch, detached, and the
#      default branch is left to be pulled where it is checked out.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

fail() { echo "error: $*" >&2; exit 1; }
note() { echo "$*"; }

USAGE="usage: scripts/merge_pr.sh [--dry-run] [<pr>]"
usage_fail() { echo "error: $*; nothing was changed" >&2; echo "$USAGE" >&2; exit 1; }

# ---------------------------------------------------------------------------
# 0. The arguments, all of them, before anything else.
# ---------------------------------------------------------------------------

DRY_RUN=0
TARGET=""
for arg in "$@"; do
    case "$arg" in
        --dry-run)
            DRY_RUN=1
            ;;
        -*)
            # No branch name starts with a dash (git refuses one), so this
            # is an option, and guessing at a misspelt --dry-run is how a
            # rehearsal becomes a merge.
            usage_fail "unrecognized option '$arg'"
            ;;
        *)
            # A named PR is never empty (below), so an empty TARGET means
            # none was named yet.
            [ -z "$TARGET" ] \
                || usage_fail "more than one PR named ('$TARGET' and '$arg')"
            TARGET="${arg#\#}"
            # "" is what an unset variable leaves behind, and "#" strips to
            # it. Taken as "no PR named" either would merge this branch's PR
            # instead of the one meant.
            [ -n "$TARGET" ] || usage_fail "an empty PR argument ('$arg')"
            ;;
    esac
done

# Run a command that changes something, or in a dry run say it would. The
# line goes to fd 3, the script's own stdout, so that a call whose stdout is
# dropped still says what it would run: the retarget in step 4 drops gh's
# stdout (the PR's URL), which would take this line with it.
exec 3>&1
act() {
    if [ "$DRY_RUN" = 1 ]; then
        echo "  would run: $*" >&3
        return 0
    fi
    "$@"
}

command -v gh >/dev/null || fail "gh is not installed"
command -v jq >/dev/null || fail "jq is not installed (brew install jq)"
gh auth status >/dev/null 2>&1 || fail "gh is not signed in (gh auth login)"

# ---------------------------------------------------------------------------
# 1. Checks, before anything changes.
# ---------------------------------------------------------------------------

git fetch --quiet --prune origin || fail "could not fetch origin"

# The repository this checkout is, as gh resolves it, which is where every
# bare number or branch name below lands. Its url as well as its name: the
# PR's url is compared under it, host for host, so no host is spelt here.
# And its default branch, which every check and step below names. GitHub's
# answer, not origin/HEAD: that is set when the clone is made and no fetch
# moves it, and which base a PR merges into is GitHub's to say. And how it
# merges, for step 2.
REPO_JSON="$(gh repo view --json nameWithOwner,url,defaultBranchRef,squashMergeAllowed,rebaseMergeAllowed,viewerDefaultMergeMethod 2>/dev/null)" \
    || fail "could not tell which GitHub repository this checkout is"
REPO="$(jq -r .nameWithOwner <<<"$REPO_JSON")"
REPO_URL="$(jq -r .url <<<"$REPO_JSON")"
# Without the url every PR would be refused as another repository's, with
# a message naming this one correctly and nothing about why.
[ -n "$REPO_URL" ] && [ "$REPO_URL" != null ] \
    || fail "gh did not report this repository's url"
DEFAULT="$(jq -r .defaultBranchRef.name <<<"$REPO_JSON")"
# Without it the base check would refuse every PR as targeting something
# other than "null", which says nothing about why.
[ -n "$DEFAULT" ] && [ "$DEFAULT" != null ] \
    || fail "gh did not report this repository's default branch"
# The merge button's method when it is one of the two this script does and
# the settings allow it; else a squash where they allow one, else a rebase
# merge (the header says why). Empty when they allow neither, which only an
# open PR minds.
SQUASH_OK="$(jq -r .squashMergeAllowed <<<"$REPO_JSON")"
REBASE_OK="$(jq -r .rebaseMergeAllowed <<<"$REPO_JSON")"
METHOD=""
case "$(jq -r .viewerDefaultMergeMethod <<<"$REPO_JSON")" in
    SQUASH) [ "$SQUASH_OK" = true ] && METHOD=squash ;;
    REBASE) [ "$REBASE_OK" = true ] && METHOD=rebase ;;
esac
if [ -z "$METHOD" ]; then
    if [ "$SQUASH_OK" = true ]; then
        METHOD=squash
    elif [ "$REBASE_OK" = true ]; then
        METHOD=rebase
    fi
fi

# Only now, with the default branch known: on it, "this branch's PR" is
# nothing to merge.
if [ -z "$TARGET" ]; then
    TARGET="$(git rev-parse --abbrev-ref HEAD)"
    [ "$TARGET" != "$DEFAULT" ] \
        || fail "on $DEFAULT - name the PR or branch to merge"
fi

FIELDS=number,title,url,state,isDraft,baseRefName,headRefName,headRefOid,isCrossRepository,mergeStateStatus
PR_JSON=""
# Whether the PR gh found is this repository's: <pr> may be a URL, and gh
# follows one into whatever repository it names. Decided here, once, from
# the PR's url under the repository's.
OWN=0
# mergeStateStatus is UNKNOWN while GitHub is still working it out (just
# after a push); ask an open PR a few times before treating that as an
# answer. A merged or closed PR answers UNKNOWN for good, and another
# repository's PR is not waited on: it is refused below whatever its state.
for attempt in 1 2 3 4 5; do
    PR_JSON="$(gh pr view "$TARGET" --json "$FIELDS" 2>/dev/null)" \
        || fail "no pull request found for '$TARGET'"
    case "$(jq -r .url <<<"$PR_JSON")" in
        "$REPO_URL/pull/"*) OWN=1 ;;
        *) break ;;
    esac
    [ "$(jq -r .state <<<"$PR_JSON")" = "OPEN" ] || break
    [ "$(jq -r .mergeStateStatus <<<"$PR_JSON")" = "UNKNOWN" ] || break
    sleep 3
done

field() { jq -r ".$1" <<<"$PR_JSON"; }
NUMBER="$(field number)"
TITLE="$(field title)"
URL="$(field url)"
STATE="$(field state)"
BRANCH="$(field headRefName)"
HEAD_SHA="$(field headRefOid)"
# The branch the PR merges into, and so the one its stacked PRs move to in
# step 4: named here once, so the check below and that retarget cannot
# disagree about it.
BASE="$(field baseRefName)"

note "PR #$NUMBER: $TITLE"
note "  $URL"
note "  $BRANCH at ${HEAD_SHA:0:7} -> $BASE, $STATE, merge state $(field mergeStateStatus)"

# Every call below hands gh and git the bare number or branch, which they
# take to THIS repository: a PR merged over there would skip to the cleanup
# and delete origin's branch of the same name here. isCrossRepository does
# not see it, because over there the PR comes from the repository's own
# branch. So this is the first refusal, ahead of the ones that read the rest
# of what gh found.
if [ "$OWN" = 0 ]; then
    # <scheme>://<host>/<owner>/<name>/pull/<n>, whichever the host.
    PR_REPO="${URL#*://*/}"
    fail "#$NUMBER is a pull request of ${PR_REPO%/pull/*}, and this checkout is $REPO; merge it from a checkout of its own repository"
fi

[ "$BASE" = "$DEFAULT" ] || fail "#$NUMBER targets $BASE, not $DEFAULT"
[ "$(field isCrossRepository)" = "false" ] \
    || fail "#$NUMBER comes from a fork; its branch is not ours to delete"
[ "$BRANCH" != "$DEFAULT" ] || fail "#$NUMBER's head is $DEFAULT"

case "$STATE" in
    OPEN)
        [ "$(field isDraft)" = "false" ] || fail "#$NUMBER is a draft"
        [ -n "$METHOD" ] \
            || fail "$REPO allows neither squash nor rebase merges, the two this script does"
        case "$(field mergeStateStatus)" in
            CLEAN|HAS_HOOKS) ;;
            BEHIND)   fail "#$NUMBER is behind $DEFAULT; update the branch first" ;;
            BLOCKED)  fail "#$NUMBER is blocked: a required check or review has not passed" ;;
            DIRTY)    fail "#$NUMBER has merge conflicts with $DEFAULT" ;;
            UNSTABLE) fail "#$NUMBER has failing checks" ;;
            *)        fail "#$NUMBER is not mergeable yet (merge state $(field mergeStateStatus))" ;;
        esac
        ;;
    MERGED)
        note "  already merged - cleaning up only"
        ;;
    *)
        fail "#$NUMBER is $STATE"
        ;;
esac

# The open PRs stacked on $BRANCH - the ones that name it as their base - one
# a line as number, head, from-a-fork and title, tab-separated. --base alone
# keeps gh on the repository's own list, which is current; a --search would
# move it to the search index, which lags.
stacked_prs() {
    gh pr list --base "$BRANCH" --state open --limit 100 \
        --json number,headRefName,isCrossRepository,title \
        --jq '.[] | [.number, .headRefName, .isCrossRepository, .title] | @tsv'
}

# Step 4 retargets them to $BASE. What can be refused from here is the one
# it plainly cannot take, a PR from that branch itself, which would come out
# as $BASE into $BASE. Any other retarget GitHub turns down keeps the branch
# in step 4.
STACKED="$(stacked_prs)" || fail "could not list the open pull requests based on $BRANCH"
if [ -n "$STACKED" ]; then
    note "  based on $BRANCH, and retargeted to $BASE before it is deleted:"
    while IFS=$'\t' read -r n head fork title; do
        note "    #$n $head: $title"
        [ "$head" != "$BASE" ] || [ "$fork" = "true" ] \
            || fail "#$n is $BASE into $BRANCH and cannot be retargeted to $BASE; close it or give it another base first"
    done <<<"$STACKED"
fi

[ -z "$(git status --porcelain --untracked-files=no)" ] \
    || fail "uncommitted changes to tracked files; commit or set them aside first"

git merge-base --is-ancestor "$DEFAULT" "origin/$DEFAULT" 2>/dev/null \
    || fail "local $DEFAULT has commits origin/$DEFAULT does not; reconcile it first"

# The worktree other than this one that has branch $1 checked out, if any.
# git checks a branch out in one worktree at a time, and from any other
# will neither switch to it nor delete it.
here="$(git rev-parse --show-toplevel)"
checked_out_elsewhere() {
    git worktree list --porcelain | awk -v b="refs/heads/$1" -v here="$here" '
        /^worktree / { path = substr($0, 10) }
        $0 == "branch " b && path != here { print path }'
}

# Found now, so the dry run already says what step 5 will do about it.
DEFAULT_ELSEWHERE="$(checked_out_elsewhere "$DEFAULT")"

LOCAL_BRANCH=0
WORKTREE_ELSEWHERE=""
if git show-ref --verify --quiet "refs/heads/$BRANCH"; then
    LOCAL_BRANCH=1
    LOCAL_SHA="$(git rev-parse "refs/heads/$BRANCH")"
    [ "$LOCAL_SHA" = "$HEAD_SHA" ] || fail "local $BRANCH is at ${LOCAL_SHA:0:7}, the PR's head is ${HEAD_SHA:0:7}; push or pull it first so nothing is lost"
    WORKTREE_ELSEWHERE="$(checked_out_elsewhere "$BRANCH")"
fi

# ---------------------------------------------------------------------------
# 2-3. The merge, pinned to the head checked above, confirmed by GitHub.
# ---------------------------------------------------------------------------

if [ "$STATE" = "OPEN" ]; then
    if [ "$METHOD" = squash ]; then
        note "Squash-merging #$NUMBER at ${HEAD_SHA:0:7}"
    else
        note "Rebase-merging #$NUMBER at ${HEAD_SHA:0:7}"
    fi
    act gh pr merge "$NUMBER" "--$METHOD" --match-head-commit "$HEAD_SHA" \
        || fail "GitHub refused the merge; nothing was deleted"
    if [ "$DRY_RUN" = 0 ]; then
        merged=""
        for attempt in 1 2 3 4 5; do
            merged="$(gh pr view "$NUMBER" --json state,mergeCommit \
                --jq 'select(.state == "MERGED") | .mergeCommit.oid')"
            [ -n "$merged" ] && break
            sleep 2
        done
        [ -n "$merged" ] || fail "#$NUMBER does not report merged; nothing was deleted"
        note "  merged as ${merged:0:7}"
    fi
fi

# ---------------------------------------------------------------------------
# 4. The stacked PRs onto $BASE, then origin's branch.
# ---------------------------------------------------------------------------

# Why origin's branch was kept, when it was; step 5's last line says so too.
KEEP=""
if git ls-remote --exit-code --heads origin "$BRANCH" >/dev/null 2>&1; then
    # Listed again, not taken from step 1: the merge sat in between, and what
    # closes a PR is being based on the branch at the moment it goes.
    if ! STACKED="$(stacked_prs)"; then
        KEEP="the open pull requests based on it could not be listed"
    elif [ -n "$STACKED" ]; then
        # gh gets no stdin, so it cannot eat the rest of the list, and its
        # stdout (the PR's URL) is dropped so the report stays these lines.
        while IFS=$'\t' read -r n head fork title; do
            note "Retargeting #$n ($head) to $BASE"
            act gh pr edit "$n" --base "$BASE" </dev/null >/dev/null \
                || note "  warning: could not retarget #$n"
        done <<<"$STACKED"
        # The delete waits for GitHub's list to come back empty, not for gh's
        # exit codes: that also catches a PR opened on the branch meanwhile.
        # Asked a few times, as the merged state is above, so a list a moment
        # behind the edits does not keep a branch that is free to go.
        if [ "$DRY_RUN" = 0 ]; then
            for attempt in 1 2 3; do
                if ! STACKED="$(stacked_prs)"; then
                    KEEP="the open pull requests based on it could not be listed"
                    break
                fi
                [ -n "$STACKED" ] || break
                [ "$attempt" = 3 ] || sleep 2
            done
            if [ -z "$KEEP" ] && [ -n "$STACKED" ]; then
                KEEP="it is still the base of $(awk -F'\t' '{ printf "%s#%s", (NR > 1 ? ", " : ""), $1 }' <<<"$STACKED")"
            fi
        fi
    fi
    if [ -z "$KEEP" ]; then
        note "Deleting origin/$BRANCH"
        act git push --quiet origin --delete "$BRANCH" \
            || note "  warning: could not delete origin/$BRANCH"
    else
        note "Keeping origin/$BRANCH: $KEEP, and deleting it closes every open PR based on it, for good"
        note "  once none is (gh pr edit <n> --base $BASE), scripts/merge_pr.sh $NUMBER deletes it"
    fi
else
    note "origin/$BRANCH is already gone"
fi

# ---------------------------------------------------------------------------
# 5. The default branch, and the local branch.
# ---------------------------------------------------------------------------

# What this checkout ends at, for the last line.
AT="$DEFAULT"
if [ -n "$DEFAULT_ELSEWHERE" ]; then
    # Another worktree holds it, and a pull from here would move the files
    # of a tree someone else works in. Origin's commit, detached, puts this
    # checkout at the same place and still frees the local branch.
    note "Detaching at origin/$DEFAULT: $DEFAULT is checked out in $DEFAULT_ELSEWHERE; pull it there"
    act git fetch --quiet origin "$DEFAULT" || fail "could not fetch $DEFAULT"
    act git switch --quiet --detach "origin/$DEFAULT" \
        || fail "could not switch to origin/$DEFAULT"
    AT="origin/$DEFAULT"
else
    if [ "$(git rev-parse --abbrev-ref HEAD)" != "$DEFAULT" ]; then
        note "Switching to $DEFAULT"
        act git switch --quiet "$DEFAULT" || fail "could not switch to $DEFAULT"
    fi
    note "Pulling $DEFAULT"
    act git pull --quiet --ff-only origin "$DEFAULT" || fail "could not fast-forward $DEFAULT"
fi

if [ "$LOCAL_BRANCH" = 1 ]; then
    if [ -n "$WORKTREE_ELSEWHERE" ]; then
        note "Keeping local $BRANCH: it is checked out in $WORKTREE_ELSEWHERE"
    elif [ "$(git rev-parse "refs/heads/$BRANCH")" != "$HEAD_SHA" ]; then
        note "Keeping local $BRANCH: it moved off the merged head while this ran"
    else
        note "Deleting local $BRANCH"
        act git branch --quiet -D "$BRANCH" || note "  warning: could not delete local $BRANCH"
    fi
else
    note "No local $BRANCH to delete"
fi

if [ "$DRY_RUN" = 1 ]; then
    note "Dry run: nothing was changed."
elif [ -n "$KEEP" ]; then
    # Not "Done": a branch a PR still hangs off is the one piece of cleanup
    # that is the user's, and the last line is what gets read.
    note "Done except origin/$BRANCH: $AT at $(git log -1 --format='%h %s')"
else
    note "Done: $AT at $(git log -1 --format='%h %s')"
fi
