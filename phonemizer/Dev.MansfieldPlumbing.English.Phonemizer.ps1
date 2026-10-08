#requires -Version 7.7
[CmdletBinding(DefaultParameterSetName='Run')]
param(
    [Parameter(ParameterSetName='Build',Mandatory)][switch]$Build,
    [Parameter(ParameterSetName='Run')][switch]$Run,
    [Parameter(ParameterSetName='Inspect',Mandatory)][switch]$Inspect,
    [Parameter(ParameterSetName='Verify',Mandatory)][switch]$Verify,
    [Parameter(ParameterSetName='Import',Mandatory)][switch]$Import,
    [string]$Text='',
    [ValidateSet('Proof','Moby','MobyOnly')][string]$LexicalSource='Moby',
    [string]$AssemblyPath=(Join-Path $env:LOCALAPPDATA 'Build\PSPerception\english\Dev.MansfieldPlumbing.English.Phonemizer.dll')
)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$script:EnglishReferenceCache=@{}
$script:MobyPhoneMap=[Collections.Generic.Dictionary[string,string]]::new([StringComparer]::Ordinal)
foreach($entry in '&=æ;(@)=ɛ;A=ɑ;eI=A;@=ə;-=ə;b=b;tS=ʧ;d=d;E=ɛ;i=i;f=f;g=ɡ;h=h;hw=w;I=ɪ;aI=I;dZ=ʤ;k=k;l=l;m=m;N=ŋ;n=n;Oi=Y;AU=W;O=ɔ;oU=O;u=u;U=ʊ;p=p;r=ɹ;S=ʃ;s=s;T=θ;D=ð;t=t;@r=əɹ;v=v;w=w;j=j;Z=ʒ;z=z'.Split(';')){
    $pair=$entry.Split('=');$script:MobyPhoneMap.Add($pair[0],$pair[1])
}

function ConvertFrom-MobyPronunciation {
    param([string]$Notation)
    # Decode the published lexical data notation. Stressed /@/ differs from schwa.
    $map=$script:MobyPhoneMap
    $out=[Text.StringBuilder]::new();$stress='';$at=0
    while($at -lt $Notation.Length){
        $ch=$Notation[$at]
        if($ch -ceq [char]39){$stress='ˈ';$at++;continue}
        if($ch -ceq ','){$stress='ˌ';$at++;continue}
        if($ch -ceq '_' -or $ch -ceq ' '){[void]$out.Append(' ');$at++;continue}
        if($ch -ceq '/'){
            $end=$Notation.IndexOf('/', $at+1)
            if($end -lt 0){return $null}
            $unit=$Notation.Substring($at+1,$end-$at-1);$at=$end+1
        }else{$unit=[string]$ch;$at++}
        if(-not $map.ContainsKey($unit)){return $null}
        $phone=$map[$unit]
        if($stress -and $unit -ceq '@'){$phone='ʌ'}
        if($stress -and $unit -ceq '@r'){$phone='ɜɹ'}
        if($phone[0] -cin 'AIOWYɑɔəæɛɜɪiʊuʌ'.ToCharArray() -and $stress){[void]$out.Append($stress);$stress=''}
        [void]$out.Append($phone)
    }
    if($stress){return $null}
    $out.ToString().Trim()
}

function Get-EnglishMobyFacts {
    param([switch]$WithoutAuthoredOverrides)
    $root=Join-Path $env:LOCALAPPDATA 'Build\PSPerception\inputs\public-domain-moby'
    [void][IO.Directory]::CreateDirectory($root)
    $commit='0a780d8d6a83909f9538b01aba8c6848b6689935'
    $sources=@(
        @('.untouched/mpron/mobypron.unc','pronunciations.txt','EAB1C6DFDA47178A36103041C118398C9A10ED1CE08C14D9D43865D60275B0D4'),
        @('.untouched/mpos/mobyposi.i','capabilities.txt','DAA369396E90E16ED8EB89B9E70E6B83939D021A7BD58077C82D3BE7FE1A2D14')
    )
    foreach($source in $sources){
        $path=Join-Path $root $source[1]
        if(-not(Test-Path -LiteralPath $path)){Invoke-WebRequest -Uri "https://raw.githubusercontent.com/elitejake/Moby-Project/$commit/$($source[0])" -OutFile $path}
        if((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -cne $source[2]){throw 'Pinned public-domain data integrity failure.'}
    }
    $cache=Join-Path $root 'parsed-facts.tsv';$cacheReceipt=Join-Path $root 'parsed-facts.clixml'
    $parserHash=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes((Get-Command Get-EnglishMobyFacts).ScriptBlock.ToString()+(Get-Command ConvertFrom-MobyPronunciation).ScriptBlock.ToString())))
    $cached=$null
    if((Test-Path -LiteralPath $cache) -and (Test-Path -LiteralPath $cacheReceipt)){
        $candidate=Import-Clixml -LiteralPath $cacheReceipt
        if($candidate.ParserHash -ceq $parserHash -and $candidate.Commit -ceq $commit -and $candidate.CacheHash -ceq (Get-FileHash -LiteralPath $cache).Hash -and $candidate.PronunciationSha256 -ceq $sources[0][2] -and $candidate.CapabilitiesSha256 -ceq $sources[1][2]){$cached=$candidate}
    }
    $records=[Collections.Generic.Dictionary[string,object]]::new([StringComparer]::Ordinal)
    if($null -ne $cached){
        foreach($line in [IO.File]::ReadLines($cache)){
            $fields=$line.Split("`t")
            if($fields.Count -ne 7){throw 'Invalid cached lexical fact.'}
            $records.Add($fields[0],@($fields[0],[int]$fields[1],$fields[2],$fields[3],$fields[4],$fields[5],$fields[6]))
        }
        $rows=$cached.SourceRows;$excluded=$cached.ExcludedMultiwordOrLongRows;$unconverted=$cached.UnconvertedRows
    }else{
    $capabilities=[Collections.Generic.Dictionary[string,int]]::new([StringComparer]::Ordinal)
    foreach($line in [IO.File]::ReadLines((Join-Path $root 'capabilities.txt'),[Text.Encoding]::Latin1)){
        $split=$line.IndexOf([char]215)
        if($split -lt 1){continue}
        $word=$line.Substring(0,$split).ToLowerInvariant();$bits=0
        foreach($tag in $line.Substring($split+1).ToCharArray()){
            switch -CaseSensitive ($tag){'N'{$bits=$bits -bor 1};'p'{$bits=$bits -bor 1};'h'{$bits=$bits -bor 1};'V'{$bits=$bits -bor 10};'t'{$bits=$bits -bor 1026};'i'{$bits=$bits -bor 2};'A'{$bits=$bits -bor 4};'r'{$bits=$bits -bor 17}}
        }
        if($capabilities.ContainsKey($word)){$capabilities[$word]=$capabilities[$word] -bor $bits}else{$capabilities.Add($word,$bits)}
    }
    $rows=0;$excluded=0;$unconverted=0
    foreach($line in [IO.File]::ReadLines((Join-Path $root 'pronunciations.txt'),[Text.Encoding]::Latin1)){
        $rows++;$space=$line.IndexOf(' ')
        if($space -lt 1){$excluded++;continue}
        $word=$line.Substring(0,$space).ToLowerInvariant();$tag=''
        $slash=$word.LastIndexOf('/')
        if($slash -ge 0){$tag=$word.Substring($slash+1);$word=$word.Substring(0,$slash)}
        if($word.Length -gt 16 -or $word.Contains('_') -or $word.Length -eq 0){$excluded++;continue}
        $pron=ConvertFrom-MobyPronunciation -Notation $line.Substring($space+1)
        if($null -eq $pron){$unconverted++;$pron=''}
        if(-not $records.ContainsKey($word)){
            $flags=if($capabilities.ContainsKey($word)){$capabilities[$word]}else{0}
            $records.Add($word,@($word,$flags,'','','','',''))
        }
        $record=$records[$word]
        $slots=switch -CaseSensitive ($tag){'n'{@(0)};'v'{@(1,3)};'aj'{@(2)};'av'{@(4)};''{@(0,1,2,3,4)};default{@()}}
        foreach($slot in $slots){
            if($pron){
                $values=@($record[$slot+2].Split('|',[StringSplitOptions]::RemoveEmptyEntries))
                if($pron -cnotin $values){$record[$slot+2]=(@($values)+@($pron)) -join '|'}
            }
        }
        switch -CaseSensitive($tag){'n'{$record[1]=$record[1] -bor 1};'v'{$record[1]=$record[1] -bor 2};'aj'{$record[1]=$record[1] -bor 4}}
    }
    $writer=[IO.StreamWriter]::new($cache,$false,[Text.UTF8Encoding]::new($false))
    try{foreach($record in $records.Values){$writer.WriteLine($record -join "`t")}}finally{$writer.Dispose()}
    [pscustomobject]@{ParserHash=$parserHash;CacheHash=(Get-FileHash -LiteralPath $cache).Hash;Commit=$commit;PronunciationSha256=$sources[0][2];CapabilitiesSha256=$sources[1][2];SourceRows=$rows;ExcludedMultiwordOrLongRows=$excluded;UnconvertedRows=$unconverted} | Export-Clixml -LiteralPath $cacheReceipt
    }
    $overrides=0
    if(-not $WithoutAuthoredOverrides){foreach($fact in (Get-EnglishProofFacts)){$records[$fact[0]]=$fact;$overrides++}}
    $script:EnglishLexicalBuildStatistics=[pscustomobject]@{SourceRows=$rows;ExcludedMultiwordOrLongRows=$excluded;UnconvertedRows=$unconverted;CompiledIdentities=$records.Count;Commit=$commit;PronunciationSha256=$sources[0][2];CapabilitiesSha256=$sources[1][2];Rights='Original public-domain data only';AuthoredOverrides=$overrides;ParsedFactCache=$cache;ParserHash=$parserHash}
    foreach($record in $records.Values){,$record}
}

