#!/usr/bin/env bash
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --time=00:10:00
#SBATCH --job-name=compile_fastp_jsons
#SBATCH --partition=short-cpu
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

dir_with_jsons=trimming
cmd="python ../bin/fastp_output_parser.py $dir_with_jsons" # creates fastp_reports.csv
echo $cmd
time eval $cmd
