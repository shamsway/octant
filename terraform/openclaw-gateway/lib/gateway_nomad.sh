#!/usr/bin/env bash
# lib/gateway_nomad.sh - gateway commands for nomad targets

_gateway_logs_nomad() {
  local alloc
  alloc="$(_nomad_running_alloc "${NOMAD_JOB}")"
  echo "==> gateway logs: alloc ${alloc}"
  nomad alloc logs -f "${alloc}" "$@"
}

_gateway_logs_err_nomad() {
  local alloc
  alloc="$(_nomad_running_alloc "${NOMAD_JOB}")"
  echo "==> gateway logs (stderr): alloc ${alloc}"
  nomad alloc logs -f -stderr "${alloc}" "$@"
}

_gateway_restart_nomad() {
  local alloc
  alloc="$(_nomad_running_alloc "${NOMAD_JOB}")"
  echo "==> Restarting ${NOMAD_JOB} alloc ${alloc} (via nomad alloc restart)..."
  nomad alloc restart "${alloc}" "$@"
  echo "Done. Watch logs: botctl gateway logs"
}

_gateway_status_nomad() {
  _require_tool nomad
  echo "==> Nomad job: ${NOMAD_JOB}"
  nomad job status "${NOMAD_JOB}"

  local alloc
  alloc="$(_nomad_running_alloc "${NOMAD_JOB}" 2>/dev/null)" || {
    echo ""
    echo "==> openclaw gateway status: (no running allocation)"
    return 0
  }
  echo ""
  echo "==> openclaw status (alloc ${alloc:0:8})"
  nomad alloc exec -task "${NOMAD_JOB}" "${alloc}" \
    node /app/openclaw.mjs status 2>&1 || true
}
