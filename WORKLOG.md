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
Spend so far: $0.0000003777 (Billing console)
