#!/usr/bin/env bash
# shellcheck disable=SC2034,SC2088,SC2155
# SC2034: Variables are exported to sourcing scripts (gateway_local.sh, etc.)
# SC2088: Tilde pattern matching is intentional in _expand_path
# SC2155: Combined declare+assign is acceptable here for config loading
#
# lib/common.sh - Shared config loading, helpers, and validation
#
# Sourced by botctl before delegating to a noun handler. Resolves the active
# target, builds a merged working config, and exposes shared helpers/globals.

BOTCTL_YAML="${BOTCTL_DIR}/botctl.yaml"
BOTCTL_LOCAL_YAML="${BOTCTL_DIR}/botctl.local.yaml"
BOTCTL_TARGET_NAME="${BOTCTL_TARGET:-}"
BOTCTL_TARGET_SOURCE="${BOTCTL_TARGET_SOURCE:-}"
BOTCTL_TARGET_SELECTION_SOURCE=""
BOTCTL_MERGED_YAML=""
TARGET_DRIVER=""

_die() {
  local message="$1"
  local detail="${2:-}"
  echo "error: ${message}" >&2
  if [[ -n "${detail}" ]]; then
    echo "       ${detail}" >&2
  fi
  exit 1
}

_expand_path() {
  local path="${1:-}"
  case "${path}" in
    ""|"null") echo "" ;;
    "~") echo "${HOME}" ;;
    "~/"*) echo "${HOME}/${path#~/}" ;;
    *) echo "${path}" ;;
  esac
}

