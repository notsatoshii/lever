#!/bin/bash
# Cron setup for Timmy's heartbeat rhythms

echo "Setting up cron jobs..."

# 4-hour activity log (every 4 hours)
# Reads memory, compiles activity, pings TG with summary
/opt/clawdbot-cli.sh cron add \
  --name "activity-log-4h" \
  --schedule "0 */4 * * *" \
  --message "Read memory files from last 4h. Compile what I did (tasks completed, research done, files created). Write detailed log to vault/logs/YYYY-MM-DD-HHmm.md. Then send short 3-line summary to Eric's TG." \
  --thinking low \
  --model anthropic/claude-sonnet-4-5

# 12-hour self-review (twice daily: 02:00 and 14:00 UTC)
/opt/clawdbot-cli.sh cron add \
  --name "self-review-12h" \
  --schedule "0 2,14 * * *" \
  --message "Read last 12h of activity logs. Review: What I did well, what I could improve, mistakes made, lessons learned. Write to vault/logs/review-YYYY-MM-DD.md. Be critical but constructive." \
  --thinking low \
  --model anthropic/claude-sonnet-4-5

# 24-hour priority check (11am KST = 02:00 UTC daily)
/opt/clawdbot-cli.sh cron add \
  --name "priority-alignment-24h" \
  --schedule "0 2 * * *" \
  --message "Read yesterday's work. Create daily summary with Notion link. Send to Eric's TG with question: 'What are your top priorities for the next 24 hours?' Update task focus based on response." \
  --thinking low \
  --model anthropic/claude-sonnet-4-5

echo "Cron jobs created. Check with: /opt/clawdbot-cli.sh cron list"
