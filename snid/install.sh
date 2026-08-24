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
echo "Create /etc/sysctl.d/10-ipv6-forwarding.conf"
echo "or /usr/sbin/sysctl -w net.ipv6.conf.all.forwarding=1"
cat << EOF > /etc/systemd/system/snid.service
[Unit]
Description=SNI TLS Proxy Daemon
After=network-online.target

[Service]
ExecStartPre=/usr/sbin/ip -6 route replace local fd38:82fc:4248:46:4646::/96 dev lo
# Add this route only if using BGP (frr)
ExecStartPre=/usr/sbin/ip -6 route replace fd38:82fc:4248:46:4646::/96 dev lo
ExecStart=/usr/local/sbin/snid -listen tcp:0.0.0.0:443 -mode nat46 -nat46-prefix fd38:82fc:4248:46:4646:: -backend-cidr 2804:1124:fd00::/40
# Add this route only if using BGP (frr)
ExecStopPost=/usr/sbin/ip -6 route del fd38:82fc:4248:46:4646::/96 dev lo
ExecStopPost=/usr/sbin/ip -6 route del local fd38:82fc:4248:46:4646::/96 dev lo
Restart=always

[Install]
WantedBy=multi-user.target

EOF

systemctl daemon-reload
systemctl enable --now snid.service
