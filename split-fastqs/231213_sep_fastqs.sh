#!/bin/bash

SCRIPTPATH="/gpfs/tools/scripts/fastq_sep_groups.py"
FQ_DIR="/vast/igc/analyses/april/KUO-FEN/evan/231213_UCSD/fastqs/"

for i in 1 2 3 4 5 6 7 8; do
 python $SCRIPTPATH \
     --kit WT_mega \
     --kit_score_skip \
     --fq1 ${FQ_DIR}120423Parse${i}_S${i}_R1_001.fastq.gz\
     --fq2 ${FQ_DIR}120423Parse${i}_S${i}_R2_001.fastq.gz \
     --opath ${FQ_DIR}split-fq \
     --group cj A1-B4 \
     --group mm B5-D12
done
