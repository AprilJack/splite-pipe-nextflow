#!/usr/bin/env nextflow
/*
 * ============================================================================
 *  Parse Biosciences split-pipe workflow
 * ============================================================================
 *  1. SPLIT_PIPE : runs `split-pipe --mode all` once per sublibrary (in parallel)
 *  2. COMBINE    : runs `split-pipe --mode comb` once ALL sublibraries finish
 *
 *  You should not need to edit this file. Every setting lives in
 *  nextflow.config and can be overridden with:
 *     - the command line      e.g.  --outdir /path/to/result --split_cpus 32
 *     - a params file         e.g.  -params-file my_run.yaml
 *
 *  Run `nextflow run main.nf --help` for the list of options.
 * ============================================================================
 */

/* ---------------------------------------------------------------------------
 *  Helper functions
 * ------------------------------------------------------------------------- */

def helpMessage() {
    return """
    Parse split-pipe Nextflow workflow
    ==================================
    Usage:
      nextflow run main.nf [-profile slurm] [-params-file run.yaml] [--option value ...]

    Input (choose one):
      --fqfiles <glob>          Glob for paired FASTQs, e.g. '/data/*_S*_{R1,R2}.fastq.gz'
      --input <csv>             Samplesheet: sublibrary,fastq_1,fastq_2[,sample_list]

    Required references:
      --genome_dir <dir>        split-pipe genome index directory
      --sample_list <file>      split-pipe sample list (sample name + wells)

    Output:
      --outdir <dir>            Results directory (one sub-folder per sublibrary)
      --combined_dir <dir>      Combined results directory (default: <outdir>/combined)

    Sublibrary naming (only used with --fqfiles):
      --sublib_regex <regex>    Regex applied to the FASTQ pair id; group 1 is kept
                                (default '^[^_]+_([^_]+)' -> 2nd '_' field, e.g. S1)
      --sublib_prefix <str>     Prefix added to the name (default 'sub_' -> sub_S1)

    split-pipe options:
      --split_pipe_bin <cmd>    split-pipe executable (default 'split-pipe')
      --mode <mode>             split-pipe mode for each sublibrary (default 'all')
      --chemistry <v1|v2|v3>    Kit chemistry
      --kit <WT|WT_mini|...>    Kit type
      --kit_score_skip          Pass --kit_score_skip (true/false)
      --start_timeout <int>     Pass --start_timeout (set to null to omit)
      --dryrun                  Pass --dryrun to split-pipe
      --split_extra_args <str>  Any other split-pipe arguments for each sublibrary
      --combine_extra_args <str> Any other split-pipe arguments for the combine step

    Combine step:
      --skip_combine            Do not run the combine step
      --combine_only            Only run the combine step on existing sublibraries
      --sublib_list <file>      Sublibrary directories to combine (used with --combine_only)

    Resources:
      --split_cpus / --split_memory / --split_time       per-sublibrary job
      --combine_cpus / --combine_memory / --combine_time combine job
      --max_parallel <int>      Max sublibraries run at the same time (0 = no limit)
      --queue / --cluster_options                        used by -profile slurm
    """.stripIndent()
}

// Absolute path helper: relative paths are resolved against the launch directory
def absPath(p) {
    return file(p.toString()).toAbsolutePath().normalize().toString()
}

// Derive a sublibrary name (e.g. "sub_S1") from a FASTQ pair id
def sublibName(String pairId) {
    def matcher = java.util.regex.Pattern.compile(params.sublib_regex.toString()).matcher(pairId)
    def core = pairId
    if (matcher.find()) {
        core = matcher.groupCount() > 0 ? matcher.group(1) : matcher.group(0)
    } else {
        log.warn("sublib_regex '${params.sublib_regex}' did not match '${pairId}'; using the full id")
    }
    return "${params.sublib_prefix ?: ''}${core}".toString()
}

def checkExists(name, value, boolean isDir) {
    if (!value) {
        error("Missing required parameter --${name}. Set it in nextflow.config, a params file, or on the command line.")
    }
    def f = file(value.toString())
    if (!f.exists()) {
        error("--${name} does not exist: ${value}")
    }
    if (isDir && !f.isDirectory()) {
        error("--${name} must be a directory: ${value}")
    }
}

def validateParams() {
    if (!params.outdir) {
        error("Missing required parameter --outdir")
    }
    if (params.combine_only) {
        checkExists('sublib_list', params.sublib_list, false)
        return
    }
    if (!params.input && !params.fqfiles) {
        error("Provide either --fqfiles (FASTQ glob) or --input (samplesheet CSV)")
    }
    checkExists('genome_dir', params.genome_dir, true)
    checkExists('sample_list', params.sample_list, false)
}

def logSummary(String outdir, String combinedDir) {
    def lines = [
        "split-pipe workflow",
        "  launch dir     : ${workflow.launchDir}",
        "  profile        : ${workflow.profile}",
        "  input          : ${params.input ?: params.fqfiles}",
        "  genome_dir     : ${params.genome_dir}",
        "  sample_list    : ${params.sample_list}",
        "  outdir         : ${outdir}",
        "  combined_dir   : ${params.skip_combine ? '(skipped)' : combinedDir}",
        "  chemistry/kit  : ${params.chemistry} / ${params.kit}",
        "  split cpus     : ${params.split_cpus}",
        "  combine_only   : ${params.combine_only}",
        "  dryrun         : ${params.dryrun}",
    ]
    log.info(lines.join('\n'))
}