_expand_command_path() {
  local value="${1:-}"
  case "${value}" in
    ""|"null") echo "" ;;
    "~"*|/*) _expand_path "${value}" ;;
    *) echo "${value}" ;;
  esac
}

_resolve_module_path() {
  local path
  path="$(_expand_path "${1:-}")"
  if [[ -z "${path}" ]]; then
    echo ""
  elif [[ "${path}" == /* ]]; then
    echo "${path}"
  else
    echo "${BOTCTL_DIR}/${path}"
  fi
}

_botctl_cleanup() {
  if [[ -n "${BOTCTL_MERGED_YAML:-}" && -f "${BOTCTL_MERGED_YAML}" ]]; then
    rm -f "${BOTCTL_MERGED_YAML}"
  fi
}

_list_targets() {
  yq e '.targets | keys | .[]' "${BOTCTL_YAML}" 2>/dev/null || true
}

_target_exists() {
  local name="$1"
  local tag
  tag="$(BOTCTL_LOOKUP_TARGET="${name}" \
    yq e '.targets[env(BOTCTL_LOOKUP_TARGET)] | tag' "${BOTCTL_YAML}" 2>/dev/null || true)"
  [[ "${tag}" != "!!null" && -n "${tag}" ]]
}

_describe_target_selection_source() {
  case "${BOTCTL_TARGET_SELECTION_SOURCE:-}" in
    cli) echo "--target" ;;
    env) echo "BOTCTL_TARGET" ;;
    defaults.target) echo "defaults.target" ;;
    implicit-single-target) echo "implicit single target" ;;
    *) echo "unknown" ;;
  esac
}

_resolve_target() {
  [[ -f "${BOTCTL_YAML}" ]] || _die "botctl config file was not found." \
    "Expected file: ${BOTCTL_YAML}"

  if [[ -n "${BOTCTL_TARGET_NAME}" ]]; then
    _target_exists "${BOTCTL_TARGET_NAME}" || _die \
      "requested target '${BOTCTL_TARGET_NAME}' was not found." \
      "Define it under 'targets:' in ${BOTCTL_YAML}."
    BOTCTL_TARGET_SELECTION_SOURCE="${BOTCTL_TARGET_SOURCE:-env}"
    export BOTCTL_TARGET="${BOTCTL_TARGET_NAME}"
    return
  fi

  local default_target
  default_target="$(yq e '.defaults.target // ""' "${BOTCTL_YAML}" 2>/dev/null || true)"
  [[ "${default_target}" == "null" ]] && default_target=""
  if [[ -n "${default_target}" ]]; then
    BOTCTL_TARGET_NAME="${default_target}"
    BOTCTL_TARGET_SELECTION_SOURCE="defaults.target"
    export BOTCTL_TARGET="${BOTCTL_TARGET_NAME}"
    return
  fi

  local target_count=0
  local only_target=""
  local target_name
  while IFS= read -r target_name; do
    [[ -n "${target_name}" ]] || continue
    target_count=$((target_count + 1))
    only_target="${target_name}"
  done < <(_list_targets)
  if [[ ${target_count} -eq 1 ]]; then
    BOTCTL_TARGET_NAME="${only_target}"
    BOTCTL_TARGET_SELECTION_SOURCE="implicit-single-target"
    export BOTCTL_TARGET="${BOTCTL_TARGET_NAME}"
    return
  fi

  if [[ ${target_count} -eq 0 ]]; then
    _die "no targets are defined in botctl.yaml." \
      "Add a 'targets:' map to ${BOTCTL_YAML}."
  fi

  _die "no target selected." \
    "Use --target <name>, set BOTCTL_TARGET, or define defaults.target in botctl.yaml."
}

_build_merged_config() {
  export BOTCTL_ACTIVE_TARGET="${BOTCTL_TARGET_NAME}"
  BOTCTL_MERGED_YAML="$(mktemp "${TMPDIR:-/tmp}/botctl-config.XXXXXX")"

  if [[ -f "${BOTCTL_LOCAL_YAML}" ]]; then
    yq ea '
      select(fileIndex == 0) as $root |
      select(fileIndex == 1) as $overlay |
      ((($root * ($root.targets[env(BOTCTL_ACTIVE_TARGET)] // {}))
        | del(.targets)
        | del(.defaults)) * $overlay)
    ' "${BOTCTL_YAML}" "${BOTCTL_LOCAL_YAML}" > "${BOTCTL_MERGED_YAML}"
  else
    yq e '
      (. * (.targets[env(BOTCTL_ACTIVE_TARGET)] // {}))
      | del(.targets)
      | del(.defaults)
    ' "${BOTCTL_YAML}" > "${BOTCTL_MERGED_YAML}"
  fi

  trap _botctl_cleanup EXIT INT TERM
}

# _config_get KEY
# Read a dotted key from the resolved target config.
# Returns the value, or empty string if not set / null.
_config_get() {
  local key="$1"
  local val
  val="$(yq e ".${key}" "${BOTCTL_MERGED_YAML}" 2>/dev/null || true)"
  [[ "${val}" == "null" ]] && val=""
  echo "${val}"
}

# _config_list KEY
# Prints one list item per line for a dotted array key.
_config_list() {
  local key="$1"
  yq e ".${key}[]?" "${BOTCTL_MERGED_YAML}" 2>/dev/null || true
}

_target_driver() {
  echo "${TARGET_DRIVER}"
}

_cli_bin_exists() {
  local cli_bin="${1:-}"
  [[ -n "${cli_bin}" ]] || return 1
  if [[ "${cli_bin}" == */* ]]; then
    [[ -x "${cli_bin}" ]]
  else
    command -v "${cli_bin}" >/dev/null 2>&1
  fi
}

_agent_is_configured() {
  local needle="$1"
  local agent
  while IFS= read -r agent; do
    [[ "${agent}" == "${needle}" ]] && return 0
  done < <(_config_list 'openclaw.agents')
  return 1
}

# ── Validation helpers ────────────────────────────────────────────────────────

_require_tool() {
  local tool="$1"
  if ! command -v "${tool}" &>/dev/null; then
    _die "'${tool}' is required but not found in PATH."
  fi
}

_require_driver() {
  local required_driver="$1"
  local command_label="${2:-this command}"
  if [[ "${TARGET_DRIVER}" != "${required_driver}" ]]; then
    _die "'${command_label}' is not supported for target '${BOTCTL_TARGET_NAME}' (driver=${TARGET_DRIVER})." \
      "This command is only available for driver=${required_driver}."
  fi
}

