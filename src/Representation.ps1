class Representation {
    [string[]]$Features

    Representation([string[]]$features) {
        $this.Features = $features
    }

    [hashtable] GetRepresentedState([object]$state) {
        $rep = @{}
        foreach ($f in $this.Features) {
            if ($f -match '\+') {
                $sub = $f -split '\+'
                $val = ($sub | ForEach-Object { $state.$_ }) -join ':'
                $rep[$f] = $val
            } else {
                $rep[$f] = $state.$f
            }
        }
        return $rep
    }

    [string] ToString() {
        return "{" + ($this.Features -join ', ') + "}"
    }
}
