[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [ValidateSet('Inspect','Preview','Start','Stop','Rollback','SelfTest')]
    [string]$Action = 'Inspect',
    [ValidateSet('GTA5','ZeroHour','WatchDogs2','HollowKnight','Silksong','Cuphead','Custom')]
    [string]$Game = 'GTA5',
    [string]$GamePath,
    [string[]]$CloseApps = @(),
    [switch]$UseHighPerformance,
    [ValidateSet('Normal','AboveNormal')]
    [string]$Priority = 'Normal',
    [int]$WaitForGameSeconds = 120,
    [string]$OutputRoot
)

if (-not $OutputRoot) { $OutputRoot = Join-Path $PSScriptRoot 'data' }

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$Presets = [ordered]@{
    GTA5          = @{ DisplayName='Grand Theft Auto V'; Processes=@('GTA5','GTA5_Enhanced','PlayGTAV'); Launchers=@('Rockstar Games Launcher','Steam','Epic Games Launcher') }
    ZeroHour      = @{ DisplayName='Zero Hour'; Processes=@('ZeroHour-Win64-Shipping','ZeroHour'); Launchers=@('Steam') }
    WatchDogs2    = @{ DisplayName='Watch Dogs 2'; Processes=@('WatchDogs2'); Launchers=@('Ubisoft Connect','Steam','Epic Games Launcher') }
    HollowKnight  = @{ DisplayName='Hollow Knight'; Processes=@('hollow_knight'); Launchers=@('Steam') }
    Silksong      = @{ DisplayName='Hollow Knight: Silksong'; Processes=@('Hollow Knight Silksong','Silksong'); Launchers=@('Steam') }
    Cuphead       = @{ DisplayName='Cuphead'; Processes=@('Cuphead'); Launchers=@('Steam') }
    Custom        = @{ DisplayName='Custom game'; Processes=@(); Launchers=@() }
}

# Only these user applications can be requested for graceful closing. Additions should be
# made deliberately. This is an allowlist, not a memory-usage heuristic.
$ClosableApps = [ordered]@{
    Spotify    = @('Spotify')
    BlueStacks = @('HD-Player','BlueStacks','BstkSVC')
    Chrome     = @('chrome')
    Edge       = @('msedge')
    Firefox    = @('firefox')
    Discord    = @('Discord')
    Teams      = @('ms-teams','Teams')
}

function Write-Log {
    param([string]$Message, [ValidateSet('INFO','WARN','ERROR')][string]$Level='INFO')
    $line = '{0} [{1}] {2}' -f (Get-Date -Format o), $Level, $Message
    Write-Host $line
    if ($script:LogFile) { Add-Content -LiteralPath $script:LogFile -Value $line -Encoding UTF8 }
}

function Initialize-Storage {
    foreach ($dir in @($OutputRoot, (Join-Path $OutputRoot 'logs'), (Join-Path $OutputRoot 'snapshots'), (Join-Path $OutputRoot 'sessions'))) {
        if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    }
    $script:LogFile = Join-Path $OutputRoot ('logs\optimizer-{0}.log' -f (Get-Date -Format 'yyyyMMdd'))
}

function Get-ActivePowerScheme {
    try {
        $text = (& powercfg /getactivescheme 2>&1 | Out-String)
        if ($LASTEXITCODE -eq 0 -and $text -match '([0-9a-fA-F-]{36})') { return $Matches[1].ToLowerInvariant() }
    } catch { Write-Log "Could not read the active power plan: $($_.Exception.Message)" WARN }
    return $null
}

function Get-HighPerformanceScheme {
    try {
        $text = (& powercfg /list 2>&1 | Out-String)
        $line = ($text -split "`r?`n" | Where-Object { $_ -match 'High performance' } | Select-Object -First 1)
        if ($line -and $line -match '([0-9a-fA-F-]{36})') { return $Matches[1].ToLowerInvariant() }
    } catch { Write-Log "Could not enumerate power plans: $($_.Exception.Message)" WARN }
    return $null
}

