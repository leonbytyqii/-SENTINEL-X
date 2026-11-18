#!/bin/bash
export JAVA_HOME=/usr/share/wazuh-indexer/jdk
export PATH=$JAVA_HOME/bin:$PATH
TOOLS=/usr/share/wazuh-indexer/plugins/opensearch-security/tools
DEFAULTS=/usr/share/wazuh-indexer/opensearch-security
CERTS=/usr/share/wazuh-indexer/certs

# Copy our internal_users.yml on top of the defaults
cp /usr/share/wazuh-indexer/plugins/opensearch-security/securityconfig/internal_users.yml \
   ${DEFAULTS}/internal_users.yml

echo "Running securityadmin with full default config set..."
${TOOLS}/securityadmin.sh \
  -cd ${DEFAULTS}/ \
  -icl -nhnv \
  -cacert ${CERTS}/root-ca.pem \
  -cert ${CERTS}/admin.pem \
  -key ${CERTS}/admin.key \
  -h 127.0.0.1

echo "securityadmin exit code: $?"
