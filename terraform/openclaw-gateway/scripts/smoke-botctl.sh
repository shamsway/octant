#!/usr/bin/env bash
set -euo pipefail

# smoke-botctl.sh - lightweight botctl smoke tests using command stubs
#
# Validates:
#   - target selection defaults and help output
#   - nomad vs local command routing
#   - unsupported command errors for local targets
#   - local config deploy file mapping
#   - image deploy / build command construction
#   - clear dependency error when jq is missing for nomad alloc lookup

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODULE_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
TMP_DIR="$(mktemp -d)"
STUB_DIR="${TMP_DIR}/stubs"
NOJQ_STUB_DIR="${TMP_DIR}/stubs-nojq"
TFVARS_FILE="${MODULE_DIR}/image.auto.tfvars"
SMOKE_AGENTS_REPO="${TMP_DIR}/openclaw-agents"
SMOKE_LOCAL_CONFIG_DIR="${TMP_DIR}/local-openclaw"

cleanup() {
  rm -rf "${TMP_DIR}"
  rm -f "${TFVARS_FILE}"
}
trap cleanup EXIT INT TERM

mkdir -p "${STUB_DIR}" "${NOJQ_STUB_DIR}" \
  "${SMOKE_AGENTS_REPO}/harry/workspace" \
  "${SMOKE_AGENTS_REPO}/bob/workspace"

cat > "${SMOKE_AGENTS_REPO}/harry/openclaw.json" <<'EOF'
{"name":"harry"}
EOF
cat > "${SMOKE_AGENTS_REPO}/harry/mcporter.json" <<'EOF'
{"mcp":true}
EOF
cat > "${SMOKE_AGENTS_REPO}/harry/workspace/SOUL.md" <<'EOF'
Harry soul
EOF
cat > "${SMOKE_AGENTS_REPO}/bob/workspace/TOOLS.md" <<'EOF'
Bob tools
EOF

cat > "${STUB_DIR}/yq" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
mode="${1:-}"
expr="${2:-}"
target="${BOTCTL_ACTIVE_TARGET:-${BOTCTL_LOOKUP_TARGET:-${BOTCTL_TARGET:-homelab}}}"

emit_target_field() {
  local field="$1"
  case "${target}:${field}" in
    homelab:driver) echo "nomad" ;;
    homelab:openclaw.nomad_job) echo "openclaw-gateway" ;;
    homelab:openclaw.image.name) echo "openclaw-homelab" ;;
    homelab:openclaw.image.registry) echo "registry.service.consul:8082" ;;
    homelab:openclaw.image.version) echo "2026.2.24-smoke" ;;
    homelab:openclaw.source_repo) echo "${SMOKE_SOURCE_REPO:-/tmp/openclaw-src}" ;;
    homelab:storage.agents_repo) echo "${SMOKE_AGENTS_REPO}" ;;
    homelab:storage.ceph_base) echo "${SMOKE_CEPH_BASE:-/tmp/openclaw-ceph}" ;;
    homelab:openclaw.compose.base) echo "compose/docker-compose.yml" ;;
    homelab:openclaw.compose.podman) echo "compose/docker-compose.podman.yml" ;;
    homelab:openclaw.compose.remote_nodes) echo "compose/docker-compose.remote-nodes.yml" ;;
    homelab:openclaw.github_url) echo "https://github.com/openclaw/openclaw" ;;
    homelab:openclaw.github_ref) echo "main" ;;
    homelab:openclaw.agents) printf 'jerry\nbobby\nbilly\n' ;;
    homelab:openclaw.nodes) printf 'bobby\nbilly\n' ;;
    workstation:driver) echo "local" ;;
    workstation:openclaw.image.name) echo "openclaw-homelab" ;;
    workstation:openclaw.image.registry) echo "registry.service.consul:8082" ;;
    workstation:openclaw.image.version) echo "2026.2.24-smoke" ;;
    workstation:openclaw.source_repo) echo "${SMOKE_SOURCE_REPO:-}" ;;
    workstation:storage.agents_repo) echo "${SMOKE_AGENTS_REPO}" ;;
    workstation:openclaw.github_url) echo "https://github.com/openclaw/openclaw" ;;
    workstation:openclaw.github_ref) echo "main" ;;
    workstation:openclaw.agents) printf 'harry\nbob\n' ;;
    workstation:openclaw.gateway.primary_agent) echo "harry" ;;
    workstation:openclaw.gateway.config_dir) echo "${SMOKE_LOCAL_CONFIG_DIR}" ;;
    workstation:openclaw.gateway.workspace_root) echo "${SMOKE_LOCAL_CONFIG_DIR}" ;;
    workstation:openclaw.gateway.health_url) echo "http://127.0.0.1:18789/health" ;;
    workstation:openclaw.gateway.log_file) echo "${SMOKE_LOCAL_CONFIG_DIR}/logs/gateway.log" ;;
    workstation:openclaw.gateway.cli_bin) echo "openclaw" ;;
    workstation:openclaw.gateway.restart.mode) echo "manual" ;;
    workstation:openclaw.gateway.restart.message) echo "Restart locally." ;;
    workstation:openclaw.nodes) printf '\n' ;;
    *) echo "null" ;;
  esac
}

