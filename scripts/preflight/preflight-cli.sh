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

BASE_DIR="$(cd "$(dirname "$0")" && pwd)"
RULE_DIR="${BASE_DIR}/preflight-rules"
LIB_DIR="${BASE_DIR}/lib"
LOG_DIR="${BASE_DIR}/logs"

# Timestamped log path
RUN_ID="preflight-$(date +%Y%m%d-%H%M%S)"
RUN_LOG_DIR="${LOG_DIR}/${RUN_ID}"
mkdir -p "${RUN_LOG_DIR}"
LOG_FILE="${RUN_LOG_DIR}/preflight.log"
VXREST_LOGS_FILE="${RUN_LOG_DIR}/consolidated_vxrest_logs.log"
RESULTS_FILE="${RUN_LOG_DIR}/check-results.tsv"
RESULTS_JSON_FILE="${RUN_LOG_DIR}/check-results.json"
WRITE_RESULTS_TSV="${WRITE_RESULTS_TSV:-false}"
WRITE_RESULTS_JSON="${WRITE_RESULTS_JSON:-false}"
RUN_LOG_ARCHIVE=""
INTERNAL_LOG_FILE="${RUN_LOG_DIR}/preflight-internal.log"

# ---------------------------------------------
# Start logging (mirror stdout/stderr to file)
# ---------------------------------------------
exec > >(tee -a "${LOG_FILE}") 2>&1

source "${LIB_DIR}/utils.sh"
source "${LIB_DIR}/cr_utils.sh"

check_all_dependencies

# ---------------------------------------------
DATA_DIR="${BASE_DIR}/lib/data"
UPGRADE_MATRIX="${DATA_DIR}/upgrade_paths.json"
DOC_REFERENCE="${DATA_DIR}/document_links.json"
DEFAULT_UPGRADE_MATRIX_GITHUB_URL="https://raw.githubusercontent.com/Arctera/infoscale-kubernetes-enterprise/main/data/upgrade_paths.json"

