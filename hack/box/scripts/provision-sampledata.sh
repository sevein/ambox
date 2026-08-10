#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
SAMPLEDATA_PATH=hack/submodules/archivematica-sampledata
SAMPLEDATA_ROOT="$ROOT/$SAMPLEDATA_PATH"

usage() {
  echo "Usage: $0 <image|e2e>" >&2
}

if [ "$#" -ne 1 ]; then
  usage
  exit 2
fi

case "$1" in
  image)
    sample_paths=(
      SampleTransfers/DemoTransferCSV
      SampleTransfers/Images
    )
    ;;
  e2e)
    sample_paths=(SampleTransfers/Images/pictures)
    ;;
  *)
    usage
    exit 2
    ;;
esac

sampledata_ref=$(git -C "$ROOT" rev-parse "HEAD:$SAMPLEDATA_PATH" 2>/dev/null) || {
  echo "sampledata: cannot resolve the $SAMPLEDATA_PATH gitlink" >&2
  exit 1
}
sampledata_repo=$(
  git config -f "$ROOT/.gitmodules" \
    --get "submodule.$SAMPLEDATA_PATH.url"
) || {
  echo "sampledata: cannot resolve the $SAMPLEDATA_PATH repository" >&2
  exit 1
}

verify_paths() {
  local root="$1"
  local first_file
  local sample_path
  for sample_path in "${sample_paths[@]}"; do
    first_file=$(find "$root/$sample_path" -type f -print -quit 2>/dev/null || true)
    if [ -z "$first_file" ]; then
      echo "sampledata: required path is empty or missing: $sample_path" >&2
      return 1
    fi
  done
}

if [ -e "$SAMPLEDATA_ROOT/.git" ]; then
  current_ref=$(git -C "$SAMPLEDATA_ROOT" rev-parse HEAD)
  if [ "$current_ref" != "$sampledata_ref" ]; then
    echo "sampledata: checkout is at $current_ref" >&2
    echo "sampledata: expected pinned revision $sampledata_ref" >&2
    exit 1
  fi

  if [ "$(git -C "$SAMPLEDATA_ROOT" config --bool core.sparseCheckout || true)" = true ]; then
    git -C "$SAMPLEDATA_ROOT" sparse-checkout add "${sample_paths[@]}"
  fi

  verify_paths "$SAMPLEDATA_ROOT"
  echo "sampledata: using pinned revision $sampledata_ref ($1 profile)"
  exit 0
fi

if [ -d "$SAMPLEDATA_ROOT" ] && \
  [ -n "$(find "$SAMPLEDATA_ROOT" -mindepth 1 -maxdepth 1 -print -quit)" ]; then
  echo "sampledata: refusing to replace non-empty $SAMPLEDATA_ROOT" >&2
  exit 1
fi

sampledata_parent=$(dirname "$SAMPLEDATA_ROOT")
checkout_tmp=$(mktemp -d "$sampledata_parent/.archivematica-sampledata.XXXXXX")

cleanup() {
  rm -rf "$checkout_tmp"
}
trap cleanup EXIT

git init --quiet "$checkout_tmp"
git -C "$checkout_tmp" remote add origin "$sampledata_repo"
git -C "$checkout_tmp" sparse-checkout set --cone "${sample_paths[@]}"
git -C "$checkout_tmp" fetch \
  --no-tags \
  --depth 1 \
  --filter=blob:none \
  origin \
  "$sampledata_ref"
git -C "$checkout_tmp" switch --quiet --detach FETCH_HEAD
verify_paths "$checkout_tmp"

if [ -d "$SAMPLEDATA_ROOT" ]; then
  rmdir "$SAMPLEDATA_ROOT"
fi
mv "$checkout_tmp" "$SAMPLEDATA_ROOT"
trap - EXIT

echo "sampledata: provisioned pinned revision $sampledata_ref ($1 profile)"
