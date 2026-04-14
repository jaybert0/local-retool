#!/usr/bin/env bash
# Cloud Stability Reporter
# Reports on the health and stability of local Retool Docker services.

set -euo pipefail

COMPOSE_FILE="${COMPOSE_FILE:-compose.yaml}"
TIMESTAMP="$(date '+%Y-%m-%d %H:%M:%S')"

RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
BOLD='\033[1m'
RESET='\033[0m'

# ── helpers ──────────────────────────────────────────────────────────────────

status_icon() {
  local state="$1" health="$2"
  if [[ "$state" != "running" ]]; then
    echo -e "${RED}✗${RESET}"
  elif [[ "$health" == "unhealthy" ]]; then
    echo -e "${YELLOW}⚠${RESET}"
  elif [[ "$health" == "healthy" ]]; then
    echo -e "${GREEN}✓${RESET}"
  else
    echo -e "${GREEN}✓${RESET}"   # running, no health-check configured
  fi
}

stability_label() {
  local restarts="$1"
  if   [[ "$restarts" -eq 0 ]];  then echo -e "${GREEN}stable${RESET}"
  elif [[ "$restarts" -le 3 ]];  then echo -e "${YELLOW}flapping${RESET}"
  else                                 echo -e "${RED}unstable${RESET}"
  fi
}

# ── banner ───────────────────────────────────────────────────────────────────

echo -e ""
echo -e "${BOLD}${CYAN}╔══════════════════════════════════════════════════╗${RESET}"
echo -e "${BOLD}${CYAN}║          Cloud Stability Reporter                ║${RESET}"
echo -e "${BOLD}${CYAN}╚══════════════════════════════════════════════════╝${RESET}"
echo -e "  Generated : ${TIMESTAMP}"
echo -e "  Compose   : ${COMPOSE_FILE}"
echo ""

# ── gather container data ─────────────────────────────────────────────────────

# docker ps returns tab-separated fields when using --format with \t
# Fields: ID, Name, State, Status, Health, RestartCount, CreatedAt
DOCKER_FORMAT='{{.ID}}\t{{.Names}}\t{{.State}}\t{{.Status}}\t{{.Health}}\t{{.RestartCount}}\t{{.CreatedAt}}'

if ! docker info &>/dev/null; then
  echo -e "${RED}ERROR: Docker daemon is not running or not accessible.${RESET}"
  exit 1
fi

# Get all containers for the active compose project (by label) or fall back to
# containers whose name matches common Retool service names.
mapfile -t LINES < <(
  docker ps -a \
    --filter "label=com.docker.compose.project" \
    --format "$DOCKER_FORMAT" \
  || true
)

if [[ ${#LINES[@]} -eq 0 ]]; then
  echo -e "${YELLOW}No compose-managed containers found. Is the stack running?${RESET}"
  echo -e "  Start with:  docker compose -f ${COMPOSE_FILE} up -d --build"
  echo ""
  exit 0
fi

# ── summary counters ──────────────────────────────────────────────────────────

total=0
running=0
stopped=0
unhealthy=0
total_restarts=0

# ── per-service table ─────────────────────────────────────────────────────────

printf "\n${BOLD}%-3s  %-30s  %-10s  %-10s  %-8s  %s${RESET}\n" \
  "St." "Container" "State" "Health" "Restarts" "Uptime / Status"
printf '%0.s─' {1..85}; echo ""

declare -A WARN_MESSAGES

for line in "${LINES[@]}"; do
  IFS=$'\t' read -r id name state status health restarts created <<< "$line"

  icon=$(status_icon "$state" "$health")
  stability=$(stability_label "$restarts")
  health_display="${health:-none}"

  # Uptime lives inside the Status field, e.g. "Up 3 hours" / "Exited (1) 5 min ago"
  uptime_str="$status"

  printf "%-4b  %-30s  %-10s  %-10s  %-8s  %s\n" \
    "$icon" "$name" "$state" "$health_display" "$restarts ($stability)" "$uptime_str"

  (( total++ ))
  [[ "$state" == "running" ]]   && (( running++ ))   || (( stopped++ ))
  [[ "$health" == "unhealthy" ]] && (( unhealthy++ ))
  (( total_restarts += restarts ))

  if [[ "$restarts" -gt 3 ]]; then
    WARN_MESSAGES["$name"]="High restart count ($restarts). Check logs: docker logs $name"
  fi
  if [[ "$state" != "running" ]]; then
    WARN_MESSAGES["$name"]="${WARN_MESSAGES[$name]:-}  Container is $state. Inspect: docker inspect $name"
  fi
  if [[ "$health" == "unhealthy" ]]; then
    WARN_MESSAGES["$name"]="${WARN_MESSAGES[$name]:-}  Health-check failing. Logs: docker logs $name"
  fi
done

# ── resource usage ─────────────────────────────────────────────────────────────

echo ""
echo -e "${BOLD}Resource Usage (running containers)${RESET}"
printf '%0.s─' {1..85}; echo ""

if [[ "$running" -gt 0 ]]; then
  docker stats --no-stream --format \
    "table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.MemPerc}}\t{{.NetIO}}\t{{.BlockIO}}" \
    2>/dev/null || echo "  (docker stats unavailable)"
else
  echo "  No running containers."
fi

# ── overall health summary ────────────────────────────────────────────────────

echo ""
echo -e "${BOLD}Summary${RESET}"
printf '%0.s─' {1..85}; echo ""
printf "  Total containers   : %d\n" "$total"
printf "  Running            : %d\n" "$running"
printf "  Stopped/Exited     : %d\n" "$stopped"
printf "  Unhealthy          : %d\n" "$unhealthy"
printf "  Total restarts     : %d\n" "$total_restarts"

echo ""
if [[ "$stopped" -eq 0 && "$unhealthy" -eq 0 && "$total_restarts" -eq 0 ]]; then
  echo -e "  ${GREEN}${BOLD}Overall status: ALL SYSTEMS STABLE${RESET}"
elif [[ "$stopped" -eq 0 && "$unhealthy" -eq 0 ]]; then
  echo -e "  ${YELLOW}${BOLD}Overall status: RUNNING WITH RESTARTS${RESET}"
elif [[ "$running" -eq 0 ]]; then
  echo -e "  ${RED}${BOLD}Overall status: STACK IS DOWN${RESET}"
else
  echo -e "  ${YELLOW}${BOLD}Overall status: DEGRADED${RESET}"
fi

# ── warnings ──────────────────────────────────────────────────────────────────

if [[ ${#WARN_MESSAGES[@]} -gt 0 ]]; then
  echo ""
  echo -e "${BOLD}${YELLOW}Warnings${RESET}"
  printf '%0.s─' {1..85}; echo ""
  for name in "${!WARN_MESSAGES[@]}"; do
    echo -e "  ${YELLOW}⚠${RESET}  ${BOLD}${name}${RESET}"
    echo "     ${WARN_MESSAGES[$name]}"
  done
fi

# ── quick-reference commands ───────────────────────────────────────────────────

echo ""
echo -e "${BOLD}Quick Commands${RESET}"
printf '%0.s─' {1..85}; echo ""
echo "  Start stack   :  docker compose -f ${COMPOSE_FILE} up -d --build"
echo "  Stop stack    :  docker compose -f ${COMPOSE_FILE} down"
echo "  Restart svc   :  docker compose -f ${COMPOSE_FILE} restart <service>"
echo "  Follow logs   :  docker compose -f ${COMPOSE_FILE} logs -f <service>"
echo "  Full report   :  bash stability-report.sh [COMPOSE_FILE=compose-workflows.yaml]"
echo ""
