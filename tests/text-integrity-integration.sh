#!/bin/sh
set -eu

cd "$(dirname "$0")/.."
project="cloud-text-integrity-test-$$"
compose() {
    docker compose -p "$project" -f tests/compose.yml "$@"
}
cleanup() {
    compose logs --no-color --tail=40 app
    compose down --volumes
}
trap cleanup EXIT

controller=/var/www/html/apps/text/lib/Controller/SessionController.php
hook=/docker-entrypoint-hooks.d/post-upgrade/verify-text-integrity.sh
cached_integrity() {
    compose exec -T -u www-data app php -r '
define("OC_CONSOLE", true);
require "/var/www/html/lib/base.php";
$results = \OCP\Server::get(\OC\IntegrityCheck\Checker::class)->getResults() ?? [];
if ($argv[1] === "invalid") {
    exit(isset($results["text"]["INVALID_HASH"]["lib/Controller/SessionController.php"]) ? 0 : 1);
}
exit(empty($results["text"]) ? 0 : 1);
' "$1"
}

compose up -d --wait --wait-timeout 180 app
compose exec -T -u www-data app php occ integrity:check-app text
compose exec -T app sh -c 'printf "\n// Disposable integrity test modification.\n" >> "$1"' sh "$controller"
if integrity=$(compose exec -T -u www-data app "$hook" 2>&1); then
    echo >&2 "Expected the upgrade hook to reject a modified signed Text controller"
    exit 1
fi
printf '%s\n' "$integrity" | grep -F 'INVALID_HASH'
printf '%s\n' "$integrity" | grep -F 'lib/Controller/SessionController.php'
cached_integrity invalid

compose restart app
compose up -d --wait --wait-timeout 120 app
compose exec -T app grep -F 'Disposable integrity test modification.' "$controller"
cached_integrity invalid

compose stop app
compose run --rm --no-deps --entrypoint php app -r '
$path = "/var/www/html/version.php";
require $path;
$previous = $OC_Version;
if ($previous[2] < 1) {
    throw new RuntimeException("This upgrade fixture requires a Nextcloud patch release.");
}
$previous[2]--;
$contents = preg_replace(
    "/\\\$OC_Version\s*=\s*array\s*\([^;]+;/",
    "\$OC_Version = " . var_export($previous, true) . ";",
    file_get_contents($path),
    1,
    $count
);
if ($count !== 1 || file_put_contents($path, $contents) === false) {
    throw new RuntimeException("Could not stage the disposable upgrade fixture.");
}
'
compose up -d --wait --wait-timeout 180 app
compose logs --no-color app | grep -F 'Verifying the upgraded, officially signed Text app'
compose exec -T app cmp "$controller" /usr/src/nextcloud/apps/text/lib/Controller/SessionController.php
cached_integrity clean
compose exec -T -u www-data app php occ integrity:check-core
echo "Same-version hotfix preservation, signed Text replacement, cached warning removal, and integrity failure checks passed."
