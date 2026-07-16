FROM wordpress:7.0-php8.2-fpm

ARG WP_CLI_VERSION=2.12.0

RUN set -eux; \
    export DEBIAN_FRONTEND=noninteractive; \
    apt-get update; \
    apt-get install -y --no-install-recommends ca-certificates curl default-mysql-client less msmtp-mta unzip; \
    rm -rf /var/lib/apt/lists/*

RUN set -eux; \
    cd /tmp; \
    curl -fsSLO "https://github.com/wp-cli/wp-cli/releases/download/v${WP_CLI_VERSION}/wp-cli-${WP_CLI_VERSION}.phar"; \
    curl -fsSLO "https://github.com/wp-cli/wp-cli/releases/download/v${WP_CLI_VERSION}/wp-cli-${WP_CLI_VERSION}.phar.sha512"; \
    expected="$(awk '{print $1}' wp-cli-${WP_CLI_VERSION}.phar.sha512)"; \
    echo "${expected}  wp-cli-${WP_CLI_VERSION}.phar" | sha512sum -c -; \
    install -m 0755 "wp-cli-${WP_CLI_VERSION}.phar" /usr/local/bin/wp; \
    rm "wp-cli-${WP_CLI_VERSION}.phar" "wp-cli-${WP_CLI_VERSION}.phar.sha512"; \
    wp --info --allow-root

COPY docker/php/msmtprc /etc/msmtprc
COPY docker/php/entrypoint.sh /usr/local/bin/photovault-entrypoint

RUN chmod 0644 /etc/msmtprc \
    && chmod 0755 /usr/local/bin/photovault-entrypoint

WORKDIR /var/www/html

ENTRYPOINT ["photovault-entrypoint"]
CMD ["php-fpm"]
