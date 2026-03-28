#!/usr/bin/env bash

set -u -o pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ADDONS_DIR="$ROOT_DIR/envs/dev/addons"
ARGOCD_APPS_DIR="$ROOT_DIR/envs/dev/argocd-apps"
FOUNDATION_DIR="$ROOT_DIR/envs/dev"
BOOTSTRAP_DIR="$ROOT_DIR/bootstrap"

AWS_REGION="us-east-1"
CLUSTER_NAME="calculator-dev"
APP_NAMESPACE="calculator"
ARGOCD_NAMESPACE="argocd"
ARGOCD_APP_NAME="calculator-dev"
NOTIFY_EMAIL="chimnem@gmail.com"
SCOPE="dev-addons"
LOG_FILE="/tmp/calculator-dev-destroy-$(date +%Y%m%d-%H%M%S).log"
SNS_TOPIC_NAME="${CLUSTER_NAME}-destroy-notify"
LOCK_STALE_AFTER_MINUTES=15
SECURITY_GROUP_DELETE_RETRIES=18
SECURITY_GROUP_DELETE_SLEEP_SECONDS=10

STARTED_AT="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
OVERALL_STATUS="SUCCESS"
NOTIFICATION_STATUS="NOT_ATTEMPTED"
TOPIC_ARN=""

declare -a SUMMARY_LINES=()

