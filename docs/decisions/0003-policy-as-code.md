# 3. Policy as Code with OPA / Conftest

- **Status:** Accepted
- **Date:** 2026-09-01
- **Deciders:** Adnan Nooruddin

## Context

The capstone brief asks for at least one "excellence" item. **Policy as Code**
is on that list. The pipeline already runs `tfsec` (a fixed rule set from a
third party); what is missing is a **project-specific, authored** policy that
encodes *this platform's* rules and fails the build when they are broken.

## Decision

Add an [OPA](https://www.openpolicyagent.org/) / Conftest policy
(`policy/terraform.rego`) evaluated against `terraform show -json` output on
every pull request, as a step in `.github/workflows/terraform-plan.yml`.

Rules enforced:

1. **Every resource carries a `Project` tag** — cost-allocation and ownership.
2. **No security group except the ALB allows `0.0.0.0/0` ingress** — protects
   the tier isolation.
3. **RDS storage must be encrypted** — data-at-rest baseline.
4. **Every S3 bucket must have an `aws_s3_bucket_public_access_block`** — no
   accidental public buckets.

The step runs after `terraform plan -out plan.out` /
`terraform show -json plan.out > plan.json`, using the official
`openpolicyagent/conftest` container. A `deny` message fails the job, which
blocks the merge via branch protection.

## Why Conftest / OPA

| Option | Verdict |
|---|---|
| **Conftest / OPA (Rego)** | Chosen. Open source, no server, runs in one container step, policy is plain files in the repo, evaluates the same plan JSON a human would read. |
| HashiCorp Sentinel | Tied to Terraform Cloud/Enterprise; not available for a CLI + GitHub Actions workflow. |
| Checkov custom policies | Already have `tfsec` for that style of check; a second scanner adds noise. OPA against the *plan* (not the HCL) can assert on computed values `tfsec` cannot see. |
| `terraform-compliance` | BDD-style; heavier dependency, less widely known. |

## Consequences

**Positive**

- A real, authored guardrail specific to this platform, versioned with the code.
- Catches regressions `tfsec` does not (e.g. a new module that forgets tagging,
  or a security group that opens to the world).
- Demonstrates the "shift-left / policy-as-code" pattern end to end.

**Negative**

- Rego has a learning curve.
- The policy asserts on *planned* values; a rule that depends on values only
  known after apply cannot be expressed.
- One more moving part in the PR pipeline (~10 s).

## Alternatives considered

- **Do nothing** — leaves the excellence requirement unmet.
- **A second commercial scanner** — cost / noise for no extra rubric credit.
