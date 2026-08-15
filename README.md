# oxo-flow-fetchngs — Fetching public sequencing data: FastQ download, metadata and samplesheets

[![CI](https://github.com/oxo-flow-community/oxo-flow-fetchngs/actions/workflows/ci.yml/badge.svg)](https://github.com/oxo-flow-community/oxo-flow-fetchngs/actions/workflows/ci.yml)
[![License](https://img.shields.io/badge/license-Apache%202.0-blue.svg)](LICENSE)

> ★ Verified · ⇄ Official port of [`nf-core/fetchngs`](https://github.com/nf-core/fetchngs) @ `1.12.0` — same tools, same versions, same commands. Part of the [oxo-flow-community catalog](https://oxo-flow-community.github.io/).

Fetch metadata and raw FastQ files from public sequence databases (SRA / ENA
/ DDBJ / GEO). Given a list of database identifiers — run accessions
(SRR/ERR/DRR), experiments, studies, biosamples or GEO series — the pipeline
retrieves the ENA run metadata, downloads the FastQ files over FTP, validates
every download against its ENA md5 sum, and auto-creates a samplesheet plus
sample id-mappings and a MultiQC mappings config, ready for downstream
nf-core pipelines such as rnaseq, atacseq or taxprofiler. You get a
ready-to-use `samplesheet.csv`, `id_mappings.csv` and `multiqc_config.yml`
together with the downloaded FastQ files and their checksums.

## Installation

### 1. Install oxo-flow

Requires **oxo-flow >= 0.12.0**. Release binary (recommended):

```bash
curl -fL -o oxo-flow.tar.gz \
  https://github.com/Traitome/oxo-flow/releases/latest/download/oxo-flow-latest-x86_64-unknown-linux-gnu.tar.gz
tar xzf oxo-flow.tar.gz
sudo mv oxo-flow /usr/local/bin/
```

Alternatively via conda: `conda install -c bioconda oxo-flow-cli` (note: the
conda package may lag behind releases; other platform binaries are available
on the [releases page](https://github.com/Traitome/oxo-flow/releases)).

### 2. Get this workflow

```bash
git clone https://github.com/oxo-flow-community/oxo-flow-fetchngs.git
cd oxo-flow-fetchngs
```

### 3. Requirements

- **Reference data — none.** This workflow downloads data from public
  archives, so no genome FASTA, annotation or indices are required. The only
  input is an ids file: one SRA/ENA/DDBJ/GEO accession per line (`[config]
  input`, default `test/fixtures/ids.txt`), kept in sync with the
  `[[sample_groups]]` sample source (extra ids can be added with
  `--sample <ID>` on the CLI).
- **Compute** — up to 2 CPUs / 12 GB per rule: the FastQ-download rule uses
  2 threads / 12 GB; the metadata-fetch and samplesheet rules use 1 thread /
  6 GB. Three rules carry a 4 h time limit for large metadata downloads.
- **Network** — outbound access to ENA over FTP (wget `-t 5 -c -T 60`, 2
  retries); no credentials required.
- **Tools** — Docker containers with pinned images
  (`quay.io/biocontainers/...`, identical to upstream), declared per rule in
  `main.oxoflow` (`[rules.environment]`); Docker is required at runtime (no
  conda environments are used).
- **Disk** — `results/fastq/` grows with the downloaded FastQ files plus
  `md5/` checksums; the total depends on your input size. `results/metadata/`
  and `results/samplesheet/` stay small.

## Usage

```bash
# 1. install oxo-flow (see Installation)
# 2. prepare data: an ids file (one SRA/ENA/DDBJ/GEO id per line) + matching
#    sample source (see test/fixtures/ids.txt and [[sample_groups]])
# 3. preview the plan
oxo-flow dry-run main.oxoflow
# 4. run
oxo-flow run main.oxoflow -j 8
# 5. run a subset
oxo-flow run main.oxoflow -t combine_samplesheets --samples first:2
```

Results land in `results/`: `fastq/` (downloaded FastQ + `md5/` checksums),
`metadata/` (runinfo TSVs), `samplesheet/` (`samplesheet.csv`,
`id_mappings.csv`, `multiqc_config.yml`), `pipeline_info/`.

Configuration lives in the `[config]` block of `main.oxoflow`: `input` (the
ids file), `ena_metadata_fields` (comma-separated ENA metadata fields; empty
= upstream default field list), `download_method` (`ftp`),
`skip_fastq_download`, `nf_core_pipeline` (tailor the samplesheet for
rnaseq/atacseq/taxprofiler) and `sample_mapping_fields` (drives the MultiQC
mappings config).

## Source

Upstream: **[nf-core/fetchngs](https://github.com/nf-core/fetchngs)** @
`1.12.0` (commit `8ec2d934f9301c818d961b1e4fdf7fc79610bdc5`), MIT license.
Created 2026-08-15; this workflow may lag behind upstream releases. See
[NOTICE.md](NOTICE.md) for attribution.

## Fidelity

Default-parameters main execution path (`--download_method ftp`,
`--skip_fastq_download false`). Rows cover every upstream process/subworkflow
that the default path touches.

| Upstream process/rule | oxo-flow rule | Tool (version) | Notes |
|---|---|---|---|
| PIPELINE_INITIALISATION (`isSraId` + id channel) | `check_ids` | python 3.9.5 | Validation regex, mixture/empty errors and deduplication ported 1:1 into `scripts/check_ids.py`; outputs `results/pipeline_info/input_ids.txt`. The ids channel itself is expanded from the workflow sample source (`[[sample_groups]]`, add ids via `--sample`); keep `[config] input` in sync. |
| SRA_IDS_TO_RUNINFO | `sra_ids_to_runinfo` | python 3.9.5 (`quay.io/biocontainers/python:3.9--1`) | Upstream `echo $id > id.txt; sra_ids_to_runinfo.py id.txt <id>.runinfo.tsv` verbatim; `--ena_metadata_fields` flag emitted only when set (same conditional). One instance per input id (upstream: one process per id). The intermediate `.runinfo.tsv` lands in `results/metadata/` (upstream leaves it unpublished in the workdir; oxo-flow requires declared outputs for the DAG contract). |
| SRA_RUNINFO_TO_FTP | `sra_runinfo_to_ftp` | python 3.9.5 | `sra_runinfo_to_ftp.py` verbatim; output `<id>.runinfo_ftp.tsv` → `results/metadata/` (published upstream). |
| SRA_FASTQ_FTP | `sra_fastq_ftp` | wget 1.20.1 (`quay.io/biocontainers/wget:1.20.1`), md5sum (coreutils, in the same image) | wget flags `-t 5 -nv -c -T 60`, `-O <exp>_<run>[_1|_2].fastq.gz` naming and `echo md5 … | md5sum -c` verification byte-identical; fastq → `results/fastq/`, md5 → `results/fastq/md5/` (upstream publishDir patterns). Per-run row parsing replaces the Groovy channel `branch`; **no outputs declared** because the produced file set (single- vs paired-end, per-run names) is data-dependent — md5 verification in the command is the correctness gate (same as upstream). Runs without FTP links are skipped with a warning (upstream routes them to the sra-tools fallback, not ported). |
| SRA_TO_SAMPLESHEET | `sra_to_samplesheet` | python 3.9.5 | Groovy `exec` block ported 1:1 into `scripts/sra_to_samplesheet.py` (removed keys, `sample` = experiment accession, `fastq_1/2` = `<outdir>/fastq/<file>`, ENA columns appended, `--sample_mapping_fields` validation with upstream error text). `localrule`, 100 MB memory, `executor 'local'` mapped to `localrule = true`. Runs only when `skip_fastq_download` is false (upstream: channel empty when skipped). |
| `collectFile('samplesheet.csv')` | `combine_samplesheets` | system (bash + coreutils) | Gather via `expand_inputs` over `config.samples_list`; header kept once, sorted by basename (upstream `keepHeader: true, sort: { it.baseName }`); `results/samplesheet/samplesheet.csv`. |
| `collectFile('id_mappings.csv')` | `combine_mappings` | system (bash + coreutils) | Same gather semantics; `results/samplesheet/id_mappings.csv`. |
| MULTIQC_MAPPINGS_CONFIG | `multiqc_mappings_config` | python 3.9.5 | `multiqc_mappings_config.py` verbatim; output `results/samplesheet/multiqc_config.yml` (upstream publishDir). Gated on `sample_mapping_fields` being set — on by default, same as upstream. |
| softwareVersionsToYAML + `versions.yml` | not ported | — | nf-core boilerplate (software-version collection for the MultiQC report); no engine equivalent, no downstream consumer in the port. |
| PIPELINE_COMPLETION (emails, summary, hooks) | not ported | — | nf-core boilerplate; oxo-flow has no workflow-level hooks. |
| CUSTOM_SRATOOLSNCBISETTINGS, SRATOOLS_PREFETCH, SRATOOLS_FASTERQDUMP (sra-tools 3.0.8 / 2.11.0 + pigz 2.6, incl. the `.sralite` variant) | not ported | — | Data-dependent fallback branch: only runs with **no** FTP links go here, decided per-run from fetched metadata at runtime. oxo-flow cannot branch per-row on data; the default path is FTP. Runs without FTP links are skipped with a warning (see `sra_fastq_ftp`). |
| ASPERA_CLI (Aspera CLI 4.14.0, `fasp` links) | not ported | — | Only with `--download_method aspera`, not the default. |
| dbGaP (`--dbgap_key`) | not ported | — | Only relevant to the sra-tools path (controlled-access data). |
| `params.nf_core_pipeline` (rnaseq/atacseq/taxprofiler columns) | `sra_to_samplesheet` | — | Off by default (empty), same as upstream; the column logic is ported and activates when `nf_core_pipeline` is set. |
| publishDir / `--publish_dir_mode` | n/a | — | oxo-flow has no publishDir; outputs are declared directly at their `results/…` paths. |

Known limitations: the ids used for per-id expansion must be declared in the
sample source (`[[sample_groups]]`, or `--sample` on the CLI) and should match
`[config] input` validated by `check_ids`; sra-tools / Aspera download methods
are not ported (see table).

## Test

```bash
bash test/run.sh
```

Runs `oxo-flow validate`, `oxo-flow lint` and a `dry-run` smoke check; CI runs
the same script on every push.

## License

Apache-2.0. Copyright (c) 2026 oxo-flow-community. Upstream attribution in
[NOTICE.md](NOTICE.md); the upstream MIT license is included verbatim at
[LICENSE.upstream](LICENSE.upstream).
