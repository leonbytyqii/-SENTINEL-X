#!/bin/sh
# Create /var/ossec/etc/shared/ structure needed by wazuh-analysisd.
# This directory is not on a persistent volume and must be created before
# the 2-manager init script runs wazuh-analysisd -t.
set -e
mkdir -p /var/ossec/etc/shared/default
touch /var/ossec/etc/shared/ar.conf
chown -R wazuh:wazuh /var/ossec/etc/shared 2>/dev/null || true
