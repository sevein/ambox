#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<USAGE
Usage: compose-notes.sh [options]

Options
  --summary <path>       Optional Copilot-generated Markdown summary
  --fallback <path>      Deterministic fallback release notes
  --footer <path>        Deterministic release-note footer
  --output <path>        Final release notes
  --source-output <path> File recording "copilot" or "fallback"
  -h, --help             Show this help text
USAGE
}

summary=""
fallback=""
footer=""
output=""
source_output=""

while [[ $# -gt 0 ]]; do
  case "$1" in
  --summary)
    [[ $# -ge 2 ]] || {
      echo "--summary requires a value" >&2
      exit 1
    }
    summary="$2"
    shift 2
    ;;
  --fallback)
    [[ $# -ge 2 ]] || {
      echo "--fallback requires a value" >&2
      exit 1
    }
    fallback="$2"
    shift 2
    ;;
  --footer)
    [[ $# -ge 2 ]] || {
      echo "--footer requires a value" >&2
      exit 1
    }
    footer="$2"
    shift 2
    ;;
  --output)
    [[ $# -ge 2 ]] || {
      echo "--output requires a value" >&2
      exit 1
    }
    output="$2"
    shift 2
    ;;
  --source-output)
    [[ $# -ge 2 ]] || {
      echo "--source-output requires a value" >&2
      exit 1
    }
    source_output="$2"
    shift 2
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

for required in fallback footer output source_output; do
  if [[ -z "${!required}" ]]; then
    echo "--${required//_/-} is required" >&2
    exit 1
  fi
done
if [[ ! -f "$fallback" || ! -f "$footer" ]]; then
  echo "Fallback notes or footer are missing" >&2
  exit 1
fi

valid_summary="false"
normalized_summary="$(mktemp -t ambox-release-summary.XXXXXX)"
trap 'rm -f "$normalized_summary"' EXIT

if [[ -n "$summary" && -s "$summary" ]] &&
  [[ "$(wc -c <"$summary")" -le 12000 ]]; then
  tr -d '\r' <"$summary" | awk '
    NF { seen = 1 }
    seen { lines[++count] = $0 }
    END {
      while (count > 0 && lines[count] == "") count--
      for (i = 1; i <= count; i++) print lines[i]
    }
  ' >"$normalized_summary"

  archivematica_headings="$(grep -c '^## Archivematica$' \
    "$normalized_summary" || true)"
  ambox_headings="$(grep -c '^## ambox$' "$normalized_summary" || true)"
  all_headings="$(grep -c '^#' "$normalized_summary" || true)"
  archivematica_line="$(grep -n '^## Archivematica$' "$normalized_summary" |
    cut -d: -f1 || true)"
  ambox_line="$(grep -n '^## ambox$' "$normalized_summary" |
    cut -d: -f1 || true)"

  if [[ "$archivematica_headings" == "1" && "$ambox_headings" == "1" &&
    "$all_headings" == "2" && -n "$archivematica_line" &&
    -n "$ambox_line" && "$archivematica_line" -lt "$ambox_line" ]] &&
    ! grep -q '^```' "$normalized_summary"; then
    archivematica_body="$(sed -n \
      "$((archivematica_line + 1)),$((ambox_line - 1))p" \
      "$normalized_summary")"
    ambox_body="$(sed -n "$((ambox_line + 1)),\$p" "$normalized_summary")"
    archivematica_words="$(wc -w <<<"$archivematica_body")"
    ambox_words="$(wc -w <<<"$ambox_body")"
    archivematica_paragraphs="$(awk '
      NF && !in_paragraph { count++; in_paragraph = 1 }
      !NF { in_paragraph = 0 }
      END { print count + 0 }
    ' <<<"$archivematica_body")"
    ambox_paragraphs="$(awk '
      NF && !in_paragraph { count++; in_paragraph = 1 }
      !NF { in_paragraph = 0 }
      END { print count + 0 }
    ' <<<"$ambox_body")"
    if grep -q '[[:alnum:]]' <<<"$archivematica_body" &&
      grep -q '[[:alnum:]]' <<<"$ambox_body" &&
      ! grep -Eq '^[[:space:]]*([-*+] |[0-9]+[.)] )' \
        <<<"$archivematica_body" &&
      ! grep -Eq '^[[:space:]]*([-*+] |[0-9]+[.)] )' <<<"$ambox_body" &&
      [[ "$archivematica_paragraphs" == "1" &&
        "$ambox_paragraphs" == "1" ]] &&
      [[ "$archivematica_words" -le 120 && "$ambox_words" -le 120 ]]; then
      valid_summary="true"
    fi
  fi
fi

if [[ "$valid_summary" == "true" ]]; then
  {
    cat "$normalized_summary"
    printf '\n'
    cat "$footer"
  } >"$output"
  printf 'copilot\n' >"$source_output"
  echo "Using validated Copilot summary"
else
  cp "$fallback" "$output"
  printf 'fallback\n' >"$source_output"
  echo "Copilot summary unavailable or invalid; using deterministic fallback" >&2
fi
