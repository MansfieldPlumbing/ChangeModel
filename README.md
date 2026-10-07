# PSPerception

> **"Every capability claim names a gate."**  
> **"A passing producer/reader pair is not independent evidence."**  
> **"State unproved work as unproved."**  
> **"Parser acceptance does not establish understanding or semantic equivalence."**  
> **"Changed token classification does not establish successful compilation."**  

---

## 1. Executive Summary & Authoritative Intent

PSPerception is counterexample-guided percept refinement. It proposes reversible changes, measures each against fixed gates, keeps or reverts, stores every kept and rejected move in a provenance graph, and hands kept percepts to PSLowering to compile into CoreLib-only code. The delta (reference minus candidate) only steers the search; percepts are what it keeps. Don't call the delta a gradient or the backward walk backpropagation. The implemented backward walk is chronological backtracking: at a dead end it returns to the most recent kept state. Dependency-directed backtracking is the intended replacement and is not implemented; don't call the current walk dependency-directed.

- **Traceable Representation Layers**: Authored source, tokens, AST, semantic structure, and runtime behavior remain distinct and traceable.
- **Error vs. Incapacity**: It separates **parametric error** ("wrong") from **representational insufficiency** ("not even wrong"):
  - *Wrong (Parametric Error)*: Given a representation $\mathcal{R}$ whose coordinate space cleanly separates all distinct behavioral states ($\text{Contradictions} = 0$), the model's predictive parameters or weights are suboptimal ($\text{PredictionError} > 0$). Tuning parameters on observed experience eliminates error on held-out data.
  - *Not Even Wrong (Structural Contradiction)*: The representation $\mathcal{R}_0$ projects causally distinct states onto identical coordinate points, producing mutually exclusive transitions from identical feature vectors ($\text{Contradictions} > 0$). No parameter regression, weight adjustment, or statistical scaling can eliminate this error—the model suffers from a **structural residual**. Search over structural mutations discovers missing causal dimensions ($\mathcal{R}_0 \to \mathcal{R}^*$).
- **Deterministic Semantic Admission**: Structural mutations are explored under deterministic semantic admission rules rather than unrestrained generation.
- **Provenance Retention**: Provenance and expandable underlying structure are preserved across mutations via the in-memory provenance graph (`src/Store.ps1`).
- **Dependency-Directed Backtracking (target)**: Search is steered by localized deltas and, at a dead end, returns to the culprit identified by justifying contradictions rather than to the most recent state. `src/Refine.ps1` currently backtracks chronologically.
- **Persistent Logical Identity**: Stable structures may eventually become compiled managed regions via `PSLowering`; the persistent logical structure, not the emitted assembly, owns identity.
- **Proposal Separation**: Proposers are evaluated against fixed gates; proposals come from the store first, then from a fixed percept grammar.

### Architectural Boundaries & Retired Terminology
- **Persistence & Replay Journals as Support Mechanisms**: Mutation journals and serialization (`.psd1` records) are support mechanisms for reconstructing runtime state across process death—they are not the model, learning objective, or product.
- **Core Representational Fitness**: Fitness is evaluated across:
  1. *Admission*: Syntax and semantic validity under host rules.
  2. *Reconstructibility*: Deterministic bidirectional restoration without loss of provenance.
  3. *Structural Usefulness*: Resolving causal ambiguities and separating distinct runtime behaviors.
  4. *Held-Out Generalization*: Predicting outcomes on unseen specimen instances under explicit support.
  5. *Economy*: Minimal complexity among equally predictive candidate representations.
  6. *Stability*: Invariance under non-semantic mutations and reversible uninstallation.
- **Observation vs. Definition**: Execution timing is a separate empirical observation—not the definition of representational fitness. A preference is not semantic proof; a missing measurement is not zero; a runtime cost is not a parse failure.
- **Rejection of Raw-Byte Triviality**: Reject trivial "consume everything as raw bytes" success claims. Byte sequences conflate syntax, structure, and execution semantics.

---

