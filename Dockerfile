# syntax=docker/dockerfile:1

ARG PYTHON_IMAGE=python:3.12-slim-bookworm

FROM ghcr.io/astral-sh/uv:0.12.17 AS uv

###########################################
#   Test Environment tools (builder)      #
###########################################
FROM ${PYTHON_IMAGE} AS te-builder

RUN apt-get update \
  && apt-get install -y --no-install-recommends \
  build-essential \
  bison \
  file \
  flex \
  gawk \
  libglib2.0-dev \
  libjansson-dev \
  libpcre2-dev \
  libpopt-dev \
  libssl-dev \
  libxml2-dev \
  libyaml-dev \
  m4 \
  ninja-build \
  perl \
  pkg-config \
  rsync \
  && rm -rf /var/lib/apt/lists/*

COPY --from=uv /uv /usr/local/bin/uv
RUN uv pip install --system --no-cache-dir meson==1.6.1

WORKDIR /app/te
COPY ./test-environment .
RUN ./dispatcher.sh -q --conf-builder=builder.conf.tools --no-run

# Keep only what is executed at runtime.
RUN set -eux; \
  cd build/inst/default; \
  rm -rf include lib/pkgconfig lib/*.a share/cm; \
  find bin lib -type f -exec sh -c \
    'file -b "$1" | grep -q "^ELF" && strip --strip-unneeded "$1" || true' _ {} \;

###########################################
#   Python dependencies (builder)         #
###########################################
FROM ${PYTHON_IMAGE} AS py-builder

# pykerberos has no wheels and builds against libkrb5.
RUN apt-get update \
  && apt-get install -y --no-install-recommends \
  build-essential \
  libffi-dev \
  libkrb5-dev \
  libssl-dev \
  && rm -rf /var/lib/apt/lists/*

COPY --from=uv /uv /usr/local/bin/uv

ENV UV_PYTHON=/usr/local/bin/python3.12 \
    UV_PYTHON_DOWNLOADS=never \
    UV_LINK_MODE=copy \
    UV_COMPILE_BYTECODE=0 \
    UV_HTTP_TIMEOUT=2400

WORKDIR /app/bublik
COPY ./bublik/requirements.txt ./

# Developer tooling from requirements.txt is not installed into the image.
RUN grep -v -i -E \
    '^(autoflake|coverage|fakeredis|importlab|networkx|ninja|pep517|pip-review|pip-tools|pipdeptree|pre-commit|pytest|pytype|ruff|syrupy)(==|\[|$)' \
    requirements.txt > requirements-runtime.txt

# watchfiles is used by docker-compose.dev.yml.
RUN --mount=type=cache,target=/root/.cache/uv \
    uv venv /opt/venv \
    && uv pip install --python /opt/venv -r requirements-runtime.txt watchfiles==1.0.4

###########################################
#         Documentation
###########################################
FROM node:24.11-alpine AS docs-base

ENV PNPM_HOME="/pnpm"
ENV PATH="$PNPM_HOME:$PATH"

ARG PNPM_VERSION=10.24.0

RUN npm i -g corepack@latest \
    && corepack enable \
    && corepack prepare "pnpm@${PNPM_VERSION}" --activate

WORKDIR /app

COPY ./bublik-release/package.json ./bublik-release/pnpm-lock.yaml ./

RUN pnpm config set registry https://registry.npmjs.org
RUN --mount=type=cache,id=pnpm,target=/pnpm/store pnpm install --frozen-lockfile

COPY ./bublik-release .

FROM docs-base AS docs-builder

ARG URL_PREFIX
ARG DOCS_URL=http://localhost

WORKDIR /app

RUN URL="${DOCS_URL}" BASE_URL="${URL_PREFIX}/docs/" pnpm run build

# Raw image copies made by docusaurus-markdown-source-plugin; the site uses assets/.
RUN rm -rf /app/build/blog/img /app/build/img

###########################################
#   Shared runtime base                   #
###########################################
FROM ${PYTHON_IMAGE} AS runtime-base

ENV PYTHONDONTWRITEBYTECODE=1
ENV PYTHONUNBUFFERED=1
ENV PATH="/app/te/build/inst/default/bin:$PATH"

# Libraries the TE tools link against and tools the entrypoints call.
# Perl serves the legacy log converters (rgt-bublik-json-legacy, xml_log_parser).
RUN apt-get update \
  && apt-get install -y --no-install-recommends \
  curl \
  gosu \
  libglib2.0-0 \
  libjansson4 \
  libjson-perl \
  libpcre2-8-0 \
  libpopt0 \
  libstdc++6 \
  libtimedate-perl \
  libxml-parser-perl \
  libxml2 \
  libyaml-0-2 \
  perl \
  pixz \
  xz-utils \
  && rm -rf /var/lib/apt/lists/* \
  # TE scripts use #!/usr/bin/python3.
  && { [ -e /usr/bin/python3 ] || ln -s /usr/local/bin/python3 /usr/bin/python3; }

WORKDIR /app

COPY --from=te-builder /app/te/build/inst /app/te/build/inst

# Let the TE tools find their own shared libraries.
RUN echo /app/te/build/inst/default/lib > /etc/ld.so.conf.d/te.conf && ldconfig

COPY ./entrypoint-common.sh \
     ./entrypoint-django.sh \
     ./entrypoint-celery.sh \
     ./entrypoint-logserver.sh \
     /app/bublik/
RUN chmod +x /app/bublik/entrypoint-*.sh

###########################################
#           Bublik Runner               #
###########################################
FROM runtime-base AS runner

# libkrb5/libgssapi: pykerberos + gssapi; pango/gdk-pixbuf + fonts: weasyprint.
RUN apt-get update \
  && apt-get install -y --no-install-recommends \
  fonts-dejavu-core \
  fonts-liberation \
  libgdk-pixbuf-2.0-0 \
  libgssapi-krb5-2 \
  libkrb5-3 \
  libpango-1.0-0 \
  libpangocairo-1.0-0 \
  && rm -rf /var/lib/apt/lists/*

# GitPython is imported at startup but git itself is not needed.
ENV VIRTUAL_ENV=/opt/venv \
    PATH="/opt/venv/bin:$PATH" \
    GIT_PYTHON_REFRESH=quiet

COPY --from=py-builder /opt/venv /opt/venv

WORKDIR /app

COPY --from=docs-builder /app/build /app/bublik/docs

COPY ./bublik ./bublik

RUN mkdir -p ./bublik/logs

WORKDIR /app/bublik

# Deploy/version info, captured on the host by scripts/git_version_env.sh and read by
# REPO_REVISIONS in settings.py. The build context has no git (.dockerignore strips
# .git, and submodule .git files point into the superproject), so it must be injected.
# Kept last so a new commit only invalidates this trailing layer.
ARG BUBLIK_REPO_URL=""
ARG BUBLIK_REPO_BRANCH=""
ARG BUBLIK_REPO_TAG=""
ARG BUBLIK_COMMIT_REV=""
ARG BUBLIK_COMMIT_DATE=""
ARG BUBLIK_COMMIT_SUMMARY=""
ARG BUBLIK_BUILD_DATE=""
ENV BUBLIK_REPO_URL=${BUBLIK_REPO_URL} \
    BUBLIK_REPO_BRANCH=${BUBLIK_REPO_BRANCH} \
    BUBLIK_REPO_TAG=${BUBLIK_REPO_TAG} \
    BUBLIK_COMMIT_REV=${BUBLIK_COMMIT_REV} \
    BUBLIK_COMMIT_DATE=${BUBLIK_COMMIT_DATE} \
    BUBLIK_COMMIT_SUMMARY=${BUBLIK_COMMIT_SUMMARY} \
    BUBLIK_BUILD_DATE=${BUBLIK_BUILD_DATE}

###########################################
#           Log Server                    #
###########################################
FROM runtime-base AS log-server

# tshark: rgt-proc-raw-log renders sniffer captures with it.
RUN apt-get update \
  && apt-get install -y --no-install-recommends \
    apache2 \
    file \
    inotify-tools \
    jq \
    tshark \
    && rm -rf /var/lib/apt/lists/*

RUN a2enmod cgid

RUN mkdir -p \
  /home/te-logs/cgi-bin \
  /home/te-logs/logs \
  /home/te-logs/incoming \
  /home/te-logs/bad \
  /home/te-logs/bin \
  /app/te-templates \
  && chmod -R 775 /home/te-logs/logs \
  && chmod -R 775 /home/te-logs/incoming \
  && chmod -R 775 /home/te-logs/bad

COPY ./test-environment/tools/log_server/te-logs-error404.template /app/te-templates/
COPY ./test-environment/tools/log_server/te-logs-index.template /app/te-templates/
COPY ./test-environment/tools/log_server/publish-logs-unpack.sh /app/te-templates/
COPY ./test-environment/tools/log_server/publish-incoming-logs.template /app/te-templates/
COPY ./test-environment/tools/log_server/apache2-te-log-server.conf.template /app/te-templates/

RUN echo "ServerName localhost" >> /etc/apache2/apache2.conf

RUN ln -sf /proc/self/fd/1 /var/log/apache2/access.log && \
  ln -sf /proc/self/fd/2 /var/log/apache2/error.log

RUN sed -i \
  -e 's|ErrorLog ${APACHE_LOG_DIR}/error.log|ErrorLog /proc/self/fd/2|' \
  -e 's|CustomLog ${APACHE_LOG_DIR}/access.log combined|CustomLog /proc/self/fd/1 combined|' \
  /etc/apache2/apache2.conf

RUN mkdir -p /app/te-logs-static && \
  cd /app/te/build/inst/default/share/rgt-format/xml2html-multi && \
  cp -r /app/te/build/inst/default/share/rgt-format/xml2html-multi/images /app/te-logs-static/ && \
  find . -type f -not -path "./images/*" -exec cp {} /app/te-logs-static/ \; && \
  chmod -R 755 /app/te-logs-static

EXPOSE ${BUBLIK_DOCKER_TE_LOG_SERVER_PORT}
ENTRYPOINT ["/app/bublik/entrypoint-logserver.sh"]
