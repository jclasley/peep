import Foundation

// Claude Code hooks: the app's own binary is the hook (`Peep --hook <Event>`),
// so users need nothing installed besides the app.

let settingsURL = URL(fileURLWithPath: home + "/.claude/settings.json")

// Hook mode. Claude Code passes the hook JSON on stdin; we append one Event line to the inbox.
func runHook(_ event: String) {
  let data = FileHandle.standardInput.readDataToEndOfFile()
  let input = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
  let env = ProcessInfo.processInfo.environment
  var e = Event(event: event, session_id: input["session_id"] as? String ?? "")
  guard !e.session_id.isEmpty else { return }
  e.cwd = input["cwd"] as? String
  // ponytail: the title only changes between turns, so skip re-reading the transcript on every tool call
  if event != "PostToolUse" {
    e.title = (input["transcript_path"] as? String).flatMap(transcriptTitle)
  }
  e.ts = ISO8601DateFormatter().string(from: Date())
  e.herdr_pane = env["HERDR_PANE_ID"]
  e.tmux_pane = env["TMUX_PANE"]
  e.zellij_session = env["ZELLIJ_SESSION_NAME"]
  e.zellij_pane = env["ZELLIJ_PANE_ID"]
  e.iterm_session = env["ITERM_SESSION_ID"]
  e.term_program = env["TERM_PROGRAM"]
  e.entrypoint = env["CLAUDE_CODE_ENTRYPOINT"]
  guard let json = try? JSONEncoder().encode(e) else { return }
  try? FileManager.default.createDirectory(
    at: inboxURL.deletingLastPathComponent(), withIntermediateDirectories: true)
  // One O_APPEND write per line, so concurrent hooks don't interleave.
  let fd = open(inboxURL.path, O_WRONLY | O_APPEND | O_CREAT, 0o644)
  guard fd >= 0 else { return }
  defer { close(fd) }
  let line = json + Data("\n".utf8)
  _ = line.withUnsafeBytes { write(fd, $0.baseAddress, line.count) }
}

// Last /rename title, else last automatic title, from a Claude Code transcript.
func transcriptTitle(_ path: String) -> String? {
  guard let text = try? String(contentsOfFile: path, encoding: .utf8) else { return nil }
  var custom: String?
  var ai: String?
  for line in text.split(separator: "\n") where line.contains("-title") {
    guard let o = (try? JSONSerialization.jsonObject(with: Data(line.utf8))) as? [String: Any]
    else { continue }
    switch o["type"] as? String {
    case "custom-title": custom = o["customTitle"] as? String ?? custom
    case "ai-title": ai = o["aiTitle"] as? String ?? ai
    default: break
    }
  }
  return custom ?? ai
}

enum Hooks {
  // (Claude Code hook, matcher, inbox event)
  static let wanted: [(String, String?, String)] = [
    ("SessionStart", nil, "SessionStart"), ("UserPromptSubmit", nil, "UserPromptSubmit"),
    ("Stop", nil, "Stop"), ("SessionEnd", nil, "SessionEnd"), ("PermissionRequest", nil, "Blocked"),
    ("PreToolUse", "AskUserQuestion|ExitPlanMode", "Blocked"), ("PostToolUse", nil, "PostToolUse"),
  ]

  static var command: String { "\"\(Bundle.main.executablePath!)\" --hook" }

  static func isOurs(_ cmd: String) -> Bool {
    cmd.contains("Peep\" --hook")
  }

  // nil when settings.json exists but isn't valid JSON: never overwrite it then.
  static func read() -> [String: Any]? {
    guard let data = try? Data(contentsOf: settingsURL) else { return [:] }
    return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
  }

  static func commands(_ root: [String: Any]) -> [String] {
    ((root["hooks"] as? [String: Any]) ?? [:]).values
      .flatMap { ($0 as? [[String: Any]]) ?? [] }
      .flatMap { ($0["hooks"] as? [[String: Any]]) ?? [] }
      .compactMap { $0["command"] as? String }
  }

  enum Status { case none, current, stale }

  static func status() -> Status {
    let ours = commands(read() ?? [:]).filter(isOurs)
    if ours.isEmpty { return .none }
    return ours.count == wanted.count && ours.allSatisfy { $0.hasPrefix(command) }
      ? .current : .stale
  }

  // Removes every buddy hook, then adds the current ones when installing. Other hooks are untouched.
  static func merged(_ root: [String: Any], install: Bool, command: String) -> [String: Any] {
    var root = root
    var hooks = root["hooks"] as? [String: Any] ?? [:]
    for (k, v) in hooks {
      guard let groups = v as? [[String: Any]] else { continue }
      let kept = groups.filter { g in
        !((g["hooks"] as? [[String: Any]]) ?? []).contains {
          isOurs($0["command"] as? String ?? "")
        }
      }
      hooks[k] = kept.isEmpty ? nil : kept
    }
    if install {
      for (hook, matcher, event) in wanted {
        var g: [String: Any] = [
          "hooks": [
            ["type": "command", "command": "\(command) \(event)", "async": true, "timeout": 5]
          ]
        ]
        if let matcher { g["matcher"] = matcher }
        hooks[hook] = ((hooks[hook] as? [[String: Any]]) ?? []) + [g]
      }
    }
    root["hooks"] = hooks.isEmpty ? nil : hooks
    return root
  }

  static func write(install: Bool) throws {
    guard let root = read() else {
      throw NSError(
        domain: "Peep", code: 1,
        userInfo: [
          NSLocalizedDescriptionKey: "\(settingsURL.path) is not valid JSON, so it was left alone."
        ])
    }
    let fm = FileManager.default
    try fm.createDirectory(
      at: settingsURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    if fm.fileExists(atPath: settingsURL.path) {
      let backup = settingsURL.appendingPathExtension("bak")
      try? fm.removeItem(at: backup)
      try fm.copyItem(at: settingsURL, to: backup)
    }
    let out = try JSONSerialization.data(
      withJSONObject: merged(root, install: install, command: command),
      options: [.prettyPrinted, .withoutEscapingSlashes])
    try out.write(to: settingsURL, options: .atomic)
  }
}
