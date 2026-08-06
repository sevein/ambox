#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<USAGE
Usage: prepare-notes.sh [options]

Options
  --version <version>    Release version used in image and comparison links
  --target <ref>         Commit or tag to summarize
  --repo <owner/repo>    Repository slug
  --output-dir <path>    Directory for generated note inputs and fallbacks
  --template <path>      Copilot prompt template
  --skip-fetch           Use the existing upstream remote-tracking branch
  -h, --help             Show this help text
USAGE
}

version=""
target=""
repo=""
output_dir=""
template=""
skip_fetch="false"

while [[ $# -gt 0 ]]; do
  case "$1" in
  --version)
    [[ $# -ge 2 ]] || {
      echo "--version requires a value" >&2
      exit 1
    }
    version="$2"
    shift 2
    ;;
  --target)
    [[ $# -ge 2 ]] || {
      echo "--target requires a value" >&2
      exit 1
    }
    target="$2"
    shift 2
    ;;
  --repo)
    [[ $# -ge 2 ]] || {
      echo "--repo requires a value" >&2
      exit 1
    }
    repo="$2"
    shift 2
    ;;
  --output-dir)
    [[ $# -ge 2 ]] || {
      echo "--output-dir requires a value" >&2
      exit 1
    }
    output_dir="$2"
    shift 2
    ;;
  --template)
    [[ $# -ge 2 ]] || {
      echo "--template requires a value" >&2
      exit 1
    }
    template="$2"
    shift 2
    ;;
  --skip-fetch)
    skip_fetch="true"
    shift
    ;;
  -h | --help)
    usage
    exit 0
    ;;
  *)
    echo "unrecognized option: $1" >&2
    exit 1
    ;;
  esac
done

for required in version target repo output_dir template; do
  if [[ -z "${!required}" ]]; then
    echo "--${required//_/-} is required" >&2
    exit 1
  fi
done

if [[ ! "$version" =~ ^[0-9A-Za-z.+-]+$ ]]; then
  echo "Invalid release version: $version" >&2
  exit 1
fi
if [[ "$target" == -* || ! "$target" =~ ^[0-9A-Za-z._/-]+$ ]]; then
  echo "Invalid target ref: $target" >&2
  exit 1
fi
if [[ ! "$repo" =~ ^[0-9A-Za-z_.-]+/[0-9A-Za-z_.-]+$ ]]; then
  echo "Invalid repository slug: $repo" >&2
  exit 1
fi
if [[ ! -f "$template" ]]; then
  echo "Prompt template not found: $template" >&2
  exit 1
fi

mkdir -p "$output_dir"

target_commit="$(git rev-parse --verify "${target}^{commit}")"
upstream_repo="artefactual/archivematica"
upstream_branch="qa/1.x"
upstream_ref="upstream/${upstream_branch}"
upstream_url="https://github.com/${upstream_repo}.git"

if [[ "$skip_fetch" != "true" ]]; then
  if git remote get-url upstream >/dev/null 2>&1; then
    current_upstream_url="$(git remote get-url upstream)"
    if [[ "$current_upstream_url" != "$upstream_url" ]]; then
      git remote set-url upstream "$upstream_url"
    fi
  else
    git remote add upstream "$upstream_url"
  fi
  git fetch --no-tags upstream "$upstream_branch"
fi

if ! git rev-parse --verify "${upstream_ref}^{commit}" >/dev/null 2>&1; then
  echo "Upstream ref is unavailable: $upstream_ref" >&2
  exit 1
fi

tag_search_ref="$target_commit"
if version_commit="$(git rev-parse --verify \
  "refs/tags/${version}^{commit}" 2>/dev/null)" &&
  [[ "$version_commit" == "$target_commit" ]]; then
  tag_search_ref="${target_commit}^"
fi

describe_args=(--tags --abbrev=0 --match '[0-9]*')
if [[ "$version" != *-* ]]; then
  describe_args+=(--exclude '*-*')
fi
previous_tag="$(git describe "${describe_args[@]}" "$tag_search_ref" 2>/dev/null || true)"

