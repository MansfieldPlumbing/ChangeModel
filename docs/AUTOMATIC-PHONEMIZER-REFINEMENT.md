# Automatic phonemizer refinement

Gate: `tests/Gate11-AutomaticPhonemizer.ps1`.

PSPerception autonomously selected, admitted, reused, and stopped on two
transferable phonemizer percepts through `Initialize-Phonemizer`,
`Invoke-PerceptRefine`, and `Get-SmaPhonemes`. The gate starts with a fresh store;
it does not install a percept or call an analogy helper to construct the gain.

## Frozen receipt

```text
Mapped diagnostic:
67.99% → 73.13% → 77.34%

Percept 1:
determiner context → NOUN
+62 / -1 diagnostic
+6 / -0 lexically disjoint admission

Percept 2:
infinitival context → VERB
+52 / -2 diagnostic
+4 / -0 lexically disjoint admission

Total:
+9.35 pp micro
+111 net fixes

Removal:
exact baseline restored

Terminal search:
2 → 0 evaluations via retained rejection memory
```

| Iteration | Micro | Macro | Candidate evaluations | Retained complexity |
|---|---:|---:|---:|---:|
| 0 | 67.98652064026959% | 68.2500580227853% | 0 | 0 |
| 1 | 73.12552653748946% | 73.33040696677061% | 4 | 1 |
| 2 | 77.33782645324347% | 77.53478844387934% | 3 | 2 |

Admission gains reached six construction-excluded lexical identities in the
first iteration and three in the second. These counts are not additive unique
identity counts. The gate checks exact whole-corpus output restoration after
removal, the unchanged terminal representation, two reused rejections, lexical
disjointness enforcement, and the exact trajectory above.

## Reproduction

Run the gate as a standalone file:

```powershell
pwsh -NoProfile -File tests/Gate11-AutomaticPhonemizer.ps1
```

The default inputs are under `$env:LOCALAPPDATA\Build\PSPerception\inputs`:
`WikipediaHomographData\data` and `misaki\us_gold.json` / `us_silver.json`.
The gate pins their SHA-256 identities before loading them. The evaluation
tree identity hashes the UTF-8, LF-separated list of sorted file names and
their SHA-256 hashes. Missing or changed inputs fail the gate; no dependency
download or restore occurs during execution. Alternate input paths must have
the same content identities. CSV and JSON receipts go only under the project
build directory.

The existing `tests/Verify.ps1` runner enables this slower, input-dependent gate
with `PSPERCEPTION_PHONEMIZER_GATE=1`. It dispatches the gate using a fresh
`pwsh -NoProfile -File` process.

The former build-only `Verify-Cycle.ps1` assessment wrapper dot-sourced
`Run-Cycle.ps1`. It encountered a parser exception before learning and is
retired, not a supported product or test entrypoint. Its root cause remains
unresolved. This distinction does not prohibit dot-loading the product's
function-definition file, which the standalone gate uses successfully.

Measured runtime: PowerShell 7.7.0-preview.3, .NET 11.0.0-preview.6.
This receipt is not RC1 evidence. Execution requires Full Language Mode for
the existing managed SMA parser and repository classes; no host protection
or language-mode setting is changed by the gate.

## Measurement boundaries

The diagnostic corpus contains 1,615 cases. This gate conservatively maps
dataset sense labels to lexicon phone alternatives, then requires a visible
ambiguous target. It scores 1,187 cases and leaves 428 unscored. It freezes
that coverage rather than silently assigning missing references.

Construction and admission each contain 128 cases. Lexical identities are
partitioned by SHA-256, and specimen hashes determine the fixed case order.
Admission identities are excluded from construction. Admission is consulted
at each iteration, so it is a repeated admission slice, not an untouched
final validation corpus. The full 1,187-case result is diagnostic and includes
both partitions. It is not an end-to-end comparison against Misaki or the
historical approximately 91.7% WORDID classification result.

The learner selects effects from construction errors using existing context
observables. It does not invent those observables. It admits at most one
percept per iteration, requires positive construction lift, at least two net
admission fixes across two excluded identities, and at most 1% admission
regressions. No target lexical identity appears in either retained percept.
Terminal rejection reuse is same-evidence memory, not a new proof of unseen
analogical search reduction. Core Gates 1/2/3/8/9/10 remain separate checks.

`NoAdmissibleCandidateInCurrentPerceptLanguage` means no available candidate
passed the current gate. It does not mean the residual errors are solved.
Unexpected-output reduction is recorded; calibrated surprisal in bits is
unmeasured. WORDID correctness and emitted-phone correctness remain distinct
metrics.
