# Run pinned misaki (fba12365) in lexicon mode over WikipediaHomographData sentences and report,
# for each row, the phonemes and tag misaki gave the target word. Network is blocked; a falsy
# fallback would load BART (en.py:531), so the fallback is a callable that returns nothing.
import csv, socket, sys
def _blocked(self, *a, **k):
    raise OSError("network blocked in reference run")
socket.socket.connect = _blocked
from misaki import en

def no_fallback(token):
    return (None, None)

g2p = en.G2P(trf=False, british=False, fallback=no_fallback, unk='❓')
split_dir, out_path = sys.argv[1], sys.argv[2]
import os
with open(out_path, 'w', encoding='utf-8', newline='') as out:
    w = csv.writer(out, delimiter='\t', quoting=csv.QUOTE_MINIMAL, lineterminator='\n')
    w.writerow(['file', 'row', 'homograph', 'wordid', 'start', 'end', 'token', 'tag', 'phonemes'])
    for name in sorted(os.listdir(split_dir)):
        with open(os.path.join(split_dir, name), encoding='utf-8') as f:
            rows = list(csv.reader(f, delimiter='\t'))
        for i, r in enumerate(rows[1:], start=1):
            hom, wid, sent, start, end = r[0], r[1], r[2], int(r[3]), int(r[4])
            # Same re-anchoring as the PowerShell experiment: nearest occurrence within 12 chars.
            if sent[start:end].lower() != hom.lower():
                found = -1
                for d in range(13):
                    for c in (start - d, start + d):
                        if 0 <= c and c + len(hom) <= len(sent) and sent[c:c + len(hom)].lower() == hom.lower():
                            found = c
                            break
                    if found >= 0:
                        break
                if found < 0:
                    continue
                start, end = found, found + len(hom)
            _, tokens = g2p(sent)
            # misaki tokens carry text + whitespace; rebuild offsets by scanning the sentence.
            pos, hit = 0, None
            for t in tokens:
                j = sent.find(t.text, pos)
                if j < 0:
                    continue
                if j <= start < j + len(t.text):
                    hit = t
                    break
                pos = j + len(t.text)
            if hit is None:
                w.writerow([name, i, hom, wid, start, end, '', '', ''])
            else:
                w.writerow([name, i, hom, wid, start, end, hit.text, hit.tag, hit.phonemes or ''])