## 2. The Eight Empirical Verification Gates

Every claim in `PSPerception` corresponds to an executable verification script under `tests/`. Passing tests are the sole acceptable proof of capability.

| Gate | Name | Executable Gate | Invariant Proven |
| :--- | :--- | :--- | :--- |
| **Gate 1** | **Parameter Calibration** | [`tests/Gate1-ParameterCalibration.ps1`](tests/Gate1-ParameterCalibration.ps1) | $\text{Contradictions} = 0$, $\text{InitialError} > 0 \implies \text{HeldOutError} = 0$ after parameter calibration. The representation is sufficient; the model was merely uncalibrated. |
| **Gate 2** | **Feature Selection** | [`tests/Gate2-FeatureSelection.ps1`](tests/Gate2-FeatureSelection.ps1) | Impoverished $\mathcal{R}_1 = \{X\}$ induces contradictions ($\text{Contradictions} > 0$). Bounded search over candidate features discovers $\{X, \text{Direction}\}$ with zero contradictions and minimal complexity. |
| **Gate 3** | **Proposal Validation & Replay** | [`tests/Gate3-ProposalValidation.ps1`](tests/Gate3-ProposalValidation.ps1) | A statistical or external proposer suggests representation mutations (`AddFeature`, `RemoveFeature`, `Combine`), but proposals must pass independent, deterministic replay. Proposals that do not strictly reduce contradictions are rejected. |
| **Gate 4** | **SMA Feature Selection** | [`tests/Gate4-SmaFeatureSelection.ps1`](tests/Gate4-SmaFeatureSelection.ps1) | Extends structural contradiction detection to authentic PowerShell AST lowering and DLR LINQ expression tree generation. |
| **Gate 5** | **Contentful SMA Delta** | [`tests/Gate5-ContentfulDelta.ps1`](tests/Gate5-ContentfulDelta.ps1) | Demonstrates that coarse representation $\mathcal{R}_0 = \{\text{CoarseDeltaExpression}\}$ conflates behavior-preserving and behavior-altering AST transformations ($\text{Contradictions} = 4$). Bounded search over authentic SMA expression features discovers the minimal zero-contradiction feature pair $\{\text{BinderOperationChanged}, \text{ConstantValueChanged}\}$ and classifies all 4 held-out pairs correctly (9 training pairs). |
| **Gate 6** | **Predicate Synthesis** | [`tests/Gate6-PredicateSynthesis.ps1`](tests/Gate6-PredicateSynthesis.ps1) | Synthesizes a composite predicate $\text{Or}(\text{BinderOperationChanged}, \text{ConstantValueChanged})$ from atomic primitives, verifies it against execution evidence, and materializes it into the live runspace via PowerShell Extended Type System (`Update-TypeData`). Pre-compiled `ScriptBlock` instances dynamically resolve the newly synthesized predicate without recompilation, and revert when `Remove-TypeData` is executed. |
| **Gate 7** | **Process-Death State Reconstruction** | [`tests/Gate7-StateReconstruction.ps1`](tests/Gate7-StateReconstruction.ps1) | Verifies bounded state reconstruction across process boundaries: learns a representational delta from recorded evidence, persists it to a `.psd1` mutation journal (`src/MutationJournal.ps1`), reconstructs the identical runtime tokenizer state in a separate `pwsh` process, and rolls back to pristine state via exact inverses. Result and limits: [`docs/GATE7-STATE-RECONSTRUCTION-RESULT.md`](docs/GATE7-STATE-RECONSTRUCTION-RESULT.md); upstream audit: [`UPSTREAM-AUDIT.md`](UPSTREAM-AUDIT.md). |
| **Gate 8** | **Refine Loop** | [`tests/Gate8-RefineLoop.ps1`](tests/Gate8-RefineLoop.ps1) | Counterexample-guided refine loop matches exhaustive search on small synthetic case ("mechanics only"), pruning non-differing attributes, recording kept and rejected moves in the in-memory provenance graph (`src/Store.ps1`), and reproducing the exact final state upon replaying the store from scratch. |

