# Live demo — click path

> Stub. The sequence of screens is fixed below; fill in the spoken talking
> points and exact narration on Thursday. Keep the whole run under ~6 minutes.
> Have `presentation/screenshots/` open in a second window as the fallback if
> anything is slow or broken.

**Before you start:** app URL loaded in one tab, AWS console logged in on the
correct region (eu-north-1), terminal ready in the repo root.

App URL: `http://ce-capstone-alb-2112669035.eu-north-1.elb.amazonaws.com`

---

## 1. The app is real (~45s)
- Open the storefront URL. Show the catalogue loads.
- Bottom-left chip: "served by i-… · eu-north-1a". Point it out.
- Hard-reload two or three times → the instance id / AZ in the chip changes.
  That is the ALB spreading requests across the Auto Scaling Group.
- _Talking point:_ ...

## 2. Load balancing + health (~45s)
- AWS console → EC2 → Target Groups → `ce-capstone-tg` → Targets tab.
- Show 3 registered targets, all Healthy, split across 1a / 1b.
- _Talking point:_ ...

## 3. Self-healing (~60s)
- EC2 → Instances → pick one `ce-capstone-app` → Instance state → Terminate.
- Switch to the Target Group tab, refresh: count drops 3 → 2, one target
  draining/unhealthy.
- ASG → `ce-capstone-asg` → Activity → new "Launching a new EC2 instance…"
  row with an EC2/ELB health-check cause.
- Back to the app URL — still serving the whole time (other instances covered).
- _Talking point:_ ...

## 4. Observability (~60s)
- CloudWatch → Dashboards → `ce-capstone-overview`. Walk the 6 widgets; point
  at the load-test spike in ALB requests / latency.
- CloudWatch → Alarms → show the 4 custom alarms + conditions.
- Show the SNS alarm email in the inbox.
- _Talking point:_ ...

## 5. IaC + CI/CD (~75s)
- GitHub → the repo → Actions → open the latest `plan` run: fmt, validate,
  tfsec, Conftest, plan — all green.
- Settings → Branches → show the protection rule on `main` (required `plan`
  check).
- Optional: `git log --oneline` in the terminal — one squash-merge per PR.
- _Talking point:_ ...

## 6. Security + cost (~45s)
- Systems Manager → Parameter Store → show `/ce-capstone/db/password` and
  `/ce-capstone/app/secret_key` are SecureString.
- EC2 → Security Groups → `ce-capstone-app-…` → inbound is 8080 from the ALB
  SG only.
- Billing → Free Tier → 0 of 9 offers over the limit.
- _Talking point:_ ...

## Close (~30s)
- One sentence on the biggest trade-off (NAT instance / single-AZ RDS) and its
  production path.
- One sentence on what you'd do next.

---

## If the live demo breaks
Fall back to the matching screenshot in `presentation/screenshots/` and narrate
from it. Mapping: §1 → 01/02, §2 → 06, §3 → 18, §4 → 03/04/05, §5 → 12/15,
§6 → 17/10/16.
