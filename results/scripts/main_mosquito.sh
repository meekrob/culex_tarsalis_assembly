#! /bin/bash

# slurm parameters, see config/parameters.txt



#variables 


ref_transcriptome =/input/mosquito_transcriptome.fasta




# Ideas #

# This script will act as the head worker, pairing up files and submitting jobs and managing dependencies. 
# This script should automattically check for output files and skip steps if they already exist. 
# Echoing logging and errors are important so that user can know if jobs were successfully submitted or not. 





# 01_trimming.sh should we submitted for every pair of rna files 
# 02_merge.sh is a dependency of 01_trimming.sh and requires the output of 01_trimming.sh. It should be run once all trimming jobs are copmlete. 
# 03_assembly.sh is a dependency of 02_merge.sh and requires the output of 02_merge.sh. It should be run once merging is complete. 
# 04_busco.sh and 04_rnaquast.sh are dependencies of 03_assembly.sh and require the output of 03_assembly.sh. They should be each be run at the same time. 
# 05_annotation.sh is a dependency of 04_busco.sh and 04_rnaquast.sh and requires the output of both. It should be run once both busco and rnaquast are complete. 
