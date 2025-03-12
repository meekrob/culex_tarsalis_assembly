This simple pipeline will run repeatmasker on the draft genome

conda env: repeatmasker which is stored here ~/pipelines/repeat_annotator/config/environment.yml




steps to run this pipeline

create conda environment and activate it.

```
conda create -f ~/pipelines/repeat_annotator/config/environment.yml > repeatmasker

**its important to make sure RepeatMasker and h5py are installed, they should be in conda env
```

download the relevant dfam databases
```
wget https://www.dfam.org/releases/current/families/FamDB/dfam39_full.0.h5.gz
wget https://www.dfam.org/releases/current/families/FamDB/dfam39_full.1.h5.gz
wget https://www.dfam.org/releases/current/families/FamDB/dfam39_full.2.h5.gz
wget https://www.dfam.org/releases/current/families/FamDB/dfam39_full.3.h5.gz
wget https://www.dfam.org/releases/current/families/FamDB/dfam39_full.4.h5.gz
wget https://www.dfam.org/releases/current/families/FamDB/dfam39_full.5.h5.gz
wget https://www.dfam.org/releases/current/families/FamDB/dfam39_full.6.h5.gz
wget https://www.dfam.org/releases/current/families/FamDB/dfam39_full.7.h5.gz
wget https://www.dfam.org/releases/current/families/FamDB/dfam39_full.8.h5.gz
wget https://www.dfam.org/releases/current/families/FamDB/dfam39_full.9.h5.gz
wget https://www.dfam.org/releases/current/families/FamDB/dfam39_full.10.h5.gz
wget https://www.dfam.org/releases/current/families/FamDB/dfam39_full.11.h5.gz
wget https://www.dfam.org/releases/current/families/FamDB/dfam39_full.12.h5.gz
wget https://www.dfam.org/releases/current/families/FamDB/dfam39_full.13.h5.gz
wget https://www.dfam.org/releases/current/families/FamDB/dfam39_full.14.h5.gz
wget https://www.dfam.org/releases/current/families/FamDB/dfam39_full.15.h5.gz
wget https://www.dfam.org/releases/current/families/FamDB/dfam39_full.16.h5.gz
```
put them in a directory
```
mkdir dfam
mv dfam39*gz dfam/
```

gunzip the downloads
```
gunzip dfam/dfam39*.gz
```

clone the FamDB repo
```
git clone git@github.com:Dfam-consortium/FamDB.git
```

make repeat.hmm usable:
```
./FamDB/famdb.py -i dfam families -f fasta_name -ad 'Diptera' > mosquito_repeats.fasta
```

run the script for repeatmasker

```
RepeatMasker -s -lib -uncurated mosquito_repeat_lib.fasta $1 -pa 4 -dir .
```