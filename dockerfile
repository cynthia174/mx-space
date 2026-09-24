FROM node:22-alpine AS builder
ENV MONGOMS_DISABLE_POSTINSTALL=1
ENV REDISMS_DISABLE_POSTINSTALL=1
WORKDIR /app
COPY . .
RUN apk add git make g++ alpine-sdk python3 py3-pip unzip
RUN corepack enable
RUN corepack prepare --activate
RUN pnpm install
RUN pnpm bundle
RUN mv apps/core/out ./out
RUN node apps/core/download-latest-admin-assets.js

FROM node:22-alpine AS runner

ARG SOURCE_COMMIT=unknown
LABEL org.opencontainers.image.revision=$SOURCE_COMMIT
LABEL org.opencontainers.image.version="v10.5.3-local"
ENV MX_SOURCE_COMMIT=$SOURCE_COMMIT

RUN apk add zip unzip mongodb-tools bash fish rsync jq curl openrc --no-cache

WORKDIR /app
COPY --from=builder /app/out .
COPY --from=builder /app/assets ./assets

RUN npm i sharp -g
RUN npm i sharp

COPY --chmod=755 docker-entrypoint.sh .
RUN sed -i 's/\r$//' docker-entrypoint.sh

ENV TZ=Asia/Shanghai

EXPOSE 2333

ENTRYPOINT [ "./docker-entrypoint.sh" ]
