class WorldState {
    [int]$X
    [int]$Direction
}

function Invoke-WorldStep {
    param([WorldState]$State)
    $newState = [WorldState]::new()
    $newState.Direction = $State.Direction
    $newState.X = $State.X + $State.Direction
    return $newState
}
