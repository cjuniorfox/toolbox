#!/usr/bin/env bash

if [[ ! -f /usr/local/sbin/snid ]]; then
	curl 'https://github.com/AGWA/snid/releases/download/v0.4.0/snid-v0.4.0-linux-amd64' -Lo /usr/local/sbin/snid && chmod +x /usr/local/sbin/snid
fi

# Get the public IPv6
while read -r ip; do
	if [[ "$ip" == \2* && "$ip" == *":"* ]]; then
		PUBLIC_IP="$ip"
	fi
done <<< "$(hostname -I | tr ' ' '\n')"

# Extract the /64 for the IP
count=0
net_parts=()
while read -r part; do
	net_parts+=("$part")

	(( count++ ))
	if (( count >= 4 )); then
		break
	fi
done <<< $(echo "$PUBLIC_IP" | tr ':' '\n');	
# Add the reverse NAT46 network to be used
net_parts+=("4646::")
arr=("a" "b" "c")

IFS=':'
NAT46_PREFIX="${net_parts[*]}"

echo "NAT46 prefix to be used: $NAT46_PREFIX"

if [[ -z "$BACKEND_CIDR" ]]; then
	echo 'Define BACKEND_CIDR first. This is the backend CIDR for your network. Can be the ISP prefix. Ex: 2001:bd8:1234::/48'
	exit 1
fi
cat << EOF > /etc/systemd/system/snid.service
[Unit]
Description=SNI TLS Proxy Daemon
After=network-online.target

[Service]
ExecStartPre=/usr/bin/sh -c '/usr/sbin/ip route add local ${NAT46_PREFIX}/96 dev lo || exit 0'
ExecStart=/usr/local/sbin/snid -listen tcp:0.0.0.0:443 -mode nat46 -nat46-prefix ${NAT46_PREFIX} -backend-cidr ${BACKEND_CIDR}
ExecStopPost=/usr/bin/sh -c '/usr/sbin/ip route del local ${NAT46_PREFIX}/96 dev lo || exit 0'
Restart=always

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now snid.service
