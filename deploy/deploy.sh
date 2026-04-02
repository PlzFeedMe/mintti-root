#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/common.sh"

usage() {
  cat <<'EOF'
Usage:
  ./deploy/deploy.sh bootstrap-host <host>
  ./deploy/deploy.sh sync-repos <host>
  ./deploy/deploy.sh render-config <host>
  ./deploy/deploy.sh deploy-stack <host>
  ./deploy/deploy.sh status-stack <host>
  ./deploy/deploy.sh stop-stack <host>
  ./deploy/deploy.sh bootstrap-customer-vm <host> <customer-slug>

Examples:
  ./deploy/deploy.sh bootstrap-host control
  ./deploy/deploy.sh deploy-stack shared
  ./deploy/deploy.sh bootstrap-customer-vm customer-acme acme
EOF
}

bootstrap_host() {
  local host_alias=$1

  load_host_config "$host_alias"
  ensure_remote_root_repo
  sync_remote_root_repo
  upload_host_inventory
  run_remote_bootstrap
}

sync_repos() {
  local host_alias=$1

  load_host_config "$host_alias"
  ensure_remote_root_repo
  sync_remote_root_repo
  upload_host_inventory
  run_remote_bootstrap
}

render_config() {
  local host_alias=$1

  load_host_config "$host_alias"
  ensure_remote_root_repo
  upload_host_inventory
  render_remote_compose
  log "Rendered compose file on $DEPLOY_SSH_TARGET: $(remote_rendered_compose_file)"
}

deploy_stack() {
  local host_alias=$1

  load_host_config "$host_alias"
  ensure_remote_root_repo
  upload_host_inventory
  render_remote_compose
  ssh_run "cd '$DEPLOY_ROOT' && docker compose -p '$DEPLOY_STACK_NAME' -f 'deploy/rendered/$DEPLOY_HOST/stack.compose.yaml' up -d --build"
}

status_stack() {
  local host_alias=$1

  load_host_config "$host_alias"
  ensure_runtime_stack
  ensure_remote_root_repo
  upload_host_inventory
  render_remote_compose
  ssh_run "cd '$DEPLOY_ROOT' && docker compose -p '$DEPLOY_STACK_NAME' -f 'deploy/rendered/$DEPLOY_HOST/stack.compose.yaml' ps"
}

stop_stack() {
  local host_alias=$1

  load_host_config "$host_alias"
  ensure_runtime_stack
  ensure_remote_root_repo
  upload_host_inventory
  render_remote_compose
  ssh_run "cd '$DEPLOY_ROOT' && docker compose -p '$DEPLOY_STACK_NAME' -f 'deploy/rendered/$DEPLOY_HOST/stack.compose.yaml' down"
}

bootstrap_customer_vm() {
  local host_alias=$1
  local customer_slug=$2
  local target_file="$INVENTORY_DIR/$host_alias.env"

  [[ -f "$target_file" ]] && fail "Inventory file already exists: $target_file"
  [[ -f "$TEMPLATE_DIR/timo-customer.env.example" ]] || fail "Missing template: $TEMPLATE_DIR/timo-customer.env.example"

  sed \
    -e "s/__HOST__/$host_alias/g" \
    -e "s/__CUSTOMER__/$customer_slug/g" \
    "$TEMPLATE_DIR/timo-customer.env.example" > "$target_file"

  log "Created $target_file"
  log "Review host-local values and deploy.config.env before running bootstrap-host."
}

main() {
  local command=${1:-}

  require_root_layout
  require_command git
  require_command ssh
  require_command sed

  case "$command" in
    bootstrap-host)
      [[ $# -eq 2 ]] || { usage; exit 1; }
      bootstrap_host "$2"
      ;;
    sync-repos)
      [[ $# -eq 2 ]] || { usage; exit 1; }
      sync_repos "$2"
      ;;
    render-config)
      [[ $# -eq 2 ]] || { usage; exit 1; }
      render_config "$2"
      ;;
    deploy-stack)
      [[ $# -eq 2 ]] || { usage; exit 1; }
      deploy_stack "$2"
      ;;
    status-stack)
      [[ $# -eq 2 ]] || { usage; exit 1; }
      status_stack "$2"
      ;;
    stop-stack)
      [[ $# -eq 2 ]] || { usage; exit 1; }
      stop_stack "$2"
      ;;
    bootstrap-customer-vm)
      [[ $# -eq 3 ]] || { usage; exit 1; }
      bootstrap_customer_vm "$2" "$3"
      ;;
    *)
      usage
      exit 1
      ;;
  esac
}

main "$@"