#!/usr/bin/env bash
set -euo pipefail

config=""
interface="wg0"
routes=""
remove_routes=""
restart=false

usage() {
  cat <<'USAGE'
Usage: sync-wireguard-routes.sh --config PATH --routes CIDR[,CIDR...] [options]

Options:
  --interface NAME       WireGuard interface to restart (default: wg0)
  --remove-routes CIDRS  Comma-separated routes to remove before adding routes
  --restart              Restart the interface after updating the configuration
USAGE
}

while (($# > 0)); do
  case "$1" in
    --config)
      config="$2"
      shift 2
      ;;
    --interface)
      interface="$2"
      shift 2
      ;;
    --routes)
      routes="$2"
      shift 2
      ;;
    --remove-routes)
      remove_routes="$2"
      shift 2
      ;;
    --restart)
      restart=true
      shift
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

if [[ -z "$config" || -z "$routes" ]]; then
  usage >&2
  exit 2
fi

if [[ ! -f "$config" ]]; then
  printf 'WireGuard configuration does not exist: %s\n' "$config" >&2
  exit 1
fi

peer_count="$(grep -Ec '^[[:space:]]*\[Peer\][[:space:]]*$' "$config" || true)"
allowed_ips_count="$(grep -Ec '^[[:space:]]*AllowedIPs[[:space:]]*=' "$config" || true)"

if [[ "$peer_count" -ne 1 || "$allowed_ips_count" -ne 1 ]]; then
  printf '%s\n' \
    'Automatic update requires exactly one [Peer] and one AllowedIPs entry.' \
    "Found $peer_count peer sections and $allowed_ips_count AllowedIPs entries in $config." >&2
  exit 1
fi

temporary_file="$(mktemp "${config}.tmp.XXXXXX")"
cleanup() {
  rm -f "$temporary_file"
}
trap cleanup EXIT

awk -v additions="$routes" -v removals="$remove_routes" '
  function trim(value) {
    gsub(/^[[:space:]]+|[[:space:]]+$/, "", value)
    return value
  }

  /^[[:space:]]*AllowedIPs[[:space:]]*=/ {
    indent = $0
    sub(/[^[:space:]].*$/, "", indent)

    current = substr($0, index($0, "=") + 1)
    current_count = split(current, current_values, ",")
    output = ""

    removal_count = split(removals, removal_values, ",")
    for (item = 1; item <= removal_count; item++) {
      value = trim(removal_values[item])
      if (value != "") {
        remove[value] = 1
      }
    }

    for (item = 1; item <= current_count; item++) {
      value = trim(current_values[item])
      if (value != "" && !remove[value] && !seen[value]++) {
        output = output (output == "" ? "" : ", ") value
      }
    }

    addition_count = split(additions, addition_values, ",")
    for (item = 1; item <= addition_count; item++) {
      value = trim(addition_values[item])
      if (value != "" && !seen[value]++) {
        output = output (output == "" ? "" : ", ") value
      }
    }

    print indent "AllowedIPs = " output
    next
  }

  { print }
' "$config" >"$temporary_file"

if cmp -s "$temporary_file" "$config"; then
  printf 'WireGuard routes are already configured in %s.\n' "$config"
else
  backup="${config}.backup.$(date -u +%Y%m%dT%H%M%SZ)"
  cp --preserve=all "$config" "$backup"
  cp "$temporary_file" "$config"
  printf 'Updated %s. Backup: %s\n' "$config" "$backup"
fi

if [[ "$restart" == true ]]; then
  if ip link show "$interface" >/dev/null 2>&1; then
    wg-quick down "$config"
  fi
  wg-quick up "$config"
  printf 'Restarted WireGuard interface %s.\n' "$interface"
fi
