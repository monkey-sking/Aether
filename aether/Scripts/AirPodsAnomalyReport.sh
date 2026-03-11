#!/bin/zsh
set -euo pipefail

TRACE_FILE="/tmp/aether_decision_trace.txt"
RESET_AFTER_REPORT=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --reset|--clear)
      RESET_AFTER_REPORT=1
      shift
      ;;
    --trace)
      TRACE_FILE="${2:-$TRACE_FILE}"
      shift 2
      ;;
    *)
      TRACE_FILE="$1"
      shift
      ;;
  esac
done

MAX_LINES="${MAX_LINES:-2000}"

if [[ ! -f "$TRACE_FILE" ]]; then
  echo "trace file not found: $TRACE_FILE"
  echo "tip: run app once, then retry."
  exit 1
fi

TMP_INPUT="$(mktemp /tmp/aether_trace_input.XXXXXX)"
trap 'rm -f "$TMP_INPUT"' EXIT

tail -n "$MAX_LINES" "$TRACE_FILE" > "$TMP_INPUT"

echo "=== AirPods Anomaly Report ==="
echo "trace: $TRACE_FILE"
echo "lines: $(wc -l < "$TMP_INPUT" | tr -d ' ')"
echo

awk '
function print_transition(i) {
  printf("  [%03d] %s | %s -> %s | %s\n", i, ts[i], from[i], to[i], src[i])
}

{
  line = $0
  if (index(line, ": State Transition(") > 0) {
    split(line, p1, ": State Transition\\(")
    tsPart = p1[1]
    rest = p1[2]
    split(rest, p2, "\\): ")
    srcPart = p2[1]
    statePart = p2[2]
    split(statePart, p3, " -> ")
    if (length(p3[1]) > 0 && length(p3[2]) > 0) {
      n++
      ts[n] = tsPart
      src[n] = srcPart
      from[n] = p3[1]
      to[n] = p3[2]
    }
  }

  if (index(line, ": Pending ") > 0 && index(line, " via ") > 0 && index(line, " from ") > 0) {
    split(line, q1, ": Pending ")
    restP = q1[2]
    split(restP, q2, " via ")
    pState = q2[1]
    split(q2[2], q3, " from ")
    pRule = q3[1]
    if (length(pState) > 0) {
      pendingTotal++
      pendingState[pState]++
      pendingRule[pRule]++
    }
  }

  if (index(line, "Rule S0-startup-guard") > 0) startupGuardHits++
}

END {
  if (n == 0) {
    print "No state transitions found in trace window."
    exit 0
  }

  print "Recent transitions:"
  start = (n > 20 ? n - 19 : 1)
  for (i = start; i <= n; i++) print_transition(i)
  print ""

  print "Anomalies:"
  anomalies = 0

  # A1: both -> single -> both in short sequence (likely false single snap)
  for (i = 1; i <= n - 2; i++) {
    if (from[i] == "both" &&
        (to[i] == "left" || to[i] == "right") &&
        to[i+1] == "both") {
      anomalies++
      printf("  [A1] both->%s->both rebound around [%03d..%03d]\n", to[i], i, i+1)
    }
  }

  # A2: direct left <-> right switch (often noise) without both/none bridge
  for (i = 1; i <= n; i++) {
    if ((from[i] == "left" && to[i] == "right") ||
        (from[i] == "right" && to[i] == "left")) {
      anomalies++
      printf("  [A2] direct side flip %s->%s at [%03d]\n", from[i], to[i], i)
    }
  }

  # A3: high churn in recent transitions
  recent = (n > 12 ? 12 : n)
  if (recent >= 8) {
    anomalies++
    printf("  [A3] high transition churn: %d transitions in recent window\n", recent)
  }

  # A4: startup guard repeatedly hit
  if (startupGuardHits >= 2) {
    anomalies++
    printf("  [A4] startup-guard activated %d times (startup evidence conflict)\n", startupGuardHits)
  }

  # A5: long pending pressure
  if (pendingTotal >= 15) {
    anomalies++
    printf("  [A5] many pending evaluations: %d (possible slow convergence)\n", pendingTotal)
  }

  if (anomalies == 0) {
    print "  none detected by heuristic rules."
  }
  print ""

  print "Counters:"
  printf("  transitions_total=%d\n", n)
  printf("  pending_total=%d\n", pendingTotal + 0)
  printf("  startup_guard_hits=%d\n", startupGuardHits + 0)
  printf("  final_state=%s\n", to[n])
  if (pendingTotal > 0) {
    printf("  pending_by_state: both=%d left=%d right=%d none=%d\n",
      pendingState["both"] + 0, pendingState["left"] + 0, pendingState["right"] + 0, pendingState["none"] + 0)
  }
}
' "$TMP_INPUT"

if [[ $RESET_AFTER_REPORT -eq 1 ]]; then
  : > "$TRACE_FILE"
  echo
  echo "trace cleared: $TRACE_FILE"
fi
