#!/usr/bin/env bash

set -u -o pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FOUNDATION_DIR="$ROOT_DIR/envs/dev"
ADDONS_DIR="$ROOT_DIR/envs/dev/addons"
ARGOCD_APPS_DIR="$ROOT_DIR/envs/dev/argocd-apps"

AWS_REGION="us-east-1"
CLUSTER_NAME="calculator-dev"
ARGOCD_NAMESPACE="argocd"
ARGOCD_APP_NAME="calculator-dev"
APP_NAMESPACE="calculator"
PORT_FORWARD_PORT="8080"
SKIP_PORT_FORWARD="false"
LOG_FILE="/tmp/calculator-dev-apply-$(date +%Y%m%d-%H%M%S).log"
PORT_FORWARD_LOG="/tmp/calculator-argocd-port-forward.log"
NOTIFY_EMAIL="chimnem@gmail.com"
SNS_TOPIC_NAME="${CLUSTER_NAME}-apply-notify"
TOPIC_ARN=""
BRAVE_PATH="/mnt/c/Program Files/BraveSoftware/Brave-Browser/Application/brave.exe"
LAST_JSONPATH_VALUE=""

declare -a SUMMARY_LINES=()

usage() {
  cat <<'EOF'
Usage: scripts/apply-dev.sh [options]

Options:
  --region <aws-region>          AWS region. Default: us-east-1
  --cluster-name <name>          EKS cluster name. Default: calculator-dev
  --port-forward-port <port>     Local port for ArgoCD port-forward. Default: 8080
  --notify-email <address>       Email address for the final summary. Default: chimnem@gmail.com
  --skip-port-forward            Do not start ArgoCD port-forward
  --log-file <path>              Optional log file path
  --help                         Show this message
EOF
}

log() {
  local message="$1"
  printf '[%s] %s\n' "$(date +"%Y-%m-%d %H:%M:%S")" "$message" | tee -a "$LOG_FILE"
}

record_summary() {
  SUMMARY_LINES+=("$1")
  log "$1"
}

require_command() {
  local cmd="$1"
  if ! command -v "$cmd" >/dev/null 2>&1; then
    log "Required command not found: $cmd"
    exit 1
  fi
}

run_cmd() {
  local description="$1"
  shift
  local rc=0

  log "RUN: $description"
  "$@" >>"$LOG_FILE" 2>&1
  rc=$?

  if [[ "$rc" -eq 0 ]]; then
    record_summary "OK: $description"
    return 0
  fi

  record_summary "ERROR: $description (exit $rc)"
  return "$rc"
}

terraform_apply() {
  local dir="$1"
  local label="$2"

  run_cmd "Terraform init in $label" terraform -chdir="$dir" init -reconfigure || return 1
  run_cmd "Terraform apply in $label" terraform -chdir="$dir" apply -auto-approve -lock-timeout=5m
}

wait_for_resource() {
  local description="$1"
  local attempts="$2"
  shift 2

  for _ in $(seq 1 "$attempts"); do
    if "$@" >>"$LOG_FILE" 2>&1; then
      record_summary "OK: $description"
      return 0
    fi
    sleep 5
  done

  record_summary "ERROR: Timed out waiting for $description"
  return 1
}

wait_for_jsonpath_value() {
  local description="$1"
  local attempts="$2"
  local expected="$3"
  shift 3

  local value=""
  for _ in $(seq 1 "$attempts"); do
    value="$("$@" 2>>"$LOG_FILE" || true)"
    if [[ "$value" == "$expected" ]]; then
      record_summary "OK: $description = $expected"
      return 0
    fi
    sleep 10
  done

  record_summary "ERROR: Timed out waiting for $description to become $expected (last value: ${value:-<empty>})"
  return 1
}

wait_for_nonempty_jsonpath() {
  local description="$1"
  local attempts="$2"
  shift 2

  local value=""
  for _ in $(seq 1 "$attempts"); do
    value="$("$@" 2>>"$LOG_FILE" || true)"
    if [[ -n "$value" ]]; then
      record_summary "OK: $description is available"
      LAST_JSONPATH_VALUE="$value"
      return 0
    fi
    sleep 10
  done

  record_summary "ERROR: Timed out waiting for $description"
  return 1
}

