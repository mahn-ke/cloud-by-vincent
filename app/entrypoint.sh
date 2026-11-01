#!/bin/sh
set -eu

mkdir -p /var/lib/cloud
chown www-data:www-data /var/lib/cloud
exec 9>/var/lib/cloud/sharelinkviewtracker.lock
flock -x 9

# Wait for any legacy cron pass before invalidating its readiness markers.
if [ -f /var/www/html/.sharelinkviewtracker.lock ]; then
    exec 8>/var/www/html/.sharelinkviewtracker.lock
    flock -x 8
fi
if [ -f /var/www/html/.sharelinkviewtracker-managed-maintenance ]; then
    mv /var/www/html/.sharelinkviewtracker-managed-maintenance /var/lib/cloud/sharelinkviewtracker-managed-maintenance
fi
rm -f /var/www/html/.sharelinkviewtracker-ready /var/www/html/.paperlessforwarder-ready /var/www/html/.sharelinkviewtracker.lock
exec 8>&-

source=/opt/nextcloud-apps/sharelinkviewtracker
target=/var/www/html/custom_apps/sharelinkviewtracker
version=$(php -r 'echo simplexml_load_file($argv[1])->version;' "$source/appinfo/info.xml")
paperless_source=/opt/nextcloud-apps/paperlessforwarder
paperless_target=/var/www/html/custom_apps/paperlessforwarder
paperless_version=$(php -r 'echo simplexml_load_file($argv[1])->version;' "$paperless_source/appinfo/info.xml")
export CLOUD_MANAGED_MAINTENANCE=0
managed_marker=/var/lib/cloud/sharelinkviewtracker-managed-maintenance

if [ -f "$target/appinfo/info.xml" ]; then
    previous=$(php -r 'echo simplexml_load_file($argv[1])->version;' "$target/appinfo/info.xml")
    php -r 'exit(version_compare($argv[1], $argv[2], ">") ? 1 : 0);' "$previous" "$version" || {
        echo >&2 "Refusing to downgrade sharelinkviewtracker from $previous to $version; restore a backup instead."
        exit 1
    }
else
    previous=
fi

if [ -f "$paperless_target/appinfo/info.xml" ]; then
    paperless_previous=$(php -r 'echo simplexml_load_file($argv[1])->version;' "$paperless_target/appinfo/info.xml")
    php -r 'exit(version_compare($argv[1], $argv[2], ">") ? 1 : 0);' "$paperless_previous" "$paperless_version" || {
        echo >&2 "Refusing to downgrade paperlessforwarder from $paperless_previous to $paperless_version; restore a backup instead."
        exit 1
    }
else
    paperless_previous=
fi

if { [ "$previous" != "$version" ] || [ "$paperless_previous" != "$paperless_version" ]; } && [ -f /var/www/html/config/config.php ]; then
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
            paperless_current=$(su -p www-data -s /bin/sh -c 'php /var/www/html/occ config:app:get paperlessforwarder installed_version --default-value=""')
            if { [ -n "$current" ] && [ "$current" != "$version" ]; } || { [ -n "$paperless_current" ] && [ "$paperless_current" != "$paperless_version" ]; }; then
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
mkdir -p "$paperless_target"
rsync -a --delete --chown=www-data:www-data "$paperless_source/" "$paperless_target/"
rm -f /var/lib/cloud/sharelinkviewtracker-ready /var/lib/cloud/paperlessforwarder-ready
exec /entrypoint.sh "$@"