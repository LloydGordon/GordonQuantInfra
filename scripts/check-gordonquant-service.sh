#!/usr/bin/env bash
set -euo pipefail

instance_id=""
region="us-east-1"
service_port="5000"
timeout_seconds="900"
poll_interval="10"

usage() {
  cat <<'USAGE'
Usage: check-gordonquant-service.sh --instance-id ID [options]

Wait for a GordonQuant EC2 instance to register with SSM, then verify
cloud-init, Docker, the deployed container, and the local health endpoint.

Options:
  --region REGION       AWS region (default: us-east-1)
  --service-port PORT   Local GordonQuant port (default: 5000)
  --timeout SECONDS     Maximum wait for SSM and the command (default: 900)
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
    --service-port)
      service_port="$2"
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

if [[ ! "$service_port" =~ ^[0-9]+$ ]] || ((service_port < 1 || service_port > 65535)); then
  printf 'Invalid service port: %s\n' "$service_port" >&2
  exit 2
fi

if [[ ! "$timeout_seconds" =~ ^[0-9]+$ ]] || ((timeout_seconds < 1)); then
  printf 'Invalid timeout: %s\n' "$timeout_seconds" >&2
  exit 2
fi

deadline=$((SECONDS + timeout_seconds))
printf 'Waiting up to %s seconds for %s to register with SSM in %s...\n' \
  "$timeout_seconds" "$instance_id" "$region"

while true; do
  ping_status="$(
    aws ssm describe-instance-information \
      --region "$region" \
      --filters "Key=InstanceIds,Values=$instance_id" \
      --query 'InstanceInformationList[0].PingStatus' \
      --output text
  )"

  if [[ "$ping_status" == "Online" ]]; then
    printf 'SSM is online for %s.\n' "$instance_id"
    break
  fi

  if ((SECONDS >= deadline)); then
    printf 'Timed out waiting for SSM on %s; last status: %s\n' \
      "$instance_id" "$ping_status" >&2
    exit 1
  fi

  printf 'SSM status: %s; retrying in %s seconds...\n' "$ping_status" "$poll_interval"
  sleep "$poll_interval"
done

parameters_file="$(mktemp)"
cleanup() {
  rm -f "$parameters_file"
}
trap cleanup EXIT

cat >"$parameters_file" <<EOF
{
  "commands": [
    "set -e",
    "cloud-init status --wait",
    "cloud-init status --long",
    "systemctl status amazon-ssm-agent docker --no-pager",
    "docker ps --all",
    "docker logs --tail 100 gordonquant",
    "cat /opt/gordonquant/deployed-tag",
    "curl --fail --silent --show-error http://127.0.0.1:${service_port}/healthz"
  ],
  "executionTimeout": ["${timeout_seconds}"]
}
EOF

command_id="$(
  aws ssm send-command \
    --region "$region" \
    --instance-ids "$instance_id" \
    --document-name AWS-RunShellScript \
    --comment 'Verify GordonQuant service' \
    --parameters "file://$parameters_file" \
    --query 'Command.CommandId' \
    --output text
)"

printf 'Running verification command %s...\n' "$command_id"
deadline=$((SECONDS + timeout_seconds))

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

  printf 'Verification status: %s; retrying in %s seconds...\n' \
    "${status:-not-yet-visible}" "$poll_interval"
  sleep "$poll_interval"
done

printf '\n--- remote stdout ---\n'
aws ssm get-command-invocation \
  --region "$region" \
  --command-id "$command_id" \
  --instance-id "$instance_id" \
  --query StandardOutputContent \
  --output text

printf '\n--- remote stderr ---\n' >&2
aws ssm get-command-invocation \
  --region "$region" \
  --command-id "$command_id" \
  --instance-id "$instance_id" \
  --query StandardErrorContent \
  --output text >&2

if [[ "$status" != "Success" ]]; then
  printf 'GordonQuant verification failed with status %s.\n' "$status" >&2
  exit 1
fi

printf 'GordonQuant verification succeeded on %s.\n' "$instance_id"
