#!/bin/sh
set -eu

umask 077

mode="${1:-verify}"
backup_name="${2:-}"

case "$mode" in
    verify|test|apply) ;;
    *)
        echo "Usage: photovault-restore verify|test|apply BACKUP_NAME" >&2
        exit 2
        ;;
esac
case "$backup_name" in
    ''|*[!A-Za-z0-9._-]*|.*|*..*)
        echo "Invalid backup name." >&2
        exit 2
        ;;
esac

backup_dir="/backups/$backup_name"

root_db() {
    MYSQL_PWD="$PHOTOVAULT_DB_ROOT_PASSWORD" mariadb --host="$PHOTOVAULT_DB_HOST" --user=root "$@"
}

app_dump() {
    MYSQL_PWD="$PHOTOVAULT_DB_PASSWORD" mariadb-dump --host="$PHOTOVAULT_DB_HOST" --user="$PHOTOVAULT_DB_USER" "$@"
}

for required in database.sql.gz media.tar.gz manifest.txt checksums.sha256; do
    if [ ! -f "$backup_dir/$required" ]; then
        echo "Backup file missing: $required" >&2
        exit 3
    fi
done

cd "$backup_dir"
sha256sum -c checksums.sha256
gzip -t database.sql.gz

if tar -tzf media.tar.gz | grep -Eq '(^/|(^|/)\.\.(/|$))'; then
    echo "Unsafe path detected in media archive." >&2
    exit 4
fi

format_version=''
manifest_database=''
manifest_tables=''
while IFS='=' read -r key value; do
    case "$key" in
        format_version) format_version="$value" ;;
        database_name) manifest_database="$value" ;;
        database_tables) manifest_tables="$value" ;;
    esac
done < manifest.txt

case "$format_version" in
    1) ;;
    *) echo "Unsupported backup format." >&2; exit 5 ;;
esac
case "$manifest_database" in
    ''|*[!A-Za-z0-9_$-]*) echo "Invalid database name in manifest." >&2; exit 5 ;;
esac
case "$manifest_tables" in
    ''|*[!0-9]*) echo "Invalid table count in manifest." >&2; exit 5 ;;
esac

if [ "$mode" = 'verify' ]; then
    echo "Backup verified: $backup_name"
    exit 0
fi

test_database="pv_restore_test_$(date -u +%Y%m%d%H%M%S)_$$"
test_media="/tmp/$test_database-media"

drop_test_database() {
    root_db --execute="DROP DATABASE IF EXISTS \`$test_database\`;" >/dev/null 2>&1 || true
    rm -rf -- "$test_media"
}
trap drop_test_database EXIT INT TERM

root_db --execute="CREATE DATABASE \`$test_database\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"
gzip -dc database.sql.gz | root_db "$test_database"

restored_tables="$(root_db \
    --batch --skip-column-names \
    --execute="SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = '$test_database';")"
if [ "$restored_tables" -ne "$manifest_tables" ]; then
    echo "Database restore test mismatch: expected $manifest_tables tables, restored $restored_tables." >&2
    exit 6
fi

mkdir -p "$test_media"
tar -xzf media.tar.gz -C "$test_media"
for media_root in uploads photovault-private; do
    if [ ! -d "$test_media/$media_root" ]; then
        echo "Media restore test is missing $media_root." >&2
        exit 7
    fi
done

if [ "$mode" = 'test' ]; then
    echo "Restore test passed: $backup_name ($restored_tables tables)"
    exit 0
fi

if [ "${CONFIRM_RESTORE:-}" != "$PHOTOVAULT_DB_NAME" ]; then
    echo "Refusing live restore. Set CONFIRM_RESTORE to the current database name." >&2
    exit 8
fi
if [ "${MAINTENANCE_CONFIRMED:-}" != 'YES' ]; then
    echo "Refusing live restore while application maintenance is not confirmed." >&2
    exit 8
fi
if [ "$manifest_database" != "$PHOTOVAULT_DB_NAME" ]; then
    echo "Backup database does not match the configured target database." >&2
    exit 8
fi

rollback_stamp="$(date -u +%Y%m%dT%H%M%SZ)"
rollback_db="$backup_dir/pre-restore-$rollback_stamp.sql.gz"
rollback_media="$backup_dir/pre-restore-media-$rollback_stamp.tar.gz"

app_dump \
    --single-transaction --quick --routines --triggers --events --hex-blob \
    "$PHOTOVAULT_DB_NAME" | gzip -9 > "$rollback_db"
tar -C /restore -czf "$rollback_media" uploads photovault-private

restore_rollback() {
    echo "Restore failed; applying automatic rollback." >&2
    gzip -dc "$rollback_db" | root_db "$PHOTOVAULT_DB_NAME" || true
    find /restore/uploads -mindepth 1 -maxdepth 1 -exec rm -rf -- {} +
    find /restore/photovault-private -mindepth 1 -maxdepth 1 -exec rm -rf -- {} +
    tar -xzf "$rollback_media" -C /restore || true
}

trap 'restore_rollback; drop_test_database' EXIT INT TERM
gzip -dc database.sql.gz | root_db "$PHOTOVAULT_DB_NAME"
find /restore/uploads -mindepth 1 -maxdepth 1 -exec rm -rf -- {} +
find /restore/photovault-private -mindepth 1 -maxdepth 1 -exec rm -rf -- {} +
cp -a "$test_media/uploads/." /restore/uploads/
cp -a "$test_media/photovault-private/." /restore/photovault-private/

trap drop_test_database EXIT INT TERM
echo "Restore completed: $backup_name"
