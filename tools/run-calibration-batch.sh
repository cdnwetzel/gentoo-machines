#!/bin/bash
# run-calibration-batch.sh — run verify-panel.py against every fixture in
# the real-psrouter corpus, appending per-run rows to a stats log. Used to
# baseline the panel's behavior against meaningful volume.
#
# Usage:
#   tools/run-calibration-batch.sh [<stats-log-path>]
#
# Default stats log: tools/verify-panel-stats/runs.jsonl
set -u

CORPUS_DIR="${CORPUS_DIR:-tools/verify-panel-fixtures/real-psrouter}"
STATS_LOG="${1:-tools/verify-panel-stats/runs.jsonl}"

mkdir -p "$(dirname "$STATS_LOG")"

echo "=== verify-panel batch ==="
echo "  corpus:    $CORPUS_DIR"
echo "  stats log: $STATS_LOG"
echo "  model:     ${VERIFY_MODEL:-default (qwen2.5:7b-instruct-q4_K_M)}"
echo "  votes:     ${VERIFY_VOTES:-1}"
echo "  backend:   ${JUDGE_BACKEND:-ollama}"
echo ""

n_total=0
n_pass=0
n_fail=0
n_err=0
total_s=0

for f in "$CORPUS_DIR"/*.json; do
    [ "$(basename "$f")" = "CALIBRATION.md" ] && continue
    n_total=$((n_total + 1))
    base=$(basename "$f" .json)
    t0=$(date +%s)
    python3 tools/verify-panel.py --case "$f" --stats-log "$STATS_LOG" >/tmp/panel-out-$$.txt 2>&1
    rc=$?
    t1=$(date +%s)
    elapsed=$((t1 - t0))
    total_s=$((total_s + elapsed))
    if [ "$rc" -eq 0 ]; then
        n_pass=$((n_pass + 1))
        verdict="PASS"
    elif [ "$rc" -eq 1 ]; then
        n_fail=$((n_fail + 1))
        verdict="FAIL"
    else
        n_err=$((n_err + 1))
        verdict="ERR ($rc)"
    fi
    findings=$(grep -E "^  ✗" /tmp/panel-out-$$.txt | wc -l)
    printf "  %-50s  %-7s  %3ds  (%d failing checks)\n" "$base" "$verdict" "$elapsed" "$findings"
done
rm -f /tmp/panel-out-$$.txt

echo ""
echo "=== batch done ==="
echo "  total:    $n_total"
echo "  pass:     $n_pass"
echo "  fail:     $n_fail"
echo "  error:    $n_err"
echo "  wall:     $((total_s / 60))m $((total_s % 60))s"
echo ""
echo "Run \`tools/panel-stats.py $STATS_LOG --by-fixture\` for the per-fixture breakdown."
