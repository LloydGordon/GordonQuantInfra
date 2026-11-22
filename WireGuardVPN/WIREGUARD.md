# WireGuard operations

This guide covers day-to-day operation of the WireGuard server created by this
repository. The server runs the Amazon Linux 2023 minimal ARM64 AMI and is
administered through AWS Systems Manager Session Manager; SSH is not exposed.
The bootstrap installs the SSM agent because it is not bundled with the minimal
AMI.

## Connect to the server

From the deployed Terragrunt unit:

```bash
cd WireGuardVPN/environments/prod/wireguard
aws ssm start-session \
  --region us-east-1 \
  --target "$(terragrunt output -raw instance_id)"
```

## Verify WireGuard

Run these commands inside the SSM session:

```bash
command -v wg
wg --version
sudo systemctl status wg-quick@wg0
sudo wg show
ip -brief address show wg0
sudo ss -lunp | grep ':51820'
sudo sysctl net.ipv4.ip_forward
```

Expected results:

- `wg` is installed, normally at `/usr/bin/wg`.
- `wg-quick@wg0` is `active (exited)`. This is normal for `wg-quick`.
- Interface `wg0` has the server address `10.8.0.1/24`.
- WireGuard listens on UDP port `51820`.
- `net.ipv4.ip_forward` is `1`.

Use `sudo wg show` to inspect each peer. Once a client connects, it shows the
peer's latest handshake, endpoint, and transfer counters.

## Server files

WireGuard files are stored under `/etc/wireguard`:

| Path | Purpose |
| --- | --- |
| `/etc/wireguard/wg0.conf` | Server interface and peer configuration |
| `/etc/wireguard/server_public.key` | Public key to place in client configurations |
| `/etc/wireguard/server_private.key` | Server secret; never copy, print, or commit it |
| `/etc/sysctl.d/99-wireguard-forwarding.conf` | Enables IPv4 forwarding |

Retrieve only the server public key:

```bash
sudo cat /etc/wireguard/server_public.key
```

The server private key is generated on the instance during first boot and is
not stored in Terraform state.

## Manage the service

```bash
sudo systemctl restart wg-quick@wg0
sudo systemctl stop wg-quick@wg0
sudo systemctl start wg-quick@wg0
sudo systemctl enable wg-quick@wg0
```

After restarting, verify it with:

```bash
sudo systemctl status wg-quick@wg0
sudo wg show
```

## Add a client peer

To install:

```
sudo apt install wireguard-tools
```

Generate the client key pair on the client device, outside this repository:

```bash
mkdir -p ~/.config/wireguard
umask 077
wg genkey \
  | tee ~/.config/wireguard/client.key \
  | wg pubkey \
  > ~/.config/wireguard/client.pub
cat ~/.config/wireguard/client.pub
```

Add only the client public key to the environment's `terragrunt.hcl`:

```hcl
peers = [
  {
    name        = "laptop"
    public_key  = "CLIENT_PUBLIC_KEY"
    allowed_ips = ["10.8.0.2/32"]
  }
]
```

Assign a unique VPN address to every peer. Then run `terragrunt plan` and
`terragrunt apply` from that environment directory.

Peer changes replace the EC2 instance because peer configuration is installed
through user data. Replacement generates a new server key, so update that key
on every client after applying the change. The Elastic IP remains unchanged.

## Client configuration

Get the current endpoint locally:

```bash
terragrunt output -raw wireguard_endpoint
```

The endpoint uses an Elastic IP address, so it remains stable when the EC2
instance is stopped, started, or replaced. AWS charges for the public IPv4
address while it is allocated, including when it is not associated with an
instance.

Create a client configuration such as `~/.config/wireguard/wg0.conf`:

```ini
[Interface]
PrivateKey = CLIENT_PRIVATE_KEY
Address = 10.8.0.2/32
DNS = 1.1.1.1

[Peer]
PublicKey = SERVER_PUBLIC_KEY
Endpoint = PUBLIC_IP:51820
AllowedIPs = 0.0.0.0/0
PersistentKeepalive = 25
```

`AllowedIPs = 0.0.0.0/0` routes all client IPv4 traffic through the VPN. To use
the tunnel only for the VPN network, set it to `10.8.0.0/24` instead.

To route only the WireGuard server and a specific private AWS webserver through
the tunnel, use their `/32` addresses:

```ini
AllowedIPs = 10.8.0.1/32, 172.31.31.229/32
```

