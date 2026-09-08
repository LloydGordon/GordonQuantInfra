# WireGuard operations

This guide covers day-to-day operation of the WireGuard server created by this
repository. The server runs Amazon Linux 2023 and is administered through AWS
Systems Manager Session Manager; SSH is not exposed.

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
through user data. Replacement generates a new server key and public IPv4
address, so update both values on every client after applying the change.

## Client configuration

Get the current endpoint locally:

```bash
terragrunt output -raw wireguard_endpoint
```

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

Start and stop the client:

```bash
sudo wg-quick up wg0
sudo wg show
sudo wg-quick down wg0
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

