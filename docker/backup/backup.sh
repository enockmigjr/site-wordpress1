#!/bin/sh
set -eu

umask 077

requested_name="${1:-}"
if [ -n "$requested_name" ]; then
    case "$requested_name" in
        *[!A-Za-z0-9._-]*|.*|*..*)
            echo "Backup name must contain only letters, numbers, dots, underscores and hyphens." >&2
            exit 2
            ;;
    esac
    backup_name="$requested_name"
else
    backup_name="photovault-$(date -u +%Y%m%dT%H%M%SZ)"
fi

final_dir="/backups/$backup_name"
staging_dir="/backups/.${backup_name}.tmp.$$"
if [ -e "$final_dir" ] || [ -e "$staging_dir" ]; then
    echo "Backup destination already exists: $backup_name" >&2
    exit 3
fi

cleanup() {
    rm -rf -- "$staging_dir"
}
trap cleanup EXIT INT TERM

mkdir -p "$staging_dir" /source/uploads /source/photovault-private

MYSQL_PWD="$PHOTOVAULT_DB_PASSWORD" mariadb-dump \
    --host="$PHOTOVAULT_DB_HOST" \
    --user="$PHOTOVAULT_DB_USER" \
    --single-transaction \
    --quick \
    --routines \
    --triggers \
    --events \
    --hex-blob \
    --default-character-set=utf8mb4 \
    "$PHOTOVAULT_DB_NAME" | gzip -9 > "$staging_dir/database.sql.gz"

tar -C /source -czf "$staging_dir/media.tar.gz" uploads photovault-private

table_count="$(MYSQL_PWD="$PHOTOVAULT_DB_PASSWORD" mariadb \
    --host="$PHOTOVAULT_DB_HOST" \
    --user="$PHOTOVAULT_DB_USER" \
    --batch --skip-column-names \
    --execute="SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = DATABASE();" \
    "$PHOTOVAULT_DB_NAME")"

case "$PHOTOVAULT_DB_NAME" in
    ''|*[!A-Za-z0-9_$-]*)
        echo "Database name contains unsupported characters." >&2
        exit 4
        ;;
esac
case "$table_count" in
    ''|*[!0-9]*)
        echo "Could not determine the database table count." >&2
        exit 5
        ;;
esac

cat > "$staging_dir/manifest.txt" <<EOF
format_version=1
created_utc=$(date -u +%Y-%m-%dT%H:%M:%SZ)
database_name=$PHOTOVAULT_DB_NAME
database_tables=$table_count
media_roots=uploads,photovault-private
EOF

(
    cd "$staging_dir"
    sha256sum database.sql.gz media.tar.gz manifest.txt > checksums.sha256
    sha256sum -c checksums.sha256 >/dev/null
    gzip -t database.sql.gz
    tar -tzf media.tar.gz >/dev/null
)

mv -- "$staging_dir" "$final_dir"
trap - EXIT INT TERM
printf '%s\n' "$final_dir"
