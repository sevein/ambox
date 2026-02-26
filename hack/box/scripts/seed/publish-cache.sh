#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/../../../.." && pwd)

SEED_CACHE_IMAGE_REPO=${SEED_CACHE_IMAGE_REPO:-}
if [ -z "$SEED_CACHE_IMAGE_REPO" ]; then
  GHCR_OWNER=${GHCR_OWNER:-sevein}
  SEED_CACHE_IMAGE_REPO="ghcr.io/${GHCR_OWNER}/ambox-build-cache"
fi

AM_SEED_KEY=${AM_SEED_KEY:-"$("$ROOT/hack/box/scripts/seed/key.sh")"}
SEED_TAG="${SEED_CACHE_IMAGE_REPO}:seed-${AM_SEED_KEY}"
SEED_BUILDER_IMAGE=${SEED_BUILDER_IMAGE:-"ambox-seed-builder:${AM_SEED_KEY}"}
PLATFORMS=${PLATFORMS:-linux/amd64,linux/arm64}
SEED_CACHE_PUSH=${SEED_CACHE_PUSH:-1}
SEED_CACHE_REMOTE_REPO=${SEED_CACHE_REMOTE_REPO:-}
SEED_CACHE_REMOTE_REUSE=${SEED_CACHE_REMOTE_REUSE:-1}

printf 'seed-cache: key=%s\n' "$AM_SEED_KEY"
printf 'seed-cache: tag=%s\n' "$SEED_TAG"

if [ "$SEED_CACHE_PUSH" != "1" ]; then
  if docker image inspect "$SEED_TAG" >/dev/null 2>&1; then
    printf 'seed-cache: local image already exists: %s\n' "$SEED_TAG"
    exit 0
  fi

  if [ "$SEED_CACHE_REMOTE_REUSE" = "1" ] && [ -n "$SEED_CACHE_REMOTE_REPO" ]; then
    remote_tag="${SEED_CACHE_REMOTE_REPO}:seed-${AM_SEED_KEY}"
    printf 'seed-cache: checking remote cache %s\n' "$remote_tag"
    if docker manifest inspect "$remote_tag" >/dev/null 2>&1; then
      printf 'seed-cache: reusing remote cache %s\n' "$remote_tag"
      docker pull "$remote_tag"
      if [ "$remote_tag" != "$SEED_TAG" ]; then
        docker tag "$remote_tag" "$SEED_TAG"
      fi
      printf 'seed-cache: loaded local image %s (from remote)\n' "$SEED_TAG"
      exit 0
    fi
    printf 'seed-cache: remote cache not found, building locally\n'
  fi
fi

tmpdir=$(mktemp -d)
cleanup() {
  rm -rf "$tmpdir"
}
trap cleanup EXIT

docker buildx build --progress=plain --load \
  --build-arg AM_SEED_CACHE_IMAGE=seedcache-empty \
  --target seed-builder \
  -f "$ROOT/hack/box/Dockerfile" \
  -t "$SEED_BUILDER_IMAGE" \
  "$ROOT"

cid=$(docker create "$SEED_BUILDER_IMAGE")
docker cp "$cid:/docker-seed/mcp.sql.gz" "$tmpdir/mcp.sql.gz"
docker cp "$cid:/docker-seed/ss.sql.gz" "$tmpdir/ss.sql.gz"
docker rm "$cid"
printf '%s\n' "$AM_SEED_KEY" > "$tmpdir/seed.key"

cat > "$tmpdir/SeedCache.Dockerfile" <<'EOF'
FROM scratch
LABEL org.opencontainers.image.title="ambox build cache"
LABEL org.opencontainers.image.description="Build-time cache artifacts for ambox"
LABEL org.opencontainers.image.source="https://github.com/sevein/ambox"
LABEL com.sevein.ambox.purpose="seed-cache"
ARG AM_SEED_KEY
LABEL com.sevein.ambox.seed.key="${AM_SEED_KEY}"
COPY mcp.sql.gz /seed/mcp.sql.gz
COPY ss.sql.gz /seed/ss.sql.gz
COPY seed.key /seed/seed.key
EOF

build_args=(
  --progress=plain
  --build-arg "AM_SEED_KEY=$AM_SEED_KEY"
  -f "$tmpdir/SeedCache.Dockerfile"
  -t "$SEED_TAG"
)

if [ "$SEED_CACHE_PUSH" = "1" ]; then
  build_args+=(--platform "$PLATFORMS" --push)
  docker buildx build "${build_args[@]}" "$tmpdir"
  printf 'seed-cache: pushed %s\n' "$SEED_TAG"
else
  if [[ "$PLATFORMS" == *,* ]]; then
    printf 'seed-cache: local mode ignores multi-platform PLATFORMS=%s and loads a single host-platform image\n' "$PLATFORMS" >&2
  elif [ -n "$PLATFORMS" ]; then
    build_args+=(--platform "$PLATFORMS")
  fi
  build_args+=(--load)
  docker buildx build "${build_args[@]}" "$tmpdir"
  printf 'seed-cache: loaded local image %s\n' "$SEED_TAG"
fi
