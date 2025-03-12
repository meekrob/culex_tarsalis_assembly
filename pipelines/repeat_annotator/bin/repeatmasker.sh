#!/bin/bash


#SBATCH --partition=short-cpu
#SBATCH --time=24:00:00
#SBATCH --nodes=1
#SBATCH --cpus-per-task=16
#SBATCH --mem=100GG
#SBATCH --job-name=repeatmasker


# activate conda env
source ~/.bashrc
conda activate repeatmasker



# run repeatmasker
RepeatMasker -s -lib -uncurated mosquito_repeat_lib.fasta $1 -pa 4 -dir .