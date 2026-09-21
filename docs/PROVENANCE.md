# Provenance

| Component | Source Path | Commit Hash | Purpose |
| :--- | :--- | :--- | :--- |
| Representation Search Engine | C:\Dev\JS2PS\tests\Prove-AstGuidedHillClimb.ps1 | 919efd2a174218c522d1d2470117ae86f0142d72 | Bounded hill-climbing search with strict improvement and exhaustive oracle validation, adapted from AST node insertion to state feature selection. |
| Proof Discipline | C:\Dev\JS2PS\docs\HILL-CLIMBING.md | 919efd2a174218c522d1d2470117ae86f0142d72 | Separation between search heuristic and semantic correctness gate. |
| SMA Lowering Probe | `C:\Dev\PSPersistence\probes\Test-SmaCompilation.ps1` | f4c07ae96e1a49a0c4ff82421abf2795926b60f9 | Reflection machinery to reach authentic SMA expression tree via _scriptBlockData and Compiler.Compile. |

## PowerShell Source Oracle

Authoritative source tree: C:\Dev\.vendor\PowerShell
Commit: 1481b98f0079f979f658e49a7281024cc754049b

### Private SMA Members Accessed

| Source File | Declaring Type | Member | Reason ChangeModel needs it |
| :--- | :--- | :--- | :--- |
| src\System.Management.Automation\engine\lang\scriptblock.cs | System.Management.Automation.ScriptBlock | _scriptBlockData (Field) | Access to the underlying AST and compiler state for a compiled script block. |
| src\System.Management.Automation\engine\parser\Compiler.cs | System.Management.Automation.Language.Compiler | Compile (Method) | Triggers internal lowering of the AST into LINQ expressions. |
| src\System.Management.Automation\engine\parser\Compiler.cs | System.Management.Automation.Language.Compiler | CompileTree (Method) | Compiles the resulting LINQ lambda into a delegate, bypassing normal caching. |
| src\System.Management.Automation\engine\parser\Compiler.cs | System.Management.Automation.Language.Compiler | _endBlockLambda (Field) | Captures the authentic SMA expression tree root emitted during Compile. |
| src\System.Management.Automation\engine\parser\Compiler.cs (implicit) | System.Management.Automation.Language.PowerShellLoopExpression | _exprs (Field) | Allows observing child expressions of SMA's custom loop expression nodes without modifying them. |
