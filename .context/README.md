# .context/ - Manual-Load Configuration

**Purpose:** Reduce token burn by keeping config files out of auto-loaded "Project Context"

## File Organization

**Auto-loaded (workspace root):**
- `SOUL.md` - Core personality (always in context)
- `USER.md` - About Eric (always in context)

**Manual-load (.context/):**
- `AGENTS.md` - Operational guidelines (read when needed)
- `HEARTBEAT.md` - Heartbeat tasks (read only during heartbeats)
- `TOOLS.md` - Tool configurations (read when using specific tools)

**Memory (memory/):**
- `MEMORY.md` - Long-term memory (main session only)
- `YYYY-MM-DD.md` - Daily logs (read recent days as needed)
- `heartbeat-state.json` - Heartbeat tracking

## Context Loading Strategy

### Heartbeats (minimal)
```
Read: .context/HEARTBEAT.md + memory/heartbeat-state.json
Skip: SOUL, USER, AGENTS, TOOLS, MEMORY
```

### Regular conversations
```
Auto-load: SOUL.md, USER.md
On-demand: .context/AGENTS.md (when needed)
           .context/TOOLS.md (when using tools)
           memory/MEMORY.md (main session only)
           memory/recent-days.md (for continuity)
```

### Spawned tasks
```
Auto-load: SOUL.md only (maintain personality)
On-demand: Minimal - only what's needed for the task
```

## Token Savings

**Before:** ~8-10K tokens per message (all files loaded)
**After:** 
- Heartbeats: ~500 tokens
- Regular chat: ~5-6K tokens
- Spawned tasks: ~2-3K tokens

**Result:** 40-90% reduction in context overhead while maintaining quality