resolve_upgrade_matrix_url() {
        local configured_url="${UPGRADE_MATRIX_GITHUB_URL:-}"

        if [[ -z "${configured_url}" && -f "${DOC_REFERENCE}" ]]; then
                configured_url="$(jq -r '.Upgrade_matrix.url // empty' "${DOC_REFERENCE}" 2>/dev/null || true)"
        fi

        if [[ -z "${configured_url}" ]]; then
                configured_url="${DEFAULT_UPGRADE_MATRIX_GITHUB_URL}"
        fi

        if [[ "${configured_url}" == https://github.com/*/blob/* ]]; then
                configured_url="$(echo "${configured_url}" | sed -E 's#https://github.com/([^/]+/[^/]+)/blob/(.+)#https://raw.githubusercontent.com/\1/\2#')"
        fi

        echo "${configured_url}"
}

refresh_upgrade_matrix_from_github() {
        local tmp_matrix fetch_ok="false"
        local matrix_url

        matrix_url="$(resolve_upgrade_matrix_url)"

        if [[ -z "${matrix_url}" ]]; then
                log_warn "upgrade_paths.json refresh skipped (matrix URL not set); using local file."
                return 0
        fi

        tmp_matrix="$(mktemp)"
        if command -v curl >/dev/null 2>&1; then
                if curl -fsSL --connect-timeout 5 --max-time 20 "${matrix_url}" -o "${tmp_matrix}"; then
                        fetch_ok="true"
                fi
        elif command -v wget >/dev/null 2>&1; then
                if wget -q -T 20 -O "${tmp_matrix}" "${matrix_url}"; then
                        fetch_ok="true"
                fi
        else
                log_warn "Neither curl nor wget is available; using local upgrade_paths.json."
                rm -f "${tmp_matrix}"
                return 0
        fi

        if [[ "${fetch_ok}" != "true" ]]; then
                log_warn "Failed to download upgrade_paths.json from ${matrix_url}; using existing local file."
                rm -f "${tmp_matrix}"
                return 0
        fi

        if ! jq -e '.ike_ocp_compatibility and .ike_upgrade_paths' "${tmp_matrix}" >/dev/null 2>&1; then
                log_warn "Downloaded upgrade_paths.json failed schema check; using existing local file."
                rm -f "${tmp_matrix}"
                return 0
        fi

        if mv -f "${tmp_matrix}" "${UPGRADE_MATRIX}" 2>/dev/null; then
                log_info "Refreshed upgrade_paths.json from ${matrix_url}."
        else
                log_warn "Could not overwrite ${UPGRADE_MATRIX} (read-only filesystem or permission denied); using existing local matrix."
                rm -f "${tmp_matrix}"
        fi
}

get_available_ike_versions() {
        if [[ ! -f "${UPGRADE_MATRIX}" ]]; then
                echo "Error: Cannot find upgrade_paths.json" >&2
                return 1
        fi
        jq -r '.ike_ocp_compatibility[].ike' "${UPGRADE_MATRIX}" | sort -V
}

get_compatible_upgrade_targets() {
        local current_ver="$1"
        if [[ ! -f "${UPGRADE_MATRIX}" ]]; then
                echo "Error: Cannot find upgrade_paths.json" >&2
                return 1
        fi
        jq -r --arg from "$current_ver" '
                .ike_upgrade_paths[]
                | select(.from == $from)
                | .to[]
                | select(.supported == true)
                | .version
        ' "${UPGRADE_MATRIX}" | sort -V
}

is_version_greater() {
        local version_a="$1"
        local version_b="$2"

        [[ "${version_a}" == "${version_b}" ]] && return 1
        [[ "$(printf '%s\n%s\n' "${version_a}" "${version_b}" | sort -V | tail -n1)" == "${version_a}" ]]
}

get_newer_ike_versions() {
        local current_ver="$1"
        local version

        while IFS= read -r version; do
                [[ -z "${version}" ]] && continue
                if is_version_greater "${version}" "${current_ver}"; then
                        echo "${version}"
                fi
        done < <(get_available_ike_versions)
}

select_upgrade_target_ike() {
        local current_ver=""
        if command -v oc &>/dev/null || command -v kubectl &>/dev/null; then
                detect_kube_cli 2>/dev/null || true
                current_ver="$(get_current_ike_version 2>/dev/null || true)"
        fi

        if [[ -n "$current_ver" ]]; then
                local higher_count
                higher_count="$(get_newer_ike_versions "$current_ver" | wc -l)"
                if [[ "$higher_count" -eq 0 ]]; then
                        echo "" >&2
                        echo "IKE version ${current_ver} is already at the highest available version." >&2
                        echo "No upgrade targets available. Using current version for compatibility checks." >&2
                        echo "${current_ver}"
                        return 0
                fi
        fi

        local version=""
        while [[ -z "$version" ]]; do
                printf "Enter target IKE version: " >&2
                read -r version </dev/tty
                [[ -z "$version" ]] && echo "No version entered. Please try again." >&2
        done
        echo "$version"
}

select_ike_version() {
        local version=""
        while [[ -z "$version" ]]; do
                printf "Enter target IKE version: " >&2
                read -r version </dev/tty
                [[ -z "$version" ]] && echo "No version entered. Please try again." >&2
        done
        echo "$version"
}
prompt_for_valid_ike_version() {
        local version="$1"

        while ! get_available_ike_versions | grep -Fxq -- "${version}"; do
                log_error "Invalid IKE version: ${version}. Available versions:"
                get_available_ike_versions | sed 's/^/  /' >&2

                if [[ -t 0 ]]; then
                        if [[ "${INSTALL_TYPE}" == "fresh-install" ]]; then
                                version="$(select_ike_version)"
                        else
                                version="$(select_upgrade_target_ike)"
                        fi
                        continue
                fi

                return 1
        done

        echo "${version}"
        return 0
}


select_target_ocp_version_optional() {
        echo "" >&2
        echo "Target OCP version is optional for upgrade mode." >&2
        echo "Press Enter to skip OCP upgrade version check." >&2
        printf "Or type target OCP version (example: 4.17.26): " >&2

        local version=""
        read -r version </dev/tty
        echo "${version}"
}

select_install_type() {
        echo "" >&2
        PS3="Select installation type (enter number): "
        select choice in "Upgrade" "Fresh Install"; do
                case $choice in
                "Upgrade")
                        echo "upgrade"
                        return 0
                        ;;
                "Fresh Install")
                        echo "fresh-install"
                        return 0
                        ;;
                *)
                        echo "Invalid selection. Please try again." >&2
                        ;;
                esac
        done
}

