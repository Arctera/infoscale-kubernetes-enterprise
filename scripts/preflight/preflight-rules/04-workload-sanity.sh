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

RULE_NAME="Workload Sanity"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

source "${ROOT_DIR}/lib/cr_utils.sh"

KUBE_CLI=""

WORKLOAD_SANITY_CACHE_READY=false
WORKLOAD_SANITY_PODS_JSON=""
WORKLOAD_SANITY_DEPLOYMENT_JSON=""
WORKLOAD_SANITY_STATEFULSET_JSON=""
WORKLOAD_SANITY_DAEMONSET_JSON=""
WORKLOAD_SANITY_REPLICASET_JSON=""
declare -A WORKLOAD_SANITY_INFOSCALE_PVC=()
declare -A WORKLOAD_SANITY_INFOSCALE_POD=()
config() {
        log_info "[${RULE_NAME}] Configuration successful"

        return 0
}
ensure_context() {
        if [[ -z "${KUBE_CLI:-}" ]]; then
                detect_kube_cli || {
                log_error "[${RULE_NAME}] Failed to detect kube client"
                return 1
                }
        fi
        
        return 0
        }


is_excluded_pod_namespace() {
        local ns="${1:-}"
        is_excluded_namespace "$ns" || [[ "$ns" == cert-manager* ]]
}
is_excluded_namespace() {
        local ns="${1:-}"
        [[ -n "$ns" && "$ns" == openshift-* ]]
}

