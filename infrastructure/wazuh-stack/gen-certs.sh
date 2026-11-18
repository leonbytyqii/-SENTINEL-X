#!/bin/sh
set -e
apk add --quiet openssl 2>/dev/null || true

mkdir -p /certs

# Root CA
openssl genrsa -out /certs/root-ca.key 2048 2>/dev/null
openssl req -new -x509 -sha256 -days 3650 \
  -subj "/C=US/L=California/O=Wazuh/OU=Wazuh/CN=root-ca" \
  -key /certs/root-ca.key -out /certs/root-ca.pem 2>/dev/null
echo "Root CA generated"

gen_cert() {
  name=$1
  cn=$2
  openssl genrsa -out /certs/${name}.key 2048 2>/dev/null
  openssl req -new -sha256 \
    -subj "/C=US/L=California/O=Wazuh/OU=Wazuh/CN=${cn}" \
    -key /certs/${name}.key -out /tmp/${name}.csr 2>/dev/null
  printf "subjectAltName=DNS:%s,DNS:localhost,IP:127.0.0.1\n" "${name}" > /tmp/${name}.ext
  openssl x509 -req -sha256 -days 3650 \
    -CA /certs/root-ca.pem -CAkey /certs/root-ca.key -CAcreateserial \
    -extfile /tmp/${name}.ext \
    -in /tmp/${name}.csr -out /certs/${name}.pem 2>/dev/null
  chmod 640 /certs/${name}.key
  echo "Cert generated: ${name} (CN=${cn})"
}

gen_cert "wazuh-indexer"   "wazuh-indexer"
gen_cert "wazuh-dashboard" "wazuh-dashboard"
gen_cert "wazuh-manager"   "wazuh-manager"
gen_cert "admin"           "admin"

echo ""
echo "=== Generated certificates ==="
ls /certs/*.pem /certs/*.key 2>/dev/null
echo "Done."
