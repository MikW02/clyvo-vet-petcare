#!/usr/bin/env bash
# ============================================================================
# Clyvo-vet PetCare — Azure deployment
# ----------------------------------------------------------------------------
# Provisions a Linux VM on Azure, opens the application + database ports,
# installs Docker + tooling via cloud-init, then deploys the Oracle and
# application containers on it.
#
# Run once, end-to-end, with a single command:
#
#     ./scripts/azure-deploy.sh
#
# Override any default with an environment variable, e.g.:
#
#     LOCATION=eastus VM_SIZE=Standard_D2as_v5 ./scripts/azure-deploy.sh
#
# Tear everything down with:
#
#     ./scripts/azure-destroy.sh
# ============================================================================

set -euo pipefail

# ---- Configuration ---------------------------------------------------------
RG_NAME="${RG_NAME:-rg-clyvo-vet}"
LOCATION="${LOCATION:-brazilsouth}"
VM_NAME="${VM_NAME:-vm-clyvo-vet}"
VM_SIZE="${VM_SIZE:-Standard_B2s}"
ADMIN_USER="${ADMIN_USER:-clyvoadmin}"
IMAGE="${IMAGE:-Ubuntu2204}"
APP_PORT="${APP_PORT:-8080}"
DB_PORT="${DB_PORT:-1521}"
NSG_NAME="${NSG_NAME:-${VM_NAME}NSG}"

ORACLE_PASSWORD="${ORACLE_PASSWORD:-oracle123}"
APP_USER="${APP_USER:-clyvo}"
APP_USER_PASSWORD="${APP_USER_PASSWORD:-clyvo123}"

REPO_URL="${REPO_URL:-https://github.com/your-org/clyvo-vet-petcare.git}"

# ---- Pre-flight ------------------------------------------------------------
command -v az >/dev/null || { echo "az CLI not found"; exit 1; }
az account show >/dev/null || { echo "Run 'az login' first"; exit 1; }

# ---- cloud-init: installs docker + tooling before our SSH bootstrap runs ---
CLOUD_INIT="$(mktemp)"
cat > "$CLOUD_INIT" <<'YAML'
#cloud-config
package_update: true
package_upgrade: false
packages:
  - git
  - nano
  - curl
  - ca-certificates
  - gnupg
  - lsb-release
  - jq
runcmd:
  - install -m 0755 -d /etc/apt/keyrings
  - curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
  - chmod a+r /etc/apt/keyrings/docker.gpg
  - echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo $VERSION_CODENAME) stable" > /etc/apt/sources.list.d/docker.list
  - apt-get update -y
  - DEBIAN_FRONTEND=noninteractive apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin
  - systemctl enable --now docker
  - usermod -aG docker CLYVO_ADMIN_USER
  - touch /var/log/clyvo-cloudinit.done
YAML
sed -i "s/CLYVO_ADMIN_USER/${ADMIN_USER}/g" "$CLOUD_INIT"

# ---- Resource group + VM ---------------------------------------------------
echo "==> Creating resource group $RG_NAME in $LOCATION"
az group create --name "$RG_NAME" --location "$LOCATION" --output none

echo "==> Creating VM $VM_NAME ($VM_SIZE, $IMAGE)"
az vm create \
    --resource-group "$RG_NAME" \
    --name "$VM_NAME" \
    --image "$IMAGE" \
    --size "$VM_SIZE" \
    --admin-username "$ADMIN_USER" \
    --generate-ssh-keys \
    --public-ip-sku Standard \
    --custom-data "$CLOUD_INIT" \
    --output none

PUBLIC_IP="$(az vm show -d -g "$RG_NAME" -n "$VM_NAME" --query publicIps -o tsv)"
echo "    Public IP: $PUBLIC_IP"

# ---- Network: open app + DB ports -----------------------------------------
echo "==> Opening ports $APP_PORT (app) and $DB_PORT (Oracle)"
az network nsg rule create \
    --resource-group "$RG_NAME" --nsg-name "$NSG_NAME" \
    --name allow-app --priority 1010 \
    --destination-port-ranges "$APP_PORT" --access Allow --protocol Tcp \
    --output none

az network nsg rule create \
    --resource-group "$RG_NAME" --nsg-name "$NSG_NAME" \
    --name allow-oracle --priority 1020 \
    --destination-port-ranges "$DB_PORT" --access Allow --protocol Tcp \
    --output none

# ---- Wait for cloud-init to finish (docker installed) ----------------------
echo "==> Waiting for cloud-init to finish on the VM (Docker install)"
az vm run-command invoke \
    --resource-group "$RG_NAME" --name "$VM_NAME" \
    --command-id RunShellScript \
    --scripts "cloud-init status --wait" \
    --output none

# ---- Deploy containers on the VM ------------------------------------------
echo "==> Cloning repo and starting containers on the VM"
REMOTE_SCRIPT=$(cat <<EOF
set -euo pipefail
sudo -u ${ADMIN_USER} bash -lc '
    cd ~
    if [ ! -d clyvo-vet-petcare ]; then
        git clone ${REPO_URL} clyvo-vet-petcare
    fi
    cd clyvo-vet-petcare

    docker network inspect clyvo-net  >/dev/null 2>&1 || docker network create clyvo-net
    docker volume  inspect clyvo-oracle-data >/dev/null 2>&1 || docker volume create clyvo-oracle-data

    docker rm -f clyvo-petcare clyvo-oracle 2>/dev/null || true

    docker build -t clyvo/oracle:local  ./oracle
    docker build -t clyvo/petcare:local ./app

    docker run -d --name clyvo-oracle \
        --network clyvo-net -p ${DB_PORT}:1521 \
        --shm-size=2g \
        -e ORACLE_PASSWORD=${ORACLE_PASSWORD} \
        -e APP_USER=${APP_USER} \
        -e APP_USER_PASSWORD=${APP_USER_PASSWORD} \
        -v clyvo-oracle-data:/opt/oracle/oradata \
        clyvo/oracle:local

    echo "Waiting for Oracle to become healthy..."
    until [ "\$(docker inspect -f {{.State.Health.Status}} clyvo-oracle 2>/dev/null)" = "healthy" ]; do
        sleep 5
    done

    docker run -d --name clyvo-petcare \
        --network clyvo-net -p ${APP_PORT}:8080 \
        -e DB_URL="jdbc:oracle:thin:@clyvo-oracle:1521/XEPDB1" \
        -e DB_USER=${APP_USER} \
        -e DB_PASSWORD=${APP_USER_PASSWORD} \
        clyvo/petcare:local
'
EOF
)

az vm run-command invoke \
    --resource-group "$RG_NAME" --name "$VM_NAME" \
    --command-id RunShellScript \
    --scripts "$REMOTE_SCRIPT" \
    --output table

# ---- Done ------------------------------------------------------------------
rm -f "$CLOUD_INIT"

cat <<EOM

================================================================
Deployment complete.

  Public IP   : $PUBLIC_IP
  API         : http://$PUBLIC_IP:$APP_PORT/api/pets
  Oracle DB   : $PUBLIC_IP:$DB_PORT (service XEPDB1, user $APP_USER)

Quick smoke test from your laptop:

  curl http://$PUBLIC_IP:$APP_PORT/api/pets

  curl -X POST http://$PUBLIC_IP:$APP_PORT/api/pets \\
       -H 'Content-Type: application/json' \\
       -d '{"name":"Thor","species":"dog","breed":"Husky","age":3,"ownerName":"Carla"}'

To tear everything down:

  ./scripts/azure-destroy.sh
================================================================
EOM
