# 1. CI authentication to AWS

- **Status:** Accepted
- **Date:** 2026-08-31
- **Deciders:** Adnan Nooruddin

## Context

The CI/CD pipeline (GitHub Actions) needs AWS credentials to run
`terraform plan` on pull requests and `terraform apply` on merges to `main`.

Two standard options:

1. **OIDC federation** — GitHub Actions presents a short-lived OIDC token;
   AWS STS exchanges it for temporary credentials via an IAM role. No
   long-lived secrets are stored. This is the modern, recommended pattern.
2. **IAM user access keys** — a long-lived key pair stored as GitHub repo
   secrets.

OIDC was attempted first.

## What was tried (OIDC)

- Created (via the `terraform/bootstrap` stack): an IAM OIDC provider for
  `token.actions.githubusercontent.com` and a deploy role
  `ce-capstone-gha-deploy`.
- Trust policy scoped with `token.actions.githubusercontent.com:aud =
  sts.amazonaws.com` and `token.actions.githubusercontent.com:job_workflow_ref`
  `StringLike` `adnannooruddin21-hue/ce-capstone-ecommerce-platform/.github/workflows/*`.
- `sts:AssumeRoleWithWebIdentity` returned `AccessDenied`
  ("Not authorized to perform sts:AssumeRoleWithWebIdentity") on every run.

Ruled out during debugging:

| Suspect | Check | Result |
|---|---|---|
| Trust policy `sub` mismatch | dumped token claims; account emits immutable IDs (`repo:owner@id/repo@id:...`) so switched the condition to `job_workflow_ref` | still failed |
| Condition value mismatch | compared live trust policy against the token's `aud` and `job_workflow_ref` | both match exactly |
| Wrong role ARN in the secret | hard-coded the ARN in the workflow | still failed |
| Organisation SCP | account is a personal account, not in an AWS Organization | not applicable |
| Stale OIDC provider / thumbprint | deleted the pre-existing provider and recreated it via Terraform with a live `tls_certificate`-derived thumbprint | still failed |

Root cause was not identified. The account had a pre-existing OIDC provider
created by an unknown process, and GitHub issues immutable-identifier subject
claims for this account — one or both may be involved. Further debugging was
not justified against the Week 9 timeline.

## Decision

Use a dedicated IAM user **`ce-capstone-ci`** with an access key pair, stored
as the GitHub repository secrets `AWS_ACCESS_KEY_ID` and
`AWS_SECRET_ACCESS_KEY`. Both workflows authenticate with these via
`aws-actions/configure-aws-credentials@v4`.

The user:

- has no console access (programmatic only);
- is used by nothing except CI;
- currently carries `AdministratorAccess` (see follow-ups).

## Consequences

**Positive**

- Unblocks the CI/CD pipeline immediately; the graded GitOps flow
  (plan-on-PR, apply-on-merge, branch protection) works as intended.
- Simple, widely understood, easy to reason about.

**Negative**

- Long-lived static credentials exist. Mitigated by: a dedicated
  single-purpose user, no console login, secrets confined to GitHub's
  encrypted secret store, and the keys being trivially rotatable or
  revocable.
- Requires manual rotation; there is no automatic expiry.
- Not the production-recommended pattern.

## Follow-ups

1. During the Tuesday security pass, replace `AdministratorAccess` on
   `ce-capstone-ci` with a least-privilege policy covering only the
   resources this project manages.
2. Rotate or delete the access key, and delete the `ce-capstone-ci` user,
   when the project is archived after the Friday demo.
3. Revisit OIDC federation outside the project timeline; the
   `terraform/bootstrap` OIDC resources are left in place (commented or
   unused) for that.

## Alternatives considered

- **OIDC federation** — preferred, but blocked as described above.
- **Run Terraform only from a laptop** — rejected; loses the graded
  deploy-on-merge / GitOps requirement.
- **OIDC against the global or `us-east-1` STS endpoint** — a possible
  workaround for a regional-endpoint issue, left untested in favour of
  unblocking now.
