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

RULE_NAME="IKE & OCP Upgrade Compatibility"
INFOSCALE_CLUSTER_RESOURCE="infoscalecluster"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
source "${ROOT_DIR}/lib/cr_utils.sh"


CR_LIST=""
KUBE_CLI=""
CURRENT_OCP_VERSION=""

#Config
config() {
        log_info "[${RULE_NAME}] Configuration successful"

        if [[ -z "${IKE_VERSION:-}" ]]; then
            log_error "[${RULE_NAME}] IKE_VERSION not set"
            return 1
        fi
        if [[ -z "${TARGET_OCP:-}" ]]; then
            log_info "[${RULE_NAME}] Target OCP version not provided. Using current cluster OCP version for compatibility checks."
        fi
        return 0
}

#Exec phase helpers
ensure_context(){
        detect_kube_cli || return 1

        CR_LIST="$(get_cr_list "${INFOSCALE_CLUSTER_RESOURCE}")"
        if [[ -z "$CR_LIST" ]]; then
            log_error "[${RULE_NAME}] No ${INFOSCALE_CLUSTER_RESOURCE} found"
            return 1
        fi

        CURRENT_OCP_VERSION="$(get_ocp_version)"
        if [[ -z "$CURRENT_OCP_VERSION" ]]; then
            log_error "[${RULE_NAME}] Unable to detect current OCP version"
            return 1
        fi
    
	return 0
}

is_version_greater_or_equal() {
    local version_a="$1"
    local version_b="$2"

    [[ -z "${version_a}" || -z "${version_b}" ]] && return 1
    [[ "${version_a}" == "${version_b}" ]] && return 0
    [[ "$(printf '%s\n%s\n' "${version_a}" "${version_b}" | sort -V | tail -n1)" == "${version_a}" ]]
}

check_upgrade_compatibility() {
    local rule="${RULE_NAME:-UPGRADE_CHECK}"
    local fail=false
    local effective_ocp
    current_version="$(get_current_ike_version)"

    effective_ocp="${TARGET_OCP:-$CURRENT_OCP_VERSION}"

    log_info "[${rule}] Validating OCP and IKE upgrade compatibility"
    
    if ! is_ocp_supported_on_ike "$effective_ocp" "$IKE_VERSION"; then
        log_error "[${rule}] IKE $IKE_VERSION is NOT supported on OCP $effective_ocp"
        fail=true
    else
        log_info "[${rule}] IKE $IKE_VERSION is supported on OCP $effective_ocp"
    fi
    if [[ -n "${current_version:-}" ]]; then
        if is_version_greater_or_equal "$current_version" "$IKE_VERSION"; then
                if [[ "$current_version" == "$IKE_VERSION" ]]; then
                        log_warn "[${rule}] Current IKE version ($current_version) is the same as target version ($IKE_VERSION). No IKE upgrade required."
                else
                        log_warn "[${rule}] Current IKE version ($current_version) is higher than target ($IKE_VERSION). Skipping IKE upgrade-path validation."
                fi
        else
            if ! is_valid_ike_upgrade_path "$current_version" "$IKE_VERSION"; then
                log_error "[${rule}] Invalid IKE upgrade path: $current_version -> $IKE_VERSION"
                fail=true
            else
                log_info "[${rule}] Valid IKE upgrade path: $current_version -> $IKE_VERSION"
            fi
        fi
    fi
    [[ "$fail" == true ]] && return 1
    return 0
}


# Exec phase
run() {
        local FAIL=false
        echo "-----------------------------------------------------------------------------------------------------"
        echo "[${RULE_NAME}]"
        echo "-----------------------------------------------------------------------------------------------------"

        ensure_context || return 1
        log_info "[${RULE_NAME}] Running upgrade compatibility checks"

        check_upgrade_compatibility || FAIL=true

        if [[ "$FAIL" == true ]]; then
            log_error "[${RULE_NAME}] One or more upgrade checks failed"
            return 1
        fi

        log_info "[${RULE_NAME}] All upgrade compatibility checks passed"
        return 0
}

