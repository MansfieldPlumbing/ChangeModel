# Inventory Analysis Report: SMA-English Baseline (Sentences 0..29 and 500-Corpus)

## 1. PowerShell-Reserved-Word Collisions (500-Corpus Survey)
Across all 500 training sentences, SMA's tokenizer identified 33 reserved keyword tokens. They map to exactly 4 distinct English words:

| Word | Occurrences | SMA Token Kind | spaCy POS | spaCy Dep | Baseline Errors | AST Behavior |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| `In` | 30 | `TokenKind.In` | `ADP` (100%) | `prep` (97%), `ROOT` (3%) | 0 errors | Enters `CommandAst` as command name, following arguments remain valid expressions |
| `While` | 1 (s.182) | `TokenKind.While` | `SCONJ` | `mark` | 1 error | Triggers `MissingOpenParenthesisAfterKeyword` (expects `while (...)`) |
| `For` | 1 (s.208) | `TokenKind.For` | `ADP` | `prep` | 2 errors | Triggers `MissingOpenParenthesisAfterKeyword` and `MissingArgument` |
| `If` | 1 (s.238) | `TokenKind.If` | `SCONJ` | `mark` | 1 error | Triggers `MissingOpenParenthesisInIfStatement` (expects `if (...)`) |

**Key Finding**:
- `In` is an unproblematic, free semantic marker: 100% of its collisions correspond to introductory prepositional phrases (`ADP`), with zero parse errors.
- Statement-initial control-flow keywords (`While`, `For`, `If`) collide with block-statement grammar, expecting parentheses. A leading sentinel (e.g. `¿ ` or `// `) neutralizes this collision completely without losing word identity.

## 2. Punctuation -> AST-Shape Mappings (30-Sentence Survey)
Punctuation in modern English interacts directly with PowerShell's parser grammar:

| Punctuation | Occurrences (in 30) | SMA Token Kind | AST Node Produced | Semantic Function in English vs SMA |
| :--- | :--- | :--- | :--- | :--- |
| `.` (period) | 33 | `Generic` | Glued to `StringConstantExpressionAst` (or standalone argument) | Terminal sentence punctuation is absorbed into the preceding word (e.g. `imagery.`), corrupting token boundary. |
| `( ... )` | 8 | `LParen`, `RParen` | `ParenExpressionAst` containing nested `PipelineAst` / `CommandAst` | **Exceptional structural match**: English parentheticals and acronym expansions (e.g. `(AWT)`, `(and successfully did so...)`) are parsed into isolated nested expression trees! |
| `,` (comma) | 26 | `Comma` | `ArrayLiteralAst` | Lists and coordinate clauses (e.g. `prolific, and`) become structured array elements `[elem1, elem2]`. When at statement head (e.g. `Rather,`), causes `MissingArgument`. |
| `"` (quote) | 7 | `StringExpandable` | `StringExpandableToken` / `ScriptBlockAst` | Encloses text in string literal; internal tokens are not exposed as individual AST elements unless replaced. |
| `-` (hyphen) | 5 | `Generic` / `Parameter` | `CommandParameterAst` or `StringConstantExpressionAst` | Hyphen before a word in command mode (e.g. `-is`, `-tis`) produces `CommandParameterAst`. When followed by comma without space, throws `MissingArgument`. |
| `'` (apostrophe) | 2 | `SingleQuote` / missing | `TerminatorExpectedAtEndOfString` error | Contractions and possessives (`don't`, `Smith's`) open unclosed string literals. |
| `;` (semicolon) | 1 | `Semi` | Statement separator in `ScriptBlockAst` | Splits sentences into multiple statements. If inside `(...)`, throws syntax error unless escaped or substituted. |

## 3. SMA Boundary Disagreements vs spaCy (30-Sentence Survey)
Out of 160 token-boundary disagreements in the first 30 sentences:
1. **Terminal Punctuation Glued (83.8%, 134/160)**:
   The period `.` (or `?`, `!`) is swallowed into the final word as a `Generic` token.
2. **Word Fused with Neighbor / Syntax (10.6%, 17/160)**:
   Runaway quotes or compound structures absorbing adjacent characters.
3. **Punctuation Absorbed into Word (5.6%, 9/160)**:
   Inner hyphens or quotes attached to adjacent words.
