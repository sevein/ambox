#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<USAGE
Usage: release-notes.sh [options] <tag>

Options
  --title <title>        Release title (defaults to tag)
  --repo <owner/repo>    Repository slug if not running inside the repo
  --prerelease[=bool]    Mark the release as a prerelease (accepts true/false)
  --dry-run              Show the command without executing it
  -h, --help             Show this help text

Example
  release.sh --prerelease --dry-run 0.9.0a3
USAGE
}

if ! command -v gh >/dev/null 2>&1; then
  echo "gh CLI is required" >&2
  exit 1
fi

current_tag=""
repo_arg=""
title=""
prerelease_flag=""
dry_run="false"

coerce_boolean() {
  local incoming="$1"
  case "$incoming" in
  true|TRUE|True|1)
    echo "true"
    ;;
  false|FALSE|False|0|"")
    echo "false"
    ;;
  *)
    echo "invalid"
    ;;
  esac
}

while [[ $# -gt 0 ]]; do
  case "$1" in
  --title)
    [[ $# -ge 2 ]] || {
      echo "--title requires a value" >&2
      exit 1
    }
    title="$2"
    shift 2
    ;;
  --repo)
    [[ $# -ge 2 ]] || {
      echo "--repo requires a value" >&2
      exit 1
    }
    repo_arg="$2"
    shift 2
    ;;
  --prerelease)
    prerelease_flag="--prerelease"
    shift 1
    ;;
  --prerelease=*)
    value="${1#*=}"
    bool_value="$(coerce_boolean "$value")"
    if [[ "$bool_value" == "invalid" ]]; then
      echo "Invalid value for --prerelease: $value" >&2
      exit 1
    fi
    if [[ "$bool_value" == "true" ]]; then
      prerelease_flag="--prerelease"
    else
      prerelease_flag=""
    fi
    shift 1
    ;;
  --dry-run)
    dry_run="true"
    shift 1
    ;;
  -h | --help)
    usage
    exit 0
    ;;
  --)
    shift 1
    break
    ;;
  -*)
    echo "unrecognized option: $1" >&2
    exit 1
    ;;
  *)
    if [[ -z "$current_tag" ]]; then
      current_tag="$1"
    elif [[ -z "$repo_arg" ]]; then
      repo_arg="$1"
    else
      echo "unexpected argument: $1" >&2
      exit 1
    fi
    shift 1
    ;;
  esac
done

if [[ -z "$current_tag" ]]; then
  usage >&2
  exit 1
fi

repo="${repo_arg:-${GH_REPO:-}}"
if [[ -z "$repo" ]]; then
  repo="$(gh repo view --json nameWithOwner --jq '.nameWithOwner')"
fi

if [[ -z "$title" ]]; then
  title="$current_tag"
fi

if ! git rev-parse "$current_tag^{commit}" >/dev/null 2>&1; then
  echo "Tag $current_tag is not available locally" >&2
  exit 1
fi

upstream_repo="artefactual/archivematica"
upstream_branch="qa/1.x"
upstream_url="https://github.com/${upstream_repo}.git"
if git remote get-url upstream >/dev/null 2>&1; then
  current_upstream_url="$(git remote get-url upstream)"
  if [[ "$current_upstream_url" != "$upstream_url" ]]; then
    git remote set-url upstream "$upstream_url"
  fi
else
  git remote add upstream "$upstream_url"
fi
git fetch --no-tags upstream "${upstream_branch}"

if [[ "$current_tag" == *-* ]]; then
  previous_tag="$(git describe --tags --abbrev=0 --match '[0-9]*' "${current_tag}^" 2>/dev/null || true)"
else
  previous_tag="$(git describe --tags --abbrev=0 --match '[0-9]*' --exclude '*-*' "${current_tag}^" 2>/dev/null || true)"
fi
notes_file="$(mktemp -t release-notes.XXXXXX)"

if [[ -z "$previous_tag" ]]; then
  : >"$notes_file"
  echo "No previous release tag found for $current_tag; creating empty release notes"
else
  if ! git rev-parse "$previous_tag^{commit}" >/dev/null 2>&1; then
    echo "Tag $previous_tag is not available locally" >&2
    exit 1
  fi

  compare_url="https://github.com/${repo}/compare/${previous_tag}...${current_tag}"

  commit_lines=()
  while IFS=$'\t' read -r sha title_line author; do
    [[ -z "$sha" ]] && continue
    commit_lines+=("* $sha: $title_line ($author)")
  done < <(git log --format='%h%x09%s%x09%an' "${previous_tag}..${current_tag}" \
    --not "upstream/${upstream_branch}")

  if [[ ${#commit_lines[@]} -eq 0 ]]; then
    if [[ -n "$upstream_repo" ]]; then
      commit_lines+=("* No fork-only commits between ${previous_tag} and ${current_tag}")
    else
      commit_lines+=("* No commits between ${previous_tag} and ${current_tag}")
    fi
  fi

  {
    printf '## Container images\n\n'
    printf 'Multi-architecture image available at:\n\n'
    printf -- '- `ghcr.io/sevein/ambox:%s`\n' "$current_tag"
    printf -- '- `docker.io/artefactual/ambox:%s`\n\n' "$current_tag"
    printf '## Changelog\n\n'
    printf '%s\n' "${commit_lines[@]}"
    printf '\n%s\n' "$compare_url"
  } >"$notes_file"
fi

cmd=(gh release create "$current_tag" --title "$title" --notes-file "$notes_file" --repo "$repo")

if [[ -n "$prerelease_flag" ]]; then
  cmd+=("$prerelease_flag")
fi

echo "Prepared release notes at: $notes_file"
printf 'Command to run:\n  '
printf '%q ' "${cmd[@]}"
printf '\n'

if [[ "$dry_run" == "true" ]]; then
  echo "Dry run mode: command not executed"
  exit 0
fi

echo "Creating GitHub release via gh CLI"
"${cmd[@]}"
echo "GitHub release created successfully"