function Add-EnglishCompiledRange {
    param([Text.StringBuilder]$Index,[Text.StringBuilder]$Data,[string]$Value,[hashtable]$Interned)
    if($Value.Length -ge 4096 -or $Data.Length -ge 16777216){throw 'Compiled lexical range bound exceeded.'}
    if($Interned.ContainsKey($Value)){$start=$Interned[$Value]}else{$start=$Data.Length;$Interned[$Value]=$start;[void]$Data.Append($Value)}
    [void]$Index.Append([char](4096+($start -band 4095)))
    [void]$Index.Append([char](4096+(($start -shr 12) -band 4095)))
    [void]$Index.Append([char](4096+$Value.Length))
}

# Authored proof facts, not a corpus or a comprehensive English dictionary.
# Capabilities: nominal=1, verb=2, property=4, participle=8, pronoun=16,
# determiner=32, copula=64, by=128, person=256, time=512,
# transitive=1024, perception complement=2048, perfect auxiliary=4096.
# Phone slots: nominal, verb, property, participle, function word.
function Get-EnglishProofFacts {
    @(
        @('a',32,'','','','','ə'),
        @('alice',257,'ˈælɪs','','','',''),
        @('an',32,'','','','','ən'),
        @('are',64,'','','','','ɑɹ'),
        @('book',1027,'bˈʊk','bˈʊk','','',''),
        @('by',128,'','','','','bI'),
        @('cat',1,'kˈæt','','','',''),
        @('cellar',1,'sˈɛləɹ','','','',''),
        @('clock',1,'klˈɑk','','','',''),
        @('close',1031,'klˈOs','klˈOz','klˈOs','',''),
        @('closed',1038,'','klˈOzd','klˈOzd','klˈOzd',''),
        @('door',1,'dˈɔɹ','','','',''),
        @('duck',3,'dˈʌk','dˈʌk','','',''),
        @('eight',1,'ˈAt','','','',''),
        @('eighteen',1,'Atˈin','','','',''),
        @('eighty',1,'ˈAti','','','',''),
        @('eleven',1,'ɪlˈɛvən','','','',''),
        @('fifteen',1,'fɪftˈin','','','',''),
        @('fifty',1,'fˈɪfti','','','',''),
        @('five',1,'fˈIv','','','',''),
        @('forty',1,'fˈɔɹti','','','',''),
        @('four',1,'fˈɔɹ','','','',''),
        @('fourteen',1,'fɔɹtˈin','','','',''),
        @('had',4096,'','','','','hæd'),
        @('has',4096,'','','','','hæz'),
        @('have',4096,'','','','','hæv'),
        @('he',273,'hi','','','',''),
        @('her',305,'hɜɹ','','','','hɜɹ'),
        @('hundred',1,'hˈʌndɹəd','','','',''),
        @('i',273,'I','','','',''),
        @('is',64,'','','','','ɪz'),
        @('lead',1027,'lˈɛd','lˈid','','',''),
        @('live',6,'','lˈɪv','lˈIv','',''),
        @('music',1,'mjˈuzɪk','','','',''),
        @('nine',1,'nˈIn','','','',''),
        @('nineteen',1,'nIntˈin','','','',''),
        @('ninety',1,'nˈInti','','','',''),
        @('noon',513,'nˈun','','','',''),
        @('one',1,'wˈʌn','','','',''),
        @('permit',1027,'pˈɜɹmɪt','pəɹmˈɪt','','',''),
        @('permits',1027,'pˈɜɹmɪts','pəɹmˈɪts','','',''),
        @('present',1031,'pɹˈɛzənt','pɹɪzˈɛnt','pɹˈɛzənt','',''),
        @('presents',1027,'pɹˈɛzənts','pɹɪzˈɛnts','','',''),
        @('read',9226,'','ɹˈid','','ɹˈɛd',''),
        @('record',1027,'ɹˈɛkəɹd','ɹɪkˈɔɹd','','',''),
        @('records',1027,'ɹˈɛkəɹdz','ɹɪkˈɔɹdz','','',''),
        @('saw',3074,'','sˈɔ','','',''),
        @('seven',1,'sˈɛvən','','','',''),
        @('seventeen',1,'sɛvəntˈin','','','',''),
        @('seventy',1,'sˈɛvənti','','','',''),
        @('she',273,'ʃi','','','',''),
        @('shit',3,'ʃˈɪt','ʃˈɪt','','',''),
        @('six',1,'sˈɪks','','','',''),
        @('sixteen',1,'sɪkstˈin','','','',''),
        @('sixty',1,'sˈɪksti','','','',''),
        @('ten',1,'tˈɛn','','','',''),
        @('the',32,'','','','','ðə'),
        @('they',273,'ðA','','','',''),
        @('thirteen',1,'θɜɹtˈin','','','',''),
        @('thirty',1,'θˈɜɹti','','','',''),
        @('thousand',1,'θˈWzənd','','','',''),
        @('three',1,'θɹˈi','','','',''),
        @('twelve',1,'twˈɛlv','','','',''),
        @('twenty',1,'twˈɛnti','','','',''),
        @('two',1,'tˈu','','','',''),
        @('was',64,'','','','','wəz'),
        @('we',273,'wi','','','',''),
        @('were',64,'','','','','wɜɹ'),
        @('wind',1027,'wˈɪnd','wˈInd','','',''),
        @('zero',1,'zˈɪɹO','','','','')
    )
}

