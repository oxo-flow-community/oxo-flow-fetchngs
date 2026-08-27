#!/usr/bin/env bash
# Shared per-run FTP download loop for the when-gated branches of the
# oxo-flow-fetchngs port (upstream SRA_FASTQ_FTP):
#   - sra_fastq_ftp_aspera_fallback  (download_method = 'aspera', sra_tools_fallback)
# The default-config rule (sra_fastq_ftp in main.oxoflow) carries the same
# logic inline: its rendered command is frozen by the byte-identical dry-run
# contract, so new branches live here instead (same pattern as
# sra_prefetch_runs.sh / sra_fastq_sratools_runs.sh).
#
# Usage: sra_fastq_ftp_aspera_runs.sh <runinfo_ftp.tsv> <out_dir>
# Processes exactly the rows upstream's `branch` sends to the FTP arm when
# download_method = 'aspera': runs that have an FTP link (fastq_1) but NO
# fasp link (fastq_aspera). The runinfo tsv is partitioned with the sibling
# rules of the same toggle: rows with a fasp link are downloaded by
# sra_fastq_aspera, rows with neither link are prefetched by
# sra_prefetch_fallback / sra_fastq_sratools_fallback — every run is
# downloaded exactly once, by whichever branch upstream's `branch` would
# pick.
set -eu

tsv="${1:?runinfo tsv required}"
out_dir="${2:?out dir required}"
fastq_dir="$out_dir/fastq"
md5_dir="$fastq_dir/md5"
mkdir -p "$fastq_dir" "$md5_dir"

# Resolve column indices from the header (default ENA metadata fields)
header=$(head -n 1 "$tsv")
col_of() {
    printf '%s\n' "$header" | tr '\t' '\n' | grep -nx "$1" | cut -d: -f1
}
c_id=$(col_of id)
c_fq1=$(col_of fastq_1)
c_fq2=$(col_of fastq_2)
c_md51=$(col_of md5_1)
c_md52=$(col_of md5_2)
c_se=$(col_of single_end)
c_fasp=$(col_of fastq_aspera)

# One row per run: download each FastQ file and verify its md5sum
tail -n +2 "$tsv" | while read -r line; do
    run_id=$(printf '%s' "$line" | cut -f "$c_id")
    fq1=$(printf '%s' "$line" | cut -f "$c_fq1")
    md51=$(printf '%s' "$line" | cut -f "$c_md51")
    fasp=$(printf '%s' "$line" | cut -f "$c_fasp")
    if [ -n "$fasp" ]; then
        echo "INFO: ${run_id} has a fasp link; handled by sra_fastq_aspera, skipping here" >&2
        continue
    fi
    if [ -z "$fq1" ]; then
        echo "INFO: no FTP link for ${run_id}; handled by the sra-tools fallback (sra_prefetch_fallback), skipping here" >&2
        continue
    fi
    # Download only when the file is absent or fails its md5 (idempotent
    # re-runs; live: wget -c appended corrupt proxy data to a complete
    # staged file and the subsequent md5 check failed).
    fetch_verified() {
        url="$1"
        out="$2"
        expected="$3"
        base=$(basename "$out")
        if [ -f "$out" ] && printf '%s  %s\n' "$expected" "$base" | (cd "$fastq_dir" && md5sum -c - > /dev/null 2>&1); then
            return 0
        fi
        wget -t 5 -nv -c -T 60 -O "$out" "$url" || exit 1
        printf '%s  %s\n' "$expected" "$base" > "$md5_dir/${base}.md5"
        (cd "$fastq_dir" && md5sum -c "md5/${base}.md5") || exit 1
    }
    se=$(printf '%s' "$line" | cut -f "$c_se")
    if [ "$se" = "true" ]; then
        fetch_verified "$fq1" "$fastq_dir/${run_id}.fastq.gz" "$md51"
    else
        fq2=$(printf '%s' "$line" | cut -f "$c_fq2")
        md52=$(printf '%s' "$line" | cut -f "$c_md52")
        fetch_verified "$fq1" "$fastq_dir/${run_id}_1.fastq.gz" "$md51"
        fetch_verified "$fq2" "$fastq_dir/${run_id}_2.fastq.gz" "$md52"
    fi
done