function Get-ProcessSnapshot {
    Get-Process -ErrorAction SilentlyContinue | ForEach-Object {
        [pscustomobject]@{
            Name = $_.ProcessName
            Id = $_.Id
            RAM_MB = [math]::Round($_.WorkingSet64 / 1MB, 1)
            CPU_s = if ($null -eq $_.CPU) { $null } else { [math]::Round($_.CPU, 1) }
            HasWindow = -not [string]::IsNullOrWhiteSpace($_.MainWindowTitle)
            WindowTitle = $_.MainWindowTitle
        }
    } | Sort-Object RAM_MB -Descending
}

function Save-Snapshot {
    param([string]$Label)
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $base = Join-Path $OutputRoot "snapshots\$stamp-$Label"
    $processes = @(Get-ProcessSnapshot)
    $processes | Export-Csv -LiteralPath "$base-processes.csv" -NoTypeInformation -Encoding UTF8
    $system = [ordered]@{
        Timestamp = (Get-Date).ToString('o')
        ComputerName = $env:COMPUTERNAME
        Windows = [System.Environment]::OSVersion.VersionString
        PowerShell = $PSVersionTable.PSVersion.ToString()
        ActivePowerScheme = Get-ActivePowerScheme
        GameModeRegistry = $(try { (Get-ItemProperty -LiteralPath 'HKCU:\Software\Microsoft\GameBar' -ErrorAction Stop).AutoGameModeEnabled } catch { $null })
        ProcessCount = $processes.Count
        TopProcesses = @($processes | Select-Object -First 20)
    }
    $system | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath "$base-system.json" -Encoding UTF8
    return [pscustomobject]@{ Base=$base; Processes=$processes; System=$system }
}

function Get-GameProcesses {
    param([hashtable]$Preset)
    $names = @($Preset.Processes)
    if ($Game -eq 'Custom' -and $GamePath) { $names = @([IO.Path]::GetFileNameWithoutExtension($GamePath)) }
    if ($names.Count -eq 0) { return @() }
    return @(Get-Process -ErrorAction SilentlyContinue | Where-Object { $names -contains $_.ProcessName })
}

function Resolve-CloseTargets {
    param([string[]]$Requested)
    $unknown = @($Requested | Where-Object { -not $ClosableApps.Contains($_) })
    if ($unknown.Count) { throw "Unknown CloseApps value(s): $($unknown -join ', '). Allowed: $($ClosableApps.Keys -join ', ')" }
    $targets = @()
    foreach ($label in $Requested) {
        foreach ($processName in $ClosableApps[$label]) {
            $targets += @(Get-Process -Name $processName -ErrorAction SilentlyContinue | ForEach-Object {
                [pscustomobject]@{ Label=$label; Name=$_.ProcessName; Id=$_.Id; RAM_MB=[math]::Round($_.WorkingSet64/1MB,1); HasWindow=($_.MainWindowHandle -ne 0) }
            })
        }
    }
    return @($targets | Sort-Object Id -Unique)
}

function Show-Preview {
    param([hashtable]$Preset)
    $targets = @(Resolve-CloseTargets $CloseApps)
    Write-Host "`nGame: $($Preset.DisplayName)"
    if ($GamePath) { Write-Host "Launch path: $GamePath" } else { Write-Host 'Launch path: none (the toolkit will wait for an already-started game)' }
    Write-Host "Priority: $Priority (High and RealTime are intentionally unsupported)"
    Write-Host "Temporary High performance plan: $UseHighPerformance"
    if ($targets.Count) {
        Write-Host "`nApplications requested for graceful close:"
        $targets | Format-Table Label,Name,Id,RAM_MB,HasWindow -AutoSize
        Write-Host 'Unsaved work may block or be lost if an app closes normally. No force-kill is used.'
    } else { Write-Host "`nNo applications will be closed." }
    $heavy = @(Get-ProcessSnapshot | Where-Object { $_.RAM_MB -ge 150 } | Select-Object -First 15)
    Write-Host "`nInformational only: largest processes (nothing is selected from this list automatically):"
    $heavy | Format-Table Name,Id,RAM_MB,HasWindow -AutoSize
}

