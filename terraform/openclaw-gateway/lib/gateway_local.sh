#!/usr/bin/env bash
# lib/gateway_local.sh - gateway commands for local targets

_local_gateway_health_status() {
  local mode="${1:-append}"
  [[ -n "${LOCAL_HEALTH_URL:-}" ]] || return 1

  local body
  if ! body="$(curl -fsS "${LOCAL_HEALTH_URL}" 2>&1)"; then
    if [[ "${mode}" == "fallback" ]]; then
      _die "failed to query local gateway health URL '${LOCAL_HEALTH_URL}'." \
        "${body}"
    fi
    echo ""
    echo "==> health check"
    echo "Health: unavailable (${LOCAL_HEALTH_URL})"
    return 1
  fi

  if [[ "${body}" == \<* ]] || [[ "${body}" == *"<html"* ]]; then
    if [[ "${mode}" == "fallback" ]]; then
      _die "configured health URL '${LOCAL_HEALTH_URL}' returned HTML instead of a health response." \
        "Unset openclaw.gateway.health_url or point it at a real health endpoint."
    fi
    echo ""
    echo "==> health check"
    echo "Health: unexpected HTML response from ${LOCAL_HEALTH_URL}"
    return 1
  fi

  echo ""
  echo "==> health check"
  if [[ "${mode}" == "fallback" ]]; then
    echo "Health source: HTTP fallback (${LOCAL_HEALTH_URL})"
  else
    echo "Health source: HTTP (${LOCAL_HEALTH_URL})"
  fi

  if command -v jq >/dev/null 2>&1 && printf '%s' "${body}" | jq -e . >/dev/null 2>&1; then
    printf '%s' "${body}" | jq '.'
  else
    printf '%s\n' "${body}"
  fi
}

_print_local_gateway_status_json() {
  local payload="$1"

  if ! command -v jq >/dev/null 2>&1 || ! printf '%s' "${payload}" | jq -e . >/dev/null 2>&1; then
    printf '%s\n' "${payload}"
    return 0
  fi

  local status channels agents sessions
  status="$(printf '%s' "${payload}" | jq -r '
    .status
    // .gateway.status
    // .gatewayState.status
    // .health.status
    // empty
  ')"
  channels="$(printf '%s' "${payload}" | jq -r '
    (.channels // .gateway.channels // .channelStatuses // empty)
    | if type == "array" then length
      elif type == "object" then keys | length
      else empty end
  ')"
  agents="$(printf '%s' "${payload}" | jq -r '
    (.agents // .gateway.agents // empty)
    | if type == "array" then length else empty end
  ')"
  sessions="$(printf '%s' "${payload}" | jq -r '
    (.sessions // .gateway.sessions // empty)
    | if type == "array" then length
      elif type == "object" then keys | length
      else empty end
  ')"

  if [[ -n "${status}" ]]; then
    echo "Status: ${status}"
  fi
  if [[ -n "${channels}" ]]; then
    echo "Channels: ${channels}"
  fi
  if [[ -n "${agents}" ]]; then
    echo "Agents: ${agents}"
  fi
  if [[ -n "${sessions}" ]]; then
    echo "Sessions: ${sessions}"
  fi
  if [[ -n "${status}${channels}${agents}${sessions}" ]]; then
    echo ""
  fi
  printf '%s' "${payload}" | jq '.'
}

_print_local_gateway_status_text() {
  local payload="$1"
  echo "==> openclaw gateway status"
  echo "Target: ${BOTCTL_TARGET_NAME}"
  echo "Driver: local"
  echo "Config dir: ${LOCAL_CONFIG_DIR}"
  echo ""
  printf '%s\n' "${payload}"
}

_gateway_logs_local() {
  if [[ -z "${LOCAL_LOG_FILE:-}" ]]; then
    _die "gateway logs are not configured for target '${BOTCTL_TARGET_NAME}'." \
      "Set openclaw.gateway.log_file or use your local service manager directly."
  fi
  if [[ ! -f "${LOCAL_LOG_FILE}" ]]; then
    _die "configured log file '${LOCAL_LOG_FILE}' was not found." \
      "Update openclaw.gateway.log_file or start the local gateway first."
  fi
  echo "==> gateway logs: ${LOCAL_LOG_FILE}"
  tail -f "${LOCAL_LOG_FILE}" "$@"
}

_gateway_restart_local() {
  case "${LOCAL_RESTART_MODE:-}" in
    manual)
      [[ -n "${LOCAL_RESTART_MESSAGE:-}" ]] || _die \
        "openclaw.gateway.restart.message is required when restart.mode=manual." \
        "Set it under targets.${BOTCTL_TARGET_NAME}.openclaw.gateway.restart."
      printf '%s\n' "${LOCAL_RESTART_MESSAGE}"
      _die "manual action required to restart target '${BOTCTL_TARGET_NAME}'." \
        "Follow the guidance above."
      ;;
    "")
      _die "gateway restart is not configured for target '${BOTCTL_TARGET_NAME}'." \
        "Set openclaw.gateway.restart.mode or restart the local gateway manually."
      ;;
    *)
      _die "unsupported local restart mode '${LOCAL_RESTART_MODE}' for target '${BOTCTL_TARGET_NAME}'." \
        "Supported values for driver=local: manual."
      ;;
  esac
}

