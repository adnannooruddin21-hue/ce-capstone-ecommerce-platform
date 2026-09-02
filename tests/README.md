# Tests

Infrastructure correctness is verified by four mechanisms:

| Mechanism | What it checks | Where |
|---|---|---|
| `terraform validate` + `terraform plan` on every PR | config is well-formed and the plan is what we expect | `.github/workflows/terraform-plan.yml` |
| `tfsec` (HIGH gate) + OPA / Conftest policy on every PR | security and tagging rules hold | `.github/workflows/terraform-plan.yml`, `policy/terraform.rego` |
| **Terratest module-contract tests** | key modules build the shape we claim | this directory, `.github/workflows/terratest.yml` |
| `terraform plan -detailed-exitcode` nightly | live infrastructure still matches the code (drift) | `.github/workflows/drift.yml` |

Drift detection is the **primary** check (see
[ADR 0002](../docs/decisions/0002-drift-detection-over-terratest.md)). The two
Terratest cases are a deliberately small supplement for the modules whose
correctness is easiest to get wrong by hand:

| Test | Type | Cost | Asserts |
|---|---|---|---|
| `TestNetworkingModulePlan` | plan only — creates nothing | $0 | VPC CIDR is `10.20.0.0/16`; two public + two private subnets |
| `TestSecurityModuleChainedGroups` | real apply + destroy | $0 (security groups + a VPC are free) | `alb-sg` open on :80; `app-sg` trusts only `alb-sg` on :8080; `db-sg` trusts only `app-sg` on :5432; no raw CIDR ingress on `app-sg` / `db-sg` |

## Running locally

```bash
cd tests
go mod tidy            # first time only — writes go.sum
export AWS_PROFILE=...  # credentials that can read AZs and create VPC/SGs
export AWS_REGION=eu-north-1
go test ./... -v -timeout 25m
```

Run one:

```bash
go test ./... -v -run TestNetworkingModulePlan     # free, no resources
go test ./... -v -run TestSecurityModuleChainedGroups
```

## In CI

`.github/workflows/terratest.yml` runs on demand, on PRs that touch
`terraform/modules/**` or `tests/**`, and nightly at 06:30 UTC. It is **not** a
required status check — it talks to real AWS and must never block a merge. Each
test tags its resources with a `tt-net-*` / `tt-sg-*` name and always destroys;
if a run is killed mid-apply, search the console for that prefix and delete.
