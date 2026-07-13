#!/bin/sh
set -eu

while true; do
    if wp core is-installed --allow-root --path=/var/www/html 2>/dev/null; then
        if ! wp cron event run --due-now --allow-root --path=/var/www/html; then
            echo "PhotoVault cron: wp cron event run failed" >&2
        fi
    else
        echo "PhotoVault cron: waiting for WordPress installation"
    fi
    sleep 60
done
