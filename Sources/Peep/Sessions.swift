import AppKit
import ApplicationServices

let claudeBundle = "com.anthropic.claudefordesktop"
// $HOME first, like other command-line tools, so hooks and tests can point elsewhere.
let home = ProcessInfo.processInfo.environment["HOME"] ?? NSHomeDirectory()
let inboxURL = URL(fileURLWithPath: home + "/.peep/inbox")

enum Source { case terminal, codeTab, chat }

// One line of ~/.peep/inbox, written by `Peep --hook` (or the chat watcher).
struct Event: Codable {
  var event: String
  var session_id: String
  var cwd: String? = nil
  var title: String? = nil
  var ts: String? = nil
  var herdr_pane: String? = nil
  var tmux_pane: String? = nil
  var zellij_session: String? = nil
  var zellij_pane: String? = nil
  var iterm_session: String? = nil
  var term_program: String? = nil
  var entrypoint: String? = nil

  var source: Source {
    if session_id == "desktop-chat" { return .chat }
    if entrypoint?.contains("desktop") == true { return .codeTab }
    // ponytail: no terminal or multiplexer ids at all means the desktop Code tab
    let ids = [term_program, herdr_pane, tmux_pane, zellij_pane, iterm_session]
    return ids.allSatisfy { ($0 ?? "").isEmpty } ? .codeTab : .terminal
  }

  var date: Date { ts.flatMap { ISO8601DateFormatter().date(from: $0) } ?? Date() }
}

enum State { case idle, working, blocked }

final class Session {
  let id: String
  var title = ""
  var state = State.idle
  var last: Date
  var ev: Event
  init(id: String, last: Date, ev: Event) {
    self.id = id
    self.last = last
    self.ev = ev
  }
}

final class Store {
  var sessions: [String: Session] = [:]
  var stack: [String] = []  // waiting sessions, newest first
  var enabled: (Source) -> Bool = { _ in true }

  // Returns the session when this event raised a new notification.
  @discardableResult
  func apply(_ e: Event, at now: Date = Date()) -> Session? {
    guard enabled(e.source) else { return nil }
    let id = e.session_id
    if e.event == "SessionEnd" {
      sessions[id] = nil
      seen(id)
      return nil
    }
    let s = sessions[id] ?? Session(id: id, last: now, ev: e)
    sessions[id] = s
    s.ev = e
    s.last = now
    if let t = e.title, !t.isEmpty {
      s.title = t
    } else if s.title.isEmpty {
      s.title = e.cwd.map { URL(fileURLWithPath: $0).lastPathComponent } ?? id
    }
    switch e.event {
    case "UserPromptSubmit":
      s.state = .working
      seen(id)
    case "Stop":
      s.state = .idle
      seen(id)
      stack.insert(id, at: 0)
      return s
    case "Blocked":  // permission prompt or question; repeats while still blocked don't re-alert
      if s.state == .blocked { return nil }
      s.state = .blocked
      seen(id)
      stack.insert(id, at: 0)
      return s
    case "PostToolUse":  // the prompt was answered
      if s.state == .blocked {
        s.state = .working
        seen(id)
      }
    default: break
    }
    return nil
  }

  var topBlocked: Bool { stack.first.flatMap { sessions[$0] }?.state == .blocked }

  func pop() -> String? { stack.isEmpty ? nil : stack.removeFirst() }
  func seen(_ id: String) { stack.removeAll { $0 == id } }

  func prune(_ now: Date = Date()) {
    for (id, s) in sessions where now.timeIntervalSince(s.last) > 12 * 3600 {
      sessions[id] = nil
      seen(id)
    }
  }
}

// ponytail: polls the file size from the animation timer instead of a DispatchSource watcher
struct Inbox {
  var offset: UInt64 = 0

  mutating func read() -> [Event] {
    guard let h = try? FileHandle(forReadingFrom: inboxURL) else { return [] }
    defer { try? h.close() }
    let end = (try? h.seekToEnd()) ?? 0
    if end < offset { offset = 0 }
    if end == offset { return [] }
    try? h.seek(toOffset: offset)
    let data = h.readDataToEndOfFile()
    guard let nl = data.lastIndex(of: 0x0A) else { return [] }
    offset += UInt64(nl - data.startIndex + 1)
    return data[data.startIndex..<nl].split(separator: 0x0A).compactMap {
      try? JSONDecoder().decode(Event.self, from: Data($0))
    }
  }
}

// MARK: - Focus

let terminalBundles = [
  "Ghostty": "com.mitchellh.ghostty", "iTerm": "com.googlecode.iterm2",
  "Warp": "dev.warp.Warp-Stable", "Terminal": "com.apple.Terminal",
]

func activate(_ bundle: String) {
  guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundle) else { return }
  let cfg = NSWorkspace.OpenConfiguration()
  cfg.activates = true
  NSWorkspace.shared.openApplication(at: url, configuration: cfg)
}

func run(_ args: [String]) {
  let p = Process()
  p.executableURL = URL(fileURLWithPath: "/usr/bin/env")
  p.arguments = args
  var env = ProcessInfo.processInfo.environment
  env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:\(NSHomeDirectory())/.local/bin:/usr/bin:/bin"
  p.environment = env
  try? p.run()
  p.waitUntilExit()
}

