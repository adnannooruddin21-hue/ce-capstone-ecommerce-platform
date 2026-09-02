# CloudWatch Logs Insights — /ce-capstone/app

## recent errors
fields @timestamp, @message | filter @message like /ERROR/ | sort @timestamp desc | limit 50

## 5xx over time
fields @timestamp | filter @message like /" 5\d\d /  | stats count() by bin(5m)

## slowest requests
parse @message /(?<path>\/\S*) .* (?<ms>\d+)ms/ | sort ms desc | limit 20