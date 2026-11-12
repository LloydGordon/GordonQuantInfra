# GordonQuant EC2 infrastructure

This Terragrunt stack runs an exact GordonQuant Git tag in Docker on an Amazon
Linux 2023 ARM64 EC2 instance. The selected release is fetched from the private
GitHub repository by an SSM Association, built locally, health checked through
`/healthz`, and started with Docker's `unless-stopped` restart policy.

Changing only `git_tag` redeploys the container without replacing EC2. The
GitHub token is read at deployment time from SSM Parameter Store and is never
passed to Terraform or stored in Terraform state.

## Structure

```text
GordonQuant/
├── root.hcl
├── modules/
│   └── ec2-service/
│       ├── main.tf
│       ├── outputs.tf
│       ├── user_data.sh.tftpl
│       ├── variables.tf
│       └── versions.tf
└── environments/
    └── prod/
        └── service/
            └── terragrunt.hcl
```

## One-time GitHub token setup

Create a fine-grained GitHub personal access token that can read the contents
of only `LloydGordon/GordonQuant`. Store it as a SecureString before the first
apply. Do not put the token in Terragrunt inputs or commit it.

```bash
read -rsp "GitHub token: " GORDONQUANT_GITHUB_TOKEN
echo
aws ssm put-parameter \
  --region us-east-1 \
  --name /gordonquant/github-token \
  --type SecureString \
  --value "$GORDONQUANT_GITHUB_TOKEN" \
  --overwrite
unset GORDONQUANT_GITHUB_TOKEN
```

## Create and select a release tag

The tag must exist in the GordonQuant GitHub repository before deployment:

```bash
cd ~/Work/GordonQuant
git tag -a v0.1.0 -m "GordonQuant v0.1.0"
git push origin v0.1.0
```

Set that exact value in `environments/prod/service/terragrunt.hcl`:

```hcl
git_tag = "v0.1.0"
```

## Plan and apply

Only the operator applies infrastructure changes:

```bash
cd ~/Work/GordonQuantInfra/GordonQuant/environments/prod/service
export AWS_ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
terragrunt init
terragrunt plan -out=gordonquant.tfplan
terragrunt apply gordonquant.tfplan
```

After applying, inspect the private endpoint and connect through SSM:

```bash
terragrunt output -raw service_url
terragrunt output -raw ssm_start_session_command
```

Run the command returned by the second output, then verify the deployment:

```bash
sudo docker ps
sudo docker logs --tail 100 gordonquant
sudo cat /opt/gordonquant/deployed-tag
curl --fail http://127.0.0.1:5000/healthz
```

## Access through WireGuard

Port `5000` is allowed only from the VPC CIDR by default. Retrieve the service's
private IP and add it to the laptop's WireGuard `AllowedIPs`:

```bash
terragrunt output -raw private_ip
```

For example, if the output is `172.31.20.10`:

```ini
AllowedIPs = 10.8.0.1/32, 172.31.20.10/32
```

Restart the client and open `http://172.31.20.10:5000`. Traffic forwarded by
the WireGuard EC2 instance is NATed to its VPC address, which the service
security group accepts.

## Deploy another version

Create and push another tag in GordonQuant, update `git_tag`, then create and
apply a new Terragrunt plan. The SSM Association fetches and deploys that tag on
the existing instance. If fetching or building the new release fails, the
currently running container is left in place. If the new container fails its
health check, the deployment script attempts to restart the previous image.

## Troubleshooting

If the association fails, connect through SSM and check:

```bash
sudo cloud-init status --long
sudo journalctl -u cloud-final --no-pager -n 200
sudo systemctl status docker amazon-ssm-agent --no-pager
sudo docker ps -a
sudo docker logs --tail 200 gordonquant
```

Confirm the configured tag exists remotely and that the SSM parameter contains
a valid GitHub token with repository Contents read access. A customer-managed
KMS key also requires `kms:Decrypt` permission on the EC2 role; the default
AWS-managed SSM key does not require an additional module policy.