function Stop-AllowedApps {
    param([object[]]$Targets)
    $results = @()
    foreach ($target in $Targets) {
        $status = 'Not attempted'
        try {
            $process = Get-Process -Id $target.Id -ErrorAction Stop
            if ($process.MainWindowHandle -eq 0) {
                $status = 'Skipped: no closable main window'
            } elseif ($PSCmdlet.ShouldProcess("$($target.Name) PID $($target.Id)", 'Request normal window close')) {
                $accepted = $process.CloseMainWindow()
                $status = if ($accepted) { 'Close requested' } else { 'Close request declined by application' }
            }
        } catch { $status = "Skipped: $($_.Exception.Message)" }
        Write-Log "$($target.Label)/$($target.Name) PID $($target.Id): $status"
        $results += [pscustomobject]@{ Label=$target.Label; Name=$target.Name; Id=$target.Id; Status=$status }
    }
    return $results
}

function Get-LatestSessionFile {
    $files = @(Get-ChildItem -LiteralPath (Join-Path $OutputRoot 'sessions') -Filter '*.json' -File -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending)
    if (-not $files.Count) { return $null }
    foreach ($file in $files) {
        try {
            $candidate = Get-Content -Raw -LiteralPath $file.FullName | ConvertFrom-Json
            if (-not $candidate.Restored) { return $file.FullName }
        } catch { Write-Log "Ignoring unreadable session file $($file.FullName): $($_.Exception.Message)" WARN }
    }
    return $files[0].FullName
}

function Restore-Session {
    param([string]$SessionFile)
    if (-not $SessionFile -or -not (Test-Path -LiteralPath $SessionFile)) { throw 'No saved session was found to restore.' }
    $state = Get-Content -Raw -LiteralPath $SessionFile | ConvertFrom-Json
    if ($state.Restored) { Write-Log "Session is already restored: $SessionFile"; return }
    if ($state.AppliedPowerScheme -and $state.OriginalPowerScheme -and $state.AppliedPowerScheme -ne $state.OriginalPowerScheme) {
        if ($PSCmdlet.ShouldProcess($state.OriginalPowerScheme, 'Restore original power plan')) {
            & powercfg /setactive $state.OriginalPowerScheme | Out-Null
            if ($LASTEXITCODE -ne 0) { throw 'powercfg could not restore the original power plan.' }
            Write-Log "Restored power plan $($state.OriginalPowerScheme)."
        }
    }
    $state.Restored = $true
    $state.RestoredAt = (Get-Date).ToString('o')
    $state | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $SessionFile -Encoding UTF8
    Save-Snapshot 'after-restore' | Out-Null
    Write-Log 'Rollback completed. Applications closed by consent are not automatically relaunched.'
}

