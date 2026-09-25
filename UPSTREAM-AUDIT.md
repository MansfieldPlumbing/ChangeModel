# Upstream audit for Gate 7

Authority: PowerShell/PowerShell `v7.7.0-preview.5`, commit
`149ab5cd6cad34869177f86ef9a3da8414f85dc6`. Paths are relative to
`src/System.Management.Automation/` unless stated. The runtime that ran the gate
was PowerShell 7.7.0-preview.5 on .NET 11.0.0-rc.1.26425.128 (SMA module version id
`ecba0531-bc70-4f8d-b8bb-aa470dca0f76`).

The requirement under test: carry an inspectable, replayable history of
representational growth, derived from real JS2PS evidence, and rebuild the same
effective worldview in a fresh process.

| Upstream mechanism | Where | Does it already solve the requirement? | Missing property, or how the spike uses it |
| --- | --- | --- | --- |
| Parser-driven tokenizer mode and rescan: `SetTokenizerMode`, `Resync` | `engine/parser/Parser.cs:499`, `:538`, `:544`; `engine/parser/tokenizer.cs:1031`, `:1039`; `Tokenizer.Mode` at `tokenizer.cs:729` | No. It is the parser's own speculation: it rescans the lookahead token when the mode changes. | Not public, not durable, and reset by `Initialize` (`tokenizer.cs:794`). Not used by this spike. |
| `DynamicKeyword` registry | `engine/parser/tokenizer.cs:71-200` | Partly. It is a public, reversible way to change what SMA's tokenizer perceives. `AddKeyword`/`RemoveKeyword` are exact inverses when the name was absent; `Push`/`Pop` save and restore the whole table. | Process-local and `[ThreadStatic]` (`:86-101`): nothing survives process death. `AddKeyword` silently overwrites (`:181-182`), so an exact inverse needs the precondition that the name is absent. The table is case-insensitive (`:82`, `:108`), while ECMAScript is case-sensitive. The static keyword table is consulted first (`:4443`), and dynamic keywords only on some scan paths (`:4449`, `:3472`). **Used** as the `Compose` realization. |
| `PSObject : IDynamicMetaObjectProvider`, deferral to a wrapped provider | `engine/MshObject.cs:47`, `MustDeferIDMOP` `:2139`, `DeferForIDMOP` `:2145` | No. It is binding delegation for live objects. | Not needed: no object crosses in this spike. It is the natural seam for future object adapters. Not durable. |
| `PSPropertyAdapter` (public) | `engine/ThirdPartyAdapter.cs:291` | No. It gives adapted property views of foreign objects. | Not needed here. Not durable. |
| TypeData and ETS with binder-rule invalidation | `engine/TypeTable.cs:3672`, `:3716`, `:3791`; `engine/runtime/Binding/Binders.cs:5061`, `:5084` | No, for history. It makes an installed concept visible to already-compiled script blocks (ChangeModel Gate 6). | The type table holds the end state only, in memory. Nothing records how an entry was learned. |
| `SessionStateTypeEntry(TypeData, bool)` into an `InitialSessionState` | `engine/InitialSessionState.cs:220`, applied at `:3597` | Partly. It is the simplest upstream way to rehydrate learned type vocabulary into a new runspace. | It rehydrates a state, not the history that produced it. Not needed here, because this spike's realization is `DynamicKeyword`. It is the replay path for ETS-realized concepts. |
| `RunspaceFactory` and runspace pools | `engine/hostifaces/ConnectionFactory.cs:84`, `:115`, `:171`, `:194`, `:217` | No. They are hosting APIs. | The gate uses a fresh process instead of a fresh runspace. That is stronger: `DynamicKeyword` state is per thread, and ETS state is per runspace. |
| Compiled script-block caches | `engine/runtime/CompiledScriptBlock.cs:57-159`, `:339-353`; script cache `:580-644` | No. | In-process only. The script cache clears itself past 1024 entries (`:630-632`). These caches are not durable cognition and are not used. |
| PowerShell data files: `Import-PowerShellDataFile` over `Ast.SafeGetValue` | `src/Microsoft.PowerShell.Commands.Utility/commands/utility/ImportPowerShellDataFile.cs:70`; `engine/parser/ast.cs:203`, `:216` | Yes, for reading. It evaluates a restricted data file without executing script. | **Used** to read the world tape. SMA has no data-file writer, so `src/WorldTape.ps1` writes one from strings, integers, booleans, arrays and dictionaries only. |
| `CodeGeneration.EscapeSingleQuotedStringContent` | `engine/lang/codegen.cs:21` | Yes, for writing string literals. | **Used** by the tape writer. |
| LINQ to persisted managed assembly | `PSPersistence` (`PersistedAssemblyBuilder`) | Yes, within PSPersistence's proven boundary. | Not exercised: no specimen reaches SMA's compiler, because all three still have parse errors under S0 and S1. PSPersistence is not broadened or copied. |

## Conclusion

No upstream facility records how a representation came to its current shape, or
survives process death. The closest are `DynamicKeyword.Push`/`Pop`, an in-memory
stack, and `TypeData` with `SessionStateTypeEntry`, which rehydrate an end state
without its history. The missing property is a durable, ordered, reversible history.
The world tape (`src/WorldTape.ps1`) supplies only that. Everything it changes in SMA
goes through upstream `DynamicKeyword` calls, and it is read back through upstream
`Import-PowerShellDataFile`.

## Pre-existing findings, not changed here

- `src/Representation.ps1` (`GetRepresentedState`) and `src/Proposal.ps1`
  (`ConvertTo-RepresentationMutation`) use regular expressions. Gate 7's new code
  uses none.
- `src/ConceptSynthesis.ps1` `Invoke-ConceptSearch` sets `ReachedOracle = $true`
  without comparing against an exhaustive result, so Gate 6's criterion 4 cannot
  fail. Gate 7 uses `Invoke-RepresentationSearch`, which does run its exhaustive
  oracle.
