# Experiment Record Contract

**Schema Version**: `1.0.0`  
**Governing Boundary**: Data-only exchange specification.

---

## 1. Overview & Architectural Role

Other projects may export data describing their empirical experiments, structural transformations, and evaluation outcomes. `ChangeModel` must never reach into external project checkouts or act as their runtime dependency.

This document defines a minimal, versioned, data-only record format for representing structural mutation experiments as potential learning examples.

Key invariants:
- **Data-Only**: Records contain structured data only (`.json` or `.psd1` data tables). Zero executable script blocks, embedded delegates, or dynamic eval blocks.
- **Reference Over Bulk**: Large artifacts (AST dumps, audio buffers, binary blobs) must be referenced via cryptographic digests (SHA-256) and source locations, never embedded in record bulk.
- **Strict Distinction of Observation Types**: Observations distinguish semantic checks, compiler admissions, behavioral outputs, runtime performance, and subjective human judgments. Units, context, uncertainty, and evaluation contracts remain distinct:
  - A pairwise preference is not semantic proof.
  - A missing measurement is not zero.
  - A runtime performance cost is not a parse failure.
- **Non-Prescriptive**: These records are potential learning examples, not proof of an implemented learner. No fixed binary layout, universal scalar reward, ingestion framework, or external-project modifications are required.

---

## 2. Specification Schema

A valid experiment record complies with the following top-level field contract:

```json
{
  "$schema": "https://mansfieldplumbing.dev/schemas/changemodel/experiment-record-1.0.0.json",
  "schema_version": "1.0.0",
  "record_id": "<UUID or deterministic hash>",
  "timestamp_utc": "YYYY-MM-DDTHH:MM:SSZ",
  "provenance": {
    "origin_project": "<string>",
    "source_commit": "<40-char SHA>",
    "input_identity": {
      "path": "<relative/normalized path>",
      "digest_sha256": "<64-char hex SHA256>",
      "byte_length": 1234
    },
    "representation_schema": {
      "name": "<e.g. SmaExpressionTree | AstJson | CstTokens>",
      "version": "<string>"
    }
  },
  "lineage": {
    "parent_id": "<hash or null for baseline>",
    "candidate_id": "<hash of resulting candidate representation>"
  },
  "transformation": {
    "ordered_mutations": [
      {
        "sequence": 1,
        "operator": "<e.g. AddFeature | RemoveFeature | ReplaceNode | InsertDynamicKeyword>",
        "target_coordinates": "<structural address, e.g. /Block/Statements[2]/BinaryExpr>",
        "parameters": {},
        "preconditions": [
          "<precondition predicate or state assertion>"
        ]
      }
    ]
  },
  "consequences": {
    "predicted": {
      "status": "accepted | rejected | uncertain | inapplicable | unmeasured",
      "expected_outcome": "<string or numeric expectation>",
      "predicted_metrics": {}
    },
    "observed": {
      "status": "accepted | rejected | uncertain | inapplicable | unmeasured",
      "actual_outcome": "<string or numeric observed outcome>",
      "prediction_matched": true
    }
  },
  "verification": {
    "semantic_checks": [
      {
        "check_id": "<string>",
        "passed": true,
        "contract": "<formal description of invariant verified>"
      }
    ],
    "counterexamples": [
      {
        "input_probe": "<probe identifier or input description>",
        "expected": "<expected value>",
        "observed": "<observed value>",
        "description": "<structural conflict description>"
      }
    ]
  },
  "observations": {
    "compiler_admission": {
      "admitted": true,
      "errors": []
    },
    "behavioral": {
      "output_difference_detected": false,
      "details": "<description or null>"
    },
    "numerical_deviation": {
      "max_absolute_error": null,
      "rms_error": null,
      "unit": null
    },
    "performance": {
      "cpu_nanoseconds": null,
      "allocated_bytes": null,
      "measurement_context": "<warmup / cold / tier>",
      "uncertainty_margin": null
    },
    "human_judgment": {
      "judgment_type": "pairwise_preference | qualitative_rating | null",
      "evaluator_id": "<string or null>",
      "preference_winner": "<candidate | parent | tied | null>",
      "confidence": null,
      "notes": null
    }
  },
  "artifacts": [
    {
      "name": "<string>",
      "role": "<e.g. source_ast | trace_log | emitted_manifest>",
      "digest_sha256": "<64-char hex SHA256>",
      "uri_or_storage_ref": "<string>"
    }
  ]
}
```

---

## 3. Enumerations and Controlled Vocabularies

### Evaluation Status
- `accepted`: The candidate satisfied all structural preconditions and deterministic semantic admission checks, strictly improving representational sufficiency.
- `rejected`: The candidate failed semantic admission, violated invariants, induced contradictions, or failed to improve sufficiency.
- `uncertain`: The candidate produced ambiguous or incomplete observations requiring additional discriminatory tests.
- `inapplicable`: The candidate mutation was structurally invalid or violated stated preconditions for the target coordinates.
- `unmeasured`: The transformation was recorded or proposed, but target verification has not yet been executed.

### Observation Categories & Semantic Boundaries
- **Compiler Admission**: Records whether the target language/runtime compiler admitted the structure without syntax or lowering errors. A parse or lowering error is an admission rejection, not a performance cost.
- **Behavioral Equality**: Records whether black-box execution of the transformed program over valid input domains yielded identical state/output transitions.
- **Numerical / Acoustic Deviation**: Records continuous deviations (e.g., float rounding differences, DSP acoustic divergence) with explicit physical/numerical units and measurement tolerances.
- **Performance**: Records resource utilization (execution time, memory allocations) under rigorous measurement contracts (JIT warmup, GC allocation gating). Execution cost is distinct from semantic validity.
- **Human Judgment**: Captures subjective ratings or pairwise A/B listening preferences. Explicitly marked as non-semantic evidence: a human preference does not establish semantic equivalence or compiler admission.