// The desktop keeps one local_<id>.json per Code tab session, holding the CLI session id the hooks see.
func desktopSessionID(cli: String) -> String? {
  let dir = URL(
    fileURLWithPath: NSHomeDirectory() + "/Library/Application Support/Claude/claude-code-sessions")
  let files = FileManager.default.enumerator(at: dir, includingPropertiesForKeys: nil)
  while let url = files?.nextObject() as? URL {
    let name = url.deletingPathExtension().lastPathComponent
    guard name.hasPrefix("local_"), url.pathExtension == "json",
      let data = try? Data(contentsOf: url), data.range(of: Data(cli.utf8)) != nil
    else { continue }
    return name
  }
  return nil
}

// TERM_PROGRAM value → Terminal setting name, for the "auto" terminal setting.
let terminalPrograms = [
  "ghostty": "Ghostty", "iTerm.app": "iTerm", "WarpTerminal": "Warp", "Apple_Terminal": "Terminal",
]

// "auto" multiplexer: whichever multiplexer id the hook recorded.
func autoMux(_ e: Event) -> String {
  if !(e.herdr_pane ?? "").isEmpty { return "herdr" }
  if !(e.zellij_pane ?? "").isEmpty { return "zellij" }
  if !(e.tmux_pane ?? "").isEmpty { return "tmux" }
  return "none"
}

func focus(_ s: Session?, terminal: String, mux: String) {
  if let s, s.ev.source == .codeTab, let id = desktopSessionID(cli: s.id),
    let url = URL(string: "claude://code/continue?session=\(id)")
  {
    NSWorkspace.shared.open(url)
    return
  }
  guard let s, s.ev.source == .terminal else { return activate(claudeBundle) }
  let e = s.ev
  let mux = mux != "auto" ? mux : autoMux(e)
  let terminal =
    terminal != "auto" ? terminal : terminalPrograms[e.term_program ?? ""] ?? "Terminal"
  switch mux {
  case "herdr":
    if let p = e.herdr_pane, !p.isEmpty { run(["herdr", "agent", "focus", p]) }
  case "tmux":
    if let p = e.tmux_pane, !p.isEmpty {
      run(["tmux", "switch-client", "-t", p])
      run(["tmux", "select-window", "-t", p])
      run(["tmux", "select-pane", "-t", p])
    }
  case "zellij":
    if let ses = e.zellij_session, let p = e.zellij_pane, !ses.isEmpty, !p.isEmpty {
      run(["zellij", "--session", ses, "action", "focus-pane-id", p])
    }
  default: break
  }
  if terminal == "iTerm", let id = e.iterm_session?.split(separator: ":").last {
    let src = """
      tell application "iTerm2"
        repeat with w in windows
          repeat with t in tabs of w
            repeat with s in sessions of t
              if unique id of s is "\(id)" then
                select w
                select t
                select s
              end if
            end repeat
          end repeat
        end repeat
        activate
      end tell
      """
    NSAppleScript(source: src)?.executeAndReturnError(nil)
    return
  }
  activate(terminalBundles[terminal] ?? terminalBundles["Terminal"]!)
}

// MARK: - Desktop chat watcher (beta)

// No official event exists: watch the Claude.app window for a "Stop" button through Accessibility.
// When it disappears, a response has finished. Can break when Claude.app changes its UI.
final class ChatWatcher {
  private var busy = false

  func poll() -> Event? {
    guard AXIsProcessTrusted(),
      let app = NSRunningApplication.runningApplications(withBundleIdentifier: claudeBundle).first
    else { return nil }
    let ax = AXUIElementCreateApplication(app.processIdentifier)
    AXUIElementSetAttributeValue(ax, "AXManualAccessibility" as CFString, kCFBooleanTrue)
    var budget = 4000
    let now = hasStop(ax, depth: 0, budget: &budget)
    defer { busy = now }
    guard now != busy else { return nil }
    return Event(
      event: now ? "UserPromptSubmit" : "Stop", session_id: "desktop-chat",
      title: windowTitle(ax) ?? "Claude chat")
  }

  private func attr(_ e: AXUIElement, _ name: String) -> CFTypeRef? {
    var v: CFTypeRef?
    AXUIElementCopyAttributeValue(e, name as CFString, &v)
    return v
  }

  private func windowTitle(_ app: AXUIElement) -> String? {
    guard let w = attr(app, kAXFocusedWindowAttribute) else { return nil }
    return attr(w as! AXUIElement, kAXTitleAttribute) as? String
  }

  private func hasStop(_ e: AXUIElement, depth: Int, budget: inout Int) -> Bool {
    budget -= 1
    if budget < 0 || depth > 40 { return false }
    if attr(e, kAXRoleAttribute) as? String == "AXButton" {
      let label =
        ((attr(e, kAXDescriptionAttribute) as? String) ?? "")
        + ((attr(e, kAXTitleAttribute) as? String) ?? "")
      if label.localizedCaseInsensitiveContains("stop") { return true }
    }
    for c in (attr(e, kAXChildrenAttribute) as? [AXUIElement]) ?? []
    where hasStop(c, depth: depth + 1, budget: &budget) {
      return true
    }
    return false
  }
}
