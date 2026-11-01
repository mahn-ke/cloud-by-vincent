ARG SHARELINKVIEWTRACKER_IMAGE=ghcr.io/vimaster/nextcloud-sharelinkviewtracker:v1.0.2@sha256:76b99a05b2151aaae79ee6f841a22d4d59c8035442a2610aa739da1a44eda8b8
ARG PAPERLESSFORWARDER_IMAGE=ghcr.io/vimaster/nextcloud-paperlessforwarder:v1.0.4@sha256:348b60c0862d533163b5b27efc366da7081af9d8ffa0ca6a4a080c4a2d5da7a2
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