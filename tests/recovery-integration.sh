#!/bin/sh
set -eu

cd "$(dirname "$0")/.."
project="cloud-tracker-recovery-test-$$"
compose() {
    docker compose -p "$project" -f tests/compose.yml "$@"
}
cleanup() {
    compose logs --no-color --tail=30 app
    compose down --volumes
}
trap cleanup EXIT

current_version=$(docker run --rm --entrypoint php cloud-sharelinkviewtracker:local -r 'echo simplexml_load_file("/opt/nextcloud-apps/sharelinkviewtracker/appinfo/info.xml")->version;')
previous_version=$(docker run --rm --entrypoint php cloud-sharelinkviewtracker:local -r '$parts = explode(".", $argv[1]); $parts[2] = max(0, (int) $parts[2] - 1); echo implode(".", $parts);' "$current_version")
compose up -d --wait --wait-timeout 180 app
compose exec -T -u www-data app php occ config:app:set sharelinkviewtracker installed_version --value="$previous_version"
compose exec -T -u www-data app php occ app:disable sharelinkviewtracker
compose exec -T -u www-data app php occ maintenance:mode --on
compose restart app
compose up -d --wait --wait-timeout 120 app

installed_version=$(compose exec -T -u www-data app php occ config:app:get sharelinkviewtracker installed_version)
test "$installed_version" = "$current_version"
compose exec -T app php -r 'require "/var/www/html/config/config.php"; exit(!empty($CONFIG["maintenance"]) ? 1 : 0);'
compose exec -T -u www-data app php occ app:list --output=json | docker run --rm -i --entrypoint php cloud-sharelinkviewtracker:local -r '
$apps = json_decode(stream_get_contents(STDIN), true, 512, JSON_THROW_ON_ERROR);
if (($apps["enabled"]["sharelinkviewtracker"] ?? null) !== $argv[1]) { exit(1); }
' "$current_version"
echo "Interrupted managed maintenance recovery passed."