get_applicable_rule_names() {
        local rule_script rule_name

        for rule_script in "${RULE_DIR}"/*.sh; do
                rule_name="$(basename "$rule_script")"
                if [[ "${INSTALL_TYPE}" == "fresh-install" && "$rule_name" != "01-platform.sh" ]]; then
                        continue
                fi
                echo "$rule_name"
        done
}

prompt_for_rules_optional() {
        local rules=()
        local rule selection=""
        local index=1

        mapfile -t rules < <(get_applicable_rule_names)
        [[ "${#rules[@]}" -eq 0 ]] && return 0

        echo "" >&2
        echo "Rule selection is optional." >&2
        echo "Press Enter to run all applicable rules." >&2
        echo "Or enter comma-separated rule names from the list below:" >&2
        for rule in "${rules[@]}"; do
                printf '  %d. %s\n' "$index" "${rule%.sh}" >&2
                index=$((index + 1))
        done
        printf 'Rules to run: ' >&2
        read -r selection </dev/tty
        echo "$selection"
}

prompt_for_install_type_and_ike() {
        local install_type
        install_type=$(select_install_type)

        if [[ "$install_type" == "fresh-install" ]]; then
                INSTALL_TYPE="fresh-install"
                IKE_VERSION=$(select_ike_version)
        else
                INSTALL_TYPE="upgrade"
                IKE_VERSION=$(select_upgrade_target_ike)
                TARGET_OCP=$(select_target_ocp_version_optional)
                OCP_PROMPT_DONE="true"
        fi
}

# Argument parsing
TARGET_OCP=""
IKE_VERSION=""
INSTALL_TYPE="upgrade"
OCP_PROMPT_DONE="false"
ORIG_ARG_COUNT="$#"
SELECTED_RULES_RAW=""
RUN_ALL_RULES="false"
TYPE_PROVIDED="false"
declare -A SELECTED_RULES_MAP=()

usage() {
        local exit_code="${1:-1}"

        printf 'Usage: %s [OPTIONS]\n\n' "$0" >&2

        cat >&2 <<'USAGE'
OPTIONS:
  --type <type>            Type of operation: 'upgrade' or 'fresh-install' (default: upgrade)
                           If omitted, interactive prompt will be shown
  --target-ike <version>   Target IKE version (required for both upgrade and fresh-install; prompts if omitted)
  --target-ocp <version>   Target OCP version (optional, only for upgrade mode)
  --rule, --rules <list>   Run only selected rule(s), comma-separated
                           Accepts rule name(s) (with or without .sh) and/or rule number(s)
                           If omitted and stdin is interactive, prompt will be shown
  --all                    Run all applicable rules (skips interactive rule prompt)
  -h, --help               Show this help message

USAGE

        echo "Available rules for --type ${INSTALL_TYPE}:" >&2
        local idx=1 rule
        while IFS= read -r rule; do
                printf '  %d. %s\n' "$idx" "${rule%.sh}" >&2
                idx=$((idx + 1))
        done < <(get_applicable_rule_names)

        cat >&2 <<'USAGE'

Examples:
  Upgrade mode:
    ./preflight-cli.sh --type upgrade --target-ike 9.1.0 --target-ocp 4.17.26

  Fresh install mode (always prompts for IKE version):
    ./preflight-cli.sh --type fresh-install

  Select specific rules by name or number:
    ./preflight-cli.sh --type upgrade --target-ike 9.1.2 --rule 01-platform,03-sourceclust
    ./preflight-cli.sh --type upgrade --target-ike 9.1.2 --rule 1,3

  Interactive mode:
    ./preflight-cli.sh

USAGE

        exit "${exit_code}"
}
while [[ $# -gt 0 ]]; do
        case "$1" in
        --type)
                if [[ $# -lt 2 || "$2" == -* ]]; then
                        log_error "Missing value for --type. Use 'upgrade' or 'fresh-install'."
                        usage
                fi
                case "$2" in
                upgrade|fresh-install)
                        INSTALL_TYPE="$2"
                        TYPE_PROVIDED="true"
                        shift 2
                        ;;
                *)
                        log_error "Invalid type '$2'. Must be 'upgrade' or 'fresh-install'."
                        usage
                        ;;
                esac
                ;;
        --target-ocp)
                if [[ $# -lt 2 || "$2" == -* ]]; then
                        log_error "Missing value for --target-ocp. Example: --target-ocp 4.17.26"
                        usage
                fi
                TARGET_OCP="$2"
                shift 2
                ;;
        --target-ike)
                if [[ $# -lt 2 || "$2" == -* ]]; then
                        log_error "Missing value for --target-ike. Example: --target-ike 9.1.2"
                        usage
                fi
                IKE_VERSION="$2"
                shift 2
                ;;
        --rule|--rules)
                if [[ $# -lt 2 || "$2" == -* ]]; then
                        log_error "Missing value for --rule/--rules. Use rule name(s) or number(s), e.g. --rule 1,03-sourceclust"
                        usage
                fi
                SELECTED_RULES_RAW="$2"
                shift 2
                ;;
        --all)
                RUN_ALL_RULES="true"
                shift
                ;;
        -h|--help)
                usage 0
                ;;
        *)
                log_error "Unknown argument: $1"
                usage
                ;;
        esac
done

refresh_upgrade_matrix_from_github

if [[ "${TYPE_PROVIDED}" != "true" && -t 0 ]]; then
        INSTALL_TYPE=$(select_install_type)
fi

if [[ "${INSTALL_TYPE}" == "fresh-install" ]]; then
        if [[ -z "${IKE_VERSION}" ]]; then
                if [[ -t 0 ]]; then
                        IKE_VERSION=$(select_ike_version)
                else
                        log_error "Missing required argument: --target-ike <infoscale_version>"
                        usage
                fi
        fi
elif [[ -z "${IKE_VERSION}" ]]; then
        if [[ -t 0 ]]; then
                IKE_VERSION=$(select_upgrade_target_ike)
        else
                log_error "Missing required argument: --target-ike <infoscale_version>"
                usage
        fi
fi

IKE_VERSION="$(prompt_for_valid_ike_version "$IKE_VERSION")" || exit 1

if [[ "${INSTALL_TYPE}" == "upgrade" && -z "${TARGET_OCP}" && "${OCP_PROMPT_DONE}" != "true" && -t 0 ]]; then
        TARGET_OCP=$(select_target_ocp_version_optional)
        OCP_PROMPT_DONE="true"
fi


# Export variables for sourced rules
export TARGET_OCP
export IKE_VERSION
export INSTALL_TYPE
export RUN_LOG_DIR
export LOG_FILE
export VXREST_LOGS_FILE
export RESULTS_FILE
export RESULTS_JSON_FILE
export WRITE_RESULTS_TSV
export WRITE_RESULTS_JSON
export INTERNAL_LOG_FILE

log_info "=============================================================="
log_info " Preflight Check - $(date)"
log_info " Installation Type : ${INSTALL_TYPE}"
log_info " Target OCP        : ${TARGET_OCP}"
log_info " Target Infoscale  : ${IKE_VERSION}"
log_info "=============================================================="
log_info "Using rules from ${RULE_DIR}"

normalize_rule_name() {
        local rule_name="$1"
        if [[ "$rule_name" == *.sh ]]; then
                echo "$rule_name"
        else
                echo "${rule_name}.sh"
        fi
}

parse_selected_rules() {
        local raw="${1:-}"
        local token normalized idx
        local -a available_rules=()

        [[ -z "$raw" ]] && return 0

        mapfile -t available_rules < <(get_applicable_rule_names)
        if [[ "${#available_rules[@]}" -eq 0 ]]; then
                log_error "No applicable rules found for --type ${INSTALL_TYPE}"
                return 1
        fi

        IFS="," read -r -a tokens <<<"$raw"
        for token in "${tokens[@]}"; do
                token="$(printf "%s" "$token" | sed "s/^[[:space:]]*//;s/[[:space:]]*$//")"
                [[ -z "$token" ]] && continue

                if [[ "$token" =~ ^[0-9]+$ ]]; then
                        idx=$((token - 1))
                        if (( idx < 0 || idx >= ${#available_rules[@]} )); then
                                log_error "Invalid rule number '$token'. Valid range for --type ${INSTALL_TYPE}: 1-${#available_rules[@]}"
                                return 1
                        fi
                        normalized="${available_rules[$idx]}"
                else
                        normalized="$(normalize_rule_name "$token")"
                fi

                SELECTED_RULES_MAP["$normalized"]=1
        done

        if [[ "${#SELECTED_RULES_MAP[@]}" -eq 0 ]]; then
                log_error "No valid rules provided in --rules"
                return 1
        fi
}
validate_selected_rules_exist() {
        local rule
        local missing=0

        [[ "${#SELECTED_RULES_MAP[@]}" -eq 0 ]] && return 0

        for rule in "${!SELECTED_RULES_MAP[@]}"; do
                if [[ ! -f "${RULE_DIR}/$rule" ]]; then
                        log_error "Selected rule not found: $rule"
                        missing=1
                fi
        done

        [[ "$missing" -eq 0 ]]
}

should_execute_rule() {
        local rule_name="$1"

        if [[ "${#SELECTED_RULES_MAP[@]}" -gt 0 ]]; then
                [[ -n "${SELECTED_RULES_MAP[$rule_name]:-}" ]]
                return
        fi

        if [[ "${INSTALL_TYPE}" == "fresh-install" ]]; then
                case "$rule_name" in
                01-platform.sh)
                        return 0
                        ;;
                *)
                        return 1
                        ;;
                esac
        fi
        return 0
}

if [[ "${INSTALL_TYPE}" == "fresh-install" ]]; then
        if [[ -n "${SELECTED_RULES_RAW}" || "${RUN_ALL_RULES}" == "true" ]]; then
                log_info "Fresh-install mode ignores --rule/--rules/--all. Running only 01-platform by default."
        fi
        SELECTED_RULES_RAW=""
        RUN_ALL_RULES="false"
        SELECTED_RULES_MAP=()
elif [[ -z "${SELECTED_RULES_RAW}" && "${RUN_ALL_RULES}" != "true" && -t 0 ]]; then
        SELECTED_RULES_RAW="$(prompt_for_rules_optional)"
fi

if ! parse_selected_rules "${SELECTED_RULES_RAW}"; then
        usage
fi

if ! validate_selected_rules_exist; then
        usage
fi

if [[ "${INSTALL_TYPE}" == "fresh-install" ]]; then
        log_info " Selected rules    : 01-platform (default for fresh-install)"
elif [[ "${#SELECTED_RULES_MAP[@]}" -gt 0 ]]; then
        log_info " Selected rules    : ${SELECTED_RULES_RAW}"
else
        log_info " Selected rules    : all applicable rules"
fi

write_results_file() {
        local enabled
        enabled="$(printf '%s' "${WRITE_RESULTS_TSV}" | tr '[:upper:]' '[:lower:]')"
        case "${enabled}" in
                true|1|yes|y)
                        ;;
                *)
                        return 0
                        ;;
        esac

        {
                printf 'rule\tstatus\tmessage\n'
                while IFS= read -r rule; do
                        IFS=':' read -r status msg <<<"${RESULTS[$rule]}"
                        printf '%s\t%s\t%s\n' "$rule" "$status" "$msg"
                done < <(printf '%s\n' "${!RESULTS[@]}" | sort)
        } >"${RESULTS_FILE}"
}

