#!/usr/bin/env bash
# lib/node.sh - botctl node noun handler
#
# Two tracks for remote nodes:
#
#   up/down/restart/logs  — compose-based (dev/smoke testing, runs on current host)
#   status                — Nomad job status for production node jobs
#
# The compose track runs containers with the 'bobby' or 'billy' profile from
# compose/docker-compose.remote-nodes.yml.
#
# The production track is managed via Terraform (remote-nodes.tf) and shows
# Nomad job status for openclaw-node-bobby and openclaw-node-billy.

_configured_nodes() {
  local found=false
  local node
  while IFS= read -r node; do
    [[ -n "${node}" ]] || continue
    found=true
    printf '%s\n' "${node}"
  done < <(yq e '.openclaw.nodes[].name // ""' "${BOTCTL_MERGED_YAML}" 2>/dev/null || true)

  if [[ "${found}" != "true" ]]; then
    printf '%s\n' "bobby" "billy"
  fi
}

cmd_node() {
  local verb="${1:-help}"
  if [[ "${verb}" != "help" && "${verb}" != "--help" && "${verb}" != "-h" ]]; then
    _require_driver nomad "botctl node ${verb}"
  fi
  shift || true
  case "${verb}" in
    up)       _node_up "$@" ;;
    down)     _node_down "$@" ;;
    restart)  _node_restart "$@" ;;
    logs)     _node_logs "$@" ;;
    status)   _node_status "$@" ;;
    help|--help|-h) _botctl_help node ;;
    *)
      echo "error: unknown verb '${verb}' for 'botctl node'" >&2
      _botctl_help node >&2
      exit 1
      ;;
  esac
}

# _validate_node NAME
# Asserts NAME is a known node; exits with error if not.
_validate_node() {
  local name="$1"
  local valid
  while IFS= read -r valid; do
    [[ "${name}" == "${valid}" ]] && return 0
  done < <(_configured_nodes)
  echo "error: unknown node '${name}'. Valid nodes: $(_configured_nodes | tr '\n' ' ')" >&2
  exit 1
}

# _compose_node VERB NODE [ARGS...]
# Runs podman-compose against the remote-nodes compose file with the given profile.
_compose_node() {
  local verb="$1"
  local node="$2"
  shift 2
  _require_tool podman-compose
  podman-compose -f "${COMPOSE_REMOTE_NODES}" --profile "${node}" \
    "${verb}" "openclaw-node-${node}" "$@"
}

_node_up() {
  local node="${1:?Usage: botctl node up <bobby|billy>}"
  shift
  _validate_node "${node}"
  echo "==> Starting openclaw-node-${node} (compose)"
  _compose_node up "${node}" -d "$@"
}

_node_down() {
  local node="${1:?Usage: botctl node down <bobby|billy>}"
  shift
  _validate_node "${node}"
  echo "==> Stopping openclaw-node-${node} (compose)"
  _compose_node down "${node}" "$@"
}

_node_restart() {
  local node="${1:?Usage: botctl node restart <bobby|billy>}"
  shift
  _validate_node "${node}"
  echo "==> Restarting openclaw-node-${node} (compose)"
  _compose_node restart "${node}" "$@"
}

_node_logs() {
  local node="${1:?Usage: botctl node logs <bobby|billy>}"
  shift
  _validate_node "${node}"
  _compose_node logs "${node}" -f "$@"
}

_node_status() {
  _require_tool nomad
  echo "==> Nomad node job status"
  local node
  while IFS= read -r node; do
    local job="openclaw-node-${node}"
    echo ""
    echo "--- ${job} ---"
    nomad job status "${job}" 2>/dev/null || echo "(job not found)"
  done < <(_configured_nodes)
}