usage() {
  cat <<'EOF'
Usage: scripts/destroy-dev.sh [options]

Options:
  --notify-email <address>   Email address for the final summary. Default: chimnem@gmail.com
  --region <aws-region>      AWS region. Default: us-east-1
  --cluster-name <name>      EKS cluster name. Default: calculator-dev
  --scope <dev-addons|all>   Destroy dev+addons or include bootstrap too. Default: dev-addons
  --log-file <path>          Optional log file path
  --help                     Show this message

Notes:
  If you monitor the run with `tail -f /tmp/destroy-dev.out`, it is safe to stop `tail`
  with Ctrl+C after you see `Destroy run finished with status ...`.
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

mark_failed() {
  OVERALL_STATUS="FAILED"
  record_summary "FAILED: $1"
}

require_command() {
  local cmd="$1"
  if ! command -v "$cmd" >/dev/null 2>&1; then
    mark_failed "Required command not found: $cmd"
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

terraform_state_list() {
  local dir="$1"
  terraform -chdir="$dir" state list -no-color 2>>"$LOG_FILE" || true
}

terraform_state_rm_if_present() {
  local dir="$1"
  local address="$2"
  local state_entries

  state_entries="$(terraform_state_list "$dir")"
  if printf '%s\n' "$state_entries" | grep -Fx "$address" >/dev/null 2>&1; then
    run_cmd "Remove state entry $address" terraform -chdir="$dir" state rm -no-color "$address"
  fi
}

terraform_state_has_entries() {
  local dir="$1"
  local state_entries

  state_entries="$(terraform_state_list "$dir")"
  [[ -n "$state_entries" ]]
}

terraform_lock_error_present() {
  local output_file="$1"
  grep -F "Error acquiring the state lock" "$output_file" >/dev/null 2>&1
}

extract_terraform_lock_field() {
  local output_file="$1"
  local field_name="$2"

  sed -n "s/^  ${field_name}: *//p" "$output_file" | head -n 1
}

other_terraform_processes_running() {
  ps -eo pid=,args= | awk -v current_pid="$$" '$1 != current_pid && $0 ~ /[t]erraform/ { found = 1 } END { exit found ? 0 : 1 }'
}

lock_is_stale_enough() {
  local created_at="$1"
  local created_epoch
  local now_epoch
  local age_minutes

  [[ -n "$created_at" ]] || return 1

  created_epoch="$(date -d "$created_at" +%s 2>/dev/null)" || return 1
  now_epoch="$(date -u +%s)"
  age_minutes="$(( (now_epoch - created_epoch) / 60 ))"

  [[ "$age_minutes" -ge "$LOCK_STALE_AFTER_MINUTES" ]]
}

terraform_force_unlock_if_safe() {
  local dir="$1"
  local label="$2"
  local output_file="$3"
  local lock_id
  local lock_who
  local lock_created

  lock_id="$(extract_terraform_lock_field "$output_file" "ID")"
  lock_who="$(extract_terraform_lock_field "$output_file" "Who")"
  lock_created="$(extract_terraform_lock_field "$output_file" "Created")"

  if [[ -z "$lock_id" ]]; then
    record_summary "WARN: Could not parse Terraform lock ID for $label"
    return 1
  fi

  if other_terraform_processes_running; then
    record_summary "WARN: Terraform lock for $label was left in place because another local Terraform process is running"
    return 1
  fi

  if ! lock_is_stale_enough "$lock_created"; then
    record_summary "WARN: Terraform lock for $label is not old enough for auto-unlock"
    return 1
  fi

  record_summary "WARN: Auto-unlocking stale Terraform lock ${lock_id} for ${label} (owner: ${lock_who:-unknown}, created: ${lock_created:-unknown})"
  run_cmd "Force-unlock Terraform state in ${label}" terraform -chdir="$dir" force-unlock -force -no-color "$lock_id"
}

foundation_vpc_id() {
  local vpc_id=""

  vpc_id="$(terraform -chdir="$FOUNDATION_DIR" output -no-color -raw vpc_id 2>>"$LOG_FILE" || true)"
  if [[ -n "$vpc_id" ]]; then
    printf '%s\n' "$vpc_id"
    return 0
  fi

  if cluster_exists; then
    vpc_id="$(aws eks describe-cluster --name "$CLUSTER_NAME" --region "$AWS_REGION" --query 'cluster.resourcesVpcConfig.vpcId' --output text 2>>"$LOG_FILE" || true)"
  fi

  if [[ -n "$vpc_id" && "$vpc_id" != "None" ]]; then
    printf '%s\n' "$vpc_id"
    return 0
  fi

  return 1
}

terraform_destroy_with_lock_recovery() {
  local dir="$1"
  local label="$2"
  shift 2
  local output_file
  local rc=0
  local recovered="false"

  run_cmd "Terraform init in $label" terraform -chdir="$dir" init -no-color -reconfigure || return 1

  output_file="$(mktemp)"

  while true; do
    log "RUN: Terraform destroy in $label"
    terraform -chdir="$dir" destroy -no-color -auto-approve -lock-timeout=5m "$@" >"$output_file" 2>&1
    rc=$?
    cat "$output_file" >>"$LOG_FILE"

    if [[ "$rc" -eq 0 ]]; then
      if [[ "$recovered" == "true" ]]; then
        record_summary "OK: Terraform destroy in $label after stale lock recovery"
      else
        record_summary "OK: Terraform destroy in $label"
      fi
      rm -f "$output_file"
      return 0
    fi

    if [[ "$recovered" == "false" ]] && terraform_lock_error_present "$output_file"; then
      if terraform_force_unlock_if_safe "$dir" "$label" "$output_file"; then
        recovered="true"
        : >"$output_file"
        continue
      fi
    fi

    if [[ "$recovered" == "true" ]]; then
      record_summary "ERROR: Terraform destroy in $label after stale lock recovery (exit $rc)"
    else
      record_summary "ERROR: Terraform destroy in $label (exit $rc)"
    fi
    rm -f "$output_file"
    return "$rc"
  done
}

terraform_destroy() {
  local dir="$1"
  local label="$2"

  terraform_destroy_with_lock_recovery "$dir" "$label"
}

terraform_destroy_foundation_preserve_ecr() {
  local dir="$1"
  local label="$2"

  terraform_destroy_with_lock_recovery "$dir" "$label while preserving ECR" \
    -target=module.github_oidc \
    -target=module.eks \
    -target=module.vpc
}

cluster_exists() {
  aws eks describe-cluster --name "$CLUSTER_NAME" --region "$AWS_REGION" >/dev/null 2>>"$LOG_FILE"
}

wait_for_namespace_gone() {
  local namespace="$1"
  local attempts=18

  for _ in $(seq 1 "$attempts"); do
    if ! kubectl get namespace "$namespace" >/dev/null 2>>"$LOG_FILE"; then
      return 0
    fi
    sleep 10
  done

  return 1
}

force_finalize_namespace() {
  local namespace="$1"
  local raw_file
  local patched_file

  raw_file="$(mktemp)"
  patched_file="$(mktemp)"

  if ! kubectl get namespace "$namespace" -o json >"$raw_file" 2>>"$LOG_FILE"; then
    rm -f "$raw_file" "$patched_file"
    return 0
  fi

  if ! jq '.spec.finalizers = []' "$raw_file" >"$patched_file"; then
    rm -f "$raw_file" "$patched_file"
    return 1
  fi

  run_cmd "Force finalize namespace $namespace" \
    kubectl replace --raw "/api/v1/namespaces/${namespace}/finalize" -f "$patched_file"

  rm -f "$raw_file" "$patched_file"
}

delete_namespace_aggressively() {
  local namespace="$1"

  if ! kubectl get namespace "$namespace" >/dev/null 2>>"$LOG_FILE"; then
    record_summary "OK: Namespace $namespace is already absent"
    return 0
  fi

  run_cmd "Delete namespace $namespace" kubectl delete namespace "$namespace" --ignore-not-found=true --wait=false || true

  if wait_for_namespace_gone "$namespace"; then
    record_summary "OK: Namespace $namespace was deleted"
    return 0
  fi

  log "Namespace $namespace is still present; forcing finalizer cleanup."
  force_finalize_namespace "$namespace" || true

  if wait_for_namespace_gone "$namespace"; then
    record_summary "OK: Namespace $namespace was force-deleted"
    return 0
  fi

  record_summary "WARN: Namespace $namespace still exists after aggressive cleanup"
  return 1
}

delete_argocd_application_if_present() {
  if ! kubectl get crd applications.argoproj.io >/dev/null 2>>"$LOG_FILE"; then
    record_summary "OK: ArgoCD application CRD is already absent"
    return 0
  fi

  run_cmd "Delete ArgoCD Application ${ARGOCD_APP_NAME}" \
    kubectl delete application "$ARGOCD_APP_NAME" -n "$ARGOCD_NAMESPACE" --ignore-not-found=true
}

uninstall_helm_if_present() {
  local release_name="$1"
  local namespace="$2"

  if helm status "$release_name" -n "$namespace" >/dev/null 2>>"$LOG_FILE"; then
    run_cmd "Helm uninstall ${release_name} from ${namespace}" \
      helm uninstall "$release_name" -n "$namespace"
  else
    record_summary "OK: Helm release ${release_name} is already absent in ${namespace}"
  fi
}

delete_argocd_crds() {
  local crd

  for crd in applications.argoproj.io applicationsets.argoproj.io appprojects.argoproj.io; do
    if kubectl get crd "$crd" >/dev/null 2>>"$LOG_FILE"; then
      run_cmd "Delete CRD ${crd}" kubectl delete crd "$crd" --ignore-not-found=true || true
    else
      record_summary "OK: CRD ${crd} is already absent"
    fi
  done
}

find_tagged_elbv2_load_balancers() {
  local arn

  aws elbv2 describe-load-balancers --region "$AWS_REGION" --output json 2>>"$LOG_FILE" \
    | jq -r '.LoadBalancers[].LoadBalancerArn'
}

elbv2_has_cluster_tag() {
  local resource_arn="$1"

  aws elbv2 describe-tags --region "$AWS_REGION" --resource-arns "$resource_arn" --output json 2>>"$LOG_FILE" \
    | jq -e --arg cluster "$CLUSTER_NAME" '
        any(.TagDescriptions[].Tags[]?;
          (.Key == "elbv2.k8s.aws/cluster" and .Value == $cluster)
          or (.Key == ("kubernetes.io/cluster/" + $cluster))
        )
      ' >/dev/null
}

delete_tagged_elbv2_load_balancers() {
  local arn
  local found="false"

  while IFS= read -r arn; do
    [[ -n "$arn" ]] || continue

    if elbv2_has_cluster_tag "$arn"; then
      found="true"
      run_cmd "Delete ELBv2 load balancer ${arn}" \
        aws elbv2 delete-load-balancer --region "$AWS_REGION" --load-balancer-arn "$arn" || true
      run_cmd "Wait for ELBv2 load balancer ${arn} deletion" \
        aws elbv2 wait load-balancers-deleted --region "$AWS_REGION" --load-balancer-arns "$arn" || true
    fi
  done < <(find_tagged_elbv2_load_balancers)

  if [[ "$found" == "false" ]]; then
    record_summary "OK: No tagged ELBv2 load balancers were found"
  fi
}

find_tagged_elbv2_target_groups() {
  aws elbv2 describe-target-groups --region "$AWS_REGION" --output json 2>>"$LOG_FILE" \
    | jq -r '.TargetGroups[].TargetGroupArn'
}

elbv2_target_group_has_cluster_tag() {
  local resource_arn="$1"

  aws elbv2 describe-tags --region "$AWS_REGION" --resource-arns "$resource_arn" --output json 2>>"$LOG_FILE" \
    | jq -e --arg cluster "$CLUSTER_NAME" '
        any(.TagDescriptions[].Tags[]?;
          (.Key == "elbv2.k8s.aws/cluster" and .Value == $cluster)
          or (.Key == ("kubernetes.io/cluster/" + $cluster))
        )
      ' >/dev/null
}

delete_tagged_elbv2_target_groups() {
  local arn
  local found="false"

  while IFS= read -r arn; do
    [[ -n "$arn" ]] || continue

    if elbv2_target_group_has_cluster_tag "$arn"; then
      found="true"
      run_cmd "Delete ELBv2 target group ${arn}" \
        aws elbv2 delete-target-group --region "$AWS_REGION" --target-group-arn "$arn" || true
    fi
  done < <(find_tagged_elbv2_target_groups)

  if [[ "$found" == "false" ]]; then
    record_summary "OK: No tagged ELBv2 target groups were found"
  fi
}

find_classic_elbs() {
  aws elb describe-load-balancers --region "$AWS_REGION" --output json 2>>"$LOG_FILE" \
    | jq -r '.LoadBalancerDescriptions[].LoadBalancerName'
}

classic_elb_has_cluster_tag() {
  local load_balancer_name="$1"

  aws elb describe-tags --region "$AWS_REGION" --load-balancer-names "$load_balancer_name" --output json 2>>"$LOG_FILE" \
    | jq -e --arg cluster "$CLUSTER_NAME" '
        any(.TagDescriptions[].Tags[]?;
          (.Key == ("kubernetes.io/cluster/" + $cluster))
        )
      ' >/dev/null
}

delete_tagged_classic_elbs() {
  local name
  local found="false"

  while IFS= read -r name; do
    [[ -n "$name" ]] || continue

    if classic_elb_has_cluster_tag "$name"; then
      found="true"
      run_cmd "Delete classic ELB ${name}" \
        aws elb delete-load-balancer --region "$AWS_REGION" --load-balancer-name "$name" || true
    fi
  done < <(find_classic_elbs)

  if [[ "$found" == "false" ]]; then
    record_summary "OK: No tagged classic ELBs were found"
  fi
}

security_group_exists() {
  local group_id="$1"

  aws ec2 describe-security-groups --region "$AWS_REGION" --group-ids "$group_id" >/dev/null 2>>"$LOG_FILE"
}

find_network_interfaces_for_security_group() {
  local group_id="$1"

  aws ec2 describe-network-interfaces \
    --region "$AWS_REGION" \
    --filters "Name=group-id,Values=${group_id}" \
    --output json 2>>"$LOG_FILE" \
    | jq -r '.NetworkInterfaces[].NetworkInterfaceId'
}

find_security_group_rule_references() {
  local group_id="$1"

  aws ec2 describe-security-group-rules --region "$AWS_REGION" --output json 2>>"$LOG_FILE" \
    | jq -r --arg group_id "$group_id" '
        .SecurityGroupRules[]
        | select(.ReferencedGroupInfo.GroupId? == $group_id)
        | [.GroupId, (if .IsEgress then "egress" else "ingress" end), .SecurityGroupRuleId]
        | @tsv
      '
}

revoke_security_group_rule_reference() {
  local owner_group_id="$1"
  local direction="$2"
  local rule_id="$3"

  if [[ "$direction" == "egress" ]]; then
    run_cmd "Revoke egress security group rule ${rule_id} from ${owner_group_id}" \
      aws ec2 revoke-security-group-egress \
        --region "$AWS_REGION" \
        --group-id "$owner_group_id" \
        --security-group-rule-ids "$rule_id"
    return
  fi

  run_cmd "Revoke ingress security group rule ${rule_id} from ${owner_group_id}" \
    aws ec2 revoke-security-group-ingress \
      --region "$AWS_REGION" \
      --group-id "$owner_group_id" \
      --security-group-rule-ids "$rule_id"
}

cleanup_security_group_rule_references() {
  local group_id="$1"
  local owner_group_id
  local direction
  local rule_id
  local found="false"

  while IFS=$'\t' read -r owner_group_id direction rule_id; do
    [[ -n "$rule_id" ]] || continue
    found="true"
    revoke_security_group_rule_reference "$owner_group_id" "$direction" "$rule_id" || true
  done < <(find_security_group_rule_references "$group_id")

  if [[ "$found" == "false" ]]; then
    log "No security group rules reference ${group_id}."
  fi
}

delete_security_group_with_retries() {
  local group_id="$1"
  local attempt
  local interfaces
  local rule_refs

  for attempt in $(seq 1 "$SECURITY_GROUP_DELETE_RETRIES"); do
    if ! security_group_exists "$group_id"; then
      record_summary "OK: Load-balancer-controller security group ${group_id} is already absent"
      return 0
    fi

    cleanup_security_group_rule_references "$group_id"

    if run_cmd "Delete load-balancer-controller security group ${group_id} (attempt ${attempt}/${SECURITY_GROUP_DELETE_RETRIES})" \
      aws ec2 delete-security-group --region "$AWS_REGION" --group-id "$group_id"; then
      return 0
    fi

    if ! security_group_exists "$group_id"; then
      record_summary "OK: Load-balancer-controller security group ${group_id} is already absent"
      return 0
    fi

    interfaces="$(find_network_interfaces_for_security_group "$group_id" | paste -sd ',' -)"
    rule_refs="$(find_security_group_rule_references "$group_id" | cut -f3 | paste -sd ',' -)"

    if [[ -n "$interfaces" ]]; then
      log "Security group ${group_id} is still attached to ENIs: ${interfaces}"
    fi

    if [[ -n "$rule_refs" ]]; then
      log "Security group ${group_id} is still referenced by security group rules: ${rule_refs}"
    fi

    if [[ "$attempt" -lt "$SECURITY_GROUP_DELETE_RETRIES" ]]; then
      log "Retrying security group ${group_id} deletion in ${SECURITY_GROUP_DELETE_SLEEP_SECONDS}s."
      sleep "$SECURITY_GROUP_DELETE_SLEEP_SECONDS"
    fi
  done

  record_summary "WARN: Security group ${group_id} still exists after ${SECURITY_GROUP_DELETE_RETRIES} delete attempts"
  return 1
}

delete_controller_security_groups() {
  local group_id
  local vpc_id=""
  local found="false"

  vpc_id="$(foundation_vpc_id || true)"

  if [[ -z "$vpc_id" || "$vpc_id" == "None" ]]; then
    record_summary "OK: No VPC ID available for security group sweep"
    return 0
  fi

  while IFS= read -r group_id; do
    [[ -n "$group_id" ]] || continue
    found="true"
    delete_security_group_with_retries "$group_id" || true
  done < <(
    aws ec2 describe-security-groups \
      --region "$AWS_REGION" \
      --filters "Name=vpc-id,Values=${vpc_id}" \
      --output json 2>>"$LOG_FILE" \
      | jq -r --arg cluster "$CLUSTER_NAME" '
          .SecurityGroups[]
          | select(
              any(.Tags[]?;
                (.Key == "elbv2.k8s.aws/cluster" and .Value == $cluster)
              )
            )
          | .GroupId
        '
  )

  if [[ "$found" == "false" ]]; then
    record_summary "OK: No load-balancer-controller security groups were found"
  fi
}

sweep_costly_aws_leftovers() {
  log "Starting targeted AWS cleanup sweep for cost-bearing leftovers."
  delete_tagged_classic_elbs
  delete_tagged_elbv2_load_balancers
  delete_tagged_elbv2_target_groups
  delete_controller_security_groups
  delete_tagged_elbv2_target_groups
  delete_controller_security_groups
}

remove_module_eks_state() {
  local address
  local removed_any="false"

  while IFS= read -r address; do
    [[ -n "$address" ]] || continue

    if [[ "$address" == module.eks* ]]; then
      removed_any="true"
      run_cmd "Remove state entry ${address}" terraform -chdir="$FOUNDATION_DIR" state rm "$address" || true
    fi
  done < <(terraform_state_list "$FOUNDATION_DIR")

  if [[ "$removed_any" == "false" ]]; then
    record_summary "OK: No module.eks state entries needed removal"
  fi
}

manual_eks_cleanup() {
  local nodegroup
  local cluster_present="false"

  if cluster_exists; then
    cluster_present="true"
  fi

  if [[ "$cluster_present" == "false" ]]; then
    record_summary "OK: EKS cluster ${CLUSTER_NAME} is already absent"
    return 0
  fi

  while IFS= read -r nodegroup; do
    [[ -n "$nodegroup" ]] || continue
    run_cmd "Delete EKS node group ${nodegroup}" \
      aws eks delete-nodegroup --region "$AWS_REGION" --cluster-name "$CLUSTER_NAME" --nodegroup-name "$nodegroup" || true
    run_cmd "Wait for EKS node group ${nodegroup} deletion" \
      aws eks wait nodegroup-deleted --region "$AWS_REGION" --cluster-name "$CLUSTER_NAME" --nodegroup-name "$nodegroup" || true
  done < <(
    aws eks list-nodegroups --region "$AWS_REGION" --cluster-name "$CLUSTER_NAME" --output json 2>>"$LOG_FILE" \
      | jq -r '.nodegroups[]?'
  )

  run_cmd "Delete EKS cluster ${CLUSTER_NAME}" \
    aws eks delete-cluster --region "$AWS_REGION" --name "$CLUSTER_NAME" || true

  run_cmd "Wait for EKS cluster ${CLUSTER_NAME} deletion" \
    aws eks wait cluster-deleted --region "$AWS_REGION" --name "$CLUSTER_NAME" || true

  if ! cluster_exists; then
    remove_module_eks_state
    record_summary "OK: Manual EKS cleanup removed the cluster"
    return 0
  fi

  record_summary "WARN: Manual EKS cleanup did not fully remove the cluster"
  return 1
}

addons_fallback_cleanup() {
  log "Starting aggressive addons fallback cleanup."

  delete_argocd_application_if_present || true
  delete_namespace_aggressively "$APP_NAMESPACE" || true
  sweep_costly_aws_leftovers
  uninstall_helm_if_present "aws-load-balancer-controller" "kube-system" || true
  uninstall_helm_if_present "argocd" "$ARGOCD_NAMESPACE" || true
  delete_namespace_aggressively "$ARGOCD_NAMESPACE" || true
  delete_argocd_crds

  terraform_state_rm_if_present "$ADDONS_DIR" "helm_release.argocd"
  terraform_state_rm_if_present "$ADDONS_DIR" "helm_release.aws_load_balancer_controller"
}

argocd_apps_fallback_cleanup() {
  log "Starting ArgoCD apps fallback cleanup."

  delete_argocd_application_if_present || true
  terraform_state_rm_if_present "$ARGOCD_APPS_DIR" "kubernetes_manifest.calculator_dev_application"
}

verify_argocd_apps_destroyed() {
  local leftovers=""

  leftovers="$(terraform_state_list "$ARGOCD_APPS_DIR")"
  if [[ -z "$leftovers" ]]; then
    record_summary "OK: ArgoCD apps Terraform state is empty"
    return 0
  fi

  record_summary "WARN: ArgoCD apps Terraform state still has entries"
  printf '%s\n' "$leftovers" >>"$LOG_FILE"
  return 1
}

verify_addons_destroyed() {
  local leftovers=""

  leftovers="$(terraform_state_list "$ADDONS_DIR")"
  if [[ -z "$leftovers" ]]; then
    record_summary "OK: Addons Terraform state is empty"
    return 0
  fi

  record_summary "WARN: Addons Terraform state still has entries"
  printf '%s\n' "$leftovers" >>"$LOG_FILE"
  return 1
}

verify_foundation_destroyed() {
  local leftovers=""
  local unexpected=""

  leftovers="$(terraform_state_list "$FOUNDATION_DIR")"
  if [[ -n "$leftovers" ]]; then
    unexpected="$(printf '%s\n' "$leftovers" | grep -Ev '^(module\.ecr\.|data\.)' || true)"

    if [[ -n "$unexpected" ]]; then
      record_summary "WARN: Foundation Terraform state still has non-ECR entries"
      printf '%s\n' "$unexpected" >>"$LOG_FILE"
      return 1
    fi

    record_summary "OK: Foundation Terraform state only keeps ECR entries"
  fi

  if cluster_exists; then
    record_summary "WARN: EKS cluster ${CLUSTER_NAME} still exists"
    return 1
  fi

  record_summary "OK: Foundation destroy preserved ECR and removed the EKS cluster"
  return 0
}

verify_bootstrap_destroyed() {
  local leftovers=""

  leftovers="$(terraform_state_list "$BOOTSTRAP_DIR")"
  if [[ -n "$leftovers" ]]; then
    record_summary "WARN: Bootstrap Terraform state still has entries"
    printf '%s\n' "$leftovers" >>"$LOG_FILE"
    return 1
  fi

  record_summary "OK: Bootstrap Terraform state is empty"
  return 0
}

ensure_sns_topic() {
  if [[ -n "$TOPIC_ARN" ]]; then
    return 0
  fi

  TOPIC_ARN="$(
    aws sns create-topic --region "$AWS_REGION" --name "$SNS_TOPIC_NAME" --output json 2>>"$LOG_FILE" \
      | jq -r '.TopicArn // empty'
  )"

  [[ -n "$TOPIC_ARN" ]]
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
        ' | head -n 1
  )"

  if [[ -z "$subscription_arn" ]]; then
    run_cmd "Subscribe ${NOTIFY_EMAIL} to SNS topic ${SNS_TOPIC_NAME}" \
      aws sns subscribe --region "$AWS_REGION" --topic-arn "$TOPIC_ARN" --protocol email --notification-endpoint "$NOTIFY_EMAIL" || return 1
    NOTIFICATION_STATUS="PENDING_CONFIRMATION"
    return 0
  fi

  if [[ "$subscription_arn" == "PendingConfirmation" ]]; then
    NOTIFICATION_STATUS="PENDING_CONFIRMATION"
  else
    NOTIFICATION_STATUS="READY"
  fi

  return 0
}

