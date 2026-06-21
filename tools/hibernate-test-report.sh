#!/usr/bin/env bash
# Parses hibernate-trigger test cycles out of the journal and independently
# verifies each one against the kernel log, instead of trusting the hook's
# own self-reported decision. Run on enterprise-d after one or more
# suspend/idle test cycles.
#
# Usage: tools/hibernate-test-report.sh [--since "<journalctl --since arg>"]

set -euo pipefail

since="${2:-1 hour ago}"
if [[ "${1:-}" == "--since" ]]; then
  since="${2:-1 hour ago}"
fi

trigger_log="$(journalctl -t hibernate-trigger --no-pager --since "$since" -o cat)"

if [[ -z "$trigger_log" ]]; then
  echo "No hibernate-trigger log entries since '$since'." >&2
  exit 1
fi

cycle=0
streak=0
best_streak=0
pending_start=""

printf '%-4s %-12s %-8s %-22s %-12s %s\n' "#" "start" "elapsed" "hook decision" "kernel" "verdict"

emit_incomplete() {
  cycle=$((cycle + 1))
  printf '%-4s %-12s %-8s %-22s %-12s %s\n' "$cycle" "$1" "-" "(no resume logged)" "-" "INCOMPLETE"
  streak=0
}

emit_cycle() {
  local start="$1" resumed="$2" elapsed="$3" decision="$4"
  cycle=$((cycle + 1))

  # The hook's "resumed" timestamp marks the S3 wake that triggers the
  # async `systemctl hibernate` call, not the actual S4 transition, which
  # completes later (observed ~90s after resume). Give the hibernate path
  # a generous window past "resumed" to actually see it land in dmesg.
  local window_end=$((resumed + 2))
  [[ "$decision" == "triggering hibernate" ]] && window_end=$((resumed + 180))

  local kernel_window hibernated_in_kernel verdict
  kernel_window="$(journalctl -k --no-pager --since "@$((start - 2))" --until "@$window_end" 2>/dev/null || true)"
  hibernated_in_kernel=no
  if grep -q "PM: hibernation: hibernation exit" <<<"$kernel_window"; then
    hibernated_in_kernel=yes
  fi

  verdict="AMBIGUOUS"
  case "$decision" in
    "triggering hibernate")
      if [[ "$hibernated_in_kernel" == yes ]]; then
        verdict="PASS"
        streak=$((streak + 1))
      else
        verdict="FAIL (hook decided to hibernate, kernel log shows no S4)"
        streak=0
      fi
      ;;
    "early wake, no hibernate")
      if [[ "$hibernated_in_kernel" == no ]]; then
        verdict="PASS (early wake correctly skipped hibernate)"
      else
        verdict="FAIL (hook skipped hibernate but kernel log shows S4 anyway)"
      fi
      ;;
  esac

  if [[ $streak -gt $best_streak ]]; then
    best_streak=$streak
  fi

  printf '%-4s %-12s %-8s %-22s %-12s %s\n' "$cycle" "$start" "${elapsed}s" "$decision" "$hibernated_in_kernel" "$verdict"
}

while IFS= read -r line; do
  if [[ "$line" =~ ^suspend\ starting\ at\ ([0-9]+) ]]; then
    if [[ -n "$pending_start" ]]; then
      emit_incomplete "$pending_start"
    fi
    pending_start="${BASH_REMATCH[1]}"
  elif [[ "$line" =~ ^resumed\ at\ ([0-9]+),\ elapsed=([0-9]+)s,\ (triggering\ hibernate|early\ wake,\ no\ hibernate) ]]; then
    if [[ -z "$pending_start" ]]; then
      cycle=$((cycle + 1))
      printf '%-4s %-12s %-8s %-22s %-12s %s\n' "$cycle" "-" "-" "(resume with no start)" "-" "AMBIGUOUS"
      continue
    fi
    emit_cycle "$pending_start" "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}" "${BASH_REMATCH[3]}"
    pending_start=""
  fi
done <<<"$trigger_log"

if [[ -n "$pending_start" ]]; then
  emit_incomplete "$pending_start"
fi

if [[ $cycle -eq 0 ]]; then
  echo "No complete cycles found since '$since'." >&2
  exit 1
fi

echo
echo "Best consecutive timer-driven-hibernate streak: $best_streak (plan requires 2 at current delay, then 2 more after restoring delay_sec=600)"
