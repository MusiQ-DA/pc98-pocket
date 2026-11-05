#!/usr/bin/env bash
# ci_watch.sh — watch one GitHub Actions run to completion, then report
# and act on the outcome.  Replaces the ad-hoc inline watcher loops that
# were duplicated four-at-a-time and produced no diagnostics on failure.
#
# Usage:  scripts/ci_watch.sh <run-id>
#
# Behaviour:
#   * Polls every 30 s, up to 3 h (CI history: 23-30 min).  Transient gh
#     errors are reported and retried; they do not consume the budget.
#   * Refuses to start if another watcher for the same run is alive
#     (single instance per run — no more quadruple watchers).
#   * On completion:
#       - prints the conclusion and every non-success job;
#       - failure: saves each failed job's log to
#         ~/.local/share/opencode/logs/ci_<run>_<job>.log and prints its
#         Internal/Error/Fatal lines (the Fitter/quartus message you
#         actually need, without manual `gh api` digging);
#       - success: downloads the bitstream artifact into
#         build/artifact_bbf2/ and prints the .sof path + size.
#
# Exit status: 0 on success-run (bitstream downloaded), 1 on failed run,
# 2 on usage/instance errors, 3 on timeout.

set -u

RUN_ID="${1:?usage: scripts/ci_watch.sh <run-id>}"
POLL=30
MAX_POLLS=360            # 3 h at 30 s
LOGDIR="$HOME/.local/share/opencode/logs"
ARTDIR="build/artifact_bbf2"
mkdir -p "$LOGDIR"

# --- single instance per run (lockdir: deterministic, no pgrep quirks) ----
LOCK="$LOGDIR/ci_watch_${RUN_ID}.lock"
self=$$
if mkdir "$LOCK" 2>/dev/null; then
  echo "$self" > "$LOCK/pid"
else
  oldpid=$(cat "$LOCK/pid" 2>/dev/null || true)
  if [ -n "$oldpid" ] && kill -0 "$oldpid" 2>/dev/null; then
    echo "ci_watch: refusing to start — watcher pid $oldpid is already on run $RUN_ID"
    exit 2
  fi
  echo "ci_watch: stale lock (pid ${oldpid:-?} gone) — taking over"
  echo "$self" > "$LOCK/pid"
fi
trap 'rmdir "$LOCK" 2>/dev/null' EXIT
trap 'rmdir "$LOCK" 2>/dev/null; exit 1' TERM INT

REPO=$(gh repo view --json nameWithOwner --jq .nameWithOwner 2>/dev/null) \
  || REPO="MusiQ-DA/pc98-pocket"

echo "ci_watch: watching $REPO run $RUN_ID (poll ${POLL}s, max $((MAX_POLLS*POLL/60))min, pid $self)"

# --- poll -----------------------------------------------------------------
i=0
consec_fail=0
while :; do
  s=$(gh run view "$RUN_ID" --json status,conclusion \
      --jq '.status+" "+(.conclusion//"-")' 2>/dev/null)
  case "$s" in
    completed*)
      echo "RUN DONE: $s"
      break
      ;;
    "")
      consec_fail=$((consec_fail+1))
      echo "ci_watch: gh query failed ($consec_fail consecutive) at poll $i"
      if [ "$consec_fail" -ge 10 ]; then
        echo "ci_watch: 10 consecutive gh failures — bad run id / auth / outage?  Aborting."
        exit 2
      fi
      ;;  # transient: do not count against the poll budget
    *)
      i=$((i+1))
      consec_fail=0
      ;;
  esac
  if [ "$i" -ge "$MAX_POLLS" ]; then
    echo "ci_watch: TIMEOUT after $i polls — run $RUN_ID still not completed"
    exit 3
  fi
  sleep "$POLL"
done

CONCL=$(gh run view "$RUN_ID" --json conclusion --jq .conclusion)

# --- non-success jobs ------------------------------------------------------
gh run view "$RUN_ID" --json jobs \
  --jq '.jobs[] | select(.conclusion != null and .conclusion != "success")
        | [(.databaseId|tostring), .name, (.conclusion // "-")] | .[]' \
  > "$LOGDIR/ci_${RUN_ID}_badjobs.txt" 2>/dev/null || true

fail=0
while read -r jid; read -r jname; read -r jconcl; do
  [ -n "${jid:-}" ] || continue
  echo "JOB $jname -> $jconcl"
  fail=1
  # Fetch the failed job's log (escape sequences and all) for the record.
  if gh api "repos/$REPO/actions/jobs/$jid/logs" --allow-escape-sequences \
      > "$LOGDIR/ci_${RUN_ID}_${jname}.log" 2>/dev/null; then
    echo "--- $jname: interesting lines (full log: $LOGDIR/ci_${RUN_ID}_${jname}.log) ---"
    # First matches name the root cause (e.g. Fitter 170012); the last ones
    # are downstream fallout (e.g. sta 23031 after a failed fit).  Show both.
    grep -aE 'Internal Error|Fatal|(%Error|Error \(|Error:)' \
      "$LOGDIR/ci_${RUN_ID}_${jname}.log" > "$LOGDIR/.errs.$$" || true
    head -6 "$LOGDIR/.errs.$$"; echo "   ..."; tail -4 "$LOGDIR/.errs.$$"; rm -f "$LOGDIR/.errs.$$"
    echo "---"
  fi
done < "$LOGDIR/ci_${RUN_ID}_badjobs.txt"

# --- act on the outcome ----------------------------------------------------
if [ "$CONCL" = "success" ]; then
  echo "ci_watch: run success — downloading bitstream artifact"
  rm -rf "$ARTDIR"
  if gh run download "$RUN_ID" -n bitstream -D "$ARTDIR" \
      && [ -f "$ARTDIR/output_files/ap_core.sof" ]; then
    ls -la "$ARTDIR/output_files/ap_core.sof"
    echo "NEXT: bash scripts/jtag_flash.sh $ARTDIR/output_files/ap_core.sof"
    exit 0
  fi
  echo "ci_watch: artifact download failed (was the run a bitstream-producing one?)"
  exit 2
fi

echo "ci_watch: run $RUN_ID conclusion=$CONCL — see job logs above / in $LOGDIR/"
exit 1
