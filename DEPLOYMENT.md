# Mintti Multi-Host Deployment

This repository now includes a phase-1 deployment scaffold for running Mintti across three server roles over Tailscale.

## Host Roles

- `ilmo-1`: control node only. It holds the root repository, deployment scripts, inventory, and `mintti-design`. No application containers should run here.
- `aimo-1`: shared heavy services and shared COD data services.
- `timo` customer VMs: one isolated application stack per customer VM.

## Deployment Model

- Use SSH from `ilmo-1` to each Tailscale VM.
- Clone the full repository set on every host if desired.
- Start only the services allowed for that host role.
- Keep host-local secrets out of git.
- Use Tailscale hostnames for internal service-to-service connectivity.
- Remote repo synchronization pulls from the configured git remote, so commits must be pushed before deployment.

## Repository Layout

- `deploy.config.env`: root-level host mapping for control, shared, and customer defaults.
- `deploy/deploy.sh`: central operator entrypoint.
- `deploy/lib/common.sh`: shared shell helpers.
- `deploy/compose/aimo-shared.compose.yaml`: shared services stack for `aimo-1`.
- `deploy/compose/customer-vm.compose.yaml`: tenant-local stack for each `timo` customer VM.
- `deploy/inventory/hosts/*.env.example`: tracked host inventory examples.
- `deploy/inventory/templates/timo-customer.env.example`: reusable customer VM template.

## Inventory Model

The deploy scaffold loads `deploy.config.env` first and then loads the selected host inventory file.

Each deployable host uses a host-local env file at `deploy/inventory/hosts/<host>.env`.

Required variables:

- `DEPLOY_HOST`: inventory alias.
- `DEPLOY_SSH_TARGET`: SSH target, usually the Tailscale hostname.
- `DEPLOY_ROLE`: `ilmo-control`, `aimo-shared`, or `timo-customer`.
- `DEPLOY_ROOT`: remote checkout path.
- `DEPLOY_COMPOSE_FILE`: role-based compose file path inside the repo.
- `DEPLOY_STACK_NAME`: compose project name.

Optional variables depend on the selected role. See the example files for the supported settings.

## Root Config

Edit `deploy.config.env` to map logical deployment targets to actual machines.

Supported defaults:

- `MINTTI_DEPLOY_CONTROL_SSH_TARGET`
- `MINTTI_DEPLOY_SHARED_SSH_TARGET`
- `MINTTI_DEPLOY_CUSTOMER_DEFAULT_SSH_TARGET`
- `MINTTI_SHARED_API_BASE_URL`
- `MINTTI_DEPLOY_DEFAULT_ROOT`

Recommended operating modes:

- Dev mode: point both control and shared to `ilmo-1`.
- Split-host mode: point control to `ilmo-1` and shared to `aimo-1`.

## Commands

Run all commands from the root repository on `ilmo-1`.

```bash
cp deploy/inventory/hosts/control.env.example deploy/inventory/hosts/control.env
cp deploy/inventory/hosts/shared.env.example deploy/inventory/hosts/shared.env
./deploy/deploy.sh bootstrap-host control
./deploy/deploy.sh bootstrap-host shared
./deploy/deploy.sh deploy-stack shared
./deploy/deploy.sh status-stack shared
```

For a new customer VM:

```bash
./deploy/deploy.sh bootstrap-customer-vm customer-vm-name customer-slug
./deploy/deploy.sh bootstrap-host customer-vm-name
./deploy/deploy.sh deploy-stack customer-vm-name
```

## Command Behavior

- `bootstrap-host`: clones or updates the root repo on the target host, uploads the inventory file, and runs `bootstrap-repos.sh` remotely.
- `sync-repos`: uploads the inventory file and re-runs repo synchronization remotely.
- `render-config`: renders a fully resolved compose file under `deploy/rendered/<host>/stack.compose.yaml` on the target host.
- `deploy-stack`: renders config and runs `docker compose up -d --build` for the selected host role.
- `status-stack`: runs `docker compose ps` for the selected host role.
- `stop-stack`: runs `docker compose down` for the selected host role.
- `bootstrap-customer-vm`: creates a new local inventory file from the reusable `timo` template.

## Preconditions

- SSH access from `ilmo-1` to each target host must already work.
- `git`, `docker`, and `docker compose` must be installed on target hosts.
- The root repo remote URL must be usable from the target hosts.
- `bootstrap-repos.sh` currently relies on GitHub CLI for child repo checkout, so target hosts should have `gh` installed and authenticated before non-interactive deployment.
- `deploy.config.env` must exist and contain the current host mapping for the environment.

## Current Boundary Note

The deployment scaffold intentionally does not resolve the existing architectural mismatch between the current frontend proxy target and the intended server placement of heavy services. The `timo` customer VM template therefore exposes `MINTTI_FRONTEND_PROXY_TARGET` as a host-local setting that must be pointed at the final tenant-local backend or other agreed API entrypoint.