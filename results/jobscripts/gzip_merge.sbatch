#!/usr/bin/env bash
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --time=06:00:00
#SBATCH --job-name=gzip-merge
#SBATCH --partition=day-long-cpu
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

mkdir -p $HOME/tmp
export TMP=$HOME/tmp
export TMPDIR=$TMP

outfile=$1
shift
infiles="$@"

ls -lHh $infiles 

#cmd="zcat $infiles | gzip -c - > $outfile"
cmd="cat $infiles > $outfile" # thanks to Jacob Lamb for noticing this capability
echo $cmd
time eval $cmd

ls -lHh $infiles $outfile
