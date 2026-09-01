# RUNBOOK

## Alarm response

### ce-capstone-unhealthy-hosts
1. Check the target group health in the EC2 console.
2. SSM into an unhealthy instance: `aws ssm start-session --target <id>`
3. `sudo systemctl status catalog` + `sudo journalctl -u catalog -n80`
4. Check `/var/log/catalog/app.log` and DB reachability (`nc -vz $DB_HOST 5432`).
5. If the host is unrecoverable, terminate it; the ASG replaces it.

### ce-capstone-alb-5xx-high
1. Confirm scope in the dashboard (all instances vs one).
2. Tail logs: `aws logs tail /ce-capstone/app --since 15m --follow`
3. Common cause: DB unreachable -> check RDS status and the db security group.
4. Roll back the last app change via a revert PR if it correlates.

### ce-capstone-latency-p95-high
1. Check ASG CPU and RDS CPU/connections on the dashboard.
2. If CPU-bound, confirm the target-tracking policy is scaling out.
3. If DB-bound, check slow queries / connection count.

### ce-capstone-asg-cpu-high
1. Expected during load; confirm scale-out is happening.
2. If stuck at max_size (4), that is the Free-Tier ceiling - note it.