---

## 3. Subsystem Architecture

```text
PSPerception/
├── Dev.MansfieldPlumbing.PowerShell.Perception.psd1 # Module manifest
├── Dev.MansfieldPlumbing.PowerShell.Perception.psm1 # Root module
├── AGENTS.md                                  # Operational constraints, epistemic boundaries, and intent
├── README.md                                  # Architectural overview, gates, and literature alignment
├── UPSTREAM-AUDIT.md                          # Pinned SMA source audit for runtime extension points
├── docs/
│   ├── EXPERIMENT-RECORD-CONTRACT.md          # Live objects receipt contract (zero JSON)
│   ├── GATE7-STATE-RECONSTRUCTION-RESULT.md   # Empirical results and exact limitations of Gate 7
│   └── PROVENANCE.md                          # Tracing AST search, reflection probes, and SMA internal members
├── probes/
│   ├── Observe-SmaLowering.ps1                # Deep inspection of internal Compiler.Compile and LINQ trees
│   └── Measure-SmaDeltas.ps1                  # Quantitative divergence probe across AST lowering stages
├── src/
│   ├── LinearState.ps1                        # Canonical state transition engines (linear motion model)
│   ├── Representation.ps1                     # Feature extraction coordinate mapping and projection
│   ├── ObservationRecord.ps1                  # Contradiction counting, structural residual auditing, history
│   ├── Prediction.ps1                         # Parametric delta predictors over feature vectors
│   ├── Proposal.ps1                           # Mutation DSL (AddFeature, RemoveFeature, Combine) and replay verifier
│   ├── Search.ps1                             # Bounded hill-climbing search with exhaustive optimum reference
│   ├── Store.ps1                              # In-memory provenance graph of live objects & replay from scratch
│   ├── Refine.ps1                             # Counterexample-guided percept refinement loop
│   ├── SmaDataset.ps1                         # Authentic SMA AST/Token/LINQ lowering specimen generator
│   ├── SmaContentfulDataset.ps1               # Multi-quadrant adversarial corpus preserving AST signatures
│   ├── ExpressionFeatures.ps1                 # Deep reflection extractors for DLR binders, constants, node types
│   ├── PredicateSynthesis.ps1                 # Predicate synthesis, sufficiency scoring, and live ETS materialization
│   └── MutationJournal.ps1                    # Replay journal support: deterministic .psd1 serialization & rollback
└── tests/
    ├── Verify.ps1                             # Master test runner executing all gates
    ├── Gate1-ParameterCalibration.ps1         # Parametric tuning gate
    ├── Gate2-FeatureSelection.ps1             # Structural residual & representation revision gate
    ├── Gate3-ProposalValidation.ps1           # Untrusted proposer / deterministic replay gate
    ├── Gate4-SmaFeatureSelection.ps1          # SMA AST expression lowering proof
    ├── Gate5-ContentfulDelta.ps1              # Multi-quadrant SMA contentful delta proof
    ├── Gate6-PredicateSynthesis.ps1           # Dynamic predicate synthesis & ETS live materialization proof
    ├── Gate7-StateReconstruction.ps1          # Two-process mutation journal replay and rollback gate
    ├── Gate7-Phase.ps1                        # Execution phase worker for Gate 7 (Learn / Replay)
    └── Gate8-RefineLoop.ps1                   # Counterexample-guided refine loop & store replay gate
```

---

## 4. The Authentic SMA Lowering Verification Ground

Rather than mocking abstract languages, `PSPerception` tests its representation search against authentic **PowerShell / System.Management.Automation (SMA)** compiler internals:

