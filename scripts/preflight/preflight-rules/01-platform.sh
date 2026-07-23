#!/bin/bash

# $Id$
# #ident "$Source$ $Revision$"
#
# VT50-2000-2016-84-28-4
# Copyright (c) 2025 Arctera US LLC. All rights reserved.
# Arctera and the Arctera Logo are trademarks or registered trademarks
# of Arctera US LLC or its affiliates in the U.S. and other countries.
# Other names may be trademarks of their respective owners.
#
# THIS SOFTWARE CONTAINS CONFIDENTIAL INFORMATION AND TRADE SECRETS OF ARCTERA US,
# LLC. USE, DISCLOSURE OR REPRODUCTION IS PROHIBITED WITHOUT THE PRIOR EXPRESS WRITTEN
# PERMISSION OF ARCTERA US, LLC.
#
# The Licensed Software and Documentation are deemed to be commercial computer
# software as defined in FAR 12.212 and subject to restricted rights as defined
# in FAR Section 52.227-19 "Commercial Computer Software - Restricted Rights" and
# DFARS 227.7202, Rights in "Commercial Computer Software or Commercial Computer
# Software Documentation," as applicable, and any successor regulations, whether
# delivered by Arctera US, LLC as on premises or hosted services.  Any use,
# modification, reproduction release, performance, display or disclosure of the
# Licensed Software and Documentation by the U.S. Government shall be solely in
# accordance with the terms of this Agreement. $
#

# --- artifact header ---
# name: infoscale-tools-v<version>
# destination: /preflight/preflight-rules
# --- end ---

set -euo pipefail

RULE_NAME="Platform"
INFOSCALE_CLUSTER_RESOURCE="infoscalecluster"


SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

DATA_DIR="${ROOT_DIR}/lib/data"
DOC_REFERENCE="${ROOT_DIR}/lib/data/document_links.json"

source "${ROOT_DIR}/lib/cr_utils.sh"

KUBE_CLI=""


config() {

        log_info "[${RULE_NAME}] Running configuration phase..."
        if [[ -z "${KUBE_CLI:-}" ]]; then
                detect_kube_cli || {
                log_error "[${RULE_NAME}] Failed to detect kube client (oc/kubectl)"
                return 1
                }
        fi

        
        current_ocp=""
        max_wait=60
        sleep=5        
        elapsed=0

        while [[ $elapsed -lt $max_wait ]]; do
                current_ocp="$(timeout 10s ${KUBE_CLI} get clusterversion version \
                        -o jsonpath='{.status.desired.version}' 2>/dev/null || true)"
                if [[ -n "$current_ocp" ]]; then
                        break
                fi
                log_warn "[${RULE_NAME}] Unable to detect OCP version yet, retrying..."
                sleep "$sleep"
                elapsed=$((elapsed + sleep))
        done

        if [[ -z "$current_ocp" ]]; then
                log_error "[${RULE_NAME}] Timed out after ${max_wait}s while trying to detect OCP version."
                log_error "[${RULE_NAME}] 'oc/kubectl' may be hung or the API server is unreachable."
        return 1
        fi

        log_info "[${RULE_NAME}] Current OCP version detected: ${current_ocp}"

log_info "[${RULE_NAME}] Configuration phase completed successfully."
        return 0
}

# Exec phase helpers

ensure_context() {
        if [[ -z "${KUBE_CLI:-}" ]]; then
                detect_kube_cli || {
                log_error "[${RULE_NAME}] Failed to detect kube client"
                return 1
                }
        fi
        if [[ "${INSTALL_TYPE:-upgrade}" == "fresh-install" ]]; then
                log_info "[${RULE_NAME}] Fresh install mode: skipping InfoScale Cluster resource presence check"
                return 0
        fi
        if [[ -z "${CR_LIST:-}" ]]; then
                CR_LIST="$(get_cr_list "${INFOSCALE_CLUSTER_RESOURCE}")"
                if [[ -z "$CR_LIST" ]]; then
                log_error "[${RULE_NAME}] No InfoScale Cluster resource found"
                return 1
                fi
                log_info "[${RULE_NAME}] InfoScale Cluster resource is found"
        fi
        return 0
}