create_run_log_archive() {
        local parent_dir archive_base archive_file

        parent_dir="$(dirname "${RUN_LOG_DIR}")"
        archive_base="$(basename "${RUN_LOG_DIR}")"

        if command -v zip >/dev/null 2>&1; then
                archive_file="${parent_dir}/${archive_base}.zip"
                rm -f "${archive_file}"
                if (cd "${parent_dir}" && zip -qr "${archive_file}" "${archive_base}"); then
                        RUN_LOG_ARCHIVE="${archive_file}"
                        return 0
                fi
                log_warn "Unable to create zip archive for ${RUN_LOG_DIR}"
                return 1
        fi

        if command -v tar >/dev/null 2>&1; then
                archive_file="${parent_dir}/${archive_base}.tar.gz"
                rm -f "${archive_file}"
                if (cd "${parent_dir}" && tar -czf "${archive_file}" "${archive_base}"); then
                        RUN_LOG_ARCHIVE="${archive_file}"
                        return 0
                fi
                log_warn "Unable to create tar.gz archive for ${RUN_LOG_DIR}"
                return 1
        fi

        log_warn "Neither zip nor tar is available; skipping log directory archive creation."
        return 1
}

report_run_artifacts() {
        log_info "All output saved to: ${LOG_FILE}"
        log_info "VxREST logs saved to: ${VXREST_LOGS_FILE}"
        if [[ "$(printf '%s' "${WRITE_RESULTS_TSV}" | tr '[:upper:]' '[:lower:]')" =~ ^(true|1|yes|y)$ ]]; then
                log_info "Check results file: ${RESULTS_FILE}"
        fi
        log_info "Run log directory: ${RUN_LOG_DIR}"
        if [[ -n "${RUN_LOG_ARCHIVE}" ]]; then
                log_info "Run log archive : ${RUN_LOG_ARCHIVE}"
        fi
}