1. **AST to LINQ Lowering**: Probes inspect internal `Compiler.Compile` and `Compiler._endBlockLambda` via reflection on `System.Management.Automation.ScriptBlock._scriptBlockData`.
2. **Authentic Features**:
   - `BinderOperationChanged`: Detects DLR dynamic callsite binder operation shifts (e.g., arithmetic, comparison).
   - `ConstantValueChanged`: Tracks literal constant modifications across lowered expression leaves.
   - `OperandOrderChanged`: Detects non-commutative parameter re-ordering.
   - `NodeTypeChanged`: Identifies syntactic category modifications (e.g., binary expressions vs method calls).
   - `CallTargetChanged`: Detects redirection of invocations to alternate methods or functions.

### The Four Quadrants of Semantic Change
In `tests/Gate5-ContentfulDelta.ps1`, pairs of scriptblocks are evaluated across a 4-quadrant truth table:
- **Q1 (Expr Unchanged / Behavior Unchanged)**: Idempotent or identical script blocks.
- **Q2 (Expr Changed / Behavior Unchanged)**: Syntactic or representation changes that preserve runtime semantics (e.g., parameter renames, neutral rewrites).
- **Q3 (Expr Changed / Behavior Changed)**: Semantic changes where both AST lowering and runtime outputs diverge.
- **Q4 (Expr Unchanged / Behavior Changed)**: Measured as $0$ on this corpus. (Observed fact for pure closed SMA lowering; not proved in general).

A coarse feature like `CoarseDeltaExpression` cannot differentiate Q2 from Q3, triggering persistent structural contradictions. `PSPerception` searches the space of expression features to isolate the minimal basis that separates behavior-preserving transforms from behavior-altering transforms.

---

## 5. Runtime Predicate Synthesis & Live ETS Materialization

Gate 6 composes existing features into a new predicate and installs it in the live runspace:

1. **Predicate Synthesis**: Evaluates compositions of atomic features using logical operators ($\text{Or}, \text{And}, \text{Not}$). Identifies that while no single feature is sufficient, $\text{Or}(\text{BinderOperationChanged}, \text{ConstantValueChanged})$ achieves zero contradictions and zero held-out error with minimal complexity.
2. **ETS Dynamic Installation**: The synthesized predicate is materialized into the live PowerShell runspace using `Update-TypeData` with dynamic `ScriptProperty` definitions registered under the `System.Management.Automation.ScriptBlock` type hierarchy.
3. **DLR Callsite Rule Invalidation**: Because PowerShell's member binder (`PSGetMemberBinder`) enforces instance-level type table restrictions, **pre-existing, already-compiled `ScriptBlock` instances immediately resolve the new predicate property at runtime** without recompilation or AST rewriting.
4. **Reversible Removal**: `Remove-TypeData` removes the synthesized property from the runspace's type table.

---

## 6. Verification & Execution

To execute the verification harness:

```powershell
pwsh -NoProfile -File tests/Verify.ps1
```

