# ChangeModel

> **"Every capability claim names a gate."**  
> **"A passing producer/reader pair is not independent evidence."**  
> **"State unproved work as unproved."**

---

## 1. Executive Summary & Epistemological Axioms

`ChangeModel` is an experimental framework in pure PowerShell (System.Management.Automation / SMA). It separates **parametric error** ("wrong") from **representational insufficiency** ("not even wrong"), searches for a representation that removes the insufficiency, and materializes the result in a live SMA runtime through upstream extension points (ETS type data, `DynamicKeyword`).

The aim is a learning component inside PowerShell/SMA that grows its own perception of inputs over time. The gates below bound what is demonstrated so far: small, hand-built or single-specimen corpora, and search methods that are established in the literature (see [Section 7](#7-relation-to-prior-work)). The PowerShell engineering is this repository's own contribution; the learning methods are not new.

### The Two Modes of Failure
1. **Wrong (Parametric Error)**:  
   Given a representation $\mathcal{R}$ whose feature coordinate space cleanly separates all distinct behavioral states ($\text{Contradictions} = 0$), the model's predictive function parameters or weights are suboptimal ($\text{PredictionError} > 0$).  
   *Remedy*: Standard parameter tuning or gradient updates on observed experience eliminate error on held-out data.
2. **Not Even Wrong (Structural Contradiction)**:  
   The representation $\mathcal{R}_0$ projects causally distinct world states onto identical coordinate points, producing mutually exclusive transitions from identical feature vectors ($\text{Contradictions} > 0$). No amount of parametric regression, weight optimization, or statistical scaling can eliminate this error—the model suffers from a **structural residual**.  
   *Remedy*: Representation search and concept synthesis ($\mathcal{R}_0 \to \mathcal{R}^*$) to discover missing causal dimensions.

---

## 2. The Six Empirical Verification Gates

Every claim in `ChangeModel` corresponds to an executable verification script under `tests/`. Passing tests are the sole acceptable proof of capability.

| Gate | Name | Executable Gate | Invariant Proven |
| :--- | :--- | :--- | :--- |
| **Gate 1** | **Wrong** | [`tests/Gate1-Wrong.ps1`](tests/Gate1-Wrong.ps1) | $\text{Contradictions} = 0$, $\text{InitialError} > 0 \implies \text{HeldOutError} = 0$ after parameter calibration. The representation is sufficient; the model was merely wrong. |
| **Gate 2** | **Not Even Wrong** | [`tests/Gate2-NotEvenWrong.ps1`](tests/Gate2-NotEvenWrong.ps1) | Impoverished $\mathcal{R}_1 = \{X\}$ induces contradictions ($\text{Contradictions} > 0$). Bounded search over candidate features discovers $\{X, \text{Direction}\}$ with zero contradictions and minimal complexity. |
| **Gate 3** | **Model Proposal & Replay** | [`tests/Gate3-ModelProposal.ps1`](tests/Gate3-ModelProposal.ps1) | A statistical or learned proposer suggests representation mutations (`AddFeature`, `RemoveFeature`, `Combine`), but proposals must pass independent, deterministic oracle replay. Proposals that do not strictly reduce contradictions are rejected. |
| **Gate 4** | **SMA Representation Revision** | [`tests/Gate4-SmaNotEvenWrong.ps1`](tests/Gate4-SmaNotEvenWrong.ps1) | Extends structural contradiction detection to authentic PowerShell AST lowering and DLR LINQ expression tree generation. |
| **Gate 5** | **Contentful SMA Delta** | [`tests/Gate5-ContentfulDelta.ps1`](tests/Gate5-ContentfulDelta.ps1) | Demonstrates that coarse representation $\mathcal{R}_0 = \{\text{CoarseDeltaExpression}\}$ conflates behavior-preserving and behavior-altering AST transformations ($\text{Contradictions} = 4$). Bounded search over authentic SMA expression features discovers the minimal zero-contradiction feature pair $\{\text{BinderOperationChanged}, \text{ConstantValueChanged}\}$ and classifies all 4 held-out pairs correctly (9 training pairs). |
| **Gate 6** | **Runtime Concept Invention** | [`tests/Gate6-RuntimeConceptInvention.ps1`](tests/Gate6-RuntimeConceptInvention.ps1) | Synthesizes a composite predicate $\text{Or}(\text{BinderOperationChanged}, \text{ConstantValueChanged})$ from atomic primitives, verifies it against execution evidence, and materializes it into the live runspace via PowerShell Extended Type System (`Update-TypeData`). Proves that pre-compiled `ScriptBlock` instances dynamically resolve the newly invented concept without recompilation, and removes it with `Remove-TypeData`. **Known defect:** `Invoke-ConceptSearch` sets `ReachedOracle = $true` without comparing against an exhaustive result, so criterion 4 cannot fail; that criterion is unproved until fixed. |
| **Gate 7** | **World Reconstruction After Process Death** | [`tests/Gate7-WorldReconstruction.ps1`](tests/Gate7-WorldReconstruction.ps1) | Learns one representational delta from real JS2PS evidence (unmodified OGL source as SMA perceives it, judged by an ECMAScript oracle), records it as a replayable `.psd1` world tape (`src/WorldTape.ps1`), rebuilds the identical world in a separate `pwsh` process, and rolls back to the pristine state exactly. Needs `JS2PS_ROOT`. Result and limits: [`docs/GATE7-RESULT.md`](docs/GATE7-RESULT.md); upstream audit: [`UPSTREAM-AUDIT.md`](UPSTREAM-AUDIT.md). |

---

## 3. Subsystem Architecture

```text
ChangeModel/
├── AGENTS.md                                  # Operational constraints and epistemic boundaries
├── README.md                                  # Architectural overview and gate verification guide
├── docs/
│   └── PROVENANCE.md                          # Tracing AST search, reflection probes, and SMA internal members
├── probes/
│   ├── Observe-SmaLowering.ps1                # Deep inspection of internal Compiler.Compile and LINQ trees
│   └── Measure-SmaDeltas.ps1                  # Quantitative divergence probe across AST lowering stages
├── src/
│   ├── World.ps1                              # Canonical state transition engines
│   ├── Representation.ps1                     # Feature extraction coordinate mapping and projection
│   ├── Experience.ps1                         # Contradiction counting, structural residual auditing, and history logs
│   ├── Prediction.ps1                         # Parametric delta predictors over feature vectors
│   ├── Proposal.ps1                           # Mutation DSL (AddFeature, RemoveFeature, Combine) and proposal engine
│   ├── Search.ps1                             # Bounded hill-climbing search with exhaustive oracle verification
│   ├── SmaDataset.ps1                         # Authentic SMA AST/Token/LINQ lowering dataset generator
│   ├── SmaContentfulDataset.ps1               # Multi-quadrant adversarial corpus preserving AST fingerprints
│   ├── ExpressionFeatures.ps1                 # Deep reflection extractors for DLR binders, constants, and node types
│   └── ConceptSynthesis.ps1                  # Concept synthesis, sufficiency scoring, and live ETS materialization
└── tests/
    ├── Verify.ps1                             # Master harness executing all gates sequentially
    ├── Gate1-Wrong.ps1                        # Parametric tuning gate
    ├── Gate2-NotEvenWrong.ps1                 # Structural residual & representation revision gate
    ├── Gate3-ModelProposal.ps1                # Untrusted proposer / deterministic replay gate
    ├── Gate4-SmaNotEvenWrong.ps1              # SMA AST expression lowering proof
    ├── Gate5-ContentfulDelta.ps1              # Multi-quadrant SMA contentful delta proof
    ├── Gate6-RuntimeConceptInvention.ps1      # Dynamic concept synthesis & ETS live materialization proof
    ├── Gate7-WorldReconstruction.ps1          # Two-process world-tape replay and rollback gate
    └── Gate7-Phase.ps1                        # One Gate 7 phase, run in its own pwsh process
```

`src/WorldTape.ps1` writes and reads the Gate 7 world tape.

---

## 4. The Authentic SMA Lowering Oracle

Rather than mocking abstract languages, `ChangeModel` tests its representation search against authentic **PowerShell / System.Management.Automation (SMA)** compiler internals:

1. **AST to LINQ Lowering**: Probes inspect internal `Compiler.Compile` and `Compiler._endBlockLambda` via reflection on `System.Management.Automation.ScriptBlock._scriptBlockData`.
2. **Authentic Features**:
   - `BinderOperationChanged`: Detects DLR dynamic callsite binder operation shifts (e.g. arithmetic, comparison).
   - `ConstantValueChanged`: Tracks literal constant modifications across lowered expression leaves.
   - `OperandOrderChanged`: Detects non-commutative parameter re-ordering.
   - `NodeTypeChanged`: Identifies syntactic category modifications (e.g. binary expressions vs method calls).
   - `CallTargetChanged`: Detects redirection of invocations to alternate methods or functions.

### The Four Quadrants of Semantic Change
In `tests/Gate5-ContentfulDelta.ps1`, pairs of scriptblocks are evaluated across a 4-quadrant truth table:
- **Q1 (Expr Unchanged / Behavior Unchanged)**: Idempotent or identical script blocks.
- **Q2 (Expr Changed / Behavior Unchanged)**: Syntactic or representation changes that preserve runtime semantics (e.g., parameter renames, neutral rewrites).
- **Q3 (Expr Changed / Behavior Changed)**: Semantic changes where both AST lowering and runtime outputs diverge.
- **Q4 (Expr Unchanged / Behavior Changed)**: Measured as $0$ on this corpus. This is not proved in general.

A coarse feature like `CoarseDeltaExpression` cannot differentiate Q2 from Q3, triggering persistent structural contradictions. `ChangeModel` searches the space of expression features to isolate the exact minimal basis that separates behavior-preserving transforms from behavior-altering transforms.

---

## 5. Runtime Concept Invention & Live ETS Materialization

Gate 6 composes existing features into a new predicate and installs it in the live runspace:

1. **Concept Synthesis**: The engine evaluates compositions of atomic features using logical operators ($\text{Or}, \text{And}$). It identifies that while no single feature is sufficient, $\text{Or}(\text{BinderOperationChanged}, \text{ConstantValueChanged})$ achieves zero contradictions and zero held-out error with minimal complexity.
2. **ETS Dynamic Installation**: The synthesized concept is materialized into the live PowerShell runspace using `Update-TypeData` with dynamic `ScriptProperty` definitions registered under the `System.Management.Automation.ScriptBlock` type hierarchy.
3. **DLR Callsite Rule Invalidation**: Because PowerShell's member binder (`PSGetMemberBinder`) enforces instance-level type table restrictions, **pre-existing, already-compiled `ScriptBlock` instances immediately resolve the new concept property at runtime** without recompilation or AST rewriting.
4. **Removal**: `Remove-TypeData` removes the synthesized property from the runspace's type table.

---

## 6. Verification & Execution

To execute the complete gate verification harness:

```powershell
pwsh -NoProfile -File tests/Verify.ps1
```

### Expected Output:
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
  Q4 (Expr unchanged / Beh changed)  : 0
Confirmed R0 Contradictions: 4 (Structural Residual Present)
Winning Concept: BinderOperationChanged, ConstantValueChanged
GATE5_CONTENTFUL_DELTA=PASS
--- Gate 6: Runtime Concept Invention ---
Winning Concept: Or(BinderOperationChanged, ConstantValueChanged)
GATE6_RUNTIME_CONCEPT_INVENTION=PASS
```

---

## 7. Relation to Prior Work

Each mechanism in `ChangeModel` has an established counterpart. This repository reimplements them inside SMA; it does not claim them as new.

| `ChangeModel` | Established counterpart |
| :--- | :--- |
| Contradiction: identical feature vectors with different outcomes | Inconsistent decision table (Pawlak, rough sets); perceptual aliasing in reinforcement learning |
| Minimal zero-contradiction feature subset (Gates 2 and 5) | FOCUS and the MIN-FEATURES bias (Almuallim and Dietterich, AAAI 1991); rough-set reducts |
| Separating "wrong" from "not even wrong" | Parameter error versus representation inadequacy under aliasing (McCallum, Utile Distinction Memory, ICML 1993; Huang, arXiv 2608.02267, 2026) |
| Growing the perceived state space only where outcomes disagree | U-Tree (McCallum, *Reinforcement Learning with Selective Perception and Hidden State*, 1996); Feature Reinforcement Learning (Hutter, arXiv 0906.1713) |
| Composite concept `Or(A, B)` from primitives (Gate 6) | Constructive induction; predicate invention in inductive logic programming |
| Impasse, then a learned result installed so the impasse does not recur | Soar impasses, substates and chunking (Laird, arXiv 2205.03854) |
| Extending the vocabulary the system perceives and expresses | DreamCoder library learning (Ellis et al., PLDI 2021, arXiv 2006.08381) |
| Ordered structural additions, each with a history record (world tape, Gate 7) | NEAT historical markings / innovation numbers (Stanley and Miikkulainen, 2002); event sourcing |

### Open questions this repository can test

- Whether `Invoke-RepresentationSearch` finds anything FOCUS does not, on the same features. Until a gate compares them, assume it does not.
- Whether a learned change to SMA's perception improves a downstream outcome: parse errors, successful compilation, or task reward. Gate 7 changed token classification but not parse errors (10, 25 and 48 before and after).
- Whether a learned percept generalizes beyond the words it was learned from. Gate 7's `Text` percept covers only words seen in training: held-out contradictions went from 366 to 332, and the remainder is almost entirely `this` and `typeof`, which the training specimen does not contain.
