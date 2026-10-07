"""
Extract spaCy token boundaries from train_500.tsv.
Reference environment: spaCy en_core_web_sm 3.8.0.
Format: TSV (no JSON, no regex).
"""

import os
import sys
import csv
import spacy

BASE_DIR = r"C:\temp\sma-english-projection"
TRAIN_TSV = os.path.join(BASE_DIR, "inputs", "train_500.tsv")
OUT_TSV = os.path.join(BASE_DIR, "inputs", "spacy_train_500.tsv")

def main():
    nlp = spacy.load("en_core_web_sm")
    print(f"Loaded spaCy {spacy.__version__}, model {nlp.meta['name']} {nlp.meta['version']}")

    sentences = []
    with open(TRAIN_TSV, "r", encoding="utf-8", newline="") as f:
        reader = csv.reader(f, delimiter="\t")
        header = next(reader)
        for row in reader:
            # id, filename, row_index, homograph, wordid, sentence
            s_id = int(row[0])
            sent_text = row[5]
            sentences.append((s_id, sent_text))

    print(f"Processing {len(sentences)} sentences...")
    
    with open(OUT_TSV, "w", encoding="utf-8", newline="") as out:
        writer = csv.writer(out, delimiter="\t")
        writer.writerow(["sentence_id", "token_idx", "start", "end", "text", "pos", "dep"])
        for s_id, sent_text in sentences:
            doc = nlp(sent_text)
            for t_idx, tok in enumerate(doc):
                writer.writerow([
                    s_id,
                    t_idx,
                    tok.idx,
                    tok.idx + len(tok.text),
                    tok.text,
                    tok.pos_,
                    tok.dep_
                ])

    print(f"Saved spaCy tokens to {OUT_TSV}")

if __name__ == "__main__":
    main()