publish_summary() {
  local finished_at
  local body
  local subject

  if ! ensure_sns_subscription; then
    NOTIFICATION_STATUS="FAILED_TO_PREPARE"
    log "Notification preparation failed. Summary email was not sent."
    return 1
  fi

  finished_at="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
  body="$(
    {
      printf 'Destroy summary for %s\n\n' "$CLUSTER_NAME"
      printf 'Status: %s\n' "$OVERALL_STATUS"
      printf 'Region: %s\n' "$AWS_REGION"
      printf 'Scope: %s\n' "$SCOPE"
      printf 'Started at: %s\n' "$STARTED_AT"
      printf 'Finished at: %s\n' "$finished_at"
      printf 'Log file: %s\n' "$LOG_FILE"
      printf 'Notification status: %s\n' "$NOTIFICATION_STATUS"
      printf '\nActions:\n'
      printf '%s\n' "${SUMMARY_LINES[@]}"
    }
  )"
  subject="calculator dev destroy: ${OVERALL_STATUS}"

  if [[ "$NOTIFICATION_STATUS" == "PENDING_CONFIRMATION" ]]; then
    log "SNS subscription for ${NOTIFY_EMAIL} is pending confirmation. Summary email cannot be delivered yet."
    return 0
  fi

  if aws sns publish \
    --region "$AWS_REGION" \
    --topic-arn "$TOPIC_ARN" \
    --subject "$subject" \
    --message "$body" >>"$LOG_FILE" 2>&1; then
    NOTIFICATION_STATUS="SENT"
    log "Summary email was published through SNS."
    return 0
  fi

  NOTIFICATION_STATUS="FAILED_TO_SEND"
  log "Failed to publish the summary email through SNS."
  return 1
}

