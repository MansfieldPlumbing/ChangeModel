# Zira pronunciation capture and Windows Kokoro speech

PSPerception captures local Microsoft Zira pronunciation decisions and retains
admitted corrections in a small lookup table. The normal execution path now
uses a PowerShell-authored, lowered CoreLib driver for scanning, role selection,
lookup, admitted corrections, source spans and Kokoro token IDs. The original
SMA context path remains available for authoring and explicit graph evidence.
Stock Kokoro synthesizes the resulting phoneme string on Windows.

All executable entrypoints remain in
`phonemizer/Dev.MansfieldPlumbing.English.Phonemizer.ps1`. Captures, correction
tables, reference source, generated reference adapters, WAVs and receipts stay
under `%LOCALAPPDATA%\Build\PSPerception`.

## Standalone pronunciation driver

```powershell
$driver = & .\phonemizer\Dev.MansfieldPlumbing.English.Phonemizer.ps1 -BuildDriver
dotnet $driver.Output 'The actor records the record.' C:\path\to\pronunciation.json

pwsh -NoProfile -File .\phonemizer\Dev.MansfieldPlumbing.English.Phonemizer.ps1 -VerifyDriver
```

The authored typed classes are lowered by PSLowering at commit
`1afabe056235a570da29e268824784557d4f6cdd`. The persisted driver references only
`System.Private.CoreLib`. It embeds the existing compiled lexical data and
admitted correction table; it does not load SMA, PowerShell or Zira to
phonemize. It requires an installed matching .NET runtime. The build receipt
records the generated source digest, assembly digest and dependency list;
the runtime configuration pins the installed runtime selected at build time.
Input is bounded to 8,192 characters, 256 occurrences and 16 candidates.

The command writes JSON with original text, phones, token IDs, source spans,
roles, pronunciation provenance and whether SMA is loaded. Exit zero means
every source token has a pronunciation; exit one means unsupported or
unresolved tokens. Exit two means incorrect argument count. Grammar and
pronunciation status remain distinct. A compiled driver does not establish
general grammar coverage.

`CORELIB_STANDALONE_PHONEMIZER=PASS` demonstrated equivalence with the existing
path on 23 specimens, four separate dotnet processes with SMA absent, input
and OOV rejection, an independently fixed record fixture, and five checks
against captured teacher corrections. One warm managed batch of 2,000 runs
averaged 353.21775 microseconds per sentence for
`The record records the record.` It includes scanning, roles, graph creation,
lookup, corrections, source spans and token IDs; it excludes build, process
startup and audio. The separate PowerShell-facing verification measured
1.4305 ms median and 2.1205 ms p95. These are Windows observations, not Android
latency estimates. Audio still uses the temporary Windows stock backend.

## Speak

```powershell
pwsh -NoProfile -File .\phonemizer\Dev.MansfieldPlumbing.English.Phonemizer.ps1 `
    -Speak -Text 'The record records the record.'
```

The command runs the canonical English phonemizer, checks that every source
token is supported, validates Kokoro's vocabulary and token IDs, synthesizes a
24 kHz mono WAV, and plays it synchronously. An unresolved word or pronunciation
stops synthesis; no other phonemizer supplies replacement phones.

The successful Windows playback produced 57,000 samples, or 2.375 seconds,
using `af_heart`. The listener confirmed the audio sounded good. The waveform
gate is `SMA_TO_STOCK_KOKORO_WAV=PASS`; the receipt identifies SMA as the
phonemizer and records phones, token provenance, source/model revisions,
waveform digest and correction-table digest.

`-NoPlayback` writes and verifies the WAV without playing it. `-PythonPath`
selects the existing Windows reference environment; the tested environment was
`C:\bin\micromamba\envs\mono\python.exe`, with PyTorch `2.14.0+cpu`.

## Direct Zira-to-Kokoro parity

The parity target is captured Zira phones encoded for stock Kokoro. Moby
pronunciations are not consulted in this path.

```powershell
pwsh -NoProfile -File .\phonemizer\Dev.MansfieldPlumbing.English.Phonemizer.ps1 -GenerateCorpus

pwsh -NoProfile -File .\phonemizer\Dev.MansfieldPlumbing.English.Phonemizer.ps1 `
    -Parity -CorpusPath .\phonemizer\corpora\english-pronunciation-challenges.txt

pwsh -NoProfile -File .\phonemizer\Dev.MansfieldPlumbing.English.Phonemizer.ps1 -Parity

pwsh -NoProfile -File .\phonemizer\Dev.MansfieldPlumbing.English.Phonemizer.ps1 `
    -Speak -UseZira -Text 'A useful idea.'
