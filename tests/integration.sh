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
next_version=$(docker run --rm --entrypoint php cloud-sharelinkviewtracker:local -r '$parts = explode(".", $argv[1]); $parts[2] = (int) $parts[2] + 1; echo implode(".", $parts);' "$initial_version")
compose up -d --wait --wait-timeout 180 app
compose exec -T -u www-data app php occ app:list --output=json | docker run --rm -i --entrypoint php cloud-sharelinkviewtracker:local -r '
$apps = json_decode(stream_get_contents(STDIN), true, 512, JSON_THROW_ON_ERROR);
if (($apps["enabled"]["sharelinkviewtracker"] ?? null) !== $argv[1]) { exit(1); }
' "$initial_version"
compose up -d --wait --wait-timeout 120 cron
compose stop --timeout 1 cron
compose exec -T -u www-data app php occ app:disable sharelinkviewtracker
compose exec -T -u www-data app php occ config:app:delete sharelinkviewtracker installed_version
compose exec -T app rm -rf /var/www/html/custom_apps/sharelinkviewtracker
compose restart app
compose up -d --wait --wait-timeout 120 app
compose exec -T app /usr/local/bin/cloud/healthcheck.sh
version=$(compose exec -T -u www-data app php occ config:app:get sharelinkviewtracker installed_version)
test "$version" = "$initial_version"

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

compose exec -T -u www-data app php occ maintenance:mode --on
compose restart app
compose exec -T app sh -c 'flock -s /var/www/html/.sharelinkviewtracker.lock true; test ! -f /var/www/html/.sharelinkviewtracker-ready'
compose exec -T app php -r 'require "/var/www/html/config/config.php"; exit(!empty($CONFIG["maintenance"]) ? 0 : 1);'

compose stop app
compose run --rm --no-deps --entrypoint /usr/local/bin/cloud/entrypoint.sh app apache2-foreground && {
    echo >&2 "Expected downgrade refusal"
    exit 1
}
echo "Fresh installation, restart, app-only upgrade, maintenance, and downgrade checks passed."