function Start-GameSession {
    param([hashtable]$Preset)
    Show-Preview $Preset
    $originalPower = Get-ActivePowerScheme
    $sessionId = Get-Date -Format 'yyyyMMdd-HHmmss'
    $sessionFile = Join-Path $OutputRoot "sessions\$sessionId-$Game.json"
    $state = [ordered]@{
        SessionId=$sessionId; Game=$Game; StartedAt=(Get-Date).ToString('o'); OriginalPowerScheme=$originalPower
        AppliedPowerScheme=$null; RequestedPriority=$Priority; GamePath=$GamePath; CloseResults=@(); Restored=$false; RestoredAt=$null
    }
    $state | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $sessionFile -Encoding UTF8
    try {
        Save-Snapshot 'before-session' | Out-Null
        if ($UseHighPerformance) {
            $high = Get-HighPerformanceScheme
            if (-not $high) { Write-Log 'High performance plan was not found. Keeping the current plan.' WARN }
            elseif ($high -eq $originalPower) { Write-Log 'High performance is already active.' }
            elseif ($PSCmdlet.ShouldProcess($high, 'Temporarily activate High performance power plan')) {
                & powercfg /setactive $high | Out-Null
                if ($LASTEXITCODE -ne 0) { throw 'powercfg could not activate High performance.' }
                $state.AppliedPowerScheme = $high
                Write-Log "Temporarily activated High performance plan $high."
            }
        }
        $targets = @(Resolve-CloseTargets $CloseApps)
        $state.CloseResults = @(Stop-AllowedApps $targets)
        $state | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $sessionFile -Encoding UTF8

        $gameProcesses = @(Get-GameProcesses $Preset)
        if (-not $gameProcesses.Count -and $GamePath) {
            if (-not (Test-Path -LiteralPath $GamePath -PathType Leaf)) { throw "GamePath does not exist: $GamePath" }
            if ([IO.Path]::GetExtension($GamePath) -notin @('.exe','.lnk','.url')) { throw 'GamePath must be an .exe, .lnk, or .url file.' }
            if ($Game -eq 'Custom' -and [IO.Path]::GetExtension($GamePath) -ne '.exe') { throw 'Custom sessions require the game executable (.exe), so its process can be detected safely.' }
            if ($PSCmdlet.ShouldProcess($GamePath, 'Launch game')) { Start-Process -FilePath $GamePath | Out-Null }
        }
        $deadline = (Get-Date).AddSeconds($WaitForGameSeconds)
        do {
            $gameProcesses = @(Get-GameProcesses $Preset)
            if ($gameProcesses.Count) { break }
            Start-Sleep -Seconds 2
        } while ((Get-Date) -lt $deadline)
        if (-not $gameProcesses.Count) { throw "Game process was not detected within $WaitForGameSeconds seconds. Start it manually or provide -GamePath." }
        foreach ($process in $gameProcesses) {
            if ($Priority -eq 'AboveNormal' -and $PSCmdlet.ShouldProcess("$($process.ProcessName) PID $($process.Id)", 'Set temporary AboveNormal priority')) {
                try { $process.PriorityClass = 'AboveNormal'; Write-Log "Set $($process.ProcessName) PID $($process.Id) to AboveNormal." }
                catch { Write-Log "Could not set AboveNormal priority: $($_.Exception.Message)" WARN }
            }
        }
        Write-Log 'Game detected. Waiting for all matching game processes to exit. Press Ctrl+C to interrupt; use Rollback afterward.'
        while (@(Get-GameProcesses $Preset).Count) { Start-Sleep -Seconds 5 }
    } finally {
        try { Restore-Session $sessionFile } catch {
            Write-Log "Automatic rollback failed: $($_.Exception.Message). Run -Action Rollback." ERROR
            throw
        }
    }
}

function Invoke-SelfTest {
    $failures = [Collections.Generic.List[string]]::new()
    function Assert([bool]$Condition, [string]$Message) { if (-not $Condition) { $failures.Add($Message) } }
    Assert ($Presets.Count -eq 7) 'Expected seven presets.'
    Assert (-not $ClosableApps.Contains('explorer')) 'Explorer must not be closable.'
    Assert (-not $ClosableApps.Contains('MsMpEng')) 'Microsoft Defender must not be closable.'
    foreach ($name in $ClosableApps.Keys) { Assert ($ClosableApps[$name].Count -gt 0) "Empty close allowlist entry: $name" }
    try { Resolve-CloseTargets @('__invalid__') | Out-Null; $failures.Add('Unknown CloseApps did not fail closed.') } catch { }
    foreach ($preset in $Presets.GetEnumerator()) {
        Assert (-not [string]::IsNullOrWhiteSpace($preset.Value.DisplayName)) "Preset missing display name: $($preset.Key)"
    }
    Assert ($Priority -in @('Normal','AboveNormal')) 'Unsafe priority value accepted.'
    if ($failures.Count) { throw "Self-test failed:`n - $($failures -join "`n - ")" }
    Write-Host 'Self-test passed: presets, close allowlist, fail-closed validation, and priority guardrails.'
}

try {
    Initialize-Storage
    $preset = $Presets[$Game]
    switch ($Action) {
        Inspect {
            $snapshot = Save-Snapshot 'inspect'
            Write-Host "Snapshot saved: $($snapshot.Base)-processes.csv"
            $snapshot.Processes | Select-Object -First 20 | Format-Table Name,Id,RAM_MB,CPU_s,HasWindow -AutoSize
        }
        Preview { Show-Preview $preset }
        Start { Start-GameSession $preset }
        Stop { Restore-Session (Get-LatestSessionFile) }
        Rollback { Restore-Session (Get-LatestSessionFile) }
        SelfTest { Invoke-SelfTest }
    }
} catch {
    Write-Log $_.Exception.Message ERROR
    exit 1
}

