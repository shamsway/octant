#!/usr/bin/env bash
# lib/image.sh - botctl image noun handler and cli command
#
# Manages the two-stage image build: Dockerfile.base → Dockerfile.infra.
# See docs/IMAGE_STRATEGY.md for the rationale.
#
# build:   builds openclaw-base then openclaw-homelab (or --base-only)
# push:    tags and pushes openclaw-homelab to the registry
# pull:    pulls openclaw-homelab from the registry and tags it locally
# deploy:  build + push + write image.auto.tfvars + terraform apply
# cli:     launches an interactive container shell (not under 'image' noun;
#          called directly as 'botctl cli' from the dispatcher)

_BASE_IMAGE_NAME="openclaw-base"
_INFRA_DOCKERFILE="${BOTCTL_DIR}/image/Dockerfile.infra"
_BASE_DOCKERFILE="${BOTCTL_DIR}/image/Dockerfile.base"

cmd_image() {
  local verb="${1:-help}"
  shift || true
  case "${verb}" in
    build)  _image_build "$@" ;;
    push)   _image_push "$@" ;;
    pull)   _image_pull "$@" ;;
    deploy) _image_deploy "$@" ;;
    help|--help|-h) _botctl_help image ;;
    *)
      echo "error: unknown verb '${verb}' for 'botctl image'" >&2
      _botctl_help image >&2
      exit 1
      ;;
  esac
}

_image_build() {
  local base_only=false
  while [[ "${1:-}" == --* ]]; do
    case "$1" in
      --base-only) base_only=true; shift ;;
      *) echo "error: unknown flag '$1'" >&2; exit 1 ;;
    esac
  done

  _require_tool podman
  _require_build_context

  local tag
  tag="$(_resolve_image_tag)"
  local base_tag="${_BASE_IMAGE_NAME}:${tag}"
  local infra_tag="${IMAGE_NAME}:${tag}"
  local ctx
  ctx="$(_resolve_build_context)"

  echo "==> Building base image: ${base_tag}"
  echo "    Dockerfile : ${_BASE_DOCKERFILE}"
  echo "    Context    : ${ctx}"
  podman build \
    -t "${base_tag}" \
    -f "${_BASE_DOCKERFILE}" \
    "${ctx}" "$@"

  if [[ "${base_only}" == true ]]; then
    echo ""
    echo "Done (base only). Base image: ${base_tag}"
    return
  fi

  echo ""
  echo "==> Building infra image: ${infra_tag}"
  echo "    Dockerfile : ${_INFRA_DOCKERFILE}"
  echo "    Base image : ${base_tag}"
  podman build \
    -t "${infra_tag}" \
    -f "${_INFRA_DOCKERFILE}" \
    --build-arg "BASE_IMAGE=${base_tag}" \
    "${ctx}"

  echo ""
  echo "Done."
  echo "  Base  : ${base_tag}"
  echo "  Infra : ${infra_tag}"
  echo ""
  echo "Next: botctl image push"
}

_image_push() {
  _require_tool podman
  local local_tag
  local_tag="$(_resolve_local_image)"
  local remote_tag
  remote_tag="$(_resolve_registry_image "${local_tag}")"

  echo "==> Tagging ${local_tag} → ${remote_tag}"
  podman tag "${local_tag}" "${remote_tag}"
  echo "==> Pushing ${remote_tag} (--tls-verify=false)"
  podman push --tls-verify=false "${remote_tag}" "$@"
}

_image_pull() {
  _require_tool podman
  local local_tag
  local_tag="$(_resolve_local_image)"
  local remote_tag
  remote_tag="$(_resolve_registry_image "${local_tag}")"

  echo "==> Pulling ${remote_tag} (--tls-verify=false)"
  podman pull --tls-verify=false "${remote_tag}" "$@"
  echo "==> Tagging ${remote_tag} → ${local_tag}"
  podman tag "${remote_tag}" "${local_tag}"
}

