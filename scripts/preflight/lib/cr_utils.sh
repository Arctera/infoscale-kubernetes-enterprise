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

UTILS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DATA_DIR="${UTILS_DIR}/data"
INFOSCALE_CLUSTER_RESOURCE="infoscalecluster"


UPGRADE_MATRIX="${DATA_DIR}/upgrade_paths.json"
DOC_REFERECE="${DATA_DIR}/document_links.json"

OCP_UPGRADE_MATRIX=""
IKE_UPGRADE_MATRIX=""

# Detect Kubernetes CLI (oc/kubectl)
detect_kube_cli() {
        if [[ -n "${KUBE_CLI:-}" ]]; then
            return 0   # already detected
        fi
        if command -v oc >/dev/null 2>&1; then
            KUBE_CLI="oc"
        elif command -v kubectl >/dev/null 2>&1; then
            KUBE_CLI="kubectl"
        else
            log_error "[${RULE_NAME}] Neither oc nor kubectl found in PATH"
            return 1
        fi
}

# Get current OpenShift version
get_ocp_version() {
        local version
        version="$(${KUBE_CLI:-oc} get clusterversion version -o=jsonpath='{.status.desired.version}' 2>/dev/null || true)"
        if [[ -z "$version" ]]; then
            return 1
        fi
        echo "$version"
        return 0
}

#Get current ike version
get_current_ike_version() {
    local ns name ver

    while read -r ns name; do
        [[ -z "$ns" || -z "$name" ]] && continue

        ver="$(get_cr_field \
            "$INFOSCALE_CLUSTER_RESOURCE" \
            "$ns" \
            "$name" \
            '{.status.version}')"

        [[ -n "$ver" ]] && {
            echo "$ver"
            return 0
        }
    done < <($KUBE_CLI get "$INFOSCALE_CLUSTER_RESOURCE" -A \
                -o jsonpath='{range .items[*]}{.metadata.namespace}{" "}{.metadata.name}{"\n"}{end}')

    return 1
}

#Check if target IKE us supported on target OCP version
is_ocp_supported_on_ike() {
        local ocp="$1"   
        local ike="$2"   

        [[ ! -f "$UPGRADE_MATRIX" ]] && return 1

        local majmin="${ocp%.*}"   
        local max exc

        max="$(jq -r --arg ike "$ike" --arg mm "$majmin" '
            .ike_ocp_compatibility[]
            | select(.ike == $ike)
            | .ocp[$mm].max // empty
        ' "$UPGRADE_MATRIX")"

        [[ -z "$max" ]] && return 1

        if [[ "$(printf '%s\n%s\n' "$ocp" "$max" | sort -V | tail -n1)" != "$max" ]]; then
            return 1
        fi

        if jq -e --arg ike "$ike" --arg mm "$majmin" --arg ocp "$ocp" '
            .ike_ocp_compatibility[]
            | select(.ike == $ike)
            | .ocp[$mm].exceptions[]
            | select(. == $ocp)
        ' "$UPGRADE_MATRIX" >/dev/null 2>&1; then
            return 1
        fi
        return 0
}

# Version check
ver_ge() {
  local a="$1" b="$2"
  [[ "$(printf '%s\n%s\n' "$b" "$a" | sort -V | head -n1)" == "$b" ]]
}

