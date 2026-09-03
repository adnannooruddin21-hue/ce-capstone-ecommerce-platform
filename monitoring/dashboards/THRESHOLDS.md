# Dashboard thresholds — `ce-capstone-overview`

Every gauge on the dashboard uses the same traffic-light scale: **green = healthy**,
**amber = attention**, **red = critical**. The values are chosen from the
application and infrastructure reality, not arbitrary round numbers, and they line
up with the CloudWatch alarms where one exists.

| Panel | Section | Green (Healthy) | Amber (Attention) | Red (Critical) | Why these values |
|---|---|---|---|---|---|
| **Overall System Health** | 01 | `0` issues | `1` issue | `≥ 2` issues | Count of the panels below that are at their alarm level. One transient blip = attention; two at once = a real incident. |
| **Application Availability** | 01 | `≥ 99 %` | `95–99 %` | `< 95 %` | Successful (2xx) responses ÷ total. A storefront below 99% success is losing customers; below 95% is an outage. |
| **Error Rate** | 01 | `< 1 %` | `1–5 %` | `> 5 %` | (4xx + 5xx) ÷ total requests. Matches the intent of the `alb-5xx-high` alarm — a few percent is noise, above 5% something is broken. |
| **Response Time (P95)** | 01 | `< 500 ms` | `500–1500 ms` | `> 1500 ms` | 1500 ms is exactly the `latency-p95-high` alarm threshold. Under 500 ms feels instant; over 1.5 s users notice. |
| **Server CPU Usage** | 03 | `< 60 %` | `60–85 %` | `> 85 %` | The auto-scaling target is 50%. 60–85% means scaling is working; above 85% scaling can't keep up (matches `asg-cpu-high` at 75% average). |
| **Server Memory Usage** | 03 | `< 70 %` | `70–90 %` | `> 90 %` | Leaves headroom for request spikes; above 90% risks the OOM killer on a `t3.micro`. |
| **Disk Usage** | 03 | `< 70 %` | `70–90 %` | `> 90 %` | 8 GB root volume. Above 90% and logging / writes start failing. |
| **Database CPU Usage** | 05 | `< 60 %` | `60–85 %` | `> 85 %` | `db.t3.micro` is burstable — sustained CPU above 85% exhausts CPU credits and the database throttles. |
| **Database Storage Used** | 05 | `< 75 %` | `75–90 %` | `> 90 %` | Derived from `FreeStorageSpace` against the 20 GiB allocated. Above 90% and writes can fail. |
| **Monthly Spend** | 01 / 08 | `< $1` | `$1–$10` | `> $10` | Free-Tier target is $0. AWS Budgets alert at $1 / $5 / $10; $10 is the hard ceiling. |

## Notes

- Gauges use `annotations.horizontal` with `fill: "above"` to paint the coloured
  bands; the needle position communicates status without the viewer reading a
  number.
- **Availability, Error Rate, Response Time, Database Storage Used** and
  **Overall System Health** are CloudWatch **metric-math expressions** over live
  metrics — no data is fabricated. When there is no traffic, availability shows
  100% and error rate 0% by design (`IF(requests > 0, …, default)`).
- The **billing** panels query **us-east-1** because `AWS/Billing EstimatedCharges`
  is only published there.
- The alarm tiles in section 01 ("Live Alerts") are the authoritative health
  signal — the Overall System Health gauge is an at-a-glance approximation of the
  same five conditions on a single period.
