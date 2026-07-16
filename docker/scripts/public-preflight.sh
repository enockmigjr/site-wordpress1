#!/bin/sh
set -eu

public_url=${1:-}

case "$public_url" in
	https://*) ;;
	*)
		echo "PUBLIC_URL must start with https://" >&2
		exit 1
		;;
esac

command -v curl >/dev/null 2>&1 || {
	echo "curl is required for the public preflight." >&2
	exit 1
}

headers_file=$(mktemp)
trap 'rm -f "$headers_file"' EXIT HUP INT TERM

effective_url=$(curl --fail --silent --show-error --location --max-time 30 --proto '=https' --output /dev/null --write-out '%{url_effective}' "$public_url")

case "$effective_url" in
	https://*) ;;
	*)
		echo "The public URL redirects outside HTTPS: $effective_url" >&2
		exit 1
		;;
esac

http_code=$(curl --fail --silent --show-error --max-time 30 --proto '=https' --dump-header "$headers_file" --output /dev/null --write-out '%{http_code}' "$effective_url")
[ "$http_code" = "200" ] || {
	echo "Unexpected public HTTP status: $http_code" >&2
	exit 1
}

check_header() {
	header_name=$1
	if ! grep -qi "^${header_name}:" "$headers_file"; then
		echo "Missing required response header: $header_name" >&2
		exit 1
	fi
	echo "${header_name}=PASS"
}

check_header 'Strict-Transport-Security'
check_header 'Content-Security-Policy'
check_header 'X-Content-Type-Options'
check_header 'Referrer-Policy'

echo "PUBLIC_URL=$effective_url"
echo "PUBLIC_HTTPS_PREFLIGHT=PASS"
