#!/bin/bash
# Regression test for the record-only "the pipeline did not run" assertion.
#
# Why this exists: the assertion is a negative one, and a negative assertion
# that looks in the wrong place is indistinguishable from a passing lane. The
# original form searched `<output>/recordings` at `-maxdepth 1`, while the app
# writes both the transcript and the protocol to `<output>/protocols`. No
# `.txt` or `.md` can appear in the searched directory in either the working or
# the broken world, so the check was satisfied unconditionally and two lanes
# claimed to prove something they never touched.
#
# The case that pins that defect is `transcript_in_protocols`: it is the exact
# on-disk shape a record-only regression produces, and it must be reported.
# Reverting the search to the recordings directory turns that case red.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=../lib/e2e-helpers.sh
source "$ROOT/scripts/lib/e2e-helpers.sh"

TMP="$(mktemp -d)"
PASSED=0
# Set at the very end. MEASURED on bash 3.2, the system bash here: a `set -u`
# abort in a script that has an EXIT trap reports `$? = 0` inside the trap AND
# exits 0, so the abort is indistinguishable from success to anything reading
# the exit status, which is how ci.yml runs this file. (errexit behaves
# correctly; only `set -u` is affected.) Without this the whole file could pass
# while running none of its cases.
COMPLETED=0
finish() {
    local rc=$?
    # One case chmods a directory to 000 to force a find failure and restores it
    # afterwards. If that case fails, the restore never runs, `rm -rf` cannot
    # clear the tree, and under `set -e` the trap dies right here — before the
    # sentinel below, which is the guard this file relies on. Measured: the
    # sentinel message never appeared and the tree stayed on disk. So make both
    # steps unable to end the trap.
    chmod -R u+rwx "$TMP" 2>/dev/null || true
    rm -rf "$TMP" 2>/dev/null || true
    if [ "$COMPLETED" -ne 1 ]; then
        echo "FAIL: the test aborted before reaching its end" >&2
        exit 1
    fi
    exit "$rc"
}
trap finish EXIT

# Each case gets its own output tree with a marker dated in the past, so every
# file the case then writes at "now" is unconditionally newer. Backdating the
# marker rather than sleeping between the two keeps this file inside the
# "finish in about a second" contract that `.github/workflows/ci.yml` states for
# `scripts/tests/test_*.sh`, and it removes the dependence on filesystem mtime
# granularity that a one-second pause was only papering over.
MARKER_STAMP=202601011000   # after PREDATES_STAMP, before any file written now
PREDATES_STAMP=202601010900

new_output_dir() {
    local name="$1"
    local dir="$TMP/$name"
    mkdir -p "$dir/recordings" "$dir/protocols"
    touch -t "$MARKER_STAMP" "$dir/.marker"
    printf '%s' "$dir"
}

# Every record-only run legitimately writes these. They must never be reported.
seed_record_only_output() {
    local dir="$1"
    : > "$dir/recordings/20260914_1000_mix.wav"
    printf '{"version":2}\n' > "$dir/recordings/20260914_1000_meta.json"
}

# Three outcomes, not two. `unknown` is the one the first version of this file
# did not have, and its absence is why the helper was allowed to answer "clean"
# for a tree it had never read.
check() {
    local name="$1" expected="$2" dir="$3"
    # Two statements: `local` declares every name before it assigns any, so a
    # default referring to an earlier name in the SAME `local` reads it as
    # unset and trips `set -u`.
    local marker="${4:-$dir/.marker}"
    local found actual=clean status=0
    found="$(pipeline_output_artifacts "$dir" "$marker" 2>/dev/null)" || status=$?
    if [ "$status" -ne 0 ]; then
        actual=unknown
    elif [ -n "$found" ]; then
        actual=reported
    fi
    if [ "$actual" = "$expected" ]; then
        echo "$name ... PASS"
        PASSED=$(( PASSED + 1 ))
    else
        echo "$name ... FAIL (expected $expected, got $actual)"
        [ -z "$found" ] || printf '%s\n' "$found" | sed 's|^|    |'
        exit 1
    fi
}

# The defect this file exists for. A record-only regression runs the full
# pipeline, and the pipeline writes the transcript into `protocols/`, not into
# `recordings/`. Searching only `recordings/` never sees it.
d="$(new_output_dir transcript_in_protocols)"
seed_record_only_output "$d"
printf 'wortwoertliches transkript\n' > "$d/protocols/20260914_1000_Standup_ab12.txt"
check transcript_in_protocols reported "$d"

