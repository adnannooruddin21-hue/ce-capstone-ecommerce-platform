# Worklog

## Monday — Foundation & Deployment
Done:
- Remote state (S3 `ce-capstone-tfstate-128529977749` + DynamoDB `ce-capstone-tflock`), GitHub OIDC deploy role
- networking: VPC 10.20.0.0/16, 2 public + 2 private subnets / 2 AZs, NAT instance + EIP, route tables, VPC flow logs
- security: alb / app / db security groups (chained by reference)
- compute: launch template (t3.micro), ALB + target group, ASG desired 3 across private subnets, app shipped as an S3 bundle
- app: CloudCart Flask storefront on :8080, /health + /api/*
- CI/CD: plan-on-PR + apply-on-merge, branch protection on main
- monitoring: overview dashboard (starter)
Issue: GitHub OIDC federation failed → fell back to `ce-capstone-ci` access-key user (ADR 0001, RCA 0001)
Spend: ~$0

## Tuesday — Features & Integration  (4 PRs: database, observability, security-scaling, drift)
Done:
- feat/database: RDS db.t3.micro 16.13 single-AZ, private subnets, storage-encrypted; DB creds + Flask secret in SSM SecureString; wired into user-data. App serving the real catalogue + transactional orders (/api/health → database ok)
- feat/observability: CloudWatch agent → /ce-capstone/app log group, mem+disk by ASG; one dashboard (ALB, latency p50/95/99, host health, EC2 CPU, RDS); SNS topic (encrypted) + email confirmed; 4 alarms, each tripped and verified; RUNBOOK alarm procedures
- feat/security-scaling: ASG target-tracking @ 50% CPU + night/morning schedules; tfsec HIGH gate on PRs (findings fixed or excluded with reasons in .tfsec/config.yml); AWS Config 7 resource types / 5 managed rules + delivery bucket; scoped Prowler CIS 2.0 report in docs/
- feat/drift-detection: scheduled drift workflow as advanced item #3 (Terratest dropped — ADR 0002)
- chore/scope-ci: `ce-capstone-ci` moved off AdministratorAccess onto docs/ci-policy.json
Issues: RDS reserved word `catalog` → renamed `cloudcart` (RCA 0003); tfsec blocked an unencrypted SNS topic on a PR (fixed)
Spend: ~$0

## Wednesday — Optimization & Documentation
Done:
- Optimization: load test with `hey`, latency + scale-out numbers captured; tagging pass; actual per-service spend recorded
- Policy as Code (excellence item): OPA/Conftest policy `policy/terraform.rego` (4 rules) wired into terraform-plan.yml (ADR 0003)
- Security follow-ups: rotated both generated secrets after finding a tracked plan file (RCA 0002); account-level IMDSv2 default + S3 Block Public Access; re-ran Prowler
- 4 architecture diagrams in docs/architecture/ (diagram-as-code, generate.py committed)
- All 6 root docs written: README, ARCHITECTURE, SECURITY, RUNBOOK, COSTS, RETROSPECTIVE
- 3 incident reports in docs/incident-reports/
- monitoring/alerts + monitoring/queries populated
- AWS Config recorder stopped after compliance screenshots captured
- Infrastructure FROZEN at 6 pm
Spend: ~$0

## Thursday — Presentation prep (no infra changes)
- slides.pdf · demo-script.md · backup screen recording · rehearsal ×3 · pre-staged tabs

## Friday — Demo day
- Present · Q&A · finalise RETROSPECTIVE with feedback · `terraform destroy` after