should_ignore_pod_by_owner_kind() {
        local ns="${1:-}"
        local owner_ref_kinds="${2:-}"
        local pod_name="${3:-}"

        [[ -z "${owner_ref_kinds}" ]] && return 1

        if [[ "${owner_ref_kinds}" == *"StatefulSet"* || "${owner_ref_kinds}" == *"DaemonSet"* || "${owner_ref_kinds}" == *"Deployment"* ]]; then
                return 0
        fi

        if [[ "${owner_ref_kinds}" != *"ReplicaSet"* || -z "${pod_name}" ]]; then
                return 1
        fi

        local owner_rs
        owner_rs=$(jq -r --arg ns "${ns}" --arg pod "${pod_name}" '
                .items[]
                | select(.metadata.namespace == $ns and .metadata.name == $pod)
                | (.metadata.ownerReferences // [])[]?
                | select(.kind == "ReplicaSet")
                | .name
        ' <<<"${WORKLOAD_SANITY_PODS_JSON:-}" 2>/dev/null | head -n1)

        [[ -z "${owner_rs}" ]] && return 1

        jq -e --arg ns "${ns}" --arg rs "${owner_rs}" '
                .items[]
                | select(.metadata.namespace == $ns and .metadata.name == $rs)
                | (.metadata.ownerReferences // [])[]?
                | select(.kind == "Deployment")
        ' <<<"${WORKLOAD_SANITY_REPLICASET_JSON:-}" >/dev/null 2>&1 && return 0

        return 1
}
get_live_pods_json() {
        local pods_json

        if [[ -n "${KUBE_CLI:-}" ]]; then
                pods_json="$(${KUBE_CLI} get pods -A -o json 2>/dev/null || true)"
                if [[ -n "${pods_json}" ]] && jq -e '.items' <<<"${pods_json}" >/dev/null 2>&1; then
                        echo "${pods_json}"
                        return 0
                fi
        fi

        get_manifest_json pods namespaced 2>/dev/null || echo '{"items":[]}'
}

get_live_or_cached_json() {
        local resource="${1:-}"
        local scope="${2:-namespaced}"
        local json=""

        if [[ -n "${KUBE_CLI:-}" ]]; then
                if [[ "$scope" == "cluster" ]]; then
                        json="$(${KUBE_CLI} get ${resource} -o json 2>/dev/null || true)"
                else
                        json="$(${KUBE_CLI} get ${resource} -A -o json 2>/dev/null || true)"
                fi
                if [[ -n "${json}" ]] && jq -e '.items' <<<"${json}" >/dev/null 2>&1; then
                        echo "${json}"
                        return 0
                fi
        fi

        get_manifest_json "${resource}" "${scope}" 2>/dev/null || echo '{"items":[]}'
}

check_pvc_status() {
        local tmpfile="$1"
        local fail=false

        log_info "[${RULE_NAME}] Checking PVC status across all namespaces..."

        while IFS=$'\t' read -r ns pvc phase sc access_modes volume deleting; do
                [[ -z "${pvc}" ]] && continue

                if [[ "${phase}" != "Bound" || "${deleting}" == "true" ]]; then
                        local pvc_issue="PVC not Bound (phase: ${phase:-Unknown}, SC: ${sc:-none})"
                        if [[ "${deleting}" == "true" ]]; then
                                pvc_issue="PVC in Terminating state (phase: ${phase:-Unknown}, SC: ${sc:-none})"
                        fi

                        printf '%s\t%s\t%s\t%s\t%s\n' \
                                "${ns}" "${pvc}" "pvc" \
                                "${pvc_issue}" \
                                "${KUBE_CLI} describe pvc ${pvc} -n ${ns}" >>"$tmpfile"
                        fail=true
                fi
        done < <(
                get_manifest_json pvc namespaced | jq -r '
                .items[] |
                [
                  .metadata.namespace,
                  .metadata.name,
                  (.status.phase // "Unknown"),
                  (.spec.storageClassName // "none"),
                  ((.status.accessModes // []) | join(",")),
                  (.spec.volumeName // "none"),
                  ((.metadata.deletionTimestamp != null) | tostring)
                ] | @tsv
                '
        )

        if [[ "${fail}" == "true" ]]; then
                log_warn "[${RULE_NAME}] Found PVCs that are not Bound or are Terminating."
                return 1
        fi

        return 0
}

init_workload_sanity_cache() {
        [[ "${WORKLOAD_SANITY_CACHE_READY}" == "true" ]] && return 0

        local sc_json pvc_json pv_json
        local -A sc_prov_map=()
        local -A pv_csi_map=()

        WORKLOAD_SANITY_PODS_JSON="$(get_live_pods_json)"
        WORKLOAD_SANITY_DEPLOYMENT_JSON="$(get_manifest_json deployment namespaced 2>/dev/null || echo '{"items":[]}')"
        WORKLOAD_SANITY_STATEFULSET_JSON="$(get_manifest_json statefulset namespaced 2>/dev/null || echo '{"items":[]}')"
        WORKLOAD_SANITY_DAEMONSET_JSON="$(get_manifest_json daemonset namespaced 2>/dev/null || echo '{"items":[]}')"
        WORKLOAD_SANITY_REPLICASET_JSON="$(get_manifest_json replicaset namespaced 2>/dev/null || echo '{"items":[]}')"

        sc_json="$(get_live_or_cached_json storageclass cluster)"
        while IFS=$'\t' read -r sc prov; do
                [[ -z "${sc}" || -z "${prov}" ]] && continue
                sc_prov_map["${sc}"]="${prov}"
        done < <(
                jq -r '.items[] | [.metadata.name, (.provisioner // "")] | @tsv' <<<"$sc_json" 2>/dev/null
        )

        pv_json="$(get_live_or_cached_json pv cluster)"
        while IFS=$'\t' read -r pv csi; do
                [[ -z "${pv}" || -z "${csi}" ]] && continue
                pv_csi_map["${pv}"]="${csi}"
        done < <(
                jq -r '.items[] | [.metadata.name, (.spec.csi.driver // .metadata.annotations["pv.kubernetes.io/provisioned-by"] // "")] | @tsv' <<<"$pv_json" 2>/dev/null
        )

        pvc_json="$(get_live_or_cached_json pvc namespaced)"
        while IFS=$'\t' read -r ns pvc sc vol pvc_prov; do
                [[ -z "${ns}" || -z "${pvc}" ]] && continue
                if [[ -n "${pvc_prov}" && "${pvc_prov}" =~ (org.veritas.infoscale|infoscale|veritas) ]]; then
                        WORKLOAD_SANITY_INFOSCALE_PVC["${ns}/${pvc}"]=1
                        continue
                fi


                if [[ -n "${sc}" && "${sc_prov_map["$sc"]:-}" =~ (org\.veritas\.infoscale|infoscale|veritas) ]]; then
                        WORKLOAD_SANITY_INFOSCALE_PVC["${ns}/${pvc}"]=1
                        continue
                fi

                if [[ -n "${vol}" && "${pv_csi_map["$vol"]:-}" =~ (org\.veritas\.infoscale|infoscale|veritas) ]]; then
                        WORKLOAD_SANITY_INFOSCALE_PVC["${ns}/${pvc}"]=1
                fi
        done < <(
                jq -r ' .items[] | [.metadata.namespace, .metadata.name, (.spec.storageClassName // ""), (.spec.volumeName // ""), (.metadata.annotations["volume.kubernetes.io/storage-provisioner"] // .metadata.annotations["volume.beta.kubernetes.io/storage-provisioner"] // "")] | @tsv ' <<<"$pvc_json" 2>/dev/null
        )

        while IFS=$'\t' read -r ns pod inline_csi pvcs; do
                [[ -z "${ns}" || -z "${pod}" ]] && continue
                if is_excluded_namespace "$ns"; then
                        continue
                fi
                if [[ "${inline_csi}" == "true" ]]; then
                        WORKLOAD_SANITY_INFOSCALE_POD["${ns}/${pod}"]=1
                        continue
                fi
                IFS="," read -r -a _pvcs <<< "${pvcs:-}"
                for pvc in "${_pvcs[@]}"; do
                        [[ -z "${pvc}" ]] && continue
                        if [[ -n "${WORKLOAD_SANITY_INFOSCALE_PVC["${ns}/${pvc}"]:-}" ]]; then
                                WORKLOAD_SANITY_INFOSCALE_POD["${ns}/${pod}"]=1
                                break
                        fi
                done
        done < <(
                jq -r '
                .items[]
                | [
                  .metadata.namespace,
                  .metadata.name,
                  (any((.spec.volumes // [])[]?; ((.csi.driver // "") | test("(org\.veritas\.infoscale|infoscale|veritas)"; "i")))) | tostring,
                  ([ (.spec.volumes // [])[]? | select(.persistentVolumeClaim?) | .persistentVolumeClaim.claimName ] | unique | join(","))
                ] | @tsv
                ' <<<"$WORKLOAD_SANITY_PODS_JSON" 2>/dev/null
        )
        WORKLOAD_SANITY_CACHE_READY=true
        return 0
}

is_workload_backed_by_infoscale_csi() {
        local ns="$1" name="$2" typ="$3"
        local pvcs workload_json pvc

        init_workload_sanity_cache || return 1

        if [[ "$typ" == "pod" ]]; then
                [[ -n "${WORKLOAD_SANITY_INFOSCALE_POD["${ns}/${name}"]:-}" ]] && return 0
                return 1
        else
                case "$typ" in
                        deployment) workload_json="$WORKLOAD_SANITY_DEPLOYMENT_JSON" ;;
                        statefulset) workload_json="$WORKLOAD_SANITY_STATEFULSET_JSON" ;;
                        daemonset) workload_json="$WORKLOAD_SANITY_DAEMONSET_JSON" ;;
                        job) workload_json="$(get_manifest_json job namespaced 2>/dev/null || echo '{"items":[]}')" ;;
                        *) return 1 ;;
                esac

                pvcs="$(jq -r --arg ns "$ns" --arg name "$name" '
                        .items[]
                        | select(.metadata.namespace == $ns and .metadata.name == $name)
                        | (.spec.template.spec.volumes // [])[]?
                        | select(.persistentVolumeClaim?)
                        | .persistentVolumeClaim.claimName
                ' <<<"$workload_json" 2>/dev/null | sort -u)"
        fi

        [[ -z "$pvcs" ]] && return 1

        while IFS= read -r pvc; do
                [[ -z "$pvc" ]] && continue
                [[ -n "${WORKLOAD_SANITY_INFOSCALE_PVC["${ns}/${pvc}"]:-}" ]] && return 0
        done <<<"$pvcs"

        return 1
}
should_ignore_native_workload() {
        local ns="${1:-}"
        local name="${2:-}"
        local typ="${3:-}"

        [[ "$typ" != "deployment" ]] && return 1

        case "${ns}/${name}" in
                cert-manager-operator/cert-manager-operator-controller-manager|infoscale-vtas/infoscale-csi-controller|infoscale-vtas/infoscale-fencing-controller)
                return 0
                ;;
        esac

        return 1
}

check_native_workloads() {
        local tmpfile="$1"
        log_info "[${RULE_NAME}] Checking Kubernetes workloads for single-node affinity or placement locks..."

        init_workload_sanity_cache || return 1
        get_live_pods_json |
                jq -r '
        .items[] |
        {
          ns: .metadata.namespace,
          name: .metadata.name,
          nodeSelector: (.spec.nodeSelector // {}),
          nodeAffinity: (.spec.affinity.nodeAffinity.requiredDuringSchedulingIgnoredDuringExecution // {}),
          podAffinity: ((((.spec.affinity.podAffinity.requiredDuringSchedulingIgnoredDuringExecution // []) | length) + ((.spec.affinity.podAffinity.preferredDuringSchedulingIgnoredDuringExecution // []) | length))),
          podAntiAffinity: ((((.spec.affinity.podAntiAffinity.requiredDuringSchedulingIgnoredDuringExecution // []) | length) + ((.spec.affinity.podAntiAffinity.preferredDuringSchedulingIgnoredDuringExecution // []) | length))),
          nodeName: (.spec.nodeName // ""),
          ownerRefCount: ((.metadata.ownerReferences // []) | length),
          ownerRefKinds: [(.metadata.ownerReferences // [])[] | .kind? // empty] | unique,
          phase: (.status.phase // "Unknown"),
          waitingReasons: [
            (.status.initContainerStatuses // [])[],
            (.status.containerStatuses // [])[]
          ] | map(.state.waiting.reason? // empty) | unique
        } |
        [
          .ns,
          .name,
          "pod",
          "1",
          (if (.nodeSelector|length>0) then "nodeSelector"
           elif (.nodeAffinity|length>0) then "nodeAffinity"
           elif (.podAffinity>0) then "podAffinity"
           elif (.podAntiAffinity>0) then "podAntiAffinity"
           else "none" end),
          .nodeName,
          (.ownerRefCount|tostring),
          (.ownerRefKinds | join(",")),
          .phase,
          (.waitingReasons | join(","))
        ] | @tsv
      ' | while IFS=$'\t' read -r ns name typ replicas placement nodeName ownerRefCount ownerRefKinds phase waitingReasons; do

                if is_excluded_pod_namespace "$ns"; then
                        continue
                fi

                if [[ "${name}" == virt-launcher-* ]]; then
                        continue
                fi

                if should_ignore_pod_by_owner_kind "$ns" "${ownerRefKinds:-}" "$name"; then
                        continue
                fi

                local owner_ref_type csi_type state_flags
                owner_ref_type="withoutOwnerRef"
                if [[ "${ownerRefCount:-0}" =~ ^[0-9]+$ ]] && (( ownerRefCount > 0 )); then
                        owner_ref_type="withOwnerRef"
                fi

                csi_type="non-InfoScale"
                if is_workload_backed_by_infoscale_csi "$ns" "$name" "pod"; then
                        csi_type="InfoScale-CSI"
                        printf "%s\t%s\t%s\t%s\t%s\n" \
                                "$ns" "$name" "$typ" \
                                "ERROR: InfoScale CSI-backed pod detected (ownerRefType=${owner_ref_type}, phase=${phase:-Unknown}, waitingReasons=${waitingReasons:-none})" \
                                "Move workload to non-InfoScale CSI storage or ensure controller-managed rescheduling before upgrade" >>"$tmpfile"
                fi

                printf "%s\t%s\t%s\t%s\t%s\n" \
                        "$ns" "$name" "$typ" \
                        "Pod detected (ownerRefType=${owner_ref_type}, csiType=${csi_type}, placementType=${placement})" \
                        "Validate whether this pod can be recreated or safely rescheduled during upgrade" >>"$tmpfile"

                state_flags=()
                if [[ "${phase:-Unknown}" == "Pending" ]]; then
                        state_flags+=("Pending")
                fi
                if [[ "${waitingReasons:-}" == *"CrashLoopBackOff"* ]]; then
                        state_flags+=("CrashLoopBackOff")
                fi

                if [[ "${#state_flags[@]}" -gt 0 ]]; then
                        local state_summary
                        state_summary=$(IFS=','; echo "${state_flags[*]}")
                        printf "%s\t%s\t%s\t%s\t%s\n" \
                                "$ns" "$name" "$typ" \
                                "ERROR: Pod in blocking state (state=${state_summary}, ownerRefType=${owner_ref_type}, csiType=${csi_type}, phase=${phase:-Unknown}, waitingReasons=${waitingReasons:-none})" \
                                "Investigate scheduling/container failures and clear blocking state before upgrade" >>"$tmpfile"
                fi
        done

        for type in deployment statefulset daemonset job; do
                get_manifest_json "$type" namespaced |
                        jq -r --arg TYPE "$type" '
        .items[] |
        {
          ns: .metadata.namespace,
          name: .metadata.name,
          nodeSelector: (.spec.template.spec.nodeSelector // {}),
          nodeAffinity: (.spec.template.spec.affinity.nodeAffinity.requiredDuringSchedulingIgnoredDuringExecution // {}),
          podAffinity: ((((.spec.template.spec.affinity.podAffinity.requiredDuringSchedulingIgnoredDuringExecution // []) | length) + ((.spec.template.spec.affinity.podAffinity.preferredDuringSchedulingIgnoredDuringExecution // []) | length))),
          podAntiAffinity: ((((.spec.template.spec.affinity.podAntiAffinity.requiredDuringSchedulingIgnoredDuringExecution // []) | length) + ((.spec.template.spec.affinity.podAntiAffinity.preferredDuringSchedulingIgnoredDuringExecution // []) | length))),
          ownerRefs: (.metadata.ownerReferences // []),
          replicas: (.spec.replicas // 1)
        } |
        [
          .ns,
          .name,
          $TYPE,
          (.replicas|tostring),
          (if (.nodeSelector|length>0) then "nodeSelector"
           elif (.nodeAffinity|length>0) then "nodeAffinity"
           elif (.podAffinity>0) then "podAffinity"
           elif (.podAntiAffinity>0) then "podAntiAffinity"
           else "none" end),
          (if (.ownerRefs|length>0) then "owned" else "unowned" end)
        ] | @tsv
      ' | while IFS=$'\t' read -r ns name typ replicas placement ownership; do

                        if is_excluded_namespace "$ns"; then
                                continue
                        fi

                        if [[ "$ns" == "cert-manager" && "$typ" == "deployment" ]]; then
                                case "$name" in
                                        cert-manager|cert-manager-cainjector|cert-manager-webhook)
                                        continue
                                        ;;
                                esac
                        fi

                        if [[ "$typ" == "daemonset" ]]; then
                                continue
                        fi

                        if should_ignore_native_workload "$ns" "$name" "$typ"; then
                                continue
                        fi

                        if [[ "$typ" == "job" ]] && is_workload_backed_by_infoscale_csi "$ns" "$name" "$typ"; then
                                printf "%s\t%s\t%s\t%s\t%s\n" \
                                        "$ns" "$name" "$typ" \
                                        "ERROR: Job uses InfoScale CSI-backed PVC" \
                                        "Move workload to non-InfoScale CSI storage or complete and remove the Job before upgrade" >>"$tmpfile"
                        fi

                        local nodes node_count workload_json selector_json

                        case "$typ" in
                                deployment) workload_json="$WORKLOAD_SANITY_DEPLOYMENT_JSON" ;;
                                statefulset) workload_json="$WORKLOAD_SANITY_STATEFULSET_JSON" ;;
                                daemonset) workload_json="$WORKLOAD_SANITY_DAEMONSET_JSON" ;;
                                job) workload_json="$(get_manifest_json job namespaced 2>/dev/null || echo '{"items":[]}')" ;;
                                *) workload_json='{"items":[]}' ;;
                        esac

                        selector_json=$(jq -c --arg ns "$ns" --arg name "$name" '
                                .items[]
                                | select(.metadata.namespace == $ns and .metadata.name == $name)
                                | (.spec.selector.matchLabels // {})
                        ' <<<"$workload_json" 2>/dev/null | head -n1)

                        if [[ "$typ" == "job" ]] && [[ -z "$selector_json" || "$selector_json" == "{}" ]]; then
                                selector_json=$(jq -c --arg ns "$ns" --arg name "$name" '
                                        .items[]
                                        | select(.metadata.namespace == $ns and .metadata.name == $name)
                                        | (.spec.template.metadata.labels // {})
                                ' <<<"$workload_json" 2>/dev/null | head -n1)
                        fi

                        if [[ -n "$selector_json" && "$selector_json" != "{}" ]]; then
                                nodes=$(jq -r --arg ns "$ns" --argjson sel "$selector_json" '
                                        def selector_match($labels; $sel):
                                                ($sel | to_entries | all((($labels[.key] // "") == (.value | tostring))));
                                        .items[]
                                        | select(.metadata.namespace == $ns)
                                        | select(selector_match((.metadata.labels // {}); $sel))
                                        | .spec.nodeName // empty
                                ' <<<"$WORKLOAD_SANITY_PODS_JSON" 2>/dev/null | sed '/^$/d' | sort -u | xargs || true)
                        else
                                nodes=""
                        fi

                        if [[ -z "$nodes" ]]; then
                                nodes="none"
                                node_count=0
                        else
                                node_count=$(wc -w <<< "$nodes")
                        fi

                        if [[ "$placement" == "podAffinity" || "$placement" == "podAntiAffinity" ]]; then
                                printf "%s\t%s\t%s\t%s\t%s\n" \
                                        "$ns" "$name" "$typ" \
                                        "Affinity-based workload detected (placementType=${placement}, ownership=${ownership})" \
                                        "Validate affinity terms and ensure alternate nodes exist for safe drain/reschedule" >>"$tmpfile"
                        fi

                        if [[ "$placement" != "none" && "$node_count" -le 1 ]]; then
                                printf "%s\t%s\t%s\t%s\t%s\n" \
                                        "$ns" "$name" "$typ" \
                                        "Single-node bound workload (placementType=$placement): no failover node available during drain/reboot" \
                                        "Relax affinity/selector constraints so pods can run on multiple worker nodes" >>"$tmpfile"
                        fi
                done
        done

}
print_workload_constraints_warning() {
        local rule="$1"

        log_warn "[${rule}] Workload risks detected — resolve all issues before proceeding with upgrade."
        log_warn "[${rule}] The table below lists each affected workload, the issue found, and the recommended fix."
}



check_infoscale_vms_cached() {
        local tmpfile="$1"
        log_info "[${RULE_NAME}] Checking Infoscale PVC-backed VMs for RWX & LiveMigratable..."

        local fail=false
        local vm_list vm_json vmi_json dv_json pvc_json

        # Reuse the shared cache which already identifies all InfoScale-backed PVCs
        # (handles SC provisioner, PV CSI driver, and PVC annotation fallbacks)
        init_workload_sanity_cache || return 1

        vm_json="$(get_live_or_cached_json vm namespaced)"
        if [[ "$(jq -r '.items | length' <<<"$vm_json" 2>/dev/null || echo 0)" -eq 0 ]]; then
                log_info "[${RULE_NAME}] No VirtualMachine resources found, skipping."
                return 0
        fi

        vmi_json="$(get_live_or_cached_json vmi namespaced)"
        dv_json="$(get_live_or_cached_json dv namespaced)"
        pvc_json="$(get_live_or_cached_json pvc namespaced)"

        # Collect every PVC/DV volume from VM template spec and VMI spec, deduplicated
        vm_list=$(
                {
                        jq -r '
                          .items[] |
                          .metadata.namespace as $ns |
                          .metadata.name as $vm |
                          (.spec.template.spec.volumes // [])[] |
                          if has("persistentVolumeClaim") then
                            "\($ns) \($vm) pvc \(.persistentVolumeClaim.claimName)"
                          elif has("dataVolume") then
                            "\($ns) \($vm) dv \(.dataVolume.name)"
                          else
                            empty
                          end
                        ' <<<"$vm_json" 2>/dev/null || true

                        jq -r '
                          .items[] |
                          .metadata.namespace as $ns |
                          .metadata.name as $vm |
                          (.spec.volumes // [])[] |
                          if has("persistentVolumeClaim") then
                            "\($ns) \($vm) pvc \(.persistentVolumeClaim.claimName)"
                          elif has("dataVolume") then
                            "\($ns) \($vm) dv \(.dataVolume.name)"
                          else
                            empty
                          end
                        ' <<<"$vmi_json" 2>/dev/null || true
                } | sed '/^$/d' | sort -u
        )

        while read -r ns vm vtype vol; do
                [[ -z "$vol" ]] && continue

                local pvc access_mode migratable sc

                if [[ "$vtype" == "pvc" ]]; then
                        pvc="$vol"
                else
                        # DataVolume -> PVC resolution with multiple fallbacks for non-simple disk flows
                        pvc=$(jq -r --arg ns "$ns" --arg dv "$vol" '
                          .items[]
                          | select(.metadata.namespace == $ns and .metadata.name == $dv)
                          | .status.claimName // empty
                        ' <<<"$dv_json" 2>/dev/null | head -n1)

                        if [[ -z "$pvc" ]]; then
                                pvc=$(jq -r --arg ns "$ns" --arg dv "$vol" '
                                  .items[]
                                  | select(.metadata.namespace == $ns)
                                  | select(any((.metadata.ownerReferences // [])[]?; .kind == "DataVolume" and .name == $dv))
                                  | .metadata.name
                                ' <<<"$pvc_json" 2>/dev/null | head -n1)
                        fi

                        if [[ -z "$pvc" ]]; then
                                pvc=$(jq -r --arg ns "$ns" --arg dv "$vol" '
                                  .items[]
                                  | select(.metadata.namespace == $ns)
                                  | select((.metadata.annotations["cdi.kubevirt.io/storage.populatedFor"] // "") == $dv
                                           or (.metadata.annotations["cdi.kubevirt.io/dataVolumeName"] // "") == $dv)
                                  | .metadata.name
                                ' <<<"$pvc_json" 2>/dev/null | head -n1)
                        fi

                        [[ -z "$pvc" ]] && pvc="$vol"
                        [[ -z "$pvc" ]] && continue
                fi

                sc=$(jq -r --arg ns "$ns" --arg pvc "$pvc" '
                  .items[]
                  | select(.metadata.namespace == $ns and .metadata.name == $pvc)
                  | .spec.storageClassName // empty
                ' <<<"$pvc_json" 2>/dev/null | head -n1)

                # Use shared InfoScale map, but also fall back to StorageClass name heuristic.
                local is_infoscale_pvc sc_lc
                is_infoscale_pvc=false
                if [[ -n "${WORKLOAD_SANITY_INFOSCALE_PVC["${ns}/${pvc}"]:-}" ]]; then
                        is_infoscale_pvc=true
                else
                        sc_lc="$(printf '%s' "${sc:-}" | tr '[:upper:]' '[:lower:]')"
                        [[ "$sc_lc" =~ (infoscale|veritas) ]] && is_infoscale_pvc=true
                fi
                [[ "$is_infoscale_pvc" != "true" ]] && continue

                access_mode=$(jq -r --arg ns "$ns" --arg pvc "$pvc" '
                  .items[]
                  | select(.metadata.namespace == $ns and .metadata.name == $pvc)
                  | .status.accessModes[0] // .spec.accessModes[0] // empty
                ' <<<"$pvc_json" 2>/dev/null | head -n1)

                migratable=$(jq -r --arg ns "$ns" --arg vm "$vm" '
                  .items[]
                  | select(.metadata.namespace == $ns and .metadata.name == $vm)
                  | (.status.conditions // [])[]?
                  | select(.type == "LiveMigratable")
                  | .status // empty
                ' <<<"$vmi_json" 2>/dev/null | head -n1)
                if [[ -z "$migratable" ]]; then
                        migratable=$(jq -r --arg ns "$ns" --arg vm "$vm" '
                          .items[]
                          | select(.metadata.namespace == $ns and .metadata.name == $vm)
                          | (.status.conditions // [])[]?
                          | select(.type == "LiveMigratable")
                          | .status // empty
                        ' <<<"$vm_json" 2>/dev/null | head -n1)
                fi

                if [[ "$access_mode" != "ReadWriteMany" ]]; then
                        printf "%s\t%s\t%s\t%s\t%s\n" \
                                "$ns" "$vm" "vm" \
                                "ERROR: VM PVC is not ReadWriteMany (PVC: ${pvc}, SC: ${sc:-unknown}, accessMode: ${access_mode:-unknown})" \
                                "Convert PVC to ReadWriteMany to allow live migration during node drain" >>"$tmpfile"
                        fail=true
                fi
                if [[ "$migratable" != "True" ]]; then
                        printf "%s\t%s\t%s\t%s\t%s\n" \
                                "$ns" "$vm" "vm" \
                                "ERROR: VM is not LiveMigratable (PVC: ${pvc}, SC: ${sc:-unknown}, accessMode: ${access_mode:-unknown}, liveMigratable: ${migratable:-unknown})" \
                                "Ensure VM uses RWX storage and verify LiveMigratable condition before upgrade" >>"$tmpfile"
                        fail=true
                fi

        done <<<"$vm_list"

        if [[ "$fail" == "true" ]]; then
                log_warn "[${RULE_NAME}] Found InfoScale CSI-backed VMs that are not RWX or not LiveMigratable."
                return 1
        fi
        return 0
}
node_is_tolerated() {
        local ns="$1"
        local vm="$2"
        local node="$3"

        local node_json vm_json
        node_json="$(get_manifest_json nodes cluster 2>/dev/null | jq -c --arg node "$node" '.items[] | select(.metadata.name == $node)' 2>/dev/null | head -n1)"
        vm_json="$(get_manifest_json vm namespaced 2>/dev/null | jq -c --arg ns "$ns" --arg vm "$vm" '.items[] | select(.metadata.namespace == $ns and .metadata.name == $vm)' 2>/dev/null | head -n1)"

        [[ -z "$node_json" || -z "$vm_json" ]] && return 1
        node_is_tolerated_json "$node_json" "$vm_json"
}

node_is_tolerated_json() {
        local node_json="$1"
        local vm_json="$2"

        jq -e -n \
        --argjson node "$node_json" \
        --argjson vm "$vm_json" '
        def tolerated($t; $tols):
                any($tols[]?;
                if ((.operator // "Equal") == "Exists") then
                (.key == $t.key) and (((.effect // "") == "") or (.effect == $t.effect))
                else
                (.key == $t.key)
                and (((.effect // "") == "") or (.effect == $t.effect))
                and ((.value // "") == ($t.value // ""))
                end
                );

        ($node.spec.taints // []) as $taints
        | ($vm.spec.template.spec.tolerations // []) as $tols
        | [ $taints[]
                | select(.effect == "NoSchedule" or .effect == "NoExecute")
                | select(tolerated(.; $tols) | not)
                ]
        | length == 0
        ' >/dev/null 2>&1
}

check_virtual_machines()
{
        local tmpfile="$1"
        log_info "[${RULE_NAME}] Checking VirtualMachines workloads for hostPath-backed storage, node-affined placement, and anti-affinity..."

        local vm_json vmi_json dv_json pvc_json sc_json pod_json node_json
        vm_json="$(get_manifest_json vm namespaced 2>/dev/null || echo '{"items":[]}')"
        vmi_json="$(get_manifest_json vmi namespaced 2>/dev/null || echo '{"items":[]}')"
        dv_json="$(get_manifest_json dv namespaced 2>/dev/null || echo '{"items":[]}')"
        if [[ "$(jq -r '.items | length' <<<"$vm_json" 2>/dev/null || echo 0)" -eq 0 ]]; then
                log_info "[${RULE_NAME}] No VirtualMachine resources found, skipping."
                return 0
        fi
        pvc_json="$(get_manifest_json pvc namespaced 2>/dev/null || echo '{"items":[]}')"
        sc_json="$(get_manifest_json storageclass cluster 2>/dev/null || echo '{"items":[]}')"
        pod_json="$(get_manifest_json pods namespaced 2>/dev/null || echo '{"items":[]}')"
        node_json="$(get_manifest_json nodes cluster 2>/dev/null || echo '{"items":[]}')"

        local ready_worker_nodes
        ready_worker_nodes=$(jq -r '
                .items[]
                | select((.metadata.labels // {} | has("node-role.kubernetes.io/worker")))
                | select((.status.conditions // []) | any(.type == "Ready" and .status == "True"))
                | .metadata.name
        ' <<<"$node_json" 2>/dev/null | sort -u)

        jq -r '
        .items[] |
        {
          ns: .metadata.namespace,
          name: .metadata.name,

          hasNodeSelector: (
            ((.spec.template.spec.nodeSelector // {}) | length) > 0
          ),

          hasRequiredNodeAffinity: (
            ((.spec.template.spec.affinity.nodeAffinity
              .requiredDuringSchedulingIgnoredDuringExecution
              .nodeSelectorTerms) // [] | length) > 0
          ),

          hasRequiredPodAntiAffinity: (
            ((.spec.template.spec.affinity.podAntiAffinity
              .requiredDuringSchedulingIgnoredDuringExecution) // [] | length) > 0
          ),

          tolerations: (.spec.template.spec.tolerations // []),

          volumeRefs: (
            [
              (.spec.template.spec.volumes // [])[]? |
              if has("persistentVolumeClaim") then ("pvc:" + .persistentVolumeClaim.claimName)
              elif has("dataVolume") then ("dv:" + .dataVolume.name)
              else empty end
            ] | unique
          )
        } |
        [
          .ns,
          .name,
          (.hasNodeSelector | tostring),
          (.hasRequiredNodeAffinity | tostring),
          (.hasRequiredPodAntiAffinity | tostring),
          ((.tolerations | length) | tostring),
          (.volumeRefs | join(","))
        ] | @tsv
        ' <<<"$vm_json" | while IFS=$'\t' read -r ns vm has_node_selector has_node_affinity has_pod_anti_affinity toler_count pvc_list; do
                if is_excluded_namespace "$ns"; then
                        continue
                fi
                local hostpath_match=0
                local nodeconstrained_match=0
                local antiaffinity_match=0
                local hostpath_details=""
                local nodeconstrained_details=""
                local antiaffinity_details=""

                local vm_obj
                vm_obj=$(jq -c --arg ns "$ns" --arg vm "$vm" '
                        .items[] | select(.metadata.namespace == $ns and .metadata.name == $vm)
                ' <<<"$vm_json" 2>/dev/null | head -n1)
                [[ -z "$vm_obj" ]] && continue
                if [[ -n "$pvc_list" ]]; then
                        IFS=',' read -r -a refs <<< "$pvc_list"
                        for ref in "${refs[@]}"; do
                                [[ -z "$ref" ]] && continue

                                local kind="${ref%%:*}"
                                local name="${ref#*:}"
                                local claim="" prov sc sc_prov sel_node

                                [[ -z "$name" ]] && continue

                                if [[ "$kind" == "pvc" ]]; then
                                        claim="$name"
                                elif [[ "$kind" == "dv" ]]; then
                                        claim=$(jq -r --arg ns "$ns" --arg dv "$name" '
                                                .items[]
                                                | select(.metadata.namespace == $ns and .metadata.name == $dv)
                                                | .status.claimName // empty
                                        ' <<<"$dv_json" 2>/dev/null | head -n1)
                                fi

                                [[ -z "$claim" ]] && continue

                                sc=$(jq -r --arg ns "$ns" --arg pvc "$claim" '
                                        .items[]
                                        | select(.metadata.namespace == $ns and .metadata.name == $pvc)
                                        | .spec.storageClassName // empty
                                ' <<<"$pvc_json" 2>/dev/null | head -n1)

                                sc_prov=""
                                if [[ -n "$sc" ]]; then
                                        sc_prov=$(jq -r --arg sc "$sc" '
                                                .items[]
                                                | select(.metadata.name == $sc)
                                                | .provisioner // empty
                                        ' <<<"$sc_json" 2>/dev/null | head -n1)
                                fi

                                prov=$(jq -r --arg ns "$ns" --arg pvc "$claim" '
                                        .items[]
                                        | select(.metadata.namespace == $ns and .metadata.name == $pvc)
                                        | .metadata.annotations["volume.kubernetes.io/storage-provisioner"]
                                          // .metadata.annotations["volume.beta.kubernetes.io/storage-provisioner"]
                                          // empty
                                ' <<<"$pvc_json" 2>/dev/null | head -n1)

                                if [[ "$sc_prov" == "kubevirt.io.hostpath-provisioner" || "$prov" == "kubevirt.io.hostpath-provisioner" ]]; then
                                        hostpath_match=1
                                        sel_node=$(jq -r --arg ns "$ns" --arg pvc "$claim" '
                                                .items[]
                                                | select(.metadata.namespace == $ns and .metadata.name == $pvc)
                                                | .metadata.annotations["volume.kubernetes.io/selected-node"] // empty
                                        ' <<<"$pvc_json" 2>/dev/null | head -n1)

                                        if [[ -z "$hostpath_details" ]]; then
                                                hostpath_details="pvc=${claim},sc=${sc},provisioner=${sc_prov:-$prov},selectedNode=${sel_node}"
                                        else
                                                hostpath_details="${hostpath_details};pvc=${claim},sc=${sc},provisioner=${sc_prov:-$prov},selectedNode=${sel_node}"
                                        fi
                                fi
                        done
                fi

                if [[ "$has_pod_anti_affinity" == "true" ]]; then
                        local anti_key=""
                        local anti_val=""
                        local anti_nodes=""
                        local anti_node_count=0
                        local launcher_node=""
                        local candidate_nodes=""

                        launcher_node=$(jq -r --arg ns "$ns" --arg vm "$vm" '
                                .items[]
                                | select(.metadata.namespace == $ns and (.metadata.labels["vm.kubevirt.io/name"] // "") == $vm)
                                | .spec.nodeName // empty
                        ' <<<"$pod_json" 2>/dev/null | head -n1)

                        anti_key=$(jq -r '
                                .spec.template.spec.affinity.podAntiAffinity.requiredDuringSchedulingIgnoredDuringExecution[0]
                                .labelSelector.matchExpressions[0].key // empty
                        ' <<<"$vm_obj" 2>/dev/null)

                        anti_val=$(jq -r '
                                .spec.template.spec.affinity.podAntiAffinity.requiredDuringSchedulingIgnoredDuringExecution[0]
                                .labelSelector.matchExpressions[0].values[0] // empty
                        ' <<<"$vm_obj" 2>/dev/null)

                        if [[ -n "$anti_key" && -n "$anti_val" ]]; then
                                anti_nodes=$(jq -r --arg k "$anti_key" --arg v "$anti_val" '
                                        .items[]
                                        | select((.metadata.labels[$k] // "") == $v)
                                        | .spec.nodeName // empty
                                ' <<<"$pod_json" 2>/dev/null | sed '/^$/d' | sort -u)
                        fi

                        candidate_nodes="$ready_worker_nodes"

                        if [[ -n "${anti_nodes:-}" ]]; then
                                candidate_nodes=$(comm -23 \
                                        <(printf "%s\n" "$candidate_nodes" | sed '/^$/d' | sort -u) \
                                        <(printf "%s\n" "$anti_nodes" | sed '/^$/d' | sort -u))
                        fi

                        if [[ -n "${launcher_node:-}" ]]; then
                                candidate_nodes=$(printf "%s\n" "$candidate_nodes" | sed '/^$/d' | grep -vx "$launcher_node" || true)
                        fi

                        anti_node_count=$(printf "%s\n" "$candidate_nodes" | sed '/^$/d' | wc -l | awk '{print $1}')

                        if [[ "$anti_node_count" -eq 0 ]]; then
                                antiaffinity_match=1
                                antiaffinity_details="NodeAvailableAfterDrain=${candidate_nodes:-none},nodeCountAfterDrain=${anti_node_count},singleNodeBound=true"
                        fi
                fi

                if [[ "$has_node_selector" == "true" || "$has_node_affinity" == "true" ]]; then
                        local placement_parts=()
                        local matching_nodes=""
                        local node_count=0
                        local toleration_details=""
                        local tolerated_nodes=""

                        [[ "$has_node_selector" == "true" ]] && placement_parts+=("nodeSelector")
                        [[ "$has_node_affinity" == "true" ]] && placement_parts+=("requiredNodeAffinity")

                        matching_nodes=$(jq -r --argjson vm "$vm_obj" '
                                def expr_match($labels; $expr):
                                        ($expr.operator // "In") as $op
                                        | ($expr.key // "") as $k
                                        | ($expr.values // []) as $vals
                                        | if $op == "In" then ($vals | index(($labels[$k] // "")) != null)
                                          elif $op == "Exists" then ($labels | has($k))
                                          elif $op == "NotIn" then ($vals | index(($labels[$k] // "")) == null)
                                          elif $op == "DoesNotExist" then (($labels | has($k)) | not)
                                          else true end;
                                def selector_match($labels; $sel):
                                        ($sel | to_entries | all((($labels[.key] // "") == (.value | tostring))));
                                def term_match($labels; $term):
                                        (($term.matchExpressions // []) | all(expr_match($labels; .)));
                                def affinity_match($labels; $terms):
                                        if ($terms | length) == 0 then true else any($terms[]; term_match($labels; .)) end;

                                .items[]
                                | select((.metadata.labels // {} | has("node-role.kubernetes.io/worker")))
                                | select((.status.conditions // []) | any(.type == "Ready" and .status == "True"))
                                | . as $n
                                | select(selector_match(($n.metadata.labels // {}); ($vm.spec.template.spec.nodeSelector // {})))
                                | select(affinity_match(($n.metadata.labels // {}); ($vm.spec.template.spec.affinity.nodeAffinity.requiredDuringSchedulingIgnoredDuringExecution.nodeSelectorTerms // [])))
                                | .metadata.name
                        ' <<<"$node_json" 2>/dev/null)

                        if [[ -n "$matching_nodes" ]]; then
                                for n in $matching_nodes; do
                                        local node_obj
                                        node_obj=$(jq -c --arg node "$n" '.items[] | select(.metadata.name == $node)' <<<"$node_json" 2>/dev/null | head -n1)
                                        if [[ -n "$node_obj" ]] && node_is_tolerated_json "$node_obj" "$vm_obj"; then
                                                tolerated_nodes+="$n "
                                        fi
                                done
                                matching_nodes=$(echo "$tolerated_nodes" | xargs)
                        fi

                        node_count=0
                        [[ -n "$matching_nodes" ]] && node_count=$(echo "$matching_nodes" | wc -w | awk '{print $1}')
                        toleration_details="tolerations=${toler_count}, toleratedMatchingNodes=${matching_nodes:-none}, toleratedNodeCount=${node_count}"

                        if [[ "$node_count" -le 1 ]]; then
                                nodeconstrained_match=1
                                nodeconstrained_details="placementTypes=$(IFS=,; echo "${placement_parts[*]}"), eligibleNodes=${matching_nodes:-none}, eligibleNodeCount=${node_count}, failoverPossible=$([[ "$node_count" -gt 1 ]] && echo yes || echo no), ${toleration_details}"
                        fi
                fi

                local -a observation_parts=()

                if [[ "$hostpath_match" -eq 1 ]]; then
                        observation_parts+=("HostPath storage (node-locked)")
                fi

                if [[ "$nodeconstrained_match" -eq 1 ]]; then
                        observation_parts+=("Insufficient schedulable nodes (0/1) after selector/affinity/toleration filtering")
                fi

                if [[ "$antiaffinity_match" -eq 1 ]]; then
                        observation_parts+=("Anti-affinity blocks all failover nodes")
                fi

                if [[ "${#observation_parts[@]}" -eq 0 ]]; then
                        continue
                fi

                local issue fix_parts_vm=()
                issue=$(IFS='; '; echo "${observation_parts[*]}")
                [[ "$hostpath_match" -eq 1 ]] && fix_parts_vm+=("migrate data off hostpath before upgrade")
                [[ "$nodeconstrained_match" -eq 1 ]] && fix_parts_vm+=("relax nodeSelector/affinity or add worker nodes")
                [[ "$antiaffinity_match" -eq 1 ]] && fix_parts_vm+=("relax podAntiAffinity before upgrade")
                local fix
                fix=$(IFS='; '; echo "${fix_parts_vm[*]}")

                printf "%s\t%s\t%s\t%s\t%s\n" \
                "$ns" "$vm" "vm" "${issue}" "${fix}" >> "$tmpfile"
        done
}



check_image_registry_infoscale_csi() {
        local tmpfile="$1"

        log_info "[${RULE_NAME}] Checking image-registry deployment PVC backing..."

        init_workload_sanity_cache || return 1

        local registry_ns registry_deploy
        registry_ns="openshift-image-registry"
        registry_deploy="image-registry"

        local pvc_list
        pvc_list="$(jq -r --arg ns "$registry_ns" --arg name "$registry_deploy" '
                .items[]
                | select(.metadata.namespace == $ns and .metadata.name == $name)
                | (.spec.template.spec.volumes // [])[]?
                | select(.persistentVolumeClaim?)
                | .persistentVolumeClaim.claimName
        ' <<<"$WORKLOAD_SANITY_DEPLOYMENT_JSON" 2>/dev/null | sort -u)"

        if [[ -z "$pvc_list" ]]; then
                log_info "[${RULE_NAME}] image-registry deployment not found or no PVC attached; assuming already scaled down or non-PVC configuration"
                return 0
        fi

        local pvc infoscale_count total_count
        local -a infoscale_pvcs=()
        local -a non_infoscale_pvcs=()
        infoscale_count=0
        total_count=0

        while IFS= read -r pvc; do
                [[ -z "$pvc" ]] && continue
                total_count=$((total_count + 1))
                if [[ -n "${WORKLOAD_SANITY_INFOSCALE_PVC["${registry_ns}/${pvc}"]:-}" ]]; then
                        infoscale_count=$((infoscale_count + 1))
                        infoscale_pvcs+=("$pvc")
                else
                        non_infoscale_pvcs+=("$pvc")
                fi
        done <<<"$pvc_list"

        if [[ "$total_count" -eq 0 ]]; then
                return 0
        fi

        if [[ "$infoscale_count" -gt 0 ]]; then
                local pvc_summary
                pvc_summary=$(IFS=','; echo "${infoscale_pvcs[*]:-none}")
                printf "%s\t%s\t%s\t%s\t%s\n" \
                        "$registry_ns" "$registry_deploy" "registry" \
                        "ERROR: image-registry PVC is backed by InfoScale CSI (pvcs=${pvc_summary})" \
                        "Scale down image-registry deployment replicas before upgrade" >>"$tmpfile"
                return 1
        fi

        local pvc_summary
        pvc_summary=$(IFS=','; echo "${non_infoscale_pvcs[*]:-none}")
        log_info "[${RULE_NAME}] image-registry PVC is not backed by InfoScale CSI (pvcs=${pvc_summary})"

        return 0
}

check_pending_pods() {
        local tmpfile="$1"
        local found=false

        log_info "[${RULE_NAME}] Checking pods for blocking states (Pending/ContainerCreating/CrashLoopBackOff)..."

        while IFS='|' read -r ns pod phase waiting_reason owner_ref_count owner_ref_kinds; do
                if is_excluded_pod_namespace "$ns"; then
                        continue
                fi
                [[ -z "${pod}" ]] && continue

                local owner_ref_type="withoutOwnerRef"
                local -a state_reasons=()
                local state_flag="normal"
                local csi_type="non-InfoScale"

                if [[ "${pod}" == virt-launcher-* ]]; then
                        continue
                fi

                if [[ "${owner_ref_count:-0}" =~ ^[0-9]+$ ]] && (( owner_ref_count > 0 )); then
                        owner_ref_type="withOwnerRef"
                fi

                if is_workload_backed_by_infoscale_csi "${ns}" "${pod}" "pod"; then
                        csi_type="InfoScale-CSI"
                        printf "%s\t%s\t%s\t%s\t%s\n" \
                                "${ns}" "${pod}" "pod" \
                                "ERROR: InfoScale CSI-backed pod detected (ownerRefType=${owner_ref_type}, ownerRefKinds=${owner_ref_kinds:-none}, phase=${phase:-Unknown}, waitingReason=${waiting_reason:-none})" \
                                "Move workload to non-InfoScale CSI storage or ensure controller-managed failover before upgrade" >>"$tmpfile"
                        found=true
                fi

                if [[ "${phase}" == "Pending" ]]; then
                        state_reasons+=("Pending")
                fi
                if [[ "${waiting_reason}" == *"ContainerCreating"* ]]; then
                        state_reasons+=("ContainerCreating")
                fi
                if [[ "${waiting_reason}" == *"CrashLoopBackOff"* ]]; then
                        state_reasons+=("CrashLoopBackOff")
                fi

                if [[ "${#state_reasons[@]}" -eq 0 ]]; then
                        continue
                fi

                state_flag=$(IFS=','; echo "${state_reasons[*]}")
                printf "%s\t%s\t%s\t%s\t%s\n" \
                        "${ns}" "${pod}" "pod" \
                        "ERROR: Pod detected in blocking state (state=${state_flag}, ownerRefType=${owner_ref_type}, ownerRefKinds=${owner_ref_kinds:-none}, phase=${phase:-Unknown}, waitingReason=${waiting_reason:-none}, csiType=${csi_type})" \
                        "Investigate pod events, scheduling, image pull, storage, and startup dependencies before upgrade" >>"$tmpfile"
                found=true
        done < <(
                get_live_pods_json | jq -r '
                .items[] |
                {
                  ns: .metadata.namespace,
                  pod: .metadata.name,
                  phase: (.status.phase // "Unknown"),
                  waitingReasons: [
                    (.status.initContainerStatuses // [])[],
                    (.status.containerStatuses // [])[]
                  ]
                  | map(.state.waiting.reason? // empty)
                  | unique,
                  ownerRefCount: ((.metadata.ownerReferences // []) | length),
                  ownerRefKinds: [(.metadata.ownerReferences // [])[] | .kind? // empty] | unique
                } |
                [
                  .ns,
                  .pod,
                  .phase,
                  ((.waitingReasons | join(",")) // "none"),
                  (.ownerRefCount | tostring),
                  ((.ownerRefKinds | join(",")) // "")
                ] | join("|")
                '
        )

        if [[ "${found}" == "true" ]]; then
                log_error "[${RULE_NAME}] Found blocking pods (Pending/ContainerCreating/CrashLoopBackOff) or InfoScale CSI-backed pods (see table)."
                return 1
        fi

        return 0
}

check_vmi_failed_phase() {
        local tmpfile="$1"
        local found=false

        log_info "[${RULE_NAME}] Checking for Failed Virtual Machine Instances..."

        while IFS=$'\t' read -r ns name phase vmi; do
                if is_excluded_namespace "$ns"; then
                        continue
                fi
                [[ -z "${name}" ]] && continue

                if [[ "${phase}" == "Failed" ]]; then
                        printf "%s\t%s\t%s\t%s\t%s\n" \
                                "${ns}" "${name}" "vmi" \
                                "ERROR: VMI in Failed phase (linked to VM: ${vmi:-unknown})" \
                                "Investigate and resolve VMI failure; delete and recreate if necessary" >>"$tmpfile"
                        found=true
                fi
        done < <(
                get_manifest_json vmi namespaced 2>/dev/null | jq -r '
                .items[] |
                [
                  .metadata.namespace,
                  .metadata.name,
                  (.status.phase // "Unknown"),
                  ((.metadata.ownerReferences // [] | map(select(.kind == "VirtualMachine") | .name) | .[0]) // .metadata.labels["kubevirt.io/vm"] // .metadata.labels["vm.kubevirt.io/name"] // .metadata.annotations["kubevirt.io/vm"] // .metadata.annotations["vm.kubevirt.io/name"] // .metadata.name)
                ] | @tsv
                '
        )

        if [[ "${found}" == "true" ]]; then
                log_error "[${RULE_NAME}] Found Failed VMI(s) preventing safe upgrade (see table)."
                return 1
        fi

        return 0
}
run() {
        echo "-----------------------------------------------------------------------------------------------------"
        echo "[${RULE_NAME}]"
        echo "-----------------------------------------------------------------------------------------------------"

        local TMPFILE
        local FAIL=false

        ensure_context || return 1
        collect_preflight_manifests || return 1

        TMPFILE=$(mktemp)
        log_info "[${RULE_NAME}] Collecting workload distribution info..."
        printf "NAMESPACE\tWORKLOAD\tTYPE\tISSUE\tREMEDIATION\n" >"$TMPFILE"
        check_pvc_status "$TMPFILE" || FAIL=true
        check_csi_priority_conflicts "$TMPFILE" || FAIL=true
        check_image_registry_infoscale_csi "$TMPFILE" || FAIL=true
        check_pending_pods "$TMPFILE" || FAIL=true
        check_vmi_failed_phase "$TMPFILE" || FAIL=true
        check_infoscale_vms_cached "$TMPFILE" || FAIL=true
        check_virtual_machines "$TMPFILE" || FAIL=true
        check_native_workloads "$TMPFILE" || FAIL=true

        awk 'NR==1 || $1 !~ /^openshift-/ || $3 == "vm" || $3 == "registry"' "$TMPFILE" >"${TMPFILE}.filtered" && mv "${TMPFILE}.filtered" "$TMPFILE"

        if [ "$(wc -l <"$TMPFILE")" -gt 1 ]; then
                print_workload_constraints_warning "${RULE_NAME}"
                column -t -s $'\t' "$TMPFILE"
                FAIL=true
        fi
        rm -f "$TMPFILE"
        if [[ "$FAIL" == true ]]; then
                log_error "[${RULE_NAME}] Fix the above issues and re-run preflight before upgrading."
                return 1
        fi
        log_info "[${RULE_NAME}] All workloads have multi-node availability"

        return 0


}