#Check if IKE upgrade path is supported
is_valid_ike_upgrade_path() {
        local from="$1"
        local to="$2"
        local prefix=""

        [[ -n "${RULE_NAME:-}" ]] && prefix="[${RULE_NAME}] "

        [[ ! -f "$UPGRADE_MATRIX" ]] && {
            log_error "${prefix}Upgrade matrix not found: $UPGRADE_MATRIX"
            return 1
        }

        local entry
        entry="$(jq -c --arg f "$from" --arg t "$to" '
            .ike_upgrade_paths[]
            | select(.from == $f)
            | .to[]
            | select(.version == $t)
        ' "$UPGRADE_MATRIX")"

        if [[ -z "$entry" ]]; then
            log_error "${prefix}Invalid IKE upgrade path: ${from} -> ${to}"
            return 1
        fi

        local supported workaround title notes
        supported="$(jq -r '.supported // true' <<<"$entry")"
        workaround="$(jq -c '.workaround // empty' <<<"$entry")"

        if [[ "$supported" != "true" ]]; then
            local reason
            reason="$(jq -r '.reason // empty' <<<"$entry")"
            log_error "${prefix}IKE upgrade path ${from} -> ${to} is not supported."
            [[ -n "$reason" ]] && log_error "${prefix}$reason"
            return 1
        fi

        if [[ -n "$workaround" && "$workaround" != "null" ]]; then
            title="$(jq -r '.title // ""' <<<"$workaround")"
            notes="$(jq -r '.notes // ""' <<<"$workaround")"
            log_warn "${prefix} ${from}->${to}: Additional actions are required before this upgrade can proceed "
            [[ -n "$notes" ]] && {
                while IFS= read -r line; do
                    echo "$line"
                done <<< "$notes"
        }
        else
            log_info "${prefix}IKE upgrade path ${from} -> ${to} is supported."
        fi

        return 0
}

# Case-sensitive grep helper
grep_e() {
        local pattern="$1"
        local text="${2:-}"   
        grep -qiE "$pattern" <<<"$text"
}

# Awk helper
awk_field() { awk "{print \$${1}}" <<<"$2"; }

#  kubectl/oc wrapper
kube_get_safe() {
        if [[ -z "${KUBE_CLI:-}" ]]; then
            echo "KUBE: $KUBE_CLI"
            log_error "KUBE_CLI is not set"
            return 1
        fi
        "$KUBE_CLI" "$@" 2>/dev/null || true
}

# Get InfoScale CR  namespace and name
get_cr_list() {
        local resource="$1"
        kube_get_safe get "$resource" -A \
        -o jsonpath='{range .items[*]}{.metadata.namespace}{" "}{.metadata.name}{"\n"}{end}'
}

# Get a  InfoScale CR field
get_cr_field() {
        local resource="$1"
        local ns="$2"
        local name="$3"
        local jsonpath="$4"

        kube_get_safe get "$resource" -n "$ns" "$name" -o "jsonpath=${jsonpath}"
}
# Get SDS pods
get_sds_pods() {
        kube_get_safe get pods -A --no-headers -owide \
            | grep -i infoscale-sds \
            | grep -iv operator || true
}
 
# Exec into SDS pod
kube_exec_safe() {
        local ns="$1"
        local pod="$2"
        shift 2
        kube_get_safe exec -n "$ns" "$pod" -- "$@"
}


# Check if virtulization is enabled
kubevirt_vm_supported() {
    $KUBE_CLI get hyperconverged -A -o name 2>/dev/null | grep -q .
}

# Build a map of PVC and CSI provisioner
build_pvc_provisioner_map() {
        declare -gA pvc_prov=()
        local ns pvc sc prov

        while IFS="|" read -r ns pvc sc; do
            [[ -z "$ns" || -z "$pvc" || -z "$sc" ]] && continue
            prov="$($KUBE_CLI get sc "$sc" -o jsonpath='{.provisioner}' 2>/dev/null || true)"
            [[ -n "$prov" ]] && pvc_prov["$ns/$pvc"]="$prov"
        done < <(
            $KUBE_CLI get pvc -A \
            -o jsonpath='{range .items[*]}{.metadata.namespace}|{.metadata.name}|{.spec.storageClassName}{"\n"}{end}'
        )
}

# Helper function for comparing CSI node and application priority
check_object_priority_against_csi()
{
        local kind="$1" ns="$2" name="$3" pc="$4" csi_prio="$5" tmpfile="$6" prefix="$7"
        shift 7
        local prefixes=("$@")
        local uses_infoscale=false

        for key in "${!pvc_prov[@]}"; do
            [[ "$key" == "$ns/"* ]] || continue
            for p in "${prefixes[@]}"; do
                [[ "$key" == "$ns/$p"* ]] || continue
                if [[ "${pvc_prov[$key]}" == "org.veritas.infoscale" ]]; then
                    uses_infoscale=true
                    break 2
                fi
            done
        done
        [[ "$uses_infoscale" != true ]] && return 0

        local app_prio
        if [[ -z "$pc" || "$pc" == "default" ]]; then
            app_prio=0
        else
            app_prio="$($KUBE_CLI get priorityclass "$pc" -o jsonpath='{.value}' 2>/dev/null || echo 0)"
        fi

        if (( app_prio > csi_prio )); then
            printf "%-12s %-15s %-30s %-25s %s\n" \
                "$kind" "$ns" "$name" "$pc" "$app_prio" >>"$tmpfile"
            return 1
        fi
        return 0
}

