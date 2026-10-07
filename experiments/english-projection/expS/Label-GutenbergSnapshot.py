# Run pinned misaki (fba12365) in lexicon mode over Project Gutenberg books.
# For each occurrence of the 671 multi-pronunciation words in us_gold.json, records:
# book_id, split (train vs heldout), homograph, token, tag, phonemes, start, end, sentence.
# Network is blocked; no fallback model. Output is saved to per-book TSVs in OutDir.
import csv, json, os, socket, sys, time
def _blocked(self, *a, **k):
    raise OSError("network blocked in reference run")
socket.socket.connect = _blocked

from misaki import en
from misaki.token import MToken
from dataclasses import replace

def no_fallback(token):
    return (None, None)

books_dir = sys.argv[1] if len(sys.argv) > 1 else os.path.expandvars(r"%LOCALAPPDATA%\Build\PSPerception\inputs\gutenberg")
gold_path = sys.argv[2] if len(sys.argv) > 2 else os.path.expandvars(r"%LOCALAPPDATA%\Build\PSPerception\inputs\misaki\us_gold.json")
out_dir = sys.argv[3] if len(sys.argv) > 3 else os.path.expandvars(r"%LOCALAPPDATA%\Build\PSPerception\inputs\gutenberg_labeled")

os.makedirs(out_dir, exist_ok=True)

# 1. Load multi-pronunciation words
with open(gold_path, 'r', encoding='utf-8') as f:
    gold = json.load(f)

multi = set()
for k, v in gold.items():
    if isinstance(v, dict):
        distinct = {x for x in v.values() if isinstance(x, str) and x}
        if len(distinct) > 1:
            multi.add(k.lower())

print(f"Loaded {len(multi)} multi-pronunciation words from {gold_path}")

# 2. Book split: 32 train books, 8 heldout books
heldout_ids = {'161', '105', '1952', '64317', '2591', '1497', '3600', '23'}

g2p = en.G2P(trf=False, british=False, fallback=no_fallback, unk='❓')

# Process books in order
book_files = sorted([f for f in os.listdir(books_dir) if f.startswith('pg') and f.endswith('.txt') and not '.raw.' in f])

total_extracted = 0
t_start = time.time()

for fname in book_files:
    book_id = fname[2:-4] # strip pg and .txt
    split = "heldout" if book_id in heldout_ids else "train"
    out_file = os.path.join(out_dir, f"pg{book_id}.tsv")

    if os.path.exists(out_file) and os.path.getsize(out_file) > 100:
        print(f"[{book_id}] already exists ({os.path.getsize(out_file)} bytes), skipping.")
        continue

    t0 = time.time()
    in_path = os.path.join(books_dir, fname)
    with open(in_path, 'r', encoding='utf-8') as f:
        text = f.read()

    lines = [l.strip() for l in text.split('\n') if l.strip()]

    target_lines = []
    for l in lines:
        clean_words = {w.strip("',-._/;:!?—…\"“”()").lower() for w in l.split()}
        if clean_words.intersection(multi):
            target_lines.append(l)

    if not target_lines:
        print(f"[{book_id}] 0 target lines found.")
        continue

    docs = list(g2p.nlp.pipe(target_lines, batch_size=512))
    rows = []

    for l, doc in zip(target_lines, docs):
        # Flatten and sanitize sentence for clean single-line TSV output
        clean_sentence = l.replace('\t', ' ').replace('\r', ' ')
        mutable_tokens = [MToken(
            text=tk.text, tag=tk.tag_, whitespace=tk.whitespace_,
            _=MToken.Underscore(is_head=True, num_flags='', prespace=False)
        ) for tk in doc]
        tokens = g2p.fold_left(mutable_tokens)
        tokens = en.G2P.retokenize(tokens)
        ctx = en.TokenContext()

        for w in reversed(tokens):
            if not isinstance(w, list):
                if w.phonemes is None:
                    w.phonemes, w.rating = g2p.lexicon(replace(w, _=w._), ctx)
                ctx = en.G2P.token_context(ctx, w.phonemes, w)
            else:
                for sw in reversed(w):
                    if sw.phonemes is None:
                        sw.phonemes, sw.rating = g2p.lexicon(replace(sw, _=sw._), ctx)
                    ctx = en.G2P.token_context(ctx, sw.phonemes, sw)

        pos = 0
        for t in tokens:
            subtokens = [t] if not isinstance(t, list) else t
            for st in subtokens:
                j = clean_sentence.find(st.text, pos)
                if j >= 0:
                    low = st.text.lower()
                    if low in multi and st.phonemes:
                        rows.append([book_id, split, low, st.text, st.tag, st.phonemes, j, j + len(st.text), clean_sentence])
                    pos = j + len(st.text)

    with open(out_file, 'w', encoding='utf-8', newline='') as out:
        writer = csv.writer(out, delimiter='\t', quoting=csv.QUOTE_MINIMAL, lineterminator='\n')
        writer.writerow(['book_id', 'split', 'homograph', 'token', 'tag', 'phonemes', 'start', 'end', 'sentence'])
        for r in rows:
            writer.writerow(r)

    dt = time.time() - t0
    total_extracted += len(rows)
    print(f"[{book_id}] ({split}): {len(rows)} occurrences labeled in {dt:.1f}s ({len(rows)/max(0.01, dt):.1f} occ/s)")

total_time = time.time() - t_start
print(f"Labeling complete: {total_extracted} total occurrences across {len(book_files)} books in {total_time:.1f}s")
