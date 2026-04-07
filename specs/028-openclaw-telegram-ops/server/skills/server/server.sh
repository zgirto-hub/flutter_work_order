#!/usr/bin/env bash
set -euo pipefail

emit_reply() {
  local status="$1"
  local reply="$2"
  local outcome="$3"
  local error="${4:-}"

  local end_ts duration_ms=0
  end_ts=$(date +%s%3N)
  duration_ms=$((end_ts - START_TS))

  if [[ -n "$error" ]]; then
    jq -nc \
      --arg status "$status" \
      --arg reply "$reply" \
      --arg action "$ACTION" \
      --argjson args "$ARGS" \
      --arg outcome "$outcome" \
      --argjson duration "$duration_ms" \
      --arg error "$error" \
      '{status:$status, reply:$reply, audit:{action:$action, args:$args, outcome:$outcome, duration_ms:$duration, error:$error}}'
  else
    jq -nc \
      --arg status "$status" \
      --arg reply "$reply" \
      --arg action "$ACTION" \
      --argjson args "$ARGS" \
      --arg outcome "$outcome" \
      --argjson duration "$duration_ms" \
      '{status:$status, reply:$reply, audit:{action:$action, args:$args, outcome:$outcome, duration_ms:$duration}}'
  fi
}

action_status() {
  local nginx_status fastapi_status disk_info
  
  if nginx_status=$(systemctl is-active nginx 2>/dev/null); then
    if [[ "$nginx_status" == "active" ]]; then
      nginx_status="active ✅"
    fi
  else
    nginx_status="unknown"
  fi
  
  if fastapi_status=$(systemctl is-active fastapi 2>/dev/null); then
    if [[ "$fastapi_status" == "active" ]]; then
      fastapi_status="active ✅"
    fi
  else
    fastapi_status="unknown"
  fi
  
  if disk_info=$(df -h / 2>/dev/null | tail -1); then
    local disk_pct
    disk_pct=$(echo "$disk_info" | awk '{print $5}')
    disk_info="$disk_pct used"
  else
    disk_info="unknown"
  fi
  
  local reply="*Server status*
- nginx: $nginx_status
- fastapi: $fastapi_status
- disk (/): $disk_info"
  
  emit_reply "ok" "$reply" "success"
}

action_disk() {
  local disk_output
  
  if disk_output=$(df -h 2>/dev/null | grep -E '^/dev/(sda|vda|nvme)' | head -5); then
    if [[ -z "$disk_output" ]]; then
      disk_output=$(df -h 2>/dev/null | tail -n +2 | head -10)
    fi
    local reply="\`\`\`\n$disk_output\n\`\`\`"
    emit_reply "ok" "$reply" "success"
  else
    emit_reply "error" "Failed to get disk information" "failure"
  fi
}

action_errors() {
  local lines="${LINES:-20}"
  
  if [[ "$lines" -gt 100 ]] || [[ "$lines" -lt 1 ]]; then
    lines=20
  fi
  
  local errors_output
  
  if errors_output=$(journalctl -u fastapi -p err -n "$lines" --no-pager 2>/dev/null); then
    if [[ -z "$errors_output" ]]; then
      emit_reply "ok" "No recent errors." "success"
    else
      local reply="\`\`\`\n$errors_output\n\`\`\`"
      emit_reply "ok" "$reply" "success"
    fi
  else
    emit_reply "error" "Failed to retrieve error logs" "failure"
  fi
}

action_restart_backend() {
  local confirmed="${CONFIRMED:-false}"
  
  if [[ "$confirmed" != "true" ]]; then
    local reply="⚠️ Restart the FastAPI backend? This will briefly interrupt the app. Reply \"yes\" within 60s."
    emit_reply "needs_confirmation" "$reply" "confirmation_required"
    return
  fi
  
  if sudo -n /bin/systemctl restart fastapi 2>/dev/null; then
    sleep 2
    local new_status
    new_status=$(systemctl is-active fastapi 2>/dev/null || echo "unknown")
    local reply="✅ FastAPI restarted. New status: $new_status."
    emit_reply "ok" "$reply" "success"
  else
    emit_reply "error" "Failed to restart FastAPI. Check sudoers configuration." "failure"
  fi
}

main() {
  START_TS=$(date +%s%3N)
  
  if [[ -z "${START_TS:-}" ]]; then
    START_TS=0
  fi
  
  if [[ ! -t 0 ]]; then
    local input
    input=$(cat)
    
    if [[ -n "$input" ]]; then
      ACTION=$(echo "$input" | jq -r '.action // "status"' 2>/dev/null || echo "status")
      ARGS=$(echo "$input" | jq -r '.args // {} | tostring' 2>/dev/null || echo "{}")
      CONFIRMED=$(echo "$input" | jq -r '.confirmed // "false"' 2>/dev/null || echo "false")
      LINES=$(echo "$input" | jq -r '.args.lines // 20' 2>/dev/null || echo "20")
    else
      ACTION="status"
      ARGS="{}"
      CONFIRMED="false"
      LINES="20"
    fi
  else
    ACTION="status"
    ARGS="{}"
    CONFIRMED="false"
    LINES="20"
  fi
  
  case "$ACTION" in
    status)
      action_status
      ;;
    disk)
      action_disk
      ;;
    errors)
      action_errors
      ;;
    restart_backend)
      action_restart_backend
      ;;
    *)
      emit_reply "error" "Unknown server action." "failure"
      ;;
  esac
}

main "$@"