
# base                  *  /nfs/home/dking/miniconda3
# busco                    /nfs/home/dking/miniconda3/envs/busco
# cutrun                   /nfs/home/dking/miniconda3/envs/cutrun
# fastp                    /nfs/home/dking/miniconda3/envs/fastp
# rnaPseudo                /nfs/home/dking/miniconda3/envs/rnaPseudo
# rstudio                  /nfs/home/dking/miniconda3/envs/rstudio
# samtools                 /nfs/home/dking/miniconda3/envs/samtools
# spades                   /nfs/home/dking/miniconda3/envs/spades
# sratoolkit               /nfs/home/dking/miniconda3/envs/sratoolkit

env_list="busco fastp rnaPseudo spades"

for env in $env_list
do
    echo "$env"
    cmd="conda list -n $env --explicit > $env.explicit.txt"
    echo $cmd
    eval $cmd
    cmd="conda env export -n $env > $env.export.yml"
    echo $cmd
    eval $cmd
    cmd="conda env export -n $env --from-history > $env.export-from-history.yml"
    echo $cmd
    eval $cmd
done
