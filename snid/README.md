# Install SNID

## Requirements

- `curl`. If it is not installed, install `curl` first.

## Define environment variables first

The following variables are required for installing `snid`. If it is not configured, configure at least the `BACKEND_CIDR` variable.

- `BACKEND_CIDR`: The backend CIDR that the SNID proxy is allowed to use. If not, this SNID proxy becomes a universal NAT46 proxy, which is not desirable.
- `NAT46_PREFIX`: (Optional) The prefix where the IPv4 prefix will be translated into IPv6. If not configured, the NAT46_PREFIX will be the `/64` prefix from your network, with `:4646::/96`

## Installation

### 1. Define the environment variables:

Do the environment variables configuration before installing.

The `BACKEND_CIDR` is the network where the web service that you want to proxy into lives on.
The `NAT46_PREFIX` is optional.

The values below are only for your example

```shell
export BACKEND_CIDR='2001:db8::/32'
export NAT46_PREFIX='2001:db8:4646::'
```

### 2. Install snid

#### Method 1: install directly.

Install directly by executing the content from curl without persisting any file:

```shell
bash <( curl "https://raw.githubusercontent.com/cjuniorfox/toolbox/refs/heads/main/snid/install.sh")
```

#### Method 2: download and run

Download the file with `wget` and install.

```shell
wget "https://raw.githubusercontent.com/cjuniorfox/toolbox/refs/heads/main/snid/install.sh"
chmod +x install.sh
./install.sh
```
