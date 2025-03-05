#!/usr/bin/env bash
#SBATCH --nodes=1
#SBATCH --ntasks=24
#SBATCH --time=01:00:00
#SBATCH --job-name=bsco-txome
#SBATCH --partition=short-cpu
#SBATCH --output=%x.%j.log # gives slurm.ID.log
# Available partitions
# day-long-cpu
# day-long-gpu
# day-long-highmem
# exp-gpu
# short-cpu*
# short-gpu
# short-highmem
# week-long-cpu
# week-long-gpu
# week-long-highmem
export NUMEXPR_MAX_THREADS=$SLURM_NTASKS
BUSCO_DOWNLOADS=/nfs/home/dking/busco_downloads
TX_FASTA=$1
OUT=${TX_FASTA}_busco.out

echo "[$0] $SLURM_JOB_NAME $@" # log the command line
cmd="source /nfs/home/dking/miniconda3/bin/activate busco"
echo $cmd
eval $cmd

cmd="busco -i $TX_FASTA --download_path $BUSCO_DOWNLOADS --lineage_dataset diptera_odb10 --mode transcriptome --cpu $SLURM_NTASKS --out $OUT"
echo $cmd
time eval $cmd
