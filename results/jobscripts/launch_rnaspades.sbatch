#!/usr/bin/env bash
# launch a script through sbatch
# launch_script sbatch_args - script_args
SCRIPT=/nfs/home/dking/jobscripts/rnaspades.sbatch
sbatch_args=""

while [ "$1" != "-" ]
do
    args="$args $1"
    shift

    if [ "$1" = "-" ] || [ -z "$@" ]
    then 
        break
    fi
done

# did we hit "-" ? 
if [ "$1" == "-" ]
then
    sbatch_args="$args"
    shift
    args="$@"
fi

SUBMIT="sbatch $sbatch_args $SCRIPT $args"
echo $SUBMIT 1>&2;
