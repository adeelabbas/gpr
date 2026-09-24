#!/bin/bash
# Merge a pull request into the default branch, then clean up after it:
# delete its branch on origin and locally, switch this checkout to the
# default branch and pull.
#
# Usage:  scripts/merge_pr.sh [--dry-run] [--squash|--rebase] [<pr>]
#
# <pr> is a number, '#number', URL or branch; the default is this branch's
# PR. --dry-run runs every check, says what it would do, and changes nothing.
# --squash and --rebase name the merge method (below). The options count
# before <pr> or after it.
#
# The repository is origin's, and gh is pinned to it (GH_REPO, step 1)
# before it is asked about any PR. A clone that also has an upstream remote
# - what gh repo clone makes of a GitHub fork, and adeelabbas/gpr is one of
# gopro/gpr - resolves a bare gh repo view to the parent: there gh pr view
# 11 answered gopro/gpr#11 (2026-09-23). The check that the PR is this
# repository's would have passed it, since gh named that repository too,
# and the branch deleted afterwards would still have been origin's.
#
# The default branch is GitHub's answer, asked once with the repository
# (step 1): master in adeelabbas/gpr, main in gpraw/gpr. This file is the
# same in both, so the code spells no branch name, and every message prints
# the one GitHub gave.
#
# How it merges is the operator's to say, with --rebase or --squash; /merge
# passes the one CLAUDE.md implies. adeelabbas/gpr keeps README, CLAUDE.md
# and workflow edits in commits of their own, so that its code commits
# cherry-pick into gpraw/gpr as they are, and a rebase merge lands each
# commit as it is, where a squash would fold them into one. gpraw/gpr
# squashes, and a squash's default message carries (#NN). With neither
# option, the method is the one of the two the repository's settings allow
# when they allow exactly one - turning the other off there pins it - and
# an open PR is refused before anything changes when they allow both, as
# both repositories' do (2026-09-23), or neither. GitHub's
# viewerDefaultMergeMethod chose it before, and cannot: it is per user, the
# method that user last clicked on the repository, so one merge by hand or
# a new operator turns it, and a merge by the wrong method cannot be undone.
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
#      string, or both --squash and --rebase. --dry-run used to count only
#      as the first argument, so "merge_pr.sh 195 --dry-run" dropped it
#      without a word and merged the pull request for real (2026-09-20, in
#      the GPRaw app's repository, where this script comes from). No
#      argument that reaches the script is ignored now, and every option
#      counts wherever it stands.
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
#      branch itself, stops the script. So does an open PR whose merge method
#      is not settled: one asked for that the settings do not allow, or none
#      asked for where they allow both a squash and a rebase merge, or
#      neither.
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
#      on it any more, and none from it.
#      Deleting a branch with a push CLOSES every open PR based on it
#      (GitHub retargets them only when it deletes the branch itself), and a
#      closed PR whose base branch is gone can be neither reopened nor
#      retargeted. Coming back from that takes recreating the base branch
#      at its old commit and putting the head back where it was at closing.
#      It closes every open PR whose head it is as well. So when a PR is
#      still based on the branch, or comes from it, the branch stays on
#      origin and the script says why.
#      A retargeted PR still carries the merged PR's own commits, and the
#      default branch has only their squash or their rebased copies, so the
#      script prints the lines each one needs before it merges: bring its
#      branch to origin's, rebase it, push it leased on the PR's head.
#      GitHub reports that PR BEHIND or DIRTY only where branch protection
#      or a conflict says so; on an unprotected default branch it can merge
#      those commits a second time. A repository set to delete head
#      branches itself has GitHub delete the branch at the merge and
#      retarget those PRs on its own, and they need the same lines.
#      The delete is leased on the head that was merged: a push that landed
#      on the branch after the merge - CI's test-gap pass, where there is
#      one, pushes to PR branches - makes it stay, with the line saying so,
#      instead of going with the rest.
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

USAGE="usage: scripts/merge_pr.sh [--dry-run] [--squash|--rebase] [<pr>]"
usage_fail() { echo "error: $*; nothing was changed" >&2; echo "$USAGE" >&2; exit 1; }

# ---------------------------------------------------------------------------
# 0. The arguments, all of them, before anything else.
# ---------------------------------------------------------------------------