finish() {
  local exit_code="$1"

  if [[ "$exit_code" -ne 0 ]]; then
    OVERALL_STATUS="FAILED"
  fi

  publish_summary || true
  log "Destroy run finished with status ${OVERALL_STATUS}. Full log: ${LOG_FILE}"
  log "If you are following the log with tail -f, you can stop tail safely with Ctrl+C now."
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --notify-email)
        [[ $# -ge 2 ]] || {
          printf 'Missing value for %s\n' "$1" >&2
          exit 1
        }
        NOTIFY_EMAIL="$2"
        shift 2
        ;;
      --region)
        [[ $# -ge 2 ]] || {
          printf 'Missing value for %s\n' "$1" >&2
          exit 1
        }
        AWS_REGION="$2"
        shift 2
        ;;
      --cluster-name)
        [[ $# -ge 2 ]] || {
          printf 'Missing value for %s\n' "$1" >&2
          exit 1
        }
        CLUSTER_NAME="$2"
        SNS_TOPIC_NAME="${CLUSTER_NAME}-destroy-notify"
        shift 2
        ;;
      --scope)
        [[ $# -ge 2 ]] || {
          printf 'Missing value for %s\n' "$1" >&2
          exit 1
        }
        SCOPE="$2"
        shift 2
        ;;
      --log-file)
        [[ $# -ge 2 ]] || {
          printf 'Missing value for %s\n' "$1" >&2
          exit 1
        }
        LOG_FILE="$2"
        shift 2
        ;;
      --help)
        usage
        exit 0
        ;;
      *)
        printf 'Unknown argument: %s\n\n' "$1" >&2
        usage >&2
        exit 1
        ;;
    esac
  done

  if [[ "$SCOPE" != "dev-addons" && "$SCOPE" != "all" ]]; then
    printf 'Unsupported scope: %s\n' "$SCOPE" >&2
    exit 1
  fi
}