// Read pairs from a glob -> [sublib, fq1, fq2, sample_list]
def readsFromGlob() {
    return channel
        .fromFilePairs(params.fqfiles.toString(), checkIfExists: true)
        .ifEmpty { error("Cannot find any FASTQ pairs matching: ${params.fqfiles}") }
        .map { pairId, fqs ->
            if (fqs.size() != 2) {
                error("Expected 2 FASTQs for '${pairId}' but found ${fqs.size()}: ${fqs}")
            }
            tuple(sublibName(pairId), fqs[0], fqs[1], absPath(params.sample_list))
        }
}

// Read pairs from a samplesheet CSV -> [sublib, fq1, fq2, sample_list]
def readsFromSamplesheet() {
    return channel
        .fromPath(params.input.toString(), checkIfExists: true)
        .splitCsv(header: true, strip: true)
        .map { row ->
            if (!row.sublibrary || !row.fastq_1 || !row.fastq_2) {
                error("Samplesheet rows need 'sublibrary', 'fastq_1' and 'fastq_2' columns. Bad row: ${row}")
            }
            def sampList = row.sample_list ? absPath(row.sample_list) : absPath(params.sample_list)
            if (!file(sampList).exists()) {
                error("sample_list for ${row.sublibrary} does not exist: ${sampList}")
            }
            tuple(
                row.sublibrary.toString(),
                file(row.fastq_1, checkIfExists: true),
                file(row.fastq_2, checkIfExists: true),
                sampList
            )
        }
}


/* ---------------------------------------------------------------------------
 *  Processes
 * ------------------------------------------------------------------------- */

process SPLIT_PIPE {
    tag "${sublib}"

    input:
    tuple val(sublib), val(sublib_dir), val(samp_list), val(genome_dir), path(fq1), path(fq2)

    output:
    val(sublib_dir), emit: sublib_dir

    script:
    // Optional flags are only added when set, so the command stays clean
    def args = [
        "--mode ${params.mode}",
        params.chemistry      ? "--chemistry ${params.chemistry}"         : null,
        params.kit            ? "--kit ${params.kit}"                     : null,
        params.kit_score_skip ? '--kit_score_skip'                        : null,
        "--fq1 ${fq1}",
        "--fq2 ${fq2}",
        "--output_dir '${sublib_dir}'",
        "--genome_dir '${genome_dir}'",
        "--samp_list '${samp_list}'",
        "--nthreads ${task.cpus}",
        params.start_timeout  ? "--start_timeout ${params.start_timeout}" : null,
        params.dryrun         ? '--dryrun'                                : null,
        params.split_extra_args ?: null,
    ].findAll { a -> a }.join(' \\\n        ')
    """
    mkdir -p '${sublib_dir}'

    ${params.split_pipe_bin} \\
        ${args}
    """
}

process COMBINE {
    tag "${sublib_dirs.size()} sublibraries"

    input:
    val(sublib_dirs)
    val(combined_dir)

    output:
    val(combined_dir), emit: combined_dir
    path('sublibraries.txt'), emit: sublib_list

    script:
    def dirs = sublib_dirs.collect { d -> "'${d}'" }.join(' ')
    def args = [
        '--mode comb',
        '--sublib_list sublibraries.txt',
        "--output_dir '${combined_dir}'",
        params.combine_extra_args ?: null,
    ].findAll { a -> a }.join(' \\\n        ')
    """
    printf '%s\\n' ${dirs} > sublibraries.txt

    # Fail early if any sublibrary directory is missing
    while read -r d; do
        [ -d "\$d" ] || { echo "Missing sublibrary directory: \$d" >&2; exit 1; }
    done < sublibraries.txt

    mkdir -p '${combined_dir}'
    cp sublibraries.txt '${combined_dir}/sublibraries.txt'

    ${params.split_pipe_bin} \\
        ${args}
    """
}


/* ---------------------------------------------------------------------------
 *  Workflow
 * ------------------------------------------------------------------------- */

workflow {
    main:
    if (params.help) {
        log.info(helpMessage())
    }
    else {
        validateParams()

        def outdir      = absPath(params.outdir)
        def combinedDir = params.combined_dir ? absPath(params.combined_dir) : "${outdir}/combined".toString()
        logSummary(outdir, combinedDir)

        if (params.combine_only) {
            // Combine sublibraries that were processed earlier
            def dirs = file(params.sublib_list.toString())
                .readLines()
                .collect { line -> line.trim() }
                .findAll { line -> line && !line.startsWith('#') }
                .collect { line -> absPath(line) }
            if (dirs.isEmpty()) {
                error("No sublibrary directories listed in ${params.sublib_list}")
            }
            COMBINE(channel.value(dirs), combinedDir)
        }
        else {
            def reads = params.input ? readsFromSamplesheet() : readsFromGlob()

            // Check sublibrary names are unique, then add the output directory
            def jobs = reads
                .toList()
                .flatMap { rows ->
                    def names = rows.collect { r -> r[0] }
                    def dups  = names.findAll { n -> names.count(n) > 1 }.unique()
                    if (dups) {
                        error("Duplicate sublibrary names ${dups}. Adjust --sublib_regex or the samplesheet.")
                    }
                    log.info("Found ${rows.size()} sublibraries: ${names.sort().join(', ')}")
                    rows
                }
                .map { sublib, fq1, fq2, sampList ->
                    tuple(sublib, "${outdir}/${sublib}".toString(), sampList, absPath(params.genome_dir), fq1, fq2)
                }

            SPLIT_PIPE(jobs)

            if (!params.skip_combine) {
                // .collect() waits until EVERY sublibrary has finished
                def allDone = SPLIT_PIPE.out.sublib_dir
                    .collect()
                    .map { dirs -> dirs.sort() }
                    .filter { dirs ->
                        if (dirs.size() < 2) {
                            log.warn("Only ${dirs.size()} sublibrary processed; skipping combine step")
                        }
                        dirs.size() >= 2
                    }
                COMBINE(allDone, combinedDir)
            }
        }
    }
}
