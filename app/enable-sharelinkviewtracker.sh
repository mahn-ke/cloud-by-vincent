#!/bin/sh
set -eu

installed=$(php -r 'if (!file_exists("/var/www/html/config/config.php")) { echo "no"; exit; } require "/var/www/html/config/config.php"; echo !empty($CONFIG["installed"]) ? "yes" : "no";')
if [ "$installed" != yes ]; then
    echo "Finish Nextcloud installation before enabling sharelinkviewtracker."
    flock -u 9
    exit 0
fi

maintenance=$(php -r 'require "/var/www/html/config/config.php"; echo !empty($CONFIG["maintenance"]) ? "yes" : "no";')
if [ "$maintenance" = yes ] && [ "${CLOUD_MANAGED_MAINTENANCE:-0}" != 1 ]; then
    echo "Preserving manual maintenance mode; app initialization deferred."
    flock -u 9
    exit 0
fi

current=$(php /var/www/html/occ config:app:get sharelinkviewtracker installed_version --default-value='')
packaged=$(php -r 'echo simplexml_load_file("/opt/nextcloud-apps/sharelinkviewtracker/appinfo/info.xml")->version;')
if [ -n "$current" ] && [ "$current" != "$packaged" ]; then
    php /var/www/html/occ upgrade --no-interaction
fi
php /var/www/html/occ app:enable sharelinkviewtracker
if [ "${CLOUD_MANAGED_MAINTENANCE:-0}" = 1 ]; then
    php /var/www/html/occ maintenance:mode --off
fi
php -r 'echo simplexml_load_file("/opt/nextcloud-apps/sharelinkviewtracker/appinfo/info.xml")->version;' > /var/www/html/.sharelinkviewtracker-ready
flock -u 9