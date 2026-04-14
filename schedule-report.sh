#!/usr/bin/env bash
# Installs (or removes) a cron job that runs stability-report.sh
# on the 1st of every month at 6:00 AM.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPORT_SCRIPT="${SCRIPT_DIR}/stability-report.sh"
LOG_FILE="${SCRIPT_DIR}/stability-report.log"
CRON_TAG="# retool-stability-reporter"
CRON_ENTRY="0 6 1 * * bash \"${REPORT_SCRIPT}\" >> \"${LOG_FILE}\" 2>&1 ${CRON_TAG}"

usage() {
  echo "Usage: bash schedule-report.sh [install|uninstall|status]"
  echo ""
  echo "  install    Add cron job (1st of every month at 06:00)"
  echo "  uninstall  Remove cron job"
  echo "  status     Show whether the cron job is installed"
  echo ""
  echo "  Defaults to 'install' when no argument is given."
}

install() {
  if ! [[ -f "$REPORT_SCRIPT" ]]; then
    echo "ERROR: stability-report.sh not found at ${REPORT_SCRIPT}"
    exit 1
  fi

  # Remove any existing entry first to avoid duplicates
  crontab -l 2>/dev/null | grep -v "$CRON_TAG" | crontab - || true

  # Append the new entry
  ( crontab -l 2>/dev/null; echo "$CRON_ENTRY" ) | crontab -

  echo "Cron job installed."
  echo "  Schedule : 1st of every month at 06:00"
  echo "  Script   : ${REPORT_SCRIPT}"
  echo "  Log      : ${LOG_FILE}"
  echo ""
  echo "Run 'bash schedule-report.sh status' to verify."
}

uninstall() {
  crontab -l 2>/dev/null | grep -v "$CRON_TAG" | crontab - || true
  echo "Cron job removed."
}

status() {
  if crontab -l 2>/dev/null | grep -q "$CRON_TAG"; then
    echo "Installed — runs on the 1st of every month at 06:00."
    echo "Log: ${LOG_FILE}"
  else
    echo "Not installed. Run 'bash schedule-report.sh install' to add it."
  fi
}

case "${1:-install}" in
  install)   install ;;
  uninstall) uninstall ;;
  status)    status ;;
  -h|--help) usage ;;
  *) echo "Unknown command: $1"; usage; exit 1 ;;
esac
