# Cost analysis

## Headline

The platform was built and run for a full week inside the **AWS Free Tier**.
Month-to-date unblended spend: **≈ $0.00** (a few millionths of a dollar of
data-transfer and EC2-Other, net of Free-Tier credits).

The design brief could have been met with a NAT Gateway, Multi-AZ RDS, managed
KMS keys, and Secrets Manager — that configuration would run roughly
**$70–90/month**. Every one of those was consciously swapped for a Free-Tier
equivalent.

## Month-to-date breakdown by service

Source: `aws ce get-cost-and-usage` grouped by SERVICE, current month.

| Service | Cost | Free-Tier basis |
|---|---|---|
| EC2 – Compute (app + NAT instances) | $0.00 | 750 hrs/mo of `t3.micro`; 4 instances × ~a week ≈ 480 hrs, under the cap |
| EC2 – Other (EBS, public IPv4) | ~$0.000002 | 30 GB EBS free; public IPv4 addresses ($0.005/hr) are the only structural charge — ALB nodes + NAT ≈ $0.015/hr |
| Elastic Load Balancing | ~$0.00000002 | 750 hrs/mo + 15 GB processing free |
| RDS | ~$0.00 (net credit) | 750 hrs/mo `db.t3.micro` single-AZ + 20 GB storage free |
| S3 (state, artifacts, config buckets) | ~$0.000000002 | 5 GB free; total data < 100 MB |
| DynamoDB (state lock) | $0.00 | 25 GB + 25 RCU/WCU always free; table is kilobytes |
| CloudWatch (1 dashboard, 4 alarms, logs) | $0.00 | 3 dashboards / 10 alarms / 5 GB logs always free; agent metrics kept ≤ 10 custom |
| SNS | $0.00 | 1,000 email notifications/mo free |
| AWS Config | $0.00 so far | **Not Free-Tier** — recorder scoped to 7 resource types and stopped after evidence capture; expected < $2 total |
| Data Transfer | ~$0.000002 | 100 GB/mo out free |
| KMS | $0.00 | only AWS-managed keys (`aws/ssm`, `aws/sns`) — no $1/key/month customer keys |
| Secrets Manager | $0.00 | **not used** — SSM Parameter Store SecureString instead |
| **Total** | **≈ $0.00** | |

## Cost-allocation strategy (tags)

Every Terraform-managed resource is tagged through the provider
`default_tags` block:

```hcl
default_tags {
  tags = {
    Project     = "ce-capstone"
    Environment = "prod"
    Owner       = "<set via TF_VAR_owner>"
    ManagedBy   = "terraform"
  }
}
```

`Project = ce-capstone` is the cost-allocation key. It is what the scoped
Prowler scan and any Cost Explorer filter use to isolate this project's spend
from the rest of the account.

> Note: `Owner` is currently the placeholder `OWNER`; set `TF_VAR_owner` (or the
> `owner` variable default) to a real value before the next apply.

## Optimisation strategies applied

| # | Optimisation | Saving vs the "obvious" build |
|---|---|---|
| 1 | **NAT instance instead of NAT Gateway** — one `t3.micro` using free instance-hours | ~$32/month + per-GB data-processing charges |
| 2 | **Single-AZ RDS** instead of Multi-AZ | ~50 % of the RDS bill (~$13–15/mo at `db.t3.micro` on-demand) |
| 3 | **Scheduled scale-in overnight** — ASG drops to 1 instance 22:00–06:00 UTC | ~40 % of app instance-hours |
| 4 | **`gp3` volumes** instead of `gp2` | ~20 % on storage, plus baseline 3,000 IOPS at no extra cost |
| 5 | **3-day log retention** on app + flow-log groups instead of never-expire | keeps CloudWatch Logs storage inside the free 5 GB indefinitely |
| 6 | **AWS-managed KMS keys** instead of customer-managed | $1/key/month × 4 keys = $48/year avoided |
| 7 | **SSM Parameter Store** instead of Secrets Manager | $0.40/secret/month × 2 |
| 8 | **AWS Config scoped to 7 resource types** + stopped after evidence | Config bills per configuration item recorded; recording "all supported" continuously would be the largest line on the bill |
| 9 | **`t3.micro`** (Free-Tier type in `eu-north-1`) rather than `t4g`/larger | keeps EC2 at $0 |

## Savings achieved

Rough monthly comparison, on-demand `eu-north-1` pricing:

| Line item | "Obvious" build | This build |
|---|---|---|
| NAT | NAT Gateway ~$32 | NAT instance $0 (free hrs) |
| RDS | Multi-AZ `db.t3.micro` ~$28 | Single-AZ $0 (free hrs) |
| App compute | 3× `t3.small` 24/7 ~$45 | 3× `t3.micro`, scaled-in nights, $0 (free hrs) |
| KMS | 4 customer keys ~$4 | AWS-managed $0 |
| Secrets Manager | 2 secrets ~$1 | SSM $0 |
| **Approx. total** | **~$110/month** | **≈ $0/month** |

## Scaling cost projection (production, out of Free Tier)

If this were run for real — Multi-AZ RDS, a NAT Gateway per AZ, reserved
instances, ACM/HTTPS, larger app instances — a reasonable estimate at low
production traffic:

| Component | Est. $/month |
|---|---|
| ALB (1) + LCU | ~$20 |
| NAT Gateway × 2 AZ + data | ~$70 |
| App: 3× `t3.small` on a 1-yr Compute Savings Plan | ~$30 |
| RDS `db.t3.small` Multi-AZ + storage + backups | ~$60 |
| CloudWatch + Config + logs | ~$15 |
| Data transfer (moderate) | ~$10 |
| **Total** | **~$200–230/month** |

### Reserved-instance / Savings Plan recommendation

- App EC2 and RDS are steady-state → a **1-year Compute Savings Plan** (no
  upfront) cuts the compute lines ~30 %, or an RDS Reserved Instance for the
  database specifically (~35 %).
- Do **not** reserve capacity while it is Free-Tier eligible or while the
  workload size is still changing.

## Budget alerts configured

An **AWS Budget** with email notifications at **$1 / $5 / $10** month-to-date
was created on Day 1, before the first `terraform apply` — the cheapest possible
insurance against a runaway resource. Actual spend never approached the first
threshold.

## What is *not* free (structural charges to watch)

- **Public IPv4 addresses** — $0.005/hr each since Feb 2024. The ALB (2 nodes)
  and NAT instance carry one each ≈ $0.015/hr ≈ **$11/month** if left running
  24/7. Destroying the stack when idle avoids it.
- **AWS Config** — bills per configuration item; the toggle keeps it off
  outside evidence-gathering windows.
