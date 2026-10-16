#!/usr/bin/env bash
# ==============================================================================
# Helper Script: Enable Nextcloud User Registration with Admin Approval
# ==============================================================================
# Run this script AFTER Nextcloud child containers have finished starting up.
# ==============================================================================

set -euo pipefail

GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${BLUE}=== Configuring Nextcloud Registration with Admin Approval ===${NC}"

# Check if nextcloud container is running
if ! docker ps --format '{{.Names}}' | grep -q "^nextcloud-aio-nextcloud$"; then
    echo -e "${RED}[ERROR] nextcloud-aio-nextcloud container is not running.${NC}"
    echo -e "Please ensure all containers have been started from the AIO web interface (port 8080) first."
    exit 1
fi

echo -e "${GREEN}[1/3] Installing and enabling 'registration' app...${NC}"
docker exec -u www-data nextcloud-aio-nextcloud php occ app:install registration || \
docker exec -u www-data nextcloud-aio-nextcloud php occ app:enable registration

echo -e "${GREEN}[2/3] Configuring admin approval requirement...${NC}"
docker exec -u www-data nextcloud-aio-nextcloud php occ config:app:set registration admin_approval_required --value=yes

echo -e "${GREEN}[3/3] Optimizing registration settings (allowing instant signup without SMTP)...${NC}"
docker exec -u www-data nextcloud-aio-nextcloud php occ config:app:set registration disable_email_verification --value=yes
docker exec -u www-data nextcloud-aio-nextcloud php occ config:app:set registration email_is_optional --value=yes
docker exec -u www-data nextcloud-aio-nextcloud php occ config:app:set registration show_fullname --value=yes

echo -e "${GREEN}=== Registration Configured Successfully! ===${NC}"
echo -e "Users can now sign up at: /apps/registration/"
echo -e "Admin approval is required for all new accounts under Administration settings -> Users."