DRY_RUN=0
# The merge method asked for, squash or rebase; empty when neither was.
ASKED=""
TARGET=""
for arg in "$@"; do
    case "$arg" in
        --dry-run)
            DRY_RUN=1
            ;;
        --squash|--rebase)
            # The same one twice is still one method. Two different ones
            # are a question only the operator can answer, and the one read
            # last winning would be a guess at it.
            [ -z "$ASKED" ] || [ "$ASKED" = "${arg#--}" ] \
                || usage_fail "both --squash and --rebase given; pass one"
            ASKED="${arg#--}"
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

# Origin is the repository: the one fetched from, pushed to and deleted on
# below, so the one gh has to be asked about as well.
ORIGIN_URL="$(git remote get-url origin 2>/dev/null)" && [ -n "$ORIGIN_URL" ] \
    || fail "this checkout has no origin remote, the repository to merge in"

git fetch --quiet --prune origin || fail "could not fetch origin"

# Origin's repository, named by origin's url and not by gh's own choice of
# remote, which in a fork's clone is the parent (the header says why). Its
# url as well as its name: the PR's url is compared under it, host for
# host, so no host is spelt here. And its default branch, which every check
# and step below names. GitHub's answer, not origin/HEAD: that is set when
# the clone is made and no fetch moves it, and which base a PR merges into
# is GitHub's to say. And the merge methods its settings allow, for step 2.
REPO_JSON="$(gh repo view "$ORIGIN_URL" --json nameWithOwner,url,defaultBranchRef,squashMergeAllowed,rebaseMergeAllowed 2>/dev/null)" \
    || fail "could not tell which GitHub repository origin ($ORIGIN_URL) is"
REPO="$(jq -r .nameWithOwner <<<"$REPO_JSON")"
REPO_URL="$(jq -r .url <<<"$REPO_JSON")"
# Without the url every PR would be refused as another repository's, with
# a message naming this one correctly and nothing about why.
[ -n "$REPO_URL" ] && [ "$REPO_URL" != null ] \
    || fail "gh did not report this repository's url"
# Every gh call below lands on origin's repository, in host/owner/name form
# so that any host works; the bare numbers and branch names it is handed
# would otherwise go wherever gh resolves this checkout. A <pr> given as a
# URL still takes gh wherever it points, and the first check after the PR
# is fetched refuses one that is not this repository's.
export GH_REPO="${REPO_URL#*://}"
DEFAULT="$(jq -r .defaultBranchRef.name <<<"$REPO_JSON")"
# Without it the base check would refuse every PR as targeting something
# other than "null", which says nothing about why.
[ -n "$DEFAULT" ] && [ "$DEFAULT" != null ] \
    || fail "gh did not report this repository's default branch"
# The merge method: the one asked for, when the settings allow it; else the
# one of the two this script does that the settings allow, when they allow
# exactly one (the header says why nothing else decides it). When it is not
# settled METHOD stays empty and NO_METHOD says why, which only an open PR
# minds: an already-merged one's cleanup needs no method.
SQUASH_OK="$(jq -r .squashMergeAllowed <<<"$REPO_JSON")"
REBASE_OK="$(jq -r .rebaseMergeAllowed <<<"$REPO_JSON")"
METHOD=""
NO_METHOD=""
# Said with the merge, so a dry run shows where the method came from.
METHOD_WHY=""
if [ -n "$ASKED" ]; then
    if { [ "$ASKED" = squash ] && [ "$SQUASH_OK" = true ]; } \
        || { [ "$ASKED" = rebase ] && [ "$REBASE_OK" = true ]; }; then
        METHOD="$ASKED"
        METHOD_WHY="asked for with --$ASKED"
    else
        NO_METHOD="--$ASKED asks for a $ASKED merge, and $REPO's settings do not allow one"
    fi
elif [ "$SQUASH_OK" = true ] && [ "$REBASE_OK" = true ]; then
    NO_METHOD="$REPO allows both squash and rebase merges; pass --squash or --rebase (CLAUDE.md says which this repository uses), or turn one off in its settings to pin the other"
elif [ "$SQUASH_OK" = true ]; then
    METHOD=squash
    METHOD_WHY="the only one the settings allow"
elif [ "$REBASE_OK" = true ]; then
    METHOD=rebase
    METHOD_WHY="the only one the settings allow"
