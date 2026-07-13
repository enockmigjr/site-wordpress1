#!/bin/sh
set -eu

root="$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)"
target="$root/.env"

if [ -e "$target" ]; then
    echo ".env already exists. Remove it explicitly before generating new secrets." >&2
    exit 1
fi

secret() {
    openssl rand -hex "$1"
}

cat > "$target" <<EOF
PHOTOVAULT_HTTP_PORT=8080
MAILPIT_UI_PORT=8025
PHOTOVAULT_ENV=development
WORDPRESS_DEBUG=1
WORDPRESS_FORCE_SSL_ADMIN=0

WORDPRESS_DB_NAME=photovault
WORDPRESS_DB_USER=photovault
WORDPRESS_DB_PASSWORD=$(secret 24)
MARIADB_ROOT_PASSWORD=$(secret 24)
WORDPRESS_TABLE_PREFIX=wp_

WORDPRESS_AUTH_KEY=$(secret 64)
WORDPRESS_SECURE_AUTH_KEY=$(secret 64)
WORDPRESS_LOGGED_IN_KEY=$(secret 64)
WORDPRESS_NONCE_KEY=$(secret 64)
WORDPRESS_AUTH_SALT=$(secret 64)
WORDPRESS_SECURE_AUTH_SALT=$(secret 64)
WORDPRESS_LOGGED_IN_SALT=$(secret 64)
WORDPRESS_NONCE_SALT=$(secret 64)
EOF

chmod 600 "$target"
echo "Generated $target with cryptographically random local secrets."
