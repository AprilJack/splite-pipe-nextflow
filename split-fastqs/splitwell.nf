#!/usr/bin/env nextflow

params.cpus = 4

channel
    .fromFilePairs(params.fqfiles)
    .ifEmpty { error "Cannot find ${params.fqfiles}" }
    .set { fq_ch }

process split_pipe {
    cpus params.cpus 

    input:
    tuple val(sample_id), path(fqs)

    shell:
    '''
    SCRIPTPATH="/gpfs/tools/scripts/fastq_sep_groups.py"
    
    python $SCRIPTPATH \
        --kit WT_mega \
        --kit_score_skip \
        --fq1 !{fqs[0]} \
        --fq2 !{fqs[1]} \
        --opath !{params.outdir} \
        --group cj A1-B4 \
        --group mm B5-D12

    '''
}

workflow {
   fq_ch | split_pipe
}