```

The PowerShell corpus generator saves 107 construction sentences, 59 separate
held-out sentences and a hash receipt under the build directory. The checked-in
challenge collection contains short heteronyms, ambiguity, article onsets,
contractions, punctuation, dates, numbers, currency, units and acronyms. Cases
such as `03/04/2026`, `SQL`, `I saw her duck` and `The door was closed` need a
declared reading or retained ambiguity; they do not have one universal answer.

`-Parity -CorpusPath` captures every line without playback. `-Parity` alone
replays saved observations. The test verifies the complete pinned Kokoro
vocabulary independently against the config, fixed conversion specimens,
unsupported-symbol rejection, model context bounds, all captured token IDs,
and a separate dotnet process with SMA absent. Stock `KModel.forward` at
`dfb907a02bba8152ca444717ca5d78747ccb4bec`, `kokoro/model.py:128-131`, maps
phonemes through `config.vocab` and surrounds the IDs with zero BOS/EOS.
This test rejects unknown symbols instead of relying on stock's filtering.
It saves cases, aligned word observations and receipts in `english/token-parity`.
Unproved word alignment remains a sentence-level phone observation, never a
fabricated word lookup.

The test exposed Zira's tied notation, including `e͡i`, `a͡i`, `t͡ʃ` and
`i͡ə`. Explicit mappings now convert supported diphthongs and affricates to
Kokoro symbols and retain the two components of `i͡ə`. It does not generically
delete tie marks or unknown phones. The mappings exist in the authored script
and the lowered driver. Stress marks are preserved if present, not invented.

`ZIRA_TO_KOKORO_TOKEN_PARITY=PASS` covered 129 saved captures and 2,627 mapped
symbols with zero dropped symbols. It excluded 266 reported pause/control
events. Nine warm compiled batches measured a median batch mean of 2.13685
microseconds for phone normalization plus tokenization, with a maximum batch
mean of 6.30215 microseconds. The full existing sentence driver measured
96.2494 microseconds median batch mean and 128.0008 microseconds maximum batch
mean. These are batch means, not per-call p95 values. Measurements reflect the
current Windows load and exclude capture, compilation, startup and synthesis.

The generated 107-sentence construction corpus was subsequently captured and
passed direct parity for 1,610 mapped symbols, with zero drops. Its corpus
SHA-256 is `17092E1FA3A3F5997A229830F131974DC4988F0741928B866A76383468F20676`.
This run saved aligned word observations with contexts and token IDs. It
measured 2.593 microseconds median batch mean for Zira token mapping and
161.7324 microseconds for the existing full driver. The latter still uses the
existing lexicon and is not a benchmark of a Zira-only lookup. The 59 generated
held-out sentences were not admitted into the construction observations.

A combined replay then passed 237 saved captures (including repeated
observations) and 4,250 mapped symbols with no drops, checking all 114
vocabulary IDs against the lowered driver's own `Phonology.SymbolId`.
Median batch means were 3.6235 microseconds for the Zira mapper and
160.8124 microseconds for the full existing driver. Maximum batch means were
9.03425 and 166.9298 microseconds respectively. These variations are observed
timings under current load, not a guaranteed latency bound.

Direct teacher speech generated and played a 45,600-sample, 1.9-second stock
Kokoro WAV for `A useful idea.` using `ə jusfəl Idiə .`. Every word's receipt
identifies `ZiraEvents`; it uses no dictionary pronunciation. The gate is
`PHONEMIZER_TO_STOCK_KOKORO_WAV=PASS`. This Windows reference path requires Zira
at capture time; it is not the Android product frontend. A Zira-extracted
replacement lexicon still needs admission, contextual selection and a stress
gate before replacing the normal lexicon. Token parity does not prove that
Zira pronounced the intended meaning correctly or that it outperforms Moby.

## Capture event evidence

```powershell
pwsh -NoProfile -File .\phonemizer\Dev.MansfieldPlumbing.English.Phonemizer.ps1 `
    -Zira -Text 'The record records the record.'

pwsh -NoProfile -File .\phonemizer\Dev.MansfieldPlumbing.English.Phonemizer.ps1 `
    -Zira -CorpusPath C:\path\to\sentences.txt
