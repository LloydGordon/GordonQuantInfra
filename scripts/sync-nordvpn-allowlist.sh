#!/usr/bin/env bash
set -euo pipefail

add_cidrs=""
remove_cidrs=""

usage() {
  cat <<'USAGE'
Usage: sync-nordvpn-allowlist.sh --add CIDR[,CIDR...] [options]

Options:
  --remove CIDRS  Comma-separated CIDRs to remove before adding current routes
USAGE
}

while (($# > 0)); do
  case "$1" in
    --add)
      add_cidrs="$2"
      shift 2
      ;;
    --remove)
      remove_cidrs="$2"
      shift 2
      ;;
    -h | --help)
      usage
      exit 0
      ;;
    *)
      printf 'Unknown argument: %s\n' "$1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if [[ -z "$add_cidrs" ]]; then
  usage >&2
  exit 2
fi

if ! command -v nordvpn >/dev/null 2>&1; then
  printf 'NordVPN is not installed; skipping its allowlist.\n'
  exit 0
fi

settings="$(nordvpn settings 2>&1)" || {
  printf '%s\n' "$settings" >&2
  printf 'NordVPN is installed but its daemon is unavailable.\n' >&2
  exit 1
}

split_cidrs() {
  local input="$1"
  local value

  IFS=',' read -ra values <<<"$input"
  for value in "${values[@]}"; do
    value="${value//[[:space:]]/}"
    if [[ -n "$value" ]]; then
      printf '%s\n' "$value"
    fi
  done
}

while IFS= read -r cidr; do
  if grep -Fq "$cidr" <<<"$settings"; then
    printf 'Removing stale NordVPN allowlist route %s...\n' "$cidr"
    nordvpn allowlist remove subnet "$cidr"
    settings="$(nordvpn settings)"
  fi
done < <(split_cidrs "$remove_cidrs")

while IFS= read -r cidr; do
  if grep -Fq "$cidr" <<<"$settings"; then
    printf 'NordVPN already allows %s.\n' "$cidr"
  else
    printf 'Adding NordVPN allowlist route %s...\n' "$cidr"
    nordvpn allowlist add subnet "$cidr"
    settings="$(nordvpn settings)"
  fi
done < <(split_cidrs "$add_cidrs")
