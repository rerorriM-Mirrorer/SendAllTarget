# SendAllTarget

Windower addon for synchronizing targets and sending target-aware commands across local FFXI clients.

Original author: Selindrile  
Upstream fork source: https://github.com/bamboooya/SendAllTarget

This work branch preserves the later v1.3 report/fetch implementation that had been living in the old `ffxi-NPCmirror` workspace. It is kept off `master` until the migrated behavior has had a fresh live acceptance pass.

## Commands

The original commands remain available:

- `//sat alltarget` — ask all local clients to target the sender's current target.
- `//sat youtarget <character>` — ask one character to target the sender's current target.
- `//sat allattack` / `//sat youattack <character>` — attack the sender's target.
- `//sat allswitch` / `//sat youswitch <character>` — switch attack target.
- `//sat allcommand ...` / `//sat youcommand ...` — send target-aware commands.
- `//sat stop` or `//sat unfollow` — stop local run/follow.

The migrated v1.3 work adds:

- `//sat fetch <character>` or `//sat fetchtarget <character>` — copy one character's current target.
- `//sat fetchall` — report other responding characters' current targets without changing the sender's target.
- `//sat alltargetreport` or `//sat alltarget report` — broadcast the current target, verify which clients actually selected it, and report results.
- `//sat target <id>` — verbose target-change diagnostic.
- `//sat help` — concise in-game summary.

v1.3 correlates and deduplicates replies, checks zone/login/visibility state, verifies the target after the 0x058 target-change packet, and reports failures instead of assuming success.

## Runtime requirements

- Windower 4
- Windower's standard `packets` and `strings` libraries
- Windower's `Send` addon loaded on every participating client
- The same SendAllTarget version on every participating client for v1.3 request/report commands

## Migration note

The old NPCMirror workspace also held intermediate `v1.1-diagnostic` and `v1.2-fetch` files. Their useful behavior is represented in this v1.3 file; the old files remain recoverable from the `ffxi-NPCmirror` Git history and are not duplicated here.

Before merging this branch to `master`, live-check at least:

1. ordinary `alltarget`;
2. `fetch <character>`;
3. `fetchall`;
4. `alltargetreport` with two or more clients;
5. failure reporting for a client in another zone or unable to see the target.