function Build-EnglishReference {
    [CmdletBinding()]
    param([string]$OutputPath,[ValidateSet('Proof','Moby','MobyOnly')][string]$Source='Moby')
    $authorSourceSha=(Get-FileHash -LiteralPath $PSCommandPath -Algorithm SHA256).Hash
    $root=[IO.Path]::GetFullPath((Join-Path $env:LOCALAPPDATA 'Build\PSPerception'))+'\'
    $OutputPath=[IO.Path]::GetFullPath($OutputPath)
    if(-not $OutputPath.StartsWith($root,[StringComparison]::OrdinalIgnoreCase)){throw 'Assembly output must remain in the project build directory.'}
    if([IO.Path]::GetFileName($OutputPath) -cne 'Dev.MansfieldPlumbing.English.Phonemizer.dll'){throw 'Unexpected product assembly identity.'}
    $compiler=Join-Path $root 'inputs\pslowering-1afabe056235a570da29e268824784557d4f6cdd'
    $manifest=Import-Csv -LiteralPath (Join-Path $compiler 'verified-source.tsv') -Delimiter "`t"
    if($manifest.Count -ne 9){throw 'Incomplete pinned compiler source.'}
    foreach($row in $manifest){
        $inputFile=[IO.Path]::GetFullPath((Join-Path $compiler $row.Path))
        if(-not $inputFile.StartsWith($compiler+'\',[StringComparison]::OrdinalIgnoreCase) -or $row.Commit -cne '1afabe056235a570da29e268824784557d4f6cdd' -or (Get-FileHash -LiteralPath $inputFile -Algorithm SHA256).Hash -cne $row.Sha256){throw 'Pinned compiler integrity failure.'}
    }
    Import-Module (Join-Path $compiler 'src\Dev.MansfieldPlumbing.PowerShell.Lowering.psd1') -Force -ErrorAction Stop
    $configPath=Join-Path $root 'kokoro-config.json'
    if((Get-FileHash -LiteralPath $configPath -Algorithm SHA256).Hash -cne '5ABB01E2403B072BF03D04FDE160443E209D7A0DAD49A423BE15196B9B43C17F'){throw 'Kokoro target specification integrity failure.'}
    # Build-only target vocabulary specification; no language dictionary ingestion.
    $vocab=(Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json -AsHashtable).vocab
    $symbols=[char[]]::new(178)
    [Array]::Fill($symbols,[char]0xFFFF)
    foreach($pair in $vocab.GetEnumerator()){
        if($pair.Key.Length -ne 1 -or $pair.Value -lt 0 -or $pair.Value -ge 178){throw 'Unsupported target vocabulary.'}
        $symbols[$pair.Value]=$pair.Key[0]
    }
    $forms=[Text.StringBuilder]::new();$caps=[Text.StringBuilder]::new()
    $offsets=[Text.StringBuilder]::new();$phones=[Text.StringBuilder]::new();$roles=[Text.StringBuilder]::new();$alternates=[Text.StringBuilder]::new();$interned=@{};$alternateRow=0
    $facts=@(if($Source -ceq 'Moby'){Get-EnglishMobyFacts}elseif($Source -ceq 'MobyOnly'){Get-EnglishMobyFacts -WithoutAuthoredOverrides}else{Get-EnglishProofFacts})
    $ordered=[Collections.Generic.SortedDictionary[string,object]]::new([StringComparer]::Ordinal)
    foreach($fact in $facts){$ordered.Add($fact[0],$fact)}
    $facts=@($ordered.Values)
    $seen=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach($fact in $facts){
        if($fact.Count -ne 7 -or $fact[0].Length -gt 16 -or -not $seen.Add($fact[0])){throw 'Invalid proof fact.'}
        [void]$forms.Append($fact[0].PadRight(16));[void]$caps.Append(([int]$fact[1]).ToString('X4'))
        foreach($pron in $fact[2..6]){
            foreach($ch in $pron.ToCharArray()){if($ch -cne '|' -and -not $vocab.ContainsKey([string]$ch)){throw 'Pronunciation contains an unsupported target symbol.'}}
        }
        $unique=@($fact[2..6] | Sort-Object -Unique -CaseSensitive)
        if($unique.Count -eq 1){Add-EnglishCompiledRange $offsets $phones $unique[0] $interned;[void]$roles.Append([char]4096)}
        else{
            Add-EnglishCompiledRange $offsets $phones '' $interned
            $alternateRow++;if($alternateRow -gt 20000){throw 'Compiled alternative index bound exceeded.'}
            [void]$roles.Append([char](4096+$alternateRow))
            foreach($pron in $fact[2..6]){Add-EnglishCompiledRange $alternates $phones $pron $interned}
        }
    }
    $template=@'
class Lexicon {
    static [int] Count() {return @COUNT@}
    static [string] Forms() {return '@FORMS@'}
    static [string] Flags() {return '@FLAGS@'}
    static [string] Offsets() {return '@OFFSETS@'}
    static [string] RoleIndexes() {return '@ROLES@'}
    static [string] Alternates() {return '@ALTERNATES@'}
    static [string] Sequences() {return '@PHONES@'}
    static [string] Form([int]$id) {
        if ($id -lt 0 -or $id -ge [Lexicon]::Count()) {throw [ArgumentOutOfRangeException]::new('id')}
        return [Lexicon]::Forms().Substring($id*16,16).Trim()
    }
    static [int] Find([string]$word) {
        if ([object]::ReferenceEquals($null,$word)) {return -1}
        if ($word.Length -gt 16) {return -1}
        [string]$key=$word.ToLowerInvariant().PadRight(16)
        [int]$low=0
        [int]$high=[Lexicon]::Count()-1
        while ($low -le $high) {
            [int]$half=($high-$low)/2
            [int]$mid=$low+$half
            [int]$cmp=[string]::CompareOrdinal([Lexicon]::Forms().Substring($mid*16,16),$key)
            if ($cmp -eq 0) {return $mid}
            if ($cmp -lt 0) {$low=$mid+1} else {$high=$mid-1}
        }
        return -1
    }
    static [int] Capabilities([int]$id) {
        if ($id -lt 0 -or $id -ge [Lexicon]::Count()) {throw [ArgumentOutOfRangeException]::new('id')}
        return [Convert]::ToInt32([Lexicon]::Flags().Substring($id*4,4),16)
    }
    static [string] Phones([int]$id,[int]$role) {
        if ($id -lt 0 -or $id -ge [Lexicon]::Count() -or $role -lt 0 -or $role -ge 5) {throw [ArgumentOutOfRangeException]::new('idOrRole')}
        [int]$alternate=[Convert]::ToInt32([Lexicon]::RoleIndexes().get_Chars($id))-4096
        [int]$slot=$id*3
        [string]$ranges=[Lexicon]::Offsets()
        if ($alternate -gt 0) {$ranges=[Lexicon]::Alternates();$slot=(($alternate-1)*5+$role)*3}
        [int]$start=[Convert]::ToInt32($ranges.get_Chars($slot))-4096
        [int]$high=[Convert]::ToInt32($ranges.get_Chars($slot+1))-4096
        $start=$start+$high*4096
        [int]$length=[Convert]::ToInt32($ranges.get_Chars($slot+2))-4096
        return [Lexicon]::Sequences().Substring($start,$length)
    }
}
class Phonology {
    static [string] Vocabulary() {return '@VOCAB@'}
    static [int] SymbolId([char]$phone) {
        if ([Convert]::ToInt32($phone) -eq 65535) {return -1}
        return [Phonology]::Vocabulary().IndexOf($phone)
    }
}
'@
    $generated=$template.Replace('@COUNT@',[string]$facts.Count).Replace('@FORMS@',$forms.ToString().Replace("'","''")).Replace('@FLAGS@',$caps.ToString()).Replace('@OFFSETS@',$offsets.ToString()).Replace('@ROLES@',$roles.ToString()).Replace('@ALTERNATES@',$alternates.ToString()).Replace('@PHONES@',$phones.ToString()).Replace('@VOCAB@',(-join $symbols))
    $directory=[IO.Path]::GetDirectoryName($OutputPath)
    [void][IO.Directory]::CreateDirectory($directory)
    $sourceFile=Join-Path $directory 'compiled-reference.ps1'
    if(Test-Path -LiteralPath $sourceFile){Copy-Item -LiteralPath $sourceFile -Destination ($sourceFile+'.before') -Force}
    if(Test-Path -LiteralPath $OutputPath){Copy-Item -LiteralPath $OutputPath -Destination ($OutputPath+'.before') -Force}
    [IO.File]::WriteAllText($sourceFile,$generated,[Text.UTF8Encoding]::new($false))
    $result=Export-LoweredAssembly -SourcePath $sourceFile -ClassName Lexicon -OutputPath $OutputPath -Deterministic
    $inspection=Test-LoweredAssembly -AssemblyPath $OutputPath
    if($inspection.AssemblyReferences.Count -ne 1 -or $inspection.AssemblyReferences[0] -cne 'System.Private.CoreLib'){throw 'Unexpected compiled reference dependency.'}
    $receipt=[pscustomobject]@{Assembly=$inspection;LexicalIdentities=$facts.Count;SourceSha256=$authorSourceSha;CompilerCommit='1afabe056235a570da29e268824784557d4f6cdd';DataOrigin=$Source;DataStatistics=if($Source -ceq 'Moby'){$script:EnglishLexicalBuildStatistics}else{$null};TargetVocabularySha256=(Get-FileHash -LiteralPath $configPath).Hash;Types=$result.Classes;Methods=$result.EmittedMethods;LanguageMode=[string]$ExecutionContext.SessionState.LanguageMode;Runtime=[Runtime.InteropServices.RuntimeInformation]::FrameworkDescription}
    $receipt | Export-Clixml -LiteralPath (Join-Path $directory 'build-receipt.clixml')
    $receipt
}

class EnglishOccurrence {
    [int]$Identity
    [int]$LexicalId
    [int]$Capabilities
    [string]$Text
    [int]$Start
    [int]$End
    [string]$Kind='Word'
    [object]$Value
}
class EnglishNominal {
    [EnglishOccurrence]$Head
    [EnglishOccurrence]$Determiner
    [EnglishOccurrence[]]$Modifiers=@()
    [int[]]$Dependencies=@()
}
class EnglishClause {
    [string]$Voice
    [string]$Tense
    [EnglishNominal]$Subject
    [EnglishOccurrence]$Predicate
    [EnglishNominal]$Object
    [EnglishOccurrence]$Auxiliary
    [EnglishNominal]$Agent
    [EnglishNominal]$Time
    [EnglishClause]$Complement
    [int[]]$Dependencies=@()
}
class EnglishRequirement {
    [EnglishNominal]$Subject
    [EnglishOccurrence]$Operation
    [string]$Missing
    [int[]]$Dependencies=@()
}
function New-EnglishRequirement {
    [CmdletBinding(DefaultParameterSetName='Operation')]
    param(
        [Parameter(Mandatory,ParameterSetName='Operation')][EnglishNominal]$Subject,
        [Parameter(Mandatory,ParameterSetName='Operation')][ValidateScript({($_.Capabilities -band (2+64+4096)) -ne 0})][EnglishOccurrence]$Operation,
        [Parameter(Mandatory,ParameterSetName='Determiner')][ValidateScript({($_.Capabilities -band 32) -ne 0})][EnglishOccurrence]$Determiner
    )
    $r=[EnglishRequirement]::new()
    if($PSCmdlet.ParameterSetName -ceq 'Determiner'){$r.Operation=$Determiner;$r.Missing='NominalHead';$r.Dependencies=@($Determiner.Identity);return $r}
    $r.Subject=$Subject;$r.Operation=$Operation
    $r.Missing=if(($Operation.Capabilities -band (64+4096)) -ne 0){'Predicate'}elseif(($Operation.Capabilities -band 1024) -ne 0){'Object'}else{'None'}
    $r.Dependencies=$Subject.Dependencies+@($Operation.Identity)
    $r
}

function New-EnglishNominal {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][ValidateScript({($_.Capabilities -band 1) -ne 0})][EnglishOccurrence]$Head,
        [ValidateScript({($_.Capabilities -band 32) -ne 0})][EnglishOccurrence]$Determiner,
        [ValidateScript({($_.Capabilities -band 4) -ne 0})][EnglishOccurrence[]]$Modifiers=@()
    )
    $n=[EnglishNominal]::new();$n.Head=$Head;$n.Determiner=$Determiner;$n.Modifiers=$Modifiers
    $n.Dependencies=@($Head.Identity)+@($Modifiers | ForEach-Object Identity)
    if($null -ne $Determiner){$n.Dependencies+=@($Determiner.Identity)}
    $n
}

