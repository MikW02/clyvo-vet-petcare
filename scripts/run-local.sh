#!/usr/bin/env bash
# Spin up the full Clyvo-vet PetCare stack locally with plain `docker` commands
# (no docker-compose). Idempotent: re-run to rebuild and restart.

set -euo pipefail

NETWORK="clyvo-net"
VOLUME="clyvo-oracle-data"
DB_CONTAINER="clyvo-oracle"
APP_CONTAINER="clyvo-petcare"

# Carrega .env.local se existir (ignorado pelo git) — copie de .env.sample
if [ -f "$(dirname "$0")/../.env.local" ]; then
    set -a; . "$(dirname "$0")/../.env.local"; set +a
fi

: "${ORACLE_PASSWORD:?defina ORACLE_PASSWORD (ex.: copie .env.sample para .env.local e edite)}"
: "${APP_USER_PASSWORD:?defina APP_USER_PASSWORD}"
APP_USER="${APP_USER:-clyvo}"

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

echo "==> Ensuring docker network and named volume exist"
docker network inspect "$NETWORK" >/dev/null 2>&1 || docker network create "$NETWORK"
docker volume inspect "$VOLUME" >/dev/null 2>&1 || docker volume create "$VOLUME"

echo "==> Removing previous containers (if any)"
docker rm -f "$APP_CONTAINER" "$DB_CONTAINER" >/dev/null 2>&1 || true

echo "==> Building Oracle image"
docker build -t clyvo/oracle:local "$ROOT_DIR/oracle"

echo "==> Starting Oracle container (named volume persists /opt/oracle/oradata)"
docker run -d \
    --name "$DB_CONTAINER" \
    --network "$NETWORK" \
    -p 1521:1521 \
    --shm-size=2g \
    -e ORACLE_PASSWORD="$ORACLE_PASSWORD" \
    -e APP_USER="$APP_USER" \
    -e APP_USER_PASSWORD="$APP_USER_PASSWORD" \
    -v "$VOLUME":/opt/oracle/oradata \
    clyvo/oracle:local

echo "==> Waiting for Oracle to report healthy (this can take a couple minutes on first start)"
until [ "$(docker inspect -f '{{.State.Health.Status}}' "$DB_CONTAINER" 2>/dev/null || echo starting)" = "healthy" ]; do
    printf '.'
    sleep 5
done
echo

echo "==> Building application image"
docker build -t clyvo/petcare:local "$ROOT_DIR/app"

echo "==> Starting application container (non-root user inside the image)"
docker run -d \
    --name "$APP_CONTAINER" \
    --network "$NETWORK" \
    -p 8080:8080 \
    -e DB_URL="jdbc:oracle:thin:@$DB_CONTAINER:1521/XEPDB1" \
    -e DB_USER="$APP_USER" \
    -e DB_PASSWORD="$APP_USER_PASSWORD" \
    clyvo/petcare:local

echo
echo "Stack is up:"
echo "  API : http://localhost:8080/api/pets"
echo "  DB  : localhost:1521  (service XEPDB1, user $APP_USER)"
echo
echo "Tail logs with:  docker logs -f $APP_CONTAINER"
