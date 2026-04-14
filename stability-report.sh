#!/usr/bin/env bash
# Cloud Stability Reporter
# Reports on the health and stability of local Retool Docker services.
# Compatible with bash 3.2+ (macOS default) and Docker Desktop.

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

# Parse health from the Status string, e.g. "Up 3 hours (healthy)"
parse_health() {
  local status="$1"
  case "$status" in
    *\(healthy\)*)   echo "healthy" ;;
    *\(unhealthy\)*) echo "unhealthy" ;;
    *)               echo "none" ;;
  esac
}

status_icon() {
  local state="$1" health="$2"
  if [[ "$state" != "running" ]]; then
    printf "${RED}✗${RESET}"
  elif [[ "$health" == "unhealthy" ]]; then
    printf "${YELLOW}⚠${RESET}"
  else
    printf "${GREEN}✓${RESET}"
  fi
}

stability_label() {
  local restarts="$1"
  if   [[ "$restarts" -eq 0 ]]; then printf "${GREEN}stable${RESET}"
  elif [[ "$restarts" -le 3 ]]; then printf "${YELLOW}flapping${RESET}"
  else                               printf "${RED}unstable${RESET}"
  fi
}

# ── banner ───────────────────────────────────────────────────────────────────

echo ""
printf "${BOLD}${CYAN}╔══════════════════════════════════════════════════╗${RESET}\n"
printf "${BOLD}${CYAN}║          Cloud Stability Reporter                ║${RESET}\n"
printf "${BOLD}${CYAN}╚══════════════════════════════════════════════════╝${RESET}\n"
echo "  Generated : ${TIMESTAMP}"
echo "  Compose   : ${COMPOSE_FILE}"
echo ""

# ── gather container data ─────────────────────────────────────────────────────

# Fields: ID, Name, State, Status, RestartCount
DOCKER_FORMAT='{{.ID}}\t{{.Names}}\t{{.State}}\t{{.Status}}\t{{.RestartCount}}'

if ! docker info &>/dev/null; then
  printf "${RED}ERROR: Docker daemon is not running or not accessible.${RESET}\n"
  exit 1
fi

# bash 3-compatible alternative to mapfile
LINES=()
while IFS= read -r line; do
  [[ -n "$line" ]] && LINES+=("$line")
done < <(docker ps -a --filter "label=com.docker.compose.project" --format "$DOCKER_FORMAT" 2>/dev/null || true)

if [[ ${#LINES[@]} -eq 0 ]]; then
  printf "${YELLOW}No compose-managed containers found. Is the stack running?${RESET}\n"
  echo "  Start with:  docker compose -f ${COMPOSE_FILE} up -d --build"
  echo ""
  exit 0
fi

# ── summary counters ──────────────────────────────────────────────────────────

total=0
running=0
stopped=0
unhealthy=0
total_restarts=0
WARNINGS=()

# ── per-service table ─────────────────────────────────────────────────────────

printf "\n${BOLD}%-4s  %-30s  %-10s  %-10s  %-18s  %s${RESET}\n" \
  "St." "Container" "State" "Health" "Restarts" "Uptime / Status"
printf '%0.s─' {1..90}; echo ""

for line in "${LINES[@]}"; do
  IFS=$'\t' read -r id name state status restarts <<< "$line"

  health=$(parse_health "$status")
  icon=$(status_icon "$state" "$health")
  stab=$(stability_label "$restarts")

  printf "%-4b  %-30s  %-10s  %-10s  %-8s  %s\n" \
    "$icon" "$name" "$state" "$health" "$restarts ($stab)" "$status"

  (( total++ ))
  [[ "$state" == "running" ]] && (( running++ )) || (( stopped++ ))
  [[ "$health" == "unhealthy" ]] && (( unhealthy++ ))
  (( total_restarts += restarts ))

  if [[ "$restarts" -gt 3 ]]; then
    WARNINGS+=("  ${YELLOW}⚠${RESET}  ${BOLD}${name}${RESET}: high restart count ($restarts) — docker logs $name")
  fi
  if [[ "$state" != "running" ]]; then
    WARNINGS+=("  ${YELLOW}⚠${RESET}  ${BOLD}${name}${RESET}: container is $state — docker inspect $name")
  fi
  if [[ "$health" == "unhealthy" ]]; then
    WARNINGS+=("  ${YELLOW}⚠${RESET}  ${BOLD}${name}${RESET}: health-check failing — docker logs $name")
  fi
done

# ── resource usage ────────────────────────────────────────────────────────────

echo ""
printf "${BOLD}Resource Usage (running containers)${RESET}\n"
printf '%0.s─' {1..90}; echo ""

if [[ "$running" -gt 0 ]]; then
  docker stats --no-stream --format \
    "table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.MemPerc}}\t{{.NetIO}}\t{{.BlockIO}}" \
    2>/dev/null || echo "  (docker stats unavailable)"
else
  echo "  No running containers."
fi

# ── summary ───────────────────────────────────────────────────────────────────

echo ""
printf "${BOLD}Summary${RESET}\n"
printf '%0.s─' {1..90}; echo ""
printf "  Total containers   : %d\n" "$total"
printf "  Running            : %d\n" "$running"
printf "  Stopped/Exited     : %d\n" "$stopped"
printf "  Unhealthy          : %d\n" "$unhealthy"
printf "  Total restarts     : %d\n" "$total_restarts"

echo ""
if [[ "$stopped" -eq 0 && "$unhealthy" -eq 0 && "$total_restarts" -eq 0 ]]; then
  printf "  ${GREEN}${BOLD}Overall status: ALL SYSTEMS STABLE${RESET}\n"
elif [[ "$stopped" -eq 0 && "$unhealthy" -eq 0 ]]; then
  printf "  ${YELLOW}${BOLD}Overall status: RUNNING WITH RESTARTS${RESET}\n"
elif [[ "$running" -eq 0 ]]; then
  printf "  ${RED}${BOLD}Overall status: STACK IS DOWN${RESET}\n"
else
  printf "  ${YELLOW}${BOLD}Overall status: DEGRADED${RESET}\n"
fi

# ── warnings ──────────────────────────────────────────────────────────────────

if [[ ${#WARNINGS[@]} -gt 0 ]]; then
  echo ""
  printf "${BOLD}${YELLOW}Warnings${RESET}\n"
  printf '%0.s─' {1..90}; echo ""
  for w in "${WARNINGS[@]}"; do
    printf "%b\n" "$w"
  done
fi

# ── quick commands ────────────────────────────────────────────────────────────

echo ""
printf "${BOLD}Quick Commands${RESET}\n"
printf '%0.s─' {1..90}; echo ""
echo "  Start stack   :  docker compose -f ${COMPOSE_FILE} up -d --build"
echo "  Stop stack    :  docker compose -f ${COMPOSE_FILE} down"
echo "  Restart svc   :  docker compose -f ${COMPOSE_FILE} restart <service>"
echo "  Follow logs   :  docker compose -f ${COMPOSE_FILE} logs -f <service>"
echo "  Full report   :  bash stability-report.sh [COMPOSE_FILE=compose-workflows.yaml]"
echo ""
