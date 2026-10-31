#!/bin/sh
set -eu

test -f /var/www/html/.sharelinkviewtracker-ready
test -f /var/www/html/.paperlessforwarder-ready
test "$(cat /var/www/html/.paperlessforwarder-ready)" = "$(php -r 'echo simplexml_load_file("/opt/nextcloud-apps/paperlessforwarder/appinfo/info.xml")->version;')"
curl --fail --silent http://127.0.0.1/status.php | php -r '
$status = json_decode(stream_get_contents(STDIN), true, 512, JSON_THROW_ON_ERROR);
exit(!empty($status["installed"]) && empty($status["maintenance"]) && empty($status["needsDbUpgrade"]) ? 0 : 1);
'