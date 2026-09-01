# WORKLOG

## Monday - Foundation & Deployment
Done:
- Remote state (S3 + DynamoDB), GitHub OIDC deploy role
- networking: VPC, 2 public + 2 private subnets / 2 AZs, NAT instance + EIP, flow logs
- security: alb/app/db security groups
- compute: launch template (t3.micro), ALB + target group, ASG desired 3 across private subnets
- app: Flask catalog on :8080, /health
- CI/CD: plan-on-PR + apply-on-merge, branch protection on main
- monitoring: overview dashboard
Next (Tue): CloudWatch agent + alarms + SNS, tfsec gate, AWS Config, RDS, auto-scaling policy, Terratest


## Tuesday - Features & Integration  (4 PRs: database, observability, security-scaling, infra-tests)
Done:
- feat/database: RDS db.t3.micro single-AZ, private subnets; DB creds + FLASK_SECRET_KEY in SSM;
  wired into user-data. CloudCart app now serving real catalogue + orders (/api/health -> database ok)
- feat/observability: cloudwatch agent -> /ce-capstone/app log group, mem+disk by ASG;
  one dashboard (ALB, latency p50/95/99, hosts, ASG+RDS CPU); SNS topic + email confirmed;
  4 alarms, each tripped and verified; RUNBOOK.md alarm procedures
- feat/security-scaling: ASG target-tracking @50% CPU + night/morning schedules;
  tfsec gate on PR (HIGH), findings triaged (.tfsec/config.yml);
  AWS Config 7 resource types / 5 rules; Prowler CIS report in docs/
- feat/infra-tests: Terratest networking suite + tests.yml
- CI user scoped off AdministratorAccess (chore/scope-ci)
Next (Wed): load test + rightsizing, COSTS.md, all docs + diagrams, Policy-as-Code, repo polish. FREEZE 6pm.
