# RCA 0002 — Terraform plan file tracked in git

- **Date found:** 2026-09-01
- **Severity:** Medium — potential secret exposure in a public repository; no evidence of actual disclosure
- **Status:** Resolved

## Context

During a repo audit, `terraform/tfplan` was found to be tracked in git. It had
been committed since the first foundation PR (`c6912c1`) because an earlier
`terraform plan -out tfplan` produced a file that a subsequent `git add -A`
staged. The repository is **public**.

## Impact

Terraform plan files, like state files, can contain sensitive resource
attributes in their internal representation. HashiCorp's guidance is to treat
them with the same care as state.

Assessment of what was actually exposed:

- The version of `tfplan` committed on `main` **predates the `data` module**
  (RDS, `random_password`, SSM SecureString parameters) — it contained only a
  public AMI SSM-parameter lookup. No database password or Flask secret.
- `.tfplan` is a zip-based container, so `strings`/`grep` on the file cannot
  reliably confirm the absence of embedded (compressed) secrets. Absence could
  not be proven with certainty for every historical version.

## Root cause

`.gitignore` contained `*.tfplan` but the file was named `tfplan` with **no
extension**, so the pattern never matched it. The runbook step that generated it
used `-out tfplan` (no extension).

## Resolution

1. `git rm --cached terraform/tfplan` and deleted the working copy.
2. Added `tfplan` and `plan.out` (bare names) to `.gitignore` alongside
   `*.tfplan`.
3. **Rotated both generated secrets** as a precaution:
   `terraform apply -replace=module.data.random_password.db
   -replace=module.data.random_password.app_secret`, followed by an ASG instance
   refresh so instances picked up the new values from SSM.
4. Verified `/api/health` returned `database: ok` after the refresh.

Git history was **not** rewritten — the committed versions contain no secrets,
and the exposed generated credentials have been rotated and are now useless.

## Prevention / follow-up

- CI generates plan files as `plan.out` and never `git add`s them; both names
  are now ignored.
- The Conftest / OPA policy and `tfsec` gate remain; neither would have caught
  this (it is a git-hygiene issue, not an IaC issue) — the fix is the
  `.gitignore` pattern and awareness.
- Consider a pre-commit hook or `gitleaks` in CI to catch state/plan artifacts
  and secret patterns before they are committed.
