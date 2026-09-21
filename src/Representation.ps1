class Representation {
    [string[]]$Features

    Representation([string[]]$features) {
        $this.Features = $features
    }

    [hashtable] GetRepresentedState([object]$state) {
        $rep = @{}
        foreach ($f in $this.Features) {
            $rep[$f] = $state.$f
        }
        return $rep
    }
}
