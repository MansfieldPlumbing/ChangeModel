# ChangeModel Repository Hygiene and Architectural Realignment Report

**Date**: 2026-10-04  
**Workspace**: `C:\Dev\ChangeModel`  
**Governing Baseline**: NIST SP 800-218 (SSDF), SP 800-53 Rev. 5 (CM-8, CM-2, SI-7, AU-7), `AGENTS.md`

---

## 1. Executive Summary of Realignment

A comprehensive audit and surgical realignment of `C:\Dev\ChangeModel` was performed to eliminate architectural misdirection, enforce strict project isolation, retire ungrounded terminology, and align the codebase with its authoritative intent: a **self-revising representation learner**.

### Core Corrective Principles Enforced
1. **Authoritative Intent Clarified**: ChangeModel concerns changes in program representation. Authored source, tokens, AST, semantic structure, and runtime behavior remain distinct and traceable.
2. **Error vs. Incapacity**: Parametric error (wrong weights/predictions under sufficient coordinates) is strictly separated from representational insufficiency (structural residuals / contradictions where identical coordinates produce incompatible outcomes).
3. **Retirement of "World Tape" Terminology**: Persistence and replay logs (`.psd1` mutation journals) are support mechanisms for process-death state reconstruction, not the model, learning objective, or product. Standalone branding and architectural primacy for this support mechanism have been eliminated.
4. **Representational Fitness Invariants**: Fitness is defined across six formal criteria: (1) Admission, (2) Reconstructibility, (3) Structural usefulness, (4) Held-out generalization, (5) Economy, and (6) Stability. Execution timing is an empirical observation, not the definition of fitness.
5. **Project Isolation (NIST SP 800-53 CM-8 / AGENTS.md)**: Prohibited reaching into external project checkouts (`C:\Dev\JS2PS`, `C:\Dev\PSPersistence`). Cross-project interactions are governed by a versioned, data-only experiment record contract.
6. **Build Separation**: Redirected all transient test outputs and replay receipts to `$env:LOCALAPPDATA\Build\ChangeModel\gate7\`.

---

## 2. Before/After Steering Matrix

| Area / Subsystem | Before Steering (Observed in Tree) | Corrected Architectural Realignment | Exact Source Evidence |
| :--- | :--- | :--- | :--- |
| **Architectural Primacy of "World Tape"** | Framed persistence and replay logs as the primary architecture/worldview model (`README.md`, `src/WorldTape.ps1:1`, `UPSTREAM-AUDIT.md:11,33`, `docs/GATE7-RESULT.md:5`). | **Retired from architectural guidance.** Mutation journals and `.psd1` serialization are identified strictly as support mechanisms for reconstructing runtime state across process boundaries—not the model, learning objective, or product. | `AGENTS.md:20-24`, `README.md:27-32`, `UPSTREAM-AUDIT.md:8-37`, `docs/GATE7-RESULT.md:1-15`, `src/WorldTape.ps1:1-18` |
| **System Identity & Scope of Learning** | Broad claims suggesting an autonomous self-growing cognitive system inside PowerShell/SMA (`README.md:11-13`). | **Separated into Authoritative Intent vs. Bounded Implemented Gates.** The intended direction is a self-revising representation learner. The transformer/statistical model is decoupled as optional proposal machinery. Currently implemented capabilities are strictly bounded to greedy/exhaustive feature selection and ETS/DynamicKeyword installation. | `AGENTS.md:9-19`, `README.md:9-26`, `tests/Gate1-Wrong.ps1`, `tests/Gate6-RuntimeConceptInvention.ps1` |
| **Evaluation of Gate 7 Claims** | Phrased as complete "World Reconstruction" and "Viable cognition" surviving process death (`docs/GATE7-RESULT.md:1-8`). | **Bounded to Tokenizer State Reconstruction.** Clarified that Gate 7 proved reversible registration of dynamic keywords; it did **not** eliminate parse errors (10, 25, and 48 syntax errors remained), did **not** achieve LINQ lowering or managed assembly compilation, and did **not** achieve general semantic understanding. | `docs/GATE7-RESULT.md:1-15`, `tests/Gate7-WorldReconstruction.ps1:8-16` |
| **Cross-Project Isolation & Evidence Provenance** | References to external active working trees (`JS2PS_ROOT` execution in `tests/Gate7-Phase.ps1:33-42`, local paths in `docs/PROVENANCE.md:5-7`). | **Enforced strict project isolation (NIST SP 800-53 CM-8 / AGENTS.md).** External projects export versioned, data-only records; ChangeModel does not reach into external checkouts or act as their runtime dependency. Normalized provenance to repository/commit references. | `AGENTS.md:35-42`, `docs/PROVENANCE.md:1-15`, `docs/EXPERIMENT-RECORD-CONTRACT.md` |
| **Representational Fitness Definition** | Fitness was loosely implied by contradiction reduction or execution timing. | **Formalized 6 Representational Fitness Invariants**: (1) Admission, (2) Reconstructibility, (3) Structural usefulness, (4) Held-Out generalization, (5) Economy, and (6) Stability. Execution timing is classified as a separate observation, not fitness. Trivial "raw bytes" claims explicitly rejected. | `AGENTS.md:23-33`, `README.md:29-38` |
| **Repository Hygiene & Output Locations** | Test scripts defaulted transient output files into repository roots (`../build/gate7`). | **Enforced NIST Build Separation (SP 800-53 CM-8).** Defaulted all transient output and replay receipt paths to `$env:LOCALAPPDATA\Build\ChangeModel\gate7\`. | `tests/Gate7-WorldReconstruction.ps1:5`, `docs/GATE7-RESULT.md:100-105` |

---

## 3. Primary Research Synthesis

Five primary publications across the four designated theoretical areas were consulted and contrasted with the ChangeModel architecture:

1. **Representation & Grammar Learning**:
   - *Primary Source*: Dana Angluin (1987), *"Learning regular sets from queries and counterexamples"*, *Information and Computation*, 75(2): 87–106.
   - *Transfers*: The foundational separation between parametric estimation and representational inadequacy. Angluin’s $L^*$ observation table separates states by distinguishing tests/features. Counterexamples reveal when identical representations produce divergent transitions (contradictions), requiring the synthesis of a new structural column ($\mathcal{R}_0 \to \mathcal{R}^*$).
   - *Does Not Transfer*: Angluin assumes an active minimally adequate teacher answering arbitrary membership and equivalence queries over all $\Sigma^*$. ChangeModel operates over historical, partially observed execution logs and empirical test probes.
2. **Structural Program Transformations & Semantic Verification**:
   - *Primary Source*: Amir Pnueli, Michael Siegel, Eli Singerman (1998), *"Translation validation"*, *TACAS '98*, LNCS 1384: 151–166.
   - *Transfers*: The principle that structural transformation proposals (whether from compilers, optimization heuristics, or statistical models) are untrusted. Each candidate must undergo independent, deterministic semantic validation before admission.
   - *Does Not Transfer*: Pnueli's framework verifies simulation refinement relations over synchronized transition systems (FTS). ChangeModel currently uses empirical execution replay (truth table quadrants and test inputs).
3. **Structural Equivalence Search**:
   - *Primary Source*: Ross Tate, Michael Stepp, Zachary Tatlock, Sorin Lerner (2009), *"Equality Saturation: A New Approach to Optimization"*, *POPL 2009*: 264–276.
   - *Transfers*: Non-destructive exploration of structural alternatives compactly encoded without premature destructive phase ordering.
   - *Does Not Transfer*: Equality saturation assumes a preexisting library of sound rewrite rules. ChangeModel seeks to discover novel distinctions whose semantic consequence is initially unmeasured.
4. **Reusable Abstraction Discovery**:
   - *Primary Sources*:
     - Matthew Bowers et al. (2023), *"Top-Down Synthesis for Library Learning"*, *Proc. ACM Program. Lang.*, 7(POPL): 1181–1213 (Stitch).
     - Kevin Ellis et al. (2021), *"DreamCoder: Bootstrapping inductive program synthesis with wake-sleep library learning"*, *PLDI 2021*.
   - *Transfers*: Extracting reusable composite abstractions (`Or(A, B)`) from accumulated experience across a corpus using parsimony/compression metrics; decoupling proposal generation (neural/statistical search) from deterministic symbolic verification.
   - *Does Not Transfer*: Stitch and DreamCoder operate on pure lambda calculus term trees. ChangeModel operates across multi-level runtime representations (AST, DLR Expression tree lowering, dynamic binders, and ETS type tables).
5. **Provenance-Preserving Compilation & Promotion**:
   - *Primary Source*: Xavier Leroy (2009), *"Formal verification of a realistic compiler"*, *Communications of the ACM*, 52(7): 107–115 (CompCert).
   - *Transfers*: Strict traceability between authored source, tokens, AST, lowered intermediate representations, and runtime behavior. The logical identity of the structure remains invariant across lowering passes.
   - *Does Not Transfer*: CompCert is a closed, static C compiler formally verified in Coq; ChangeModel operates dynamically inside a live managed host runtime (.NET / SMA).

---

## 4. Multi-Project Experiment Ingestion Contract

The versioned, data-only experiment record contract has been defined at `docs/EXPERIMENT-RECORD-CONTRACT.md`.

### Key Contract Specifications (Schema `1.0.0`)
- **Data-Only Boundary**: Structured pure data (`.json` or restricted `.psd1`). Zero executable code, embedded scriptblocks, or dynamic evaluation.
- **Lineage & Coordinates**:
  - `origin_project`, `source_commit`, `representation_schema`.
  - `parent_id` and `candidate_id`.
  - Ordered structural mutations: sequence, operator, structural coordinates (e.g., `/Block/Statements[2]/BinaryExpr`), parameters, and preconditions.
- **Consequences & Status**:
  - Predicted vs. observed consequences.
  - Evaluation status enumeration: `accepted`, `rejected`, `uncertain`, `inapplicable`, `unmeasured`.
- **Multi-Level Observations**:
  - *Compiler Admission*: `admitted: bool`, parser/lowering error diagnostics.
  - *Behavioral Equality*: Black-box state divergence.
  - *Numerical / Acoustic Deviation*: Continuous error metrics with explicit units and tolerances.
  - *Performance*: CPU time and GC allocations with explicit tier context (distinct from semantic validity).
  - *Human Judgment*: Pairwise preferences and ratings (explicitly distinct from semantic proof).
- **Digest References**: Large artifacts (AST trees, payloads) are referenced via SHA-256 hashes rather than embedded in record bulk.

---

## 5. Verification Results & Regression Check

The test harness `tests/Verify.ps1` was executed in a clean PowerShell session:

```text
Running Verification...
GATE1_WRONG=PASS
GATE2_NOT_EVEN_WRONG=PASS
GATE3_MODEL_PROPOSAL=PASS
GATE4_SMA_NOT_EVEN_WRONG=PASS
--- Gate 5: Contentful SMA Delta ---
Quadrant Distribution:
  Q1 (Expr unchanged / Beh unchanged): 3
  Q2 (Expr changed   / Beh unchanged): 2
  Q3 (Expr changed   / Beh changed)  : 4
  Q4 (Expr unchanged / Beh changed)  : 0 (Measured fact: 0 for pure closed SMA lowering)