_require_ceph() {
  if [[ -z "${CEPH_BASE:-}" ]]; then
    _die "storage.ceph_base is not configured." \
      "This operation requires direct filesystem access to CephFS."
  fi
}

_require_agents_repo() {
  if [[ -z "${AGENTS_REPO:-}" ]]; then
    _die "storage.agents_repo is not configured." \
      "Set BOTCTL_AGENTS_REPO or add 'storage.agents_repo' to botctl.local.yaml."
  fi
  if [[ ! -d "${AGENTS_REPO}" ]]; then
    _die "agents_repo '${AGENTS_REPO}' does not exist." \
      "Set BOTCTL_AGENTS_REPO or update 'storage.agents_repo' in botctl.local.yaml."
  fi
}

_require_source_repo() {
  if [[ -z "${SOURCE_REPO:-}" ]]; then
    _die "openclaw.source_repo is not configured." \
      "Set BOTCTL_SOURCE_REPO or add 'openclaw.source_repo' to botctl.local.yaml."
  fi
  if [[ ! -d "${SOURCE_REPO}" ]]; then
    _die "source_repo '${SOURCE_REPO}' does not exist."
  fi
}

_require_build_context() {
  if [[ -n "${SOURCE_REPO:-}" ]] && [[ -d "${SOURCE_REPO}" ]]; then
    return 0
  fi
  if [[ -n "${GITHUB_URL:-}" ]]; then
    return 0
  fi
  _die "no build context configured." \
    "Set 'openclaw.github_url' in botctl.yaml, or set 'openclaw.source_repo' / BOTCTL_SOURCE_REPO for a local path."
}

_require_local_gateway_config() {
  if [[ -z "${LOCAL_CONFIG_DIR:-}" ]]; then
    _die "openclaw.gateway.config_dir is not configured for target '${BOTCTL_TARGET_NAME}'." \
      "Set it under targets.${BOTCTL_TARGET_NAME}.openclaw.gateway.config_dir."
  fi
}

_require_local_primary_agent() {
  if [[ -z "${PRIMARY_AGENT:-}" ]]; then
    _die "openclaw.gateway.primary_agent is not configured for target '${BOTCTL_TARGET_NAME}'." \
      "Set it under targets.${BOTCTL_TARGET_NAME}.openclaw.gateway.primary_agent."
  fi
  _agent_is_configured "${PRIMARY_AGENT}" || _die \
    "primary agent '${PRIMARY_AGENT}' is not listed in openclaw.agents for target '${BOTCTL_TARGET_NAME}'." \
    "Add it to targets.${BOTCTL_TARGET_NAME}.openclaw.agents."
}

# ── Image resolution ──────────────────────────────────────────────────────────

_resolve_image_tag() {
  local version="${BOTCTL_IMAGE_VERSION:-}"
  if [[ -z "${version}" ]]; then
    version="$(_config_get 'openclaw.image.version' 2>/dev/null || true)"
  fi
  if [[ -z "${version}" ]] && [[ -n "${SOURCE_REPO:-}" ]] && [[ -f "${SOURCE_REPO}/package.json" ]]; then
    version="$(node -p "require('${SOURCE_REPO}/package.json').version" 2>/dev/null || true)"
  fi
  if [[ -z "${version}" ]] && [[ -n "${GITHUB_URL:-}" ]]; then
    local owner_repo="${GITHUB_URL#https://github.com/}"
    owner_repo="${owner_repo%/}"
    local raw_url="https://raw.githubusercontent.com/${owner_repo}/${GITHUB_REF}/package.json"
    version="$(curl -fsSL "${raw_url}" 2>/dev/null | jq -r '.version // empty' 2>/dev/null || true)"
  fi
  echo "${version:-local}"
}

_resolve_local_image() {
  echo "${IMAGE_NAME}:$(_resolve_image_tag)"
}

_resolve_registry_image() {
  local img="${1:-$(_resolve_local_image)}"
  local base="${img#*/}"
  echo "${IMAGE_REGISTRY}/${base}"
}

_resolve_build_context() {
  if [[ -n "${SOURCE_REPO:-}" ]] && [[ -d "${SOURCE_REPO}" ]]; then
    echo "${SOURCE_REPO}"
  else
    echo "${GITHUB_URL}.git#${GITHUB_REF}"
  fi
}

