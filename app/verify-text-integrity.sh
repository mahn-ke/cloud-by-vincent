#!/bin/sh
set -eu

echo "Verifying the upgraded, officially signed Text app and refreshing its integrity result."
php /var/www/html/occ integrity:check-app text
