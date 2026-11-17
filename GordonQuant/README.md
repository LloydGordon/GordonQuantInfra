# GordonQuant EC2 infrastructure

The service stack owns one persistent private Amazon Linux 2023 ARM64 instance
and a Launch Template. Both deploy an exact GordonQuant Git tag during
cloud-init. The optional ELB stack creates a public Application Load Balancer
and a separate two-instance Auto Scaling Group from that template. Each
instance builds the selected release locally, health checks `/healthz`, and
runs it with Docker's `unless-stopped` restart policy.

Changing `git_tag` creates a new Launch Template version. Applying the ELB
stack then performs a rolling replacement while retaining at least one healthy
instance. The GitHub token is read at deployment time from SSM Parameter Store
and is never passed to Terraform or stored in Terraform state.

## Structure

```text
GordonQuant/
├── root.hcl
├── modules/
│   ├── ec2-service/
│   │   ├── main.tf
│   │   ├── outputs.tf
│   │   ├── user_data.sh.tftpl
│   │   ├── variables.tf
│   │   └── versions.tf
│   └── public-alb/
│       ├── main.tf
│       ├── outputs.tf
│       ├── variables.tf
│       └── versions.tf
└── environments/
    └── prod/
        ├── service/
        │   └── terragrunt.hcl
        └── elb/
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

The service stack creates the persistent private GordonQuant instance. Verify
its private URL and connect through SSM with:

```bash
terragrunt output -raw service_url
$(terragrunt output -raw ssm_start_session_command)
```

Create the optional public ALB and its separate two-instance ASG only when a
public link is needed:

```bash
cd ../elb
terragrunt init
terragrunt plan -out=elb.tfplan
terragrunt apply elb.tfplan
terragrunt output -raw public_url
```

To connect to any GordonQuant instance through SSM, list all instance IDs:

```bash
cd ../service
$(terragrunt output -raw ssm_list_instances_command)
aws ssm start-session --region us-east-1 --target INSTANCE_ID
```

Then verify the selected instance:

```bash
sudo docker ps
sudo docker logs --tail 100 gordonquant
sudo cat /opt/gordonquant/deployed-tag
curl --fail http://127.0.0.1:5000/healthz
```

## Optional public load balancer

The `prod/elb` stack depends on outputs from `prod/service`. It creates an
internet-facing Application Load Balancer on port 80 and an Auto Scaling Group
with `min_size = 2`, `desired_capacity = 2`, and `max_size = 2`. These are two
additional GordonQuant instances; the persistent private service instance is
not registered with the ALB and remains owned by `prod/service`. The ASG
instances are registered on port 5000 and checked at `/healthz`. The EC2
security group permits traffic only from the VPC CIDR, while the ALB security
group sends port 5000 traffic only into that VPC. Port 5000 is not opened
directly to the internet.

The ASG has the fixed name `gordonquant-prod-asg`. It intentionally does not
use `name_prefix` or `create_before_destroy`; this prevents failed applies from
leaving multiple uniquely named ASGs running billable duplicate instances.

An Application Load Balancer requires two public subnets in different
availability zones. Production uses the service subnet in `us-east-1c` and
`subnet-0d8e8a3398c5de545` in `us-east-1a`.

Apply the service stack first. It creates or updates both the persistent
private instance and the Launch Template used by the optional public stack:

```bash
cd ~/Work/GordonQuantInfra/GordonQuant/environments/prod/service
terragrunt plan -out=gordonquant-persistent-instance.tfplan
terragrunt apply gordonquant-persistent-instance.tfplan
```

Then plan and apply the public load balancer separately:

```bash
cd ../elb
terragrunt init
terragrunt plan -out=elb.tfplan
terragrunt apply elb.tfplan
terragrunt output -raw public_url
```

The default `public_ingress_cidrs = ["0.0.0.0/0"]` makes HTTP public. To share
the application with only specific people, replace it with their public
`/32` CIDRs before planning. This stack provides HTTP only; add an ACM
certificate and HTTPS listener before sending credentials or sensitive data.

Destroying `prod/elb` removes the load balancer and both ASG instances. It does
not remove the persistent private GordonQuant instance owned by `prod/service`,
so WireGuard and SSM access continue to work. The Launch Template, IAM
resources, and service security group also remain. While the public stack
exists, the ALB and its two additional EC2 instances incur cost even when they
receive little or no traffic.

The resulting EC2 counts are:

- Public ELB stack present: one WireGuard, one persistent GordonQuant, and two
  GordonQuant ASG instances — four EC2 instances total.
- Public ELB stack destroyed: one WireGuard and one persistent GordonQuant —
  two EC2 instances total.

## Access through WireGuard

Port `5000` is allowed only from the VPC CIDR by default. The ASG is reached
through the public ALB, so WireGuard only routes the persistent private
GordonQuant instance:

```bash
cd ~/Work/GordonQuantInfra
make wireguard-gordonquant-sync
```

The target reads the service stack's current `private_ip` output. The resulting
peer routes include the instance-specific address:

```ini
AllowedIPs = 10.8.0.1/32, PERSISTENT_GORDONQUANT_PRIVATE_IP/32
```

The target removes the previous managed `/32` and legacy ASG subnet routes,
creates a timestamped client-config backup, and restarts `wg0`. Run it again
after the service stack replaces the persistent instance. ASG replacements do
not require a WireGuard update.

## Deploy another version

Create and push another tag in GordonQuant and update `git_tag`. Apply the
service stack to replace the persistent private instance and create a new
Launch Template version. If the optional public stack exists, apply it next to
roll the ASG to that version. At least one old ASG instance remains healthy
during the rolling replacement. If a new instance cannot fetch, build, or pass
its health check, it never becomes a healthy ALB target.

## Troubleshooting

If an instance fails to become healthy, connect through SSM and check:

```bash
sudo cloud-init status --long
sudo journalctl -u cloud-final --no-pager -n 200
sudo systemctl status docker amazon-ssm-agent --no-pager
sudo docker ps -a
sudo docker logs --tail 200 gordonquant
```

Amazon Linux 2023 includes `curl-minimal`. The bootstrap intentionally keeps
that package rather than installing the conflicting full `curl` package.

Confirm the configured tag exists remotely and that the SSM parameter contains
a valid GitHub token with repository Contents read access. A customer-managed
KMS key also requires `kms:Decrypt` permission on the EC2 role; the default
AWS-managed SSM key does not require an additional module policy.