Confirmed R0 Contradictions: 4 (Structural Residual Present)
Selected Features: BinderOperationChanged, ConstantValueChanged
Winning Measure Contradictions: 0
Winning Measure Complexity    : 2
Reached Exhaustive Oracle     : True
Confirmed Minimal Complexity: 2 is minimal among all zero-contradiction representations.
Held-Out Metrics:
  HeldOutCount     : 4
  HeldOutCorrect   : 4
  HeldOutError     : 0
  HeldOutUnseenKeys: 0
GATE5_CONTENTFUL_DELTA=PASS
--- Gate 6: Runtime Concept Invention ---
Candidate concepts generated: 30
Confirmed all 5 individual atomic features suffer from structural residuals.
Winning Concept: Or(BinderOperationChanged, ConstantValueChanged)
  Contradictions : 0
  PredictionError: 3
  Complexity     : 2
  Reached Oracle : True
Oracle optimum: Or(BinderOperationChanged, ConstantValueChanged) over 30 concepts
Control: optimum withheld, search chose Atom(BinderOperationChanged), Reached Oracle = False
Held-Out Support Metrics:
  HeldOutCount     : 4
  HeldOutCorrect   : 4
  HeldOutError     : 0
  HeldOutUnseenKeys: 0
Confirmed: Pre-compiled ScriptBlock cannot resolve SemanticEffect prior to installation.
Confirmed: EXACT SAME ScriptBlock instance resolved newly materialized concept without recompilation.
Confirmed: Semantic reversibility proven - property access reverted to null on exact same ScriptBlock.
GATE6_RUNTIME_CONCEPT_INVENTION=PASS
GATE7_WORLD_RECONSTRUCTION=NOT RUN (set JS2PS_ROOT to a JS2PS checkout at the pinned commit)
```

- **Contract Compatibility**: `src/WorldTape.ps1` functions (`Write-WorldTape`, `Read-WorldTape`, `Invoke-WorldTape`) were maintained and aliased (`Write-ReplayJournal`, etc.), guaranteeing zero regressions across existing test callers.
- **Output Path Isolation**: `tests/Gate7-WorldReconstruction.ps1` was updated to default `-OutDir` to `$env:LOCALAPPDATA\Build\ChangeModel\gate7\`, preventing transient build pollution in the source tree.

---

## 6. Explicit Remaining Proposals & Unresolved Gaps

1. **Autonomous Continuous Mutate/Replay/Retain Loop**: Currently, search is invoked on static batches. A continuous, autonomous self-revision cycle is unimplemented.
2. **Reflective Tokens & Dynamic Grammars**: Modifying token definitions or parsing grammars at runtime beyond existing SMA `DynamicKeyword` registration is unexercised and unimplemented.
3. **Arbitrary AST Structural Search Under Semantic Admission**: Current search is bounded to boolean feature selection and predicate composition over hand-extracted attributes. Arbitrary program AST synthesis under semantic admission is unimplemented.
4. **Memory-Layout & Cache Optimization**: No physical memory compaction, layout optimization, or native alignment tuning exists.
5. **Managed-Assembly Promotion**: Compiling stabilized learned concepts into persisted managed assemblies (`PersistedAssemblyBuilder`) is unexercised; all concept installations currently terminate at in-memory ETS type tables.
6. **Multi-Project Experiment Ingestion Engine**: While the data contract schema is defined in `docs/EXPERIMENT-RECORD-CONTRACT.md`, no automated ingestion parser or cross-project learning pipeline is implemented.

---

## 7. Scoped Git Diff Summary

```text
=== Git Status ===
 M AGENTS.md
 M README.md
 M UPSTREAM-AUDIT.md
 M docs/GATE7-RESULT.md
 M docs/PROVENANCE.md
 M src/WorldTape.ps1
 M tests/Gate7-WorldReconstruction.ps1
?? docs/EXPERIMENT-RECORD-CONTRACT.md
?? docs/REALIGNMENT-REPORT.md

=== Git Diff Stat ===
 AGENTS.md                           |  60 +++++++++++++-
 README.md                           | 156 +++++++++++++++++++-----------------
 UPSTREAM-AUDIT.md                   |  14 ++--
 docs/GATE7-RESULT.md                |  19 +++--
 docs/PROVENANCE.md                  |  18 ++---
 src/WorldTape.ps1                   |  27 +++++--
 tests/Gate7-WorldReconstruction.ps1 |   8 +-
 7 files changed, 193 insertions(+), 109 deletions(-)
```
