# Advanced Biter Tactics

Factorio 2.0 runtime mod that uses local wall and turret heuristics to make enemy attack groups behave less like a battering ram.

Current V1 behavior:

- Tracks newly created enemy unit groups, but only takes script control once they reach player wall or gate lines.
- Detects local wall networks and scores nearby breach candidates by turret coverage, distance, and local wall density.
- Refuses to immediately hit turret-covered wall contacts when a safer flank exists nearby.
- Shares temporary siege targets so nearby attack groups converge on the same weak point.
- Splits ranged attackers into a temporary support group when a safe bombardment position exists.
- After a breach opens, splits melee attackers across nearby defending turrets instead of piling the whole wave into one target.
- Prioritizes flamethrower turrets first, keeps spitters back from flame zones, and tries to fan melee approaches across safer lanes.
- Reuses already open, no-longer-covered breaches for later attack groups instead of starting a fresh wall breach.

Implementation notes:

- Runtime-only logic lives in `control.lua`.
- No startup settings are required for V1.
- The repository now includes a VS Code startup smoke test for reaching `InGame`; deeper gameplay validation still depends on static review plus targeted in-game smoke tests with Factorio 2.0.

Debugging / test arena:

- Both slash commands are admin-only.
- `/abt-debug on|off|status|dump|clear` enables or disables capture, prints a live summary, refreshes debug files, or clears transient overlays and cached debug state.
- `/abt-debug-arena wall-open|wall-covered-flank|closed-ring|spitter-siege|mixed-breach-siege|mixed-turret-breach|flame-turret-breach|breach-reuse` rebuilds a dedicated `abt-debug-arena` surface, teleports the issuing admin there, and spawns a reproducible enemy test group.
- Debug output is written under `script-output/advanced-biter-tactics/` as `events.jsonl`, `latest-snapshot.json`, and `arena-manifest.json`.
- `events.jsonl` is the primary AI-readable event stream; `latest-snapshot.json` captures current group and siege-site state; `arena-manifest.json` records scenario coordinates and expected event flow.
- `spitter-siege` is meant to show pure ranged breach widening from standoff range; `mixed-breach-siege` adds melee units that should hold position until the breach is at least 2 to 3 wall segments wide.
- `mixed-turret-breach` focuses on post-breach melee splitting across multiple interior gun turrets.
- `flame-turret-breach` focuses on flamethrower-turret priority, wide melee approach lanes, and keeping spitters out of flame danger.
- `breach-reuse` seeds an already open breach so a fresh group should use it instead of picking a new wall contact.

VS Code:

- Copy `.vscode/settings.example.json` to a local `.vscode/settings.json` or set `advancedBiterTactics.factorioExe` in your personal VS Code user settings.
- Use `Run and Debug` with `Factorio: Start Local Test Instance` to start a local test instance wired to `.factorio-test/`.
- The launch entry uses VS Code's Windows `cppvsdbg` debugger type, so VS Code may ask to install the Microsoft C/C++ debugger extension the first time.
- Use `Terminal -> Run Task -> Factorio: Run Startup Smoke Test` to run the non-interactive startup smoke test that waits for Factorio to reach `InGame` and then shuts it down again.
