#!/bin/bash
#SBATCH --partition=day-long-cpu
#SBATCH --job-name=fastpLoop
#SBATCH --output=%x.%A_%a.log # like: jobname-job.ID_1.log
#SBATCH --time=0:10:00
#SBATCH --qos=normal
#SBATCH --nodes=1
#SBATCH --ntasks=17
#SBATCH --mail-type=ALL
#SBATCH --mail-user=$USER

module purge
#source activate base
#conda activate rnaPseudo
source $HOME/miniconda3/bin/activate cutrun

mkdir -vp trimmed htmls


# array context
if [ -n "$SLURM_ARRAY_TASK_ID" ]
then
    cmd_line=( $@ )
    in_args=${cmd_line[$SLURM_ARRAY_TASK_ID]}
else
    in_args="$@"
fi

for FILE in $in_args
do
  echo $FILE
  #TWO=$(echo $FILE | rev | sed s/./2/14 | rev) #Read in R1 file, reverse it, replace the 12th character with a 2, and reverse for R2
  #TWO=${FILE/_1/_2}
  TWO=${FILE/R1/R2}
  BASE=${FILE/R1/}
  TRIM1="trimmed/trimmed."$(basename $FILE)
  TRIM2="trimmed/trimmed."$(basename $TWO)

  if false
  then
      # for merging of read pairs
      merged_out="trimmed/merged.$(basename $BASE)"
      unpaired1="trimmed/unpaired1.$(basename $BASE)"
      unpaired2="trimmed/unpaired2.$(basename $BASE)"
      out1="trimmed/out1.$(basename $BASE)"
      out2="trimmed/out2.$(basename $BASE)"
      merge_args="-m --merged_out $merged_out --out1 $out1 --out2 $out2 --unpaired1 $unpaired1 --unpaired2 $unpaired2 "
  fi

  # fastp uses 16 threads maximum (version 0.23.4)
  cmd="fastp -i ${FILE} -I ${TWO} \
             -o ${TRIM1} -O ${TRIM2} \
             $merge_args \
             -h htmls/$(basename $TWO).html -j htmls/$(basename $TWO).json \
             -w $((SLURM_NTASKS-1)) --dedup "
  echo $cmd
  time eval $cmd
done
