ARG SHARELINKVIEWTRACKER_IMAGE=ghcr.io/vimaster/nextcloud-sharelinkviewtracker:v1.0.2@sha256:76b99a05b2151aaae79ee6f841a22d4d59c8035442a2610aa739da1a44eda8b8
FROM ${SHARELINKVIEWTRACKER_IMAGE} AS tracker

FROM nextcloud:35.0.1-apache
COPY --from=tracker /sharelinkviewtracker /opt/nextcloud-apps/sharelinkviewtracker
COPY --chmod=755 entrypoint.sh cron.sh healthcheck.sh /usr/local/bin/cloud/
COPY --chmod=755 enable-sharelinkviewtracker.sh /docker-entrypoint-hooks.d/before-starting/
ENTRYPOINT ["/usr/local/bin/cloud/entrypoint.sh"]
CMD ["apache2-foreground"]