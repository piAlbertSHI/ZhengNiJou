# Long-task preferences (latest user instructions)

- Long commands are allowed directly in Goal mode. Do not require clearing Goal or moving to a different task.
- Start the real program once in the foreground and reuse its exact session/PID until natural exit. A yielded tool call is not permission to relaunch it.
- Wait on the real process/session, not timers, watchdogs, heartbeat automations, background monitors, or status-polling loops.
- Do not send routine progress messages while a long process is alive; retain required start/result visibility, subject to higher-priority product instructions.
- Read the terminal exit code and final JSON after natural exit. A timeout is not process failure.
- Diagnose nonzero exits and failed scientific gates before any deliberate repair/new verification. Do not blindly retry, relax gates, or mark the goal blocked merely because the first attempt failed.
- An explicit instruction to resume an unfinished objective supersedes an earlier blocked decision. Continue in Goal mode and preserve previous failure evidence.
- These instructions supersede historical 30-minute timer/heartbeat rules in older reports and research notes.
