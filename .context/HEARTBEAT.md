# HEARTBEAT.md — Timmy's Periodic Tasks

## How This Works
Every heartbeat poll, I check what's due and execute it.

## State Tracking
Read/update: `memory/heartbeat-state.json`

```json
{
  "lastChecks": {
    "4h-log": 1738598400,
    "12h-review": 1738598400,
    "24h-priorities": 1738598400
  }
}
```

## Task Schedule

### Every 4 Hours — Activity Log
**Check:** If >4h since `lastChecks.4h-log`

**Do:**
1. Read memory files from last 4h
2. Compile: tasks completed, research done, files created, decisions made
3. Create entry in **⚡ Timmy Activity Tracker** database (ID: `2fcc1ccc-fbef-81f1-a5e7-da2f95cff026`) with:
   - Task: "Activity Log - [timestamp]"
   - Detailed breakdown in page body
   - Read API key from `.context/TOOLS.md` (env var not passed to sandbox)
4. Send 3-line summary to Eric's TG with Notion link:
   ```
   📋 4h Update: [Notion link]
   - [Key accomplishment]
   - [Key accomplishment]
   - [Current focus]
   ```
5. Update `lastChecks.4h-log` to current timestamp

### Every 12 Hours — Self-Review
**Check:** If >12h since `lastChecks.12h-review`

**Do:**
1. Read last 12h of activity logs from Activity Tracker
2. Review:
   - What I did well
   - What I could improve
   - Mistakes made
   - Lessons learned
3. Create entry in **⚡ Timmy Activity Tracker** database with:
   - Task: "Self-Review - [timestamp]"
   - Critical but constructive reflection in page body
4. Update `lastChecks.12h-review` to current timestamp

**No TG ping** — this is internal reflection

### Every 24 Hours — Priority Alignment
**Check:** If >24h since `lastChecks.24h-priorities` AND current hour is 02:00 UTC (11am KST)

**Do:**
1. Read yesterday's work
2. Create daily summary
3. Generate Notion link to Activity Tracker filtered by yesterday's date
4. Send to Eric's TG:
   ```
   📊 Daily Summary: [Notion link]
   
   Yesterday: [1-line summary]
   
   What are your top priorities for the next 24 hours?
   ```
5. Update `lastChecks.24h-priorities` to current timestamp

## Execution Order
If multiple tasks are due:
1. Run 4h log first (fastest)
2. Then 12h review
3. Then 24h priorities (interactive, needs Eric's response)

## When Nothing is Due
Reply: `HEARTBEAT_OK`

## Notes
- All timestamps are Unix epoch (seconds)
- Always update state file after completing a task
- If a task fails, don't update timestamp (will retry next heartbeat)
- Keep TG messages concise — Eric is busy