# Check workloads with higher priority
check_csi_priority_conflicts() {
        local report_table="${1:-}"
        local prefix=""
        [[ -n "${RULE_NAME:-}" ]] && prefix="[${RULE_NAME}] "

        log_info "${prefix}Checking workloads using InfoScale CSI with priority higher than CSI node"

        local tmpfile
        tmpfile="$(mktemp)"
        echo "KIND NAMESPACE NAME PRIORITYCLASS VALUE" >"$tmpfile"

        local csi_pc csi_prio
        csi_pc="$(get_manifest_json daemonset namespaced |
            jq -r '.items[]
                | select(.metadata.name | test("infoscale-csi-node"; "i"))
                | .spec.template.spec.priorityClassName // empty' | head -n1)"

        csi_prio=0
        [[ -n "$csi_pc" ]] && csi_prio="$($KUBE_CLI get priorityclass "$csi_pc" -o jsonpath='{.value}' 2>/dev/null || echo 0)"

        build_pvc_provisioner_map
        #Deployments and daemonsets
        for kind in daemonset deployment; do
            get_manifest_json "$kind" namespaced |
            jq -r '
                .items[] | {
                    ns: .metadata.namespace,
                    name: .metadata.name,
                    pc: (.spec.template.spec.priorityClassName // "default"),
                    vols: [.spec.template.spec.volumes[]?
                            | select(.persistentVolumeClaim?)
                            | .persistentVolumeClaim.claimName]
                } | @base64' |
            while read -r obj; do
                _jq() { echo "$obj" | base64 --decode | jq -r "$1"; }

                local ns name pc
                ns="$(_jq '.ns')"
                name="$(_jq '.name')"
                pc="$(_jq '.pc')"

                mapfile -t prefixes < <(_jq '.vols[]?')

                check_object_priority_against_csi \
                    "$kind" "$ns" "$name" "$pc" "$csi_prio" "$tmpfile" "$prefix" \
                    "${prefixes[@]}"
            done
        done
        #Statefulsets
        get_manifest_json statefulset namespaced |
        jq -r '
            .items[] | {
                ns: .metadata.namespace,
                name: .metadata.name,
                pc: (.spec.template.spec.priorityClassName // "default"),
                vcts: [.spec.volumeClaimTemplates[]?.metadata.name]
            } | @base64' |
        while read -r obj; do
            _jq() { echo "$obj" | base64 --decode | jq -r "$1"; }

            local ns name pc
            ns="$(_jq '.ns')"
            name="$(_jq '.name')"
            pc="$(_jq '.pc')"

            mapfile -t prefixes < <(_jq '.vcts[]?' | sed "s/$/-$name-/")

            check_object_priority_against_csi \
                "statefulset" "$ns" "$name" "$pc" "$csi_prio" "$tmpfile" "$prefix" \
                "${prefixes[@]}"
        done
        #Virtual Machines
        if kubevirt_vm_supported; then
            get_manifest_json vm namespaced |
            jq -c '
            .items[] | {
                ns: .metadata.namespace,
                vm: .metadata.name,
                dvs: [
                .spec.dataVolumeTemplates[]? |
                {
                    tpl: .metadata.name,
                    pc: (.spec.priorityClassName // "default")
                }
                ]
            }' |
            while read -r line; do
                ns=$(jq -r '.ns' <<<"$line")
                vm=$(jq -r '.vm' <<<"$line")

                jq -c '.dvs[]?' <<<"$line" | while read -r dv; do
                    tpl=$(jq -r '.tpl' <<<"$dv")
                    pc=$(jq -r '.pc'  <<<"$dv")

                    [[ "$pc" == "default" ]] && continue

                    dv_prio="$($KUBE_CLI get priorityclass "$pc" -o jsonpath='{.value}' 2>/dev/null || echo 0)"

                    if (( dv_prio > csi_prio )); then
                        printf "%-12s %-20s %-30s %-25s %s\n" \
                            "VM" "$ns" "$vm" "$pc" "$dv_prio" >>"$tmpfile"
                    fi
                done
            done
        fi

        if [[ "$(wc -l <"$tmpfile")" -gt 1 ]]; then

            if [[ -n "${report_table}" ]]; then
                while read -r kind ns name pc val; do
                    printf "%s\t%s\t%s\t%s\t%s\n" \
                        "${ns}" "${name}" "${kind}" \
                        "ERROR: PriorityClass '${pc}' value ${val} is higher than Infoscale CSI priority (${csi_prio})" \
                        "Lower PriorityClass below CSI priority before upgrade" >>"${report_table}"
                done < <(tail -n +2 "$tmpfile")
            fi

            rm -f "$tmpfile"
            return 1
        fi

        rm -f "$tmpfile"
        log_info "${prefix}No workloads were found that can block InfoScale CSI node eviction."
        return 0
}

manifest_snapshot_dir() {
        local base="${RUN_LOG_DIR:-${PWD}}"
        echo "${base}/manifests"
}

manifest_snapshot_file_base() {
        local resource="$1"
        echo "$resource" | sed 's#[/.]#_#g'
}

collect_manifest_snapshot() {
        local resource="$1"
        local scope="${2:-namespaced}"
        local dir base json_file yaml_file txt_file
        local -a cmd

        dir="$(manifest_snapshot_dir)"
        mkdir -p "$dir"

        base="$(manifest_snapshot_file_base "$resource")"
        json_file="${dir}/${base}.json"
        yaml_file="${dir}/${base}.yaml"
        txt_file="${dir}/${base}.txt"

        cmd=("$KUBE_CLI" get "$resource")
        if [[ "$scope" == "namespaced" ]]; then
                cmd+=("-A")
        fi

        if ! "${cmd[@]}" -o json >"$json_file" 2>/dev/null; then
                printf '{"apiVersion":"v1","kind":"List","items":[]}\n' >"$json_file"
        fi

        if ! "${cmd[@]}" -o yaml >"$yaml_file" 2>/dev/null; then
                printf '%s\n' \
                        'apiVersion: v1' \
                        'kind: List' \
                        'items: []' >"$yaml_file"
        fi

        if ! "${cmd[@]}" >"$txt_file" 2>/dev/null; then
                printf 'No resources found for %s\n' "$resource" >"$txt_file"
        fi
}
get_manifest_snapshot_json() {
        local resource="$1"
        local scope="${2:-namespaced}"
        local dir base json_file

        dir="$(manifest_snapshot_dir)"
        base="$(manifest_snapshot_file_base "$resource")"
        json_file="${dir}/${base}.json"

        if [[ ! -s "$json_file" ]]; then
                collect_manifest_snapshot "$resource" "$scope"
        fi

        echo "$json_file"
}

get_manifest_json() {
        local resource="$1"
        local scope="${2:-namespaced}"
        local json_file

        json_file="$(get_manifest_snapshot_json "$resource" "$scope")"
        cat "$json_file"
}

collect_preflight_manifests() {
        local prefix=""
        [[ -n "${RULE_NAME:-}" ]] && prefix="[${RULE_NAME}] "

        log_info "${prefix}Collecting manifest snapshots and get output under $(manifest_snapshot_dir)"

        collect_manifest_snapshot pods namespaced
        collect_manifest_snapshot pvc namespaced
        collect_manifest_snapshot daemonset namespaced
        collect_manifest_snapshot deployment namespaced
        collect_manifest_snapshot statefulset namespaced
        collect_manifest_snapshot vm namespaced
        collect_manifest_snapshot vmi namespaced
        collect_manifest_snapshot dv namespaced
        collect_manifest_snapshot volumesnapshots namespaced
        collect_manifest_snapshot storageclass cluster
        collect_manifest_snapshot priorityclass cluster
        collect_manifest_snapshot pv cluster
        collect_manifest_snapshot nodes cluster
}
