#!/usr/bin/env python3
"""oxo-flow port of the SRA_TO_SAMPLESHEET process (nf-core/fetchngs 1.12.0).

Translates the upstream Groovy `exec` block: reads the runinfo_ftp.tsv
produced by sra_runinfo_to_ftp.py (one row per run) and writes, per id:

1. `<id>.samplesheet.csv` — one row per run with the sample name (experiment
   accession), the FastQ paths (mirroring the upstream
   `meta.fastq_1 = "${params.outdir}/fastq/${reads[0].getName()}"` rewrite;
   with `skip_fastq_download=true` the raw ENA URLs from the metadata are
   used unchanged, as upstream does when the download branch is skipped) and
   every remaining ENA metadata column, with the nf-core pipeline columns
   (strandedness / replicate / fasta) inserted between `fastq_2` and the
   metadata columns (upstream `pipeline_map.keySet()` order).
2. `<id>.mappings.csv` — the sample-id mapping restricted to the columns
   given by `--sample_mapping_fields` (upstream prepends `'sample'` to the
   fields), validated against the available keys.

Usage: sra_to_samplesheet.py <TSV_IN> <SAMPLESHEET_OUT> <MAPPINGS_OUT> \
       <OUTDIR> <NF_CORE_PIPELINE> <STRANDEDNESS> <MAPPING_FIELDS> <SKIP_FASTQ_DOWNLOAD>
"""

import csv
import sys

# Keys removed from the metadata map before writing the samplesheet
# (upstream `meta_clone.remove(...)` calls)
REMOVED = {"id", "fastq_1", "fastq_2", "md5_1", "md5_2", "single_end"}

# nf-core pipeline specific columns, inserted between fastq_2 and the
# metadata columns (upstream `pipeline_map << [...]`); `viralrecon` is a
# valid enum value but adds no extra columns (same as upstream).
PIPELINE_COLUMNS = {
    "rnaseq": ["strandedness"],
    "atacseq": ["replicate"],
    "taxprofiler": ["fasta"],
    "viralrecon": [],
}


def quote(value):
    return '"{}"'.format(value)


def main():
    if len(sys.argv) != 9:
        sys.exit(
            "usage: sra_to_samplesheet.py <TSV_IN> <SAMPLESHEET_OUT> <MAPPINGS_OUT> "
            "<OUTDIR> <NF_CORE_PIPELINE> <STRANDEDNESS> <MAPPING_FIELDS> <SKIP_FASTQ_DOWNLOAD>"
        )
    tsv_in, samplesheet_out, mappings_out, outdir = sys.argv[1:5]
    pipeline, strandedness, mapping_fields = sys.argv[5], sys.argv[6], sys.argv[7]
    skip_fastq_download = sys.argv[8].strip().lower() == "true"

    with open(tsv_in, newline="") as fin:
        reader = csv.DictReader(fin, delimiter="\t")
        header = list(reader.fieldnames)
        rows = [dict(row) for row in reader]
    if not rows:
        sys.exit("No run rows found in {}".format(tsv_in))

    # Upstream: `fields = mapping_fields ? ['sample'] + mapping_fields.split(',').collect{ it.trim().toLowerCase() } : []`
    fields = (["sample"] + [f.strip().lower() for f in mapping_fields.split(",")]) if mapping_fields else []

    # Samplesheet column keys follow the upstream `pipeline_map.keySet()`
    # order: sample, fastq_1, fastq_2, nf-core pipeline columns, then every
    # remaining metadata column.
    pipeline_keys = PIPELINE_COLUMNS.get(pipeline, [])
    keys = ["sample", "fastq_1", "fastq_2"] + pipeline_keys + [k for k in header if k not in REMOVED]

    # Upstream check: `(mappings_map.keySet() + fields).unique().size() != mappings_map.keySet().size()`
    if len(set(keys + fields)) != len(set(keys)):
        sys.exit(
            "Invalid option for '--sample_mapping_fields': {}.\n"
            "Valid options: {}".format(mapping_fields, ", ".join(keys))
        )

    samplesheet_lines = [",".join(quote(k) for k in keys)]
    mapping_lines = [",".join(quote(f) for f in fields)] if fields else [""]

    for row in rows:
        run_id = row["id"]
        single_end = row.get("single_end") == "true"
        # Upstream: `sample: "${meta.id.split('_')[0..-2].join('_')}"`
        sample = run_id.rsplit("_", 1)[0] if "_" in run_id else run_id

        if skip_fastq_download:
            # Metadata-only mode (upstream `skip_fastq_download`): the
            # download branch is skipped entirely and the raw ENA URLs from
            # the runinfo metadata flow into the samplesheet unchanged.
            pipeline_map = {
                "sample": sample,
                "fastq_1": row.get("fastq_1", ""),
                "fastq_2": row.get("fastq_2", ""),
            }
        else:
            if single_end:
                fq1_name = "{}.fastq.gz".format(run_id)
                fq2_name = ""
            else:
                fq1_name = "{}_1.fastq.gz".format(run_id)
                fq2_name = "{}_2.fastq.gz".format(run_id)
            # Upstream: `meta.fastq_1 = "${params.outdir}/fastq/${reads[0].getName()}"`
            pipeline_map = {
                "sample": sample,
                "fastq_1": "{}/fastq/{}".format(outdir, fq1_name),
                "fastq_2": "{}/fastq/{}".format(outdir, fq2_name) if not single_end else "",
            }

        # nf-core pipeline specific entries (default: none)
        if pipeline == "rnaseq":
            pipeline_map["strandedness"] = strandedness
        elif pipeline == "atacseq":
            pipeline_map["replicate"] = 1
        elif pipeline == "taxprofiler":
            pipeline_map["fasta"] = ""

        for key in header:
            if key not in REMOVED:
                pipeline_map[key] = row.get(key, "")

        samplesheet_lines.append(",".join(quote(pipeline_map.get(k, "")) for k in keys))
        mapping_lines.append(",".join(quote(pipeline_map.get(f, "")) for f in fields))

    with open(samplesheet_out, "w", newline="") as fout:
        fout.write("\n".join(samplesheet_lines) + "\n")
    with open(mappings_out, "w", newline="") as fout:
        fout.write("\n".join(mapping_lines) + "\n")


if __name__ == "__main__":
    sys.exit(main())
