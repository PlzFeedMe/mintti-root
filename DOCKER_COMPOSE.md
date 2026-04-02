# Mintti Compose Scaffold

This workspace-level scaffold models one container per repo, excluding `mintti-design`.

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

## Behavior

- Placeholder repos build a tiny Alpine image and stay idle with the repo bind-mounted at `/workspace`.
- `mintti-cod-db` builds a Python image with its loader dependencies installed and mounts the local COD assets into the container.
- `mintti-frontend-backend` starts the Vite dev server on port `3000`.

## Usage

From the workspace root:

```powershell
docker compose up --build
```

To run the COD metadata loader inside its service container:

```powershell
docker compose exec mintti-cod-db python load-metadata.py
```

To stop the stack:

```powershell
docker compose down
```

## Notes

- Root-level port and database defaults are defined in `.env.example`.
- Repo-local loader settings still live in `mintti-COD-db/.env`.
- The frontend proxies API traffic to `http://mintti-background:8000`, which is currently just a reserved scaffold target until that repo gets an actual service implementation.