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


set -euo pipefail

RULE_NAME="IKE Source Cluster Health"
INFOSCALE_CLUSTER_RESOURCE="infoscalecluster"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

DATA_DIR="${ROOT_DIR}/lib/data"
DOC_REFERENCE="${DATA_DIR}/document_links.json"

source "${ROOT_DIR}/lib/cr_utils.sh"

KUBE_CLI=""
CR_LIST=""

# Config
config() {
    if [[ -z "${KUBE_CLI:-}" ]]; then
        detect_kube_cli || {
            log_error "[${RULE_NAME}] Failed to detect kube client"
            return 1
        }
    fi
    if [[ -z "${IKE_VERSION:-}" ]]; then
        log_error "[${RULE_NAME}] Target IKE_VERSION not set"
        return 1
    fi
    if [[ -z "${CR_LIST:-}" ]]; then
        CR_LIST="$(get_cr_list "${INFOSCALE_CLUSTER_RESOURCE}")"
        if [[ -z "$CR_LIST" ]]; then
            log_error "[${RULE_NAME}] No InfoScale Cluster resource found in the cluster."
            log_error "[${RULE_NAME}] This indicates that the IKE is not installed."
            log_error "[${RULE_NAME}] Product upgrade checks are not applicable. Aborting this rule."
            return 1
        fi
        log_info "[${RULE_NAME}] InfoScale Cluster resource found."
        log_info "[${RULE_NAME}] Configuration successful"
    fi
    return 0
}

#Exec phase helpers
ensure_context() {
    if [[ -z "${KUBE_CLI:-}" ]]; then
        detect_kube_cli || {
            log_error "[${RULE_NAME}] Failed to detect kube client"
            return 1
        }
    fi
    if [[ -z "${CR_LIST:-}" ]]; then
        CR_LIST="$(get_cr_list "${INFOSCALE_CLUSTER_RESOURCE}")"
        if [[ -z "$CR_LIST" ]]; then
            log_error "[${RULE_NAME}] No InfoScale Cluster resource found"
            return 1
        fi
        log_info "[${RULE_NAME}] InfoScale Cluster resource has been found going ahead with further checks"
    fi
    return 0
}

check_sourcecluster_get() {
    local FAIL=false
    IKE_troubleshooting_doc="$(jq -r '.IKE_troubleshooting.url' "$DOC_REFERENCE")"
    log_info "[${RULE_NAME}] Checking InfoScale Cluster resource status"

    while read -r ns name; do
        [[ -z "$ns" ]] && continue

        local row
        row="$(${KUBE_CLI} get "${INFOSCALE_CLUSTER_RESOURCE}" -n "$ns" "$name" --no-headers 2>/dev/null || true)"
        if [[ -z "$row" ]]; then
            log_error "No output for ${ns}/${name}"
            FAIL=true
            continue
        fi

        read -r cname version clusterid state diskgroups status age <<<"$row"
        echo "----------------------------------------"
        log_info "[${RULE_NAME}] Namespace: $ns"
        log_info "[${RULE_NAME}] Name    : $cname"
        log_info "[${RULE_NAME}] Version : $version"
        log_info "[${RULE_NAME}] State   : $state"
        if [[ "${state,,}" != "running" ]]; then
            log_error "[${RULE_NAME}] Cluster state not Running for ${ns}/${cname}: found=${state}"
            log_warn  "[${RULE_NAME}] Refer to the documentation for next steps:${IKE_troubleshooting_doc}"
            FAIL=true
        fi
        log_info "[${RULE_NAME}] Status  : $status"
        if [[ "${status,,}" != "healthy" ]]; then
            log_error "[${RULE_NAME}] Cluster status not Healthy for ${ns}/${cname}: found=${status}"
            log_warn  "[${RULE_NAME}] Refer to the documentation for next steps:${IKE_troubleshooting_doc}"
            FAIL=true
        fi
    done <<< "$CR_LIST"
    $FAIL && return 1 || return 0
}

