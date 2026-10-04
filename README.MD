# cloud.by.vincent.mahn.ke

Hosts the container serving [cloud.by.vincent.mahn.ke](https://cloud.by.vincent.mahn.ke).

## Share Link View Tracker

`app/Dockerfile` combines the pinned official Nextcloud image with the semver
app artifact published by `ViMaSter/nextcloud-ShareLinkViewTracker` to GHCR.
The app does not need to be published to the Nextcloud App Store.

The shared deployment workflow already builds `app/Dockerfile`, pushes
`ghcr.io/mahn-ke/cloud-by-vincent:latest`, and pulls that image on the deployment
host. Both web and cron use it; no source submodule or plugin bind mount is used.
The app is downloaded at build time, not startup. Renovate updates the app image
reference and pins its digest, with explicit review rather than automerge.

### First deployment

1. Commit the app release implementation and publish its `v1.0.0` tag first.
2. Make `ghcr.io/vimaster/nextcloud-sharelinkviewtracker` public. The shared image
	build currently pulls dependencies without a ViMaSter registry login.
3. Back up the existing Nextcloud database and volume.
4. Merge the cloud changes only after the app artifact is available. The existing
	shared workflow builds and deploys the derived image. Do not edit generated
	workflow files.
5. Verify `docker compose exec -u www-data app php occ app:list` and access a
	public share to check the activity entry.

Startup synchronizes only `custom_apps/sharelinkviewtracker` before Nextcloud's
initialization, runs app migrations even when the Nextcloud version is unchanged,
and enables the app before Apache starts. A shared lock serializes initialization
and cron; old cron containers skip execution when their packaged app version no
longer matches the initialized volume. Cron starts only after the web healthcheck
passes. Long-running cron jobs can delay initialization until they complete.

Manual maintenance mode is preserved and defers app initialization. After
finishing maintenance, turn it off and restart the app container to initialize
the app again. Failed managed upgrades retain maintenance mode; investigate the
logs and complete recovery deliberately before resuming service.

For an entirely fresh Nextcloud instance, also provide `NEXTCLOUD_ADMIN_USER`
and `NEXTCLOUD_ADMIN_PASSWORD` (or supported Docker secrets) to automate initial
installation. Without them, finish web installation and restart the app; the
deployment healthcheck will not pass until initialization is complete.

The app's Nextcloud compatibility range is enforced by `occ app:enable`; do not
force-enable it after a Nextcloud major upgrade. The app is unsigned and may
produce integrity warnings. App downgrades are refused: reverting an image is
not a substitute for restoring a database/volume backup after migrations.

### Local integration checks

Build the app-only image in the app repository first, then run here:

```sh
docker build --build-arg SHARELINKVIEWTRACKER_IMAGE=sharelinkviewtracker-artifact:local \
  -t cloud-sharelinkviewtracker:local app
sh tests/integration.sh
```

The test uses a disposable SQLite instance, isolated containers, and a new named
volume, which it removes afterward. It checks first enablement, cron startup,
restart, an app-only upgrade, maintenance preservation, and downgrade refusal.