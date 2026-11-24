#!/usr/bin/env bash
set -euo pipefail

instance_id=""
region="us-east-1"
timeout_seconds="900"
poll_interval="10"

usage() {
  cat <<'USAGE'
Usage: get-wireguard-server-public-key.sh --instance-id ID [options]

Wait for a WireGuard EC2 instance to register with SSM and finish cloud-init,
then print only its server public key.

Options:
  --region REGION    AWS region (default: us-east-1)
  --timeout SECONDS  Maximum wait for SSM and cloud-init (default: 900)
USAGE
}

while (($# > 0)); do
  case "$1" in
    --instance-id)
      instance_id="$2"
      shift 2
      ;;
    --region)
      region="$2"
      shift 2
      ;;
    --timeout)
      timeout_seconds="$2"
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

if [[ ! "$instance_id" =~ ^i-[0-9a-f]+$ ]]; then
  printf 'Invalid or missing EC2 instance ID: %s\n' "$instance_id" >&2
  exit 2
fi

if [[ ! "$timeout_seconds" =~ ^[0-9]+$ ]] || ((timeout_seconds < 1)); then
  printf 'Invalid timeout: %s\n' "$timeout_seconds" >&2
  exit 2
fi

deadline=$((SECONDS + timeout_seconds))
printf 'Waiting for WireGuard SSM registration on %s...\n' "$instance_id" >&2

while true; do
  ping_status="$(
    aws ssm describe-instance-information \
      --region "$region" \
      --filters "Key=InstanceIds,Values=$instance_id" \
      --query 'InstanceInformationList[0].PingStatus' \
      --output text
  )"

  if [[ "$ping_status" == "Online" ]]; then
    break
  fi

  if ((SECONDS >= deadline)); then
    printf 'Timed out waiting for SSM on %s; last status: %s\n' \
      "$instance_id" "$ping_status" >&2
    exit 1
  fi

  printf 'SSM status: %s; retrying in %s seconds...\n' \
    "$ping_status" "$poll_interval" >&2
  sleep "$poll_interval"
done

command_id="$(
  aws ssm send-command \
    --region "$region" \
    --instance-ids "$instance_id" \
    --document-name AWS-RunShellScript \
    --comment 'Read WireGuard server public key after cloud-init' \
    --parameters "commands=[\"cloud-init status --wait >/dev/null && cat /etc/wireguard/server_public.key\"],executionTimeout=[\"${timeout_seconds}\"]" \
    --query 'Command.CommandId' \
    --output text
)"

printf 'Waiting for WireGuard bootstrap via SSM command %s...\n' "$command_id" >&2

while true; do
  status="$(
    aws ssm get-command-invocation \
      --region "$region" \
      --command-id "$command_id" \
      --instance-id "$instance_id" \
      --query Status \
      --output text 2>/dev/null || true
  )"

  case "$status" in
    Success | Failed | Cancelled | TimedOut | Cancelling)
      break
      ;;
  esac

  if ((SECONDS >= deadline)); then
    printf 'Timed out waiting for SSM command %s; last status: %s\n' \
      "$command_id" "$status" >&2
    exit 1
  fi

  sleep "$poll_interval"
done

if [[ "$status" != "Success" ]]; then
  aws ssm get-command-invocation \
    --region "$region" \
    --command-id "$command_id" \
    --instance-id "$instance_id" \
    --query StandardErrorContent \
    --output text >&2
  printf 'WireGuard key retrieval failed with status %s.\n' "$status" >&2
  exit 1
fi

server_public_key="$(
  aws ssm get-command-invocation \
    --region "$region" \
    --command-id "$command_id" \
    --instance-id "$instance_id" \
    --query StandardOutputContent \
    --output text | tr -d '\r\n'
)"

if [[ ! "$server_public_key" =~ ^[A-Za-z0-9+/]{43}=$ ]]; then
  printf 'SSM returned an invalid WireGuard public key.\n' >&2
  exit 1
fi

printf '%s\n' "$server_public_key"