check_sourcecluster_details() {
        local FAIL=false
        IKE_troubleshooting_doc="$(jq -r '.IKE_troubleshooting.url' "$DOC_REFERENCE")"
        while read -r ns name; do
            [[ -z "$ns" ]] && continue
            local version state cluster_state diskgroup shared
            version="$(get_cr_field "$INFOSCALE_CLUSTER_RESOURCE" "$ns" "$name" '{.status.version}')"
            state="$(get_cr_field "$INFOSCALE_CLUSTER_RESOURCE" "$ns" "$name" '{.status.phase}')"
            cluster_state="$(get_cr_field "$INFOSCALE_CLUSTER_RESOURCE" "$ns" "$name" '{.status.clusterState}')"
            diskgroup="$(get_cr_field "$INFOSCALE_CLUSTER_RESOURCE" "$ns" "$name" '{.status.diskgroups[0].State}')"
            shared="$(get_cr_field "$INFOSCALE_CLUSTER_RESOURCE" "$ns" "$name" '{.spec.isSharedStorage}')"

            log_info "[${RULE_NAME}] Cluster State  : $cluster_state"
            if [[ "${cluster_state,,}" != "healthy" ]] ; then
                log_error "[${RULE_NAME}] Cluster state not Healthy for ${ns}/${name}: found=${cluster_state}"
                log_warn  "[${RULE_NAME}] Refer to the documentation for next steps:${IKE_troubleshooting_doc}"
                FAIL=true
            fi
            log_info "[${RULE_NAME}] Diskgroup      : $diskgroup"
            if [[ "${diskgroup,,}" != "imported" ]] ; then
                log_error "[${RULE_NAME}] Diskgroup is not imported for $INFOSCALE_CLUSTER_RESOURCE"
                log_warn  "[${RULE_NAME}] Refer to the documentation for next steps:${IKE_troubleshooting_doc}"
                FAIL=true
            fi
            log_info "[${RULE_NAME}] Shared Storage : $shared"
        done <<< "$CR_LIST"
        $FAIL && return 1 || return 0
    }

check_node_join_status() {
        IKE_troubleshooting_doc="$(jq -r '.IKE_troubleshooting.url' "$DOC_REFERENCE")"
        local FAIL=false
        log_info "[${RULE_NAME}] Checking node join status"
        echo "----------------------------------------"
        while read -r ns name; do
            [[ -z "$ns" ]] && continue
            local nodes
            nodes="$(get_cr_field "$INFOSCALE_CLUSTER_RESOURCE" "$ns" "$name" '{.status.clusterNodes[*].nodeName}')"
            for node in $nodes; do
                local role
                role="$(get_cr_field "$INFOSCALE_CLUSTER_RESOURCE" "$ns" "$name" "{.status.clusterNodes[?(@.nodeName=='$node')].role}")"

                if ! grep_e "joined" "$role"; then
                    log_error "[${RULE_NAME}] Node $node not joined ($role)"
                    log_warn "[${RULE_NAME}] Please login to SDS pod and check for node join failure for $node"
                    log_warn  "[${RULE_NAME}] Refer to the documentation for next steps:${IKE_troubleshooting_doc}"
                    FAIL=true
                else
                    log_info "[${RULE_NAME}] Node $node joined"
                fi
            done
        done <<< "$CR_LIST"
        $FAIL && return 1 || return 0
}

