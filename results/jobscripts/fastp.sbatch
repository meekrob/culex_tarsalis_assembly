#!/bin/bash
#SBATCH --partition=day-long-cpu
#SBATCH --job-name=fastpArray
#SBATCH --output=%x.%j.out
#SBATCH --time=1:00:00
#SBATCH --qos=normal
#SBATCH --nodes=1
#SBATCH --ntasks=17
#SBATCH --mail-type=ALL
#SBATCH --mail-user=$USER
datetime=$(date +"%Y-%m-%d_%H:%M:%S")
echo "[$datetime] $SLURM_JOB_NAME $@" # log the command line

module purge
#source activate base
#conda activate rnaPseudo
source $HOME/miniconda3/bin/activate cutrun

mkdir -vp trimmed htmls

r1_array=()
for FILE in $@
do
    R1=$FILE
    R2=${R1/R1/R2}
    R2=${R1/_1/_2}
    if [[ $R2 == $FILE ]]
    then
        # skip this file if the substitution didn't work. 
        # this will automatically skip R2 files (we assume they're in the directory and automatically interpolated)
        echo 1>&2 "Error substituting R2 pattern for R1 for ${FILE}. Check filenames to see if the patterns are correct." 
        continue
    fi
    r1_array+=($R1)
done


# if in array job, do the one only
if [ -n "$SLURM_ARRAY_JOB_ID" ]
then
    r1_array=${r1_array[$SLURM_ARRAY_JOB_ID]}
fi
