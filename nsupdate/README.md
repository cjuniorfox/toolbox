# NSUpdate install script

Install nameserver update for updating dynamically registers on technitium DNS server by using generated TSIG keys

## Parameters

- **NS Server Name**: Technitium DNS Server name
- **Hostname**: Server hostname. Default its own hostname
- **Domain**: Domain name for the server hostname
- **TTL**: Time to Live for the domain
- **Public**: Register only public IP addresses? Default is not

## How to install

```shell
sh <(curl -Ls 'https://raw.githubusercontent.com/cjuniorfox/toolbox/refs/heads/main/nsupdate/install.sh')
```
