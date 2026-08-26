#!/usr/bin/env bash
# Shared per-run sra-tools prefetch loop for the when-gated branches of the
# oxo-flow-fetchngs port (upstream SRATOOLS_PREFETCH + CUSTOM_SRATOOLSNCBISETTINGS):
#   - sra_prefetch_dbgap     (download_method = 'sratools', dbgap_key set)
#   - sra_prefetch_fallback  (download_method = 'ftp', sra_tools_fallback)
# The default-config rules (sra_prefetch / sra_fastq_sratools in main.oxoflow)
# carry the same logic inline: their rendered command is frozen by the
# byte-identical dry-run contract, so new branches live here instead.
#
# Usage: sra_prefetch_runs.sh [--fallback] <runinfo_ftp.tsv> <sra_dir> [certificate]
#   --fallback  only process runs whose metadata has NEITHER an FTP link
#               (fastq_1) NOR a fasp link (fastq_aspera) — the upstream
#               branch condition `!meta.fastq_aspera && !meta.fastq_1`
#   certificate dbGaP authorized-access certificate; `.ngc` -> `--ngc`,
#               `.jwt` -> `--perm` (upstream SRATOOLS_PREFETCH shell logic)
set -eu

fallback=false
if [ "${1:-}" = "--fallback" ]; then
    fallback=true
    shift
fi
tsv="${1:?runinfo tsv required}"
sra_dir="${2:?sra dir required}"
cert="${3:-}"

mkdir -p "$sra_dir"

# Upstream CUSTOM_SRATOOLSNCBISETTINGS: fresh NCBI user settings with a GUID
# and cloud identity reporting; per-sample file name (shared docker workdir,
# one rule instance runs this script at a time, keyed off the sra dir).
base=$(basename "$sra_dir")
guid=$(cat /proc/sys/kernel/random/uuid 2>/dev/null || date +%s%N)
printf '/LIBS/GUID = "%s"\n/libs/cloud/report_instance_identity = "true"\n' "$guid" > ".ncbi_${base}.mkfg"
export NCBI_SETTINGS="$PWD/.ncbi_${base}.mkfg"

# Upstream certificate handling (SRATOOLS_PREFETCH shell block)
cert_args=""
if [ -n "$cert" ]; then
    case "$cert" in
        *.jwt) cert_args="--perm $cert" ;;
        *.ngc) cert_args="--ngc $cert" ;;
    esac
fi

# Resolve column indices from the header (default ENA metadata fields)
header=$(head -n 1 "$tsv")
col_of() {
    printf '%s\n' "$header" | tr '\t' '\n' | grep -nx "$1" | cut -d: -f1
}
c_run=$(col_of run_accession)
c_fq1=$(col_of fastq_1)
c_fasp=$(col_of fastq_aspera)

# Upstream prefetch retry policy: 5 attempts, 1 s base delay, 100 s max
source scripts/retry_with_backoff.sh

# One row per run: prefetch the SRA record, then validate it. The retry
# helper manages failed attempts itself, so `set -e` is disabled around the
# call and the captured status is checked explicitly.
tail -n +2 "$tsv" | while read -r line; do
    run=$(printf '%s' "$line" | cut -f "$c_run")
    fq1=$(printf '%s' "$line" | cut -f "$c_fq1")
    fasp=$(printf '%s' "$line" | cut -f "$c_fasp")
    if [ "$fallback" = "true" ] && { [ -n "$fq1" ] || [ -n "$fasp" ]; }; then
        # This run has download links: it is handled by the ftp branch
        continue
    fi
    if [ -z "$run" ]; then
        echo "WARNING: row without run_accession skipped" >&2
        continue
    fi
    (
        cd "$sra_dir"
        set +e
        retry_with_backoff 5 1 100 prefetch $cert_args "$run"
        prefetch_status=$?
        set -e
        if [ "$prefetch_status" -ne 0 ]; then
            echo "prefetch failed for $run after retries" >&2
            exit "$prefetch_status"
        fi
        if [ -f "$run.sralite" ]; then
            vdb-validate "$run.sralite"
        else
            vdb-validate "$run"
        fi
    )
done
