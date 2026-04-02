# Mintti Compose Scaffold

This workspace-level scaffold models one container per repo, excluding `mintti-design`.

The root repository expects the child repositories to live beside it as sibling directories.

## Services

- `mintti-background`
- `mintti-cod-db`
- `mintti-frontend-backend`
- `mintti-peaks`
- `mintti-project-db`
- `mintti-report-builder`
- `mintti-rietveld`
- `mintti-search-match`

`mintti-cod-postgres` is an internal dependency for `mintti-cod-db`, not a repo container.

## Remote Bootstrap

On a Linux remote server, clone the root repository first and then run the bootstrap script from the root.

```bash
bash ./bootstrap-repos.sh
```

The bootstrap script does the following:

- installs GitHub CLI on Ubuntu/Debian if `gh` is missing and `sudo` is available
- starts `gh auth login` interactively if GitHub CLI is not authenticated yet
- clones missing child repositories into the exact directory names expected by `docker-compose.yaml`
- fetches and fast-forwards clean existing child repositories
- creates `.env` from `.env.example` if the root env file is missing
- creates `mintti-COD-db/.env` from `mintti-COD-db/.env.example` when available, or from built-in defaults otherwise

If the server cannot use `sudo` or is not Ubuntu/Debian, install GitHub CLI manually before running the script.

## Behavior

- Placeholder repos build a tiny Alpine image and stay idle with the repo bind-mounted at `/workspace`.
- `mintti-cod-db` builds a Python image with its loader dependencies installed and mounts the local COD assets into the container.
- `mintti-frontend-backend` starts the Vite dev server on port `3000`.

## Usage

From the workspace root:

```bash
docker compose up --build
```

To run the COD metadata loader inside its service container:

```bash
docker compose exec mintti-cod-db python load-metadata.py
```

To stop the stack:

```bash
docker compose down
```

## Notes

- Root-level port and database defaults are defined in `.env.example`.
- Repo-local loader settings live in `mintti-COD-db/.env`, with defaults committed in `mintti-COD-db/.env.example`.
- The frontend proxies API traffic to `http://mintti-background:8000`, which is currently just a reserved scaffold target until that repo gets an actual service implementation.
- `mintti-design` remains a separate sibling repository but is not part of the compose stack.