get_argocd_password() {
  kubectl -n "$ARGOCD_NAMESPACE" get secret argocd-initial-admin-secret \
    -o jsonpath='{.data.password}' 2>>"$LOG_FILE" | base64 -d
}

get_app_ingress_address() {
  kubectl -n "$APP_NAMESPACE" get ingress calculator -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>>"$LOG_FILE" || true
}

get_argocd_app_health() {
  kubectl -n "$ARGOCD_NAMESPACE" get application "$ARGOCD_APP_NAME" -o jsonpath='{.status.health.status}' 2>>"$LOG_FILE" || true
}

get_argocd_app_sync() {
  kubectl -n "$ARGOCD_NAMESPACE" get application "$ARGOCD_APP_NAME" -o jsonpath='{.status.sync.status}' 2>>"$LOG_FILE" || true
}

start_port_forward() {
  if [[ "$SKIP_PORT_FORWARD" == "true" ]]; then
    record_summary "OK: Skipped ArgoCD port-forward by request"
    return 0
  fi

  if command -v ss >/dev/null 2>&1 && ss -ltn "( sport = :${PORT_FORWARD_PORT} )" | grep -q ":${PORT_FORWARD_PORT}"; then
    record_summary "WARN: Local port ${PORT_FORWARD_PORT} is already in use; skipping port-forward"
    return 0
  fi

  log "RUN: Start ArgoCD port-forward on localhost:${PORT_FORWARD_PORT}"
  nohup kubectl -n "$ARGOCD_NAMESPACE" port-forward svc/argocd-server "${PORT_FORWARD_PORT}:443" >"$PORT_FORWARD_LOG" 2>&1 &
  local pf_pid=$!
  sleep 3

  if kill -0 "$pf_pid" >/dev/null 2>&1; then
    record_summary "OK: ArgoCD port-forward started on https://localhost:${PORT_FORWARD_PORT}"
    record_summary "OK: Port-forward PID ${pf_pid}; log file ${PORT_FORWARD_LOG}"
    return 0
  fi

  record_summary "ERROR: ArgoCD port-forward failed to start; see ${PORT_FORWARD_LOG}"
  return 1
}

open_in_brave() {
  local argocd_url="$1"
  local app_url="$2"

  if [[ ! -x "$BRAVE_PATH" ]]; then
    record_summary "WARN: Brave executable not found at ${BRAVE_PATH}; skipping browser launch"
    return 0
  fi

  log "RUN: Open Brave with ArgoCD and calculator URLs"
  "$BRAVE_PATH" --new-window "$argocd_url" "$app_url" >>"$LOG_FILE" 2>&1 &
  record_summary "OK: Brave launch requested for ${argocd_url} and ${app_url}"
}

ensure_sns_topic() {
  if [[ -n "$TOPIC_ARN" ]]; then
    return 0
  fi

  TOPIC_ARN="$(
    aws sns create-topic --region "$AWS_REGION" --name "$SNS_TOPIC_NAME" --output json 2>>"$LOG_FILE" \
      | jq -r '.TopicArn // empty'
  )"

  if [[ -z "$TOPIC_ARN" ]]; then
    record_summary "WARN: Could not create or read SNS topic ${SNS_TOPIC_NAME}"
    return 1
  fi

  record_summary "OK: SNS topic ready: ${TOPIC_ARN}"
  return 0
}

ensure_sns_subscription() {
  local subscription_arn=""

  ensure_sns_topic || return 1

  subscription_arn="$(
    aws sns list-subscriptions-by-topic --region "$AWS_REGION" --topic-arn "$TOPIC_ARN" --output json 2>>"$LOG_FILE" \
      | jq -r --arg email "$NOTIFY_EMAIL" '
          .Subscriptions[]
          | select(.Protocol == "email" and .Endpoint == $email)
          | .SubscriptionArn
        ' | head -n1
  )"

  if [[ -z "$subscription_arn" ]]; then
    run_cmd "Subscribe ${NOTIFY_EMAIL} to SNS topic ${SNS_TOPIC_NAME}" \
      aws sns subscribe --region "$AWS_REGION" --topic-arn "$TOPIC_ARN" --protocol email --notification-endpoint "$NOTIFY_EMAIL" || return 1
    subscription_arn="PendingConfirmation"
  fi

  if [[ "$subscription_arn" == "PendingConfirmation" ]]; then
    record_summary "WARN: SNS subscription for ${NOTIFY_EMAIL} is pending confirmation"
    return 1
  fi

  record_summary "OK: SNS email subscription for ${NOTIFY_EMAIL} is confirmed"
  return 0
}

