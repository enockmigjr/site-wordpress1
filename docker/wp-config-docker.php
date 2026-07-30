<?php
/**
 * Docker-only WordPress configuration.
 */

$env = static function ( $key, $fallback = '' ) {
	$value = getenv( $key );

	return false === $value ? $fallback : $value;
};

$required_env = static function ( $key ) use ( $env ) {
	$value = (string) $env( $key );

	if ( '' === $value || false !== strpos( $value, 'replace-with-' ) || false !== strpos( $value, 'change-me' ) ) {
		throw new RuntimeException( sprintf( 'Required Docker environment variable is missing or unsafe: %s', $key ) ); // phpcs:ignore WordPress.Security.EscapeOutput.ExceptionNotEscaped -- The key comes from fixed bootstrap calls.
	}

	return $value;
};

$environment = strtolower( (string) $env( 'PHOTOVAULT_ENV', 'development' ) );
if ( ! in_array( $environment, array( 'development', 'test', 'staging', 'production' ), true ) ) {
	throw new RuntimeException( 'PHOTOVAULT_ENV must be development, test, staging or production.' );
}

define( 'DB_NAME', $env( 'WORDPRESS_DB_NAME', 'photovault' ) );
define( 'DB_USER', $env( 'WORDPRESS_DB_USER', 'photovault' ) );
define( 'DB_PASSWORD', $required_env( 'WORDPRESS_DB_PASSWORD' ) );
define( 'DB_HOST', $env( 'WORDPRESS_DB_HOST', 'db:3306' ) );
define( 'DB_CHARSET', 'utf8mb4' );
define( 'DB_COLLATE', '' );

define( 'AUTH_KEY', $required_env( 'WORDPRESS_AUTH_KEY' ) );
define( 'SECURE_AUTH_KEY', $required_env( 'WORDPRESS_SECURE_AUTH_KEY' ) );
define( 'LOGGED_IN_KEY', $required_env( 'WORDPRESS_LOGGED_IN_KEY' ) );
define( 'NONCE_KEY', $required_env( 'WORDPRESS_NONCE_KEY' ) );
define( 'AUTH_SALT', $required_env( 'WORDPRESS_AUTH_SALT' ) );
define( 'SECURE_AUTH_SALT', $required_env( 'WORDPRESS_SECURE_AUTH_SALT' ) );
define( 'LOGGED_IN_SALT', $required_env( 'WORDPRESS_LOGGED_IN_SALT' ) );
define( 'NONCE_SALT', $required_env( 'WORDPRESS_NONCE_SALT' ) );

$table_prefix = (string) $env( 'WORDPRESS_TABLE_PREFIX', 'wp_' ); // phpcs:ignore WordPress.WP.GlobalVariablesOverride.Prohibited -- Required by WordPress bootstrap.
if ( ! preg_match( '/^[A-Za-z0-9_]+$/', $table_prefix ) ) {
	throw new RuntimeException( 'WORDPRESS_TABLE_PREFIX contains invalid characters.' );
}

$debug               = in_array( strtolower( (string) $env( 'WORDPRESS_DEBUG', '0' ) ), array( '1', 'true', 'yes', 'on' ), true );
$force_ssl_admin     = in_array( strtolower( (string) $env( 'WORDPRESS_FORCE_SSL_ADMIN', '0' ) ), array( '1', 'true', 'yes', 'on' ), true );
$trust_proxy_headers = in_array( strtolower( (string) $env( 'PHOTOVAULT_TRUST_PROXY_HEADERS', '0' ) ), array( '1', 'true', 'yes', 'on' ), true );
$trusted_proxy_hosts = array_filter( array_map( 'trim', explode( ',', strtolower( (string) $env( 'PHOTOVAULT_TRUSTED_PROXY_HOSTS' ) ) ) ) );
$home_url            = trim( (string) $env( 'WORDPRESS_HOME_URL' ) );
$site_url            = trim( (string) $env( 'WORDPRESS_SITE_URL', $home_url ) );

$validate_wordpress_url = static function ( $url ) {
	if ( '' === $url ) {
		return;
	}
	if ( false === filter_var( $url, FILTER_VALIDATE_URL ) || ! preg_match( '#^https?://#i', $url ) ) {
		throw new RuntimeException( 'WORDPRESS_HOME_URL and WORDPRESS_SITE_URL must be absolute HTTP(S) URLs.' );
	}
};
$validate_wordpress_url( $home_url );
$validate_wordpress_url( $site_url );

