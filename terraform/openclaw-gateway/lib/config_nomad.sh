#!/usr/bin/env bash
# lib/config_nomad.sh - config sync commands for nomad targets
#
# Supports two source layouts:
#
# 1. External agents repo (AGENTS_REPO set):
#    Config and workspaces live in an external git repo (e.g. openclaw-agents/).
#    Layout: <agents_repo>/<agent>/openclaw.json, <agents_repo>/<agent>/workspace/
#
# 2. Module-local config (AGENTS_REPO unset):
#    Config and workspaces live alongside the Terraform module in config/.
#    Layout: <botctl_dir>/config/openclaw.json, <botctl_dir>/config/workspace/
#
# In both cases, the CephFS destination layout is:
#    <ceph_base>/config/openclaw.json
#    <ceph_base>/workspaces/<agent>/*.md

_config_deploy_nomad() {
  _require_ceph
  _require_tool rsync

  local ceph_config="${CEPH_BASE}/config"

  echo "==> config deploy (${BOTCTL_TARGET_NAME}): -> ${CEPH_BASE}"
  echo ""

  if [[ -n "${AGENTS_REPO:-}" ]] && [[ -d "${AGENTS_REPO}" ]]; then
    # External agents repo layout: <agents_repo>/<primary_agent>/openclaw.json
    local primary_agent
    primary_agent="$(_config_list 'openclaw.agents' | head -1)"
    primary_agent="${primary_agent:-scotty}"

    echo "    openclaw.json (from ${AGENTS_REPO}/${primary_agent}/)"
    cp "${AGENTS_REPO}/${primary_agent}/openclaw.json" "${ceph_config}/openclaw.json"

    if [[ -f "${AGENTS_REPO}/${primary_agent}/mcporter.json" ]]; then
      echo "    mcporter.json"
      cp "${AGENTS_REPO}/${primary_agent}/mcporter.json" "${ceph_config}/mcporter.json"
    fi

    local agent
    while IFS= read -r agent; do
      [[ -n "${agent}" ]] || continue
      local src="${AGENTS_REPO}/${agent}/workspace"
      local dst="${CEPH_BASE}/workspaces/${agent}"
      [[ -d "${src}" ]] || continue
      echo "    workspaces/${agent}/ (*.md)"
      mkdir -p "${dst}"
      rsync -a --include="*.md" --exclude="*" "${src}/" "${dst}/"
    done < <(_config_list 'openclaw.agents')
  else
    # Module-local layout: <botctl_dir>/config/openclaw.json
    local config_dir="${BOTCTL_DIR}/config"

    echo "    openclaw.json (from ${config_dir}/)"
    cp "${config_dir}/openclaw.json" "${ceph_config}/openclaw.json"

    if [[ -f "${config_dir}/mcporter.json" ]]; then
      echo "    mcporter.json"
      cp "${config_dir}/mcporter.json" "${ceph_config}/mcporter.json"
    fi

    local agent
    while IFS= read -r agent; do
      [[ -n "${agent}" ]] || continue
      # Module-local: workspace files live in config/workspace/ (single agent)
      local src="${config_dir}/workspace"
      local dst="${CEPH_BASE}/workspaces/${agent}"
      [[ -d "${src}" ]] || continue
      echo "    workspaces/${agent}/ (*.md)"
      mkdir -p "${dst}"
      rsync -a --include="*.md" --exclude="*" "${src}/" "${dst}/"
    done < <(_config_list 'openclaw.agents')
  fi

  echo ""
  echo "Done. openclaw.json hot-reloads automatically."
  echo "Run 'botctl gateway restart' if you changed tool/plugin config."
}

_config_sync_nomad() {
  _require_ceph

  local ceph_config="${CEPH_BASE}/config"

  echo "==> config sync (${BOTCTL_TARGET_NAME}): ${CEPH_BASE} -> local"
  echo ""

  if [[ -n "${AGENTS_REPO:-}" ]] && [[ -d "${AGENTS_REPO}" ]]; then
    _require_tool rsync

    local primary_agent
    primary_agent="$(_config_list 'openclaw.agents' | head -1)"
    primary_agent="${primary_agent:-scotty}"

    echo "    openclaw.json -> ${AGENTS_REPO}/${primary_agent}/"
    cp "${ceph_config}/openclaw.json" "${AGENTS_REPO}/${primary_agent}/openclaw.json"

    if [[ -f "${ceph_config}/mcporter.json" ]]; then
      echo "    mcporter.json"
      cp "${ceph_config}/mcporter.json" "${AGENTS_REPO}/${primary_agent}/mcporter.json"
    fi

    if [[ -f "${ceph_config}/cron/jobs.json" ]]; then
      echo "    cron/jobs.json"
      mkdir -p "${AGENTS_REPO}/${primary_agent}/cron"
      cp "${ceph_config}/cron/jobs.json" "${AGENTS_REPO}/${primary_agent}/cron/jobs.json"
    fi

    local agent
    while IFS= read -r agent; do
      [[ -n "${agent}" ]] || continue
      local src="${CEPH_BASE}/workspaces/${agent}"
      local dst="${AGENTS_REPO}/${agent}/workspace"
      [[ -d "${src}" ]] || continue
      echo "    workspaces/${agent}/*.md -> ${agent}/workspace/"
      mkdir -p "${dst}"
      rsync -a --include="*.md" --exclude="*" "${src}/" "${dst}/"
    done < <(_config_list 'openclaw.agents')

    echo ""
    echo "Done. Review changes:"
    echo "  cd ${AGENTS_REPO} && git diff"
  else
    _require_tool rsync

    local config_dir="${BOTCTL_DIR}/config"

    echo "    openclaw.json -> ${config_dir}/"
    cp "${ceph_config}/openclaw.json" "${config_dir}/openclaw.json"

    if [[ -f "${ceph_config}/mcporter.json" ]]; then
      echo "    mcporter.json"
      cp "${ceph_config}/mcporter.json" "${config_dir}/mcporter.json"
    fi

    local agent
    while IFS= read -r agent; do
      [[ -n "${agent}" ]] || continue
      local src="${CEPH_BASE}/workspaces/${agent}"
      local dst="${config_dir}/workspace"
      [[ -d "${src}" ]] || continue
      echo "    workspaces/${agent}/*.md -> config/workspace/"
      mkdir -p "${dst}"
      rsync -a --include="*.md" --exclude="*" "${src}/" "${dst}/"
    done < <(_config_list 'openclaw.agents')

    echo ""
    echo "Done. Review changes:"
    echo "  cd ${BOTCTL_DIR} && git diff"
  fi
}
