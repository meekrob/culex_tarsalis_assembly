#!/usr/bin/env bash
#SBATCH --nodes=1
#SBATCH --ntasks=32
#SBATCH --time=7-00:00:00
#SBATCH --job-name=rnaspades
#SBATCH --partition=week-long-highmem
#SBATCH --output=%x.%j.log # gives jobname.ID.log
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
datetime=$(date +"%Y-%m-%d_%H:%M:%S")
echo "[$datetime] $SLURM_JOB_NAME $@" # log the command line
cmd="source /nfs/home/dking/miniconda3/bin/activate spades"
echo $cmd
eval $cmd

left=$1
right=$2
out=$3
shift 3
other_opts="$@"

mkdir -p $out

mkdir -p $HOME/tmp
export TMP=$HOME/tmp
export TMPDIR=$TMP

cmd="rnaspades.py -t $SLURM_NTASKS -1 $left -2 $right -o $out $other_opts" 
echo $cmd
time eval $cmd

#### run BUSCO
export NUMEXPR_MAX_THREADS=$SLURM_NTASKS
BUSCO_DOWNLOADS=/nfs/home/dking/busco_downloads
TX_FASTA=$out/transcripts.fasta
TX_FASTA_ALIAS=$out/${out}_transcripts.fasta
OUT=${TX_FASTA}_busco.out

# how many transcripts did it assemble?
echo "${TX_FASTA} contains $(grep -c '^>' ${TX_FASTA}) transcripts."
# make an alias/bkup of the transcripts file with a meaningful name
ln -v ${TX_FASTA} ${TX_FASTA_ALIAS}


cmd="source /nfs/home/dking/miniconda3/bin/activate busco"
echo $cmd
eval $cmd

cmd="busco -i $TX_FASTA --download_path $BUSCO_DOWNLOADS --lineage_dataset diptera_odb10 --mode transcriptome --cpu $SLURM_NTASKS --out $OUT"
echo $cmd
time eval $cmd
