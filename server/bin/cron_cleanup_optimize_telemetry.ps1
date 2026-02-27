param(
  [int]$RetentionDays,
  [switch]$DryRun
)

$ErrorActionPreference = 'Stop'

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location (Join-Path $scriptDir '..')

$argsList = @('run', 'bin/cleanup_optimize_telemetry.dart')

if ($PSBoundParameters.ContainsKey('RetentionDays')) {
  $argsList += "--retention-days=$RetentionDays"
}

if ($DryRun) {
  $argsList += '--dry-run'
}

& dart @argsList
if ($LASTEXITCODE -ne 0) {
  exit $LASTEXITCODE
}
