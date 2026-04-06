# Advanced Biter Tactics

Factorio 2.0 runtime mod that uses local wall and turret heuristics to make enemy attack groups behave less like a battering ram.

Current V1 behavior:

- Tracks newly created enemy unit groups, but only takes script control once they reach player wall or gate lines.
- Detects local wall networks and scores nearby breach candidates by turret coverage, distance, and local wall density.
- Refuses to immediately hit turret-covered wall contacts when a safer flank exists nearby.
- Shares temporary siege targets so nearby attack groups converge on the same weak point.
- Splits ranged attackers into a temporary support group when a safe bombardment position exists.
- Falls back to a ranged cone-siege when no safe standoff exists, so spitters spread across multiple outer lanes instead of collapsing into one blob.
- After a breach opens, splits melee attackers across nearby defending turrets instead of piling the whole wave into one target.
- Prioritizes flamethrower turrets first, keeps spitters back from flame zones, and tries to fan melee approaches across safer lanes.
- Reuses physically open breaches even when the interior is still defended, then prioritizes interior turrets before deeper exploit targets.

Implementation notes:

- Runtime-only logic lives in `control.lua`.
- No startup settings are required for V1.
- The repository now includes a VS Code startup smoke test for reaching `InGame`; deeper gameplay validation still depends on static review plus targeted in-game smoke tests with Factorio 2.0.

Debugging / test arena:

- Both slash commands are admin-only.
- `/abt-debug on|off|status|dump|clear` enables or disables capture, prints a live summary, refreshes debug files, or clears transient overlays and cached debug state.
- `/abt-debug-arena wall-open|wall-covered-flank|closed-ring|spitter-siege|mixed-breach-siege|mixed-turret-breach|flame-turret-breach|breach-reuse` rebuilds a dedicated `abt-debug-arena` surface, teleports the issuing admin there, and spawns a reproducible enemy test group.
- Debug output is written under `script-output/advanced-biter-tactics/` as `events.jsonl`, `latest-snapshot.json`, and `arena-manifest.json`.
- `events.jsonl` is the primary AI-readable event stream; `latest-snapshot.json` captures current group and siege-site state including support mode, cone lanes, and breach pressure; `arena-manifest.json` records scenario coordinates plus explicit expected support-mode / reuse metadata for the arena run.
- `spitter-siege` is meant to show pure ranged breach widening from standoff range; `mixed-breach-siege` adds melee units that should hold position until the breach is at least 2 to 3 wall segments wide.
- `mixed-turret-breach` now focuses on front-side gun-turret danger zones versus an uncovered rear wall, so the group should walk around the rectangle before it starts the breach.
- `flame-turret-breach` focuses on west-facing flamethrower turrets with dedicated infinity-pipe fuel and a pre-breach ranged cone that forms outside flame range before it presses the wall.
- `breach-reuse` now runs as a two-wave scenario with interior gun turrets, so each wave should first traverse the already open breach and only then switch to interior targets.

VS Code:

- This repo workflow currently targets Windows because it uses `powershell.exe` and a local `factorio.exe` path.
- Copy `.vscode/settings.example.json` to a local `.vscode/settings.json` or set `advancedBiterTactics.factorioExe` in your personal VS Code user settings. The local `.vscode/settings.json` file is gitignored.
- Use `Run and Debug` with `Factorio: Start Local Test Instance` to start a local test instance wired to `.factorio-test/`.
- Use `Run and Debug` with `Factorio: Run Startup Smoke Test` or `Terminal -> Run Task -> Factorio: Run Startup Smoke Test` to run the non-interactive startup smoke test that waits for Factorio to reach `InGame` and then shuts it down again.
- `Factorio: Sync Test Mod Files` runs automatically before both Run-and-Debug entries and before the startup smoke-test task, so you normally do not need to run it by hand.
- The VS Code helper logic lives in `.vscode/factorio-vscode.ps1`, so the workflow does not depend on long inline shell commands or on your default integrated terminal shell.

Agent bridge runs:

- `tools/run-agent-bridge.ps1 -Scenario wall-open -FactorioExe 'E:\SteamLibrary\steamapps\common\Factorio\bin\x64\factorio.exe'` runs a deterministic bridge-backed scenario and writes artifacts under `.factorio-test/user-data/script-output/agent-bridge-runs/<run-id>/`.
- Each run writes `run-manifest.json`, `events.jsonl`, `frames/frame-<tick>.json`, `assertions.json`, and `summary.json`.
- The runner builds a temporary harness mod locally inside `.factorio-test/`, so no extra tracked test artifacts are added to the repo.
