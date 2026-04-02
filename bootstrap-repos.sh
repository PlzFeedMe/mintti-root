#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
GITHUB_OWNER=${GITHUB_OWNER:-PlzFeedMe}
INSTALL_GH=${INSTALL_GH:-1}

REPO_FOLDERS=(
  "mintti-background"
  "mintti-COD-db"
  "mintti-design"
  "mintti-frontend-backend"
  "mintti-peaks"
  "mintti-project-db"
  "mintti-report-builder"
  "mintti-rietveld"
  "mintti-search-match"
)

REPO_SLUGS=(
  "mintti-background"
  "Mintti-COD-DB"
  "mintti-design"
  "mintti-frontend-backend"
  "mintti-peaks"
  "mintti-project-db"
  "mintti-report-builder"
  "mintti-rietveld"
  "mintti-search-match"
)

log() {
  printf '[mintti-bootstrap] %s\n' "$*"
}

fail() {
  printf '[mintti-bootstrap] ERROR: %s\n' "$*" >&2
  exit 1
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || fail "Required command not found: $1"
}

require_root_layout() {
  if [[ ! -f "$ROOT_DIR/docker-compose.yaml" ]]; then
    fail "Run this script from the Mintti root repository. Expected docker-compose.yaml in $ROOT_DIR"
  fi
}

install_gh_cli() {
  if command -v gh >/dev/null 2>&1; then
    return
  fi

  if [[ "$INSTALL_GH" != "1" ]]; then
    fail "GitHub CLI is not installed. Install it first or rerun with INSTALL_GH=1 on Ubuntu/Debian."
  fi

  if ! command -v apt-get >/dev/null 2>&1; then
    fail "GitHub CLI is not installed and automatic installation only supports Ubuntu/Debian. Install gh manually and rerun."
  fi

  if ! command -v sudo >/dev/null 2>&1; then
    fail "GitHub CLI is not installed and sudo is unavailable. Install gh manually and rerun."
  fi

  log "Installing GitHub CLI with apt-get"
  sudo apt-get update
  sudo apt-get install -y gh
}

ensure_gh_auth() {
  if gh auth status >/dev/null 2>&1; then
    return
  fi

  log "GitHub CLI is not authenticated. Starting interactive login."
  gh auth login
}

clone_or_update_repo() {
  local folder=$1
  local slug=$2
  local target="$ROOT_DIR/$folder"
  local repo_ref="$GITHUB_OWNER/$slug"

  if [[ ! -e "$target" ]]; then
    log "Cloning $repo_ref into $folder"
    gh repo clone "$repo_ref" "$target"
    return
  fi

  if [[ ! -d "$target/.git" ]]; then
    fail "Path exists but is not a git repository: $target"
  fi

  log "Fetching latest refs for $folder"
  git -C "$target" fetch --all --prune

  if [[ -n "$(git -C "$target" status --porcelain)" ]]; then
    log "Skipping pull for $folder because it has local changes"
    return
  fi

  if ! git -C "$target" rev-parse --abbrev-ref HEAD >/dev/null 2>&1; then
    log "Skipping pull for $folder because the repository state is not readable"
    return
  fi

  if [[ "$(git -C "$target" rev-parse --abbrev-ref HEAD)" == "HEAD" ]]; then
    log "Skipping pull for $folder because it is in detached HEAD state"
    return
  fi

  if ! git -C "$target" rev-parse --abbrev-ref --symbolic-full-name '@{u}' >/dev/null 2>&1; then
    log "Skipping pull for $folder because the current branch has no upstream"
    return
  fi

  log "Fast-forwarding $folder"
  git -C "$target" pull --ff-only
}

copy_if_missing() {
  local source=$1
  local target=$2

  if [[ -f "$target" ]]; then
    return
  fi

  if [[ -f "$source" ]]; then
    cp "$source" "$target"
    log "Created $(realpath --relative-to="$ROOT_DIR" "$target" 2>/dev/null || printf '%s' "$target") from template"
  fi
}

create_cod_env_fallback() {
  local target="$ROOT_DIR/mintti-COD-db/.env"

  if [[ -f "$target" ]]; then
    return
  fi

  cat > "$target" <<'EOF'
DB_NAME=coddb
DB_USER=coddbuser
DB_PASSWORD=coddbpassword
DB_HOST=localhost
DB_PORT=5432

COD_CIFS_PATH=/cod-cifs
COD_METADATA_PATH=/cod-metadata
METADATA_LOAD_MODE=replace
EOF
  log "Created mintti-COD-db/.env from built-in defaults"
}

scaffold_env_files() {
  copy_if_missing "$ROOT_DIR/.env.example" "$ROOT_DIR/.env"

  if [[ -d "$ROOT_DIR/mintti-COD-db" ]]; then
    copy_if_missing "$ROOT_DIR/mintti-COD-db/.env.example" "$ROOT_DIR/mintti-COD-db/.env"
    create_cod_env_fallback
  fi
}

main() {
  require_root_layout
  require_command git
  install_gh_cli
  ensure_gh_auth

  for index in "${!REPO_FOLDERS[@]}"; do
    clone_or_update_repo "${REPO_FOLDERS[$index]}" "${REPO_SLUGS[$index]}"
  done

  scaffold_env_files

  log "Bootstrap complete. Review env files, then run: docker compose up --build"
}

main "$@"