# Tests

This project has **no automated test suite by design**. Infrastructure
correctness is verified by three other mechanisms instead:

| Mechanism | What it checks | Where |
|---|---|---|
| `terraform validate` + `terraform plan` on every PR | config is well-formed and the plan is what we expect | `.github/workflows/terraform-plan.yml` |
| `tfsec` (HIGH gate) + OPA / Conftest policy on every PR | security and tagging rules hold | `.github/workflows/terraform-plan.yml`, `policy/terraform.rego` |
| `terraform plan -detailed-exitcode` nightly | live infrastructure still matches the code (drift) | `.github/workflows/drift.yml` |

The decision to use **drift detection instead of Terratest** is recorded in
[ADR 0002](../docs/decisions/0002-drift-detection-over-terratest.md): no Go
toolchain to maintain, no per-run AWS cost, and it was the approach taught in
the course.

Application behaviour is exercised manually and with a load test
([`LOADTESTING.md`](../LOADTESTING.md)).

If this project grew, the first tests to add would be Terratest cases that
stand up the `networking` and `security` modules in a throwaway account and
assert on subnet routing and security-group rules.