```

The corpus is UTF-8 text, one sentence per line. Capture explicitly selects
`Microsoft Zira Desktop`, loads the installed PowerShell `System.Speech.dll`
from its filesystem path, registers `SpeakProgress`, `PhonemeReached` and
`SpeakCompleted`, and uses `SetOutputToNull`. It unregisters its own events and
disposes the synthesizer when finished.

Each capture retains the original sentence, word character spans and audio
positions, raw phones, next phones, durations, emphasis flags, voice identity,
and local assembly/engine digests. Capture creates a new JSON file each time;
previous observations remain available.

Word alignment requires exact source-span agreement, strictly ordered
nonoverlapping word spans, a first phone timestamp equal to each word onset,
and complete assignment of audible phones. Control phones remain in the raw
capture but do not become pronunciation symbols. Number expansion or another
ambiguous alignment remains raw evidence and cannot supply word corrections.

This alignment gate was demonstrated on the recorded specimens. It does not
establish alignment correctness for every possible engine input.

## Distill and admit corrections

```powershell
pwsh -NoProfile -File .\phonemizer\Dev.MansfieldPlumbing.English.Phonemizer.ps1 -Distill

pwsh -NoProfile -File .\phonemizer\Dev.MansfieldPlumbing.English.Phonemizer.ps1 `
    -Distill -CorpusPath C:\path\to\construction.txt `
    -ValidationCorpusPath C:\path\to\held-out.txt
```

This is behavioral distillation into lookup entries, not neural retraining.
The key combines word identity, the role selected by the existing SMA bindings,
and whether the following word has a vowel onset in the compiled lexicon.
It uses pronunciation rather than spelling: `university` and `one` have
consonant onsets; `hour` has a vowel onset. Unknown onsets do not match a rule.

Construction requires consistent pronunciation in at least two distinct
sentences. Admission sentences must be separate from construction sentences.
An entry must fix at least one held-out pronunciation without regressing a
previously matching pronunciation. The complete table is then evaluated through
`Invoke-EnglishPhonemizer` on those held-out sentences. Successful tables are
loaded automatically by the normal execution path. Existing entries are
retained; replaced tables are backed up.

The initial demonstrated result used six construction sentences and seven
admission sentences. All 13 aligned. One admitted entry changed `the` before a
compiled vowel onset from `ðə` to Zira's observed `ðɪ`. It fixed three held-out
occurrences, with zero measured regressions. The gate is
`ZIRA_CORRECTION_ADMISSION=PASS`.

The construction vowel contexts were `apple` and `orange`. The corrected
held-out contexts were `elephant`, `actor` and `hour`. The consonant controls
included `clock`, `university` and `one`. This demonstrates that one local
context condition transfers across those following-word identities. It does
not establish broad pronunciation accuracy or general English understanding.

The student's compiled pronunciations retain lexical stress. Zira's raw
phones are converted to supported Kokoro symbols, including `ɻ` to `ɹ` and
Kokoro's diphthong/affricate symbols. When the observed phone sequence matches a
compiled variant, the variant supplies stress. A changed stressed lexical
pronunciation without a supported stress source is rejected. The admitted
article correction has no manufactured lexical stress.

## Evidence and limits

### Pronunciation accuracy gate

The current compiled lexicon is Moby-derived (115,491 identities), with
authored entries and admitted Zira corrections. It is not a Zira-extracted
lexicon. The 13 demonstrated captures establish a small correction gate,
not broad accuracy or a measured ordinary-text coverage percentage.

To evaluate a Zira-derived replacement, freeze separate construction,
development and final evaluation sentence sets before extraction. Preserve
the set digests in the evaluation receipt. Group paraphrases and repeated
templates together so closely related sentences do not cross partitions.
Held-out contexts for known words test contextual selection; held-out words
test vocabulary coverage. Report these separately. Once a final evaluation
failure is used to improve the lookup, that specimen becomes a regression
test and the next final evaluation needs fresh specimens.

Use two distinct comparisons: recorded Zira observations for teacher fidelity,
and stock Misaki for Kokoro-facing phoneme and stress comparison. Neither is
an independent ground truth. Review disagreements against intended meaning
and listen to matched Kokoro renders. Misaki's English symbol specification
includes both primary and secondary stress:
<https://github.com/hexgrad/misaki/blob/main/EN_PHONES.md>.

For each category, report input word coverage, unsupported source spans,
phoneme edit rate, exact word-pronunciation agreement, lexical stress errors,
and contextual heteronym errors. Do not combine missing words with correctly
pronounced words or omit unresolved tokens from the denominator. Report the
sample size with every percentage. Zira event captures demonstrated so far
do not establish lexical stress extraction; this is an explicit evidence gap
for a Zira-only lookup.

The frozen set must include ordinary prose, questions, noun/verb heteronyms
such as record/present/read, names, contractions, punctuation, numbers,
decimals, dates, currencies, units, and acronyms such as MB and KB. Number and
acronym readings need explicit intended expansions where multiple readings
are valid. Source-span alignment failure is a capture failure, not permission
to guess an expanded word's pronunciation.

For listening, hold checkpoint, voice, speed, sentence and rendering backend
constant. Randomize which render is A and B, and record pronunciation errors
separately from naturalness preferences. Waveform equality is not an accuracy
criterion when phonemes differ. A speech-recognition transcript is diagnostic
only; it does not prove stress, vowel choice or pronunciation correctness.

An initial engineering target is zero dropped source spans, zero unsupported
Kokoro symbols, zero known regression failures and at least 99% correctly
pronounced words on the frozen evaluation corpus, with category-specific
results. These are proposed acceptance thresholds, not achieved scores.
Measure warm frontend median/p95 separately from cold startup and Kokoro
time to first audio. A successful standalone driver gate does not establish
pronunciation accuracy or Android execution.

Run the diagnostic against a frozen UTF-8 file, one sentence per line:

```powershell
pwsh -NoProfile -File .\phonemizer\Dev.MansfieldPlumbing.English.Phonemizer.ps1 `
    -Audit -ValidationCorpusPath C:\path\to\held-out.txt
```