# The protocol is the other half of the same regression, and the same search
# missed it for the same reason.
d="$(new_output_dir protocol_in_protocols)"
seed_record_only_output "$d"
printf '# Protokoll\n' > "$d/protocols/20260914_1000_Standup_ab12.md"
check protocol_in_protocols reported "$d"

# A healthy record-only run: audio plus its sidecar, nothing else. This is the
# case the lane is asserting, so it has to stay clean or the lane is useless in
# the other direction.
d="$(new_output_dir record_only_is_clean)"
seed_record_only_output "$d"
check record_only_is_clean clean "$d"

# Output from an EARLIER meeting must not be blamed on this one. The lane runs
# against the developer's or the runner's real output folder, which routinely
# already holds transcripts from previous runs.
d="$(new_output_dir predates_marker)"
mkdir -p "$d/protocols"
printf 'altes transkript\n' > "$d/protocols/20260101_0900_Alt_zz99.txt"
touch -t "$PREDATES_STAMP" "$d/protocols/20260101_0900_Alt_zz99.txt"
seed_record_only_output "$d"
check predates_marker clean "$d"

# NOT LOOKING IS NOT FINDING NOTHING. Both of the cases below used to come back
# empty, and an empty answer is what the lane reads as proof that the pipeline
# stayed out of the way.
#
# An earlier version of this file asserted the first one as `clean`, on the
# grounds that a fresh machine has no output folder yet. That reasoning does not
# survive the lane as it now stands: it asserts that the app resolved this exact
# directory before it gets here, and by then a record-only meeting has written
# its audio into it. A missing directory at that point means something is wrong
# elsewhere, and answering "no artifacts" would report that as a pass.
check missing_output_dir unknown "$TMP/does-not-exist"

# `find` exits non-zero when a subtree cannot be read, after printing to stderr
# and nothing to stdout. On a shared runner that is reachable: the output folder
# is the console user's, and the lane has been run by hand under another
# account. The transcript below is exactly what a record-only regression leaves,
# and it sits where the helper cannot reach it.
d="$(new_output_dir unreadable_subtree)"
seed_record_only_output "$d"
printf 'wortwoertliches transkript\n' > "$d/protocols/20260914_1000_Standup_ab12.txt"
chmod 000 "$d/protocols"
check unreadable_subtree unknown "$d"
chmod 755 "$d/protocols"

# And the control that stops the case above from passing for the wrong reason:
# the same tree, readable, must report the very file it could not see before.
check unreadable_subtree_control reported "$d"

# A symlinked tree is the third way to come back empty without having looked.
# `test -d` follows a link, BSD `find` defaults to -P and does not descend one,
# so the helper answered clean while a transcript sat plainly behind the link.
# Measured in both shapes: the output folder itself symlinked, and only
# `protocols/` inside it.
d="$(new_output_dir symlinked_subdir)"
seed_record_only_output "$d"
mkdir -p "$TMP/elsewhere_sub"
printf 'wortwoertliches transkript\n' > "$TMP/elsewhere_sub/20260914_1000_Standup_ab12.txt"
rmdir "$d/protocols"
ln -s "$TMP/elsewhere_sub" "$d/protocols"
check symlinked_subdir reported "$d"

d="$(new_output_dir symlinked_root_real)"
seed_record_only_output "$d"
printf '# Protokoll\n' > "$d/protocols/20260914_1000_Standup_ab12.md"
ln -s "$d" "$TMP/symlinked_root"
check symlinked_root reported "$TMP/symlinked_root" "$d/.marker"

# --- "nothing finished" is not "nothing ran" --------------------------------