function Invoke-EnglishClause {
    [CmdletBinding(DefaultParameterSetName='Active')]
    param(
        [Parameter(Mandatory,ParameterSetName='Active')]
        [Parameter(Mandatory,ParameterSetName='Stative')][EnglishNominal]$Subject,
        [Parameter(Mandatory,ParameterSetName='Active')][ValidateScript({($_.Capabilities -band 2) -ne 0})][EnglishOccurrence]$Verb,
        [Parameter(ParameterSetName='Active')][EnglishNominal]$Object,
        [Parameter(Mandatory,ParameterSetName='Passive')][EnglishNominal]$Patient,
        [Parameter(Mandatory,ParameterSetName='Passive')][ValidateScript({($_.Capabilities -band 8) -ne 0})][EnglishOccurrence]$Participle,
        [Parameter(Mandatory,ParameterSetName='Stative')][ValidateScript({($_.Capabilities -band 4) -ne 0})][EnglishOccurrence]$Property,
        [Parameter(Mandatory,ParameterSetName='Passive')]
        [Parameter(Mandatory,ParameterSetName='Stative')][ValidateScript({($_.Capabilities -band 64) -ne 0})][EnglishOccurrence]$Copula,
        [Parameter(ParameterSetName='Active')][ValidateScript({($_.Capabilities -band 4096) -ne 0})][EnglishOccurrence]$Perfect,
        [Parameter(ParameterSetName='Active')][ValidateSet('Unspecified','Present','Past','Perfect')][string]$Tense='Unspecified'
    )
    $c=[EnglishClause]::new();$c.Voice=$PSCmdlet.ParameterSetName;$c.Tense=$Tense
    if($PSCmdlet.ParameterSetName -ceq 'Passive'){$c.Subject=$Patient;$c.Predicate=$Participle;$c.Auxiliary=$Copula}
    elseif($PSCmdlet.ParameterSetName -ceq 'Stative'){$c.Subject=$Subject;$c.Predicate=$Property;$c.Auxiliary=$Copula}
    else{
        if(($Verb.Capabilities -band 1024) -ne 0 -and $null -eq $Object){throw 'Transitive operation requires an object.'}
        $c.Subject=$Subject;$c.Predicate=$Verb;$c.Object=$Object;$c.Auxiliary=$Perfect
    }
    $c.Dependencies=$c.Subject.Dependencies+@($c.Predicate.Identity)
    if($null -ne $c.Object){$c.Dependencies+=$c.Object.Dependencies}
    if($null -ne $c.Auxiliary){$c.Dependencies+=@($c.Auxiliary.Identity)}
    $c
}

function Add-EnglishRelation {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][EnglishClause]$Clause,
        [Parameter(Mandatory)][ValidateScript({($_.Capabilities -band 128) -ne 0})][EnglishOccurrence]$Relation,
        [Parameter(Mandatory)][EnglishNominal]$Complement
    )
    $c=[EnglishClause]::new()
    foreach($name in @('Voice','Subject','Predicate','Object','Auxiliary','Agent','Time','Complement','Dependencies')){$c.$name=$Clause.$name}
    if(($Complement.Head.Capabilities -band 512) -ne 0){$c.Time=$Complement}
    elseif(($Complement.Head.Capabilities -band 256) -ne 0 -and $c.Voice -ceq 'Passive'){$c.Agent=$Complement}
    else{throw 'Unsupported relation interpretation.'}
    $c.Dependencies+=$Complement.Dependencies+@($Relation.Identity)
    $c
}

