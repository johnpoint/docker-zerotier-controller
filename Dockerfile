FROM node:current-alpine as build-stage
LABEL Author="sbilly <superli_1980@hotmail.com>"
LABEL Maintainer="sbilly <superli_1980@hotmail.com>"

ENV NODE_OPTIONS=--openssl-legacy-provider
ENV YARN_VERSION=2.4.0
# ENV ZEROTIER_ONE_VERSION=`curl --silent "https://api.github.com/repos/zerotier/ZeroTierOne/releases" | jq -r ".[0].tag_name"`
ENV ZEROTIER_ONE_VERSION=1.6.6
    

RUN apk update && \
    apk add python3 alpine-sdk gcc wget git linux-headers libpq libpq-dev postgresql-dev bash jq

WORKDIR /src

# Prepaire Environment
COPY ./patch /src/patch
COPY ./config /src/config

# Downloading and build latest libpqxx
RUN LIBPQXX_VERSION=`curl --silent "https://api.github.com/repos/jtv/libpqxx/releases" | jq -r ".[0].tag_name"` && \
    curl https://codeload.github.com/jtv/libpqxx/tar.gz/refs/tags/${LIBPQXX_VERSION} --output /tmp/libpqxx.tar.gz && \
    mkdir -p /src && \
    cd /src && \
    tar fxz /tmp/libpqxx.tar.gz && \
    mv /src/libpqxx-* /src/libpqxx && \
    rm -rf /tmp/libpqxx.tar.gz && \
    cd /src/libpqxx && \
    /src/libpqxx/configure --disable-documentation && \
    make && \
    make install

# Downloading and build latest version ZeroTierOne
RUN curl https://codeload.github.com/zerotier/ZeroTierOne/tar.gz/refs/tags/${ZEROTIER_ONE_VERSION} --output /tmp/ZeroTierOne.tar.gz && \
    mkdir -p /src && \
    cd /src && \
    tar fxz /tmp/ZeroTierOne.tar.gz && \
    mv /src/ZeroTierOne-* /src/ZeroTierOne && \
    rm -rf /tmp/ZeroTierOne.tar.gz && \
    python3 /src/patch/patch.py && \
    cd /src/ZeroTierOne && \
    make CPPFLAGS+=-w && \
    cd /src/ZeroTierOne/attic/world && \
    bash build.sh

# Downloading and build latest tagged zero-ui
# `curl --silent "https://api.github.com/repos/key-networks/ztncui/tags" | jq -r '.[0].name'` && \
#    curl https://codeload.github.com/key-networks/ztncui/tar.gz/refs/tags/${ZERO_UI_VERSION} --output /tmp/zero-ui.tar.gz && \
RUN curl https://codeload.github.com/dec0dOS/zero-ui/tar.gz/refs/tags/v1.0.21 --output /tmp/zero-ui.tar.gz && \
    mkdir -p /src/ && \
    cd /src && \
    tar fxz /tmp/zero-ui.tar.gz && \
    mv /src/zero-ui-* /src/zero-ui && \
    rm -rf /tmp/zero-ui.tar.gz && \
    cd /src/zero-ui && \
    yarn set version ${YARN_VERSION} && \
    yarn install && \
    yarn installDeps && \
    yarn build

FROM node:current-alpine

WORKDIR /app/ZeroTierOne

# libpqxx
COPY --from=build-stage /usr/local/lib/libpqxx.la /usr/local/lib/libpqxx.la
COPY --from=build-stage /usr/local/lib/libpqxx.a /usr/local/lib/libpqxx.a

# ZeroTierOne
COPY --from=build-stage /src/ZeroTierOne/zerotier-one /app/ZeroTierOne/zerotier-one
RUN cd /app/ZeroTierOne && \
    ln -s zerotier-one zerotier-cli && \
    ln -s zerotier-one zerotier-idtool

# mkworld @ ZeroTierOne
COPY --from=build-stage /src/ZeroTierOne/attic/world/mkworld /app/ZeroTierOne/mkworld
COPY --from=build-stage /src/ZeroTierOne/attic/world/world.bin /app/config/world.bin
COPY --from=build-stage /src/config/world.c /app/config/world.c

# Envirment
RUN apk update && \
    apk add libpq postgresql-dev postgresql jq curl bash wget && \
    mkdir -p /var/lib/zerotier-one/ && \
    ln -s /app/config/authtoken.secret /var/lib/zerotier-one/authtoken.secret

# Installing s6-overlay
RUN wget https://github.com/just-containers/s6-overlay/releases/download/v2.2.0.3/s6-overlay-amd64.tar.gz -O /tmp/s6-overlay-amd64.tar.gz && \
    gunzip -c /tmp/s6-overlay-amd64.tar.gz | tar -xf - -C / && \
    rm -rf /tmp/s6-overlay-amd64.tar.gz

# Frontend @ zero-ui
COPY --from=build-stage /src/zero-ui/frontend/build /app/frontend/build/

# Backend @ zero-ui
WORKDIR /app/backend
COPY --from=build-stage /src/zero-ui/backend/package*.json /app/backend
COPY --from=build-stage /src/zero-ui/backend/yarn.lock /app/backend
RUN yarn set version ${YARN_VERSION} && \
    yarn install && \
    ln -s /app/config/world.bin /app/frontend/build/static/planet
COPY --from=build-stage /src/zero-ui/backend /app/backend

# s6-overlay
COPY ./s6-files/etc /etc/

# schema
COPY ./schema /app/schema/

EXPOSE 3000 4000 9993 9993/UDP
ENV S6_KEEP_ENV=1

ENTRYPOINT ["/init"]
CMD []
