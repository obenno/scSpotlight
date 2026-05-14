# syntax=docker/dockerfile:1.3-labs

#############################################
# Dockerfile to build scSpotlight container #
#############################################

ARG PIXI_VERSION=0.65.0

FROM ghcr.io/prefix-dev/pixi:${PIXI_VERSION} AS build

## Maintainer
MAINTAINER oben <obennoname@gmail.com>

WORKDIR /app

## Copy pixi files first for better caching.
COPY pixi.toml pixi.lock ./

## Materialize the dev environment for JS builds and the prod environment for runtime.
RUN pixi install --locked -e default
RUN pixi install --locked -e prod

## Copy repo from host into the container
COPY . .

## Build bundled frontend assets, then install the R package into the prod env.
RUN pixi run -e default npm ci
RUN pixi run -e default npm run build
RUN pixi run -e prod setup-r

## Generate a runtime activation entrypoint so Pixi is not needed in the final image.
RUN pixi shell-hook -e prod -s bash > /shell-hook
RUN printf '#!/usr/bin/env bash\n' > /app/entrypoint.sh && \
    cat /shell-hook >> /app/entrypoint.sh && \
    printf '\nexec "$@"\n' >> /app/entrypoint.sh

FROM ubuntu:24.04 AS production

WORKDIR /app

COPY --from=build /app/.pixi/envs/prod /app/.pixi/envs/prod
COPY --from=build --chmod=0755 /app/entrypoint.sh /app/entrypoint.sh

## Follow Dockstore's guide
## Use existing ubuntu user (UID 1000 in Ubuntu 24.04) or create one
RUN if ! id -u ubuntu >/dev/null 2>&1; then \
        groupadd -r -g 1001 ubuntu && useradd -m -r -g ubuntu -u 1001 ubuntu; \
    fi
RUN chown -R ubuntu:ubuntu /app
USER ubuntu

# expose port
EXPOSE 8081

ENTRYPOINT ["/app/entrypoint.sh"]

## Run the installed R package inside the activated prod environment.
CMD ["Rscript", "-e", "scSpotlight::run_app(options = list(port = 8081, host = '0.0.0.0', launch.browser = FALSE), runningMode = 'analysis')"]
