# Runbook

Operational procedures for the CloudCart platform. Region is `eu-north-1`
throughout. Names: ASG `ce-capstone-asg`, ALB `ce-capstone-alb`, RDS
`ce-capstone-pg`, SNS topic `ce-capstone-alerts`, log group `/ce-capstone/app`.

Get the URL:

```bash
ALB=$(terraform -chdir=terraform output -raw alb_dns_name)
```

## Deploy infrastructure

**First time** — bootstrap the backend once, then deploy:

```bash
cd terraform/bootstrap
terraform init && terraform apply -var "github_repo=adnannooruddin21-hue/ce-capstone-ecommerce-platform"
cd ..
terraform init
export TF_VAR_alarm_email="you@example.com"
terraform apply          # RDS ~8-12 min on first run
aws autoscaling start-instance-refresh --region eu-north-1 \
  --auto-scaling-group-name ce-capstone-asg --preferences '{"MinHealthyPercentage":50}'
```

Confirm the SNS subscription email.

**Ongoing** — do not apply by hand. Open a PR; `terraform-plan` runs the checks;
merge to `main` triggers `terraform-apply`. Verify:

```bash
gh run list --workflow terraform-apply.yml --limit 1
```

## Update the application

1. Edit files under `app/src/`.
2. Open a PR. Terraform re-zips `app/src`, the object hash changes, the launch
   template gets a new version — the plan shows this.
3. Merge. `terraform-apply` updates the launch template.
4. Roll the running fleet onto the new version:

```bash
aws autoscaling start-instance-refresh --region eu-north-1 \
  --auto-scaling-group-name ce-capstone-asg --preferences '{"MinHealthyPercentage":50}'
```

5. Watch it:

```bash
aws autoscaling describe-instance-refreshes --region eu-north-1 \
  --auto-scaling-group-name ce-capstone-asg --query 'InstanceRefreshes[0].[Status,PercentageComplete]'
```

## Monitor system health

| What | Where |
|---|---|
| Dashboard | CloudWatch → Dashboards → `ce-capstone-overview` |
| Live app health | `curl -s "http://$ALB/api/health" \| jq` → `{"status":"ok","database":"ok"}` |
| Which instance served you | `curl -s "http://$ALB/api/infra" \| jq` |
| Target health | EC2 → Target Groups → `ce-capstone-tg` → Targets |
| App logs | `aws logs tail /ce-capstone/app --region eu-north-1 --since 15m --follow` |
| Alarms | `aws cloudwatch describe-alarms --region eu-north-1 --alarm-name-prefix ce-capstone --query 'MetricAlarms[].[AlarmName,StateValue]' --output table` |

## Alarm response

### `ce-capstone-unhealthy-hosts` (unhealthy targets > 0)

1. Target group → Targets: which instance(s), which AZ.
2. `aws ssm start-session --target <instance-id>` (no SSH needed).
3. `sudo systemctl status catalog` and `sudo journalctl -u catalog -n 80`.
4. `tail -n 50 /var/log/catalog/app.log`.
5. Check DB reachability from the box: `nc -vz $DB_HOST 5432` (host is in
   `/etc/catalog.env`).
6. If the instance is unrecoverable, terminate it — the ASG replaces it:
   `aws ec2 terminate-instances --region eu-north-1 --instance-ids <id>`.

### `ce-capstone-alb-5xx-high` (target 5xx > 5/min)

1. Dashboard: is it all instances or one? Is it correlated with a recent merge?
2. `aws logs tail /ce-capstone/app --since 15m --follow` — look for the stack trace.
3. Common cause: RDS unreachable. Check RDS status and the `db-sg` rules.
4. If it correlates with a deploy, revert: open a PR that reverts the merge
   commit, merge it, then instance-refresh.

### `ce-capstone-latency-p95-high` (p95 > 1.5 s)

1. Dashboard: EC2 CPU vs RDS CPU / connections.
2. CPU-bound → confirm the target-tracking policy is scaling out
   (`aws autoscaling describe-scaling-activities --region eu-north-1
   --auto-scaling-group-name ce-capstone-asg`).
3. DB-bound → check `DatabaseConnections`; a `db.t3.micro` saturates around a
   few dozen. Consider a temporary `max_size` bump.

### `ce-capstone-asg-cpu-high` (ASG CPU > 75 %)

Expected under load. Confirm scale-out is happening. If it is pinned at
`max_size = 4`, that is the Free-Tier ceiling — raise `max_size` in
`modules/compute` (or `terraform.tfvars`) and deploy.

## Common troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| New instances never pass health checks | app failed to start | SSM in, `journalctl -u catalog`; usually a missing SSM parameter or `pip install` failed (NAT instance down → no egress) |
| Instances have no internet | NAT instance stopped / `source_dest_check` on / private route wrong | start the NAT instance; confirm the private route table points at its ENI |
| `terraform plan` shows unexpected changes (drift) | out-of-band console change | reconcile: either `terraform apply` to restore, or import/adjust code to match |
| PR merge blocked, "base branch policy prohibits merge" | required `plan` check didn't run (docs-only change) | `gh pr merge --admin` for a genuine docs-only PR |
| `/api/health` shows `database: error` | RDS unavailable or credentials stale | check RDS status; if credentials were rotated, instance-refresh the ASG |

## Backup and recovery

- **Database** — RDS automated backups, 1-day retention, daily snapshot +
  transaction logs. Restore: `aws rds restore-db-instance-to-point-in-time`
  (or from the console) into a new instance, then repoint
  `/ce-capstone/db/host` and instance-refresh.
- **State** — the S3 state bucket has versioning enabled; a bad `apply` can be
  recovered by restoring the previous state object version.
- **Application code** — in git; redeployable from any commit.
- **Infrastructure** — fully reproducible from Terraform (`terraform apply`
  from a clean account after the bootstrap step).

## Scaling procedures

| Need | Action |
|---|---|
| More capacity now | `aws autoscaling set-desired-capacity --region eu-north-1 --auto-scaling-group-name ce-capstone-asg --desired-capacity N` (≤ `max_size`) |
| Raise the ceiling | change `max_size` in `modules/compute` (or `terraform.tfvars`), PR + merge |
| Change the CPU target | edit `aws_autoscaling_policy.cpu_target.target_value`, PR + merge |
| Pause overnight scale-in | remove / adjust `aws_autoscaling_schedule.night_in` and `morning_out` |
| Bigger database | change `instance_class` in `modules/data`; expect a short outage on apply |

## Teardown

```bash
cd terraform && terraform destroy
cd bootstrap && terraform destroy -var "github_repo=adnannooruddin21-hue/ce-capstone-ecommerce-platform"
```

Then sweep the console for: unattached Elastic IPs, orphaned EBS snapshots,
CloudWatch log groups, the AWS Config recorder, and the `ce-capstone-ci` IAM
user + its access key.
