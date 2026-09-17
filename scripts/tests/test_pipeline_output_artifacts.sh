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
    rm -rf "$TMP"
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
CALLS="$(grep -nE '^[[:space:]]*[a-z_]+="\$\(pipeline_output_artifacts ' "$LANE" || true)"
CALL_COUNT="$(printf '%s' "$CALLS" | grep -c . || true)"
if [ "$CALL_COUNT" -lt 2 ]; then
    echo "call_sites_separate_the_outcomes ... FAIL: expected both record-only lanes to call the helper, found $CALL_COUNT"
    exit 1
fi
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
    case "$call" in
        *'\') ;;
        *) echo "call_sites_separate_the_outcomes ... FAIL: the call at line $n does not continue into a refusal:"
           printf '%s\n' "$call" | sed 's|^|    |'
           exit 1 ;;
    esac
    case "${next#"${next%%[![:space:]]*}"}" in
        '|| fail'*) ;;
        *) echo "call_sites_separate_the_outcomes ... FAIL: the call at line $n is not followed by its own refusal:"
           printf '%s\n' "$next" | sed 's|^|    |'
           exit 1 ;;
    esac
done <<< "$CALLS"
echo "call_sites_separate_the_outcomes ... PASS"
PASSED=$(( PASSED + 1 ))

COMPLETED=1
echo "$PASSED checks passed"
