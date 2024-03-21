#!/usr/bin/env nextflow

params.cpus = 64

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
    IFS='_' read -r _ N  _ <<< !{sample_id}
    sublibrary=sub_$N
    output_dir=!{params.outdir}/$sublibrary

    # Make sublibrary directory if it does not exist
    [ -d $output_dir ] || mkdir -p $output_dir

    split-pipe \
        --mode all \
        --chemistry v2 \
        --kit WT \
        --kit_score_skip \
        --fq1 !{fqs[0]} \
        --fq2 !{fqs[1]} \
        --output_dir $output_dir \
        --genome_dir  !{params.genome_dir} \
        --samp_list !{params.sample_list} \
        --nthreads !{params.cpus} \
	--start_timeout 120
        #--dryrun
    '''
}

workflow {
   fq_ch | split_pipe
}