current_upstream="$(git merge-base "$target_commit" "$upstream_ref" 2>/dev/null || true)"
previous_upstream=""
if [[ -n "$previous_tag" ]]; then
  previous_upstream="$(git merge-base "$previous_tag" "$upstream_ref" 2>/dev/null || true)"
fi

upstream_changes="$output_dir/upstream-changes.md"
ambox_changes="$output_dir/ambox-changes.md"
changelog="$output_dir/changelog.md"
footer="$output_dir/footer.md"
fallback="$output_dir/fallback.md"
prompt="$output_dir/prompt.md"

if [[ -n "$current_upstream" && -n "$previous_upstream" ]]; then
  git log --first-parent --max-count=250 --format='- %h: %s' \
    "${previous_upstream}..${current_upstream}" >"$upstream_changes"
elif [[ -n "$current_upstream" ]]; then
  printf -- '- Initial release based on upstream commit %s.\n' \
    "$(git rev-parse --short=8 "$current_upstream")" >"$upstream_changes"
else
  printf -- '- The upstream commit range could not be determined.\n' \
    >"$upstream_changes"
fi
if [[ ! -s "$upstream_changes" ]]; then
  printf -- '- No upstream changes are included in this release.\n' \
    >"$upstream_changes"
fi

if [[ -n "$previous_tag" ]]; then
  git log --no-merges --max-count=250 --format='- %h: %s' \
    "${previous_tag}..${target_commit}" --not "$upstream_ref" \
    >"$ambox_changes"
else
  git log --no-merges --max-count=250 --format='- %h: %s' \
    "$target_commit" --not "$upstream_ref" >"$ambox_changes"
fi
if [[ ! -s "$ambox_changes" ]]; then
  printf -- '- No ambox-specific changes are included in this release.\n' \
    >"$ambox_changes"
fi

if [[ -n "$previous_tag" ]]; then
  changelog_range="${previous_tag}..${target_commit}"
else
  changelog_range="$target_commit"
fi
while IFS=$'\t' read -r sha title_line author; do
  [[ -z "$sha" ]] && continue
  printf '* %s: %s (%s)\n' "$sha" "$title_line" "$author"
done < <(git log --format='%h%x09%s%x09%an' "$changelog_range" \
  --not "$upstream_ref") >"$changelog"
if [[ ! -s "$changelog" ]]; then
  printf '* No fork-only commits are included in this release.\n' >"$changelog"
fi

repo_owner="${repo%%/*}"
{
  if [[ -n "$current_upstream" ]]; then
    upstream_short="$(git rev-parse --short=8 "$current_upstream")"
    printf 'Based on upstream commit [%s](https://github.com/%s/commit/%s).\n\n' \
      "$upstream_short" "$upstream_repo" "$current_upstream"
  fi
  printf '## Container images\n\n'
  printf 'Multi-architecture image available at:\n\n'
  printf -- '- `ghcr.io/%s/ambox:%s`\n' "$repo_owner" "$version"
  printf -- '- `docker.io/artefactual/ambox:%s`\n\n' "$version"
  printf '## Changelog\n\n'
  cat "$changelog"
  if [[ -n "$previous_tag" ]]; then
    printf '\nhttps://github.com/%s/compare/%s...%s\n' \
      "$repo" "$previous_tag" "$version"
  fi
} >"$footer"

{
  printf '## Archivematica\n\n'
  cat "$upstream_changes"
  printf '\n## ambox\n\n'
  cat "$ambox_changes"
  printf '\n'
  cat "$footer"
} >"$fallback"

{
  cat "$template"
  printf '\n\nRelease version: `%s`\n' "$version"
  if [[ -n "$previous_tag" ]]; then
    printf 'Previous release: `%s`\n' "$previous_tag"
  else
    printf 'Previous release: none\n'
  fi
  printf '\n<untrusted_archivematica_changes>\n'
  cat "$upstream_changes"
  printf '</untrusted_archivematica_changes>\n'
  printf '\n<untrusted_ambox_changes>\n'
  cat "$ambox_changes"
  printf '</untrusted_ambox_changes>\n'
} >"$prompt"

printf 'Prepared release-note inputs for %s (%s..%s)\n' \
  "$version" "${previous_tag:-initial}" "$(git rev-parse --short=8 "$target_commit")"
