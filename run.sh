#!/bin/bash

set -e

CURRENT_DIR=$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )
JOBS=$(cat /proc/cpuinfo | awk '/^processor/{print $3}' | wc -l)
TAG=davidbz/mitmproxy:1.0
PUBLIC_KEY_PATH=""
PRIVATE_KEY_PATH=""

while [[ $# -gt 0 ]]
do
key="$1"

case $key in
    -j|--jobs)
    JOBS="$2"
    shift # past argument
    shift # past value
    ;;
    -t|--tag)
    TAG="$2"
    shift
    shift
    ;;
    -p|--public)
    PUBLIC_KEY_PATH="$2"
    shift
    shift
    ;;
    -k|--key)
    PRIVATE_KEY_PATH="$2"
    shift
    shift
    ;;
esac
done

if [ ! -f "${PUBLIC_KEY_PATH}" ]; then
    echo "Please provide a valid path to ROOT CA public key"
    exit 1
fi

if [ ! -f "${PRIVATE_KEY_PATH}" ]; then
    echo "Please provide a valid path to ROOT CA private key"
    exit 2
fi

echo "Building ${TAG}"
docker build --build-arg BUILD_THREADS=${JOBS} -t ${TAG} ${CURRENT_DIR}/

#-v /home/fireglass/development/ats_bluecoat/trafficserver/configs/records.config.default.in:/etc/trafficserver/records.config \
echo "Running ${TAG}"
docker run --rm -it \
    -p 8080:8080 \
    -v ${PUBLIC_KEY_PATH}:/var/cache/trafficserver/certifier/root-ca.pem:ro \
    -v ${PRIVATE_KEY_PATH}:/var/cache/trafficserver/certifier/root-ca-key.pem:ro \
    --ulimit nofile=131072:131072 \
    --sysctl net.core.somaxconn=8192 \
    ${TAG}
