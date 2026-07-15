[CmdletBinding()]
param(
	[Parameter(Mandatory)]
	[ValidateSet('verify', 'test', 'apply')]
	[string] $Mode,

	[Parameter(Mandatory)]
	[ValidatePattern('^[A-Za-z0-9][A-Za-z0-9._-]*$')]
	[string] $Backup,

	[switch] $Confirm
)

$ErrorActionPreference = 'Stop'
if ('apply' -eq $Mode -and -not $Confirm) {
	throw 'Live restore requires the explicit -Confirm switch.'
}

$root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$arguments = @('compose', '--profile', 'tools', 'run', '--rm')
$pausedServices = @()

Push-Location $root
try {
	if ('apply' -eq $Mode) {
		$config = (& docker compose --profile tools config --format json) | ConvertFrom-Json
		if ($LASTEXITCODE -ne 0) {
			throw 'Could not resolve the Docker Compose configuration.'
		}
		$databaseName = $config.services.restore.environment.PHOTOVAULT_DB_NAME
		if (-not $databaseName) {
			throw 'Could not resolve the configured target database name.'
		}
		$runningServices = @(& docker compose ps --services --status running)
		if ($LASTEXITCODE -ne 0) {
			throw 'Could not inspect the running Docker Compose services.'
		}
		$pausedServices = @('nginx', 'cron', 'wordpress') | Where-Object { $runningServices -contains $_ }
		if ($pausedServices.Count -gt 0) {
			& docker compose stop @pausedServices
			if ($LASTEXITCODE -ne 0) {
				throw 'Could not place PhotoVault services in maintenance mode.'
			}
		}
		$arguments += @('-e', "CONFIRM_RESTORE=$databaseName", '-e', 'MAINTENANCE_CONFIRMED=YES')
	}
	$arguments += @('restore', $Mode, $Backup)
	& docker @arguments
	if ($LASTEXITCODE -ne 0) {
		throw "PhotoVault restore $Mode failed with exit code $LASTEXITCODE."
	}
} finally {
	$restartFailed = $false
	if ($pausedServices.Count -gt 0) {
		& docker compose start @pausedServices
		if ($LASTEXITCODE -ne 0) {
			$restartFailed = $true
		}
	}
	Pop-Location
	if ($restartFailed) {
		throw 'Restore finished, but one or more paused services could not be restarted.'
	}
}
