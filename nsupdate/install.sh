#!/usr/bin/env sh

until [[ $CORRECT == "y" ]]; do
	unset NSSERVER
	unset HOST
	unset DOMAIN
	unset TTL
	unset TSIG_NAME
	unset TSIG_KEY

	until [[ -n "$NSSERVER" ]] ; do
		echo "DNS Name Server: "
		read NSSERVER
	done

	echo "Host Name: (Default ${HOSTNAME})"
	read HOST

	if [ -z "$HOST" ]; then
		HOST="$HOSTNAME"
	fi

	until [[ -n "${DOMAIN}" ]]; do
		echo "Domain: "
		read DOMAIN
	done

	echo "Only public addresses? (Default: No)"
	read PUBLIC

	PUBLIC=${PUBLIC,,}
	PUBLIC="${PUBLIC:0:1}"

	if [[ "$PUBLIC" != "n" && "$PUBLIC" != "" ]]; then
		PUBLIC="public"
	else
		PUBLC=""
	fi

	until [[ $TTL == +([0-9]) ]] ; do
		echo "Time to Live: (Default 3600) "
		read TTL
		if [[ -z "$TTL" ]]; then
			TTL="3600"
		fi
		[[ $TTL == +([0-9]) ]] || echo "Only numbers are allowed."
	done

	until [[ -n "$TSIG_KEY" ]]; do
		unset TSIG_NAME
		unset TSIG_KEY
		echo "TSIG Key name: (Default ${HOST})"
		read TSIG_NAME
		if [[ -z "$TSIG_NAME" ]]; then
			TSIG_NAME="$HOST"
		fi
		echo "TSIG Key value: "
		read -s TSIG_KEY
	done

	echo -e "
Nameserver: ${NSSERVER}
Hostname: ${HOSTNAME}
Domain: ${DOMAIN}
Only Public Addresses: $( [[ -n "$PUBLIC" ]] && echo "yes" || echo "no" )
Time to Live: ${TTL}
TSIG Name: ${TSIG_NAME}
TSIG Key: [secret with length of ${#TSIG_KEY}]
	"
	echo "Everything is correct? (Y/N. Default: N)"
	read CORRECT
	CORRECT=${CORRECT,,}
	CORRECT="${CORRECT:0:1}"
done

cat << EOF > /etc/tsig.key
key "${TSIG_NAME}" {
	algorithm hmac-sha256;
	secret "${TSIG_KEY}";
};
EOF
chmod 600 /etc/tsig.key

curl -Lso /usr/local/bin/nsupdate.sh 'https://github.com/cjuniorfox/toolbox/raw/refs/heads/main/nsupdate/usr/local/bin/nsupdate.sh'
chmod +x /usr/local/bin/nsupdate/sh

curl -Ls 'https://raw.githubusercontent.com/cjuniorfox/toolbox/refs/heads/main/nsupdate/etc/systemd/system/nsupdate.service' | \
	sed \
	-e "s/{{NSSERVER}}/$NSSERVER/g" \
	-e "s/{{HOST}}/$HOST/g" \
	-e "s/{{DOMAIN}}/$DOMAIN/g" \
	-e "s/{{PUBLIC}}/$PUBLIC/g" \
	-e "s/{{TTL}}/$TTL/g" > /etc/systemd/system/nsupdate.service
systemctl daemon-reload
systemctl enable --now nsupdate.service
systemctl status nsupdate.service