else
    NO_METHOD="$REPO allows neither squash nor rebase merges, the two this script does"
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
        [ -n "$METHOD" ] || fail "$NO_METHOD"
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
        # Said rather than refused: there is no merge left for it to choose,
        # and the cleanup is what the run is for.
        [ -z "$ASKED" ] || note "  --$ASKED goes unused: there is nothing left to merge"
        ;;
    *)
        fail "#$NUMBER is $STATE"
        ;;
esac

# The open PRs stacked on $BRANCH - the ones that name it as their base - one
# a line as number, head, from-a-fork, title and head commit, tab-separated.
# --base alone keeps gh on the repository's own list, which is current; a
# --search would move it to the search index, which lags.
stacked_prs() {
    gh pr list --base "$BRANCH" --state open --limit 100 \
        --json number,headRefName,isCrossRepository,title,headRefOid \
        --jq '.[] | [.number, .headRefName, .isCrossRepository, .title, .headRefOid] | @tsv'
}

# What stacked PR #$1 - branch $2, head commit $3, from a fork when $4 is
# true - needs before it merges, once it is based on $BASE: its own commits
# only, onto what $BASE is now. Printed, never run: the rebase and the push
# are the PR's owner's.
# The fetch, switch and --ff-only first make the local branch origin's, and
# the push is leased on $3, the PR's head as listed here; a bare
# --force-with-lease leases on origin/$2, which every fetch moves. Measured
# in scratch repositories (2026-09-23): the rebase alone, printed here
# before, stopped where the branch is only on origin (fatal: no such
# branch/commit), the usual case for another session's branch, and over a
# stale local copy it exited 0 without a commit only origin had - a
# test-gap pass, where there is one, pushes to PR branches - which the
# force-push then dropped. The fetch is the first line because this
# script's own came before it listed $3: without it, a push that landed in
# between was dropped too, the lease passing on $3. /next gives the other
# four after its own fetch, which comes after its read.
# A fork's branch is not in this checkout, and here origin/$BASE and a
# local $2 (the default branch, when the fork's head has its name) are the
# wrong refs to hand it, so that PR gets one line naming its owner.
rebase_hint() {
    if [ "$4" = true ]; then
        note "  then, before #$1 merges: its branch is in a fork, so the rebase is its owner's, in their clone: git rebase --onto <$REPO's $BASE> $HEAD_SHA $2, and a force-push to the fork"
        return
    fi
    # Chained with &&, so the block pasted at once stops where a line
    # fails: unchained, a --ff-only that refused (a local branch that has
    # diverged) let the rebase run on the stale copy and the leased push,
    # whose lease still matched, drop the commit only origin had.
    note "  then, before #$1 merges, in a checkout with nothing uncommitted:"
    note "    git fetch origin &&"
    note "    git switch $2 &&"
    note "    git merge --ff-only origin/$2 &&"
    note "    git rebase --onto origin/$BASE $HEAD_SHA $2 &&"
    note "    git push --force-with-lease=refs/heads/$2:$3 origin $2"
}

# Why, once after the PRs rebase_hint named; $1 is 1 when one of them was
# not from a fork, and so got the lines above.
rebase_why() {
    note "  A retargeted PR's branch still carries #$NUMBER's commits, and $BASE has only their squash or their rebased copies."
    note "  GitHub reports it BEHIND or DIRTY only where branch protection or a conflict says so; on an unprotected $BASE it can merge #$NUMBER's commits a second time."
    [ "$1" = 0 ] \
        || note "  The fetch, switch and --ff-only put the local branch at origin's (--ff-only stops where the two have diverged); the lease names the PR's head as listed here, so a push that lands on it after that is refused, not lost."
}

# Step 4 retargets them to $BASE. What can be refused from here is the one
# it plainly cannot take, a PR from that branch itself, which would come out
# as $BASE into $BASE. Any other retarget GitHub turns down keeps the branch
# in step 4.
STACKED="$(stacked_prs)" || fail "could not list the open pull requests based on $BRANCH"
if [ -n "$STACKED" ]; then
    note "  based on $BRANCH, and retargeted to $BASE before it is deleted:"
    while IFS=$'\t' read -r n head fork title oid; do
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
        note "Squash-merging #$NUMBER at ${HEAD_SHA:0:7} ($METHOD_WHY)"
    else
        note "Rebase-merging #$NUMBER at ${HEAD_SHA:0:7} ($METHOD_WHY)"
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

