# Expectation provenance and analogical proposals

PSPerception refines its predictive representation. Domain correctness is one
judge; retained explanation structure and the effort required to propose a
useful change are separate measurements. Phonemization and language execution
supply observations and fixed domain gates. Neither defines this core.

`New-PerceptExpectation` snapshots a specimen identity, representation identity,
predicted outcome, active assumptions, and their justification graph. An
optional outcome distribution must be explicitly supplied and normalized.
It is not inferred from a winning prediction. Supplying probabilities does not
establish their calibration.

`Measure-PerceptSurprise` records prediction mismatch and, where support was
declared, `-log2 P(observed)`. An outcome outside the declared support remains
unmeasured; it is distinct from an explicitly declared zero probability.
No prior/posterior belief change is measured.

`Get-SurpriseAttribution` walks the active justification dependencies. These
assumptions are implicated in the prediction, not proved causes of failure.
Relational claims become a bounded graph query. Inactive claims are excluded.
Determining which implicated assumption failed requires further observations
or counterfactual checks.

`Find-PerceptRoleBinding` aligns directed relation graphs through a bijection
between their roles. Relation names remain semantic constraints; role names
may change. Edge order is irrelevant. A matching bag of relations with different
topology fails. Ambiguous mappings and exhausted budgets produce no binding.
This is exact structural alignment, not approximate similarity or semantic
understanding.

`Get-AnalogicalPerceptProposals` retrieves explanation-bearing mutations from
the current provenance path and binds their arguments to the query roles.
The proposal retains its source node and evidence references. Abandoned
branches do not become active knowledge. Ancestry and binding work have separate
bounds. Retrieval does not perform admission.

`RepresentationMutation.Pattern` and `.Evidence` retain the relation structure
and supporting specimen identities. Store transitions snapshot those fields
and arguments rather than sharing mutable proposal inputs. Existing feature
mutation replay remains unchanged.

Rejected proposal evidence can be reused only under the same provenance state,
bounded primitive observation snapshot, runtime identity, and authored admission
implementation. `Get-PerceptProposalHistory` compares mutation arguments exactly
and reports the source rejection nodes. The refinement loop skips a previously
evaluated strict fitness failure under that scope. Exhausting a neutral-move
budget is not a reusable rejection. Unsupported observation types disable this
reuse rather than acquiring an approximate identity. Search counters distinguish
candidate evaluations from reused rejection evidence.

The gate demonstrates two candidate evaluations becoming one on continuation
from an actual rejected proposal, with the same final admitted result. This is
same-context reuse, not held-out analogical search reduction or intuition.

The gate `tests/Gate9-InferenceContracts.ps1` checks these contracts with
independently specified expected values and graph mappings. Its fixtures
establish mechanics only. They do not establish phonemizer correctness,
TypeScript execution, held-out predictive lift, reduced search effort,
automatic abduction, learned proposal preferences, process-death explanation
reconstruction, consolidation, or CoreLib lowering.

The existing refinement loop still uses its original predictor and fixed
grammar. These interfaces do not silently change that admission policy.
Connecting attributed surprises to proposal selection requires explicit
domain observations, regression gates, and transfer evidence. A missing
measurement must not be treated as success.