function Import-EnglishReference {
    param([string]$Path)
    $path=[IO.Path]::GetFullPath($Path)
    if($script:EnglishReferenceCache.ContainsKey($path)){return $script:EnglishReferenceCache[$path]}
    $receiptPath=Join-Path ([IO.Path]::GetDirectoryName($path)) 'build-receipt.clixml'
    $receipt=Import-Clixml -LiteralPath $receiptPath
    if((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -cne $receipt.Assembly.SHA256){throw 'Compiled reference integrity failure.'}
    $assembly=[Reflection.Assembly]::LoadFrom($path)
    if($assembly.GetName().Name -cne 'Dev.MansfieldPlumbing.English.Phonemizer'){throw 'Unexpected reference identity.'}
    $lex=$assembly.GetType('Lexicon',$true);$ph=$assembly.GetType('Phonology',$true)
    $reference=[pscustomobject]@{
        Assembly=$assembly
        Find=[Func[string,int]]$lex.GetMethod('Find').CreateDelegate([Func[string,int]])
        Flags=[Func[int,int]]$lex.GetMethod('Capabilities').CreateDelegate([Func[int,int]])
        Phones=[Func[int,int,string]]$lex.GetMethod('Phones').CreateDelegate([Func[int,int,string]])
        Form=[Func[int,string]]$lex.GetMethod('Form').CreateDelegate([Func[int,string]])
        SymbolId=[Func[char,int]]$ph.GetMethod('SymbolId').CreateDelegate([Func[char,int]])
        Count=$lex.GetMethod('Count').Invoke($null,@())
    }
    $script:EnglishReferenceCache[$path]=$reference
    $reference
}

function New-EnglishCandidate {
    param($From=$null)
    $c=[pscustomobject]@{Subject=$null;Determiner=$null;Modifiers=@();Auxiliary=$null;Predicate=$null;Object=$null;Clause=$null;Relation=$null;Requirement=$null;PredicateRole=1;Tense='Unspecified';Phase='Subject';Voice='Active';Status='Pending';Choices=@{};Bindings=@();Need='Nominal';DependencyIds=@()}
    if($null -ne $From){
        foreach($p in $From.PSObject.Properties){$c.($p.Name)=$p.Value}
        $c.Choices=@{}+$From.Choices;$c.Bindings=@($From.Bindings);$c.Modifiers=@($From.Modifiers)
    }
    $c
}

function New-EnglishContext {
    param([string]$ReferencePath=$AssemblyPath,[switch]$Profile)
    [pscustomobject]@{
        Reference=(Import-EnglishReference $ReferencePath)
        Text='';Occurrences=[Collections.Generic.List[EnglishOccurrence]]::new()
        Candidates=@(New-EnglishCandidate);Withdrawn=[Collections.Generic.List[object]]::new()
        Revision=0;Invocations=0;Trace=[Collections.Generic.List[object]]::new();Evidence=@{}
        MaximumCandidates=16;MaximumOccurrences=256;Boundary=$false
        Profile=if($Profile){@{}}else{$null}
    }
}

function Start-EnglishMeasure {
    param([string]$Phase)
    [pscustomobject]@{Phase=$Phase;Ticks=[Diagnostics.Stopwatch]::GetTimestamp();Allocated=[GC]::GetAllocatedBytesForCurrentThread()}
}
function Stop-EnglishMeasure {
    param($Context,$Measurement)
    $ticks=[Diagnostics.Stopwatch]::GetTimestamp()-$Measurement.Ticks
    $bytes=[GC]::GetAllocatedBytesForCurrentThread()-$Measurement.Allocated
    if(-not $Context.Profile.ContainsKey($Measurement.Phase)){$Context.Profile[$Measurement.Phase]=[pscustomobject]@{Calls=0;Ticks=[long]0;AllocatedBytes=[long]0}}
    $entry=$Context.Profile[$Measurement.Phase];$entry.Calls++;$entry.Ticks+=$ticks;$entry.AllocatedBytes+=$bytes
}

function Add-EnglishBindingTrace {
    param($Context,$Candidate,[string]$Command,[hashtable]$Arguments,$Result)
    if($null -ne $Context.Profile){$measurement=Start-EnglishMeasure 'TraceMaterialization'}
    $definition=(Get-Command -Name $Command -CommandType Function).ScriptBlock.Ast
    $binding=[pscustomobject]@{Revision=$Context.Revision;Command=$Command;InvocationTemplate=$Command+' '+(($Arguments.Keys | Sort-Object | ForEach-Object {'-'+$_+' $bound.'+$_}) -join ' ');SmaAst=$definition.GetType().Name;DefinitionFile=$definition.Extent.File;DefinitionLine=$definition.Extent.StartLineNumber;Arguments=@($Arguments.GetEnumerator() | Sort-Object Key | ForEach-Object {[pscustomobject]@{Parameter=$_.Key;Type=$_.Value.GetType().FullName}});OutputType=$Result.GetType().FullName;Dependencies=@($Result.Dependencies)}
    $Candidate.Bindings+=@($binding);$Context.Trace.Add($binding);$Context.Invocations++
    if($null -ne $Context.Profile){Stop-EnglishMeasure $Context $measurement}
}

function Complete-EnglishNominal {
    param($Context,$Candidate,[EnglishOccurrence]$Occurrence)
    $args=@{Head=$Occurrence;Modifiers=[EnglishOccurrence[]]$Candidate.Modifiers}
    if($null -ne $Candidate.Determiner){$args.Determiner=$Candidate.Determiner}
    # Fixed command identity and file-authored body; input supplies data only.
    if($null -ne $Context.Profile){$measurement=Start-EnglishMeasure 'NativeCommands'}
    $nominal=New-EnglishNominal @args
    if($null -ne $Context.Profile){Stop-EnglishMeasure $Context $measurement}
    Add-EnglishBindingTrace $Context $Candidate 'New-EnglishNominal' $args $nominal
    $Candidate.Choices[$Occurrence.Identity]=0
    if($null -ne $Candidate.Determiner){$Candidate.Choices[$Candidate.Determiner.Identity]=4}
    foreach($mod in $Candidate.Modifiers){$Candidate.Choices[$mod.Identity]=2}
    $Candidate.Determiner=$null;$Candidate.Modifiers=@()
    $nominal
}

function Complete-EnglishClause {
    param($Context,$Candidate)
    $args=@{}
    if($Candidate.Voice -ceq 'Passive'){$args=@{Patient=$Candidate.Subject;Participle=$Candidate.Predicate;Copula=$Candidate.Auxiliary};$role=3}
    elseif($Candidate.Voice -ceq 'Stative'){$args=@{Subject=$Candidate.Subject;Property=$Candidate.Predicate;Copula=$Candidate.Auxiliary};$role=2}
    else{
        $args=@{Subject=$Candidate.Subject;Verb=$Candidate.Predicate;Tense=$Candidate.Tense};$role=$Candidate.PredicateRole
        if($null -ne $Candidate.Object){$args.Object=$Candidate.Object}
        if($null -ne $Candidate.Auxiliary){$args.Perfect=$Candidate.Auxiliary;$role=3}
    }
    if($null -ne $Context.Profile){$measurement=Start-EnglishMeasure 'NativeCommands'}
    $clause=Invoke-EnglishClause @args
    if($null -ne $Context.Profile){Stop-EnglishMeasure $Context $measurement}
    Add-EnglishBindingTrace $Context $Candidate 'Invoke-EnglishClause' $args $clause
    $Candidate.Choices[$Candidate.Predicate.Identity]=$role
    if($null -ne $Candidate.Auxiliary){$Candidate.Choices[$Candidate.Auxiliary.Identity]=4}
    $Candidate.Clause=$clause;$Candidate.Phase='Extension';$Candidate.Status='Extensible';$Candidate.Need='OptionalRelation'
}

function Add-EnglishOccurrence {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Context,[Parameter(Mandatory)][EnglishOccurrence]$Occurrence)
    if($Context.Occurrences.Count -ge $Context.MaximumOccurrences){throw 'Utterance occurrence bound exceeded.'}
    $Occurrence.Identity=$Context.Occurrences.Count;$Context.Occurrences.Add($Occurrence);$Context.Revision++
    if($Occurrence.Kind -ceq 'Boundary'){$Context.Boundary=$Occurrence.Text -cin @('.','!','?');return}
    $Context.Boundary=$false
    $next=[Collections.Generic.List[object]]::new()
    foreach($prior in $Context.Candidates){
        $c=New-EnglishCandidate $prior
        if($c.Status -cin @('Unsupported','Contradictory')){$next.Add($c);continue}
        $f=$Occurrence.Capabilities
        if($Occurrence.LexicalId -lt 0){$c.Status='Unsupported';$c.Need='UnknownLexicalIdentity';$next.Add($c);continue}
        if($c.Phase -cin @('Subject','Object','RelationComplement')){
            if(($f -band 32) -ne 0 -and $null -eq $c.Determiner){
                $det=New-EnglishCandidate $c;$det.Determiner=$Occurrence;$det.Choices[$Occurrence.Identity]=4;$det.Status='Pending';$det.Need='NominalHead';$next.Add($det)
                $args=@{Determiner=$Occurrence}
                if($null -ne $Context.Profile){$measurement=Start-EnglishMeasure 'NativeCommands'}
                $det.Requirement=New-EnglishRequirement @args
                if($null -ne $Context.Profile){Stop-EnglishMeasure $Context $measurement}
                Add-EnglishBindingTrace $Context $det 'New-EnglishRequirement' $args $det.Requirement
            }
            if(($f -band 4) -ne 0 -and $null -ne $c.Determiner){
                $mod=New-EnglishCandidate $c;$mod.Modifiers+=@($Occurrence);$mod.Choices[$Occurrence.Identity]=2;$mod.Need='NominalHead';$next.Add($mod)
            }
            if(($f -band 1) -ne 0){
                $nominal=Complete-EnglishNominal $Context $c $Occurrence
                switch($c.Phase){
                    'Subject' {$c.Subject=$nominal;$c.Phase='Predicate';$c.Status='Extensible';$c.Need='Predicate'}
                    'Object' {$c.Object=$nominal;Complete-EnglishClause $Context $c}
                    'RelationComplement' {
                        if(($f -band 512) -ne 0 -or (($f -band 256) -ne 0 -and $c.Voice -ceq 'Passive')){
                            $args=@{Clause=$c.Clause;Relation=$c.Relation;Complement=$nominal}
                            if($null -ne $Context.Profile){$measurement=Start-EnglishMeasure 'NativeCommands'}
                            $result=Add-EnglishRelation @args
                            if($null -ne $Context.Profile){Stop-EnglishMeasure $Context $measurement}
                            Add-EnglishBindingTrace $Context $c 'Add-EnglishRelation' $args $result
                            $c.Clause=$result;$c.Phase='Extension';$c.Status='Extensible';$c.Need='OptionalRelation'
                        }else{$c.Status='Unsupported';$c.Need='RelationSense';$Context.Withdrawn.Add([pscustomobject]@{Revision=$Context.Revision;Reason='UnsupportedRelationSense';Candidate=$prior})}
                    }
                }
                $next.Add($c)
            }
            if(($f -band (1+4+32)) -eq 0){$c.Status='Contradictory';$c.Need='NominalHead';$next.Add($c)}
        }
        elseif($c.Phase -ceq 'Predicate'){
            if(($f -band (64+4096)) -ne 0){
                $args=@{Subject=$c.Subject;Operation=$Occurrence}
                if($null -ne $Context.Profile){$measurement=Start-EnglishMeasure 'NativeCommands'}
                $c.Requirement=New-EnglishRequirement @args
                if($null -ne $Context.Profile){Stop-EnglishMeasure $Context $measurement}
                Add-EnglishBindingTrace $Context $c 'New-EnglishRequirement' $args $c.Requirement
                $c.Auxiliary=$Occurrence;$c.Choices[$Occurrence.Identity]=4;$c.Phase='AfterAuxiliary';$c.Status='Pending';$c.Need=$c.Requirement.Missing;$next.Add($c)
            }
            elseif(($f -band 2) -ne 0){
                $c.Predicate=$Occurrence;$c.Choices[$Occurrence.Identity]=1
                $args=@{Subject=$c.Subject;Operation=$Occurrence}
                if($null -ne $Context.Profile){$measurement=Start-EnglishMeasure 'NativeCommands'}
                $c.Requirement=New-EnglishRequirement @args
                if($null -ne $Context.Profile){Stop-EnglishMeasure $Context $measurement}
                Add-EnglishBindingTrace $Context $c 'New-EnglishRequirement' $args $c.Requirement
                if(($f -band 1024) -ne 0){$c.Phase='Object';$c.Status='Pending';$c.Need='Object'}else{Complete-EnglishClause $Context $c}
                $next.Add($c)
                if(($f -band 8192) -ne 0){
                    $past=New-EnglishCandidate $c;$past.PredicateRole=3;$past.Tense='Past';$past.Choices[$Occurrence.Identity]=3
                    $c.Tense='Present'
                    if($past.Phase -ceq 'Extension'){Complete-EnglishClause $Context $past}
                    $next.Add($past)
                }
            }else{$c.Status='Contradictory';$c.Need='CallablePredicate';$next.Add($c)}
        }
        elseif($c.Phase -ceq 'AfterAuxiliary'){
            if(($c.Auxiliary.Capabilities -band 4096) -ne 0 -and ($f -band 8) -ne 0){
                $c.Predicate=$Occurrence;$c.Choices[$Occurrence.Identity]=3
                if(($f -band 1024) -ne 0){$c.Phase='Object';$c.Need='Object'}else{Complete-EnglishClause $Context $c}
                $next.Add($c)
            }elseif(($c.Auxiliary.Capabilities -band 64) -ne 0){
                if(($f -band 8) -ne 0){$passive=New-EnglishCandidate $c;$passive.Predicate=$Occurrence;$passive.Voice='Passive';Complete-EnglishClause $Context $passive;$next.Add($passive)}
                if(($f -band 4) -ne 0){$stative=New-EnglishCandidate $c;$stative.Predicate=$Occurrence;$stative.Voice='Stative';Complete-EnglishClause $Context $stative;$next.Add($stative)}
                if(($f -band 12) -eq 0){$c.Status='Unsupported';$c.Need='CopularComplement';$next.Add($c)}
            }else{$c.Status='Contradictory';$c.Need='Participle';$next.Add($c)}
        }
        elseif($c.Phase -ceq 'Extension'){
            if(($f -band 128) -ne 0){$c.Relation=$Occurrence;$c.Choices[$Occurrence.Identity]=4;$c.Phase='RelationComplement';$c.Status='Pending';$c.Need='RelationComplement';$next.Add($c)}
            elseif(($c.Predicate.Capabilities -band 2048) -ne 0 -and ($f -band 2) -ne 0 -and ($f -band 1024) -eq 0){
                $args=@{Subject=$c.Object;Verb=$Occurrence}
                if($null -ne $Context.Profile){$measurement=Start-EnglishMeasure 'NativeCommands'}
                $embedded=Invoke-EnglishClause @args
                if($null -ne $Context.Profile){Stop-EnglishMeasure $Context $measurement}
                Add-EnglishBindingTrace $Context $c 'Invoke-EnglishClause' $args $embedded
                $parent=[EnglishClause]::new()
                foreach($name in @('Voice','Subject','Predicate','Object','Auxiliary','Dependencies')){$parent.$name=$c.Clause.$name}
                $parent.Complement=$embedded;$parent.Dependencies+=$embedded.Dependencies
                $c.Clause=$parent;$c.Choices[$Occurrence.Identity]=1;$next.Add($c)
            }else{$c.Status='Unsupported';$c.Need='AdditionalConstruction';$next.Add($c)}
        }
    }
    if($next.Count -gt $Context.MaximumCandidates){throw 'Grammatical alternative bound exceeded; input not silently pruned.'}
    $Context.Candidates=$next.ToArray()
}

