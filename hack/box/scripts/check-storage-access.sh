#!/bin/sh

set -eu

failed=0
service_uid=$(id -u)
service_gid=$(id -g)

check_directory() {
  label=$1
  path=$2
  required_access=$3

  if [ ! -d "$path" ]; then
    printf >&2 'ambox: %s directory does not exist: %s\n' "$label" "$path"
    failed=1
    return
  fi

  missing_access=
  case "$required_access" in
    *r*)
      if [ ! -r "$path" ]; then missing_access="$missing_access read"; fi
      ;;
  esac
  case "$required_access" in
    *w*)
      if [ ! -w "$path" ]; then missing_access="$missing_access write"; fi
      ;;
  esac
  case "$required_access" in
    *x*)
      if [ ! -x "$path" ]; then missing_access="$missing_access traverse"; fi
      ;;
  esac

  if [ -z "$missing_access" ]; then return; fi

  metadata=$(stat -c 'UID=%u GID=%g mode=%a' "$path" 2>/dev/null || true)
  if [ -z "$metadata" ]; then metadata="metadata unavailable"; fi

  printf >&2 'ambox: %s is missing%s access for UID/GID %s:%s\n' \
    "$label" "$missing_access" "$service_uid" "$service_gid"
  printf >&2 'ambox: path=%s %s\n' "$path" "$metadata"
  failed=1
}

check_directory "Transfer source" /home rx
check_directory \
  "SFTP upload directory" \
  /home/archivematica/transfers \
  rwx
check_directory \
  "AIP Store" \
  /var/archivematica/sharedDirectory/www/AIPsStore \
  rwx
check_directory \
  "DIP Store" \
  /var/archivematica/sharedDirectory/www/DIPsStore \
  rwx

if [ "$failed" -ne 0 ]; then
  printf >&2 '\n'
  printf >&2 'ambox: storage access checks failed.\n'
  printf >&2 \
    'ambox: grant UID/GID %s:%s access using ownership or ACLs, then restart.\n' \
    "$service_uid" "$service_gid"
  printf >&2 'ambox: ambox does not change ownership of mounted data.\n'
  exit 1
fi

printf 'ambox: storage access checks passed for UID/GID %s:%s.\n' \
  "$service_uid" "$service_gid"
