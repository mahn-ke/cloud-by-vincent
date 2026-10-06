#!/bin/sh
set -eu

exec 9>/var/www/html/.sharelinkviewtracker.lock
flock -x 9
    if [ -n "$current" ] && [ "$current" != "$version" ]; then

source=/opt/nextcloud-apps/sharelinkviewtracker
target=/var/www/html/custom_apps/sharelinkviewtracker
version=$(php -r 'echo simplexml_load_file($argv[1])->version;' "$source/appinfo/info.xml")
export CLOUD_MANAGED_MAINTENANCE=0
managed_marker=/var/www/html/.sharelinkviewtracker-managed-maintenance

if [ -f "$target/appinfo/info.xml" ]; then
    previous=$(php -r 'echo simplexml_load_file($argv[1])->version;' "$target/appinfo/info.xml")
    php -r 'exit(version_compare($argv[1], $argv[2], ">") ? 1 : 0);' "$previous" "$version" || {
        echo >&2 "Refusing to downgrade sharelinkviewtracker from $previous to $version; restore a backup instead."
        exit 1
    }
else
    previous=
fi

if [ "$previous" != "$version" ] && [ -f /var/www/html/config/config.php ]; then
    state=$(php -r 'require "/var/www/html/config/config.php"; echo !empty($CONFIG["installed"]) && empty($CONFIG["maintenance"]) ? "ready" : "other";')
    if [ "$state" = ready ]; then
        su -p www-data -s /bin/sh -c 'php /var/www/html/occ maintenance:mode --on'
        touch "$managed_marker"
        export CLOUD_MANAGED_MAINTENANCE=1
    fi
fi

if [ -f /var/www/html/config/config.php ]; then
    maintenance=$(php -r 'require "/var/www/html/config/config.php"; echo !empty($CONFIG["maintenance"]) ? "yes" : "no";')
    if [ "$maintenance" = yes ]; then
        if [ "${CLOUD_RECOVER_MANAGED_MAINTENANCE:-0}" = 1 ] && [ ! -f "$managed_marker" ]; then
            current=$(su -p www-data -s /bin/sh -c 'php /var/www/html/occ config:app:get sharelinkviewtracker installed_version --default-value=""')
            if [ "$current" != "$version" ]; then
                touch "$managed_marker"
            fi
        fi
        if [ -f "$managed_marker" ]; then
            export CLOUD_MANAGED_MAINTENANCE=1
        fi
    fi
fi

mkdir -p "$target"
rsync -a --delete --chown=www-data:www-data "$source/" "$target/"
exec /entrypoint.sh "$@"