$public_proxy_url = '';
if ( $trust_proxy_headers && isset( $_SERVER['HTTP_X_FORWARDED_HOST'], $_SERVER['HTTP_X_FORWARDED_PROTO'] ) ) {
	$forwarded_host  = strtolower( trim( explode( ',', (string) $_SERVER['HTTP_X_FORWARDED_HOST'] )[0] ) );
	$forwarded_proto = strtolower( trim( explode( ',', (string) $_SERVER['HTTP_X_FORWARDED_PROTO'] )[0] ) );
	$host_matches    = array();
	$host_is_valid   = 1 === preg_match( '/^(?:[a-z0-9](?:[a-z0-9.-]{0,251}[a-z0-9])?|\\[[0-9a-f:.]+\\])(?::([0-9]{1,5}))?$/', $forwarded_host, $host_matches );
	$parsed_host     = $host_is_valid ? parse_url( 'http://' . $forwarded_host, PHP_URL_HOST ) : null;
	$parsed_port     = isset( $host_matches[1] ) && '' !== $host_matches[1] ? (int) $host_matches[1] : null;
	$host_is_valid   = $host_is_valid
		&& is_string( $parsed_host )
		&& '' !== $parsed_host
		&& ( false !== filter_var( $parsed_host, FILTER_VALIDATE_DOMAIN, FILTER_FLAG_HOSTNAME ) || false !== filter_var( trim( $parsed_host, '[]' ), FILTER_VALIDATE_IP ) )
		&& ( null === $parsed_port || ( $parsed_port >= 1 && $parsed_port <= 65535 ) );
	$host_is_trusted = false;

	if ( $host_is_valid ) {
		foreach ( $trusted_proxy_hosts as $trusted_host ) {
			if ( $parsed_host === $trusted_host ) {
				$host_is_trusted = true;
				break;
			}

			if ( 0 === strpos( $trusted_host, '*.' ) ) {
				$suffix = substr( $trusted_host, 1 );
				if ( strlen( $parsed_host ) > strlen( $suffix ) && substr( $parsed_host, -strlen( $suffix ) ) === $suffix ) {
					$host_is_trusted = true;
					break;
				}
			}
		}
	}

	if ( $host_is_trusted && in_array( $forwarded_proto, array( 'http', 'https' ), true ) ) {
		$_SERVER['HTTP_HOST']   = $forwarded_host;
		$_SERVER['SERVER_PORT'] = 'https' === $forwarded_proto ? '443' : '80';
		$_SERVER['HTTPS']       = 'https' === $forwarded_proto ? 'on' : 'off';
		$public_proxy_url       = $forwarded_proto . '://' . $forwarded_host;
	}
}

define( 'WP_DEBUG', $debug );
define( 'WP_DEBUG_LOG', $debug );
define( 'WP_DEBUG_DISPLAY', false );
define( 'DISABLE_WP_CRON', true );
define( 'DISALLOW_FILE_EDIT', true );
define( 'WP_AUTO_UPDATE_CORE', 'minor' );
define( 'FS_METHOD', 'direct' );
define( 'WP_ENVIRONMENT_TYPE', $environment );
define( 'WPMU_PLUGIN_DIR', '/opt/photovault/mu-plugins' );

if ( $force_ssl_admin ) {
	define( 'FORCE_SSL_ADMIN', true );
}

if ( '' !== $public_proxy_url ) {
	define( 'WP_HOME', $public_proxy_url );
	define( 'WP_SITEURL', $public_proxy_url );
} elseif ( '' !== $home_url ) {
	define( 'WP_HOME', rtrim( $home_url, '/' ) );
	if ( '' !== $site_url ) {
		define( 'WP_SITEURL', rtrim( $site_url, '/' ) );
	}
} elseif ( '' !== $site_url ) {
	define( 'WP_SITEURL', rtrim( $site_url, '/' ) );
}

if ( $trust_proxy_headers && 'https' === (string) parse_url( $public_proxy_url, PHP_URL_SCHEME ) ) {
	$_SERVER['HTTPS'] = 'on';
}

if ( ! defined( 'ABSPATH' ) ) {
	define( 'ABSPATH', __DIR__ . '/' );
}

$local_secrets_file = __DIR__ . '/docker/wp-config-secrets.php';
if ( is_readable( $local_secrets_file ) ) {
	require $local_secrets_file;
}

require_once ABSPATH . 'wp-settings.php';