case "${mode}:${expr}" in
  e:.targets\ \|\ keys\ \|\ .\[\]) printf 'homelab\nworkstation\n' ;;
  e:.defaults.target\ //\ \"\") echo "homelab" ;;
  e:.targets\[env\(BOTCTL_LOOKUP_TARGET\)\]\ \|\ tag)
    if [[ "${BOTCTL_LOOKUP_TARGET:-}" == "homelab" || "${BOTCTL_LOOKUP_TARGET:-}" == "workstation" ]]; then
      echo "!!map"
    else
      echo "!!null"
    fi
    ;;
  e:.driver) emit_target_field "driver" ;;
  e:.openclaw.nomad_job) emit_target_field "openclaw.nomad_job" ;;
  e:.openclaw.image.name) emit_target_field "openclaw.image.name" ;;
  e:.openclaw.image.registry) emit_target_field "openclaw.image.registry" ;;
  e:.openclaw.image.version) emit_target_field "openclaw.image.version" ;;
  e:.openclaw.source_repo) emit_target_field "openclaw.source_repo" ;;
  e:.storage.agents_repo) emit_target_field "storage.agents_repo" ;;
  e:.storage.ceph_base) emit_target_field "storage.ceph_base" ;;
  e:.openclaw.compose.base) emit_target_field "openclaw.compose.base" ;;
  e:.openclaw.compose.podman) emit_target_field "openclaw.compose.podman" ;;
  e:.openclaw.compose.remote_nodes) emit_target_field "openclaw.compose.remote_nodes" ;;
  e:.openclaw.github_url) emit_target_field "openclaw.github_url" ;;
  e:.openclaw.github_ref) emit_target_field "openclaw.github_ref" ;;
  e:.openclaw.gateway.primary_agent) emit_target_field "openclaw.gateway.primary_agent" ;;
  e:.openclaw.gateway.config_dir) emit_target_field "openclaw.gateway.config_dir" ;;
  e:.openclaw.gateway.workspace_root) emit_target_field "openclaw.gateway.workspace_root" ;;
  e:.openclaw.gateway.health_url) emit_target_field "openclaw.gateway.health_url" ;;
  e:.openclaw.gateway.log_file) emit_target_field "openclaw.gateway.log_file" ;;
  e:.openclaw.gateway.cli_bin) emit_target_field "openclaw.gateway.cli_bin" ;;
  e:.openclaw.gateway.restart.mode) emit_target_field "openclaw.gateway.restart.mode" ;;
  e:.openclaw.gateway.restart.message) emit_target_field "openclaw.gateway.restart.message" ;;
  e:.openclaw.agents\[\]\?) emit_target_field "openclaw.agents" ;;
  e:.openclaw.nodes\[\].name\ //\ \"\") emit_target_field "openclaw.nodes" ;;
  e:*targets\[env\(BOTCTL_ACTIVE_TARGET\)\]*) echo "driver: ${target}" ;;
  ea:*targets\[env\(BOTCTL_ACTIVE_TARGET\)\]*) echo "driver: ${target}" ;;
  *) echo "null" ;;
esac
EOF

cat > "${STUB_DIR}/nomad" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${1:-}" == "job" && "${2:-}" == "allocs" && "${3:-}" == "-json" ]]; then
  echo '[{"ID":"alloc-smoke-123","ClientStatus":"running"}]'
  exit 0
fi
echo "NOMAD $*"
EOF

cat > "${STUB_DIR}/jq" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
input="$(cat)"
filter="${1:-}"
if [[ "${filter}" == *".version"* ]]; then
  echo "${input}" | grep -o '"version":"[^"]*"' | cut -d'"' -f4 || true
  exit 0
fi
if [[ "${filter}" == *".[] | select(.ClientStatus == \"running\")"* ]]; then
  echo "alloc-smoke-123"
  exit 0
fi
if [[ "${filter}" == "." ]]; then
  printf '%s\n' "${input}"
  exit 0
