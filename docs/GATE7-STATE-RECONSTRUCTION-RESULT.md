# Gate 7 Result: VIABLE (Bounded State Reconstruction)

Question: Can PSPerception carry a compact, inspectable, replayable history of
representational growth, derived from real JS2PS evidence, and use upstream SMA
machinery to reconstruct the same runtime tokenizer state after process death?

Answer, bounded by `tests/Gate7-StateReconstruction.ps1`: **VIABLE**.

The mutation journal survives process death and reconstructs deterministically:
- The runtime state digest, SMA tokenization digest, and LINQ availability vectors are identical in a
  fresh process that never saw the initial learning pass.
- The exact inverses return SMA to its pristine state.
- Two complete runs produced identical digests and identical mutation journal bytes.
- Persistence and replay journals are support mechanisms for state reconstruction across process boundaries,
  not the model, learning objective, or product.

## Evidence

- **Source**: JS2PS `485044dee8e797386977e4f780ec943ad7c6b9b9`, pinned `ogl@1.0.11`
  files (npm SHA-512 integrity verified), unmodified. Training specimen:
  `extras/Box.js`. Held out: `math/Vec3.js`, `math/Mat4.js`.
- **Lexer Probe**: JS2PS `tools/Observe-SmaPerception.ps1`. Units are SMA's own tokens
  that spell one IdentifierName: 180 training units and 432 held-out units.
- **Reference Model**: `ecma262.strict-binding-identifier`: in strict-mode Script code, is the
  word a ReservedWord that cannot be a BindingIdentifier (ECMA-262
  `sec-keywords-and-reserved-words`, `sec-identifiers-static-semantics-early-errors`)?
  The authority is Node v22.22.2's parser (`vm.Script`) on a probe built from the
  token text. The specimen is never edited or executed.
- **Specimen Set**: `evidence/js2ps-ogl-lexical.json`, SHA-256
  `0F8579250E5D9C31BAC80E6FD10E83A1AAE29975576E94B57659A0D7EB39452C`.

## What Was Learned

1. **Not Even Wrong**: Under pristine SMA (S0), no subset of SMA's native tokens
   (`SmaTokenKind`, `SmaKeywordFlag`, `SmaCommandNameFlag`) separates the reference model's
   outcomes. The exhaustive baseline produces 176 contradictions on the 180 training
   units. SMA tokenizes `export`, `import`, `const`, `let`, `new` and `super` identically
   to ordinary identifiers.
2. **Representation Growth**: PSPerception's `Invoke-RepresentationSearch`
   adds feature `Text` and achieves 0 contradictions. Exhaustive search
   confirms it: 8 search evaluations against 16 exhaustive combinations.
3. **Materialization**: The learned distinction (words the reference marks reserved
   that SMA's native tokens did not) is composed into SMA as eight
   `DynamicKeyword` entries: `class`, `const`, `export`, `extends`, `import`, `let`,
   `new`, `super`.
4. **Altered SMA Tokenization**: SMA's token classification of the unmodified source
   changes. With native features alone:

   | Specimen Set | S0 Contradictions | S1 Contradictions |
   | :--- | ---: | ---: |
   | Training | 176 | 7 |
   | Held-Out | 366 | 332 |

## Cryptographic Digests

| State / Artifact | SHA-256 Digest |
| :--- | :--- |
| S0 Runtime State (fresh process, both runs) | `79D1D4D158B397B7C0041C898DE66FA4A2BF62D05EAC3F2B592D0E9C396FBADA` |
| S1 Runtime State (learned, and replayed in a fresh process) | `69A80AF5D57099776C238FCC13488208F70FEBDC130F05CF28F32B5ABA659A4F` |
| S0 SMA Tokenization | `53A634898A52FBC8BE2892AA6AD9013F3F3E34EF74F536DFD30856A6A87B432E` |
| Mutation Journal (`mutation-journal.psd1`) | `0A26A9BBF9BEEC387CFE8FB9A1D019B7727485D2C1505E62573A2A3F7E5F6223` |

The runtime state digest covers:
- The PowerShell version and SMA module version ID;
- The representation's active features;
- Registered `DynamicKeyword` entries with their modes;
- SMA's tokenization of all three specimens;
- The reference model outcomes.

## Gate Checks

The two phases ran in separate `pwsh` processes, and each check passed:
- The replay process read identical journal bytes;
- Fresh S0 equals learned S0;
- S1 state digest, tokenization digest, and LINQ availability were reconstructed;
- SMA tokenization differs between S0 and S1;
- Rollback restores S0 state and tokenization digests and leaves zero `DynamicKeyword` entries registered.

## Explicit Non-Claims

- **LINQ and Assemblies**: No specimen reaches LINQ. All three specimens still produce parse
  errors under S0 and S1 (10, 25, and 48), so the LINQ comparison covers
  availability only, and nothing is persisted as a compiled managed assembly.
- **Semantic Understanding**: Parser acceptance does not establish semantic equivalence or understanding.
- **Residuals**:
  - On training, 7 contradictions remain. Five `new` and one `extends` occurrences
    arrive as tokens that `DynamicKeyword` does not reach. The pinned tokenizer
    consults the static keyword table first (`tokenizer.cs:4443`) and dynamic
    keywords only on select scan paths (`:4449`, `:3472`).
  - On held-out files, most of the residual is `this` (81 units) plus one
    `typeof`. Both are reserved but absent from `Box.js`: a vocabulary learned
    from one specimen covers only the tokens observed in its support.
- **Case Sensitivity**: `DynamicKeyword` is case-insensitive while ECMAScript is not.

## Reproduction

```powershell
$env:JS2PS_ROOT = '<JS2PS checkout at 485044d>'
pwsh -NoProfile -File tests/Gate7-StateReconstruction.ps1
```

Generated mutation journals and receipts are redirected to `$env:LOCALAPPDATA\Build\PSPerception\gate7\` by default and are not committed.
