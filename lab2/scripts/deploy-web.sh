#!/usr/bin/env bash
set -euo pipefail

# This script always runs as VM_SUDO_USER (invoked directly over SSH as
# that user by 06-deploy-web.sh), so no need to source vars.sh — just ask
# who's actually running it.
DEPLOY_USER="$(whoami)"

sudo dnf install -y httpd
echo "<h1>ACS730 — deployed by ${DEPLOY_USER} user</h1>" | sudo tee /var/www/html/index.html
sudo chown "${DEPLOY_USER}:$(id -gn "${DEPLOY_USER}")" /var/www/html/index.html
sudo systemctl start httpd
curl -s localhost | head -3