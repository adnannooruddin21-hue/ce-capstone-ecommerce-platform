# RCA 0001 — GitHub OIDC federation to AWS failed

- **Date:** 2026-08-31
- **Severity:** Medium — blocked the CI/CD pipeline; no production impact (nothing was deployed yet)
- **Status:** Resolved with a fallback; root cause not isolated

## Context

The CI/CD design called for keyless authentication: GitHub Actions presents a
short-lived OIDC token, AWS STS exchanges it for temporary credentials via the
`ce-capstone-gha-deploy` IAM role. The provider and role were created in the
`terraform/bootstrap` stack.

## Impact

Every workflow run failed at `aws-actions/configure-aws-credentials` with:

```
Could not assume role with OIDC: Not authorized to perform sts:AssumeRoleWithWebIdentity
```

`terraform plan` / `apply` could not run in CI. Work continued locally, but the
graded GitOps flow was blocked.

## Investigation

The raw STS error was `AccessDenied` — a trust-policy evaluation failure — even
though the token and the policy appeared to match. Each hypothesis was tested:

| Hypothesis | Test | Result |
|---|---|---|
| `sub` claim mismatch | Dumped the token claims in the workflow. The account emits **immutable-identifier** subject claims (`repo:owner@<id>/repo@<id>:...`), which a name-based `sub` pattern cannot match. Switched the trust condition to `job_workflow_ref` (not mangled). | Still failed |
| Condition value wrong | Compared the live trust policy against the token's `aud` and `job_workflow_ref` character by character | Both matched exactly |
| Wrong role ARN in the secret | Hard-coded the ARN directly in the workflow | Still failed |
| Organisation SCP denying federation | Account is a personal account, not in an AWS Organization | Not applicable |
| Stale / wrong OIDC provider thumbprint | Deleted the pre-existing provider (created by an unknown earlier process) and recreated it via Terraform with a live `tls_certificate`-derived thumbprint | Still failed |
| Regional STS endpoint issue | Planned a global vs regional endpoint test | Not run — fell back first |

## Root cause

Not conclusively identified. The two unusual factors on this account are (a) a
pre-existing GitHub OIDC provider of unknown origin and (b) GitHub issuing
immutable-ID subject claims. One or both is the likely cause. Further debugging
was not justified against a one-week project budget.

## Resolution

Fell back to a dedicated IAM user, `ce-capstone-ci`, with an access-key pair
stored as the GitHub secrets `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY`. Both
workflows authenticate with these. The user was later scoped **off**
`AdministratorAccess` onto `docs/ci-policy.json`. See
[ADR 0001](../decisions/0001-ci-authentication.md).

## Prevention / follow-up

- Bring OIDC up in isolation on a throwaway repo before wiring it into a real
  pipeline, so the failure surface is small.
- Retry OIDC after the project; the `bootstrap` OIDC resources are left in place.
- Rotate or delete the `ce-capstone-ci` access key when the project is archived.