check_ocp_version_alignment() {
        local current_ocp
        if [[ -z "${TARGET_OCP:-}" ]]; then
                log_info "[${RULE_NAME}] Skipping OCP version alignment check (no target OCP provided)"
                return 0
        fi
        current_ocp="$(${KUBE_CLI}  get clusterversion version -o jsonpath='{.status.desired.version}' 2>/dev/null || echo "unknown")"

        if [[ "${current_ocp}" == "${TARGET_OCP}" ]]; then
                log_info "[${RULE_NAME}] Cluster already at target version (${TARGET_OCP})."
        else
                log_info "[${RULE_NAME}] Detected OCP version ${current_ocp}; upgrade target is ${TARGET_OCP}."
        fi
}

check_target_ocp_offered_by_upgrade() {
        local target_version="${TARGET_OCP:-}"

        if [[ -z "${target_version}" ]]; then
                log_info "[${RULE_NAME}] Skipping target OCP support check (no target OCP provided)"
                return 0
        fi

        local current_ocp current_ike
        current_ocp="$(${KUBE_CLI} get clusterversion version -o jsonpath='{.status.desired.version}' 2>/dev/null || true)"

        if [[ -n "${current_ocp}" && "${current_ocp}" == "${target_version}" ]]; then
                log_info "[${RULE_NAME}] Cluster already at requested OCP version (${target_version})."
                log_info "[${RULE_NAME}] Running all platform checks and skipping only target OCP upgrade-offer validation."
                return 0
        fi

        if [[ -n "${IKE_VERSION:-}" ]]; then
                current_ike="$(get_current_ike_version 2>/dev/null || true)"
                if [[ -n "${current_ike}" && "${current_ike}" == "${IKE_VERSION}" ]]; then
                        log_info "[${RULE_NAME}] Cluster already at requested IKE version (${IKE_VERSION})."
                fi

                if ! is_ocp_supported_on_ike "${target_version}" "${IKE_VERSION}"; then
                        log_error "[${RULE_NAME}] Target OCP ${target_version} is not supported for IKE ${IKE_VERSION}"
                        log_info "[${RULE_NAME}] Skipping 'oc adm upgrade' visibility check for unsupported target"
                        return 0
                fi
        fi

        if [[ "${KUBE_CLI}" != "oc" ]]; then
                log_error "[${RULE_NAME}] Target OCP support check requires oc client (detected: ${KUBE_CLI})."
                return 1
        fi

        local target_re
        target_re=$(printf '%s' "${target_version}" | sed -e 's/[][(){}.^$*+?|\]/\\&/g')

        if ${KUBE_CLI} adm upgrade 2>&1 | awk '{print $1}' | grep -Fxq "${target_version}"; then
                log_info "[${RULE_NAME}] Target OCP version ${target_version} is offered by oc adm upgrade."
                return 0
        fi

        local current_minor target_minor
        current_minor="$(echo "${current_ocp:-}" | cut -d. -f2)"
        target_minor="$(echo "${target_version}" | cut -d. -f2)"

        if [[ -n "${current_minor}" && -n "${target_minor}" && "${target_minor}" -gt "${current_minor}" ]]; then
                local expected_channel="stable-4.${target_minor}"
                local current_channel
                current_channel="$(${KUBE_CLI} get clusterversion version -o jsonpath='{.spec.channel}' 2>/dev/null || true)"
                log_warn "[${RULE_NAME}] Target OCP major version stream (4.${target_minor}) differs from current (4.${current_minor})."
                log_warn "[${RULE_NAME}] Current channel: ${current_channel:-<unknown>}"
                if [[ "${current_channel}" == "${expected_channel}" ]]; then
                        log_warn "[${RULE_NAME}] Channel is already set to ${expected_channel}. The target version (${target_version}) may not yet be offered in the update graph."
                        log_warn "[${RULE_NAME}] Verify available updates using 'oc adm upgrade' and check with Red Hat Support if this target should be available."
                else
                        log_warn "[${RULE_NAME}] For a major-version stream change, switch the channel to the target major release stream (e.g. ${expected_channel})."
                        log_warn "[${RULE_NAME}] Run: oc adm upgrade channel ${expected_channel}"
                        log_warn "[${RULE_NAME}] Then verify: oc adm upgrade"
                        log_warn "[${RULE_NAME}] Non-interactive check: switch channel as above, then re-run preflight to validate visibility of target ${target_version}."
                fi
        fi

        log_error "[${RULE_NAME}] Upgrade path to target OCP ${target_version} is not visible in 'oc adm upgrade' output (current OCP: ${current_ocp:-unknown})."
        log_error "[${RULE_NAME}] Verify available/recommended updates using 'oc adm upgrade'."
        log_error "[${RULE_NAME}] If this target should be available, please check with Red Hat Support."
        return 1
}