# The artifact check above and the lastJob check beside it are blind to the same
# job for two different reasons: `lastJob` reports only FINISHED jobs, and the
# transcript is written near the END of the pipeline. A regression that hands
# the queue a usable recording is still transcribing when both run, a few
# seconds after the recording stops, so the lane would pass while the very thing
# record-only forbids was underway. Neither lane runs a second meeting in CI, so
# nothing catches it later either.
violation_case() {
    local name="$1" expect="$2" snapshot="$3"
    local got
    got="$(record_only_violation "$snapshot" A)"
    local actual=quiet
    [ -z "$got" ] || actual=reported
    if [ "$actual" = "$expect" ]; then
        echo "$name ... PASS"; PASSED=$(( PASSED + 1 ))
    else
        echo "$name ... FAIL (expected $expect, got $actual: $got)"; exit 1
    fi
}
violation_case idle_pipeline_is_quiet quiet     '{"lastJob":{"jobID":"A"},"pipeline":{"activeJobCount":0,"waitingJobCount":0}}'
violation_case job_still_transcribing reported     '{"lastJob":{"jobID":"A"},"pipeline":{"activeJobCount":1,"waitingJobCount":0}}'
violation_case job_still_waiting reported     '{"lastJob":{"jobID":"A"},"pipeline":{"activeJobCount":0,"waitingJobCount":2}}'
violation_case a_job_finished reported     '{"lastJob":{"jobID":"B"},"pipeline":{"activeJobCount":0,"waitingJobCount":0}}'
# Absent counters must not read as zero-by-luck: an older app, or a renamed
# field, would otherwise make this assertion quietly stop looking.
violation_case missing_counters_are_not_idle reported     '{"lastJob":{"jobID":"A"},"pipeline":{}}'

# --- both call sites separate the three outcomes ----------------------------

# Structural, and said so: driving the record-only lanes needs a running app.
# What it pins is the half that makes the third outcome worth having. The helper
# can distinguish "could not look" from "looked and found nothing" all it likes;
# if a caller writes `unexpected="$(...)"` and reads only the string, the
# fail-open is straight back, and that is how this assertion was hollow before.
#
# Anchored on the call itself rather than filtered afterwards: a `grep -n`
# prefixes every line with its number, so a comment filter keyed on a leading
# `#` silently matches nothing.
LANE="$ROOT/scripts/e2e-app.sh"
# EVERY mention in the lane has to be a conforming call, not "at least two of
# them". Requiring a count let a third call site in through the door: measured,
# adding one written as `local unexpected="$(pipeline_output_artifacts ...)"`
# left this check green, and `local` returns 0 whatever the substitution did, so
# the attached refusal never fires. That is the exact fail-open this assertion
# exists to prevent, in the form a shell author reaches for first.
MENTIONS="$(grep -nE '^[[:space:]]*[^#]*pipeline_output_artifacts' "$LANE" || true)"
MENTION_COUNT="$(printf '%s' "$MENTIONS" | grep -c . || true)"
if [ "$MENTION_COUNT" -lt 2 ]; then
    echo "call_sites_separate_the_outcomes ... FAIL: both record-only lanes should call the helper, found $MENTION_COUNT mention(s)"
    exit 1
fi
CALLS="$MENTIONS"
# The refusal has to be attached to the CALL, not merely nearby. A window of a
# few lines is satisfied by the `|| fail` of the NEXT statement, the one that
# reports artifacts, which is present either way: measured, dropping the
# continuation from the first call site left this check green. So the call line
# must end in a continuation and the line after it must begin with `|| fail`.
while IFS= read -r line; do
    [ -n "$line" ] || continue
    n="${line%%:*}"
    call="$(sed -n "${n}p" "$LANE")"
    next="$(sed -n "$(( n + 1 ))p" "$LANE")"
    # `local x="$(...)"` is rejected outright: bash returns the status of
    # `local`, not of the substitution, so no refusal attached to it can fire.
    case "${call#"${call%%[![:space:]]*}"}" in
        local\ *)
            echo "call_sites_separate_the_outcomes ... FAIL: the call at line $n assigns through \`local\`,"
            echo "  which returns 0 whatever the helper answered, so its refusal can never fire:"
            printf '%s\n' "$call" | sed 's|^|    |'
            exit 1 ;;
    esac
    # The refusal must belong to the CALL, either on the same line or on the
    # next one after a continuation. A window of a few lines is satisfied by the
    # `|| fail` of the NEXT statement, which is present either way: measured,
    # dropping the continuation from one call site left this check green.
    case "$call" in
        *"|| fail"*) ;;
        *'\')
            case "${next#"${next%%[![:space:]]*}"}" in
                '|| fail'*) ;;
                *) echo "call_sites_separate_the_outcomes ... FAIL: the call at line $n is not followed by its own refusal:"
                   printf '%s\n' "$next" | sed 's|^|    |'
                   exit 1 ;;
            esac ;;
        *) echo "call_sites_separate_the_outcomes ... FAIL: the call at line $n neither refuses on its own line nor continues into a refusal:"
           printf '%s\n' "$call" | sed 's|^|    |'
           exit 1 ;;
    esac
done <<< "$CALLS"
echo "call_sites_separate_the_outcomes ... PASS"
PASSED=$(( PASSED + 1 ))

COMPLETED=1
echo "$PASSED checks passed"
