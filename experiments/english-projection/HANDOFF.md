# SMA-English Projection Experiment: Handoff Document

## 1. What Has Been Completed
- **Environment & Input Verification**:
  - Pwsh: PowerShell 7.7.0-preview.5 (`C:\bin\pwsh\pwsh.exe`).
  - Python: Verified 3.14 (`C:\bin\micromamba\envs\2026\python.exe`) and added to User PATH without disturbing existing entries.
  - SpaCy frozen reference: Python 3.11.16, spaCy 3.8.4, `en_core_web_sm` 3.8.0 (`%LOCALAPPDATA%\Build\Kokoro-Hexagon\misaki-ref-fba12365\src\.venv\Scripts\python.exe`). Untouched.
  - Materialized 329 files from pinned commit `8f008f021e88f8b71118a27ae655f1f3121162bc` into `inputs/WikipediaHomographData/` and generated `inputs/MANIFEST.tsv` (SHA-256).
  - Materialized deterministic training subset (500 sentences) in `inputs/train_500.tsv` and held-out eval set (200 sentences) in `inputs/eval_200.tsv`.
  - Extracted spaCy token reference for training set in `inputs/spacy_train_500.tsv`.
- **Baseline Inventories (30-Sentence & 500-Corpus Surveys)**:
  - Surveyed all 33 reserved keyword collisions across 500 sentences (`results/inventory_reserved_collisions_500.tsv`). Revealed that `In` at sentence start provides a 100% reliable free prepositional marker (`ADP`/`prep`).
  - Surveyed punctuation-to-AST shape mappings (`results/inventory_punctuation_ast_shapes_30.tsv`).
  - Surveyed boundary disagreements against spaCy (`results/inventory_boundary_disagreements_30.tsv`). Found 83.8% of disagreements are caused simply by terminal punctuation absorption.
  - Cataloged numeric morphology across 126 forms $\times$ 2 contexts (`results/inventory_numeric_morphology.tsv`).
- **Experiment A: Exhaustive vs. Greedy Comparison (30-Sentence Subset)**:
  - Exhaustively evaluated all 768 configurations in the bounded mutation vocabulary (`receipts/exhaustive_30_receipts.tsv`).
  - Ran greedy one-mutation-at-a-time hill-climb (`receipts/greedy_30_receipts.tsv`).
  - Proved that greedy reaches the exact **exhaustive optimum objective value** (`Errors=0, FailSent=0, UsefulAST=460, BoundDiff=57, Muts=6`).
  - Discovered a degenerate equivalence class between `pre=qmark` (`¿ `) and `pre=slash` (`// `) as command-head sentinels.
- **500-Sentence Greedy Hill-Climb (Train Set)**:
  - Starting baseline: 77 errors across 72 sentences (428/500 passing, UsefulAST=6153, BoundDiff=1657).
  - Converged at step 13 (156 evaluations): **1 error across 1 sentence** (499/500 passing, 99.8% pass rate, UsefulAST=8037, BoundDiff=831).
  - Saved frozen winning configuration in `results/frozen_best_config.tsv` and full receipts in `receipts/greedy_train500_receipts.tsv`.
- **Held-Out 200 Evaluation (Single-Pass Execution)**:
  - Ran `inputs/eval_200.tsv` exactly once after freezing the best configuration.
  - Baseline on eval 200: 37 errors across 30 failing sentences (85.0% pass rate).
  - Frozen projection on eval 200: **8 errors across 2 failing sentences (99.0% pass rate)**.
  - Verified 100% bit-for-bit lossless reversibility across all 200 sentences.
  - Fully diagnosed root causes and mapped directly to PowerShell source code in `results/FAILURE_ANALYSIS_AND_LIMITATIONS.md`.

---