function Add-EnglishText {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Context,[Parameter(Mandatory)][AllowEmptyString()][string]$Chunk)
    if($Context.Text.Length+$Chunk.Length -gt 8192){throw 'Source extent bound exceeded.'}
    # Chunks end at lexical boundaries. Arbitrary mid-word chunks need buffering.
    $base=$Context.Text.Length;$Context.Text+=$Chunk;$at=0
    while($at -lt $Chunk.Length){
        if([char]::IsWhiteSpace($Chunk[$at])){$at++;continue}
        if($null -ne $Context.Profile){$scan=Start-EnglishMeasure 'TokenScan'}
        $start=$at;$kind='Word'
        if([char]::IsLetterOrDigit($Chunk[$at]) -or $Chunk[$at] -ceq '$'){
            $at++
            while($at -lt $Chunk.Length -and ([char]::IsLetterOrDigit($Chunk[$at]) -or $Chunk[$at] -cin @([char]39,[char]0x2019))){$at++}
        }else{$kind='Boundary';$at++}
        $o=[EnglishOccurrence]::new();$o.Text=$Chunk.Substring($start,$at-$start);$o.Start=$base+$start;$o.End=$base+$at;$o.Kind=$kind
        if($null -ne $Context.Profile){Stop-EnglishMeasure $Context $scan;$lookup=Start-EnglishMeasure 'ReferenceLookup'}
        $o.LexicalId=if($kind -ceq 'Word'){$Context.Reference.Find.Invoke($o.Text)}else{-1}
        if($o.LexicalId -ge 0){$o.Capabilities=$Context.Reference.Flags.Invoke($o.LexicalId)}
        if($null -ne $Context.Profile){Stop-EnglishMeasure $Context $lookup;$activation=Start-EnglishMeasure 'ConstructionActivation'}
        Add-EnglishOccurrence $Context $o
        if($null -ne $Context.Profile){Stop-EnglishMeasure $Context $activation}
    }
}

