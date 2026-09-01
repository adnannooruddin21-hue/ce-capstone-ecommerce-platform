# Retrospective

## What went well

- **Module structure held up.** Six focused Terraform modules (networking,
  security, compute, data, monitoring, governance) with a thin root that just
  wires them together. Adding RDS on Tuesday was a new module plus three lines
  in `main.tf` — nothing else moved.
- **The GitOps flow was real, not decorative.** Every change after the first
  deploy went through a PR: `fmt` / `validate` / `tflint` / `tfsec` / policy /
  `plan` on the pull request, `apply` on merge, branch protection blocking
  direct pushes. Eight PRs across the week.
- **The security gate earned its place.** `tfsec` blocked an unencrypted SNS
  topic from merging. That is exactly the kind of thing that slips through in a
  rush, and the pipeline stopped it.
- **Free-Tier discipline paid off.** Deliberately choosing a NAT instance,
  single-AZ RDS, AWS-managed KMS keys, SSM over Secrets Manager, and scheduled
  scale-in kept the week's spend at effectively $0 while still demonstrating
  every graded capability.
- **The application makes the infrastructure visible.** The "served by
  instance i-… · eu-north-1b" badge, backed by `/api/infra`, turns "there is a
  load balancer in front of an auto scaling group" into something you can see
  by refreshing the page.

## Challenges faced

### 1. GitHub OIDC federation would not authenticate

Set up the standard OIDC provider + deploy role. `AssumeRoleWithWebIdentity`
returned `AccessDenied` on every run despite a trust policy that provably
matched the token's `aud` and `job_workflow_ref` claims.

**How it was overcome.** Systematically ruled out the `sub` condition (the
account emits immutable-ID subject claims, so switched to `job_workflow_ref`),
the role-ARN secret (hard-coded it), an Org SCP (personal account), and a stale
provider thumbprint (deleted and recreated the provider). Root cause was never
isolated — likely an account-level quirk. Rather than burn more of a one-week
budget, fell back to a dedicated `ce-capstone-ci` IAM user with access keys,
then scoped that user off `AdministratorAccess` during the security pass.
Documented in [ADR 0001](docs/decisions/0001-ci-authentication.md) and
[incident report 0001](docs/incident-reports/0001-oidc-federation-failure.md).

### 2. Integrating a second, differently-shaped project

A separate "CloudCart" project arrived mid-week with its own minimal
infrastructure (single public EC2, Nginx, SSH-based deploy). The temptation was
to adopt it wholesale.

**How it was overcome.** Took only its *application* (a genuinely good Flask
storefront with real cart/order logic) and ran it on this project's
ALB + ASG + private-RDS infrastructure, discarding its Terraform and its
SSH-deploy workflow. That kept the multi-tier / HA / load-balancing capabilities
the rubric rewards. Because the app is multi-file (templates + static), it is
shipped as a Terraform-built S3 bundle that instances pull at boot.

### 3. Small AWS quirks that cost real time

- `db_name = "catalog"` is a reserved word in RDS PostgreSQL — renamed to
  `cloudcart` ([incident report 0003](docs/incident-reports/0003-rds-reserved-word.md)).
- A `terraform plan -out tfplan` artifact had been committed since Day 1;
  `.gitignore` had `*.tfplan` but not the bare filename. Untracked it, fixed the
  ignore, rotated the generated secrets as a precaution
  ([incident report 0002](docs/incident-reports/0002-tfplan-tracked-in-git.md)).
- A local-only Terraform provider lock and the IAM inline-policy 2 KB size
  limit both surfaced and were worked around.

## Technical skills learned

- Terraform module design, `for_each`/`count`, `cidrsubnet()`, `templatefile()`,
  `archive_file`, provider `default_tags`, and remote state with S3 + DynamoDB
  locking.
- GitHub Actions: matrixless pipelines, `pull_request` path filters, OIDC vs
  static credentials, branch protection interacting with required checks.
- CloudWatch: dashboard JSON, metric math for percentiles, the agent config and
  its SSM-parameter delivery, alarm → SNS → email wiring.
- AWS Config: recorder / delivery channel / managed rules, the service-principal
  bucket policy it needs, and scoping it for cost.
- Policy as Code with OPA/Conftest against `terraform show -json`.
- IAM least-privilege in practice — the difference between "scoped by service"
  and "scoped by resource ARN", and how tedious the latter is.
- The AWS Free Tier boundaries in detail (what counts, what does not, the
  public-IPv4 charge).

## Key takeaways

- **Constraints improve design.** "No paid services" forced a NAT instance, a
  single-AZ database, and scheduled scale-in — each of which is a legitimate,
  defensible engineering decision, not just a cost hack.
- **Write the decision when you make it.** The ADRs and incident reports written
  in the moment are far better than anything reconstructed at the end of the
  week.
- **A pipeline is only as good as its gates.** Adding `tfsec` and an OPA policy
  to the PR check turned "I hope this is fine" into "the machine confirmed it".
- **Know when to stop debugging.** The OIDC rabbit hole could have consumed a
  day. A documented fallback plus a follow-up plan was the right call under a
  deadline.

## What I would do differently

- **Get OIDC working first**, on a clean throwaway repo, before wiring it into
  the real pipeline — the failure mode was hard to diagnose because too much was
  changing at once.
- **Add drift detection on Day 1**, not as a Tuesday afterthought.
- **Set `TF_VAR_owner`** properly from the start instead of shipping resources
  tagged `Owner = OWNER`.
- **Give `alarm_email` a default** so the pipeline doesn't need a secret + env
  in three workflow files.
- **Move schema seeding out of user-data** into a one-shot task earlier.

## Future improvements

| Area | Next step |
|---|---|
| TLS | Register a domain, add ACM + an HTTPS listener + HTTP→HTTPS redirect |
| Database HA | Multi-AZ RDS + a read replica for catalogue reads |
| Network HA | NAT Gateway per AZ (`nat_mode = "gateway"`) |
| Delivery | Containerise, push to ECR, `docker run` on the ASG — or move to ECS Fargate |
| Deployment | Blue/green or rolling deploys with automated rollback on alarm |
| CI auth | Solve OIDC federation and retire the access-key user |
| Observability | Distributed tracing (X-Ray / OpenTelemetry), structured JSON logs |
| Security | WAF on the ALB, GuardDuty, CloudTrail + the CIS monitoring alarms, customer-managed KMS keys |
| Cost | 1-year Compute Savings Plan once the workload size settles |