# Config collection
for RULE_SCRIPT in "${RULE_DIR}"/*.sh; do
        RULE_NAME="$(basename "$RULE_SCRIPT")"

        if ! should_execute_rule "$RULE_NAME"; then
                log_info "Skipping rule (mode/selection filter): ${RULE_NAME}"
                continue
        fi

        log_info "Loading rule: ${RULE_NAME}"
        source "$RULE_SCRIPT"

        if ! (source "$RULE_SCRIPT" && config); then
                record_result "$RULE_NAME" "FAIL" "Config phase failed"
                log_error "Config failed for ${RULE_NAME}, aborting all checks."
                print_summary
                write_results_file
                create_run_log_archive || true
                report_run_artifacts
                log_error "Preflight terminated early. See log: ${LOG_FILE}"
                exit 1
        fi
done

# Executing rules
for RULE_SCRIPT in "${RULE_DIR}"/*.sh; do
        RULE_NAME="$(basename "$RULE_SCRIPT")"

        if ! should_execute_rule "$RULE_NAME"; then
                continue
        fi

        log_info "Executing: ${RULE_NAME}"

        if (source "$RULE_SCRIPT" && run); then
                record_result "$RULE_NAME" "PASS" "All checks passed"
        else
                record_result "$RULE_NAME" "FAIL" "Some checks failed"
        fi
done

print_summary
write_results_file
create_run_log_archive || true
report_run_artifacts