function Get-EnglishResult {
    param($Context)
    if($null -ne $Context.Profile){$filter=Start-EnglishMeasure 'EvidenceFiltering'}
    $viable=@($Context.Candidates | Where-Object Status -cnotin @('Unsupported','Contradictory'))
    $contextRejected=[Collections.Generic.List[object]]::new()
    foreach($constraint in $Context.Evidence.Values){
        $accepted=[Collections.Generic.List[object]]::new()
        foreach($candidate in $viable){
            if(-not $candidate.Choices.ContainsKey($constraint.OccurrenceIdentity) -or $candidate.Choices[$constraint.OccurrenceIdentity] -in $constraint.Roles){$accepted.Add($candidate)}
            else{$contextRejected.Add([pscustomobject]@{Revision=$Context.Revision;Reason='LinkedObjectGraphConstraint';Evidence=$constraint.Id;Candidate=$candidate})}
        }
        $viable=$accepted.ToArray()
    }
    $status=if($viable.Count -gt 1){'Ambiguous'}elseif($viable.Count -eq 1){if($Context.Boundary -and $viable[0].Status -ceq 'Extensible' -and $null -ne $viable[0].Clause){'Resolved'}else{$viable[0].Status}}elseif(@($Context.Candidates | Where-Object Status -ceq 'Unsupported').Count){'Unsupported'}else{'Contradictory'}
    if($null -ne $Context.Profile){Stop-EnglishMeasure $Context $filter;$projection=Start-EnglishMeasure 'ProjectionAndResult'}
    $tokens=[Collections.Generic.List[object]]::new();$parts=[Collections.Generic.List[string]]::new();$ids=[Collections.Generic.List[int]]::new();$unresolved=[Collections.Generic.List[object]]::new();$cursor=0
    foreach($o in $Context.Occurrences){
        $phone=$null;$roles=@();$alternatives=@();$reason=$null
        if($o.Kind -ceq 'Boundary'){
            if($Context.Reference.SymbolId.Invoke($o.Text[0]) -ge 0){$phone=$o.Text}else{$reason='UnsupportedSymbol'}
        }elseif($o.LexicalId -lt 0){$reason='UnknownLexicalIdentity'}
        elseif($viable.Count -eq 0){$reason='NoAdmittedRelationship'}
        else{
            $roles=@($viable | ForEach-Object {if($_.Choices.ContainsKey($o.Identity)){$_.Choices[$o.Identity]}else{-1}} | Sort-Object -Unique)
            if($roles -contains -1){$reason='PendingRole'}
            else{
                $alternatives=@($roles | ForEach-Object {$Context.Reference.Phones.Invoke($o.LexicalId,$_).Split('|',[StringSplitOptions]::RemoveEmptyEntries)} | Sort-Object -Unique -CaseSensitive)
                if($alternatives.Count -eq 1 -and $alternatives[0].Length -gt 0){$phone=$alternatives[0]}else{$reason='PronunciationAmbiguous'}
            }
        }
        # Unambiguous lexical projection does not require a resolved clause.
        if($null -eq $phone -and $o.LexicalId -ge 0){
            $all=@(0..4 | ForEach-Object {$Context.Reference.Phones.Invoke($o.LexicalId,$_).Split('|',[StringSplitOptions]::RemoveEmptyEntries)} | Sort-Object -Unique -CaseSensitive)
            if($all.Count -eq 1){$phone=$all[0];$reason=$null}
        }
        $start=$null;$end=$null
        if($null -ne $phone){
            if($parts.Count -gt 0){$ids.Add(16);$cursor++}
            $start=$cursor
            foreach($ch in $phone.ToCharArray()){
                $symbol=$Context.Reference.SymbolId.Invoke($ch)
                if($symbol -lt 0){throw 'Compiled phone outside target vocabulary.'}
                $ids.Add($symbol);$cursor++
            }
            $end=$cursor;$parts.Add($phone)
        }
        $record=[pscustomobject]@{Identity=$o.Identity;LexicalId=$o.LexicalId;Word=$o.Text;SourceStart=$o.Start;SourceEnd=$o.End;Pron=$phone;SymbolIds=if($phone){[int[]]@($phone.ToCharArray() | ForEach-Object {$Context.Reference.SymbolId.Invoke($_)})}else{@()};Roles=$roles;Alternatives=$alternatives;Status=if($phone){'Valid'}else{$reason};EmissionStart=$start;EmissionEnd=$end}
        $tokens.Add($record);if($null -ne $reason){$unresolved.Add($record)}
    }
    [pscustomobject]@{
        OriginalText=$Context.Text;ProjectedText=$null;Reversible=$true
        KokoroPhones=if($unresolved.Count -eq 0){$parts -join ' '}else{$null}
        SupportedPhones=$parts -join ' ';SymbolIds=$ids.ToArray();Tokens=$tokens.ToArray()
        Complete=$unresolved.Count -eq 0;GrammarStatus=$status;PronunciationStatus=if($unresolved.Count -eq 0){'Resolved'}else{'UnsupportedOrPending'}
        Candidates=$viable;RetainedCandidates=$Context.Candidates;UnresolvedSpans=$unresolved.ToArray();OovSpans=@($unresolved | Where-Object Status -ceq 'UnknownLexicalIdentity')
        AmbiguousDecisions=@($tokens | Where-Object {$_.Roles.Count -gt 1 -or $_.Alternatives.Count -gt 1})
        Bindings=$Context.Trace.ToArray();Withdrawn=@($Context.Withdrawn.ToArray())+@($contextRejected.ToArray());Revision=$Context.Revision
        Pending=@($viable | Where-Object Status -ceq 'Pending' | ForEach-Object Need)
        Execution='SMA named parameter binding';ReferenceAssembly=$Context.Reference.Assembly.GetName().Name
    }
    if($null -ne $Context.Profile){Stop-EnglishMeasure $Context $projection}
}

function Add-EnglishContextEvidence {
    [CmdletBinding(DefaultParameterSetName='Entity')]
    param(
        [Parameter(Mandatory)]$Context,
        [Parameter(Mandatory)][ValidateRange(0,255)][int]$OccurrenceIdentity,
        [Parameter(Mandatory,ParameterSetName='Entity')][EnglishNominal]$Entity,
        [Parameter(Mandatory,ParameterSetName='Event')][EnglishClause]$Event,
        [Parameter(Mandatory)][ValidateLength(1,256)][string]$EvidenceIdentity
    )
    if($OccurrenceIdentity -ge $Context.Occurrences.Count){throw 'Evidence target is outside the active source.'}
    $occurrence=$Context.Occurrences[$OccurrenceIdentity]
    $referent=if($PSCmdlet.ParameterSetName -ceq 'Entity'){$Entity.Head}else{$Event.Predicate}
    if($occurrence.LexicalId -lt 0 -or $referent.LexicalId -ne $occurrence.LexicalId){throw 'Explicit lexical reference link is required.'}
    # The caller supplies a grounded link, not a proximity heuristic or POS guess.
    # Candidate graphs stay retained; withdrawing evidence restores alternatives.
    $Context.Evidence[$EvidenceIdentity]=[pscustomobject]@{Id=$EvidenceIdentity;OccurrenceIdentity=$OccurrenceIdentity;Referent=$referent;Roles=if($PSCmdlet.ParameterSetName -ceq 'Entity'){@(0)}else{@(1,3)}}
    Get-EnglishResult $Context
}

function Remove-EnglishContextEvidence {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Context,[Parameter(Mandatory)][string]$EvidenceIdentity)
    $Context.Evidence.Remove($EvidenceIdentity)
    Get-EnglishResult $Context
}

function Invoke-EnglishPhonemizer {
    [CmdletBinding()]
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Text,$Context=$null,[string]$ReferencePath=$AssemblyPath)
    $start=[Diagnostics.Stopwatch]::StartNew()
    if($null -eq $Context){$Context=New-EnglishContext -ReferencePath $ReferencePath}
    Add-EnglishText -Context $Context -Chunk $Text
    $result=Get-EnglishResult $Context
    $result | Add-Member -NotePropertyName Timing -NotePropertyValue ([pscustomobject]@{TotalMs=$start.Elapsed.TotalMilliseconds;BinderInvocations=$Context.Invocations})
    $result
}

function Assert-EnglishContract {
    param([string]$Name,[bool]$Condition)
    if(-not $Condition){throw ('English behavioral contract failed: '+$Name)}
}

