Three versions of each environment by what they specify:
1. envname.export.yml              - Target programs only. Your conda create will resolve its own dependencies.
2. envname.export-from-history.yml - Conda environment exported with the dependencies as they were solved for me. Your conda create will still do a lot of work.
3. envname.explicit.txt            - Package list. Can be imported directly into a new conda environment with running the solver. This is the fastest (but less portable) solution.


For example, to install busco:

case 1)

    conda env create -f busco.export-from-history.yml
    
case 2)

    conda env create -f busco.export.yml
    
case 3)

    conda env create -n busco -f busco.explicit.txt

