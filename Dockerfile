###########################################
#         Base Python Image              #
###########################################
FROM python:3.12-slim AS base

ENV PYTHONDONTWRITEBYTECODE=1
ENV PYTHONUNBUFFERED=1
ENV PATH="/app/te/build/inst/default/bin:$PATH"

WORKDIR /app

RUN apt-get update \
  && apt-get install -y --no-install-recommends \
  gettext=0.21* \
  python3-celery=5.2.6* \
  gosu \
  util-linux \
  rsync=3.2.7* \
  flex=2.6.4* \
  bison=2:3.8.2* \
  ninja-build=1.11* \
  libjansson-dev=2.14* \
  libjansson-doc=2.14* \
  libjansson4=2.14* \
  libpopt-dev=1.19* \
  libpcre3-dev=2:8.39* \
  pixz=1.0.7* \
  libxml-parser-perl=2.46* \
  build-essential=12.9* \
  curl=7.88.1* \
  libkrb5-dev=1.20.1* \
  libffi-dev=3.4.4* \
  libxml2-dev=2.9.14* \
  libyaml-dev=0.2.5* \
  libssl-dev=3.0.15* \
  libglib2.0-dev=2.74.6* \
  git=1:2.39.5* \
  && rm -rf /var/lib/apt/lists/* \
  && cpan -T JSON

# Install UV
ADD https://astral.sh/uv/install.sh /uv-installer.sh
RUN chmod +x /uv-installer.sh && /uv-installer.sh && rm /uv-installer.sh
ENV PATH="/root/.local/bin/:$PATH"
ENV UV_HTTP_TIMEOUT=2400

# Install dependencies using uv pip
RUN uv pip install --system --no-cache-dir meson==1.6.1 watchfiles==1.0.4

RUN mkdir bublik

COPY ./bublik/requirements.txt /app/bublik/requirements.txt
RUN uv pip install --system --no-cache-dir -r /app/bublik/requirements.txt

COPY ./entrypoint-common.sh /app/bublik/entrypoint-common.sh
COPY ./entrypoint-django.sh /app/bublik/entrypoint-django.sh
COPY ./entrypoint-celery.sh /app/bublik/entrypoint-celery.sh
COPY ./entrypoint-logserver.sh /app/bublik/entrypoint-logserver.sh
RUN chmod +x /app/bublik/entrypoint-*.sh

WORKDIR /app/te
COPY ./test-environment .
RUN ./dispatcher.sh -q --conf-builder=builder.conf.tools --no-run

###########################################
#         Documentation Builder          #
###########################################
FROM node:22.13-alpine AS docs-builder

ENV PNPM_HOME="/pnpm"
ENV PATH="$PNPM_HOME:$PATH"
RUN npm i -g corepack@latest
RUN corepack enable

ARG URL_PREFIX
ARG DOCS_URL

WORKDIR /app

COPY ./bublik-release/package.json ./bublik-release/pnpm-lock.yaml ./

RUN --mount=type=cache,id=pnpm,target=/pnpm/store pnpm install --frozen-lockfile

COPY ./bublik-release .

RUN URL="${DOCS_URL}" BASE_URL="${URL_PREFIX}/docs/" pnpm run build

###########################################
#           Bublik Runner               #
###########################################
FROM base AS runner

WORKDIR /app

COPY --from=docs-builder /app/build /app/bublik/docs

COPY ./bublik ./bublik

RUN mkdir -p ./bublik/logs

WORKDIR /app/bublik

###########################################
#           Log Server                    #
###########################################
FROM base AS log-server

RUN apt-get update && apt-get install -y \
    apache2 \
    file \
    jq \
    && rm -rf /var/lib/apt/lists/*

RUN a2enmod cgid

RUN mkdir -p \
    /home/te-logs/cgi-bin \
    /home/te-logs/logs \
    /home/te-logs/incoming \
    /home/te-logs/bad \
    /home/te-logs/bin \
    /app/bublik \
    /app/te-templates \
    && chmod -R 775 /home/te-logs/logs \
    && chmod -R 775 /home/te-logs/incoming \
    && chmod -R 775 /home/te-logs/bad

COPY ./entrypoint-common.sh /app/bublik/entrypoint-common.sh
COPY ./entrypoint-logserver.sh /app/bublik/entrypoint-logserver.sh
RUN chmod +x /app/bublik/entrypoint-*.sh

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
