#!/usr/bin/env bash
# lib/config_local.sh - config sync commands for local targets

_copy_file_if_newer() {
  local src="$1"
  local dst="$2"
  [[ -f "${src}" ]] || return 0

  local dst_dir
  dst_dir="$(dirname "${dst}")"
  mkdir -p "${dst_dir}"

  if [[ ! -e "${dst}" || "${src}" -nt "${dst}" ]]; then
    cp "${src}" "${dst}"
    return 0
  fi
  return 1
}

_copy_workspace_markdown_if_newer() {
  local src_dir="$1"
  local dst_dir="$2"
  [[ -d "${src_dir}" ]] || return 1

  mkdir -p "${dst_dir}"

  local copied=false
  local src
  shopt -s nullglob
  for src in "${src_dir}"/*.md; do
    local name dst
    name="$(basename "${src}")"
    dst="${dst_dir}/${name}"
    if _copy_file_if_newer "${src}" "${dst}"; then
      copied=true
    fi
  done
  shopt -u nullglob

  [[ "${copied}" == "true" ]]
}

_local_workspace_dir_for_agent() {
  local agent="$1"
  if [[ "${agent}" == "${PRIMARY_AGENT}" ]]; then
    echo "${LOCAL_WORKSPACE_ROOT}/workspace"
  else
    echo "${LOCAL_WORKSPACE_ROOT}/workspace-${agent}"
  fi
}

_config_deploy_local() {
  _require_agents_repo
  _require_local_gateway_config
  _require_local_primary_agent

  echo "==> config deploy (${BOTCTL_TARGET_NAME}): ${AGENTS_REPO} -> ${LOCAL_CONFIG_DIR}"
  echo ""

  local primary_repo="${AGENTS_REPO}/${PRIMARY_AGENT}"
  local config_dir="${LOCAL_CONFIG_DIR}"
  local workspace_root="${LOCAL_WORKSPACE_ROOT}"
  mkdir -p "${config_dir}" "${workspace_root}"

  [[ -f "${primary_repo}/openclaw.json" ]] || _die \
    "required file '${primary_repo}/openclaw.json' was not found." \
    "The primary agent repo must contain openclaw.json."

  if _copy_file_if_newer "${primary_repo}/openclaw.json" "${config_dir}/openclaw.json"; then
    echo "    openclaw.json"
  else
    echo "    openclaw.json (unchanged)"
  fi

  if [[ -f "${primary_repo}/mcporter.json" ]]; then
    if _copy_file_if_newer "${primary_repo}/mcporter.json" "${config_dir}/mcporter.json"; then
      echo "    mcporter.json"
    else
      echo "    mcporter.json (unchanged)"
    fi
  fi

  local agent
  while IFS= read -r agent; do
    [[ -n "${agent}" ]] || continue
    local src="${AGENTS_REPO}/${agent}/workspace"
    local dst
    dst="$(_local_workspace_dir_for_agent "${agent}")"
    if _copy_workspace_markdown_if_newer "${src}" "${dst}"; then
      if [[ "${agent}" == "${PRIMARY_AGENT}" ]]; then
        echo "    workspace/ (*.md)"
      else
        echo "    workspace-${agent}/ (*.md)"
      fi
    else
      if [[ "${agent}" == "${PRIMARY_AGENT}" ]]; then
        echo "    workspace/ (*.md unchanged)"
      else
        echo "    workspace-${agent}/ (*.md unchanged)"
      fi
    fi
  done < <(_config_list 'openclaw.agents')

  echo ""
  echo "Done. Re-run 'botctl gateway restart' if your local service manager requires it."
}

_config_sync_local() {
  _require_agents_repo
  _require_local_gateway_config
  _require_local_primary_agent

  echo "==> config sync (${BOTCTL_TARGET_NAME}): ${LOCAL_CONFIG_DIR} -> ${AGENTS_REPO}"
  echo ""

  local primary_repo="${AGENTS_REPO}/${PRIMARY_AGENT}"
  mkdir -p "${primary_repo}"

  [[ -f "${LOCAL_CONFIG_DIR}/openclaw.json" ]] || _die \
    "required file '${LOCAL_CONFIG_DIR}/openclaw.json' was not found." \
    "Start from a deployed local gateway config before running sync."

  if _copy_file_if_newer "${LOCAL_CONFIG_DIR}/openclaw.json" "${primary_repo}/openclaw.json"; then
    echo "    openclaw.json"
  else
    echo "    openclaw.json (unchanged)"
  fi

  if [[ -f "${LOCAL_CONFIG_DIR}/mcporter.json" ]]; then
    if _copy_file_if_newer "${LOCAL_CONFIG_DIR}/mcporter.json" "${primary_repo}/mcporter.json"; then
      echo "    mcporter.json"
    else
      echo "    mcporter.json (unchanged)"
    fi
  fi

  local agent
  while IFS= read -r agent; do
    [[ -n "${agent}" ]] || continue
    local src dst
    src="$(_local_workspace_dir_for_agent "${agent}")"
    dst="${AGENTS_REPO}/${agent}/workspace"
    if _copy_workspace_markdown_if_newer "${src}" "${dst}"; then
      if [[ "${agent}" == "${PRIMARY_AGENT}" ]]; then
        echo "    workspace/*.md -> ${agent}/workspace/"
      else
        echo "    workspace-${agent}/*.md -> ${agent}/workspace/"
      fi
    else
      if [[ "${agent}" == "${PRIMARY_AGENT}" ]]; then
        echo "    workspace/*.md unchanged"
      else
        echo "    workspace-${agent}/*.md unchanged"
      fi
    fi
  done < <(_config_list 'openclaw.agents')

  echo ""
  echo "Done. Review changes:"
  echo "  cd ${AGENTS_REPO} && git diff"
  echo "Commit when ready:"
  echo "  cd ${AGENTS_REPO} && git add -A && git commit -m 'sync: local config updates'"
}
