#!/bin/sh
set -eu

config_file=/etc/msmtprc
secret_file=/run/photovault-smtp-password
mode=${PHOTOVAULT_SMTP_MODE:-mailpit}
host=${PHOTOVAULT_SMTP_HOST:-mailpit}
port=${PHOTOVAULT_SMTP_PORT:-1025}
from=${PHOTOVAULT_SMTP_FROM:-${WORDPRESS_MAIL_FROM:-wordpress@photovault.local}}

validate_host() {
	case "$1" in
		''|*[!A-Za-z0-9.-]*)
			echo "Invalid PHOTOVAULT_SMTP_HOST." >&2
			exit 1
			;;
	esac
}

validate_port() {
	case "$1" in
		''|*[!0-9]*)
			echo "Invalid PHOTOVAULT_SMTP_PORT." >&2
			exit 1
			;;
	esac
	if [ "$1" -lt 1 ] || [ "$1" -gt 65535 ]; then
		echo "PHOTOVAULT_SMTP_PORT must be between 1 and 65535." >&2
		exit 1
	fi
}

validate_address() {
	case "$1" in
		*@*.*) ;;
		*)
			echo "Invalid SMTP sender address." >&2
			exit 1
			;;
	esac
	case "$1" in
		*[!A-Za-z0-9@._+-]*)
			echo "SMTP sender address contains unsupported characters." >&2
			exit 1
			;;
	esac
}

validate_switch() {
	case "$2" in
		on|off) ;;
		*)
			echo "$1 must be on or off." >&2
			exit 1
			;;
	esac
}

validate_host "$host"
validate_port "$port"
validate_address "$from"
rm -f "$secret_file"

case "$mode" in
	mailpit)
		cat > "$config_file" <<EOF
defaults
auth off
tls off
logfile -

account mailpit
host $host
port $port
from $from

account default : mailpit
EOF
		;;
	smtp)
		user=${PHOTOVAULT_SMTP_USER:-}
		password=${PHOTOVAULT_SMTP_PASSWORD:-}
		tls=${PHOTOVAULT_SMTP_TLS:-on}
		starttls=${PHOTOVAULT_SMTP_STARTTLS:-on}

		case "$user" in
			''|*[!A-Za-z0-9@._+-]*)
				echo "Invalid PHOTOVAULT_SMTP_USER." >&2
				exit 1
				;;
		esac
		if [ -z "$password" ] || printf '%s' "$password" | LC_ALL=C grep -q '[[:cntrl:]]'; then
			echo "PHOTOVAULT_SMTP_PASSWORD is missing or contains control characters." >&2
			exit 1
		fi
		validate_switch PHOTOVAULT_SMTP_TLS "$tls"
		validate_switch PHOTOVAULT_SMTP_STARTTLS "$starttls"

		umask 027
		printf '%s' "$password" > "$secret_file"
		chown root:www-data "$secret_file"
		chmod 0640 "$secret_file"

		cat > "$config_file" <<EOF
defaults
auth on
tls $tls
tls_starttls $starttls
tls_trust_file /etc/ssl/certs/ca-certificates.crt
logfile -

account external
host $host
port $port
user $user
passwordeval "cat $secret_file"
from $from

account default : external
EOF
		;;
	*)
		echo "PHOTOVAULT_SMTP_MODE must be mailpit or smtp." >&2
		exit 1
		;;
esac

chown root:www-data "$config_file"
chmod 0644 "$config_file"

exec docker-entrypoint.sh "$@"
