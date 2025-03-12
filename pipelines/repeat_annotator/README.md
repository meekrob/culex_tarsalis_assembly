This simple pipeline will run repeatmasker on the draft genome

conda env: repeatmasker which is stored here ~/pipelines/repeat_annotator/config/environment.yml




steps to run this pipeline

create conda environment. 
```
conda create -f ~/pipelines/repeat_annotator/config/environment.yml > repeatmasker
```

download the relevant dfam database
```
wget https://www.dfam.org/releases/current/families/FamDB/dfam39_full.14.h5.gz 
```

gunzip the download
```
gunzip dfam39_full.14.h5.gz
```

clone the FamDB repo
```
git clone git@github.com:Dfam-consortium/FamDB.git
```

make repeat.hmm usable:
```
./FamyDB/famdb.py -i dfam39_full.14.h5.gz fasta > mosquito_repeat_lib.fasta
```

run the script for repeatmasker

```
RepeatMasker -s -lib -uncurated mosquito_repeat_lib.fasta $1 -pa 4 -dir .
```



#comands i need to finish running
find /nfs/home/rsbg/01_fastq/ -maxdepth 1 -type d -not -path "/nfs/home/rsbg/01_fastq/" | parallel -j16 rsync -avhzP --exclude="*/subsample/*" --exclude="*/trinity-work/*" --include="*/" --include="*.fastq.gz" --exclude="*" {}/ . > rsync_output.log 2>&1 &  (wd: ~/Projects/mosquito_denovo/data/raw_reads)
[2]+  Running                 wget https://www.dfam.org/releases/current/families/FamDB/dfam39_full.14.h5.gz > mosquito_repeat.hmm &