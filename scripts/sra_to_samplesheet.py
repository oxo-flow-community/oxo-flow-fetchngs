#!/usr/bin/env python3
"""oxo-flow port of the samplesheet/mappings generation (nf-core/fetchngs 1.13.0).

Upstream 1.12.0 shipped this as the SRA_TO_SAMPLESHEET process (Groovy `exec`
block); in 1.13.0 that process was folded into the CHANNEL_SRA_CREATE_CSV
subworkflow (subworkflows/local/channel_sra_create_csv/main.nf) with the
`buildPipelineMap` helper plus the per-run FastQ-name rewrite in
workflows/fetchngs.nf. This script carries the 1.13.0 semantics:

1. `<id>.samplesheet.csv` — one row per run with the sample name (experiment
   accession), the outdir-relative FastQ paths and every remaining ENA
   metadata column. The FastQ file names follow the branch upstream's
   FETCHNGS `branch` closure assigns to the run (1.13.0):
     - ftp / aspera arms: `<id>[_1|_2].fastq.gz`
     - sratools arm (fasterq-dump 3.2.1, `--split-files --outfile <id>.fastq`
       + the `exclude_third` mv): single-end `<id>.fastq.gz`, paired-end
       `<id>.fastq_1.fastq.gz` / `<id>.fastq_2.fastq.gz`
       (the '#' path bug workaround, ncbi/sra-tools#865)
     - fastq-dl arm: the fastq-dl module's own names, keyed by the run
       accession: `<run>[_1|_2].fastq.gz` (single-end `<run>.fastq.gz`)
2. `<id>.mappings.csv` — the sample-id mapping restricted to the columns
   given by `--sample_mapping_fields`, validated against the available keys.

nf-core pipeline extras follow `buildPipelineMap` (1.13.0): rnaseq ->
strandedness, atacseq -> replicate=1, taxprofiler -> fasta='', ampliseq ->
run='', mag -> group='' / short_reads_platform='ILLUMINA' /
long_reads_platform='', sarek -> patient=sample_accession; metatdenovo and
viralrecon are valid `nf_core_pipeline` values without extra columns.

Usage: sra_to_samplesheet.py <TSV_IN> <SAMPLESHEET_OUT> <MAPPINGS_OUT> \
       <OUTDIR> <NF_CORE_PIPELINE> <STRANDEDNESS> <MAPPING_FIELDS> \
       <DOWNLOAD_METHOD>
"""

import csv
import sys

# Keys removed from the metadata map before writing the samplesheet
# (upstream `meta.subMap(meta.keySet() - [...])` in buildPipelineMap)
REMOVED = {"id", "fastq_1", "fastq_2", "md5_1", "md5_2", "single_end"}

# (key, value-builder) pairs per nf-core pipeline, mirroring the 1.13.0
# `pipeline_extras` map of buildPipelineMap (entries with a fixed value are
# stored as constants; sarek's patient column reads the row's ENA metadata).
PIPELINE_EXTRAS = {
    "ampliseq": ("run", ""),
    "atacseq": ("replicate", 1),
    "mag": None,          # handled specially: three columns
    "rnaseq": ("strandedness", None),  # value = strandedness param
    "sarek": ("patient", "sample_accession"),  # value from the row metadata
    "taxprofiler": ("fasta", ""),
}


def quote(value):
    return '"{}"'.format(value)


def final_branch(row, download_method):
    """Mirror the 1.13.0 FETCHNGS workflow `branch` closure (arm selection).

    The arm decides how the run's FastQ files are named, so the samplesheet
    must derive it exactly like upstream: aspera only with a fasp link,
    fastq-dl overrides aspera for the whole method, and runs without either
    download link (or the sratools method) always go to sra-tools.
    """
    branch = "ftp"
    if row.get("fastq_aspera") and download_method == "aspera":
        branch = "aspera"
    if download_method == "fastq-dl":
        branch = "fastq-dl"
    if (not row.get("fastq_aspera") and not row.get("fastq_1")) or download_method == "sratools":
        branch = "sratools"
    return branch


