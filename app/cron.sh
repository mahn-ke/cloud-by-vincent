#!/bin/sh
set -eu

version=$(php -r 'echo simplexml_load_file("/opt/nextcloud-apps/sharelinkviewtracker/appinfo/info.xml")->version;')
while true; do
    (
        exec 9>/var/www/html/.sharelinkviewtracker.lock
        flock -s 9
        if [ -f /var/www/html/.sharelinkviewtracker-ready ] && [ "$(cat /var/www/html/.sharelinkviewtracker-ready)" = "$version" ]; then
            su -p www-data -s /bin/sh -c 'php -f /var/www/html/cron.php' 9>&- || echo >&2 "Nextcloud cron failed; retrying next cycle."
        fi
    )
    sleep 300
done