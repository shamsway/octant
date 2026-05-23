#!/usr/bin/env bash
# lib/config.sh - botctl config noun handler

# shellcheck source=lib/config_nomad.sh
source "${LIB_DIR}/config_nomad.sh"
# shellcheck source=lib/config_local.sh
source "${LIB_DIR}/config_local.sh"

cmd_config() {
  local verb="${1:-help}"
  shift || true
  case "${verb}" in
    deploy)  _config_deploy "$@" ;;
    sync)    _config_sync "$@" ;;
    help|--help|-h) _botctl_help config ;;
    *)
      echo "error: unknown verb '${verb}' for 'botctl config'" >&2
      _botctl_help config >&2
      exit 1
      ;;
  esac
}

_config_deploy() {
  case "${TARGET_DRIVER}" in
    nomad) _config_deploy_nomad "$@" ;;
    local) _config_deploy_local "$@" ;;
  esac
}

_config_sync() {
  case "${TARGET_DRIVER}" in
    nomad) _config_sync_nomad "$@" ;;
    local) _config_sync_local "$@" ;;
  esac
}
