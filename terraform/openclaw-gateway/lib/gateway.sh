#!/usr/bin/env bash
# lib/gateway.sh - botctl gateway noun handler

# shellcheck source=lib/gateway_nomad.sh
source "${LIB_DIR}/gateway_nomad.sh"
# shellcheck source=lib/gateway_local.sh
source "${LIB_DIR}/gateway_local.sh"

cmd_gateway() {
  local verb="${1:-help}"
  shift || true
  case "${verb}" in
    logs)      _gateway_logs "$@" ;;
    logs-err)  _gateway_logs_err "$@" ;;
    restart)   _gateway_restart "$@" ;;
    status)    _gateway_status "$@" ;;
    help|--help|-h) _botctl_help gateway ;;
    *)
      echo "error: unknown verb '${verb}' for 'botctl gateway'" >&2
      _botctl_help gateway >&2
      exit 1
      ;;
  esac
}

_gateway_logs() {
  case "${TARGET_DRIVER}" in
    nomad) _gateway_logs_nomad "$@" ;;
    local) _gateway_logs_local "$@" ;;
  esac
}

_gateway_logs_err() {
  case "${TARGET_DRIVER}" in
    nomad) _gateway_logs_err_nomad "$@" ;;
    local)
      _die "'botctl gateway logs-err' is not supported for target '${BOTCTL_TARGET_NAME}' (driver=local)." \
        "This command is only available for driver=nomad."
      ;;
  esac
}

_gateway_restart() {
  case "${TARGET_DRIVER}" in
    nomad) _gateway_restart_nomad "$@" ;;
    local) _gateway_restart_local "$@" ;;
  esac
}

_gateway_status() {
  case "${TARGET_DRIVER}" in
    nomad) _gateway_status_nomad "$@" ;;
    local) _gateway_status_local "$@" ;;
  esac
}
