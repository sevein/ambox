# AGENTS.md

This repo is a fork of Archivematica focused on the hack/box single-container
distribution ("ambox"). Optimize for changes in `hack/box/` unless the task
explicitly needs core Archivematica code.

## Project focus

- ambox is a self-contained container for local testing and lightweight use.
- The container is orchestrated with s6-overlay; service definitions live in
  `hack/box/s6-rc.d/`.
- Configuration is layered via `hack/box/config/` (default config and JSON
  schema).

## Key paths

- `hack/box/README.md`: user-facing quick start and operational notes.
- `hack/box/Dockerfile`: image build.
- `hack/box/Makefile`: build/run helpers.
- `hack/box/scripts/`: build helpers, including seed-cache tooling.
- `hack/box/s6-rc.d/`: service supervision graph.
- `.github/workflows/release.yml`: release pipeline.

## Common commands (local)

Run these from `hack/box/` unless specified:

- Build: `make build`
- Run locally: `make run`
- Shell into image: `make shell`

Ports exposed by the container:

- `64080` Dashboard
- `64081` Storage Service
- `64022` SFTP (user `archivematica`, password `12345`)
- If `make run` fails with a port bind error, stop any previous ambox container
  before retrying (the container name is auto-generated unless explicitly set).

## Release flow (CI)

Releases are driven by the GitHub Actions workflow
`.github/workflows/release.yml`:

- Workflow input: semantic version string (e.g. `1.2.3` or `1.2.3-rc.1`).
- Builds multi-arch images (amd64/arm64) with buildx.
- Pushes to Docker Hub `artefactual/ambox` and GHCR
  `ghcr.io/<repo_owner>/ambox`, tagging both `<version>` and `latest`.
- Publishes a GitHub Release and tags the repo.

If you change release behavior, update the workflow and any docs that mention
the process.

## Contribution guardrails

- Keep diffs minimal and scoped to `hack/box/` unless necessary.
- When changing service dependencies, update both the s6 definitions and any
  relevant docs/graphs in `hack/box/README.md`.
- When changing configuration schema, update both `config/ambox.yaml` and
  `config/schema.json`.
- Prefer using existing scripts in `hack/box/scripts/` rather than re-creating
  logic.

## Roadmap

Longer-term items live in the project wiki; use it for context only and avoid
copying large sections into repo docs unless requested.