# Why origin's branch was kept, when it was, and what clears that; step 5's
# last line says so too.
KEEP=""
KEEP_NEXT=""
# Where origin's branch is now, named in full: ls-remote takes a bare name as
# a pattern that matches the tail of a ref, so "a" would find a branch
# x/a as well. A list that fails (pipefail carries git's status) says
# nothing about the branch: read as empty, it would print "already gone"
# and end "Done" with the branch still on origin.
LISTED=1
ORIGIN_SHA="$(git ls-remote --heads origin "refs/heads/$BRANCH" 2>/dev/null \
    | awk -v r="refs/heads/$BRANCH" '$2 == r { print $1 }')" || LISTED=0
if [ "$LISTED" = 0 ]; then
    KEEP="origin's branches could not be listed, so this run neither retargeted any PR based on it nor deleted it"
    KEEP_NEXT="once origin answers, scripts/merge_pr.sh $NUMBER does the rest of the cleanup"
    note "Keeping origin/$BRANCH: $KEEP"
    note "  $KEEP_NEXT"
elif [ -n "$ORIGIN_SHA" ]; then
    CLOSES="and deleting it closes every open PR based on it, for good"
    # Listed again, not taken from step 1: the merge sat in between, and what
    # closes a PR is being based on the branch at the moment it goes.
    if ! STACKED="$(stacked_prs)"; then
        KEEP="the open pull requests based on it could not be listed, $CLOSES"
    elif [ -n "$STACKED" ]; then
        # gh gets no stdin, so it cannot eat the rest of the list, and its
        # stdout (the PR's URL) is dropped so the report stays these lines.
        RETARGETED=0
        PLAIN=0
        while IFS=$'\t' read -r n head fork title oid; do
            note "Retargeting #$n ($head) to $BASE"
            if act gh pr edit "$n" --base "$BASE" </dev/null >/dev/null; then
                rebase_hint "$n" "$head" "$oid" "$fork"
                RETARGETED=1
                [ "$fork" = true ] || PLAIN=1
            else
                note "  warning: could not retarget #$n"
            fi
        done <<<"$STACKED"
        [ "$RETARGETED" = 0 ] || rebase_why "$PLAIN"
        # The delete waits for GitHub's list to come back empty, not for gh's
        # exit codes: that also catches a PR opened on the branch meanwhile.
        # Asked a few times, as the merged state is above, so a list a moment
        # behind the edits does not keep a branch that is free to go.
        if [ "$DRY_RUN" = 0 ]; then
            for attempt in 1 2 3; do
                if ! STACKED="$(stacked_prs)"; then
                    KEEP="the open pull requests based on it could not be listed, $CLOSES"
                    break
                fi
                [ -n "$STACKED" ] || break
                [ "$attempt" = 3 ] || sleep 2
            done
            if [ -z "$KEEP" ] && [ -n "$STACKED" ]; then
                KEEP="it is still the base of $(awk -F'\t' '{ printf "%s#%s", (NR > 1 ? ", " : ""), $1 }' <<<"$STACKED"), $CLOSES"
            fi
        fi
    fi
    # With the repository named: in a fork's clone a bare gh pr edit <n>
    # would edit the parent's PR <n>, as the header says.
    [ -z "$KEEP" ] \
        || KEEP_NEXT="once none is (gh pr edit <n> --base $BASE -R $GH_REPO), scripts/merge_pr.sh $NUMBER deletes it"
    # The open PRs whose head is the branch, this one aside (a dry run finds
    # it still open): deleting a branch closes those too. A fork's PR from a
    # branch of the same name comes from the fork's branch, not this one.
    if [ -z "$KEEP" ]; then
        if ! FROM="$(gh pr list --head "$BRANCH" --state open --limit 100 \
                --json number,isCrossRepository \
                --jq ".[] | select(.isCrossRepository | not) | select(.number != $NUMBER) | .number")"; then
            KEEP="the open pull requests from it could not be listed, and deleting it closes every open PR from it"
        elif [ -n "$FROM" ]; then
            KEEP="it is the head of open $(awk '{ printf "%s#%s", (NR > 1 ? ", " : ""), $1 }' <<<"$FROM"), and deleting it closes every open PR from it"
        fi
        [ -z "$KEEP" ] \
            || KEEP_NEXT="once none is (merge or close it), scripts/merge_pr.sh $NUMBER deletes it"
    fi
    # A push that landed on the branch after the head that was merged: what
    # it added is on origin's branch alone, and deleting the branch loses it.
    if [ -z "$KEEP" ] && [ "$ORIGIN_SHA" != "$HEAD_SHA" ]; then
        KEEP="it is at ${ORIGIN_SHA:0:7}, not at ${HEAD_SHA:0:7}, the head that was merged: a push landed on it since, and deleting it would lose that"
        KEEP_NEXT="after a git fetch, git log ${HEAD_SHA:0:7}..origin/$BRANCH shows what; whether it goes is the user's call"
    fi
    if [ -z "$KEEP" ]; then
        note "Deleting origin/$BRANCH"
        # Leased on that head, so a push that lands between the check above
        # and this delete makes git refuse it (stale info) instead. Either
        # way the branch is still there, and the last line says so. git's
        # own lines are printed under the warning, indented: they include
        # "error: failed to push some refs", and the run goes on, where a
        # line starting "error:" is otherwise this script's last. In a dry
        # run act's line goes to fd 3, past the capture.
        if ! pushed="$(act git push --quiet --force-with-lease="refs/heads/$BRANCH:$HEAD_SHA" origin --delete "$BRANCH" 2>&1)"; then
            note "  warning: could not delete origin/$BRANCH; if it moved off ${HEAD_SHA:0:7}, the lease kept it"
            [ -z "$pushed" ] || printf '%s\n' "$pushed" | sed 's/^/    /'
            KEEP="the delete failed"
        fi
    else
        note "Keeping origin/$BRANCH: $KEEP"
        note "  $KEEP_NEXT"
    fi
