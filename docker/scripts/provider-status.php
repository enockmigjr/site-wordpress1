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
	echo $label . '_READY=' . ( $is_ready ? '1' : '0' ) . PHP_EOL;
}