publish_summary() {
  local subject="calculator-dev apply summary: SUCCESS"
  local message=""

  if ! ensure_sns_subscription; then
    log "Notification preparation failed. Summary email was not sent."
    return 1
  fi

  message="$(printf '%s\n' "${SUMMARY_LINES[@]}")"

  if aws sns publish \
    --region "$AWS_REGION" \
    --topic-arn "$TOPIC_ARN" \
    --subject "$subject" \
    --message "$message" >>"$LOG_FILE" 2>&1; then
    record_summary "OK: Summary email published through SNS"
    return 0
  fi

  record_summary "WARN: Failed to publish the summary email through SNS"
  return 1
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --region)
        AWS_REGION="$2"
        shift 2
        ;;
      --cluster-name)
        CLUSTER_NAME="$2"
        shift 2
        ;;
      --port-forward-port)
        PORT_FORWARD_PORT="$2"
        shift 2
        ;;
      --notify-email)
        NOTIFY_EMAIL="$2"
        shift 2
        ;;
      --skip-port-forward)
        SKIP_PORT_FORWARD="true"
        shift
        ;;
      --log-file)
        LOG_FILE="$2"
        shift 2
        ;;
      --help)
        usage
        exit 0
        ;;
      *)
        echo "Unknown argument: $1" >&2
        usage
        exit 1
        ;;
    esac
  done
}

main() {
  parse_args "$@"

  mkdir -p "$(dirname "$LOG_FILE")"
  : >"$LOG_FILE"

  require_command terraform
  require_command aws
  require_command kubectl
  require_command base64
  require_command nohup
  require_command jq

  log "Apply run started. Log file: $LOG_FILE"

  terraform_apply "$FOUNDATION_DIR" "foundation" || exit 1
  run_cmd "Refresh kubeconfig for ${CLUSTER_NAME}" aws eks update-kubeconfig --region "$AWS_REGION" --name "$CLUSTER_NAME" || exit 1
  terraform_apply "$ADDONS_DIR" "addons" || exit 1

  wait_for_resource "ArgoCD Application CRD" 24 kubectl get crd applications.argoproj.io || exit 1
  terraform_apply "$ARGOCD_APPS_DIR" "argocd-apps" || exit 1

  wait_for_resource "ArgoCD server service" 24 kubectl -n "$ARGOCD_NAMESPACE" get svc argocd-server || exit 1
  wait_for_jsonpath_value "ArgoCD app sync status" 36 "Synced" get_argocd_app_sync || exit 1
  wait_for_jsonpath_value "ArgoCD app health status" 36 "Healthy" get_argocd_app_health || exit 1
  start_port_forward || exit 1

  local password=""
  local app_ingress=""
  password="$(get_argocd_password || true)"
  wait_for_nonempty_jsonpath "calculator ingress hostname" 36 get_app_ingress_address || exit 1
  app_ingress="$LAST_JSONPATH_VALUE"

  if [[ -n "$password" ]]; then
    log "INFO: ArgoCD admin username: admin"
    log "INFO: ArgoCD admin password: ${password}"
    record_summary "OK: ArgoCD credentials are ready in the local log output"
  else
    record_summary "WARN: Could not read the ArgoCD initial admin password yet"
  fi

  if [[ -n "$app_ingress" ]]; then
    record_summary "OK: Calculator app URL: http://${app_ingress}"
  else
    record_summary "WARN: Calculator ingress address is not available yet"
  fi

  open_in_brave "https://localhost:${PORT_FORWARD_PORT}" "http://${app_ingress}" || true
  publish_summary || true

  log "Apply run finished."
}

main "$@"
