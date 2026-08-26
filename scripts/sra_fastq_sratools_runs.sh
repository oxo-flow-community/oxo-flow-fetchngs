#!/usr/bin/env bash
# Shared per-run fasterq-dump + pigz loop for the when-gated branches of the
# oxo-flow-fetchngs port (upstream SRATOOLS_FASTERQDUMP):
#   - sra_fastq_sratools_dbgap     (download_method = 'sratools', dbgap_key set)
#   - sra_fastq_sratools_fallback  (download_method = 'ftp', sra_tools_fallback)
# See sra_prefetch_runs.sh for the sibling comment about the frozen inline
# copies in main.oxoflow.
#
# Usage: sra_fastq_sratools_runs.sh [--fallback] <runinfo_ftp.tsv> <sra_dir> <fastq_dir> [certificate]
#   --fallback  only process runs without FTP/fasp links (same filter as
#               sra_prefetch_runs.sh --fallback)
#   certificate dbGaP authorized-access certificate; `.ngc` -> `--ngc`,
#               `.jwt` -> `--perm` (upstream SRATOOLS_FASTERQDUMP script logic)
set -eu

fallback=false
if [ "${1:-}" = "--fallback" ]; then
    fallback=true
    shift
fi
tsv="${1:?runinfo tsv required}"
sra_dir="${2:?sra dir required}"
fastq_dir="${3:?fastq dir required}"
cert="${4:-}"

mkdir -p "$fastq_dir"

# Fresh NCBI settings as in sra_prefetch_runs.sh (fasterq-dump requires them
# too); per-sample file name (shared docker workdir).
base=$(basename "$sra_dir")
guid=$(cat /proc/sys/kernel/random/uuid 2>/dev/null || date +%s%N)
printf '/LIBS/GUID = "%s"\n/libs/cloud/report_instance_identity = "true"\n' "$guid" > ".ncbi_${base}.mkfg"
export NCBI_SETTINGS="$PWD/.ncbi_${base}.mkfg"

# Upstream certificate handling (SRATOOLS_FASTERQDUMP script block)
key_file=""
if [ -n "$cert" ]; then
    case "$cert" in
        *.jwt) key_file="--perm $cert" ;;
        *.ngc) key_file="--ngc $cert" ;;
    esac
fi

# Resolve column indices from the header (default ENA metadata fields)
header=$(head -n 1 "$tsv")
col_of() {
    printf '%s\n' "$header" | tr '\t' '\n' | grep -nx "$1" | cut -d: -f1
}
c_id=$(col_of id)
c_run=$(col_of run_accession)
c_fq1=$(col_of fastq_1)
c_fasp=$(col_of fastq_aspera)
c_se=$(col_of single_end)

# One row per run: fasterq-dump the prefetched record, compress with pigz.
# fasterq-dump runs in a per-run temp dir so concurrent rule instances in
# the shared docker workdir cannot cross-talk (pigz would otherwise glob
# another instance's fastq).
tail -n +2 "$tsv" | while read -r line; do
    run_id=$(printf '%s' "$line" | cut -f "$c_id")
    run=$(printf '%s' "$line" | cut -f "$c_run")
    fq1=$(printf '%s' "$line" | cut -f "$c_fq1")
    fasp=$(printf '%s' "$line" | cut -f "$c_fasp")
    se=$(printf '%s' "$line" | cut -f "$c_se")
    if [ "$fallback" = "true" ] && { [ -n "$fq1" ] || [ -n "$fasp" ]; }; then
        # This run has download links: it is handled by the ftp branch
        continue
    fi
    if [ -z "$run" ]; then
        echo "WARNING: no run accession for ${run_id}; skipping" >&2
        continue
    fi
    sra_file="$sra_dir/$run.sra"
    [ -f "$sra_file" ] || sra_file="$sra_dir/$run.sralite"
    if [ ! -f "$sra_file" ]; then
        echo "ERROR: prefetched SRA file for ${run} not found in $sra_dir" >&2
        exit 1
    fi
    d=".fd_${base}_${run}"
    mkdir -p "$d"
    (
        cd "$d"
        if [ "$se" = "true" ]; then
            fasterq-dump --split-files --include-technical --threads 2 --outfile "${run_id}.fastq" $key_file "$sra_file"
        else
            fasterq-dump --split-files --include-technical --threads 2 --outfile "$run_id" $key_file "$sra_file"
        fi
        pigz --no-name --processes 2 ./*.fastq
        mv ./*.fastq.gz "$fastq_dir/"
    )
    rm -rf "$d"
done
