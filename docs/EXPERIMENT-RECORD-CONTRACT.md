# Experiment Record & Live Receipt Contract

**Module**: `Dev.MansfieldPlumbing.PowerShell.Perception`  
**Governing Boundary**: Live in-memory object and exchange contract. Zero JSON.

---

## 1. Overview & Architectural Role

Other projects may export data describing their empirical experiments, structural transformations, and evaluation outcomes. `Dev.MansfieldPlumbing.PowerShell.Perception` must never reach into external project checkouts or act as their runtime dependency.

All evaluation receipts and experiment records in `PSPerception` are represented as **live in-memory PowerShell objects** (`PerceptionReceipt`). Serialization to JSON or text bloat is prohibited in live operations.

Key invariants:
- **Live In-Memory Objects**: Receipts are instantiated directly as strongly-typed runtime records (`PerceptionReceipt`).
- **No JSON**: JSON schemas and serialized payloads are retired. Live objects preserve full runtime fidelity and object identities.
- **Reference Over Bulk**: Large artifacts (AST trees, runtime tokens, lowered expression leaves) are referenced via cryptographic digests (SHA-256) or typed object references, never serialized bulk.
- **Strict Distinction of Observation Types**: Observations distinguish semantic checks, compiler admissions, behavioral outputs, runtime performance, and subjective human judgments:
  - A pairwise preference is not semantic proof.
  - A missing measurement is not zero.
  - A runtime performance cost is not a parse failure.
- **Steering vs. Retention**: The delta (reference minus candidate) only steers the search; percepts are what the engine keeps. Backtracking is dependency-directed.

---

## 2. Live Receipt Specification

Every evaluation step produces a live receipt object with the following fields:

| Field | Type | Description |
| :--- | :--- | :--- |
| `case` | `string` | Unique identifier or description of the specimen / test case under evaluation. |
| `reference choice` | `object` | The reference/oracle decision, classification, or ground-truth output for this specimen. |
| `candidate choice` | `object` | The candidate representation's decision, classification, or predicted output. |
| `first divergent percept` | `string` | The specific percept/feature where candidate evaluation diverged from the reference (or empty if aligned). |
| `delta` | `object` | The localized divergence (reference minus candidate) steering the search. |
| `proposal` | `object` | The proposed reversible mutation / percept operation evaluated to resolve the delta. |
| `before` | `object` | The representational state / measure before the proposal was applied. |
| `after` | `object` | The representational state / measure after the proposal was applied. |
| `outcome` | `string` | The gate decision on the proposal: `kept`, `rejected`, or `inapplicable`. |
| `compiled consequence` | `object` | The compiled consequence handed to `PSLowering` to compile into CoreLib-only code (or materialized runtime state). |

---

## 3. Enumerations and Controlled Vocabularies

### Outcome Status
- `kept`: The candidate satisfied all strictly ordered lexicographic gates, resolving contradictions or improving prediction without violating complexity invariants.
- `rejected`: The candidate failed lexicographic gating (induced higher contradictions, failed to reduce error, or increased complexity without resolving contradictions). Reverted immediately.
- `inapplicable`: The candidate mutation was structurally invalid or violated stated preconditions for the target coordinates.

### Classification Categories
- `representation collision`: Two distinct observations produce identical condition keys under current percepts but yield differing reference outcomes. Solved by proposing candidates from differing attributes at combination depth $\le 2$.
- `wrong value`: Condition keys are unique (zero contradictions), but predictive parameters/magnitudes are uncalibrated. Solved by parametric regression/calibration.
- `missing operation`: An operation, keyword, or action is entirely unhandled by the current grammar.

---

## 4. Integration with Store Provenance Graph

Live receipt objects are recorded directly into `src/Store.ps1` (`PerceptionStore.Receipts`). Each receipt corresponds to a state transition in the in-memory provenance graph (`PerceptionProvenanceNode`), linking:
- `Parents`: Preceding representational states.
- `PerceptsIntroduced`: The percepts introduced by the proposal.
- `JustifyingContradictions`: The colliding observations that triggered the proposal.
- `Dependents`: Subsequent states branching from this point.
- `DeltaBefore` / `DeltaAfter`: Measured metrics before and after the move.
- `Outcome`: `kept`, `rejected`, or `inapplicable`.

Replaying the store from scratch walks kept transitions and reproduces the exact final representation and runtime state without external dependencies.
