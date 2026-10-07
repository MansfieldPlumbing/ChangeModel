# Failure Analysis and SMA Engine Source Grounding

## 1. Executive Summary
- **Baseline Performance**:
  - Train 500: 72 failing sentences / 77 parse errors (85.6% pass rate).
  - Eval 200: 30 failing sentences / 37 parse errors (85.0% pass rate).
- **Frozen Projection Performance**:
  - Train 500: 1 failing sentence / 1 parse error (**99.8% pass rate**).
  - Eval 200: 2 failing sentences / 8 parse errors (**99.0% pass rate**).
- **Lossless Reversibility**: **100% verified** bit-for-bit identity across all 700 sentences.

---

## 2. Taxonomy of Remaining Failures & Grounded Root Causes

### A. Genuine Punctuation Defect in Source Corpus
- **Occurrence**: Eval Sentence 166 (`There is evidence that by-attribute processing is the preferred process for decision making (Arieli et al.`)
- **Error**: `MissingEndParenthesisInExpression: Missing closing ')' in expression.`
- **Engine Source Location**: `System.Management.Automation/engine/parser/parser.cs:5560-5575` (`Parser.ParenExpressionRule`).
- **Mechanism**: The raw source sentence from Wikipedia contains an open parenthesis `(` with no matching `)`. PowerShell strictly enforces balanced parentheses; encountering `EndOfInput` before `RParen` triggers `ParserStrings.MissingEndParenthesisInExpression`.
- **Classification**: **Genuine Source Defect / Strict Syntax Boundary**. Unreachable without speculative, destructive modification of authoritative source text.

### B. Expression Mode Juxtaposition inside Parentheses
- **Occurrence**: Eval Sentence 138 (`This corresponds to 180 kpc (600,000 ly) at an approximate distance of 55 kpc (180,000 ly).`)
- **Errors**: `UnexpectedToken: Unexpected token 'ly' in expression or statement` and `MissingEndParenthesisInExpression`.
- **Engine Source Location**: `System.Management.Automation/engine/parser/parser.cs:5570` (`Parser.ParenExpressionRule`).
- **Mechanism**: When SMA encounters `(`, it transitions from Command Argument Mode into Expression Mode (`ExpressionRule`). In expression mode:
  1. `600,000` is parsed as an `ArrayLiteralAst` (`600`, `,`, `000`).
  2. The subsequent word `ly` is adjacent without an operator. Expression grammar requires an operator (binary, comma, pipeline) between expressions. Juxtaposition is illegal in Expression Mode.
- **Classification**: **Genuine SMA Grammar Limitation**.
- **Path Forward**: Reachable in extended contact languages by joining number and unit (e.g., `600,000♠ly`) or wrapping units.

### C. Comma Immediately Following Closing Parenthesis in Argument Mode
- **Occurrence**: Train Sentence 84 (`The other parts of Vedas are the Samhitas (benedictions, hymns), Brahmanas...`)
- **Error**: `MissingArgument: Missing argument in parameter list.`
- **Engine Source Location**: `System.Management.Automation/engine/parser/parser.cs:6537-6543` (`Parser.CommandArgumentInternal`).
- **Mechanism**: In command argument mode, parenthetical arguments are closed by `RParen`. When the parser subsequently encounters `,` as the leading character of the next command element, it executes:
  ```csharp
  case TokenKind.Comma:
      endExtent = token.Extent;
      ReportError(token.Extent,
          nameof(ParserStrings.MissingArgument),
          ParserStrings.MissingArgument);
      SkipNewlines();
      break;
  ```
- **Classification**: **Genuine SMA Grammar Limitation**. A standalone comma cannot initiate a command element after an expression argument.
- **Path Forward**: Reachable in extended contact languages by projecting commas following closing parentheses to fullwidth `，` or inserting space before the comma.

---

## 3. Solved Error Classes & Verification Mapping

| Error Class | Baseline Mechanism | Engine Source Trigger | Winning Projection Solution | Resolution Rate |
| :--- | :--- | :--- | :--- | :--- |
| **Apostrophe / Contractions** | `'` parsed as opening single-quote literal; missing closing quote throws `TerminatorExpectedAtEndOfString`. | `tokenizer.cs:2325` (`c.IsSingleQuote()`) | `apos=modifier` (`ʼ` U+02BC) or `apos=escaped` (`` `' ``). Keeps word intact as `Identifier`. | **100% resolved** (60/60 sentences fixed) |
| **Sentence-Initial Adverbial Commas** | `Rather,`, `Indeed,` at statement start; comma immediately after command name throws `MissingArgument`. | `parser.cs:6537` (`case TokenKind.Comma:`) | `pre=slash` (`// `) or `pre=qmark` (`¿ `). Shifts all words to argument position where commas form valid `ArrayLiteralAst`. | **100% resolved** (38/38 sentences fixed) |
| **Statement-Initial Keywords** | `While`, `For`, `If` trigger block statement parsers expecting `(...)`. | `parser.cs:4000` (`StatementRule`) | Sentinel prefix (`// ` or `¿ `). Keywords become bare-word arguments. | **100% resolved** (4/4 sentences fixed) |
| **Semicolon Splitting** | `;` splits statements inside parentheticals or before commas. | `tokenizer.cs:3420` (`TokenKind.Semi`) | `semi=fullwidth` (`；` U+FF1B). Preserves clause boundaries without statement fragmentation. | **100% resolved** (4/4 sentences fixed) |
| **Comment Collisions** | `#` (e.g. `#1089`) comments out remainder of line and trailing `)`. | `tokenizer.cs:2200` (`TokenKind.Comment`) | `hash=fullwidth` (`＃` U+FF03). Neutralizes comment parsing. | **100% resolved** (2/2 sentences fixed) |
| **Terminal Punctuation Swallowing** | Trailing `.` swallowed into final word argument (`imagery.`). | `tokenizer.cs:3430` (`ScanGenericToken`) | `term=space` (`imagery .`). Separates lexical word from punctuation. | **100% resolved** (826 boundary fixes) |
| **Quote Literal Collisions** | `"` encloses multi-word spans in opaque `StringExpandableToken`. | `tokenizer.cs:2320` (`IsDoubleQuote()`) | `quot=guillemets` (`« »`). Exposes internal words as distinct AST elements. | **100% resolved** |
