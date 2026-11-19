#!/usr/bin/env bash
# Verbatim copy of the `retry_with_backoff` helper from the upstream
# nf-core/fetchngs 1.13.0 SRATOOLS_PREFETCH template
# (modules/nf-core/sratools/prefetch/templates/retry_with_backoff.sh),
# sourced by the `sra_prefetch` rule shell. The helper body is unchanged
# 1.12.0 -> 1.13.0 (only the template's Nextflow escaping style changed);
# 1.13.0 moved the post-call integrity gate into the template as
# `vdb-validate <id>` plus the md5sum comparison against the NCBI locate
# endpoint for checksum-less archives — ported into the callers
# (sra_prefetch inline rule + scripts/sra_prefetch_runs.sh). Upstream default
# retry policy (ext.args2): 5 attempts, 1 s base delay, 100 s max delay.

retry_with_backoff() {
    local max_attempts=${1}
    local delay=${2}
    local max_time=${3}
    local attempt=1
    local output=
    local status=

    # Remove the first three arguments to this function in order to access
    # the 'real' command with `${@}`.
    shift 3

    while [ ${attempt} -le ${max_attempts} ]; do
        output=$("${@}")
        status=${?}

        if [ ${status} -eq 0 ]; then
            break
        fi

        if [ ${attempt} -lt ${max_attempts} ]; then
            echo "Failed attempt ${attempt} of ${max_attempts}. Retrying in ${delay} s." >&2
            sleep ${delay}
        elif [ ${attempt} -eq ${max_attempts} ]; then
            echo "Failed after ${attempt} attempts." >&2
            return ${status}
        fi

        attempt=$(( ${attempt} + 1 ))
        delay=$(( ${delay} * 2 ))
        if [ ${delay} -ge ${max_time} ]; then
            delay=${max_time}
        fi
    done

    echo "${output}"
}