main() {
  parse_args "$@"
  trap 'finish $?' EXIT

  mkdir -p "$(dirname "$LOG_FILE")"
  : >"$LOG_FILE"

  require_command terraform
  require_command aws
  require_command kubectl
  require_command helm
  require_command jq

  record_summary "INFO: Starting aggressive destroy flow for ${CLUSTER_NAME}"
  run_cmd "Validate AWS credentials" aws sts get-caller-identity --region "$AWS_REGION" || {
    mark_failed "AWS credentials validation failed"
    exit 1
  }

  if terraform_state_has_entries "$ARGOCD_APPS_DIR"; then
    if ! terraform_destroy "$ARGOCD_APPS_DIR" "envs/dev/argocd-apps"; then
      record_summary "WARN: ArgoCD apps destroy failed on the first attempt, switching to fallback cleanup"
      argocd_apps_fallback_cleanup

      if ! terraform_destroy "$ARGOCD_APPS_DIR" "envs/dev/argocd-apps after fallback"; then
        mark_failed "ArgoCD apps destroy still failed after fallback cleanup"
      fi
    fi
  else
    record_summary "OK: ArgoCD apps Terraform state is already empty"
  fi

  verify_argocd_apps_destroyed || mark_failed "Final verification found remaining ArgoCD app resources"

  if terraform_state_has_entries "$ADDONS_DIR"; then
    if ! terraform_destroy "$ADDONS_DIR" "envs/dev/addons"; then
      record_summary "WARN: Addons destroy failed on the first attempt, switching to aggressive fallback cleanup"
      addons_fallback_cleanup

      if ! terraform_destroy "$ADDONS_DIR" "envs/dev/addons after fallback"; then
        mark_failed "Addons destroy still failed after fallback cleanup"
      fi
    fi
  else
    record_summary "OK: Addons Terraform state is already empty"
  fi

  verify_addons_destroyed || mark_failed "Final verification found remaining addons resources"
  sweep_costly_aws_leftovers

  if ! terraform_destroy_foundation_preserve_ecr "$FOUNDATION_DIR" "envs/dev"; then
    record_summary "WARN: Foundation destroy failed on the first attempt, retrying after targeted AWS cleanup"
    sweep_costly_aws_leftovers

    if ! terraform_destroy_foundation_preserve_ecr "$FOUNDATION_DIR" "envs/dev retry"; then
      record_summary "WARN: Foundation destroy still failed, switching to manual EKS cleanup"
      manual_eks_cleanup || true
      sweep_costly_aws_leftovers

      if ! terraform_destroy_foundation_preserve_ecr "$FOUNDATION_DIR" "envs/dev after manual EKS cleanup"; then
        mark_failed "Foundation destroy still failed after manual EKS cleanup"
      fi
    fi
  fi

  if [[ "$SCOPE" == "all" ]]; then
    if ! terraform_destroy "$BOOTSTRAP_DIR" "bootstrap"; then
      mark_failed "Bootstrap destroy failed"
    fi
    verify_bootstrap_destroyed || mark_failed "Final verification found remaining bootstrap resources"
  fi

  verify_foundation_destroyed || mark_failed "Final verification found remaining foundation resources"

  if [[ "$OVERALL_STATUS" == "FAILED" ]]; then
    exit 1
  fi
}

main "$@"
