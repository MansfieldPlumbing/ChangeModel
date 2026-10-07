"""
Materialize deterministically:
- first 500 sentences from data/train/*.tsv
- first 200 sentences from data/eval/*.tsv
Format: TSV without regex or JSON.
"""

import os
import sys
import csv

BASE_DIR = r"C:\temp\sma-english-projection"
INPUT_DIR = os.path.join(BASE_DIR, "inputs", "WikipediaHomographData")
DATA_TRAIN = os.path.join(INPUT_DIR, "data", "train")
DATA_EVAL = os.path.join(INPUT_DIR, "data", "eval")

def extract_sentences(src_dir, target_count, out_path):
    files = sorted([f for f in os.listdir(src_dir) if f.endswith(".tsv")])
    collected = []
    
    for fname in files:
        fpath = os.path.join(src_dir, fname)
        with open(fpath, "r", encoding="utf-8", newline="") as f:
            reader = csv.reader(f, delimiter="\t")
            header = next(reader, None)
            row_idx = 0
            for row in reader:
                if not row or len(row) < 3:
                    continue
                row_idx += 1
                homograph = row[0]
                wordid = row[1]
                sentence = row[2]
                collected.append((len(collected), fname, row_idx, homograph, wordid, sentence))
                if len(collected) == target_count:
                    break
        if len(collected) == target_count:
            break

    with open(out_path, "w", encoding="utf-8", newline="") as out:
        writer = csv.writer(out, delimiter="\t")
        writer.writerow(["id", "filename", "row_index", "homograph", "wordid", "sentence"])
        for item in collected:
            writer.writerow(item)

    print(f"Wrote {len(collected)} sentences to {out_path}")

if __name__ == "__main__":
    train_out = os.path.join(BASE_DIR, "inputs", "train_500.tsv")
    eval_out = os.path.join(BASE_DIR, "inputs", "eval_200.tsv")
    extract_sentences(DATA_TRAIN, 500, train_out)
    extract_sentences(DATA_EVAL, 200, eval_out)
