<?php
/**
 * Reports provider readiness without exposing credential values.
 */

$providers = array(
	'TWILIO_ACCOUNT_SID' => 'IDENTITY_SECURITY_TWILIO_ACCOUNT_SID',
	'TWILIO_AUTH_TOKEN'  => 'IDENTITY_SECURITY_TWILIO_AUTH_TOKEN',
	'TWILIO_FROM'        => 'IDENTITY_SECURITY_TWILIO_FROM',
	'RESEND_API_KEY'     => 'NEWSLETTER_CAMPAIGN_KIT_RESEND_API_KEY',
);

foreach ( $providers as $label => $constant_name ) {
	$is_ready = defined( $constant_name ) && '' !== trim( (string) constant( $constant_name ) );
	WP_CLI::line( $label . '_READY=' . ( $is_ready ? '1' : '0' ) );
}

$twilio_from  = defined( 'IDENTITY_SECURITY_TWILIO_FROM' )
	? trim( (string) IDENTITY_SECURITY_TWILIO_FROM )
	: '';
$sms_provider = function_exists( 'identity_security_kit_get_sms_provider' )
	? identity_security_kit_get_sms_provider()
	: 'unavailable';

$newsletter_settings  = function_exists( 'newsletter_campaign_kit_get_provider_settings' )
	? newsletter_campaign_kit_get_provider_settings()
	: array();
$newsletter_provider  = sanitize_key( $newsletter_settings['provider'] ?? 'unavailable' );
$from_email           = sanitize_email( $newsletter_settings['from_email'] ?? '' );
$from_domain          = false !== strpos( $from_email, '@' ) ? substr( strrchr( $from_email, '@' ), 1 ) : '';
$reserved_domains     = array( 'resend.dev', 'localhost' );
$reserved_suffixes    = array( '.local', '.test', '.example', '.invalid' );
$from_domain_lower    = strtolower( $from_domain );
$is_reserved_domain   = static function ( $domain ) use ( $reserved_domains, $reserved_suffixes ) {
	$domain = strtolower( trim( (string) $domain ) );
	if ( '' === $domain || in_array( $domain, $reserved_domains, true ) ) {
		return true;
	}
	foreach ( $reserved_suffixes as $reserved_suffix ) {
		if ( str_ends_with( $domain, $reserved_suffix ) ) {
			return true;
		}
	}

	return false;
};
$reserved_from_domain = $is_reserved_domain( $from_domain_lower );

$twilio_live_candidate = 'twilio' === $sms_provider
	&& defined( 'IDENTITY_SECURITY_TWILIO_ACCOUNT_SID' )
	&& '' !== trim( (string) IDENTITY_SECURITY_TWILIO_ACCOUNT_SID )
	&& defined( 'IDENTITY_SECURITY_TWILIO_AUTH_TOKEN' )
	&& '' !== trim( (string) IDENTITY_SECURITY_TWILIO_AUTH_TOKEN )
	&& '' !== $twilio_from
	&& '+15005550006' !== $twilio_from;
$resend_live_candidate = 'resend' === $newsletter_provider
	&& defined( 'NEWSLETTER_CAMPAIGN_KIT_RESEND_API_KEY' )
	&& '' !== trim( (string) NEWSLETTER_CAMPAIGN_KIT_RESEND_API_KEY )
	&& '' !== $from_domain
	&& ! $reserved_from_domain;
$smtp_mode             = sanitize_key( (string) getenv( 'PHOTOVAULT_SMTP_MODE' ) );
$smtp_host             = strtolower( trim( (string) getenv( 'PHOTOVAULT_SMTP_HOST' ) ) );
$smtp_user             = trim( (string) getenv( 'PHOTOVAULT_SMTP_USER' ) );
$smtp_password_ready   = '' !== trim( (string) getenv( 'PHOTOVAULT_SMTP_PASSWORD' ) );
$smtp_from             = sanitize_email( (string) getenv( 'PHOTOVAULT_SMTP_FROM' ) );
$smtp_from             = '' !== $smtp_from ? $smtp_from : sanitize_email( (string) getenv( 'WORDPRESS_MAIL_FROM' ) );
$smtp_from_domain      = false !== strpos( $smtp_from, '@' ) ? substr( strrchr( $smtp_from, '@' ), 1 ) : '';
$smtp_tls              = 'on' === strtolower( trim( (string) getenv( 'PHOTOVAULT_SMTP_TLS' ) ) );
$smtp_live_candidate   = 'smtp' === $smtp_mode
	&& '' !== $smtp_host
	&& '' !== $smtp_user
	&& $smtp_password_ready
	&& $smtp_tls
	&& ! $is_reserved_domain( $smtp_from_domain );
$home_https            = 'https' === wp_parse_url( home_url( '/' ), PHP_URL_SCHEME );

WP_CLI::line( 'SMS_PROVIDER=' . $sms_provider );
WP_CLI::line( 'TWILIO_FROM_MODE=' . ( '+15005550006' === $twilio_from ? 'test_magic' : ( '' === $twilio_from ? 'missing' : 'live_candidate' ) ) );
WP_CLI::line( 'TWILIO_LIVE_CANDIDATE=' . ( $twilio_live_candidate ? '1' : '0' ) );
WP_CLI::line( 'NEWSLETTER_PROVIDER=' . $newsletter_provider );
WP_CLI::line( 'RESEND_SENDER_MODE=' . ( $resend_live_candidate ? 'live_candidate' : 'test_local_or_missing' ) );
WP_CLI::line( 'RESEND_LIVE_CANDIDATE=' . ( $resend_live_candidate ? '1' : '0' ) );
WP_CLI::line( 'TRANSACTIONAL_SMTP_MODE=' . ( '' !== $smtp_mode ? $smtp_mode : 'missing' ) );
WP_CLI::line( 'TRANSACTIONAL_SMTP_LIVE_CANDIDATE=' . ( $smtp_live_candidate ? '1' : '0' ) );
WP_CLI::line( 'WORDPRESS_HOME_HTTPS=' . ( $home_https ? '1' : '0' ) );

$require_live = in_array( strtolower( (string) getenv( 'PHOTOVAULT_REQUIRE_LIVE_PROVIDERS' ) ), array( '1', 'true', 'yes', 'on' ), true );
if ( $require_live && ( ! $twilio_live_candidate || ! $resend_live_candidate || ! $smtp_live_candidate || ! $home_https ) ) {
	WP_CLI::error( 'PRODUCTION_PROVIDER_PREFLIGHT=FAIL' );
}

WP_CLI::line( 'PRODUCTION_PROVIDER_PREFLIGHT=' . ( $twilio_live_candidate && $resend_live_candidate && $smtp_live_candidate && $home_https ? 'PASS' : 'NOT_REQUESTED' ) );
