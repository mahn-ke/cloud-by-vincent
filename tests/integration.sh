#!/bin/sh
set -eu

cd "$(dirname "$0")/.."
project="cloud-tracker-test-$$"
compose() {
    docker compose -p "$project" -f tests/compose.yml "$@"
}
cleanup() {
    compose logs --no-color --tail=30 app
    compose down --volumes
}
trap cleanup EXIT

initial_version=$(docker run --rm --entrypoint php cloud-sharelinkviewtracker:local -r 'echo simplexml_load_file("/opt/nextcloud-apps/sharelinkviewtracker/appinfo/info.xml")->version;')
paperless_version=$(docker run --rm --entrypoint php cloud-sharelinkviewtracker:local -r 'echo simplexml_load_file("/opt/nextcloud-apps/paperlessforwarder/appinfo/info.xml")->version;')
next_version=$(docker run --rm --entrypoint php cloud-sharelinkviewtracker:local -r '$parts = explode(".", $argv[1]); $parts[2] = (int) $parts[2] + 1; echo implode(".", $parts);' "$initial_version")
paperless_next_version=$(docker run --rm --entrypoint php cloud-sharelinkviewtracker:local -r '$parts = explode(".", $argv[1]); $parts[2] = (int) $parts[2] + 1; echo implode(".", $parts);' "$paperless_version")
compose up -d --wait --wait-timeout 180 app
compose exec -T -u www-data app php occ integrity:check-core
backgroundjobs_mode=$(compose exec -T -u www-data app php occ config:system:get backgroundjobs_mode)
test "$backgroundjobs_mode" = cron
compose exec -T -u www-data app php occ app:list --output=json | docker run --rm -i --entrypoint php cloud-sharelinkviewtracker:local -r '
$apps = json_decode(stream_get_contents(STDIN), true, 512, JSON_THROW_ON_ERROR);
if (($apps["enabled"]["sharelinkviewtracker"] ?? null) !== $argv[1]) { exit(1); }
' "$initial_version"
compose exec -T -u www-data app php occ app:list --output=json | docker run --rm -i --entrypoint php cloud-sharelinkviewtracker:local -r '
$apps = json_decode(stream_get_contents(STDIN), true, 512, JSON_THROW_ON_ERROR);
if (($apps["enabled"]["paperlessforwarder"] ?? null) !== $argv[1]) { exit(1); }
' "$paperless_version"
ready_version=$(compose exec -T app cat /var/lib/cloud/paperlessforwarder-ready)
test "$ready_version" = "$paperless_version"
webdav() {
    code=$(compose exec -T app curl -s -o /dev/null -w '%{http_code}' -u integration-admin:disposable-integration-password \
        "$@")
    test "$code" = 201 || {
        echo >&2 "WebDAV request $* returned $code"
        exit 1
    }
}
dav=http://localhost/remote.php/dav/files/integration-admin
webdav -X MKCOL "$dav/Paperless"
webdav -X PUT --data-binary 'integration upload' "$dav/Paperless/upload.pdf"
webdav -X PUT --data-binary 'integration upload' "$dav/upload.pdf"

compose exec -T app touch /var/www/html/.sharelinkviewtracker.lock
compose exec -T app cp /var/lib/cloud/sharelinkviewtracker-ready /var/www/html/.sharelinkviewtracker-ready
compose exec -T app cp /var/lib/cloud/paperlessforwarder-ready /var/www/html/.paperlessforwarder-ready
if integrity=$(compose exec -T -u www-data app php occ integrity:check-core); then
    echo >&2 "Expected legacy lifecycle files to fail core integrity"
    exit 1
fi
for name in .sharelinkviewtracker.lock .sharelinkviewtracker-ready .paperlessforwarder-ready; do
    printf '%s\n' "$integrity" | grep -F -- "$name:"
done
compose restart app
compose up -d --wait --wait-timeout 120 app
compose exec -T -u www-data app php occ integrity:check-core
# Simulate a sleeping legacy cron container waking before it is replaced.
compose exec -T app touch /var/www/html/.sharelinkviewtracker.lock
compose up -d --wait --wait-timeout 120 cron
compose stop --timeout 1 cron
compose exec -T -u www-data app php occ integrity:check-core
compose exec -T -u www-data app php occ app:disable sharelinkviewtracker
compose exec -T -u www-data app php occ config:app:delete sharelinkviewtracker installed_version
compose exec -T app rm -rf /var/www/html/custom_apps/sharelinkviewtracker
compose restart app
compose up -d --wait --wait-timeout 120 app
compose exec -T app /usr/local/bin/cloud/healthcheck.sh
version=$(compose exec -T -u www-data app php occ config:app:get sharelinkviewtracker installed_version)
test "$version" = "$initial_version"

compose exec -T app rm -rf /var/www/html/custom_apps/sharelinkviewtracker
compose restart app
compose up -d --wait --wait-timeout 120 app
compose exec -T app /usr/local/bin/cloud/healthcheck.sh

compose exec -T app php -r '
$path = "/opt/nextcloud-apps/sharelinkviewtracker/appinfo/info.xml";
$info = simplexml_load_file($path);
$info->version = $argv[1];
$info->asXML($path);
' "$next_version"
compose restart app
compose up -d --wait --wait-timeout 120 app
version=$(compose exec -T -u www-data app php occ config:app:get sharelinkviewtracker installed_version)
test "$version" = "$next_version"
compose exec -T app /usr/local/bin/cloud/healthcheck.sh

compose exec -T app php -r '
$path = "/opt/nextcloud-apps/paperlessforwarder/appinfo/info.xml";
$info = simplexml_load_file($path);
$info->version = $argv[1];
$info->asXML($path);
' "$paperless_next_version"
compose restart app
compose up -d --wait --wait-timeout 120 app
paperless_installed_version=$(compose exec -T -u www-data app php occ config:app:get paperlessforwarder installed_version)
test "$paperless_installed_version" = "$paperless_next_version"
compose exec -T app /usr/local/bin/cloud/healthcheck.sh

compose exec -T -u www-data app php occ integrity:check-core
compose exec -T -u www-data app php occ maintenance:mode --on
compose restart app
compose exec -T app sh -c 'flock -s /var/lib/cloud/sharelinkviewtracker.lock true; test ! -f /var/lib/cloud/sharelinkviewtracker-ready; test ! -f /var/lib/cloud/paperlessforwarder-ready'
compose exec -T app php -r 'require "/var/www/html/config/config.php"; exit(!empty($CONFIG["maintenance"]) ? 0 : 1);'

compose stop app
compose run --rm --no-deps --entrypoint /usr/local/bin/cloud/entrypoint.sh app apache2-foreground && {
    echo >&2 "Expected downgrade refusal"
    exit 1
}
echo "Fresh installation, core integrity, legacy marker migration, WebDAV upload, restart, app-only upgrade, maintenance, and downgrade checks passed."