<?php
/**
 * Docker-only WordPress mail defaults.
 *
 * @package PhotoVaultInfrastructure
 */

if ( ! defined( 'ABSPATH' ) ) {
	exit;
}

function photovault_docker_mail_from( $current_email ) {
	$configured_email = getenv( 'WORDPRESS_MAIL_FROM' );
	if ( false === $configured_email || '' === trim( $configured_email ) ) {
		return $current_email;
	}

	$configured_email = sanitize_email( $configured_email );
	return is_email( $configured_email ) ? $configured_email : $current_email;
}
add_filter( 'wp_mail_from', 'photovault_docker_mail_from' );

function photovault_docker_mail_from_name( $current_name ) {
	$configured_name = getenv( 'WORDPRESS_MAIL_FROM_NAME' );
	if ( false === $configured_name || '' === trim( $configured_name ) ) {
		return $current_name;
	}

	$configured_name = sanitize_text_field( $configured_name );
	return '' !== $configured_name ? $configured_name : $current_name;
}
add_filter( 'wp_mail_from_name', 'photovault_docker_mail_from_name' );
