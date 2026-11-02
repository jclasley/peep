# Peep

A floating pixel-art buddy for macOS that tells you when a Claude Code session finishes or needs your input, and takes you straight to that session. Swift + AppKit, no dependencies.

## Commands

| Command | What it does |
|---|---|
| `swift run Peep --check` | Self-check: renders every skin, runs the session-store, hook-installer and title fixtures. Must print `ok` |
| `scripts/build.sh [version]` | Builds a universal `build/Peep.app` (ad-hoc signed) and `build/Peep.zip` |
| `open "build/Peep.app"` | Run the local build |
| `<app>/Contents/MacOS/Peep --install-hooks` / `--uninstall-hooks` | Install or remove the hooks without the GUI (used by the README's agent install steps) |
| `swift format --in-place --recursive Sources` | Format after every change |

Releases: pushing a `v*` tag runs `.github/workflows/release.yml`, which runs the self-check, builds, and attaches the zip to a GitHub release. Use Option-right-click → Test alert / Test question to try alerts without Claude Code.

When you run a local build, it re-points the hooks to itself (see `setUpHooks`). The installed copy takes them back the next time it starts.

## How it works

```
Claude Code hooks ──► Peep --hook <Event> ──► ~/.peep/inbox (JSON lines)
                                                      │  polled every 0.3 s
                                                      ▼
                                   Store (sessions + notification stack)
                                      │                         │
                           sprite frame + badge          sound, macOS notification
                                      │
                         double-click / menu ──► focus(): multiplexer pane, terminal tab,
                                                 or claude:// deep link
```

- **`Sources/Peep/Hooks.swift`**: the app's own binary is the hook. `runHook` reads the hook JSON from stdin and adds the session title (last `custom-title`, then last `ai-title`, from the transcript; skipped for `PostToolUse`). It also adds every id it can find in the environment (`HERDR_PANE_ID`, `TMUX_PANE`, `ZELLIJ_*`, `ITERM_SESSION_ID`, `TERM_PROGRAM`, `CLAUDE_CODE_ENTRYPOINT`), then appends one line to the inbox. `Hooks` installs and removes the entries in `~/.claude/settings.json`:
  - It removes every buddy hook, then adds the current ones, so re-running is safe.
  - It never touches other hooks.
  - It saves `settings.json.bak` first.
  - It refuses to write if the file isn't valid JSON.
  - Paths come from `$HOME`, so tests can point them elsewhere.
- **`Sources/Peep/Sessions.swift`**: `Event` (one inbox line), `Store` (state machine), `Inbox` (reads new lines), `focus()` (jumps to a session), `ChatWatcher` (beta desktop-chat detection through Accessibility).
- **`Sources/Peep/Sprites.swift`**: the 32×32 pixel buffer, drawing helpers, outline pass, badge glyphs and all skins.
- **`Sources/Peep/main.swift`**: the floating panel, mouse handling, animation timer, notifications, right-click menu, settings and the `--check` self-check.

### Event → state

| Inbox `event` | Sent by hook | Effect |
|---|---|---|
| `SessionStart` | `SessionStart` | Session listed as idle |
| `UserPromptSubmit` | `UserPromptSubmit` | Working; clears its notification |
| `Stop` | `Stop` | Idle; pushes a notification ("!") |
| `Blocked` | `PermissionRequest`, `PreToolUse` for `AskUserQuestion\|ExitPlanMode` | Needs input; pushes a notification ("?", confused animation) |
| `PostToolUse` | `PostToolUse` | Clears a `Blocked` state |
| `SessionEnd` | `SessionEnd` | Removes the session |

The notification stack is newest first. A double-click pops the newest one. Sessions whose id starts with `test-` are removed once acknowledged and are skipped when the inbox is replayed at launch.

## Adding a skin

Add a `Skin` to `skins` in `Sprites.swift`:

```swift
Skin(name: "Blob", theme: "Cute", draw: { a, t, bl in
  a.e(16, 19, 10, 8, rgb(0x8E7CF0))   // body: ellipse (center x, center y, radius x, radius y)
  a.face(17, 3, bl)                    // eyes, cheeks and mouth; `bl` = blinking this frame
}, overlay: { a, t in                  // optional: drawn after the outline, so it gets none
  a.p(4, Double(3 + t % 6), rgb(0x85B7EB))
})
```

- The canvas is 32×32 and `x = 16` is the center line (mirror of column `c` is `31 - c`).
- Helpers on `Px`: `p` (pixel), `r` (rectangle), `e` (ellipse, with optional row clip), `eye`, `face`, `empty`.
- `t` counts frames at 10 fps. Animate with `t % n`. Blinking is handled for you through `bl`.
- Leave 2 empty pixels on every side. The outline pass adds a dark ring and a white ring, and the self-check fails if a skin touches the edge in any of 120 frames.
- Use `overlay` for effects that should not be outlined (rain, bubbles, orbits). Check `a.empty(x, y)` to draw only behind the body.
- The skin shows up in the right-click **Skin** menu automatically.

## Adding a setting

1. Register a default in `defaults.register(defaults:)` in `main.swift`.
2. Add a menu item in `menu()`: `choice(title, key, [(label, value)])` for one-of-many, or `toggle(title, key)` for on/off. Both read and write `UserDefaults` for you.
3. Read it where it matters with `defaults.string(forKey:)` / `defaults.bool(forKey:)`. Settings are read on every use, so no restart is needed.

## Adding a hook event

1. Add a `(Claude Code hook, matcher, inbox event)` entry to `Hooks.wanted` in `Hooks.swift`.
2. Handle it in `Store.apply` in `Sessions.swift`. Return the session only when the event should alert.
3. Add a case to the fixture in `selfCheck()`.
4. Start the new build. `setUpHooks` sees the installed hooks no longer match `Hooks.wanted` and rewrites them.

## Adding a terminal or multiplexer

- **Terminal**: add its bundle id to `terminalBundles` and its `TERM_PROGRAM` value to `terminalPrograms` (for **Auto**), then add it to the Terminal menu in `menu()`.
- **Multiplexer**:
  1. Make `runHook` record the pane id from the environment.
  2. Add the field to `Event`.
  3. Detect it in `autoMux`.
  4. Add a `case` in `focus()` that runs the multiplexer's focus command through `run([...])`.
  5. Add it to the Multiplexer menu.

  `run` uses a fixed `PATH` with Homebrew and `~/.local/bin`, because apps don't inherit the shell's `PATH`.
- **Badge glyphs**: 3×5 strings in `Px.glyphs`.

## Claude desktop

- Code tab sessions open with `claude://code/continue?session=local_<id>`. The hook sees the CLI `session_id`, so `desktopSessionID` maps it to the desktop's `local_<id>` through `cliSessionId` in `~/Library/Application Support/Claude/claude-code-sessions/**/local_*.json`. These are internal app details and can change with Claude.app updates.
- Desktop *chat* alerts (Settings → Alert sources, beta) look for a "Stop" button in Claude.app through Accessibility. They need Accessibility permission and can only bring the app to the front.

## Conventions

- No third-party dependencies. Prefer AppKit and Foundation.
- Keep it small: one file per concern, no abstractions with one user. Mark deliberate shortcuts with a `ponytail:` comment that names the limit.
- Times are UTC (`date -u` in the hook, ISO 8601 in the app).
- Keep personal setup out of the code: defaults are `auto`, and everything else is a setting.
