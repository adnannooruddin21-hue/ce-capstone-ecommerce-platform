# 2. Drift detection instead of a Terratest suite

- **Status:** Accepted
- **Date:** 2026-09-01
- **Deciders:** Adnan Nooruddin

## Context

The capstone brief lists ten optional "advanced" items and asks for at least
three. Two were already chosen (Auto Scaling policies, managed database / RDS).
The third slot was initially planned as **Infrastructure Testing** with a
Terratest suite that provisions the networking module in a throwaway VPC and
asserts on its outputs.

Two problems with Terratest here:

- It needs a Go toolchain locally and in CI, which is extra setup for a
  one-week solo project.
- Each run stands up a real VPC + NAT instance for a couple of minutes —
  small cost and a source of orphaned resources if a run is interrupted.

**Infrastructure drift detection** is the other candidate for that slot. It was
covered in the bootcamp, needs no new tooling, and adds no running cost.

## Decision

Drop the Terratest suite. Use a scheduled **drift-detection workflow**
(`.github/workflows/drift.yml`) as the third advanced item.

- Runs `terraform plan -detailed-exitcode` daily (07:00 UTC) and on demand.
- Exit code `2` (a non-empty plan) fails the job, signalling that the live
  infrastructure no longer matches the code.
- Uses the existing `ce-capstone-ci` credentials; no Go, no provisioning, no
  cost.

`tests/terratest/` and `.github/workflows/tests.yml` were removed.

## Consequences

**Positive**

- Zero new tooling or spend.
- Catches out-of-band console changes and provider-side changes to managed
  resources — a realistic operational concern.
- Aligns with what was taught in the course.

**Negative**

- Does not test the modules in isolation or assert on their behaviour the way
  Terratest would; it only compares deployed state to code.
- A noisy provider (attributes that always show a diff) can cause false
  positives; those must be pinned or `lifecycle { ignore_changes }`-ed.

## Alternatives considered

- **Terratest suite** — stronger guarantee, but the tooling and per-run cost
  were not worth it for this project (see Context).
- **`terraform validate` + `tflint` only** — already run on every PR; that is
  static checking, not drift detection, so it does not fill this slot.

## Update — 2026-09-02

The *primary* decision stands: drift detection remains the third advanced item.
But the "no Terratest at all" position was narrowed. Two small module-contract
tests were added under `tests/` (`.github/workflows/terratest.yml`):

- `TestNetworkingModulePlan` — plan only, creates nothing, asserts the VPC CIDR
  and the 2-public / 2-private subnet layout.
- `TestSecurityModuleChainedGroups` — real apply/destroy of a throwaway VPC +
  the security module (both free), asserts the `alb → app → db` ingress chain.

This is not the "provision the whole stack" suite the Context rejected — no NAT
instance, no RDS, runtime measured in seconds. The workflow is deliberately
**not** a required status check so a slow or rate-limited AWS call can never
block a merge. Orphan risk is bounded by `defer terraform.Destroy` and the
`tt-net-*` / `tt-sg-*` naming.
