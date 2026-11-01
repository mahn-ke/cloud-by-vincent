#!/bin/sh
set -eu

version=$(php -r 'echo simplexml_load_file("/opt/nextcloud-apps/sharelinkviewtracker/appinfo/info.xml")->version;')
paperless_version=$(php -r 'echo simplexml_load_file("/opt/nextcloud-apps/paperlessforwarder/appinfo/info.xml")->version;')
# The replaced cron container may have recreated this while waiting for rollout.
rm -f /var/www/html/.sharelinkviewtracker.lock
while true; do
    (
        exec 9>/var/lib/cloud/sharelinkviewtracker.lock
        flock -s 9
        if [ -f /var/lib/cloud/sharelinkviewtracker-ready ] \
            && [ "$(cat /var/lib/cloud/sharelinkviewtracker-ready)" = "$version" ] \
            && [ -f /var/lib/cloud/paperlessforwarder-ready ] \
            && [ "$(cat /var/lib/cloud/paperlessforwarder-ready)" = "$paperless_version" ]; then
            su -p www-data -s /bin/sh -c 'php -f /var/www/html/cron.php' 9>&- || echo >&2 "Nextcloud cron failed; retrying next cycle."
        fi
    )
    sleep 300
done