check_clusteroperators_health() 
{
        log_info "[${RULE_NAME}] Checking ClusterOperator health..."

        local json
        json="$(${KUBE_CLI}  get co -o json || true)"

        local unavailable_cos progressing_cos degraded_cos
        unavailable_cos="$(jq -r '.items[]
        | select(any(.status.conditions[]; .type == "Available" and .status != "True"))
        | .metadata.name' <<<"$json")"

        progressing_cos="$(jq -r '.items[]
        | select(any(.status.conditions[]; .type == "Progressing" and .status == "True"))
        | .metadata.name' <<<"$json")"

        degraded_cos="$(jq -r '.items[]
        | select(any(.status.conditions[]; .type == "Degraded" and .status == "True"))
        | .metadata.name' <<<"$json")"

        local FAIL=false

        if [[ -n "${unavailable_cos}" ]]; then
                log_error "[${RULE_NAME}] Unavailable ClusterOperators:"
                echo "${unavailable_cos}" | sed 's/^/   - /'
                FAIL=true
        fi

        if [[ -n "${progressing_cos}" ]]; then
                log_warn "[${RULE_NAME}] Progressing ClusterOperators:"
                echo "${progressing_cos}" | sed 's/^/   - /'
                FAIL=true
        fi

        if [[ -n "${degraded_cos}" ]]; then
                log_error "[${RULE_NAME}] Degraded ClusterOperators:"
                echo "${degraded_cos}" | sed 's/^/   - /'
                FAIL=true
        fi

        if [[ "${FAIL}" == "true" ]]; then
                return 1
        fi

        log_info "[${RULE_NAME}] All ClusterOperators are healthy and stable."
        return 0
}

check_kubelet_config_status() 

{
        upgrade_doc="$(jq -r '.upgrade_doc_reference.url' "$DOC_REFERENCE")"

        log_info "[${RULE_NAME}] Checking kubelet config status..."

        local kubelet_status
        kubelet_status="$(${KUBE_CLI} describe kubeletconfigs.machineconfiguration.openshift.io 2>/dev/null | grep -A2 "Status:" || true)"
        local kubelet_success=false
        local kubelet_rollout_success=false

        if echo "$kubelet_status" | grep -qi "Success"; then
                kubelet_success=true
        fi

        if [[ "$kubelet_success" == "true" ]]; then
                local workers worker worker_node inhibit_output
                local total_workers=0
                local rollout_workers=0
                workers="$(${KUBE_CLI}  get nodes -l node-role.kubernetes.io/worker= -o name 2>/dev/null || true)"

                if [[ -z "$workers" ]]; then
                        log_warn "[${RULE_NAME}] Could not find worker nodes to verify kubelet rollout status."
                else
                        while read -r worker; do
                                [[ -z "$worker" ]] && continue
                                total_workers=$((total_workers + 1))
                                worker_node="${worker##*/}"
                                inhibit_output="$(${KUBE_CLI} debug node/${worker_node} -- chroot /host systemd-inhibit --list 2>/dev/null || true)"
                                if printf '%s\n' "$inhibit_output" | awk '
                                        NR == 1 { next }
                                        $1 == "kubelet" && $6 ~ /shutdown/ && $NF == "delay" { found = 1 }
                                        END { exit(found ? 0 : 1) }
                                '; then
                                        rollout_workers=$((rollout_workers + 1))
                                        log_info "[${RULE_NAME}] Kubelet rollout for inhibitor (shutdown/delay) is completed on node ${worker_node}."
                                else
                                        log_warn "[${RULE_NAME}] Kubelet shutdown inhibitor with delay mode not detected on node ${worker_node}."
                                fi
                        done <<< "$workers"

                        if [[ "$total_workers" -gt 0 && "$rollout_workers" -eq "$total_workers" ]]; then
                                kubelet_rollout_success=true
                        else
                                log_warn "[${RULE_NAME}] Kubelet rollout summary: ${rollout_workers}/${total_workers} worker nodes show active rollout."
                        fi
                fi
        fi

        if [[ "$kubelet_success" == "true" && "$kubelet_rollout_success" == "true" ]]; then
                log_info "[${RULE_NAME}] Expected kubelet config is applied and rolled out."
                return 0
        fi

        if [[ "$kubelet_success" == "true" && "$kubelet_rollout_success" != "true" ]]; then
                log_error "[${RULE_NAME}] Kubelet config reports Success, but rollout is not visible on worker node."
                log_error "[${RULE_NAME}] Expected kubelet config is not applied."
                log_warn  "[${RULE_NAME}] Refer documentation: ${upgrade_doc}"
                return 1
        fi

        log_error "[${RULE_NAME}] Expected kubelet config is not applied."
        log_warn  "[${RULE_NAME}] Refer documentation: ${upgrade_doc}"
        return 1
}


