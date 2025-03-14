# convert fastp json output files to a csv, extracting scalar values on filtering stats
import json,os,sys
import pandas as pd
try:
    dir_w_jsons=sys.argv[1]
except:
    print(f"Usage: {sys.argv[0]} dir_w_jsons")
    sys.exit(0)

fnames = [os.path.join(dir_w_jsons, f) for f in os.listdir(dir_w_jsons) if f.endswith('.json') ] 
rows = []
for fname in fnames:
    with open(fname) as fp:
        report=json.load(fp)
    row = {}
    row['report_name'] = fname
    row['duplication'] = report['duplication']['rate']

    for stat_group in ['read1_before_filtering','read2_before_filtering','read1_after_filtering','read2_after_filtering']:
        # get the scalars from these
        for stat in ['total_reads', 'total_bases', 'q20_bases', 'q30_bases']:
            row["_".join([stat_group,stat])] = report[stat_group][stat]

    rows.append(row)

df = pd.DataFrame(rows)
df.to_csv("fastp_reports.csv", sep="\t")
