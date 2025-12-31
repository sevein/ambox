#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/../../.." && pwd)

paths="
hack/submodules/archivematica-storage-service/src/archivematica/storage_service/locations/migrations
hack/submodules/archivematica-storage-service/src/archivematica/storage_service/administration/migrations
src/archivematica/dashboard/components/administration/migrations
src/archivematica/dashboard/main/migrations
src/archivematica/dashboard/fpr/migrations
hack/box/scripts/seed/seed.sh
"

if command -v sha256sum >/dev/null 2>&1; then
  hash_cmd="sha256sum"
else
  hash_cmd="shasum -a 256"
fi

printf "%s" "$paths" | while IFS= read -r path; do
  [ -z "$path" ] && continue
  commit=$(git -C "$ROOT" log -1 --format=%H -- "$path" 2>/dev/null || true)
  if [ -z "$commit" ]; then
    commit="missing:${path}"
  fi
  printf "%s  %s\n" "$commit" "$path"
done | $hash_cmd | awk '{print $1}'