fi
if [[ "${filter}" == "-e" ]]; then
  printf '%s\n' "${input}" >/dev/null
  exit 0
fi
if [[ "${filter}" == "-r" ]]; then
  shift
  filter="${1:-}"
fi
case "${filter}" in
  *status*) echo "ok" ;;
  *channels*) echo "2" ;;
  *agents*) echo "2" ;;
  *sessions*) echo "3" ;;
  *) printf '%s\n' "${input}" ;;
esac
EOF

cat > "${STUB_DIR}/podman-compose" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
echo "PODMAN-COMPOSE $*"
EOF

cat > "${STUB_DIR}/podman" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
echo "PODMAN: $*"
EOF

cat > "${STUB_DIR}/terraform" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
echo "TERRAFORM: $*"
EOF

cat > "${STUB_DIR}/curl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
for arg in "$@"; do
  if [[ "${arg}" == *"raw.githubusercontent.com"* ]]; then
    echo '{"version":"2026.2.24-smoke"}'
    exit 0
  fi
done
echo '{"status":"ok","health":"green"}'
EOF

cat > "${STUB_DIR}/openclaw" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${1:-}" == "--config-dir" ]]; then
  shift 2
fi
if [[ "${1:-}" == "gateway" && "${2:-}" == "status" && "${3:-}" == "--json" ]]; then
  echo '{"status":"ok","channels":["discord","slack"],"agents":["harry","bob"],"sessions":["a","b","c"]}'
  exit 0
fi
echo "OPENCLAW $*"
EOF

chmod +x "${STUB_DIR}/yq" "${STUB_DIR}/nomad" "${STUB_DIR}/jq" \
  "${STUB_DIR}/podman-compose" "${STUB_DIR}/podman" "${STUB_DIR}/terraform" \
  "${STUB_DIR}/curl" "${STUB_DIR}/openclaw"

cp "${STUB_DIR}/yq" "${NOJQ_STUB_DIR}/yq"
cp "${STUB_DIR}/nomad" "${NOJQ_STUB_DIR}/nomad"
cp "${STUB_DIR}/podman-compose" "${NOJQ_STUB_DIR}/podman-compose"
chmod +x "${NOJQ_STUB_DIR}/yq" "${NOJQ_STUB_DIR}/nomad" "${NOJQ_STUB_DIR}/podman-compose"
for tool in dirname cat mkdir rm tr basename mktemp cp; do
  if [[ -x "/usr/bin/${tool}" ]]; then
    ln -sf "/usr/bin/${tool}" "${NOJQ_STUB_DIR}/${tool}"
  fi
done

pass() { printf 'PASS: %s\n' "$1"; }
fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }
assert_contains() {
  local haystack="$1"
  local needle="$2"
  local label="$3"
  [[ "${haystack}" == *"${needle}"* ]] && pass "${label}" || {
    printf 'Output:\n%s\n' "${haystack}" >&2
    fail "${label} (missing: ${needle})"
  }
}

BASE_PATH="/usr/bin:/bin:/usr/sbin:/sbin"
TEST_PATH="${STUB_DIR}:${BASE_PATH}"
TEST_PATH_NOJQ="${NOJQ_STUB_DIR}:/bin:/usr/sbin:/sbin"

run_botctl() {
  PATH="${TEST_PATH}" SMOKE_AGENTS_REPO="${SMOKE_AGENTS_REPO}" \
    SMOKE_LOCAL_CONFIG_DIR="${SMOKE_LOCAL_CONFIG_DIR}" "$@"
}

run_botctl_nojq() {
  PATH="${TEST_PATH_NOJQ}" SMOKE_AGENTS_REPO="${SMOKE_AGENTS_REPO}" \
    SMOKE_LOCAL_CONFIG_DIR="${SMOKE_LOCAL_CONFIG_DIR}" "$@"
}

printf 'Running botctl smoke tests in %s\n\n' "${MODULE_DIR}"

# 1) Help uses defaults.target and reports the selected driver.
out="$(run_botctl "${MODULE_DIR}/botctl" help 2>&1)"
assert_contains "${out}" "Usage: botctl [--target <name>] <noun> <verb> [args...]" "target-aware usage text"
assert_contains "${out}" "Selected target: homelab" "help shows default target"
assert_contains "${out}" "Selection source: defaults.target" "help shows target selection source"

# 2) Nomad gateway status still routes through Nomad.
out="$(run_botctl "${MODULE_DIR}/botctl" gateway status 2>&1)"
assert_contains "${out}" "==> Nomad job: openclaw-gateway" "gateway status reaches nomad handler"
assert_contains "${out}" "NOMAD job status openclaw-gateway" "gateway status invokes nomad"

