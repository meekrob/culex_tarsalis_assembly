This pipeline will handle the annotation of the genome data, using the rna sequencing data as support. 

Two ideas: 

1. MAKER 



2. BRAKER


### Braker3 requirments

** there is a singularity container that we can use which might be the best

# 
create conda env, install singularity if not already installed, and build the container



```
mkdir tmp #make a tmp dir 

export SINGULARITY_TMPDIR=/path/to/tmp # set singularity tmp dir

singularity build braker3.sif docker://teambraker/braker3:latest # build the singularity container
```
# should now have a .sif file and we can remove the tmp dir



