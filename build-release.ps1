[CmdletBinding()]
param([string]$Output = (Join-Path $PSScriptRoot 'release'))

$ErrorActionPreference = 'Stop'
$project = Join-Path $PSScriptRoot 'SafeGamingOptimizer\SafeGamingOptimizer.csproj'
dotnet publish $project -c Release -r win-x64 --self-contained true -p:PublishSingleFile=true -o $Output
if ($LASTEXITCODE -ne 0) { throw 'Release build failed.' }
Write-Host "Release created: $(Join-Path $Output 'SafeGamingOptimizer.exe')"
