# run-split-pipe (Nextflow)

Runs Parse Biosciences `split-pipe` on every sublibrary in parallel, then runs
`split-pipe --mode comb` automatically once **all** sublibraries have finished.

```
FASTQ pairs ──► SPLIT_PIPE (sub_S1) ──┐
            ──► SPLIT_PIPE (sub_S2) ──┤
            ──► ...                   ├──► COMBINE  ──► <outdir>/combined
            ──► SPLIT_PIPE (sub_S8) ──┘
```

`main.nf` never needs to be edited. All settings live in `nextflow.config`.

## Quick start

1. Edit the `params { ... }` block in `nextflow.config` (input FASTQs, genome,
   sample list, output folder, chemistry/kit), **or** copy
   `params.example.yaml` to a per-project file and edit that instead.
2. Run:

```bash
# using the values in nextflow.config
nextflow run main.nf

# using a per-project params file (keeps nextflow.config untouched)
nextflow run main.nf -params-file my_project.yaml

# override anything on the command line
nextflow run main.nf --outdir /vast/.../result --split_cpus 32

# resume after a failure (finished sublibraries are skipped)
nextflow run main.nf -resume

# list all options
nextflow run main.nf --help
```

## Inputs

**Option A: FASTQ glob** (`fqfiles`). `{R1,R2}` marks the read pair. The
sublibrary name comes from the pair id using `sublib_regex` (capture group 1)
plus `sublib_prefix`. With the defaults, the second `_`-separated field is
used: `120423Parse1_S1_group_mm_R1.fastq.gz` becomes `sub_S1`. This matches the
original pipeline's naming.

**Option B: samplesheet** (`input`). A CSV that names each sublibrary
explicitly. It takes priority over `fqfiles`. The optional `sample_list`
column lets a sublibrary use its own sample list. See `samplesheet.example.csv`.

```csv
sublibrary,fastq_1,fastq_2,sample_list
sub_S1,/path/S1_R1.fastq.gz,/path/S1_R2.fastq.gz,
sub_S2,/path/S2_R1.fastq.gz,/path/S2_R2.fastq.gz,/path/other_sample_list.txt
```

## Main parameters

| Parameter | Default | Purpose |
|---|---|---|
| `fqfiles` / `input` | (see config) | FASTQ glob or samplesheet CSV |
| `genome_dir` | mm39 path | split-pipe genome index |
| `sample_list` | (see config) | split-pipe `--samp_list` |
| `outdir` | (see config) | one folder per sublibrary |
| `combined_dir` | `<outdir>/combined` | combine output |
| `split_pipe_bin` | `split-pipe` | executable name or full path |
| `mode` | `all` | split-pipe mode for each sublibrary |
| `chemistry` / `kit` | `v2` / `WT` | kit settings |
| `kit_score_skip` | `true` | adds `--kit_score_skip` |
| `start_timeout` | `120` | `null` leaves the flag out |
| `dryrun` | `false` | adds `--dryrun` |
| `split_extra_args` | `''` | any other split-pipe flags (per sublibrary) |
| `combine_extra_args` | `''` | any other flags for the combine step |
| `skip_combine` | `false` | process sublibraries only |
| `combine_only` + `sublib_list` | `false` / `null` | combine existing sublibraries only |
| `max_cpus` / `max_memory` | `64` / `480 GB` | what Nextflow may use on the server |
| `split_cpus` / `split_memory` | `64` / – | per-sublibrary resources |
| `combine_cpus` / `combine_memory` | `16` / – | combine resources |
| `max_parallel` | `0` (no limit) | extra cap on sublibraries at once |
| `conda_env` | – | used with `-profile conda` |

Any flag without its own parameter can go in `split_extra_args`, for example
`--split_extra_args "--samp_sltwell /path/wells.xlsx"`.

## Running on the server (64 CPUs / 500 GB RAM)

Everything runs locally on the server; no job scheduler is needed. Nextflow
only starts as many sublibraries as fit within `max_cpus` and `max_memory`:

| Setting | Effect |
|---|---|
| `--split_cpus 64` (default) | one sublibrary at a time, all 64 threads |
| `--split_cpus 32` | two sublibraries at a time, 32 threads each |
| `--split_cpus 32 --split_memory '220 GB'` | two at a time, and Nextflow checks RAM too |

Because a run can take many hours, start it inside `screen` or `tmux` (or
with `nohup ... &`) so it keeps going if your SSH session disconnects:

```bash
tmux new -s splitpipe
nextflow run main.nf -params-file my_project.yaml
# detach with Ctrl-b d; reattach later with: tmux attach -t splitpipe
```

## Combine step

After every sublibrary finishes, the workflow writes the list of sublibrary
folders to `<combined_dir>/sublibraries.txt` and runs:

```
split-pipe --mode comb --sublib_list sublibraries.txt --output_dir <combined_dir>
```

It is skipped when only one sublibrary was processed. To combine sublibraries
that were processed earlier (this replaces `combine.sh`):

```bash
nextflow run main.nf --combine_only --sublib_list sublibraries.txt
```

## Outputs

```
<outdir>/
├── sub_S1/ ... sub_S8/      split-pipe results per sublibrary
├── combined/                combined results + sublibraries.txt
└── pipeline_info/           Nextflow trace, report and timeline
```

Note: split-pipe writes straight into `<outdir>`, not the Nextflow `work/`
folder, so these large files are not copied. `-resume` decides what to skip
from Nextflow's cache. If you delete a sublibrary folder, re-run without
`-resume`, or delete that task's `work/` folder.
