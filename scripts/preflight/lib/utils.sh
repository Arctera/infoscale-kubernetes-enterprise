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

declare -A RESULTS
log_info() { echo -e "\033[1;34m[INFO]\033[0m  $*"; }
log_warn() { echo -e "\033[1;33m[WARN]\033[0m  $*"; }
log_error() { echo -e "\033[1;31m[ERROR]\033[0m $*" >&2; }
log_internal() {
        local ts
        ts="$(date '+%Y-%m-%d %H:%M:%S')"
        if [[ -n "${INTERNAL_LOG_FILE:-}" ]]; then
                echo "[INTERNAL] ${ts} $*" >> "${INTERNAL_LOG_FILE}"
        elif [[ -n "${LOG_FILE:-}" ]]; then
                echo "[INTERNAL] ${ts} $*" >> "${LOG_FILE}"
        fi
}

record_result() {
        local RULE="$1" STATUS="$2" MSG="$3"
        RESULTS["$RULE"]="$STATUS:$MSG"
}

print_summary() {
        echo -e "\n========== PRE-FLIGHT SUMMARY =========="
        for RULE in "${!RESULTS[@]}"; do
                IFS=':' read -r STATUS MSG <<<"${RESULTS[$RULE]}"
                case "$STATUS" in
                PASS) echo -e "$RULE : $MSG" ;;
                WARN) echo -e "$RULE : $MSG" ;;
                FAIL) echo -e "$RULE : $MSG" ;;
                esac
        done
        echo "========================================"
}

# Supported OCP versions
get_supported_ocp_versions() {
        echo "4.16 4.17 4.18 4.19 4.20"
}

# Dependency Checks
check_dependency() {
        local BIN="$1"
        if ! command -v "$BIN" &>/dev/null; then
                log_error "Required dependency '$BIN' not found in PATH."
                log_info "Please install it using your package manager. Examples:"
                log_info "  - RHEL/CentOS: sudo yum install -y $BIN"
                exit 1
        fi
}

check_all_dependencies() {
        log_info "Verifying required CLI dependencies..."
        local DEPS=(jq)
        for DEP in "${DEPS[@]}"; do
                check_dependency "$DEP"
        done
        log_info "All dependencies verified successfully."
}

# Allowed container registries
get_allowed_registries() {
        cat <<EOF
gcr.io
ghcr.io
quay.io
registry.access.redhat.com
registry.connect.redhat.com
registry.redhat.io
registry.k8s.io
EOF
}
