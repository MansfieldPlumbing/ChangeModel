# Gate 7 result: VIABLE

Question: can ChangeModel carry a small, inspectable, replayable history of
representational growth, derived from real JS2PS evidence, and use upstream SMA
machinery to reconstruct the same effective worldview after process death?

Answer, bounded by `tests/Gate7-WorldReconstruction.ps1`: **VIABLE**.

The mutation history survives process death and reconstructs deterministically:
- the world, SMA-perception and LINQ-availability fingerprints are identical in a
  process that never saw the learning;
- the exact inverses return SMA to its pristine state;
- two complete runs produced identical fingerprints and identical tape bytes.

## Evidence

- **Source.** JS2PS `485044dee8e797386977e4f780ec943ad7c6b9b9`, pinned `ogl@1.0.11`
  files (npm SHA-512 integrity verified), unmodified. Training specimen:
  `extras/Box.js`. Held out: `math/Vec3.js`, `math/Mat4.js`.
- **Sensor.** JS2PS `tools/Observe-SmaPerception.ps1`. Units are SMA's own tokens
  that spell one IdentifierName: 180 training units and 432 held-out units.
- **Oracle.** `ecma262.strict-binding-identifier`: in strict-mode Script code, is the
  word a ReservedWord that cannot be a BindingIdentifier (ECMA-262
  `sec-keywords-and-reserved-words`, `sec-identifiers-static-semantics-early-errors`)?
  The authority is Node v22.22.2's parser (`vm.Script`) on a probe built from the
  token text. The specimen is never edited or executed.
- **Experience set.** `evidence/js2ps-ogl-lexical.json`, SHA-256
  `0F8579250E5D9C31BAC80E6FD10E83A1AAE29975576E94B57659A0D7EB39452C`.

## What was learned

1. **Not even wrong.** Under pristine SMA (S0), no subset of SMA's native percepts
   (`SmaTokenKind`, `SmaKeywordFlag`, `SmaCommandNameFlag`) separates the oracle's
   outcomes. The exhaustive oracle's best is 176 contradictions on the 180 training
   units. SMA perceives `export`, `import`, `const`, `let`, `new` and `super` exactly
   as it perceives ordinary identifiers.
2. **Representation growth.** ChangeModel's existing `Invoke-RepresentationSearch`
   adds the percept `Text` and reaches 0 contradictions. The exhaustive oracle
   confirms it: 8 search evaluations against 16 exhaustive.
3. **Materialization.** The learned distinction (words the oracle marks reserved
   that SMA's native percepts did not) is composed into SMA as eight
   `DynamicKeyword` entries: `class`, `const`, `export`, `extends`, `import`, `let`,
   `new`, `super`.
4. **Different SMA perception.** SMA's own perception of the unmodified source
   changes. With native percepts alone:

   | | S0 contradictions | S1 contradictions |
   | --- | ---: | ---: |
   | training | 176 | 7 |
   | held out | 366 | 332 |

## Fingerprints

| | SHA-256 |
| --- | --- |
| S0 world (fresh process, both runs) | `79D1D4D158B397B7C0041C898DE66FA4A2BF62D05EAC3F2B592D0E9C396FBADA` |
| S1 world (learned, and replayed in a fresh process) | `69A80AF5D57099776C238FCC13488208F70FEBDC130F05CF28F32B5ABA659A4F` |
| S0 SMA perception | `53A634898A52FBC8BE2892AA6AD9013F3F3E34EF74F536DFD30856A6A87B432E` |
| World tape (`build/gate7/world-tape.psd1`) | `0A26A9BBF9BEEC387CFE8FB9A1D019B7727485D2C1505E62573A2A3F7E5F6223` |

The world fingerprint covers:
- the PowerShell version and SMA module version id;
- the representation's features;
- the registered `DynamicKeyword` entries with their modes;
- SMA's perception of all three specimens;
- the oracle outcomes.

## Gate checks

The two phases ran in separate `pwsh` processes, and each check below passed:
- the replay process read the same tape bytes;
- fresh S0 equals learned S0;
- S1's world, perception and LINQ availability were reconstructed;
- SMA's perception differs between S0 and S1;
- rollback restores S0's world and perception and leaves no `DynamicKeyword`
  registered.

## Not claimed

- **LINQ and assemblies.** No specimen reaches LINQ. All three still have parse
  errors under S0 and S1 (10, 25 and 48), so the LINQ comparison covers
  availability only, and nothing is persisted as an assembly.
- **Semantic success.** Nothing here says SMA now understands these files.
- **Residuals.**
  - On training, 7 contradictions remain. Five `new` and one `extends` occurrence
    still arrive as tokens `DynamicKeyword` does not reach. The pinned tokenizer
    consults the static keyword table first (`tokenizer.cs:4443`) and dynamic
    keywords only on some scan paths (`:4449`, `:3472`). The exact path these
    tokens take is not yet identified.
  - On the held-out files, most of the residual is `this` (81 units) plus one
    `typeof`. Both are reserved but absent from `Box.js`: a vocabulary learned
    from one specimen covers only the words it saw.
- **Case sensitivity.** `DynamicKeyword` is case-insensitive while ECMAScript is not.
  No specimen exercised the difference.

## Reproduce

```
JS2PS_ROOT=<JS2PS checkout at 485044d> pwsh -NoProfile -File tests/Gate7-WorldReconstruction.ps1
```

Generated tapes and receipts are written to `build/gate7/` and are not committed.
