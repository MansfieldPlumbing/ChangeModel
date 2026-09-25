# ChangeModel

> **"Every capability claim names a gate."**  
> **"A passing producer/reader pair is not independent evidence."**  
> **"State unproved work as unproved."**

---

## 1. Executive Summary & Epistemological Axioms

`ChangeModel` is an empirical systems framework implemented in pure PowerShell (System.Management.Automation / SMA) that operationalizes the formal boundary between **parametric error** ("wrong") and **representational insufficiency** ("not even wrong"), and proves that an autonomous runtime can synthesize, verify, and materialize novel semantic concepts directly into a live execution environment.

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
| **Gate 5** | **Contentful SMA Delta** | [`tests/Gate5-ContentfulDelta.ps1`](tests/Gate5-ContentfulDelta.ps1) | Demonstrates that coarse representation $\mathcal{R}_0 = \{\text{CoarseDeltaExpression}\}$ conflates behavior-preserving and behavior-altering AST transformations ($\text{Contradictions} = 4$). Bounded search over authentic SMA expression features discovers the minimal zero-contradiction feature pair $\{\text{BinderOperationChanged}, \text{ConstantValueChanged}\}$ with $100\%$ held-out generalization. |
| **Gate 6** | **Runtime Concept Invention** | [`tests/Gate6-RuntimeConceptInvention.ps1`](tests/Gate6-RuntimeConceptInvention.ps1) | Synthesizes a composite predicate $\text{Or}(\text{BinderOperationChanged}, \text{ConstantValueChanged})$ from atomic primitives, verifies it against execution evidence, and materializes it into the live runspace via PowerShell Extended Type System (`Update-TypeData`). Proves that pre-compiled `ScriptBlock` instances dynamically resolve the newly invented concept without recompilation, and proves semantic reversibility when the type data is removed. |
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
    └── Gate6-RuntimeConceptInvention.ps1      # Dynamic concept synthesis & ETS live materialization proof
```

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
- **Q4 (Expr Unchanged / Behavior Changed)**: Measured as $0$ (guaranteed by pure, closed SMA compilation).

A coarse feature like `CoarseDeltaExpression` cannot differentiate Q2 from Q3, triggering persistent structural contradictions. `ChangeModel` searches the space of expression features to isolate the exact minimal basis that separates behavior-preserving transforms from behavior-altering transforms.

---

## 5. Runtime Concept Invention & Live ETS Materialization

In Gate 6, `ChangeModel` proves that conceptual invention is not merely an offline search heuristic, but can be translated into live OS/runtime reality:

1. **Concept Synthesis**: The engine evaluates compositions of atomic features using logical operators ($\text{Or}, \text{And}$). It identifies that while no single feature is sufficient, $\text{Or}(\text{BinderOperationChanged}, \text{ConstantValueChanged})$ achieves zero contradictions and zero held-out error with minimal complexity.
2. **ETS Dynamic Installation**: The synthesized concept is materialized into the live PowerShell runspace using `Update-TypeData` with dynamic `ScriptProperty` definitions registered under the `System.Management.Automation.ScriptBlock` type hierarchy.
3. **DLR Callsite Rule Invalidation**: Because PowerShell's member binder (`PSGetMemberBinder`) enforces instance-level type table restrictions, **pre-existing, already-compiled `ScriptBlock` instances immediately resolve the new concept property at runtime** without recompilation or AST rewriting.
4. **Semantic Reversibility**: Upon executing `Remove-TypeData`, the synthesized concept cleanly evaporates from the runtime, restoring the exact pristine state of the host engine.

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
