# ChangeModel Agent Guidance & Architectural Baseline

> Every capability claim names a gate.  
> A passing producer/reader pair is not independent evidence.  
> State unproved work as unproved.  
> Parser acceptance does not establish understanding or semantic equivalence.  
> Changed token classification does not establish successful compilation.  

---

## 1. Authoritative Intent

ChangeModel concerns changes in program representation. Its larger intended direction is a self-revising representation learner:

- **Traceable Representation Layers**: Authored source, tokens, AST, semantic structure, and runtime behavior remain distinct and traceable.
- **Error vs. Incapacity**: Distinguish incorrect predictions (parametric error) from a representation incapable of expressing the observed distinction (structural residual / representational insufficiency).
- **Admitted Structural Search**: Search over structural mutations under deterministic semantic admission.
- **Provenance Retention**: Preserve provenance and expandable underlying structure across transformations.
- **Reusable Abstraction Discovery**: Learn reusable distinctions and abstractions from accumulated experience.
- **Persistent Logical Identity**: Stable structures may eventually become compiled managed regions; the persistent logical structure, not the emitted assembly, owns identity.
- **Proposal Separation**: A statistical model or transformer is optional proposal/observation machinery, not the definition of the system.

This intent is not permission to claim those later capabilities exist.

---

## 2. Architectural Boundaries & Retired Terminology

- **Persistence & Replay as Support Mechanisms**: "World tape" is NOT the intended architecture. Terminology such as "world tape" and "worldview" is retired from active architectural guidance. Persistence and replay logs (`.psd1` mutation journals) are support mechanisms for process-death state reconstruction, not the model, learning objective, or product. Do not replace this with newly invented branding or framework wrappers.
- **Core Representational Fitness**: Fitness is evaluated across:
  1. *Admission*: Strict deterministic syntax and semantic validity under host rules.
  2. *Reconstructibility*: Deterministic bidirectional restoration without loss of provenance.
  3. *Structural Usefulness*: Resolving causal ambiguities and separating distinct runtime behaviors.
  4. *Held-Out Generalization*: Predicting outcomes on unseen specimen instances under explicit support.
  5. *Economy*: Minimal complexity among equally predictive candidate representations.
  6. *Stability*: Invariance under non-semantic mutations and reversible uninstallation.
- **Observation vs. Definition**: Execution timing is a separate empirical observation—not the definition of representational fitness. A preference is not semantic proof; a missing measurement is not zero; a runtime cost is not a parse failure.
- **Rejection of Raw-Byte Triviality**: Reject trivial "consume everything as raw bytes" success claims. Byte sequences conflate syntax, structure, and execution semantics.

---

## 3. Project Isolation & Data-Only Experiment Ingestion

- **Strict Repository Boundary**: Agents work strictly within `C:\Dev\ChangeModel`. Never reach into, import, edit, build, or depend on other project checkouts under `C:\Dev`.
- **Decoupled Experiment Ingestion**: Other projects may export data describing their experiments. ChangeModel must not reach into those projects or become their runtime dependency.
- **Contract Adherence**: External experiment ingestion adheres strictly to the versioned, data-only contract defined in [`docs/EXPERIMENT-RECORD-CONTRACT.md`](docs/EXPERIMENT-RECORD-CONTRACT.md).
- **Zero Execution of External Records**: Imported experiment records are data-only specifications. Never execute code embedded in records or evaluate dynamic strings from imported data.

---

## 4. Execution & Code Hygiene Constraints

- **File-Based Execution**: Run PowerShell code exclusively from script files with `pwsh -NoProfile -File <script.ps1>`.
- **Prohibited Toolchains & Dynamic Evaluation**: Zero Python, C#, Roslyn, `Add-Type`, `Invoke-Expression`, or encoded commands.
- **Build Separation (NIST SP 800-53 CM-8 / CM-2)**: Never place transient build artifacts, caches, logs, or emitted files in the repository source tree. Redirect all transient outputs to `$env:LOCALAPPDATA\Build\ChangeModel\`.
- **Change Control**: Back up affected files prior to modification. No Git history rewriting or pushing.
- **Zero AI Attribution**: Omit attribution phrases, AI tool references, and decorative framing in code, documentation, and commits.