# ── Nomad helpers ─────────────────────────────────────────────────────────────

_nomad_running_alloc() {
  local job="${1:-${NOMAD_JOB}}"
  _require_tool nomad
  _require_tool jq
  local alloc
  alloc="$(nomad job allocs -json "${job}" 2>/dev/null \
    | jq -r '[.[] | select(.ClientStatus == "running")] | first | .ID // empty')"
  if [[ -z "${alloc}" ]]; then
    echo "error: no running allocation found for Nomad job '${job}'" >&2
    return 1
  fi
  echo "${alloc}"
}

# ── Resolve target-scoped config ──────────────────────────────────────────────

_resolve_target
_build_merged_config

TARGET_DRIVER="$(_config_get 'driver')"
case "${TARGET_DRIVER}" in
  nomad|local) ;;
  "")
    _die "target '${BOTCTL_TARGET_NAME}' is missing required field 'driver'." \
      "Set targets.${BOTCTL_TARGET_NAME}.driver to 'nomad' or 'local'."
    ;;
  *)
    _die "target '${BOTCTL_TARGET_NAME}' has unsupported driver '${TARGET_DRIVER}'." \
      "Valid values: nomad, local."
    ;;
esac

# Env vars take precedence over yaml config.
NOMAD_JOB="${BOTCTL_NOMAD_JOB:-$(_config_get 'openclaw.nomad_job')}"
NOMAD_JOB="${NOMAD_JOB:-openclaw-gateway}"

IMAGE_NAME="${BOTCTL_IMAGE_NAME:-$(_config_get 'openclaw.image.name')}"
IMAGE_NAME="${IMAGE_NAME:-openclaw-homelab}"

IMAGE_REGISTRY="${BOTCTL_IMAGE_REGISTRY:-$(_config_get 'openclaw.image.registry')}"
IMAGE_REGISTRY="${IMAGE_REGISTRY:-registry.service.consul:8082}"

SOURCE_REPO="$(_expand_path "${BOTCTL_SOURCE_REPO:-$(_config_get 'openclaw.source_repo')}")"
AGENTS_REPO="$(_expand_path "${BOTCTL_AGENTS_REPO:-$(_config_get 'storage.agents_repo')}")"
CEPH_BASE="$(_expand_path "${BOTCTL_CEPH_BASE:-$(_config_get 'storage.ceph_base')}")"
GITHUB_URL="${BOTCTL_GITHUB_URL:-$(_config_get 'openclaw.github_url')}"
GITHUB_REF="${BOTCTL_GITHUB_REF:-$(_config_get 'openclaw.github_ref')}"
GITHUB_REF="${GITHUB_REF:-main}"

COMPOSE_BASE="$(_resolve_module_path "$(_config_get 'openclaw.compose.base')")"
COMPOSE_PODMAN="$(_resolve_module_path "$(_config_get 'openclaw.compose.podman')")"
COMPOSE_REMOTE_NODES="$(_resolve_module_path "$(_config_get 'openclaw.compose.remote_nodes')")"

PRIMARY_AGENT="$(_config_get 'openclaw.gateway.primary_agent')"
LOCAL_CONFIG_DIR="$(_expand_path "$(_config_get 'openclaw.gateway.config_dir')")"
LOCAL_WORKSPACE_ROOT="$(_expand_path "$(_config_get 'openclaw.gateway.workspace_root')")"
LOCAL_WORKSPACE_ROOT="${LOCAL_WORKSPACE_ROOT:-${LOCAL_CONFIG_DIR}}"
LOCAL_HEALTH_URL="$(_config_get 'openclaw.gateway.health_url')"
LOCAL_LOG_FILE="$(_expand_path "$(_config_get 'openclaw.gateway.log_file')")"
LOCAL_CLI_BIN="$(_expand_command_path "$(_config_get 'openclaw.gateway.cli_bin')")"
LOCAL_CLI_BIN="${LOCAL_CLI_BIN:-openclaw}"
LOCAL_RESTART_MODE="$(_config_get 'openclaw.gateway.restart.mode')"
LOCAL_RESTART_MESSAGE="$(_config_get 'openclaw.gateway.restart.message')"

