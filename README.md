# oxo-flow-fetchngs — Fetching public sequencing data: FastQ download, metadata and samplesheets

[![CI](https://github.com/oxo-flow-community/oxo-flow-fetchngs/actions/workflows/ci.yml/badge.svg)](https://github.com/oxo-flow-community/oxo-flow-fetchngs/actions/workflows/ci.yml)
[![License](https://img.shields.io/badge/license-Apache%202.0-blue.svg)](LICENSE)

> ★ Verified · ⇄ Official port of [`nf-core/fetchngs`](https://github.com/nf-core/fetchngs) @ `1.13.0` — same tools, same versions, same commands. Part of the [oxo-flow-community catalog](https://oxo-flow-community.github.io/).

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

Requires **oxo-flow >= 0.17.0**. Release binary (recommended):

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
- **Compute** — up to 2 CPUs / 12 GB per rule: the FastQ-download rules
  (`sra_fastq_ftp`, `sra_fastq_fastqdl` and `sra_fastq_ftp_aspera_fallback`
  2 threads / 12 GB, `sra_fastq_sratools` 2 threads / 8 GB) are the
  heaviest; metadata/samplesheet rules use 1 thread / 1-6 GB; `sra_prefetch`
  1 thread / 2 GB; `sra_fastq_aspera` 1 thread / 4 GB. Thirteen rules carry
  a 4 h time limit (all download and metadata rules plus
  `multiqc_mappings_config`).
- **Network** — outbound access to ENA over FTP (wget `-t 5 -nv -w 5
  --random-wait -c -T 60`, 2 retries); no credentials required. The
  `sratools` branch additionally reaches the NCBI SRA endpoints (prefetch /
  fasterq-dump) and the NCBI locate endpoint used for the md5 check of
  checksum-less prefetch archives; the `aspera` branch needs ENA fasp on
  port 33001 plus outbound internet at runtime (the 4.20.0 image fetches
  its ascp client via `ascli conf ascp install`); the `fastq-dl` branch
  queries ENA and downloads from ENA's own mirrors.
- **Tools** — Docker containers with pinned images
  (`quay.io/biocontainers/...` and `community.wave.seqera.io/library/...`,
  identical to upstream), declared per rule in `main.oxoflow`
  (`[rules.environment]`); Docker is required at runtime (no conda
  environments are used).
- **Disk** — `results/fastq/` grows with the downloaded FastQ files plus
  `md5/` checksums; the total depends on your input size.
  `results/metadata/` holds the runinfo tables (and, for the `fastq-dl`
  branch, the per-run `*-run-info.tsv` / `*-run-mergers.tsv`);
  `results/samplesheet/` stays small.

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
= upstream default field list), `download_method` (`ftp`, the upstream
default, or `sratools` / `aspera` / `fastq-dl` — each gates its own download
branch; `fastq-dl` queries ENA directly and downloads from ENA's own mirrors),
`skip_fastq_download`, `sra_tools_fallback` (upstream's per-run triage for
runs without the method's download links — ftp-method runs without
FTP/fasp links and aspera-method runs without a fasp link are routed to the
FTP / sra-tools branches; off by default so the default plan is unchanged —
see the fidelity table; with `download_method = fastq-dl` the triage runs
unconditionally, like upstream), `dbgap_key` (path to a `.ngc`/`.jwt` dbGaP
authorized-access certificate for the sratools branch; empty = public data
only), `nf_core_pipeline` (tailor the samplesheet for one of the upstream
schema enum values `ampliseq`, `atacseq`, `mag`, `metatdenovo`, `rnaseq`,
`sarek`, `taxprofiler`, `viralrecon`), `sample_mapping_fields` (drives the
MultiQC mappings config) and the completion-notification keys `email` /
`email_on_fail` (see below).

### Completion notifications

The upstream `PIPELINE_COMPLETION` (nf-core `workflow.onComplete` +
`workflow.onError`) is ported onto the engine's workflow-level terminal
hooks `[workflow] on_complete` / `on_error` (engine >= 0.17.0 to fire;
unknown `[workflow]` keys are ignored by older engines, so they no-op there
and the default plan is unchanged). Both keys default empty (upstream's null
params) — the hooks are no-ops unless configured:

- `email` — address the run-summary mail is sent to after a run without
  failed rules (`sendmail -t` if available, else `mail`; if neither exists
  the hook only warns — notifications never change the run status)
- `email_on_fail` — address mailed after a failed run; falls back to
  `email` when empty (nf-core behavior)

Upstream 1.13.0 removed the 1.12.0 `hook_url` / `imNotification` webhook
feature together with its `assets/adaptivecard.json` /
`assets/slackreport.json` payloads, so this port carries no webhook branch
either. The upstream `workflow.onError` troubleshooting note is echoed by
the script on failed runs.

The hooks run `scripts/pipeline_completion.sh` in the workflow root; the
mail subject/body mirror the upstream summary (status + `{succeeded}` /
`{failed}` / `{skipped}` counters + `results/` path). Upstream's
`sraCurateSamplesheetWarn` end-of-run log note has no hook: the
auto-created samplesheet should be curated manually (see the Known
limitations paragraph below).

## Source

Upstream: **[nf-core/fetchngs](https://github.com/nf-core/fetchngs)** @
`1.13.0` (commit `955c892d80927cee633765e6e390f9cc6b7235c9`), MIT license.
Created 2026-08-14, re-ported to 1.13.0 2026-11-19; this workflow may lag
behind upstream releases. See [NOTICE.md](NOTICE.md) for attribution.

## Fidelity

Default-parameters main execution path (`--download_method ftp`,
`--skip_fastq_download false`). Rows cover every upstream process/subworkflow
that the default path touches.

| Upstream process/rule | oxo-flow rule | Tool (version) | Notes |
|---|---|---|---|
| PIPELINE_INITIALISATION (id validation + id channel) | `check_ids` | python 3.9.5 | In 1.12.0 this was the `isSraId` Groovy check of PIPELINE_INITIALISATION; in 1.13.0 upstream validates `--input` against the items pattern of `assets/schema_input.json` via the nf-schema plugin's `samplesheetToList` — the regex is byte-identical in both, and oxo-flow has no schema plugin, so `scripts/check_ids.py` remains the port-side enforcement point: validation regex, mixture/empty errors and deduplication ported 1:1; outputs `results/pipeline_info/input_ids.txt`. The ids channel itself is expanded from the workflow sample source (`[[sample_groups]]`, add ids via `--sample`); keep `[config] input` in sync. |
| SRA_IDS_TO_RUNINFO | `sra_ids_to_runinfo` | python 3.9.5 (`quay.io/biocontainers/python:3.9--1`) | Upstream `echo ${id} > id.txt; sra_ids_to_runinfo.py id.txt <id>.runinfo.tsv` verbatim; `--ena_metadata_fields` flag emitted only when set (same conditional), and since 1.13.0 (PR 381) upstream quotes the list and collapses whitespace around the commas — ported as a quoted bash array so field lists cannot word-split. One instance per input id (upstream: one process per id). The intermediate `.runinfo.tsv` lands in `results/metadata/` (upstream leaves it unpublished in the workdir; oxo-flow requires declared outputs for the DAG contract). |
| SRA_RUNINFO_TO_FTP | `sra_runinfo_to_ftp` | python 3.9.5 | `sra_runinfo_to_ftp.py` verbatim; output `<id>.runinfo_ftp.tsv` → `results/metadata/` (published upstream). |
| SRA_FASTQ_FTP | `sra_fastq_ftp` | wget 1.25.0 (`community.wave.seqera.io/library/gzip_wget:041a8ba200c3fa3f`, the upstream 1.13.0 Seqera Wave image bundling gzip 1.14 + wget 1.25.0), md5sum (coreutils, in the same image) | wget flags `-t 5 -nv -w 5 --random-wait -c -T 60` (1.13.0 added the `-w 5 --random-wait` wait flags, PR 325), `-O <exp>_<run>[_1|_2].fastq.gz` naming and `echo md5 … | md5sum -c` verification byte-identical; fastq → `results/fastq/`, md5 → `results/fastq/md5/` (upstream publishDir patterns). Per-run row parsing replaces the Groovy channel `branch`; **no outputs declared** because the produced file set (single- vs paired-end, per-run names) is data-dependent — md5 verification in the command is the correctness gate (same as upstream). Runs without FTP links are skipped with a warning in the default config; with `sra_tools_fallback = true` they are handled by the per-run sratools fallback rules below (the upstream `branch` triage, ported as a when-gated branch — off by default so the default plan is unchanged). |
| FASTQDL (nf-core/fastqdl, added in 1.13.0) | `sra_fastq_fastqdl` | fastq-dl 4.0.1 (`community.wave.seqera.io/library/fastq-dl:4.0.1--fd5420f75c055a44`, the upstream pin) | When-gated on `download_method = "fastq-dl"` (new in 1.13.0, off by default — the default plan is unchanged). `fastq-dl --prefix <id> --accession <run> --cpus 2 --outdir .` — the upstream script with `task.ext.args` empty (no `withName` block adds args for this process) and the upstream 2-cpu label. Runs with neither FTP nor fasp link are triaged to the sratools fallback rules (upstream `branch`), which this method enables unconditionally. The tool's own `<run>[_1|_2].fastq.gz` outputs move to `results/fastq/`, the `<id>-run-info.tsv` (+ paired-run `<id>-run-mergers.tsv`, upstream `optional: true`) to `results/metadata/` (upstream publishDirs). Deviations: `retries = 1` (the module carries no `error_retry` label; the base config's `maxRetries = 1` on infra-status retries is the port-side equivalent), and upstream's `--cpus` follows the label's cpus; the tool's own checksum verification is the integrity gate (upstream adds no md5sum pass for this branch). |
| SRA_TO_SAMPLESHEET (1.12.0) → CHANNEL_SRA_CREATE_CSV (1.13.0, subworkflows/local/channel_sra_create_csv) | `sra_to_samplesheet` | python 3.9.5 | Ported 1:1 from the upstream logic — in 1.13.0 the Groovy moved from the SRA_TO_SAMPLESHEET `exec` block into the CHANNEL_SRA_CREATE_CSV subworkflow (`buildPipelineMap`): removed keys (`id`, `md5_1/2`, `single_end`, `fastq_1/2`), `sample` = `<id>` without its trailing `_<run>` segment, `fastq_1/2` = `<outdir>/fastq/<file>` named per the 1.13.0 `branch` arm the run is routed to (ftp/aspera `<id>[_1|_2].fastq.gz`; sratools `<id>.fastq[_1|_2].fastq.gz` — the `--outfile <id>.fastq` split-file names; fastq-dl `<run>[_1|_2].fastq.gz`), ENA columns appended, the `pipeline_extras` of `buildPipelineMap` (rnaseq→strandedness, atacseq→replicate=1, taxprofiler→fasta='', ampliseq→run='', mag→group='' / short_reads_platform='ILLUMINA' / long_reads_platform='', sarek→patient=sample_accession; metatdenovo/viralrecon add no columns) and the `--sample_mapping_fields` validation with upstream error text. `localrule`, 100 MB memory, `executor 'local'` mapped to `localrule = true`. Runs only when `skip_fastq_download` is false (upstream: channel empty when skipped). |
| `collectFile('samplesheet.csv')` | `combine_samplesheets` | system (bash + coreutils) | Gather via `expand_inputs` over `config.samples_list`; 1.13.0 CHANNEL_SRA_CREATE_CSV collects the per-run strings with `newLine: true, keepHeader: true, sort: true` — header kept once, value rows in lexicographic order (`LC_ALL=C sort`, identical for the ASCII rows); `results/samplesheet/samplesheet.csv`. |
| `collectFile('id_mappings.csv')` | `combine_mappings` | system (bash + coreutils) | Same gather + `sort: true` semantics; `results/samplesheet/id_mappings.csv`. |
| MULTIQC_MAPPINGS_CONFIG | `multiqc_mappings_config` | python 3.9.5 | `multiqc_mappings_config.py` byte-identical to the upstream bin script — adopted verbatim with the 1.13.0 change (proper `csv.reader` parsing of the mappings csv, newline-safe quoting). Output `results/samplesheet/multiqc_config.yml` (upstream publishDir). Gated on `sample_mapping_fields` being set — on by default, same as upstream (1.13.0 gates per-element via `ch_mappings.filter { sample_mapping_fields }`). |
| softwareVersionsToYAML + `versions.yml` | engine-native export: `oxo-flow report --versions-yml <file> main.oxoflow` | — | oxo-flow ≥ 0.17.0 exports an nf-core-style `versions.yml` derived statically from the workflow declarations: one entry per rule (17 rules) with the pinned container image (registry + tag), or a `system` entry with an explicit "no software versions declared" note for the host-tool gather rules. Deviation: it is a standalone CI-diff artifact, not a per-process runtime capture — upstream 1.13.0 emits per-process version tuples on the `versions` topic (the 1.12.0 per-process `versions.yml` heredocs are gone) and collects them via the nf-core-utils plugin's `softwareVersionsToYAML` + `collectFile` into `pipeline_info/nf_core_fetchngs_software_versions.yml` (1.13.0 renamed the file, dropping the stale `_mqc`); the export reflects the pinned versions in the definition (resolved runtime package versions depend on the execution environment). The topic/plugin machinery has no oxo-flow equivalent — the export serves the same purpose, and its file name matches the upstream collected name. Per-rule version emission inside every command is deliberately not replicated (it would change every rule's command while the default plan stays byte-identical). The collected file has no consumer in fetchngs itself (no MultiQC process; the mappings config targets downstream pipelines) — upstream ships it as boilerplate, here the export serves the same CI-diff purpose. |
| PIPELINE_COMPLETION (`workflow.onComplete`: completionEmail / completionSummary / sraCurateSamplesheetWarn; `workflow.onError` note — 1.13.0 removed the 1.12.0 `hook_url` / `imNotification` branch together with `assets/adaptivecard.json` + `assets/slackreport.json`) | `[workflow] on_complete` + `on_error` hooks (`scripts/pipeline_completion.sh`) | sendmail / mail (host tools) | Ported onto the engine's workflow-level terminal hooks (engine >= 0.17.0): `email` mails the run-summary on completion, `email_on_fail` after a failed run (falling back to `email`, like upstream). Both default empty (upstream's null params), so the hooks no-op; older engines ignore the `[workflow]` keys entirely, keeping the default plan unchanged. The upstream `workflow.onError` troubleshooting line (`Pipeline failed. Please refer to troubleshooting docs …`) is echoed by the script on the failed path. `completionSummary`'s stdout line is covered by the engine's own "Done: N succeeded..." line, and `sraCurateSamplesheetWarn` is a static log note (see Known limitations). Hooks are best-effort: a missing mail tool only warns and never changes the run status. |
| CUSTOM_SRATOOLSNCBISETTINGS + SRATOOLS_PREFETCH | `sra_prefetch` | sra-tools 3.2.1 (`quay.io/biocontainers/sra-tools:3.2.1--h4304569_1`, the upstream 1.13.0 pin) | When-gated branch, off by default (`download_method = "sratools"` + `dbgap_key` empty): per-run `prefetch` under the upstream `retry_with_backoff` policy (5 attempts / 1 s base / 100 s max, `scripts/retry_with_backoff.sh` verbatim — the helper body is byte-identical to the 1.13.0 template, which also echoes the effective retry policy + final prefetch args) + the 1.13.0 integrity gate: `vdb-validate <run>` on the per-run output directory (sra-tools 3.2.1 emits ETL directories — upstream `path("${id}", type: 'dir')` — the 1.12.0 `.sralite` branch is gone) and, when the archive carries no checksums, an md5 comparison against the NCBI locate endpoint (PR 305). Fresh NCBI settings file per id (upstream CUSTOM_SRATOOLSNCBISETTINGS GUID config). SRA records land in `results/sra/<id>/` (upstream publishDir `results/sra`, `enabled: false` — intermediates). Applies to **all** runs, matching upstream's explicit `--download_method sratools` mode; with `dbgap_key` set, the dbGaP variant below takes over. |
| SRATOOLS_FASTERQDUMP | `sra_fastq_sratools` | sra-tools 3.2.1 + pigz 2.8 (`community.wave.seqera.io/library/sra-tools_pigz:4a694d823f6f7fcf`, the upstream 1.13.0 Seqera Wave image — the 1.12.0 patched mulled image and its local sratools-fasterqdump.diff are gone) | When-gated on `download_method = "sratools"` (+ `dbgap_key` empty); depends on `sra_prefetch`. Consumes the per-run prefetch **directories** of sra-tools 3.2.1. `fasterq-dump --split-files --include-technical --threads --outfile <id>.fastq` + the 1.13.0 paired-run guard `mv <id>.fastq <id> || echo 'No third file'` (keeping the "third file" out of the `pigz *.fastq` glob; workaround for the '.'-in-path bug, ncbi/sra-tools#865) + `pigz --no-name --processes`, translated from the module. Files land in `results/fastq/`; paired runs now come out as `<id>.fastq_1.fastq.gz` / `<id>.fastq_2.fastq.gz` (the 1.12.0 module's `<id>_1/2.fastq.gz` names changed with the `--outfile <id>.fastq` adoption) — the samplesheet references the actual per-branch names (see `sra_to_samplesheet`). |
| Per-run sratools fallback (upstream FETCHNGS `branch`, runs without FTP/fasp links — for `download_method = "ftp"` / `"aspera"` gated on `sra_tools_fallback`, and unconditionally for `"fastq-dl"`) | `sra_prefetch_fallback` + `sra_fastq_sratools_fallback` | sra-tools 3.2.1 + the Wave sra-tools_pigz image (same images as above) | When-gated on `sra_tools_fallback = true` + `download_method = "ftp"` or `"aspera"` (off by default — the default plan is unchanged); for `download_method = "fastq-dl"` the two rules carry the upstream triage unconditionally (1.13.0 routes runs without download links to the sratools subworkflow for every method). Mirrors the sratools-method rules but processes only the runs upstream's `branch` sends to sra-tools: rows whose metadata has neither `fastq_1` nor `fastq_aspera` (branch condition `!meta.fastq_aspera && !meta.fastq_1`, re-derived from the runinfo tsv by `scripts/sra_prefetch_runs.sh` / `scripts/sra_fastq_sratools_runs.sh`). Prefetch + the 1.13.0 vdb-validate/md5-locate gate, then fasterq-dump (`--outfile <id>.fastq` + the paired-run guard) + pigz into `results/fastq/` with the per-branch naming so the samplesheet matches; the FTP rule keeps downloading the runs that do have links. Like upstream (which passes `params.dbgap_key` to the sratools subworkflow for every download method), a configured dbGaP certificate flows into the triage too — the public path (empty `dbgap_key`) is unchanged. |
| dbGaP (`--dbgap_key`) | `sra_prefetch_dbgap` + `sra_fastq_sratools_dbgap` | sra-tools 3.2.1 + the Wave sra-tools_pigz image (same images) | When-gated on `download_method = "sratools"` + `dbgap_key` set (off by default: `dbgap_key = ""`; the plain sratools rules are gated off in that case). The certificate is passed through verbatim like upstream: `.ngc` → `prefetch --ngc` / `fasterq-dump --ngc`, `.jwt` → `--perm` (SRATOOLS_PREFETCH cert_arg and SRATOOLS_FASTERQDUMP key_file logic, same rules for both tools); the 1.13.0 modules key the choice off `certificate.name`/`toString().endsWith`, same effect. Still requires the user's own NIH authorized-access credentials at runtime — the port itself needs nothing, and the public path (empty `dbgap_key`) is unchanged. |
| ASPERA_CLI (Aspera CLI 4.20.0, `fasp` links) | `sra_fastq_aspera` | aspera-cli 4.20.0 (`quay.io/biocontainers/aspera-cli:4.20.0--hdfd78af_0`, the upstream 1.13.0 image). BREAKING vs 1.12.0 (4.14.0): the image no longer bundles the `ascp` client — the upstream script header bootstraps it at runtime via `ascli conf ascp install` (idempotent; needs outbound internet on the compute node) and locates it via `find ${HOME}/.aspera/sdk`; and the download now authenticates with the RSA bypass key `assets/aspera_bypass_rsa.pem` (the upstream module asset, shipped byte-identical — the 1.12.0 in-image DSA key is deprecated) | When-gated on `download_method = "aspera"`: `"$ASCP" -QT -l 300m -P33001 -i "$BYPASS_KEY"` (upstream ext.args) against the `fastq_aspera` fasp links with user `era-fasp`, md5-verified like the FTP branch. No credentials needed — the anonymous ENA fasp endpoint is what upstream uses. Deviation: upstream also sends runs without fasp links to the ftp/sra-tools branches per run; that triage is ported as when-gated branches (`sra_fastq_ftp_aspera_fallback` + `sra_prefetch_fallback` / `sra_fastq_sratools_fallback`, all on `sra_tools_fallback = true`), so with the fallback off such runs are skipped with a warning. |
| Per-run FTP fallback for the aspera method (upstream FETCHNGS `branch`: with `download_method = "aspera"`, runs with an FTP link but no fasp link go to the FTP process) | `sra_fastq_ftp_aspera_fallback` | wget 1.25.0 (same Wave image as `sra_fastq_ftp`) | When-gated on `download_method = "aspera"` + `sra_tools_fallback = true` (off by default — the default plan is unchanged). `scripts/sra_fastq_ftp_aspera_runs.sh` carries the same wget `-t 5 -nv -w 5 --random-wait -c -T 60` download + md5 verification loop as the frozen `sra_fastq_ftp` command, applied to exactly the rows upstream's `branch` sends to the FTP arm: `fastq_1` set, `fastq_aspera` empty (branch condition `meta.fastq_1 && !meta.fastq_aspera`, re-derived from the runinfo tsv). Together with `sra_prefetch_fallback` / `sra_fastq_sratools_fallback` (same toggle) the runinfo tsv is fully partitioned — every run is downloaded exactly once by whichever branch upstream's `branch` would pick, with the FTP-branch naming so the samplesheet is method-agnostic. |
| `params.nf_core_pipeline` (1.13.0 schema enum: `ampliseq`/`atacseq`/`mag`/`metatdenovo`/`rnaseq`/`sarek`/`taxprofiler`/`viralrecon`) | `sra_to_samplesheet` | — | Off by default (empty), same as upstream; the `buildPipelineMap` column logic (see that row) is ported and activates when `nf_core_pipeline` is set. |
| publishDir / `--publish_dir_mode` | n/a | — | oxo-flow has no publishDir; outputs are declared directly at their `results/…` paths. |

Known limitations: the ids used for per-id expansion must be declared in the
sample source (`[[sample_groups]]`, or `--sample` on the CLI) and should match
`[config] input` validated by `check_ids`. The sra-tools, Aspera and fastq-dl
download methods are ported as when-gated branches (`download_method =
"sratools"` / `"aspera"` / `"fastq-dl"`); the upstream **per-run** triage is
ported as when-gated branches too, off by default (except for `fastq-dl`,
where upstream routes link-less runs to sra-tools unconditionally and the
two fallback rules run with the method) so the default plan is
byte-identical: `sra_tools_fallback = true` restores upstream's per-run
routing — with `ftp`, runs without FTP/fasp links go to prefetch/fasterq-dump;
with `aspera`, runs without a fasp link go to the FTP branch when they have an
FTP link (`sra_fastq_ftp_aspera_fallback`) and to prefetch/fasterq-dump
otherwise; with `fastq-dl`, runs without FTP/fasp links always go to
prefetch/fasterq-dump — and `dbgap_key` enables the dbGaP certificate path of
the sratools branch and the triage (the certificate is passed through
verbatim; the port itself needs no credentials). Remaining deviations: with
`ftp` or `aspera` and the fallback off, runs whose metadata lacks the
matching download links are skipped with a warning (upstream would route
them per run; enable `sra_tools_fallback` to restore the triage), and the
`aspera` branch needs outbound internet on the compute nodes at runtime
(runtime `ascli conf ascp install` download of the ascp client) — isolated
HPC clusters without direct egress should use `ftp`, `sratools` or
`fastq-dl`. The sratools-branch paired-end file names changed with 1.13.0
(`<id>.fastq_1.fastq.gz` / `<id>.fastq_2.fastq.gz`, driven by the
`--outfile <id>.fastq` adoption) and the samplesheet references the actual
per-branch names. The auto-created samplesheet should be double-checked
before downstream use (the upstream `sraCurateSamplesheetWarn` end-of-run
note): public databases don't reliably hold information such as strandedness
or controls, and all sample metadata from the ENA is appended as additional
columns to help manual curation. The nf-core boilerplate (`versions.yml`
collection) is covered by the engine-native export
(`oxo-flow report --versions-yml <file> main.oxoflow`, see table).

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