# 3) Local gateway status uses the local adapter and health URL.
out="$(run_botctl "${MODULE_DIR}/botctl" --target workstation gateway status 2>&1)"
assert_contains "${out}" "Driver: local" "local gateway status identifies driver"
assert_contains "${out}" "Status: ok" "local gateway status summarizes CLI output"
assert_contains "${out}" "Health source: HTTP (http://127.0.0.1:18789/health)" "local gateway status appends health check"

# 4) Local node commands fail explicitly.
set +e
out="$(run_botctl "${MODULE_DIR}/botctl" --target workstation node status 2>&1)"
rc=$?
set -e
[[ ${rc} -ne 0 ]] || fail "local node status exits non-zero"
assert_contains "${out}" "'botctl node status' is not supported for target 'workstation' (driver=local)." "local node status unsupported message"

# 5) Local config deploy maps primary and secondary workspaces correctly.
rm -rf "${SMOKE_LOCAL_CONFIG_DIR}"
out="$(run_botctl "${MODULE_DIR}/botctl" --target workstation config deploy 2>&1)"
assert_contains "${out}" "config deploy (workstation): ${SMOKE_AGENTS_REPO} -> ${SMOKE_LOCAL_CONFIG_DIR}" "local config deploy banner"
[[ -f "${SMOKE_LOCAL_CONFIG_DIR}/openclaw.json" ]] || fail "local config deploy copied openclaw.json"
[[ -f "${SMOKE_LOCAL_CONFIG_DIR}/workspace/SOUL.md" ]] || fail "local config deploy copied primary workspace"
[[ -f "${SMOKE_LOCAL_CONFIG_DIR}/workspace-bob/TOOLS.md" ]] || fail "local config deploy copied secondary workspace"
pass "local config deploy copied expected files"

# 6) Missing target produces a clear error.
set +e
out="$(run_botctl "${MODULE_DIR}/botctl" --target does-not-exist help 2>&1)"
rc=$?
set -e
[[ ${rc} -ne 0 ]] || fail "missing target exits non-zero"
assert_contains "${out}" "error: requested target 'does-not-exist' was not found." "missing target error message"

# 7) image deploy writes image.auto.tfvars with correct image and calls terraform.
rm -f "${TFVARS_FILE}"
out="$(BOTCTL_IMAGE_VERSION="2026.2.24-smoke" run_botctl "${MODULE_DIR}/botctl" \
  image deploy --skip-build --skip-push --auto-approve 2>&1)"
assert_contains "${out}" "==> image deploy: registry.service.consul:8082/openclaw-homelab:2026.2.24-smoke" "image deploy shows target image"
assert_contains "${out}" "TERRAFORM: apply -auto-approve" "image deploy calls terraform apply"
[[ -f "${TFVARS_FILE}" ]] || fail "image deploy: image.auto.tfvars not written"
tfvars_content="$(cat "${TFVARS_FILE}")"
assert_contains "${tfvars_content}" 'image = "registry.service.consul:8082/openclaw-homelab:2026.2.24-smoke"' "image deploy tfvars content correct"
rm -f "${TFVARS_FILE}"

# 8) image deploy is explicitly unsupported for local targets.
set +e
out="$(run_botctl "${MODULE_DIR}/botctl" --target workstation image deploy 2>&1)"
rc=$?
set -e
[[ ${rc} -ne 0 ]] || fail "local image deploy exits non-zero"
assert_contains "${out}" "'botctl image deploy' is not supported for target 'workstation' (driver=local)." "local image deploy unsupported message"

# 9) image build --base-only uses GitHub URL as context when source_repo is absent.
out="$(BOTCTL_IMAGE_VERSION="2026.2.24-smoke" BOTCTL_SOURCE_REPO="" \
  run_botctl "${MODULE_DIR}/botctl" image build --base-only 2>&1)"
assert_contains "${out}" "Context    : https://github.com/openclaw/openclaw.git#main" "image build --base-only uses GitHub URL context"
assert_contains "${out}" "PODMAN: build -t openclaw-base:2026.2.24-smoke" "image build --base-only invokes podman"

# 10) missing jq produces explicit dependency error on gateway logs.
set +e
out="$(run_botctl_nojq "${MODULE_DIR}/botctl" gateway logs 2>&1)"
rc=$?
set -e
[[ ${rc} -ne 0 ]] || fail "missing jq exits non-zero"
assert_contains "${out}" "error: 'jq' is required but not found in PATH." "jq dependency guard"

printf '\nAll botctl smoke tests passed.\n'