if [[ "${TARGET_DRIVER}" == "local" ]]; then
  _require_local_gateway_config
  _require_local_primary_agent
fi

# ── Help ──────────────────────────────────────────────────────────────────────

_botctl_help() {
  local noun="${1:-}"
  local target_note="target: ${BOTCTL_TARGET_NAME} (driver=${TARGET_DRIVER}, selected via $(_describe_target_selection_source))"
  case "${noun}" in
    gateway|gw)
      if [[ "${TARGET_DRIVER}" == "nomad" ]]; then
        cat <<EOF
botctl gateway <verb>

${target_note}

  logs        Follow gateway stdout logs (Nomad alloc)
  logs-err    Follow gateway stderr logs
  restart     Restart the running gateway allocation
  status      Show Nomad job status + openclaw internal gateway status
EOF
      else
        cat <<EOF
botctl gateway <verb>

${target_note}

  logs        Follow the configured local log file
  restart     Print the configured local restart instructions
  status      Query the local gateway via the OpenClaw CLI / health URL

Notes:
  logs-err is not supported for driver=local.
EOF
      fi
      ;;
    node)
      if [[ "${TARGET_DRIVER}" == "nomad" ]]; then
        cat <<EOF
botctl node <verb> [name]

${target_note}

  up <name>       Start a remote node container (podman-compose)
  down <name>     Stop a remote node container
  restart <name>  Restart a remote node container
  logs <name>     Follow remote node logs
  status          Show Nomad job status for all remote node jobs
EOF
      else
        cat <<EOF
botctl node <verb> [name]

${target_note}

Node commands are only available for driver=nomad targets.
EOF
      fi
      ;;
    image|img)
      if [[ "${TARGET_DRIVER}" == "nomad" ]]; then
        cat <<EOF
botctl image <verb>

${target_note}

  build [--base-only]                  Build infra image (and base)
  push                                 Tag and push to registry
  pull                                 Pull from registry and tag locally
  deploy [--skip-build] [--skip-push]  Build + push + terraform apply
         [--auto-approve]
EOF
      else
        cat <<EOF
botctl image <verb>

${target_note}

  build [--base-only]  Build infra image (and base)
  push                 Tag and push to registry
  pull                 Pull from registry and tag locally

Notes:
  image deploy is not supported for driver=local.
EOF
      fi
      ;;
    config|cfg)
      cat <<EOF
botctl config <verb>

${target_note}

  deploy   Push agent configs to the selected runtime
  sync     Pull live runtime edits back to the agents repo
EOF
      ;;
    cli)
      if [[ "${TARGET_DRIVER}" == "nomad" ]]; then
        cat <<EOF
botctl cli [args...]

${target_note}

Launch an interactive container shell with the openclaw alias configured.
Mounts config and workspace directories from the host.
EOF
      else
        cat <<EOF
botctl cli [args...]

${target_note}

Run the configured local OpenClaw CLI directly.
EOF
      fi
      ;;
    *)
      cat <<EOF
botctl - OpenClaw gateway management CLI

Usage: botctl [--target <name>] <noun> <verb> [args...]

Selected target: ${BOTCTL_TARGET_NAME}
Driver: ${TARGET_DRIVER}
Selection source: $(_describe_target_selection_source)

Nouns:
  gateway (gw)    Manage the selected gateway
  node            Manage remote node containers (nomad targets only)
  image (img)     Build and push container images
  config (cfg)    Sync configs between git and the selected runtime
  cli             Open a target-aware OpenClaw CLI session
  version         Show version info

Run 'botctl help <noun>' for detailed usage of each noun.

Config: ${BOTCTL_YAML}
Local overrides: ${BOTCTL_LOCAL_YAML} $( [[ -f "${BOTCTL_LOCAL_YAML}" ]] && echo "(loaded)" || echo "(not present)" )
See docs/OPERATIONS.md for full documentation.
EOF
      ;;
  esac
}