check_ntp_sync_on_workers() {
        log_info "[${RULE_NAME}] Checking NTP sync status on worker nodes..."
        local workers
        workers="$(${KUBE_CLI}  get nodes -l node-role.kubernetes.io/worker= -o name)"

        if [[ -z "${workers}" ]]; then
                log_warn "[${RULE_NAME}] No worker nodes found."
                return 0
        fi
        local FAIL=false
        for node in ${workers}; do
                local nodename="${node##*/}"
                local ntp_status
                ntp_status="$(${KUBE_CLI}  debug node/${nodename} -- chroot /host chronyc tracking 2>/dev/null | grep -i 'Leap status' || true)"

                if echo "${ntp_status}" | grep -q "Normal"; then
                        log_info "[${RULE_NAME}] ${nodename}: NTP is synced (Leap status Normal)"
                else
                        log_warn "[${RULE_NAME}] ${nodename}: NTP may not be synced"
                        log_warn  "[${RULE_NAME}] NTP synchronization appears to be disabled or not in sync on one or more nodes."
                        log_warn  "[${RULE_NAME}] Time drift between nodes can cause instability during upgrades and cluster operations."
                        log_warn  "[${RULE_NAME}] Ensure NTP/chrony is enabled and all nodes are time-synchronized before proceeding."
                        FAIL=true
                fi
        done
        if [[ "${FAIL}" == "true" ]]; then
                return 1
        fi
        return 0
}

