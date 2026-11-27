# GordonQuant EC2 infrastructure

The service stack owns one persistent private Amazon Linux 2023 minimal ARM64 instance
and a Launch Template. Both deploy an exact GordonQuant Git tag during
cloud-init. The optional ELB stack creates a public Application Load Balancer
and a separate two-instance Auto Scaling Group from that template. Each
instance builds the selected release locally, health checks `/healthz`, and
runs it with Docker's `unless-stopped` restart policy.

The minimal Amazon Linux image does not include the SSM agent, so cloud-init
installs `amazon-ssm-agent` explicitly before enabling Session Manager.

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
terragrunt output -raw service_dns_url
$(terragrunt output -raw ssm_start_session_command)
```

The service stack creates `dev.gordonquant.app` in the public Route 53 hosted
zone, with an `A` record containing the persistent instance's private VPC
address. The name is therefore reachable only from the VPC or through
WireGuard; DNS does not expose the service to the public internet. On the
persistent instance, Docker binds the application's port 5000 to localhost and
Nginx proxies standard HTTP and HTTPS traffic to it. Certbot uses a Route 53
DNS challenge to obtain and automatically renew the certificate, and HTTP is
redirected to `https://dev.gordonquant.app`.

During first boot, cloud-init polls DNS for up to 15 minutes and does not run
Certbot until `dev.gordonquant.app` resolves to that instance's private IP.
This handles the interval between EC2 becoming `running` and Terraform creating
or updating the Route 53 record. Terraform updates the record automatically
whenever the persistent instance is replaced.

By default Certbot registers without an email address. To receive Let's Encrypt
account and expiry notices, set `certificate_email` in
`environments/prod/service/terragrunt.hcl` before applying.

Create the optional public ALB, HTTPS DNS route, and its separate two-instance
ASG only when a public link is needed:

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
cd ~/Work/GordonQuantInfra
make gordonquant-service-check
```

This waits up to 15 minutes for the persistent instance to register with SSM,
waits for cloud-init, and checks the SSM agent, Docker service, container logs,
deployed tag, and `/healthz` endpoint. Open an interactive session separately:

```bash
make gordonquant-service-session
```

The equivalent commands inside the instance are:

```bash
sudo docker ps
sudo docker logs --tail 100 gordonquant
sudo cat /opt/gordonquant/deployed-tag
curl --fail http://127.0.0.1:5000/healthz
sudo systemctl status nginx certbot-renew.timer --no-pager
sudo certbot certificates
```

## Optional public load balancer

The `prod/elb` stack depends on outputs from `prod/service`. It creates an
internet-facing Application Load Balancer with HTTPS on port 443 and an Auto
Scaling Group with `min_size = 2`, `desired_capacity = 2`, and `max_size = 2`. These are two
additional GordonQuant instances; the persistent private service instance is
not registered with the ALB and remains owned by `prod/service`. The ASG
instances are registered on the configured service port and checked at
`/healthz`. The EC2 security group permits traffic only from the VPC CIDR,
while the ALB security group sends application traffic only into that VPC. The
container's internal port 5000 is not opened
directly to the internet.

The stack looks up the public Route 53 hosted zone for `gordonquant.app`,
requests an ACM certificate covering both `*.gordonquant.app` and the apex
`gordonquant.app`, and creates the DNS validation records. It creates an alias
`A` record from `gordonquant.app` to the ALB. HTTP port 80 redirects to HTTPS;
the application remains HTTP on port 5000 between the ALB and EC2 instances.
The certificate must include the apex explicitly because a wildcard certificate
does not cover `gordonquant.app` itself.

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

The default `public_ingress_cidrs = ["0.0.0.0/0"]` makes HTTPS public. To share
the application with only specific people, replace it with their public
`/32` CIDRs before planning. Open `https://gordonquant.app` after the apply;
requests to `http://gordonquant.app` are redirected to HTTPS.

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