All build outputs and temporary run receipts default to `$env:LOCALAPPDATA\Build\PSPerception\` in compliance with NIST SP 800-53 CM-8.

---

## 7. Relation to Prior Work & Primary Research

Each mechanism in `PSPerception` is anchored in established research literature. This repository reimplements and evaluates them inside SMA; it does not claim the underlying learning principles as new.

| Domain / Publication | Core Mechanism | Transfer to PSPerception | Limits / Non-Transfer |
| :--- | :--- | :--- | :--- |
| **Representation & Grammar Learning**<br>Angluin (1987), *Information and Computation* 75(2): 87–106 ($L^*$) | Minimally adequate teacher; observation table distinguishing states via suffixes; counterexamples expand table dimensions. | Separating parametric tuning from structural insufficiency; counterexamples force representation expansion ($\mathcal{R}_0 \to \mathcal{R}^*$). | Angluin assumes an active oracle answering arbitrary queries over $\Sigma^*$; PSPerception operates on logged empirical experience. |
| **Structural Transformations & Semantic Verification**<br>Pnueli, Siegel, Singerman (1998), *TACAS '98*, LNCS 1384: 151–166 | Translation validation: checking individual compiler target outputs against sources via refinement relations. | Untrusted proposal engine with independent deterministic verification gate before admission. | Pnueli uses synchronized transition relations; PSPerception currently uses empirical execution replay and quadrant tables. |
| **Structural Equivalence Search**<br>Tate et al. (2009), *POPL 2009*: 264–276; Willsey et al. (2021) | Equality saturation over e-graphs to explore equivalent structures without destructive phase ordering. | Non-destructive structural exploration under cost models. | E-graphs saturate using proven sound rewrite rules; PSPerception learns candidate distinctions whose semantic impact is initially unknown. |
| **Reusable Abstraction Discovery**<br>Bowers et al. (2023), *POPL 2023* (Stitch); Ellis et al. (2021), *PLDI 2021* (DreamCoder) | Top-down branch-and-bound library learning via compression metrics; wake-sleep separation of proposal models and symbolic libraries. | Discovering reusable composite predicates (`Or(A, B)`) from corpus experience; separating statistical proposers from verified symbolic libraries. | Stitch and DreamCoder operate on lambda calculus AST term trees; PSPerception handles multi-level representations (AST, DLR Expression lowering, ETS). |
| **Provenance-Preserving Compilation**<br>Leroy (2009), *CACM* 52(7): 107–115 (CompCert) | Multi-pass verified compilation preserving simulation relations and structural provenance across lowering passes. | Strict traceability between authored source, tokens, AST, LINQ expressions, and runtime behavior; persistent logical identity owns structure. | CompCert is a static, verified C-to-ASM compiler in Coq; PSPerception operates dynamically in a live managed runtime host (.NET/SMA). |

---

## 8. Status: Implemented Capabilities vs. Remaining Proposals

To maintain strict epistemological rigor, implemented capabilities must be explicitly separated from proposed future directions.

### What Is Implemented & Verified
- Parametric error calibration under sufficient representations (Gate 1).
- Bounded greedy and exhaustive feature selection resolving structural residuals (Gates 2, 4, 5).
- Rejection of invalid/spurious model proposals via deterministic ledger replay (Gate 3).
- Feature extraction over authentic lowered DLR Expression trees from SMA (Gates 4, 5).
- Synthesis of composite boolean predicates (`Atom`, `Not`, `And`, `Or`) evaluated against exhaustive optimum baselines (Gate 6).
- Live runtime predicate materialization into PowerShell ETS with callsite invalidation and reversible rollback (Gate 6).
- Bounded process-death state reconstruction using `.psd1` mutation journals, restoring tokenizer states and rolling back via exact inverses (Gate 7).
- In-memory provenance graph recording live state transitions, kept and rejected moves, and replay from scratch (`src/Store.ps1`, Gate 8).
- Counterexample-guided percept refinement loop with attribute differencing pruning at combination depth $\le 2$, strictly ordered lexicographic gates, and chronological backtracking to the most recent kept state (`src/Refine.ps1`, Gate 8).
- Versioned live receipts exchange contract ([`docs/EXPERIMENT-RECORD-CONTRACT.md`](docs/EXPERIMENT-RECORD-CONTRACT.md)).

### Remaining Proposals & Unimplemented Work
- **Autonomous End-to-End Pipeline**: Currently, the refine loop executes on candidate batches; continuous autonomous integration with live compiler streams is future work.
- **Reflective Tokens & Evolving Grammar**: Modifying token definitions or parsing grammars dynamically at runtime beyond SMA `DynamicKeyword` is unimplemented.
- **General Structural AST Mutation Search**: Search is currently bounded to feature selection and boolean compositions; arbitrary AST rewriting under semantic admission is unimplemented.
- **Dependency-Directed Backtracking**: The refine loop backtracks chronologically. Walking recorded justifications back to the culprit assumption (Doyle TMS, de Kleer ATMS) and minimizing the culprit set by subset search (delta debugging) is unimplemented.
- **Memory-Layout Optimization**: No memory-layout or cache-locality optimization is performed.
- **Managed-Assembly Promotion via PSLowering**: Compiling stable learned percepts into persisted, managed assembly regions via `PSLowering` is the intended compilation target.
