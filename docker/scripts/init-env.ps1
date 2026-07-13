$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$target = Join-Path $root '.env'

if (Test-Path -LiteralPath $target) {
	throw '.env already exists. Remove it explicitly before generating new secrets.'
}

function New-HexSecret([int] $byteCount) {
	if ($byteCount -lt 16) {
		throw 'Secrets must contain at least 16 random bytes.'
	}

	$bytes = [byte[]]::new($byteCount)
	$rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()

	try {
		$rng.GetBytes($bytes)
	} finally {
		$rng.Dispose()
	}

	return -join ($bytes | ForEach-Object { $_.ToString('x2') })
}

$dbPassword = New-HexSecret 24
$rootPassword = New-HexSecret 24
$authKey = New-HexSecret 64
$secureAuthKey = New-HexSecret 64
$loggedInKey = New-HexSecret 64
$nonceKey = New-HexSecret 64
$authSalt = New-HexSecret 64
$secureAuthSalt = New-HexSecret 64
$loggedInSalt = New-HexSecret 64
$nonceSalt = New-HexSecret 64

$lines = [string[]] @(
	'PHOTOVAULT_HTTP_PORT=8080',
	'MAILPIT_UI_PORT=8025',
	'PHOTOVAULT_ENV=development',
	'WORDPRESS_DEBUG=1',
	'WORDPRESS_FORCE_SSL_ADMIN=0',
	'',
	'WORDPRESS_DB_NAME=photovault',
	'WORDPRESS_DB_USER=photovault',
	"WORDPRESS_DB_PASSWORD=$dbPassword",
	"MARIADB_ROOT_PASSWORD=$rootPassword",
	'WORDPRESS_TABLE_PREFIX=wp_',
	'',
	"WORDPRESS_AUTH_KEY=$authKey",
	"WORDPRESS_SECURE_AUTH_KEY=$secureAuthKey",
	"WORDPRESS_LOGGED_IN_KEY=$loggedInKey",
	"WORDPRESS_NONCE_KEY=$nonceKey",
	"WORDPRESS_AUTH_SALT=$authSalt",
	"WORDPRESS_SECURE_AUTH_SALT=$secureAuthSalt",
	"WORDPRESS_LOGGED_IN_SALT=$loggedInSalt",
	"WORDPRESS_NONCE_SALT=$nonceSalt"
)

[System.IO.File]::WriteAllLines($target, $lines, [System.Text.UTF8Encoding]::new($false))
Write-Host "Generated $target with cryptographically random local secrets."
