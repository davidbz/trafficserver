FROM ubuntu:19.04 AS mitm-compile-time

# Build & Runtime args
ARG BUILD_THREADS=10

# APT non-interactive
ENV DEBIAN_FRONTEND=noninteractive

ARG BUILD_DEPS="\
    autoconf \
    build-essential \
    libtool \
    m4 \
    automake \
    libssl-dev \
    tcl-dev \
    libpcre3-dev \
    devscripts \
    git \
    debhelper \
    pkg-config \
    dh-autoreconf \
    libcap-dev \
"

RUN apt-get update && apt-get install -y ${BUILD_DEPS}

# Download naive mitm source code
RUN cd /tmp/ && \
    git clone --single-branch --branch naive_mitm https://github.com/davidbz/trafficserver && \
    cd /tmp/trafficserver && \
    autoreconf -if && \
    ./configure --enable-experimental-plugins --enable-layout=Debian --with-user=david --with-group=david && \
    make -j ${BUILD_THREADS}

FROM ubuntu:19.04 AS mitm-runtime

# User details
ARG AS_USER=david
ARG AS_GROUP=david
ARG AS_USER_ID=1000
ARG AS_GROUP_ID=1000

# APT non-interactive
ENV DEBIAN_FRONTEND=noninteractive

# Create non-root user
RUN addgroup $AS_GROUP --gid $AS_GROUP_ID
RUN useradd --gid $AS_GROUP --uid $AS_USER_ID --no-create-home $AS_USER

COPY --from=mitm-compile-time /tmp/trafficserver /tmp/trafficserver
ARG RUNTIME_DEPS="\
    m4 \
    tcl-dev \
    libpcre3-dev \
    libcap-dev \
    ca-certificates \
    build-essential \
    libssl-dev \
"

RUN apt-get update && apt-get install -y --no-install-recommends ${RUNTIME_DEPS}

# Deploy
RUN cd /tmp/trafficserver && \
    make install && \
    ldconfig

# Cleanups
RUN rm -rf /tmp/*
RUN apt-get purge -y build-essential && apt-get autoremove -y


# Enable Healthcheck
RUN echo "healthchecks.so /etc/trafficserver/healthcheck.config" >> /etc/trafficserver/plugin.config && \
    echo "OK" > /etc/trafficserver/ts-alive && \
    echo "/_hc /etc/trafficserver/ts-alive text/plain 200 403" > /etc/trafficserver/healthcheck.config

# Enable MITM
RUN echo "mitm.so" >> /etc/trafficserver/plugin.config

# Preparte Certifier
RUN mkdir -p /var/cache/trafficserver/certifier/certs
RUN echo "1234323267\n1234567343\n1234567233" >> /var/cache/trafficserver/certifier/ca-serial.txt
RUN chown -R ${AS_USER}:${AS_GROUP} /var/cache/trafficserver/certifier

# Enable Certifier
RUN echo "certifier.so --store=/var/cache/trafficserver/certifier/certs --max=10000 --sign-cert=/var/cache/trafficserver/certifier/root-ca.pem --sign-key=/var/cache/trafficserver/certifier/root-ca-key.pem --sign-serial=/var/cache/trafficserver/certifier/ca-serial.txt" >> /etc/trafficserver/plugin.config

RUN date -u +"%s" > /etc/timestamp

ENTRYPOINT ["/usr/bin/traffic_server"]

