ARG SHARELINKVIEWTRACKER_IMAGE=ghcr.io/vimaster/nextcloud-sharelinkviewtracker:v1.0.2@sha256:76b99a05b2151aaae79ee6f841a22d4d59c8035442a2610aa739da1a44eda8b8
ARG PAPERLESSFORWARDER_IMAGE=ghcr.io/vimaster/nextcloud-paperlessforwarder:v1.0.0@sha256:86ed5f40c7a3c3d5d0d188b2be8ccfab0d3c482f9d8afcc7a09c03494f512de1
FROM ${SHARELINKVIEWTRACKER_IMAGE} AS tracker

FROM ${PAPERLESSFORWARDER_IMAGE} AS paperlessforwarder

FROM nextcloud:35.0.2-apache
COPY --from=tracker /sharelinkviewtracker /opt/nextcloud-apps/sharelinkviewtracker
COPY --from=paperlessforwarder /paperlessforwarder /opt/nextcloud-apps/paperlessforwarder
COPY --chmod=755 entrypoint.sh cron.sh healthcheck.sh /usr/local/bin/cloud/
COPY --chmod=755 enable-sharelinkviewtracker.sh /docker-entrypoint-hooks.d/before-starting/
COPY --chmod=755 enable-paperlessforwarder.sh /docker-entrypoint-hooks.d/before-starting/
ENTRYPOINT ["/usr/local/bin/cloud/entrypoint.sh"]
CMD ["apache2-foreground"]