# _image_deploy - build + push + update image.auto.tfvars + terraform apply
#
# Flags:
#   --skip-build    Skip the image build step (image must already exist locally)
#   --skip-push     Skip the registry push step
#   --auto-approve  Pass -auto-approve to terraform apply (non-interactive)
#
# Writes image.auto.tfvars (gitignored) so terraform uses the new image for
# all jobs (gateway + remote nodes) without modifying variables.tf.
_image_deploy() {
  _require_driver nomad "botctl image deploy"

  local skip_build=false
  local skip_push=false
  local auto_approve=false

  while [[ "${1:-}" == --* ]]; do
    case "$1" in
      --skip-build)   skip_build=true;   shift ;;
      --skip-push)    skip_push=true;    shift ;;
      --auto-approve) auto_approve=true; shift ;;
      *) echo "error: unknown flag '$1'" >&2; exit 1 ;;
    esac
  done

  _require_tool terraform

  local registry_img
  registry_img="$(_resolve_registry_image)"

  echo "==> image deploy: ${registry_img}"
  echo ""

  if [[ "${skip_build}" == false ]]; then
    _image_build
    echo ""
  fi

  if [[ "${skip_push}" == false ]]; then
    _image_push
    echo ""
  fi

  # Write image.auto.tfvars — auto-loaded by Terraform, overrides var.image
  # for all jobs in this module (gateway + remote nodes).
  local tfvars="${BOTCTL_DIR}/image.auto.tfvars"
  echo "==> Writing image.auto.tfvars"
  printf 'image = "%s"\n' "${registry_img}" > "${tfvars}"
  echo "    image = ${registry_img}"
  echo ""

  # Init if needed (e.g. first run in a fresh checkout)
  if [[ ! -d "${BOTCTL_DIR}/.terraform" ]]; then
    echo "==> terraform init"
    (cd "${BOTCTL_DIR}" && terraform init)
    echo ""
  fi

  local tf_args=("apply")
  [[ "${auto_approve}" == true ]] && tf_args+=("-auto-approve")

  echo "==> terraform apply"
  (cd "${BOTCTL_DIR}" && terraform "${tf_args[@]}")

  echo ""
  echo "Deployed: ${registry_img}"
}

# cmd_cli - launch an interactive container shell
# Called as 'botctl cli', not under the image noun.
cmd_cli() {
  if [[ "${TARGET_DRIVER}" == "local" ]]; then
    if ! _cli_bin_exists "${LOCAL_CLI_BIN}"; then
      _die "local CLI binary '${LOCAL_CLI_BIN}' was not found." \
        "Set openclaw.gateway.cli_bin or install the OpenClaw CLI."
    fi
    local cmd=("${LOCAL_CLI_BIN}")
    cmd+=("$@")
    exec "${cmd[@]}"
  fi

  _require_tool podman
  local image
  image="$(_resolve_local_image)"

  # Config and workspace paths: use CephFS if available, else ~/.openclaw
  local config_dir workspace_dir
  if [[ -n "${CEPH_BASE:-}" ]]; then
    config_dir="${CEPH_BASE}/config"
    local cli_agent
    cli_agent="$(_config_list 'openclaw.agents' | head -1)"
    cli_agent="${cli_agent:-scotty}"
    workspace_dir="${CEPH_BASE}/workspaces/${cli_agent}"
  else
    config_dir="${OPENCLAW_CONFIG_DIR:-${HOME}/.openclaw}"
    workspace_dir="${OPENCLAW_WORKSPACE_DIR:-${HOME}/.openclaw/workspace}"
  fi
  mkdir -p "${config_dir}" "${workspace_dir}"

  # Write a temp rcfile that registers the openclaw alias and a clear prompt.
  local rc_file
  rc_file="$(mktemp /tmp/botctl-cli.XXXXXX)"
  # shellcheck disable=SC2064
  trap "rm -f '${rc_file}'" EXIT INT TERM
  cat > "${rc_file}" <<'RCEOF'
alias openclaw="node /app/openclaw.mjs"
echo "OpenClaw CLI  — run 'openclaw --help' to get started."
PS1="\[\033[0;36m\][openclaw]\[\033[0m\] \u@\h:\w\$ "
RCEOF

  echo "Image  : ${image}"
  echo "Config : ${config_dir}"

  podman run --rm -it \
    --init \
    --network host \
    --workdir /app \
    -e HOME=/home/node \
    -e TERM="${TERM:-xterm-256color}" \
    -v "${config_dir}:/home/node/.openclaw" \
    -v "${workspace_dir}:/home/node/.openclaw/workspace" \
    -v "${rc_file}:/etc/openclaw.bashrc:ro" \
    "${image}" \
    bash --rcfile /etc/openclaw.bashrc \
    "$@"
}
