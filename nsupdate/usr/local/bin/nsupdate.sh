#!/usr/bin/env bash

if [[ $# -ne 4 && $# -ne 5 ]]; then
    echo "Usage: $0 NSSERVER HOST ZONE TTL [public]" >&2
    exit 1
fi

NSSERVER="$1"
HOST="$2"
ZONE="$3"
TTL="$4"
PUBLIC="$5"
FQDN="${HOST}.${ZONE}"
QUERYFILE=$(mktemp)

is_private_ipv4() {
	local ip="$1"
	[[ "$ip" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] || return 1

	case "$ip" in
		10.*|192.168.*)
			return 0
			;;
		172.1[6-9].*|172.2[0-9].*|172.3[0-1].*)
			return 0
			;;
		169.254.*) # link-local
			return 0
			;;
		100.6[4-9].*|100.[7-9][0-9].*|100.1[0-1][0-9].*|100.12[0-7].*)
			return 0 # CGNAT 100.64.0.0/10
		;;
	esac

	return 1
}

is_private_ipv6() {
	local ip="${1,,}" # lowercase

	[[ "$ip" == *:* ]] || return 1

	case "$ip" in
		fc*|fd*)
			return 0 # ULA fc00::/7
			;;
		fe8*|fe9*|fea*|feb*)
			return 0 # link-local fe80::/10
			;;
	esac

	return 1
}

update(){
{
		echo "server $NSSERVER"
		echo "zone $ZONE"

		# Remove the current entries for this hostname
		echo "update delete $FQDN A"
		echo "update delete $FQDN AAAA"

		# Add all IPv4 for this hostname
		for ip in "$@"; do
			if [[ "$ip" != *:* && "$ip" != 127.* ]]; then
				if [[ -z "$PUBLIC" ]]; then
					echo "update add $FQDN $TTL A $ip"
				elif ! is_private_ipv4 $ip; then
					echo "update add $FQDN $TTL A $ip" 
				fi
			elif [[ "$ip" == *:* && "$ip" != ::1 && "$ip" != fe80::* ]]; then
				if [[ -z "$PUBLIC" ]]; then
					echo "update add $FQDN $TTL AAAA $ip"
				elif ! is_private_ipv6 $ip; then
					echo "update add $FQDN $TTL AAAA $ip"
				fi
			fi
		done

		echo "send"
	} | nsupdate -k /etc/tsig.key
}

cleanup(){
	rm -r ${QUERYFILE}
}

while true; do
	IPS=$(hostname -I)
	if [[ "$IPS" != "$(cat ${QUERYFILE})"  ]]; then
		echo "There's updates ( $IPS)"
		echo "$IPS" > ${QUERYFILE}
		update $IPS
	fi
	sleep $TTL
done