check_spec_status_mismatch() {
    IKE_troubleshooting_doc="$(jq -r '.IKE_troubleshooting.url' "$DOC_REFERENCE")"
    local FAIL=false
    log_info "[${RULE_NAME}] Checking spec/status consistency for fencing devices"
    echo "----------------------------------------"

    while read -r ns name; do
        [[ -z "$ns" ]] && continue

        local cr_json
        cr_json="$(kube_get_safe get "$INFOSCALE_CLUSTER_RESOURCE" -n "$ns" "$name" -o json 2>/dev/null || true)"

        if [[ -z "$cr_json" ]] || ! jq -e . >/dev/null 2>&1 <<<"$cr_json"; then
            log_error "[${RULE_NAME}] Failed to fetch valid JSON for ${INFOSCALE_CLUSTER_RESOURCE} ${ns}/${name} for spec/status comparison"
            log_warn  "[${RULE_NAME}] Refer to the documentation for next steps: ${IKE_troubleshooting_doc}"
            FAIL=true
            continue
        fi

        local is_shared_storage scsi3pr_enabled
        is_shared_storage="$(jq -r '(.spec.isSharedStorage // false) | tostring' <<<"$cr_json")"
        scsi3pr_enabled="$(jq -r '(.spec.enableScsi3pr // false) | tostring' <<<"$cr_json")"

        if [[ "${is_shared_storage,,}" != "true" || "${scsi3pr_enabled,,}" != "true" ]]; then
            log_info "[${RULE_NAME}] ${ns}/${name}: skipping fencing disk spec/status validation because spec.isSharedStorage=${is_shared_storage:-<empty>} and spec.enableScsi3pr=${scsi3pr_enabled:-<empty>}"
            continue
        fi

        local spec_fencing_nodes
        spec_fencing_nodes="$(jq -r '
            (.spec.clusterInfo // [])
            | map(select(((.fencingDevice // []) | map(select(length > 0)) | length) > 0))
            | map(.nodeName // empty)
            | map(select(length > 0))
            | unique | sort | .[]
        ' <<<"$cr_json")"

        while read -r spec_fencing_node; do
            [[ -z "$spec_fencing_node" ]] && continue

            local spec_node_fencing status_node_fencing spec_node_fencing_count status_node_fencing_count status_node_exists_count
            spec_node_fencing="$(jq -r --arg node "$spec_fencing_node" '
                (.spec.clusterInfo // [])
                | map(select((.nodeName // "") == $node))
                | .[0].fencingDevice // []
                | map(select(length > 0))
                | join(",")
            ' <<<"$cr_json")"

            spec_node_fencing_count="$(jq -r --arg node "$spec_fencing_node" '
                (.spec.clusterInfo // [])
                | map(select((.nodeName // "") == $node))
                | .[0].fencingDevice // []
                | map(select(length > 0))
                | length
            ' <<<"$cr_json")"

            status_node_exists_count="$(jq -r --arg node "$spec_fencing_node" '
                (.status.clusterNodes // [])
                | map(select((.nodeName // "") == $node))
                | length
            ' <<<"$cr_json")"

            status_node_fencing="$(jq -r --arg node "$spec_fencing_node" '
                (.status.clusterNodes // [])
                | map(select((.nodeName // "") == $node))
                | .[0].fencingDevice // []
                | map(select(length > 0))
                | join(",")
            ' <<<"$cr_json")"

            status_node_fencing_count="$(jq -r --arg node "$spec_fencing_node" '
                (.status.clusterNodes // [])
                | map(select((.nodeName // "") == $node))
                | .[0].fencingDevice // []
                | map(select(length > 0))
                | length
            ' <<<"$cr_json")"

            log_internal "[${RULE_NAME}] ${ns}/${name}: spec fencing node=${spec_fencing_node}, spec_count=${spec_node_fencing_count}, status_node_count=${status_node_exists_count}, status_count=${status_node_fencing_count}, spec=[${spec_node_fencing}], status=[${status_node_fencing}]"

            if [[ "$status_node_exists_count" -eq 0 ]]; then
                log_error "[${RULE_NAME}] ${ns}/${name}: node ${spec_fencing_node} exists in spec fencing configuration but is missing in status.clusterNodes"
                FAIL=true
                continue
            fi

            if [[ "$spec_node_fencing_count" -gt 0 && "$status_node_fencing_count" -eq 0 ]]; then
                log_error "[${RULE_NAME}] ${ns}/${name}: status fencing devices are missing for node ${spec_fencing_node} even though fencingDevice is defined in spec"
                log_error "[${RULE_NAME}] ${ns}/${name}: spec fencing=[${spec_node_fencing:-<empty>}]"
                FAIL=true
                continue
            fi

            if [[ "${status_node_fencing}" != "${spec_node_fencing}" ]]; then
                log_error "[${RULE_NAME}] ${ns}/${name}: fencing disks mismatch for node ${spec_fencing_node}; spec and status must match exactly in sequence"
                log_error "[${RULE_NAME}] ${ns}/${name}: spec   fencing=[${spec_node_fencing:-<empty>}]"
                log_error "[${RULE_NAME}] ${ns}/${name}: status fencing=[${status_node_fencing:-<empty>}]"

                local spec_disk status_disk
                while IFS= read -r spec_disk; do
                    [[ -z "$spec_disk" ]] && continue
                    if ! grep -Fqx "$spec_disk" < <(tr ',' '\n' <<<"$status_node_fencing"); then
                        log_error "[${RULE_NAME}] ${ns}/${name}: missing in status for node ${spec_fencing_node}: ${spec_disk}"
                    fi
                done < <(tr ',' '\n' <<<"$spec_node_fencing")

                while IFS= read -r status_disk; do
                    [[ -z "$status_disk" ]] && continue
                    if ! grep -Fqx "$status_disk" < <(tr ',' '\n' <<<"$spec_node_fencing"); then
                        log_error "[${RULE_NAME}] ${ns}/${name}: unexpected in status for node ${spec_fencing_node}: ${status_disk}"
                    fi
                done < <(tr ',' '\n' <<<"$status_node_fencing")

                local idx spec_at_idx status_at_idx max_count
                max_count="$(( spec_node_fencing_count > status_node_fencing_count ? spec_node_fencing_count : status_node_fencing_count ))"
                for ((idx=1; idx<=max_count; idx++)); do
                    spec_at_idx="$(awk -F',' -v i="$idx" '{print $i}' <<<"$spec_node_fencing")"
                    status_at_idx="$(awk -F',' -v i="$idx" '{print $i}' <<<"$status_node_fencing")"
                    [[ -z "$spec_at_idx" && -z "$status_at_idx" ]] && continue
                    if [[ "$spec_at_idx" != "$status_at_idx" ]]; then
                        log_error "[${RULE_NAME}] ${ns}/${name}: order mismatch for node ${spec_fencing_node} at position ${idx}: spec=[${spec_at_idx:-<empty>}] status=[${status_at_idx:-<empty>}]"
                    fi
                done

                FAIL=true
                continue
            fi

            local sds_line sds_ns sds_pod
            sds_line="$(get_sds_pods | awk -v ns="$ns" -v node="$spec_fencing_node" '$1 == ns && $8 == node { print; exit }')"
            if [[ -z "$sds_line" ]]; then
                log_error "[${RULE_NAME}] ${ns}/${name}: unable to find SDS pod for spec fencing node ${spec_fencing_node}"
                FAIL=true
                continue
            fi
            sds_ns="$(awk '{print $1}' <<<"$sds_line")"
            sds_pod="$(awk '{print $2}' <<<"$sds_line")"

            local vxdisk_e_out
            vxdisk_e_out="$(kube_exec_safe "$sds_ns" "$sds_pod" vxdisk -e list 2>/dev/null || true)"

            while IFS= read -r disk; do
                [[ -z "$disk" ]] && continue

                local os_disk
                os_disk="$(kube_exec_safe "$sds_ns" "$sds_pod" bash -lc 'resolved=$(readlink -f -- "$1" 2>/dev/null || true); [[ -n "$resolved" ]] && basename -- "$resolved"' -- "$disk" 2>/dev/null || true)"

                if [[ -z "$os_disk" ]]; then
                    log_error "[${RULE_NAME}] ${ns}/${name}: unable to resolve fencing path '${disk}' to an OS disk on node ${spec_fencing_node}"
                    FAIL=true
                    continue
                fi

                local vxdisk_line aliases alias
                vxdisk_line="$(grep -w -- "$os_disk" <<<"$vxdisk_e_out" | head -n1 || true)"

                if [[ -z "$vxdisk_line" ]]; then
                    aliases="$(kube_exec_safe "$sds_ns" "$sds_pod" vxdisk list "$os_disk" 2>/dev/null | awk '$2 ~ /^state=/{print $1}' | sort -u || true)"
                    while IFS= read -r alias; do
                        [[ -z "$alias" ]] && continue
                        vxdisk_line="$(grep -w -- "$alias" <<<"$vxdisk_e_out" | head -n1 || true)"
                        if [[ -n "$vxdisk_line" ]]; then
                            log_internal "[${RULE_NAME}] ${ns}/${name}: fencing path '${disk}' resolved to '${os_disk}' matched via alias '${alias}' on node ${spec_fencing_node}"
                            break
                        fi
                    done <<<"$aliases"
                fi

                if [[ -z "$vxdisk_line" ]]; then
                    log_error "[${RULE_NAME}] ${ns}/${name}: resolved OS disk '${os_disk}' (from fencing path '${disk}') not found in 'vxdisk -e list' on node ${spec_fencing_node} (including alias fallback)"
                    FAIL=true
                    continue
                fi

                if ! grep -qi "coord" <<<"$vxdisk_line"; then
                    log_error "[${RULE_NAME}] ${ns}/${name}: OS disk '${os_disk}' (from fencing path '${disk}') is not part of coordinator DG on node ${spec_fencing_node}"
                    FAIL=true
                else
                    log_info "[${RULE_NAME}] ${ns}/${name}: fencing path '${disk}' resolved to '${os_disk}' and is in coordinator DG on node ${spec_fencing_node}"
                fi
            done < <(tr ',' '\n' <<<"$spec_node_fencing")

        done <<<"$spec_fencing_nodes"

        local status_fencing_nodes
        status_fencing_nodes="$(jq -r '
            (.status.clusterNodes // [])
            | map(select(((.fencingDevice // []) | map(select(length > 0)) | length) > 0))
            | map(.nodeName // empty)
            | map(select(length > 0))
            | unique | sort | .[]
        ' <<<"$cr_json")"

        while read -r status_node; do
            [[ -z "$status_node" ]] && continue

            if grep -Fxq "$status_node" <<<"$spec_fencing_nodes"; then
                continue
            fi

            local status_node_fencing
            status_node_fencing="$(jq -r --arg node "$status_node" '
                (.status.clusterNodes // [])
                | map(select((.nodeName // "") == $node))
                | .[0].fencingDevice // []
                | map(select(length > 0))
                | join(",")
            ' <<<"$cr_json")"

            [[ -z "$status_node_fencing" ]] && continue

            local status_sds_line status_sds_ns status_sds_pod
            status_sds_line="$(get_sds_pods | awk -v ns="$ns" -v node="$status_node" '$1 == ns && $8 == node { print; exit }')"
            if [[ -z "$status_sds_line" ]]; then
                log_error "[${RULE_NAME}] ${ns}/${name}: unable to find SDS pod for status fencing node ${status_node}"
                FAIL=true
                continue
            fi
            status_sds_ns="$(awk '{print $1}' <<<"$status_sds_line")"
            status_sds_pod="$(awk '{print $2}' <<<"$status_sds_line")"

            local status_vxdisk_e_out
            status_vxdisk_e_out="$(kube_exec_safe "$status_sds_ns" "$status_sds_pod" vxdisk -e list 2>/dev/null || true)"

            while IFS= read -r disk; do
                [[ -z "$disk" ]] && continue

                local status_os_disk
                status_os_disk="$(kube_exec_safe "$status_sds_ns" "$status_sds_pod" bash -lc 'resolved=$(readlink -f -- "$1" 2>/dev/null || true); [[ -n "$resolved" ]] && basename -- "$resolved"' -- "$disk" 2>/dev/null || true)"

                if [[ -z "$status_os_disk" ]]; then
                    log_error "[${RULE_NAME}] ${ns}/${name}: unable to resolve status fencing path '${disk}' to an OS disk on node ${status_node}"
                    FAIL=true
                    continue
                fi

                local status_vxdisk_line status_aliases status_alias
                status_vxdisk_line="$(grep -w -- "$status_os_disk" <<<"$status_vxdisk_e_out" | head -n1 || true)"

                if [[ -z "$status_vxdisk_line" ]]; then
                    status_aliases="$(kube_exec_safe "$status_sds_ns" "$status_sds_pod" vxdisk list "$status_os_disk" 2>/dev/null | awk '$2 ~ /^state=/{print $1}' | sort -u || true)"
                    while IFS= read -r status_alias; do
                        [[ -z "$status_alias" ]] && continue
                        status_vxdisk_line="$(grep -w -- "$status_alias" <<<"$status_vxdisk_e_out" | head -n1 || true)"
                        if [[ -n "$status_vxdisk_line" ]]; then
                            log_internal "[${RULE_NAME}] ${ns}/${name}: status fencing path '${disk}' resolved to '${status_os_disk}' matched via alias '${status_alias}' on node ${status_node}"
                            break
                        fi
                    done <<<"$status_aliases"
                fi

                if [[ -z "$status_vxdisk_line" ]]; then
                    log_error "[${RULE_NAME}] ${ns}/${name}: resolved OS disk '${status_os_disk}' (from status fencing path '${disk}') not found in 'vxdisk -e list' on node ${status_node} (including alias fallback)"
                    FAIL=true
                    continue
                fi

                if ! grep -qi "coord" <<<"$status_vxdisk_line"; then
                    log_error "[${RULE_NAME}] ${ns}/${name}: OS disk '${status_os_disk}' (from status fencing path '${disk}') is not part of coordinator DG on node ${status_node}"
                    FAIL=true
                else
                    log_info "[${RULE_NAME}] ${ns}/${name}: status fencing path '${disk}' resolved to '${status_os_disk}' and is in coordinator DG on node ${status_node}"
                fi
            done < <(tr ',' '\n' <<<"$status_node_fencing")
        done <<<"$status_fencing_nodes"

        local total_status_nodes status_nodes_with_fencing status_nodes_without_fencing
        if [[ -n "$spec_fencing_nodes" ]]; then
            total_status_nodes="$(jq -r '(.status.clusterNodes // []) | length' <<<"$cr_json")"
            status_nodes_with_fencing="$(jq -r '(.status.clusterNodes // []) | map(select(((.fencingDevice // []) | map(select(length > 0)) | length) > 0)) | length' <<<"$cr_json")"
            status_nodes_without_fencing=$((total_status_nodes - status_nodes_with_fencing))

            if [[ "$status_nodes_with_fencing" -gt 0 && "$status_nodes_without_fencing" -gt 0 ]]; then
                log_warn "[${RULE_NAME}] ${ns}/${name}: fencing device configuration is incomplete: ${status_nodes_with_fencing} node(s) have fencing but ${status_nodes_without_fencing} node(s) do not"
                log_warn "[${RULE_NAME}] ${ns}/${name}: all cluster nodes should have consistent fencing device configuration"
            fi
        fi

    done <<< "$CR_LIST"

    if [[ "${FAIL}" == "true" ]]; then
        log_warn "[${RULE_NAME}] Refer to the documentation for next steps: ${IKE_troubleshooting_doc}"
        return 1
    fi

    log_info "[${RULE_NAME}] Spec and status are consistent for fencing devices"
    return 0
}

check_pod_readiness_status() {
    local ns="$1" pod="$2" ready="$3" status="$4"

    
    if [[ "$ready" != "1/1" ]]; then
        log_error "[${RULE_NAME}] InfoScale Pod $pod is NOT Ready (ready=$ready, status=$status)"
        log_warn  "[${RULE_NAME}] Refer to the documentation for next steps: ${IKE_troubleshooting_doc}"
        return 1
    fi
    
    if [[ "$status" != "Running" ]]; then
        log_error "[${RULE_NAME}] InfoScale Pod $pod is not running ($status)"
        log_warn  "[${RULE_NAME}] Refer to the documentation for next steps: ${IKE_troubleshooting_doc}"
        return 1
    fi
    
    return 0
}

check_diskgroup_imported() {
    local ns="$1" pod="$2" node="$3"
    
    local dg_info
    dg_info="$(kube_exec_safe "$ns" "$pod" vxdg list 2>/dev/null || true)"
    if ! grep_e "enabled" "$dg_info"; then
        log_warn "[${RULE_NAME}] Diskgroup not imported in pod $pod"
        log_warn  "[${RULE_NAME}] Please login to SDS pod and check why Diskgroup is not imported on node $node"
        log_warn  "[${RULE_NAME}] Refer to the documentation for next steps: ${IKE_troubleshooting_doc}"
        return 1
    fi
    
    log_info "[${RULE_NAME}] Diskgroup is imported in pod $pod"
    return 0
}

check_volume_states() {
    local ns="$1" pod="$2"
    
    local vol_info
    vol_info="$(kube_exec_safe "$ns" "$pod" vxprint -ht 2>/dev/null || true)"
    if grep_e "NEEDSYNC" "$vol_info"; then
        log_warn "[${RULE_NAME}] Some volumes/snapshots in pod $pod are in NEEDSYNC state"
        log_warn  "[${RULE_NAME}] Please login to SDS pod and check why volumes/snapshots are in NEEDSYNC state"
        log_warn  "[${RULE_NAME}] Refer to the documentation for next steps: ${IKE_troubleshooting_doc}"
        return 1
    elif grep_e "DISABLED|FAULTED|INACTIVE|DETACHED" "$vol_info"; then
        log_warn "[${RULE_NAME}] Some volumes in pod $pod are not active/enabled"
        log_warn  "[${RULE_NAME}] Please login to SDS pod and check why all volumes/snapshots are not in enabled state"
        log_warn  "[${RULE_NAME}] Refer to the documentation for next steps: ${IKE_troubleshooting_doc}"
        return 1
    fi
    
    log_info "[${RULE_NAME}] All volumes are enabled/active in pod $pod"
    return 0
}

check_background_sync_tasks() {
    local ns="$1" pod="$2"
    
    local task_info active_tasks
    task_info="$(kube_exec_safe "$ns" "$pod" /opt/VRTS/bin/hacli -cmd "vxtask list" 2>/dev/null || true)"
    [[ -z "$task_info" ]] && task_info="$(kube_exec_safe "$ns" "$pod" vxtask list 2>/dev/null || true)"

    active_tasks=$(echo "$task_info" | awk '
        BEGIN { IGNORECASE=1 }
        /SNAPSYNC\/R/ {
            print "ID:" $1 " Progress:" $4
        }
    ')
   
    if [[ -n "$active_tasks" ]]; then
        log_warn "[${RULE_NAME}] Background VxVM tasks detected in pod $pod"
        log_warn  "[${RULE_NAME}] Active task : ${active_tasks}"
        log_warn  "[${RULE_NAME}] Please login to SDS pod and review: vxtask list"
        log_warn  "[${RULE_NAME}] Refer to the documentation for next steps: ${IKE_troubleshooting_doc}"
        return 1
    fi
    
    log_info "[${RULE_NAME}] No active VxVM tasks in pod $pod"
    return 0
}

check_snap_associations() {
    local ns="$1" pod="$2" node="$3"
    
    local dg_info dg_names any_pairs
    dg_info="$(kube_exec_safe "$ns" "$pod" vxdg list 2>/dev/null || true)"
    dg_names="$(awk 'tolower($0) ~ /enabled/ && NF >= 1 { print $1 }' <<<"$dg_info" | sort -u)"
    
    if [[ -z "$dg_names" ]]; then
        log_warn "[${RULE_NAME}] Could not determine diskgroup name(s) from vxdg list in pod $pod; skipping vxsnap check"
        return 0
    fi
    
    any_pairs=false
    while read -r dg; do
        [[ -z "$dg" ]] && continue
        local snap_list
        snap_list="$(kube_exec_safe "$ns" "$pod" vxsnap -g "$dg" list 2>/dev/null || true)"
        [[ -z "$snap_list" ]] && continue
        
        local pairs
        pairs="$(awk '
            NR==1 { next }          
            NF<6 { next }
            {
                child=$1
                parent=$5
                snapdate=$7
                if (child ~ /^snapres_/ && parent ~ /^snap_/) {
                    printf "%s\t%s\t%s\n", child, parent, snapdate
                }
            }
        ' <<<"$snap_list")"
        
        if [[ -n "$pairs" ]]; then
            any_pairs=true
            local cnt
            cnt="$(wc -l <<<"$pairs" | tr -d " ")"
            log_warn "[${RULE_NAME}] Found snapres child volumes with snap parent snapshots in pod $pod on node $node"
            log_warn  "[${RULE_NAME}] Diskgroup: $dg (${cnt} associations)"

            while IFS=$'\t' read -r child parent snapdate; do
                log_warn "[${RULE_NAME}]   - Child=${child}  Parent=${parent}  CreatedOn=${snapdate}"
            done <<<"$pairs"

            log_warn "[${RULE_NAME}] Please login to SDS pod and review: vxsnap -g $dg list"
            log_warn "[${RULE_NAME}] Refer to the documentation for next steps: ${IKE_troubleshooting_doc}"
        fi
    done <<<"$dg_names"
    
    if ! $any_pairs; then
        log_info "[${RULE_NAME}] No snapres->snap child/parent associations detected in pod $pod on node $node"
    else
        return 1
    fi
    
    return 0
}

check_disk_health_status() {
    local ns="$1" pod="$2" node="$3"
    
    local disk_info
    disk_info="$(kube_exec_safe "$ns" "$pod" vxdisk list 2>/dev/null || true)"
    if grep_e "failed|error|removed" "$disk_info"; then
        log_error "[${RULE_NAME}] Disk errors detected inside pod $pod on node $node"
        log_warn  "[${RULE_NAME}] Please login to SDS pod and check disks status"
        log_warn  "[${RULE_NAME}] Refer to the documentation for next steps: ${IKE_troubleshooting_doc}"
        return 1
    fi
    
    log_info "[${RULE_NAME}] All disks are good inside pod $pod"
    return 0
}

check_split_brain() {
    local ns="$1" pod="$2" node="$3"
    local fail=false
    local all_node_count cluster_name
    local cluster_json is_shared_storage scsi3pr_enabled
    local disk_info unique_disks unknown_nodes

    log_info "[${RULE_NAME}] Checking for split brain condition"

    cluster_name="$(awk -v ns="$ns" '$1 == ns { print $2; exit }' <<<"$CR_LIST")"

    if [[ -z "$cluster_name" ]]; then
        log_warn "[${RULE_NAME}] No InfoScaleCluster found in namespace $ns; split brain node-count validation skipped for pod $pod"
        return 0
    fi

    cluster_json="$(kube_get_safe get "$INFOSCALE_CLUSTER_RESOURCE" -n "$ns" "$cluster_name" -o json 2>/dev/null || true)"
    if [[ -n "$cluster_json" ]]; then
        all_node_count="$(jq -r '(.status.clusterNodes // []) | length' <<<"$cluster_json" 2>/dev/null || echo "0")"
    else
        all_node_count="0"
    fi

    if [[ ! "$all_node_count" =~ ^[0-9]+$ ]]; then
        all_node_count="0"
    fi

    if [[ -z "$cluster_json" ]] || ! jq -e . >/dev/null 2>&1 <<<"$cluster_json"; then
        log_warn "[${RULE_NAME}] Unable to fetch valid InfoScaleCluster JSON for ${ns}/${cluster_name}; split brain check skipped for pod $pod"
        return 0
    fi

    is_shared_storage="$(jq -r '(.spec.isSharedStorage // false) | tostring' <<<"$cluster_json")"
    scsi3pr_enabled="$(jq -r '(.spec.enableScsi3pr // false) | tostring' <<<"$cluster_json")"
    if [[ "${is_shared_storage,,}" != "true" || "${scsi3pr_enabled,,}" != "true" ]]; then
        log_info "[${RULE_NAME}] Split brain check skipped for ${ns}/${cluster_name} (spec.isSharedStorage=${is_shared_storage:-<empty>}, spec.enableScsi3pr=${scsi3pr_enabled:-<empty>})"
        return 0
    fi

    log_info "[${RULE_NAME}] Using InfoScaleCluster '$cluster_name' for pod $pod on node $node; expected node count = $all_node_count"

    disk_info="$(kube_exec_safe "$ns" "$pod" vxdisk list 2>/dev/null || true)"

    if [[ -z "$disk_info" ]]; then
        log_info "[${RULE_NAME}] No disk info available for split brain check"
        return 0
    fi

    unique_disks="$(echo "$disk_info" | awk 'NR>1 && $0 ~ /online[[:space:]]+invalid/ {next} {print $1}' | sort -u)"

    while read -r disk; do
        [[ -z "$disk" ]] && continue

        local key_output keys_found nodes_registered
        key_output="$(kube_exec_safe "$ns" "$pod" vxfenadm -s /dev/vx/rdmp/"$disk" 2>/dev/null || true)"

        [[ -z "$key_output" ]] && continue

        keys_found=$(echo "$key_output" | grep "Total Number Of Keys:" | awk '{print $NF}')
        [[ -z "$keys_found" ]] && continue

        nodes_registered=$(echo "$key_output" | grep "Node Name:" | awk -F': ' '{print $NF}' | grep -v '^Unknown$' | sort -u | wc -l)
        unknown_nodes=$(echo "$key_output" | grep "Node Name:" | awk -F': ' '{print $NF}' | grep -c '^Unknown$' || true)

        log_info "[${RULE_NAME}] Disk $disk: Total keys=$keys_found, Registered nodes=$nodes_registered, Unknown node names=$unknown_nodes"

        if [[ "${unknown_nodes:-0}" -gt 0 ]]; then
            log_error "[${RULE_NAME}] Disk $disk: $unknown_nodes SCSI key(s) have Node Name reported as 'Unknown'"
            log_error "[${RULE_NAME}] This indicates a node identity resolution failure; vxfenadm cannot map SCSI key(s) to a cluster node"
            log_warn  "[${RULE_NAME}] Investigate SCSI registration key ownership on disk $disk before upgrading"
            log_warn  "[${RULE_NAME}] Refer to the documentation for next steps: ${IKE_troubleshooting_doc}"
            fail=true
        fi

        if [[ $all_node_count -gt 0 ]] && [[ $nodes_registered -lt $all_node_count ]]; then
            log_error "[${RULE_NAME}] Split brain DETECTED on disk $disk in pod $pod"
            log_error "[${RULE_NAME}] Expected $all_node_count nodes but only $nodes_registered are registered with a known name"
            log_warn  "[${RULE_NAME}] Please check SCSI reservations and cluster interconnect immediately"
            log_warn  "[${RULE_NAME}] Refer to the documentation for next steps: ${IKE_troubleshooting_doc}"
            fail=true
        elif [[ "${unknown_nodes:-0}" -eq 0 ]]; then
            log_info "[${RULE_NAME}] Disk $disk: All nodes properly registered with known names (keys=$keys_found, nodes=$nodes_registered)"
        fi
    done <<< "$unique_disks"

    $fail && return 1 || return 0
}
capture_pod_vxrest_logs() {
    local ns="$1" pod="$2" node="$3"
    
    log_info "[${RULE_NAME}] Capturing VxREST logs from pod $pod"
    echo "" >> "${VXREST_LOGS_FILE}"
    echo "### Pod: $pod (Node: $node) ###" >> "${VXREST_LOGS_FILE}"
    kube_exec_safe "$ns" "$pod" cat /opt/VRTSrest/log/vxrest.log 2>/dev/null >> "${VXREST_LOGS_FILE}" || log_warn "[${RULE_NAME}] Failed to capture vxrest.log from pod $pod"
    echo "" >> "${VXREST_LOGS_FILE}"
    echo "" >> "${VXREST_LOGS_FILE}"
}


check_vxvm_health_in_pods() {
        local fail=false
        [[ -z "${VXREST_LOGS_FILE:-}" ]] && VXREST_LOGS_FILE="${LOG_DIR:-/tmp}/consolidated_vxrest_logs.log"
        : > "${VXREST_LOGS_FILE}"
        echo "=====================================================" >> "${VXREST_LOGS_FILE}"
        echo "VxREST Logs Consolidated - $(date)" >> "${VXREST_LOGS_FILE}"
        echo "=====================================================" >> "${VXREST_LOGS_FILE}"
        echo "" >> "${VXREST_LOGS_FILE}"

        IKE_troubleshooting_doc="$(jq -r '.IKE_troubleshooting.url' "$DOC_REFERENCE")"
        log_info "[${RULE_NAME}] Checking InfoScale Volumes/Disks/Diskgroup health inside SDS pods"
        echo "----------------------------------------"

        local pods
        pods="$(get_sds_pods)"
        if [[ -z "$pods" ]]; then
            log_error "[${RULE_NAME}] No SDS pods found"
            return 1
        fi

        while read -r line; do
            [[ -z "$line" ]] && continue

            local ns pod status node
            read -r ns pod ready status node <<<"$(awk '{print $1, $2, $3, $4, $8}' <<<"$line")"
            
            log_info "[${RULE_NAME}] InfoScale Pod $pod on node $node has status $status"
            
            # Run all checks for this pod
            check_pod_readiness_status "$ns" "$pod" "$ready" "$status"              || fail=true
            check_diskgroup_imported "$ns" "$pod" "$node"                           || fail=true
            check_volume_states "$ns" "$pod"                                         || fail=true
            check_background_sync_tasks "$ns" "$pod"                                 || fail=true
            check_snap_associations "$ns" "$pod" "$node"                             || fail=true
            check_disk_health_status "$ns" "$pod" "$node"                            || fail=true
            check_split_brain "$ns" "$pod" "$node"                                   || fail=true
            capture_pod_vxrest_logs "$ns" "$pod" "$node"
        done <<<"$pods"
        
        $fail && return 1 || return 0
}


# Exec phase
run() {
        echo "-----------------------------------------------------------------------------------------------------"
        echo "[${RULE_NAME}]"
        echo "-----------------------------------------------------------------------------------------------------"

        local FAIL=false
        ensure_context || return 1
        check_sourcecluster_get    || FAIL=true
        check_sourcecluster_details  || FAIL=true
        check_node_join_status       || FAIL=true
        check_spec_status_mismatch   || FAIL=true
        check_vxvm_health_in_pods    || FAIL=true

        if [[ "${FAIL}" == "true" ]]; then
                log_error "[${RULE_NAME}] One or more IKE cluster health checks failed."
                return 1
        fi

        log_info "[${RULE_NAME}] All IKE cluster health  checks passed"
        return 0
}
