[CmdletBinding()]
param([switch]$Recover, [switch]$Preview, [switch]$NoElevation,
      [int]$WaitSeconds=600, [string]$StateRoot)
if (-not $StateRoot) { $StateRoot=Join-Path $PSScriptRoot 'data\automatic' }
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$games=@('GTA5','GTA5_Enhanced','ZeroHour','ZeroHour-Win64-Shipping','WatchDogs2','hollow_knight','Hollow Knight Silksong','Silksong','Cuphead')
$background=@('chrome','msedge','firefox','Spotify','Discord','Teams','ms-teams')
$stateFile=Join-Path $StateRoot 'session.json'
$logFile=Join-Path $StateRoot 'session.log'
function Save-State($state) {
    $temp=Join-Path $StateRoot 'session.tmp'
    $state | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $temp -Encoding UTF8
    Move-Item -LiteralPath $temp -Destination $stateFile -Force
}
function Log([string]$message) {
    Write-Host $message
    Add-Content -LiteralPath $logFile -Value ('{0} {1}' -f (Get-Date -Format o),$message)
}
function Restore-State($state) {
    $failed=$false
    foreach($entry in $state.Entries) {
        try {
            $p=Get-Process -Id $entry.Id -ErrorAction SilentlyContinue
            if($p -and $p.StartTime.ToUniversalTime().ToString('o') -eq $entry.StartTime) {
                $p.PriorityClass=$entry.Priority
                Log "Restored $($p.ProcessName) PID $($p.Id)."
            }
        } catch { $failed=$true; Log "Recovery needed: $($_.Exception.Message)" }
    }
    $state.Restored=-not $failed
    Save-State $state
    if($failed) { throw 'Some priorities could not be restored. Run Analyze Gaming.bat again to recover.' }
}
try {
    if(-not $Preview -and -not $NoElevation) {
        $principal=New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
        if(-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
            $arguments='-NoLogo -NoProfile -ExecutionPolicy Bypass -File "{0}"' -f $PSCommandPath
            if($Recover) { $arguments+=' -Recover' }
            $child=Start-Process powershell.exe -Verb RunAs -ArgumentList $arguments -Wait -PassThru
            exit $child.ExitCode
        }
    }
    if($Preview) {
        Write-Host 'Automatic detection: GTA V, Zero Hour, Watch Dogs 2, Hollow Knight, Silksong, Cuphead.'
        Write-Host 'Temporary BelowNormal CPU priority: browsers, Spotify, Discord, Teams.'
        Write-Host 'Original priorities restored after game exit. No apps closed. RAM and GPU allocations remain owned by each app.'
        exit 0
    }
    New-Item -ItemType Directory -Path $StateRoot -Force | Out-Null
    # An exclusive lock prevents two sessions from overwriting each other's recovery state.
    $lock=[IO.File]::Open((Join-Path $StateRoot 'session.lock'),[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
    try {
        if(Test-Path -LiteralPath $stateFile) {
            $old=Get-Content -Raw -LiteralPath $stateFile | ConvertFrom-Json
            if(-not $old.Restored) { Log 'Recovering previous session first...'; Restore-State $old }
        }
        if($Recover) { Log 'Recovery complete.'; exit 0 }
        Log 'Launch your game normally. Waiting up to 10 minutes. Keep this window open.'
        $deadline=(Get-Date).AddSeconds($WaitSeconds)
        $session=(Get-Process -Id $PID).SessionId
        do {
            $active=@(Get-Process | Where-Object { $games -contains $_.ProcessName -and $_.SessionId -eq $session })
            if($active.Count) { break }
            Start-Sleep -Milliseconds 500
        } while((Get-Date) -lt $deadline)
        if(-not $active.Count) { throw 'No supported game detected. Run the original launcher Inspect option and send the process CSV.' }
        $state=[pscustomobject]@{ Started=(Get-Date -Format o); Games=@($active.ProcessName); Entries=@(); Restored=$false }
        Save-State $state
        Get-Process | Select-Object ProcessName,Id,WorkingSet64,CPU | Export-Csv -LiteralPath (Join-Path $StateRoot 'before.csv') -NoTypeInformation
        try {
            Log "Game detected: $($active.ProcessName -join ', '). Applying temporary background priorities."
            foreach($p in @(Get-Process | Where-Object { $background -contains $_.ProcessName -and $_.SessionId -eq $session })) {
                try {
                    if($p.PriorityClass -in @('Idle','BelowNormal')) { continue }
                    $state.Entries+= [pscustomobject]@{ Id=$p.Id; Name=$p.ProcessName; StartTime=$p.StartTime.ToUniversalTime().ToString('o'); Priority=$p.PriorityClass.ToString() }
                    Save-State $state
                    $p.PriorityClass='BelowNormal'
                    Log "Reduced CPU priority: $($p.ProcessName) PID $($p.Id)."
                } catch { Log "Skipped $($p.ProcessName): $($_.Exception.Message)" }
            }
            do {
                Start-Sleep -Seconds 2
                $active=@(Get-Process | Where-Object { $games -contains $_.ProcessName -and $_.SessionId -eq $session })
            } while($active.Count)
        } finally { Restore-State $state }
        Log 'Game closed. Background priorities restored.'
    } finally { if($lock) { $lock.Dispose() } }
} catch {
    Write-Host "Gaming session error: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}
