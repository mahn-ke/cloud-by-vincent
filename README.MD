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

## Paperless Forwarder

The cloud image also packages `paperlessforwarder` from its GHCR app artifact.
The app and cron containers share the `PAPERLESS_FORWARDER_MODE`, user ID, and
scope path; the Paperless API token is passed to the cron container only.
Forwarding stays off by default, and the default path is `/Paperless`, including
its subdirectories. Configure the token as the
`PAPERLESS_API_TOKEN` deployment secret; set the `PAPERLESS_FORWARDER_MODE`
deployment secret to `live` to enable forwarding. Production uses this scope
after successful canary validation. For a new deployment, first override
`PAPERLESS_FORWARDER_PATH` to `/Paperless/_forwarder-test` for both containers
until the canary passes. The configured Nextcloud user defaults to the intended
account.

The app upgrade lifecycle and readiness marker are managed alongside the share
tracker. The app code is synced into `custom_apps` before Nextcloud starts, and
cron waits until both packaged app versions match the initialized volume.

### First deployment

1. Commit the app release implementation and publish its `v1.0.0` tag first.
2. Make both app packages public. The shared image build pulls dependencies
	without a ViMaSter registry login.
3. Back up the existing Nextcloud database and volume.
4. Merge the cloud changes only after the app artifact is available. The existing
	shared workflow builds and deploys the derived image. Do not edit generated
	workflow files.
5. Verify `docker compose exec -u www-data app php occ app:list` and access a
	public share to check the activity entry.

Startup synchronizes only `custom_apps/sharelinkviewtracker` and
`custom_apps/paperlessforwarder` before Nextcloud's
initialization, runs app migrations even when the Nextcloud version is unchanged,
and enables the app before Apache starts. A shared lock serializes initialization
and cron; old cron containers skip execution when their packaged app version no
longer matches the initialized volume. Cron starts only after the web healthcheck
passes. Long-running cron jobs can delay initialization until they complete.

Both containers must mount the shared `cloud_runtime` volume at `/var/lib/cloud`.
It holds the lock, readiness files, and managed-maintenance marker outside
Nextcloud's signed core directory. Startup migrates the legacy root-level markers
after waiting for any active legacy cron pass; the replacement cron container
removes any legacy lock recreated during rollout. Deploy both containers together.
After upgrading, run `docker compose exec -u www-data app php occ integrity:check-core`
to refresh Nextcloud's cached integrity result. Do not disable integrity checks.

Manual maintenance mode is preserved and defers app initialization. After
finishing maintenance, turn it off and restart the app container to initialize
the app again. Failed managed upgrades retain maintenance mode; investigate the
logs and complete recovery deliberately before resuming service.

For an entirely fresh Nextcloud instance, also provide `NEXTCLOUD_ADMIN_USER`
and `NEXTCLOUD_ADMIN_PASSWORD` (or supported Docker secrets) to automate initial
installation. Without them, finish web installation and restart the app; the
deployment healthcheck will not pass until initialization is complete.

The app's Nextcloud compatibility range is enforced by `occ app:enable`; do not
force-enable it after a Nextcloud major upgrade. Both custom apps are unsigned;
Nextcloud skips their app signature checks. This is separate from the signed core
integrity check, which must pass. App downgrades are refused: reverting an image is
not a substitute for restoring a database/volume backup after migrations.

### Retiring the Text session-close hotfix

The production Text 9.0.1 controller has a temporary source hotfix for mobile
session closing ([nextcloud/text#9385](https://github.com/nextcloud/text/pull/9385)).
Its `INVALID_HASH` warning is genuine; do not disable integrity checks, alter
signature metadata, or restore the old controller while it still contains the
session-close bug.

The official stable-35 backport is
[nextcloud/text#9510](https://github.com/nextcloud/text/pull/9510), included in
Text 9.0.2 in Nextcloud 35.0.3 RC1. As of November 8, 2026, the latest stable
Nextcloud image is still 35.0.2. Keep that pin until an official stable image
containing the fix is published; do not deploy the release candidate merely to
remove the warning. Renovate tracks the base image in `app/Dockerfile`.

When updating to that stable release, back up the database and volume and deploy
web and cron together. The official image entrypoint replaces bundled Text with
the release's signed files during the Nextcloud upgrade. The post-upgrade
`verify-text-integrity.sh` hook then runs `occ integrity:check-app text`, refreshing
the cached warning and reporting any remaining signature failures with a nonzero
exit status. An ordinary same-version restart does not replace the hotfix.

After deployment, verify `docker compose exec -u www-data app php occ integrity:check-app text`
and test closing the rich editor followed by a plain-editor save on a disposable
note. Both requests should succeed without a lingering Text lock.

### Local integration checks

Build the Paperless Forwarder app artifact in its repository first, then run
these commands from this repository:

```sh
docker build -f ../nextcloud-PaperlessForwarder/packaging/Dockerfile \
  -t paperlessforwarder-artifact:local ../nextcloud-PaperlessForwarder
docker build --build-arg PAPERLESSFORWARDER_IMAGE=paperlessforwarder-artifact:local \
  -t cloud-sharelinkviewtracker:local app
sh tests/integration.sh
sh tests/text-integrity-integration.sh
```

The test uses a disposable SQLite instance, isolated containers, and a new named
volume, which it removes afterward. It checks first enablement, cron startup,
restart, app-only upgrades, maintenance preservation, downgrade refusal, core
integrity, and migration of legacy lifecycle markers.

The Text test uses a separate disposable instance. It modifies the signed
controller, confirms that a same-version restart preserves it and its warning,
then lowers only the fixture's installed code version to exercise the official
image upgrade path. It checks signed-file replacement and cached-warning removal
without rescanning to hide a missing hook. This tests the deployment lifecycle,
not the availability or session-close behavior of a future stable release.