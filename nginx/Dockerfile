FROM node:24.11-alpine AS frontend-builder

ENV PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD=1
ENV PNPM_HOME="/pnpm"
ENV PATH="$PNPM_HOME:$PATH"

ARG PNPM_VERSION=10.24.0

RUN npm i -g corepack@latest \
    && corepack enable \
    && corepack prepare "pnpm@${PNPM_VERSION}" --activate

ARG URL_PREFIX=""

RUN pnpm add -g nx

WORKDIR /app

COPY ./bublik-ui/package.json ./bublik-ui/pnpm-lock.yaml ./

RUN --mount=type=cache,id=pnpm,target=/pnpm/store pnpm install --frozen-lockfile

COPY ./bublik-ui ./

# Regenerate the frontend's git-info.json, which is otherwise a stale committed file
# refreshed only by the release-it `after:bump` hook (tools/get-git-info.ts). Same
# shape, so frontend-version.ts needs no change. Build args are exposed to RUN as
# environment variables, so node reads them via process.env and no commit summary
# ever passes through shell quoting. Without args, the committed file is kept.
ARG BUBLIK_UI_REPO_BRANCH=""
ARG BUBLIK_UI_REPO_TAG=""
ARG BUBLIK_UI_COMMIT_REV=""
ARG BUBLIK_UI_COMMIT_DATE=""
ARG BUBLIK_UI_COMMIT_SUMMARY=""
RUN if [ -n "$BUBLIK_UI_COMMIT_REV" ]; then \
      node -e "const f='libs/bublik/features/deploy-info/src/lib/git-info.json'; \
        const e=process.env; \
        require('fs').writeFileSync(f, JSON.stringify({ \
          date: (e.BUBLIK_UI_COMMIT_DATE||'').slice(0,10).replace(/-/g,'.'), \
          summary: e.BUBLIK_UI_COMMIT_SUMMARY||'', \
          revision: e.BUBLIK_UI_COMMIT_REV||'', \
          branch: e.BUBLIK_UI_REPO_BRANCH||'', \
          latestTag: e.BUBLIK_UI_REPO_TAG||'' \
        })); console.log('git-info.json:', require('fs').readFileSync(f,'utf8'));"; \
    fi

ARG SOURCE_MAP=""

RUN BASE_URL="$URL_PREFIX/v2" \
    nx run bublik:build \
    --base="$URL_PREFIX/v2" \
    ${SOURCE_MAP:+--sourcemap=true}

FROM nginx:1.27-alpine

COPY --from=frontend-builder /app/dist/apps/bublik /app/bublik-ui

RUN rm /etc/nginx/conf.d/default.conf

# The upload endpoint's body limit, which the templates read. The compose files
# set it from .env; a deployment that does not (a Helm chart made from an older
# compose file, say) still gets a valid config instead of nginx refusing to start.
ENV BUBLIK_UPLOAD_MAX_BODY=2g
