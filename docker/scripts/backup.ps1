[CmdletBinding()]
param(
	[ValidatePattern('^[A-Za-z0-9][A-Za-z0-9._-]*$')]
	[string] $Name
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$arguments = @('compose', '--profile', 'tools', 'run', '--rm', 'backup')
if ($Name) {
	$arguments += $Name
}

Push-Location $root
try {
	& docker @arguments
	if ($LASTEXITCODE -ne 0) {
		throw "PhotoVault backup failed with exit code $LASTEXITCODE."
	}
} finally {
	Pop-Location
}
