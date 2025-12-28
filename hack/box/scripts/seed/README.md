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
- `.github/workflows/seed-cache.yml`: reusable workflow that generates the dumps
  (via the `seed-builder` target) and publishes the cache artifact to GHCR.
- `hack/box/Dockerfile`: provides a `seed-builder` target to generate dumps and
  a final `runtime` image that consumes the cache artifact when
  `AM_SEED_CACHE_IMAGE` is provided.

## Cache artifact

The cache is pushed to:

```
ghcr.io/<org>/ambox-build-cache:seed-<fullhash>
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
AM_SEED_CACHE_IMAGE=ghcr.io/<org>/ambox-build-cache:seed-<fullhash>
AM_SEED_KEY=<fullhash>
```

The Dockerfile copies `/seed/*.sql.gz` into `/docker-seed` in the `runtime`
stage. The `seed-builder` target is used only by the cache workflow.

## Local usage (optional)

Compute the key:

```
./hack/box/scripts/seed/key.sh
```

Run the seed build manually (needs GHCR auth to push):

```
AM_SEED_KEY=$(./hack/box/scripts/seed/key.sh)
docker buildx build --progress=plain --load \
  --build-arg AM_SEED_CACHE_IMAGE=seedcache-empty \
  -f hack/box/Dockerfile \
  -t ambox-seed-builder:${AM_SEED_KEY} .
```