else
    note "origin/$BRANCH is already gone"
    # Gone after this run's merge: the repository is set to delete head
    # branches itself ("Automatically delete head branches"), and GitHub,
    # deleting the branch at the merge, retargets the open PRs based on it
    # to $BASE on its own. Those are the ones step 1 listed - none is based
    # on the branch any more to be listed now - and they still carry
    # #$NUMBER's commits as a retarget here leaves them, so they get the
    # same lines. Both repositories had the setting off on 2026-09-23; it
    # is a setting, and turns on without this file changing.
    if [ "$STATE" = OPEN ] && [ "$DRY_RUN" = 0 ] && [ -n "$STACKED" ]; then
        # Asked, not assumed: a branch deleted by a push rather than by
        # GitHub closes the PRs based on it instead, and a closed PR whose
        # base is gone needs recovering by hand, not a rebase.
        PLAIN=0 RETARGETED=0
        while IFS=$'\t' read -r n head fork title oid; do
            case "$(gh pr view "$n" --json state,baseRefName --jq '.state + " " + .baseRefName' 2>/dev/null)" in
                "OPEN $BASE")
                    note "GitHub retargeted #$n ($head) to $BASE when it deleted $BRANCH"
                    rebase_hint "$n" "$head" "$oid" "$fork"
                    RETARGETED=1
                    [ "$fork" = true ] || PLAIN=1 ;;
                CLOSED*)
                    note "  warning: #$n ($head) is closed: $BRANCH was deleted by a push, which closes the PRs based on it rather than retargeting them."
                    note "    To bring it back: git push origin $HEAD_SHA:refs/heads/$BRANCH, then gh pr reopen $n -R $GH_REPO and gh pr edit $n -R $GH_REPO --base $BASE, then delete $BRANCH again (a bare gh in a fork's clone acts on the parent's #$n)." ;;
                *)
                    note "  warning: could not tell what became of #$n ($head), which was based on $BRANCH; check it by hand." ;;
            esac
        done <<<"$STACKED"
        [ "$RETARGETED" = 0 ] || rebase_why "$PLAIN"
    fi
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
    # Not "Done": a branch kept on origin - a PR still hangs off it, or it
    # holds a push the merge did not take - is the one piece of cleanup that
    # is the user's, and the last line is what gets read.
    note "Done except origin/$BRANCH: $AT at $(git log -1 --format='%h %s')"
else
    note "Done: $AT at $(git log -1 --format='%h %s')"
fi
