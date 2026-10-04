ARG SHARELINKVIEWTRACKER_IMAGE=ghcr.io/vimaster/nextcloud-sharelinkviewtracker:v1.0.0@sha256:068433b64ad503686a99093fe85fb6356fe352ba6bbc1d87b22c2c5e79840564
FROM ${SHARELINKVIEWTRACKER_IMAGE} AS tracker

FROM nextcloud:33.0.9-apache
COPY --from=tracker /sharelinkviewtracker /opt/nextcloud-apps/sharelinkviewtracker
COPY --chmod=755 entrypoint.sh cron.sh healthcheck.sh /usr/local/bin/cloud/
COPY --chmod=755 enable-sharelinkviewtracker.sh /docker-entrypoint-hooks.d/before-starting/
ENTRYPOINT ["/usr/local/bin/cloud/entrypoint.sh"]
CMD ["apache2-foreground"]