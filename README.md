Getting Parse pipeline started	

## Demultiplexing Parse-seq split-seq data

Parse-seq data is demultiplexed using BCL2fastq first to the sub-library level. Samples are demultiplexed from sub libraries using the split-pipe pipeline. 

```
#demultiplexing Parse-seq data
bcl2fastq -r 6 -p 16 -w 6 -R /vast/igc/illumina/runfolders/NovaSeq/230131_A01960_0058_AH2WH5DRX3/ -p 32 --sample-sheet /vast/igc/illumina/runfolders/NovaSeq/230131_A01960_0058_AH2WH5DRX3/SampleSheet_Novaseq.csv --output-dir /vast/igc/illumina/fastq/230131_Parse --no-lane-splitting 2> $dir/log.txt
```
Set-up split-pipe environment
```
conda activate spipe
PATH=/gpfs/tools/anaconda/envs/spipe/bin:$PATH
```

Here's the link to the GTF formatting guidelines article (please make sure you're logged in or the article won't appear): https://support.parsebiosciences.com/hc/en-us/articles/11606689895828-GTF-Formatting-Guidelines
### Making reference for mm39 

```
wget https://ftp.ensembl.org/pub/release-108/fasta/mus_musculus/dna/Mus_musculus.GRCm39.dna.primary_assembly.fa.gz;
wget https://ftp.ensembl.org/pub/release-108/gtf/mus_musculus/Mus_musculus.GRCm39.108.gtf.gz;

#make mm39 genome
split-pipe \
--mode mkref \
--genome_name mm39 \
--fasta /vast/igc/data/genomes/parse_genomes/mm39/Mus_musculus.GRCm39.dna.primary_assembly.fa.gz \
--genes /vast/igc/data/genomes/parse_genomes/mm39/Mus_musculus.GRCm39.108.gtf.gz \
--output_dir /vast/igc/data/genomes/parse_genomes/mm39
```
### Making reference for calJac4 from UCSC

```
cd /vast/igc/data/genomes/calJac4.Callithrix_jacchus_cj1700_1.1
# Swap CDS for gene
sed "s/\tCDS\t/\tgene\t/g" ncbiRefSeq.gtf > calJac_gene.gtf

# append "gene_biotype "protein coding" to all lines
awk '{print $0, "gene_biotype \"protein_coding\";"}' calJac_gene.gtf > calJac_mod.gtf
```
### General Pipeline

1. Multi-species runs must first be split by species or alignment statistics will be affected. Using the Nextflow pipeline or scripts found in `split-fastqs`
2. After splitting both species should be aligned separately using pipeline found in `run-split-pipe`


### Running without Nextflow

```
conda activate spipe
PATH=/gpfs/tools/anaconda/envs/spipe/bin:$PATH

split-pipe \
--mode mkref \
--genome_name calJac4 \
--output_dir "/vast/igc/data/genomes/calJac4.Callithrix_jacchus_cj1700_1.1" \
--genes "/vast/igc/data/genomes/calJac4.Callithrix_jacchus_cj1700_1.1/calJac_mod.gtf.gz" \
--fasta "/vast/igc/data/genomes/calJac4.Callithrix_jacchus_cj1700_1.1/calJac4.fa.gz"

```