This command runs the canonical driver, captures fresh Zira events, and writes
per-word disagreements and a corpus-hashed receipt in the build directory.
It never admits corrections or changes the lookup. Its result is an audit,
not a pass assertion. Missing student pronunciations count as mismatches and
deletions wherever the teacher aligns. Teacher alignment failures remain
reported separately; they cannot establish agreement.

The first broader diagnostic used 20 sentences, with corpus SHA-256
`AA8734010CDB8E89CD9417F6E45CC562B4BAEF0BF9C5B806EE336F94FA0900CB`.
It supported 85 of 108 input word spans (78.7%) and produced complete
pronunciations for 6 of 20 sentences. It matched Zira's stress-stripped phone
sequence for 47 of 79 strictly comparable word spans (59.5%). Its Kokoro
symbol edit rate was 36.3%; four sentence captures failed strict alignment.
The corpus exercised prose, heteronyms, names, contractions, numbers, dates,
currency, MB and KB. It is a small diagnostic corpus, not a population-wide
accuracy estimate. Stress and listening preference were not measured.
These historical scores preceded the tied-notation mapping fixes. They include
conversion failures and cannot establish comparative Zira-versus-Moby accuracy.

`-Verify` passed the existing `CanonicalEnglishSmaExecution` behavioral gate
after integration. A warm Windows run of the five-word fixture measured
32.3545 ms median and 37.7231 ms p95 over 30 runs after ten warm-ups. These
are CPU phonemizer measurements, not Hexagon or end-to-end latency.

A subsequent run measured 71.1828 ms median and 124.4788 ms p95, so the
32 ms result is not a stable latency guarantee. That run also measured
172.56502 microseconds per compiled word lookup plus pronunciation fetch,
averaged over 10,000 repetitions of `record`. The boundary includes a
PowerShell loop and two managed delegate calls, and excludes grammatical
candidate construction and provenance. It is not a native-only benchmark.

The lexicon is already lowered into a CoreLib-only assembly. The correction
selector and grammatical orchestration still execute in PowerShell. Lowering
their typed hot path could reduce dispatch and allocation overhead; that
additional lowering and its latency benefit have not been demonstrated.

Stock source is pinned to Kokoro commit
`dfb907a02bba8152ca444717ca5d78747ccb4bec`; extracted files are verified against
that commit's Git blobs. Model/config/voice inputs are pinned to revision
`f3ff3571791e39611d31c381e3a41a3af07b4987` and checked against SHA-256 digests.
Matching local assets in `C:\models\Kokoro-82M` are reused read-only. Missing
model inputs are downloaded into the project build folder. The shim checks
loaded model parameters against the checkpoint and checks SMA token IDs against
the model vocabulary before inference.

This work proves Windows reference speech and the limited correction gate.
It does not prove Kokoro-Hexagon whole-model synthesis or target-device latency.
General grammar, currency/date verbalization and arbitrary acronym expansion
remain unsupported by this execution path; successful SMA parsing elsewhere
does not establish their English pronunciations here.

Microsoft's API contracts describe the captured events:
[PhonemeReached](https://learn.microsoft.com/en-us/dotnet/api/system.speech.synthesis.speechsynthesizer.phonemereached),
[SpeakProgress](https://learn.microsoft.com/en-us/dotnet/api/system.speech.synthesis.speechsynthesizer.speakprogress),
and [SetOutputToNull](https://learn.microsoft.com/en-us/dotnet/api/system.speech.synthesis.speechsynthesizer.setoutputtonull).