### Route the persistent GordonQuant instance

The public ALB handles access to the Auto Scaling Group, so the WireGuard client
only needs a `/32` route for the persistent GordonQuant instance. After applying
the service stack, run this from the repository root:

```bash
make wireguard-gordonquant-sync
```

The target reads the current `private_ip` output from `prod/service`, removes
the previous managed `/32` and the legacy ASG subnet routes, adds only the new
instance `/32`, creates a timestamped backup, and restarts `wg0`. Display the
route without changing the client configuration with:

```bash
make wireguard-gordonquant-routes
```

It uses `/etc/wireguard/wg0.conf` by default. To update the configuration under
the user's home directory instead:

```bash
make wireguard-gordonquant-sync \
  WIREGUARD_CLIENT_CONFIG="$HOME/.config/wireguard/wg0.conf"
```

The target is idempotent and does not print or change private keys. It
deliberately stops if the file contains multiple peer sections, because
choosing which peer to edit would be ambiguous.

Start and stop the client:

```bash
sudo wg-quick up wg0
sudo wg show
sudo wg-quick down wg0
```

## Use WireGuard with NordVPN on Linux

NordVPN can run at the same time as this WireGuard tunnel. NordVPN's Linux
firewall blocks private network traffic by default, so exclude the WireGuard
and AWS destination networks from NordVPN using its allowlist:

```bash
GORDONQUANT_PRIVATE_IP="$(terragrunt --working-dir GordonQuant/environments/prod/service output -raw private_ip)"
nordvpn allowlist add subnet 10.8.0.0/24
nordvpn allowlist add subnet 172.31.31.229/32
nordvpn allowlist add subnet "$GORDONQUANT_PRIVATE_IP/32"
nordvpn settings
```

An allowlisted destination bypasses the NordVPN tunnel. Traffic to the AWS
webserver is still encrypted inside the WireGuard tunnel. There is normally no
need to allowlist the WireGuard server's Elastic IP when `wg show` reports a
successful handshake.

Connect NordVPN first and then start WireGuard so that WireGuard installs its
more-specific AWS routes after NordVPN configures the default route:

```bash
sudo wg-quick down wg0 2>/dev/null || true
nordvpn disconnect
nordvpn connect
sudo wg-quick up wg0
```

Verify that the private destinations use WireGuard and that both VPNs have a
recent handshake:

```bash
ip route get 10.8.0.1
ip route get 172.31.31.229
sudo wg show
```

Both route checks should report `dev wg0`. If NordVPN reconnects and replaces
the routes, restart `wg0`. If its Kill Switch still blocks allowlisted traffic,
temporarily disable the Kill Switch to confirm the cause:

```bash
nordvpn set killswitch off
nordvpn disconnect
nordvpn connect
sudo wg-quick down wg0
sudo wg-quick up wg0
```

Re-enable the Kill Switch after testing if required by your security policy.
To remove the exceptions later:

```bash
nordvpn allowlist remove subnet 10.8.0.0/24
nordvpn allowlist remove subnet 172.31.31.229/32
nordvpn allowlist remove subnet "$GORDONQUANT_PRIVATE_IP/32"
```

## Troubleshooting

If WireGuard was not installed during first boot:

```bash
sudo cloud-init status --long
sudo tail -n 200 /var/log/cloud-init-output.log
```

If the service fails:

```bash
sudo systemctl status wg-quick@wg0 --no-pager
sudo journalctl -u wg-quick@wg0 --no-pager -n 200
sudo wg-quick strip wg0
```

If there is no client handshake, check:

1. The client endpoint matches the current `wireguard_endpoint` output.
2. The client has the current server public key.
3. The server has the client's public key and unique VPN address.
4. The EC2 security group permits UDP `51820` from the client's public address.
5. The existing subnet routes internet traffic through an internet gateway.

If a handshake succeeds but internet traffic does not pass:

```bash
sudo sysctl net.ipv4.ip_forward
sudo iptables -S FORWARD
sudo iptables -t nat -S POSTROUTING
```

## Security notes

- Never commit client or server private keys.
- Only public keys belong in Terragrunt inputs.
- Restrict `wireguard_client_cidrs` when clients have stable public addresses.
- Keep UDP `51820` as the only inbound security-group rule.
- Use SSM Session Manager for administration rather than opening SSH.

Further reading: [WireGuard Quick Start](https://www.wireguard.com/quickstart/)
and [AWS Session Manager](https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager.html).

