class LinearState {
    [int]$X
    [int]$Direction
}

function Invoke-LinearStep {
    param([LinearState]$State)
    $newState = [LinearState]::new()
    $newState.Direction = $State.Direction
    $newState.X = $State.X + $State.Direction
    return $newState
}