check_master_schedulable() {
        log_info "[${RULE_NAME}] Checking for nodes serving both master/control-plane and worker roles..."
        local control_plane_topology
        control_plane_topology="$(${KUBE_CLI} get infrastructure cluster -o jsonpath='{.status.controlPlaneTopology}' 2>/dev/null || true)"
        if [[ "${control_plane_topology}" == "HighlyAvailableArbiter" ]]; then
                log_info "[${RULE_NAME}] Control plane topology is ${control_plane_topology}; skipping schedulable-master check."
                return 0
        fi

        local nodes_json combined_nodes
        nodes_json="$(${KUBE_CLI} get nodes -o json 2>/dev/null || true)"

        if [[ -z "${nodes_json}" ]] || ! jq -e '.items' <<<"${nodes_json}" >/dev/null 2>&1; then
                log_warn "[${RULE_NAME}] Unable to retrieve node list; skipping master schedulability check."
                return 0
        fi

        combined_nodes="$(jq -r '
                .items[]
                | select((.metadata.labels // {})
                        | (has("node-role.kubernetes.io/master")
                          or has("node-role.kubernetes.io/control-plane")))
                | select((.metadata.labels // {}) | has("node-role.kubernetes.io/worker"))
                | .metadata.name
        ' <<<"${nodes_json}" 2>/dev/null || true)"

        if [[ -z "${combined_nodes}" ]]; then
                log_info "[${RULE_NAME}] No nodes share both master/control-plane and worker roles."
                return 0
        fi

        log_error "[${RULE_NAME}] Detected node(s) that are both master/control-plane and worker (schedulable master):"
        echo "${combined_nodes}" | sed 's/^/   - /'
        log_error "[${RULE_NAME}] With masters schedulable, InfoScale workloads may co-locate with OpenShift control-plane components on the same node."
        log_error "[${RULE_NAME}] This can cause port conflicts between InfoScale services and control-plane components (controller-manager)."
        log_error "[${RULE_NAME}] Recommendation: dedicate worker-only nodes for InfoScale, or verify InfoScale port ranges do not overlap with control-plane bindings before proceeding."
        return 1
}

check_machine_config_status() {
        local updating degraded updated

        updating="$(${KUBE_CLI}  get mcp -o jsonpath='{range .items[*]}{.metadata.name}:{.status.conditions[?(@.type=="Updating")].status}{"\n"}{end}' 2>/dev/null)"
        degraded="$(${KUBE_CLI}  get mcp -o jsonpath='{range .items[*]}{.metadata.name}:{.status.conditions[?(@.type=="Degraded")].status}{"\n"}{end}' 2>/dev/null)"
        updated="$(${KUBE_CLI}  get mcp -o jsonpath='{range .items[*]}{.metadata.name}:{.status.conditions[?(@.type=="Updated")].status}{"\n"}{end}' 2>/dev/null)"

        if echo "$updating" | grep -q ":True"; then
                        log_error "[${RULE_NAME}] One or more MachineConfig pools are still updating"
                        ${KUBE_CLI} get mcp
                        log_warn "[${RULE_NAME}] Resolve these issues by following the guidance in the Red Hat OpenShift documentation."
                        return 1
        fi

        if echo "$degraded" | grep -q ":True"; then
                        log_error "[${RULE_NAME}] One or more MachineConfig pools are degraded."
                        ${KUBE_CLI} get mcp
                        log_warn "[${RULE_NAME}] Resolve these issues by following the guidance in the Red Hat OpenShift documentation."
                        return 1
        fi

        if echo "$updated" | grep -q ":True" && echo "$updated" | grep -q ":False"; then
                        echo "$updated" | grep ":False" | while read -r line; do
                                log_error "[${RULE_NAME}] MachineConfig pools are in a mixed state (some are updated, while some are not)"
                                ${KUBE_CLI} get mcp
                                log_warn "[${RULE_NAME}] Resolve these issues by following the guidance in the Red Hat OpenShift documentation."
                        done
                        return 1
        fi
        return 0
}

check_allowed_registries() {
        log_info "[${RULE_NAME}] Checking allowed image registries..."

        if ! type get_allowed_registries &>/dev/null; then
                log_error "[${RULE_NAME}] Missing function 'get_allowed_registries' in lib/utils."
                return 1
        fi
        local allowed expected missing=()
        expected=($(get_allowed_registries))
        allowed=($(${KUBE_CLI}  get image.config.openshift.io/cluster -o jsonpath='{.spec.registrySources.allowedRegistries[*]}' 2>/dev/null || true))

        if [[ ${#allowed[@]} -eq 0 ]]; then
                log_warn "[${RULE_NAME}] No allowed registries found in cluster config."
                return 1
        fi

        for reg in "${expected[@]}"; do
                if ! printf '%s\n' "${allowed[@]}" | grep -qx "${reg}"; then
                        missing+=("${reg}")
                fi
        done

        if [[ ${#missing[@]} -gt 0 ]]; then
                log_warn "[${RULE_NAME}] Missing expected registries:"
                for reg in "${missing[@]}"; do echo "   - ${reg}"; done
                return 1
        fi

        log_info "[${RULE_NAME}] All expected registries are configured correctly."
        return 0
}

check_ike_ocp_fresh_install_compatibility() {
        local rule="${RULE_NAME:-IKE_OCP_CHECK}"
        local current_ocp installed_ike_version latest_ike_version

        if [[ "${INSTALL_TYPE}" != "fresh-install" ]]; then
                log_info "[${rule}] Skipping fresh install compatibility check (upgrade mode)"
                return 0
        fi

        log_info "[${rule}] Evaluating fresh-install prerequisites..."

        installed_ike_version="$(get_current_ike_version 2>/dev/null || true)"
        if [[ -n "${installed_ike_version}" ]]; then
                log_warn "[${rule}] IKE version ${installed_ike_version} is already installed on this cluster."

                latest_ike_version="$(jq -r '.ike_ocp_compatibility[].ike' "${UPGRADE_MATRIX}" 2>/dev/null | sort -V | tail -n1)"
                if [[ -n "${latest_ike_version}" ]]; then
                        if [[ "$(printf '%s\n%s\n' "${installed_ike_version}" "${latest_ike_version}" | sort -V | head -n1)" == "${installed_ike_version}" && "${installed_ike_version}" != "${latest_ike_version}" ]]; then
                                log_warn "[${rule}] Installed IKE (${installed_ike_version}) is lower than latest available (${latest_ike_version})."
                                log_warn "[${rule}] Suggestion: run preflight in upgrade mode and plan upgrade to ${latest_ike_version}."
                        elif [[ "${installed_ike_version}" == "${latest_ike_version}" ]]; then
                                log_warn "[${rule}] Installed IKE is already at latest available version (${latest_ike_version})."
                        else
                                log_warn "[${rule}] Installed IKE (${installed_ike_version}) is higher than matrix latest (${latest_ike_version})."
                                log_warn "[${rule}] Suggestion: verify matrix content for this build and use upgrade mode if needed."
                        fi
                else
                        log_warn "[${rule}] Could not determine latest IKE version from compatibility matrix."
                fi

                log_warn "[${rule}] Fresh-install mode selected, so compatibility check is skipped for existing installation."
                return 0
        fi

        current_ocp="$(${KUBE_CLI} get clusterversion version -o jsonpath='{.status.desired.version}' 2>/dev/null || true)"
        if [[ -z "${current_ocp}" ]]; then
                log_error "[${rule}] Unable to determine current OCP version"
                return 1
        fi

        log_info "[${rule}] Current OCP version: ${current_ocp}"
        log_info "[${rule}] Target IKE version : ${IKE_VERSION}"

        if is_ocp_supported_on_ike "${current_ocp}" "${IKE_VERSION}"; then
                log_info "[${rule}] IKE version ${IKE_VERSION} is supported on current OCP ${current_ocp} for fresh install"
                return 0
        else
                log_error "[${rule}] IKE version ${IKE_VERSION} is NOT supported on current OCP ${current_ocp} for fresh install"
                log_error "[${rule}] Please consult the compatibility matrix in upgrade_paths.json"
                return 1
        fi
}

# Exec phase
run() {
        echo "-----------------------------------------------------------------------------------------------------"
        echo "[${RULE_NAME}]"
        echo "-----------------------------------------------------------------------------------------------------"

        log_info "[${RULE_NAME}] Executing platform validation checks..."

        local OVERALL_FAIL=false
        ensure_context || return 1
        check_ike_ocp_fresh_install_compatibility || OVERALL_FAIL=true
        check_ocp_version_alignment || OVERALL_FAIL=true
        check_target_ocp_offered_by_upgrade || OVERALL_FAIL=true
        check_clusteroperators_health || OVERALL_FAIL=true
        check_machine_config_status || OVERALL_FAIL=true
        check_kubelet_config_status || OVERALL_FAIL=true
        check_ntp_sync_on_workers || OVERALL_FAIL=true
        check_master_schedulable || OVERALL_FAIL=true
        check_allowed_registries || OVERALL_FAIL=true

        if [[ "${OVERALL_FAIL}" == "true" ]]; then
                log_error "[${RULE_NAME}] One or more platform checks failed."
                return 1
        fi

        log_info "[${RULE_NAME}] All platform checks passed successfully."
        return 0
}
