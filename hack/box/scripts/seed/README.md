# Seed Cache (GHCR)

This directory contains the tooling to build and consume pre-seeded MySQL dumps
for the ambox image. The dumps are stored as an OCI artifact in GHCR and keyed
by a deterministic hash derived from migration directories and the seed script.

## Components

- `seed.sh`: builds the seed dumps inside the image build (writes to
  `/docker-seed/mcp.sql.gz` and `/docker-seed/ss.sql.gz`). It exits early if the
  dumps already exist.
- `key.sh`: computes the seed cache key from the latest git commits touching
  migrations plus `seed.sh`.
- `publish-cache.sh`: builds `seed-builder`, extracts the dumps, and publishes
  the seed cache OCI artifact to GHCR for the current key (or loads it locally
  when `SEED_CACHE_PUSH=0`).
- `.github/workflows/seed-cache.yml`: reusable workflow that generates the dumps
  and publishes the cache artifact to GHCR by calling `publish-cache.sh`.
- `hack/box/Dockerfile`: provides a `seed-builder` target to generate dumps and
  a final `runtime` image that consumes the cache artifact when
  `AM_SEED_CACHE_IMAGE` is provided.

## Cache artifact

The cache is pushed to:

```
ghcr.io/sevein/ambox-build-cache:seed-<fullhash>
```

It contains:

- `/seed/mcp.sql.gz`
- `/seed/ss.sql.gz`
- `/seed/seed.key` (the full cache key)

Labels include:

- `com.sevein.ambox.purpose=seed-cache`
- `com.sevein.ambox.seed.key=<fullhash>`

## Release flow

1. `release.yml` calls `seed-cache.yml` (via `workflow_call`).
2. `seed-cache.yml` computes `AM_SEED_KEY`, checks for an existing cache tag,
   and builds/pushes it if missing.
3. The release build passes:

```
AM_SEED_CACHE_IMAGE=ghcr.io/sevein/ambox-build-cache:seed-<fullhash>
AM_SEED_KEY=<fullhash>
```

The Dockerfile copies `/seed/*.sql.gz` into `/docker-seed` in the `runtime`
stage. The `seed-builder` target is used only by the cache workflow.

## Local usage (optional)

Compute the key:

```
./hack/box/scripts/seed/key.sh
```

Publish the seed cache manually (needs GHCR auth to push):

```
docker login ghcr.io

# Default: push to ghcr.io/sevein/ambox-build-cache
./hack/box/scripts/seed/publish-cache.sh

# Override: push to a different namespace/repo
SEED_CACHE_IMAGE_REPO=ghcr.io/<org-or-user>/ambox-build-cache \
  ./hack/box/scripts/seed/publish-cache.sh
```

From `hack/box/`, the Makefile wraps the same script:

```
# Default: push to ghcr.io/sevein/ambox-build-cache
make seed-cache

# Override: push to a different remote repo
make seed-cache SEED_CACHE_IMAGE_REMOTE=ghcr.io/<org-or-user>/ambox-build-cache

# Default: build/load a local-only cache image in `ambox-build-cache-local`
# (first tries to reuse the matching remote tag from `SEED_CACHE_IMAGE_REMOTE`)
make seed-cache-local

# Override: use a different local image repo name
make seed-cache-local SEED_CACHE_IMAGE=<local-repo-name>
```

For local testing before publishing, build a local cache image and then point
`make build` at the same image repo. By default, `hack/box/Makefile` already
uses `SEED_CACHE_IMAGE=ambox-build-cache-local`, so the two commands line up:

```
make seed-cache-local
make build
```

CI/release workflows do not use the Makefile default for remote builds; they set
the seed cache image/tag explicitly in the workflow.

To disable remote reuse and force a local seed rebuild:

```
make seed-cache-local SEED_CACHE_REMOTE_REUSE=0
```
