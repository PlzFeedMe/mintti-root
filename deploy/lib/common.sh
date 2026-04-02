#!/usr/bin/env bash

set -euo pipefail

COMMON_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT_DIR=$(cd "$COMMON_DIR/../.." && pwd)
INVENTORY_DIR="$ROOT_DIR/deploy/inventory/hosts"
TEMPLATE_DIR="$ROOT_DIR/deploy/inventory/templates"
DEPLOY_CONFIG_FILE="$ROOT_DIR/deploy.config.env"

log() {
  printf '[mintti-deploy] %s\n' "$*"
}

fail() {
  printf '[mintti-deploy] ERROR: %s\n' "$*" >&2
  exit 1
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || fail "Required command not found: $1"
}

require_root_layout() {
  [[ -f "$ROOT_DIR/docker-compose.yaml" ]] || fail "Run this script from the Mintti root repository."
}

load_root_config() {
  if [[ -n "${MINTTI_DEPLOY_ROOT_CONFIG_LOADED:-}" ]]; then
    return
  fi

  [[ -f "$DEPLOY_CONFIG_FILE" ]] || fail "Missing root deployment config: $DEPLOY_CONFIG_FILE"

  set -a
  # shellcheck disable=SC1090
  source "$DEPLOY_CONFIG_FILE"
  set +a

  MINTTI_DEPLOY_ROOT_CONFIG_LOADED=1
}

load_host_config() {
  local host_alias=$1

  load_root_config

  HOST_ALIAS="$host_alias"
  HOST_ENV_FILE="$INVENTORY_DIR/$host_alias.env"

  [[ -f "$HOST_ENV_FILE" ]] || fail "Missing host inventory file: $HOST_ENV_FILE"

  set -a
  # shellcheck disable=SC1090
  source "$HOST_ENV_FILE"
  set +a

  [[ -n "${DEPLOY_HOST:-}" ]] || fail "DEPLOY_HOST is required in $HOST_ENV_FILE"
  [[ -n "${DEPLOY_SSH_TARGET:-}" ]] || fail "DEPLOY_SSH_TARGET is required in $HOST_ENV_FILE"
  [[ -n "${DEPLOY_ROLE:-}" ]] || fail "DEPLOY_ROLE is required in $HOST_ENV_FILE"
  [[ -n "${DEPLOY_ROOT:-}" ]] || fail "DEPLOY_ROOT is required in $HOST_ENV_FILE"
  [[ -n "${DEPLOY_STACK_NAME:-}" ]] || fail "DEPLOY_STACK_NAME is required in $HOST_ENV_FILE"
}

has_runtime_stack() {
  [[ -n "${DEPLOY_COMPOSE_FILE:-}" ]]
}

ensure_runtime_stack() {
  has_runtime_stack || fail "Host $DEPLOY_HOST is control-only and has no DEPLOY_COMPOSE_FILE"
}

remote_repo_url() {
  git -C "$ROOT_DIR" remote get-url origin
}

remote_rendered_dir() {
  printf '%s' "$DEPLOY_ROOT/deploy/rendered/$DEPLOY_HOST"
}

remote_rendered_compose_file() {
  printf '%s/stack.compose.yaml' "$(remote_rendered_dir)"
}

ssh_run() {
  local command=$1
  ssh "$DEPLOY_SSH_TARGET" "bash -lc $(printf '%q' "$command")"
}

upload_host_inventory() {
  ssh_run "mkdir -p '$DEPLOY_ROOT/deploy/inventory/hosts'"
  ssh "$DEPLOY_SSH_TARGET" "cat > '$DEPLOY_ROOT/deploy/inventory/hosts/$DEPLOY_HOST.env'" < "$HOST_ENV_FILE"
}

ensure_remote_root_repo() {
  local repo_url
  repo_url=$(remote_repo_url)

  ssh_run "mkdir -p '$(dirname "$DEPLOY_ROOT")'"

  if ssh_run "test -d '$DEPLOY_ROOT/.git'"; then
    log "Remote root repo already exists on $DEPLOY_SSH_TARGET"
    return
  fi

  log "Cloning root repo to $DEPLOY_SSH_TARGET:$DEPLOY_ROOT"
  ssh_run "git clone '$repo_url' '$DEPLOY_ROOT'"
}

sync_remote_root_repo() {
  ssh_run "cd '$DEPLOY_ROOT' && git fetch --all --prune"

  if ssh_run "cd '$DEPLOY_ROOT' && [[ -n \"\$(git status --porcelain)\" ]]"; then
    log "Skipping root repo pull on $DEPLOY_SSH_TARGET because it has local changes"
    return
  fi

  if ssh_run "cd '$DEPLOY_ROOT' && [[ \"\$(git rev-parse --abbrev-ref HEAD)\" == 'HEAD' ]]"; then
    log "Skipping root repo pull on $DEPLOY_SSH_TARGET because it is in detached HEAD state"
    return
  fi

  if ! ssh_run "cd '$DEPLOY_ROOT' && git rev-parse --abbrev-ref --symbolic-full-name '@{u}' >/dev/null 2>&1"; then
    log "Skipping root repo pull on $DEPLOY_SSH_TARGET because the current branch has no upstream"
    return
  fi

  ssh_run "cd '$DEPLOY_ROOT' && git pull --ff-only"
}

run_remote_bootstrap() {
  log "Running bootstrap-repos.sh on $DEPLOY_SSH_TARGET"
  ssh_run "cd '$DEPLOY_ROOT' && INSTALL_GH=0 GH_AUTH_MODE=fail bash ./bootstrap-repos.sh"
}

render_remote_compose() {
  ensure_runtime_stack
  ssh_run "mkdir -p '$(remote_rendered_dir)'"
  ssh_run "cd '$DEPLOY_ROOT' && docker compose --env-file 'deploy/inventory/hosts/$DEPLOY_HOST.env' -f '$DEPLOY_COMPOSE_FILE' config > 'deploy/rendered/$DEPLOY_HOST/stack.compose.yaml'"
}