def fastq_names(row, branch):
    """FastQ file names per branch (see module docstring)."""
    run_id = row["id"]
    single_end = row.get("single_end") == "true"
    if branch == "sratools":
        if single_end:
            return "{}.fastq.gz".format(run_id), ""
        return "{}.fastq_1.fastq.gz".format(run_id), "{}.fastq_2.fastq.gz".format(run_id)
    if branch == "fastq-dl":
        run = row.get("run_accession") or run_id
        if single_end:
            return "{}.fastq.gz".format(run), ""
        return "{}_1.fastq.gz".format(run), "{}_2.fastq.gz".format(run)
    # ftp and aspera arms name files after meta.id
    if single_end:
        return "{}.fastq.gz".format(run_id), ""
    return "{}_1.fastq.gz".format(run_id), "{}_2.fastq.gz".format(run_id)


def main():
    if len(sys.argv) != 9:
        sys.exit(
            "usage: sra_to_samplesheet.py <TSV_IN> <SAMPLESHEET_OUT> <MAPPINGS_OUT> "
            "<OUTDIR> <NF_CORE_PIPELINE> <STRANDEDNESS> <MAPPING_FIELDS> <DOWNLOAD_METHOD>"
        )
    tsv_in, samplesheet_out, mappings_out, outdir = sys.argv[1:5]
    pipeline, strandedness, mapping_fields, download_method = (
        sys.argv[5], sys.argv[6], sys.argv[7], sys.argv[8]
    )

    with open(tsv_in, newline="") as fin:
        reader = csv.DictReader(fin, delimiter="\t")
        header = list(reader.fieldnames)
        rows = [dict(row) for row in reader]
    if not rows:
        sys.exit("No run rows found in {}".format(tsv_in))

    fields = [f.strip().lower() for f in mapping_fields.split(",")] if mapping_fields else []

    # nf-core pipeline specific entries (default: none). Upstream inserts
    # them into `pipeline_map` BEFORE the metadata map, so its rendered
    # header (`pipeline_map.keySet()`) carries them. Precompute the same key
    # set here so the samplesheet header, the validation set and the per-row
    # renders all stay in lockstep.
    extra_keys = {
        "rnaseq": ["strandedness"],
        "atacseq": ["replicate"],
        "taxprofiler": ["fasta"],
        "ampliseq": ["run"],
        "mag": ["group", "short_reads_platform", "long_reads_platform"],
        "sarek": ["patient"],
    }
    keys = ["sample", "fastq_1", "fastq_2"]
    keys += extra_keys.get(pipeline, [])
    keys += [k for k in header if k not in REMOVED]

    # Upstream check: `(pipeline_map.keySet() + fields).unique().size() != pipeline_map.keySet().size()`
    if len(set(keys + fields)) != len(set(keys)):
        sys.exit(
            "Invalid option for '--sample_mapping_fields': {}.\n"
            "Valid options: {}".format(mapping_fields, ", ".join(keys))
        )

    samplesheet_lines = [",".join(quote(k) for k in keys)]
    mapping_lines = [",".join(quote(f) for f in fields)] if fields else [""]

    for row in rows:
        branch = final_branch(row, download_method)
        fq1_name, fq2_name = fastq_names(row, branch)
        run_id = row["id"]
        # Upstream: `sample: "${meta.id.toString().split('_')[0..-2].join('_')}"`
        sample = run_id.rsplit("_", 1)[0] if "_" in run_id else run_id

        pipeline_map = {
            "sample": sample,
            "fastq_1": "{}/fastq/{}".format(outdir, fq1_name) if fq1_name else "",
            "fastq_2": "{}/fastq/{}".format(outdir, fq2_name) if fq2_name else "",
        }

        # nf-core pipeline specific entries (buildPipelineMap, 1.13.0)
        if pipeline == "rnaseq":
            pipeline_map["strandedness"] = strandedness
        elif pipeline == "atacseq":
            pipeline_map["replicate"] = 1
        elif pipeline == "taxprofiler":
            pipeline_map["fasta"] = ""
        elif pipeline == "ampliseq":
            pipeline_map["run"] = ""
        elif pipeline == "mag":
            pipeline_map["group"] = ""
            pipeline_map["short_reads_platform"] = "ILLUMINA"
            pipeline_map["long_reads_platform"] = ""
        elif pipeline == "sarek":
            pipeline_map["patient"] = row.get("sample_accession", "")

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