_gateway_status_local() {
  local used_cli=false
  local cli_output=""
  local cli_rc=0

  if _cli_bin_exists "${LOCAL_CLI_BIN}"; then
    used_cli=true
    local base_cmd=("${LOCAL_CLI_BIN}")

    local json_cmd=("${base_cmd[@]}" "gateway" "status" "--json")
    if cli_output="$("${json_cmd[@]}" 2>&1)"; then
      if command -v jq >/dev/null 2>&1 && printf '%s' "${cli_output}" | jq -e . >/dev/null 2>&1; then
        echo "==> openclaw gateway status"
        echo "Target: ${BOTCTL_TARGET_NAME}"
        echo "Driver: local"
        echo "Config dir: ${LOCAL_CONFIG_DIR}"
        echo ""
        _print_local_gateway_status_json "${cli_output}"
        _local_gateway_health_status append || true
        return 0
      fi
    fi

    local text_cmd=("${base_cmd[@]}" "gateway" "status")
    cli_output="$("${text_cmd[@]}" 2>&1)" || true
    cli_rc=$?
    if [[ $cli_rc -eq 0 ]]; then
      _print_local_gateway_status_text "${cli_output}"
      _local_gateway_health_status append || true
      return 0
    fi
    if [[ -z "${LOCAL_HEALTH_URL:-}" ]]; then
      _die "failed to query local gateway status via '${LOCAL_CLI_BIN}'." \
        "${cli_output}"
    fi

    echo "==> openclaw gateway status"
    echo "Target: ${BOTCTL_TARGET_NAME}"
    echo "Driver: local"
    echo ""
    echo "CLI status unavailable from '${LOCAL_CLI_BIN}' (exit ${cli_rc})."
    echo "Falling back to configured health URL."
    _local_gateway_health_status fallback
    return 0
  fi

  if [[ -n "${LOCAL_HEALTH_URL:-}" ]]; then
    echo "==> openclaw gateway status"
    echo "Target: ${BOTCTL_TARGET_NAME}"
    echo "Driver: local"
    echo ""
    echo "CLI binary '${LOCAL_CLI_BIN}' was not found. Falling back to configured health URL."
    _local_gateway_health_status fallback
    return 0
  fi

  if [[ "${used_cli}" == false ]]; then
    _die "no local gateway status adapter is configured for target '${BOTCTL_TARGET_NAME}'." \
      "Install '${LOCAL_CLI_BIN}' or set openclaw.gateway.health_url."
  fi
}
