#!/usr/bin/env bash
# Delete the entire Clyvo-vet resource group from Azure.
# This removes the VM, disks, network, public IP, NSG — everything.
set -euo pipefail

RG_NAME="${RG_NAME:-rg-clyvo-vet}"

echo "==> Deleting resource group $RG_NAME (this may take a few minutes)"
az group delete --name "$RG_NAME" --yes --no-wait

echo "Delete submitted. Track with:  az group show -n $RG_NAME"
