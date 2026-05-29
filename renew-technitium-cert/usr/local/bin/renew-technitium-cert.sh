#!/bin/bash
set -e

DOMAIN="ns3.lnar.net"
CERT_DIR="/etc/dns/certs"
PASS="plzChangeME!"

# Renew certificate
/root/.acme.sh/acme.sh \
  --home /root/.acme.sh \
  --renew -d "$DOMAIN" \
  --standalone

# Generate PFX
openssl pkcs12 -export \
  -out "$CERT_DIR/technitium.pfx" \
  -inkey "$CERT_DIR/key.pem" \
  -in "$CERT_DIR/fullchain.pem" \
  -passout pass:${PASS}

# Permissions
chown dns-server:dns-server "$CERT_DIR/technitium.pfx"
chmod 640 "$CERT_DIR/technitium.pfx"

# Restart Technitium
systemctl restart dns
