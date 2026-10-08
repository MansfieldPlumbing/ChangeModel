# Zira pronunciation capture and Windows Kokoro speech

PSPerception captures local Microsoft Zira pronunciation decisions and retains
admitted corrections in a small lookup table. The existing compiled lexicon
and SMA grammatical bindings still select pronunciation. Stock Kokoro then
synthesizes the resulting phoneme string on Windows.

All executable entrypoints remain in
`phonemizer/Dev.MansfieldPlumbing.English.Phonemizer.ps1`. Captures, correction
tables, reference source, generated reference adapters, WAVs and receipts stay
under `%LOCALAPPDATA%\Build\PSPerception`.

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

## Capture Zira

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