## 2. Exact Current Hypothesis
- **Syntactic Contact Projection**: English text can be compiled via a lightweight, 1:1 reversible contact language into SMA’s native parser grammar, allowing `[Parser]::ParseInput` to serve as a zero-execution, deterministic, sub-millisecond syntactic substrate.
- **Structural Mapping**:
  - Initial sentinels (`// ` or `¿ `) shift sentence parsing into Command Argument Mode, eliminating command-head collisions and allowing commas to form `ArrayLiteralAst`.
  - Apostrophe escaping (`` don`'t `` or `donʼt`) eliminates runaway single-quote strings while preserving contraction word units.
  - Fullwidth substitutions (`＃`, `；`) prevent comment truncation and premature statement termination.
  - Spacing before terminal punctuation (`imagery .`) isolates punctuation into standalone tokens without altering lexical word boundaries.
- **Semantic Invariance**: Beyond syntax parsing, equivalent English expressions (e.g., `1,000` vs `1000`, `don't` vs `do not`, `John's` vs `of John`) can be normalized into equivalent SMA AST topologies, providing an inductive bias for downstream phonetics, prosody, and homograph disambiguation in Kokoro/Misaki.

---

## 3. Current Mutation Vocabulary
The frozen vocabulary comprises 7 orthogonal slots:
1. `Prefix`: `none`, `qmark` (`¿ `), `slash` (`// `), `spade` (`♠ `)
2. `Apostrophe`: `none`, `modifier` (`ʼ` U+02BC), `escaped` (`` `' ``), `backtick` (`` ` ``)
3. `Hash`: `none`, `fullwidth` (`＃` U+FF03)
4. `Semicolon`: `none`, `fullwidth` (`；` U+FF1B)
5. `TermPunct`: `none`, `space` (` .`), `nbsp` (`\u00A0.`)
6. `Hyphen`: `none`, `unicode` (`‐` U+2010)
7. `Quote`: `none`, `guillemets` (`« »`)

Winning frozen configuration:
`pre=slash|apos=modifier|hash=fullwidth|semi=fullwidth|term=space|hyph=unicode|quot=guillemets`
(Equivalence class: `pre=qmark` yields identical score).

---

## 4. Latest Scores

| Dataset | Split | Model / Configuration | Errors | Failing Sentences | Pass Rate | Useful AST Score | Boundary Disagreements |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| **Subset 30** | Train | Baseline (unmutated) | 7 | 6 / 30 | 80.0% | 338 | 115 |
| **Subset 30** | Train | Exhaustive Optimum (768 evals) | 0 | 0 / 30 | 100.0% | 460 | 57 |
| **Subset 30** | Train | Greedy Final (6 steps) | 0 | 0 / 30 | 100.0% | 460 | 57 |
| **Full 500** | Train | Baseline (unmutated) | 77 | 72 / 500 | 85.6% | 6,153 | 1,657 |
| **Full 500** | Train | Frozen Best Projection | **1** | **1 / 500** | **99.8%** | **8,037** | **831** |
| **Held-Out 200** | Eval | Baseline (unmutated) | 37 | 30 / 200 | 85.0% | 2,397 | N/A |
| **Held-Out 200** | Eval | Frozen Best Projection (Single pass) | **8** | **2 / 200** | **99.0%** | **3,205** | N/A |

Lossless reversibility is **100.0% verified** across all 700 sentences.

---

## 5. Commands Needed to Reproduce Latest Results
All commands must be executed using `C:\bin\pwsh\pwsh.exe -NoProfile`:

1. **Verify Lossless Reversibility**:
   `& "C:\bin\pwsh\pwsh.exe" -NoProfile -File "C:\temp\sma-english-projection\tools\test_reversibility.ps1"`
2. **Reproduce Exhaustive vs. Greedy (30 Sentences)**:
   `& "C:\bin\pwsh\pwsh.exe" -NoProfile -File "C:\temp\sma-english-projection\tools\run_exhaustive_30.ps1"`
3. **Reproduce 500-Sentence Greedy Hill-Climb**:
   `& "C:\bin\pwsh\pwsh.exe" -NoProfile -File "C:\temp\sma-english-projection\tools\run_greedy_train500.ps1"`
4. **Reproduce Single-Pass Held-Out 200 Evaluation**:
   `& "C:\bin\pwsh\pwsh.exe" -NoProfile -File "C:\temp\sma-english-projection\tools\run_heldout_eval200.ps1"`
5. **Run Numeric Morphology Probe**:
   `& "C:\bin\pwsh\pwsh.exe" -NoProfile -File "C:\temp\sma-english-projection\tools\numeric_morphology_probe.ps1"`

---

## 6. Files That Matter
- `inputs/train_500.tsv`: Authoritative first 500 training sentences.
- `inputs/eval_200.tsv`: Authoritative held-out 200 eval sentences.
- `inputs/spacy_train_500.tsv`: Reference spaCy token boundaries for train 500.
- `inputs/MANIFEST.tsv`: SHA-256 digests of all 329 WikipediaHomographData input files.
- `tools/EvaluationEngine.ps1`: Core evaluation engine, projection and unprojection functions, comparator.
- `tools/run_exhaustive_30.ps1`: Exhaustive 768-eval search and greedy runner for 30-sentence subset.
- `tools/run_greedy_train500.ps1`: Full 500-sentence hill-climb engine.
- `tools/run_heldout_eval200.ps1`: Frozen evaluation runner on held-out 200 set.
- `tools/numeric_morphology_probe.ps1`: 126-form numeric morphology probe.
- `results/frozen_best_config.tsv`: Machine-readable winning configuration parameters.
- `results/INVENTORIES_REPORT.md`: Baseline inventory report (reserved collisions, punctuation shapes, boundary diffs).
- `results/FAILURE_ANALYSIS_AND_LIMITATIONS.md`: Exhaustive failure classification mapped to PowerShell engine source code.
- `receipts/exhaustive_30_receipts.tsv`: Full TSV log of all 768 evaluations on 30 sentences.
- `receipts/greedy_30_receipts.tsv`: Full TSV step receipts of 30-sentence greedy climb.
- `receipts/greedy_train500_receipts.tsv`: Full TSV step receipts of 500-sentence greedy climb.

---

## 7. What Remains / Next Steps for Muse Glimmer
1. **Semantic Invariance Testing (Experiment B)**:
   - Construct pairs of meaning-preserving English sentences (`1,000` vs `1000`, `don't` vs `do not`, `John's` vs `the book of John`, `pages 3–5` vs `pages 3 to 5`).
   - Measure whether the projected AST topologies converge to identical structural trees.
2. **Homograph Disambiguation Integration**:
   - Evaluate whether SMA AST position (command head vs argument vs modifier) correlates with part-of-speech and pronunciation in `WikipediaHomographData` (`abstract_adj-nou` vs `abstract_verb`).
3. **Contact Language Expansion for the Two Edge Cases**:
   - Test parenthetical unit joining (`600,000♠ly`) to eliminate expression-mode juxtaposition errors.
   - Test comma post-parenthesis spacing (`(...) ,`) to eliminate `MissingArgument` on closed expressions.

---

## 8. Failed Approaches Worth Not Repeating
- **Unescaped raw ASCII single quote (`'`)**: Always triggers `TerminatorExpectedAtEndOfString` unless matched. Never leave unescaped in English prose.
- **Bare statement-initial commas (`Rather,`)**: Always triggers `MissingArgument` when parsing in statement mode. Always use a command-head sentinel (`// ` or `¿ `).
- **Unbalanced parentheses in source text**: Cannot be parsed in SMA without syntactic repair. Must be rejected or explicitly flagged as source data errors.
- **Juxtaposing bare words after expressions inside `(...)`**: Inside parentheses, PowerShell switches to Expression Mode, forbidding space-separated arguments (`expr1 expr2`). Do not leave unit symbols adjacent to numbers inside parentheses without explicit joining or operators.
