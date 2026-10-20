# syntax=docker/dockerfile:1.28
# Skeleton runtime image (builder -> runner), the repo's only top-level
# Dockerfile; an instance replaces the app parts and keeps the shape. The
# devcontainer image is the base-owned .devcontainer/Dockerfile's `develop`
# stage. As shipped it serves GET /health/live on port 8000 (busybox httpd)
# so `make release-check` has a real image to smoke-test; template-docker
# releases itself through that contract.

# Also declared in .devcontainer/Dockerfile; scripts/check-dockerfile-versions.sh
# keeps the two equal.
ARG DEBIAN_VERSION=trixie

ARG APP_UID=1000

ARG SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt
ARG SSL_CERT_DIR=/etc/ssl/certs

########################################
# builder -- produces what the runner needs (here: a static busybox)
########################################
FROM debian:${DEBIAN_VERSION}-slim AS builder
ARG SSL_CERT_FILE
ARG SSL_CERT_DIR

ENV SSL_CERT_FILE=${SSL_CERT_FILE} \
    SSL_CERT_DIR=${SSL_CERT_DIR} \
    DEBIAN_FRONTEND=noninteractive

RUN apt-get update \
    && apt-get install -y --no-install-recommends busybox-static \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /build
RUN mkdir -p www/health \
    && printf 'ok\n' > www/health/live

########################################
# runner -- minimal runtime image. Runs under an arbitrary UID (e.g.
# OpenShift's restricted SCC) as well as a fixed one: see runner-setup.sh.
########################################
FROM debian:${DEBIAN_VERSION}-slim AS runner
ARG APP_UID
ARG SSL_CERT_FILE
ARG SSL_CERT_DIR
# Set by `make build` through BUILD_ARGS in image.mk when an instance wants
# them; empty otherwise.
ARG APP_VERSION=
ARG APP_COMMIT=

ENV APP_VERSION=${APP_VERSION} \
    APP_COMMIT=${APP_COMMIT} \
    HOME=/home/appuser \
    SSL_CERT_FILE=${SSL_CERT_FILE} \
    SSL_CERT_DIR=${SSL_CERT_DIR}

COPY --from=builder /bin/busybox /usr/local/bin/busybox
COPY --from=builder --chown=${APP_UID}:0 --chmod=750 /build/www /app/www
WORKDIR /app

COPY scripts/runner-setup.sh /tmp/runner-setup.sh
COPY scripts/runner-setup.d/ /tmp/runner-setup.d/
RUN bash /tmp/runner-setup.sh "$APP_UID" && rm -rf /tmp/runner-setup.sh /tmp/runner-setup.d

USER $APP_UID
EXPOSE 8000
ENTRYPOINT ["busybox", "httpd", "-f", "-p", "8000", "-h", "/app/www"]