function Test-EnglishPhonemizer {
    [CmdletBinding()]
    param([string]$ReferencePath=$AssemblyPath)
    $checks=[Collections.Generic.List[string]]::new()
    $reference=Import-EnglishReference $ReferencePath
    Assert-EnglishContract 'managed assembly identity' ($reference.Assembly.GetName().Name -ceq 'Dev.MansfieldPlumbing.English.Phonemizer')
    $references=@($reference.Assembly.GetReferencedAssemblies() | ForEach-Object Name)
    Assert-EnglishContract 'CoreLib only' ($references.Count -eq 1 -and $references[0] -ceq 'System.Private.CoreLib')
    Assert-EnglishContract 'no mutable data fields' (@($reference.Assembly.GetTypes() | ForEach-Object { $_.GetFields([Reflection.BindingFlags]'Public,NonPublic,Static,Instance') }).Count -eq 0)
    Assert-EnglishContract 'executable accessor' ($reference.Find.Invoke('record') -ge 0 -and $reference.Phones.Invoke($reference.Find.Invoke('record'),1) -ceq 'ɹɪkˈɔɹd')
    $checks.Add('Fresh process executable managed reference, immutable data, CoreLib only')
    $ctx=New-EnglishContext -ReferencePath $ReferencePath
    $states=[Collections.Generic.List[object]]::new()
    foreach($chunk in @('the ','door ','was ','closed')){
        Add-EnglishText $ctx $chunk;$r=Get-EnglishResult $ctx
        $states.Add([pscustomobject]@{Source=$ctx.Text;Status=$r.GrammarStatus;Pending=$r.Pending;Bindings=$r.Bindings.Count;Phones=$r.KokoroPhones})
    }
    Assert-EnglishContract 'determiner pending nominal head' ($states[0].Pending -contains 'NominalHead')
    Assert-EnglishContract 'native auxiliary deferred binding' ($states[2].Pending -contains 'Predicate' -and @($r.Bindings | Where-Object Command -ceq 'New-EnglishRequirement').Count -eq 2)
    Assert-EnglishContract 'closure retains passive and stative' ($r.Candidates.Count -eq 2 -and $r.Complete)
    Add-EnglishText $ctx ' by Alice.';$agent=Get-EnglishResult $ctx
    Assert-EnglishContract 'later agent evidence' ($agent.Candidates.Count -eq 1 -and $agent.Candidates[0].Clause.Agent.Head.Text -ceq 'Alice')
    $time=Invoke-EnglishPhonemizer -Text 'The door was closed by noon.' -ReferencePath $ReferencePath
    Assert-EnglishContract 'by time is not an agent' ($time.Candidates.Count -eq 2 -and @($time.Candidates | Where-Object {$null -ne $_.Clause.Agent}).Count -eq 0)
    $checks.Add('Cascading native calls, pending operands, later agent vs time binding')
    $record=Invoke-EnglishPhonemizer -Text 'The record records the record.' -ReferencePath $ReferencePath
    Assert-EnglishContract 'three distinct record occurrences' ($record.Tokens[1].Roles[0] -eq 0 -and $record.Tokens[2].Roles[0] -eq 1 -and $record.Tokens[4].Roles[0] -eq 0 -and $record.Tokens[1].Identity -ne $record.Tokens[4].Identity)
    Assert-EnglishContract 'record projection fixture' ($record.KokoroPhones -ceq 'ðə ɹˈɛkəɹd ɹɪkˈɔɹdz ðə ɹˈɛkəɹd .')
    $transfer=@(
        @('They present the present.','present',1,'pɹɪzˈɛnt'),
        @('They permit the record.','permit',1,'pəɹmˈɪt'),
        @('They live.','live',1,'lˈɪv'),
        @('The music is live.','live',2,'lˈIv'),
        @('They close the door.','close',1,'klˈOz'),
        @('They wind the clock.','wind',1,'wˈInd'),
        @('They lead the cat.','lead',1,'lˈid'),
        @('They had read the record.','read',3,'ɹˈɛd')
    )
    foreach($case in $transfer){
        $result=Invoke-EnglishPhonemizer -Text $case[0] -ReferencePath $ReferencePath
        $target=@($result.Tokens | Where-Object Word -ceq $case[1])[0]
        Assert-EnglishContract ('shared binding: '+$case[1]) ($result.Complete -and $target.Roles -contains $case[2] -and $target.Pron -ceq $case[3])
    }
    $tense=Invoke-EnglishPhonemizer -Text 'They read the record.' -ReferencePath $ReferencePath
    Assert-EnglishContract 'read tense ambiguity retained' (-not $tense.Complete -and $tense.Candidates.Count -eq 2 -and $null -eq $tense.KokoroPhones)
    $checks.Add('Role-sensitive projection shared across eight supported cross-word fixtures; unresolved read tense retained')
    $ambiguous=New-EnglishContext -ReferencePath $ReferencePath
    Add-EnglishText $ambiguous 'I saw her duck.';$a=Get-EnglishResult $ambiguous
    Assert-EnglishContract 'genuine ambiguity can finish phones' ($a.Candidates.Count -eq 2 -and $a.GrammarStatus -ceq 'Ambiguous' -and $a.Complete)
    $transferred=Invoke-EnglishPhonemizer -Text 'I saw her shit.' -ReferencePath $ReferencePath
    Assert-EnglishContract 'perception complement transfers to another nominal and verb' ($transferred.Candidates.Count -eq 2 -and $transferred.GrammarStatus -ceq 'Ambiguous' -and $transferred.Complete -and @($transferred.Candidates | Where-Object {$null -ne $_.Clause.Complement}).Count -eq 1)
    $entity=Invoke-EnglishPhonemizer -Text 'The duck.' -ReferencePath $ReferencePath
    $target=@($ambiguous.Occurrences | Where-Object Text -ceq 'duck')[0].Identity
    $linked=Add-EnglishContextEvidence -Context $ambiguous -OccurrenceIdentity $target -Entity $entity.Candidates[0].Subject -EvidenceIdentity 'observed-nominal-link'
    Assert-EnglishContract 'linked nominal graph constrains reading' ($linked.Candidates.Count -eq 1 -and $null -eq $linked.Candidates[0].Clause.Complement)
    $restored=Remove-EnglishContextEvidence -Context $ambiguous -EvidenceIdentity 'observed-nominal-link'
    Assert-EnglishContract 'evidence withdrawal restores ambiguity' ($restored.Candidates.Count -eq 2 -and $restored.KokoroPhones -ceq $a.KokoroPhones)
    $event=Invoke-EnglishPhonemizer -Text 'They duck.' -ReferencePath $ReferencePath
    $linked=Add-EnglishContextEvidence -Context $ambiguous -OccurrenceIdentity $target -Event $event.Candidates[0].Clause -EvidenceIdentity 'observed-event-link'
    Assert-EnglishContract 'linked event graph constrains reading' ($linked.Candidates.Count -eq 1 -and $null -ne $linked.Candidates[0].Clause.Complement)
    $checks.Add('Prior/later explicitly linked typed graphs constrain ambiguity; removing evidence restores alternatives')
    foreach($sentence in @('The record records the record.','The door was closed by Alice.','I saw her duck.','They had read the record.')){
        $whole=Invoke-EnglishPhonemizer -Text $sentence -ReferencePath $ReferencePath
        $incremental=New-EnglishContext -ReferencePath $ReferencePath
        $words=$sentence.Split(' ')
        for($i=0;$i -lt $words.Length;$i++){Add-EnglishText $incremental ($words[$i]+$(if($i -lt $words.Length-1){' '}else{''}))}
        $stream=Get-EnglishResult $incremental
        Assert-EnglishContract 'streaming phone and graph agreement' ($stream.KokoroPhones -ceq $whole.KokoroPhones -and $stream.Candidates.Count -eq $whole.Candidates.Count -and ($stream.Tokens.SourceStart -join ',') -ceq ($whole.Tokens.SourceStart -join ','))
        foreach($token in $stream.Tokens){Assert-EnglishContract 'source extent identity' ($sentence.Substring($token.SourceStart,$token.SourceEnd-$token.SourceStart) -ceq $token.Word)}
    }
    $checks.Add('Four whole vs lexical-boundary streaming comparisons; exact source extents')
    $unknown=Invoke-EnglishPhonemizer -Text 'The quuxblarg records the record.' -ReferencePath $ReferencePath
    Assert-EnglishContract 'uncovered input cannot produce successful shortened output' (-not $unknown.Complete -and $null -eq $unknown.KokoroPhones -and $unknown.OovSpans.Count -gt 0)
    $invalidNominal=New-EnglishContext -ReferencePath $ReferencePath
    Add-EnglishText $invalidNominal 'live'
    $bindingRejected=$false
    try{$null=New-EnglishNominal -Head $invalidNominal.Occurrences[0]}catch [Management.Automation.ParameterBindingException]{$bindingRejected=$true}
    Assert-EnglishContract 'SMA validates lexical operand capabilities' $bindingRejected
    $tokens=$null;$errors=$null;[void][Management.Automation.Language.Parser]::ParseInput('1 +',[ref]$tokens,[ref]$errors)
    Assert-EnglishContract 'parser incomplete syntax differs from deferred command' (@($errors | Where-Object IncompleteInput).Count -gt 0)
    $checks.Add('Native parameter validation rejection, explicit source coverage failure, parser/binder distinction')
    $samples=[Collections.Generic.List[double]]::new();$allocated=[Collections.Generic.List[long]]::new()
    for($i=0;$i -lt 10;$i++){$null=Invoke-EnglishPhonemizer -Text 'The record records the record.' -ReferencePath $ReferencePath}
    for($i=0;$i -lt 30;$i++){
        $bytes=[GC]::GetAllocatedBytesForCurrentThread();$sw=[Diagnostics.Stopwatch]::StartNew()
        $null=Invoke-EnglishPhonemizer -Text 'The record records the record.' -ReferencePath $ReferencePath
        $samples.Add($sw.Elapsed.TotalMilliseconds);$allocated.Add([GC]::GetAllocatedBytesForCurrentThread()-$bytes)
    }
    $sorted=@($samples | Sort-Object);$allocation=@($allocated | Sort-Object)
    $receipt=[pscustomobject]@{Gate='CanonicalEnglishSmaExecution';Passed=$checks.ToArray();StreamingStates=$states.ToArray();Runtime=[Runtime.InteropServices.RuntimeInformation]::FrameworkDescription;PowerShell=$PSVersionTable.PSVersion.ToString();AssemblySha256=(Get-FileHash -LiteralPath $ReferencePath).Hash;AssemblyBytes=(Get-Item -LiteralPath $ReferencePath).Length;LexicalIdentities=$reference.Count;WarmFixture='The record records the record.';WarmRuns=$samples.Count;P50Ms=$sorted[14];P95Ms=$sorted[28];P50AllocatedBytes=$allocation[14];IndependentAccuracy='Not established by authored behavior fixtures';AutomaticDiscourseCoreference='Unsupported; graph links must be explicit';Unsupported=@('general grammar','arbitrary mid-token streaming','broad productive morphology','currency/date verbalization','automatic semantic sense resolution')}
    $receipt | Export-Clixml -LiteralPath (Join-Path ([IO.Path]::GetDirectoryName($ReferencePath)) 'verify-receipt.clixml')
    $receipt
}

if($Build){Build-EnglishReference -OutputPath $AssemblyPath -Source $LexicalSource}
elseif($Import){return}
elseif($Verify){Test-EnglishPhonemizer -ReferencePath $AssemblyPath}
else{Invoke-EnglishPhonemizer -Text $Text -ReferencePath $AssemblyPath}
