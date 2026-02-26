#!/usr/bin/env bash
set -euo pipefail

# `key.sh` lives in `hack/box/scripts/seed/`; go back to the repository root.
ROOT=$(cd "$(dirname "$0")/../../../.." && pwd)

SS_ROOT="$ROOT/hack/submodules/archivematica-storage-service"

superproject_paths="
src/archivematica/dashboard/components/administration/migrations
src/archivematica/dashboard/main/migrations
src/archivematica/dashboard/fpr/migrations
hack/box/scripts/seed/seed.sh
"

ss_paths="
src/archivematica/storage_service/locations/migrations
src/archivematica/storage_service/administration/migrations
"

if command -v sha256sum >/dev/null 2>&1; then
  hash_cmd="sha256sum"
else
  hash_cmd="shasum -a 256"
fi

latest_commit() {
  local repo_root="$1"
  local path="$2"
  local label="$3"
  local commit
  commit=$(git -C "$repo_root" log -1 --format=%H -- "$path" 2>/dev/null || true)
  if [ -z "$commit" ]; then
    commit="missing:${label}"
  fi
  printf "%s  %s\n" "$commit" "$label"
}

{
  printf "%s" "$superproject_paths" | while IFS= read -r path; do
    [ -z "$path" ] && continue
    latest_commit "$ROOT" "$path" "$path"
  done

  printf "%s" "$ss_paths" | while IFS= read -r path; do
    [ -z "$path" ] && continue
    if git -C "$SS_ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
      latest_commit "$SS_ROOT" "$path" "hack/submodules/archivematica-storage-service/$path"
    else
      printf "%s  %s\n" \
        "missing:hack/submodules/archivematica-storage-service/$path" \
        "hack/submodules/archivematica-storage-service/$path"
    fi
  done
} | $hash_cmd | awk '{print $1}'
