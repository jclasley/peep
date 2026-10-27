import AppKit
import ServiceManagement
import UserNotifications

let scale: CGFloat = 4
let side = CGFloat(W) * scale
let defaults = UserDefaults.standard
defaults.register(defaults: [
  "skin": "Clawd", "terminal": "auto", "mux": "auto", "sound": true,
  "src.terminal": true, "src.codeTab": true, "src.chat": false,
])

final class BuddyView: NSView {
  var image: CGImage?
  var bob = 0
  var dx = 0
  private var grab = NSPoint.zero

  override func draw(_ dirtyRect: NSRect) {
    guard let image, let ctx = NSGraphicsContext.current?.cgContext else { return }
    ctx.interpolationQuality = .none
    ctx.draw(
      image,
      in: CGRect(x: CGFloat(1 + dx) * scale, y: CGFloat(bob) * scale, width: side, height: side))
  }

  override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

  override func mouseDown(with e: NSEvent) {
    grab = e.locationInWindow
    if e.clickCount == 2 { buddy.doubleClick() }
  }

  override func mouseDragged(with e: NSEvent) {
    let m = NSEvent.mouseLocation
    window?.setFrameOrigin(NSPoint(x: m.x - grab.x, y: m.y - grab.y))
  }

  override func mouseUp(with e: NSEvent) {
    guard let o = window?.frame.origin else { return }
    defaults.set(o.x, forKey: "x")
    defaults.set(o.y, forKey: "y")
  }

  override func rightMouseDown(with e: NSEvent) {
    NSMenu.popUpContextMenu(buddy.menu(), with: e, for: self)
  }
}

final class Buddy: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
  let store = Store()
  let view = BuddyView(
    frame: NSRect(x: 0, y: 0, width: side + 2 * scale, height: side + 2 * scale))
  var panel: NSPanel!
  var inbox = Inbox()
  let chat = ChatWatcher()
  var chatPolling = false
  var tick = 0

  func applicationDidFinishLaunching(_ n: Notification) {
    panel = NSPanel(
      contentRect: view.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered,
      defer: false)
    panel.isOpaque = false
    panel.backgroundColor = .clear
    panel.hasShadow = false
    panel.level = .floating
    panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
    panel.contentView = view
    if defaults.object(forKey: "x") != nil {
      panel.setFrameOrigin(
        NSPoint(x: defaults.double(forKey: "x"), y: defaults.double(forKey: "y")))
    } else if let f = NSScreen.main?.visibleFrame {
      panel.setFrameOrigin(NSPoint(x: f.maxX - side - 40, y: f.minY + 40))
    }
    panel.orderFrontRegardless()

    let center = UNUserNotificationCenter.current()
    center.delegate = self
    center.requestAuthorization(options: [.alert]) { _, _ in }

    store.enabled = { src in
      switch src {
      case .terminal: defaults.bool(forKey: "src.terminal")
      case .codeTab: defaults.bool(forKey: "src.codeTab")
      case .chat: defaults.bool(forKey: "src.chat")
      }
    }
    // Rebuild state from the inbox without alerting, then start fresh if it has grown large.
    try? FileManager.default.createDirectory(
      at: inboxURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    for e in inbox.read() where !e.session_id.hasPrefix("test-") { store.apply(e, at: e.date) }
    store.prune()
    if inbox.offset > 1_000_000 {
      try? Data().write(to: inboxURL)
      inbox.offset = 0
    }

    Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in self?.step() }
    setUpHooks()
  }

  // Re-point hooks silently if the app moved; ask once if they were never installed.
  func setUpHooks() {
    switch Hooks.status() {
    case .current: return
    case .stale: try? Hooks.write(install: true)
    case .none:
      guard !defaults.bool(forKey: "hooksAsked") else { return }
      defaults.set(true, forKey: "hooksAsked")
      NSApp.activate(ignoringOtherApps: true)
      let a = NSAlert()
      a.messageText = "Connect Peep to Claude Code?"
      a.informativeText =
        "This adds hooks to ~/.claude/settings.json so the buddy knows when a session finishes or needs input. A backup is saved as settings.json.bak. You can remove them later in Settings."
      a.addButton(withTitle: "Install hooks")
      a.addButton(withTitle: "Not now")
      if a.runModal() == .alertFirstButtonReturn { installHooks(true) }
    }
  }

  func installHooks(_ on: Bool) {
    do { try Hooks.write(install: on) } catch {
      NSApp.activate(ignoringOtherApps: true)
      NSAlert(error: error).runModal()
    }
  }

  func step() {
    tick += 1
    if tick % 3 == 0 { for e in inbox.read() { if let s = store.apply(e) { alert(s) } } }
    if tick % 10 == 0, defaults.bool(forKey: "src.chat"), !chatPolling {
      chatPolling = true
      DispatchQueue.global().async {
        let e = self.chat.poll()
        DispatchQueue.main.async {
          self.chatPolling = false
          if let e, let s = self.store.apply(e) { self.alert(s) }
        }
      }
    }
    if tick % 600 == 0 { store.prune() }
    let skin = skins.first { $0.name == defaults.string(forKey: "skin") } ?? skins[2]
    let n = store.stack.count
    let confused = store.topBlocked
    view.image = cgImage(
      frame(skin, t: tick, badge: badgeText(n, question: confused), confused: confused))
    view.dx = confused ? [0, -1, 0, 1][(tick / 3) % 4] : 0
    view.bob = confused ? 0 : n > 0 ? (tick % 4 < 2 ? 2 : 0) : (tick / 8) % 2
    view.needsDisplay = true
  }

  func alert(_ s: Session) {
    if defaults.bool(forKey: "sound") { NSSound(named: "Glass")?.play() }
    let c = UNMutableNotificationContent()
    c.title = s.state == .blocked ? "\(s.title) needs your input" : "\(s.title) is waiting"
    c.body = "Double-click the buddy to jump to it."
    c.userInfo = ["id": s.id]
    UNUserNotificationCenter.current().add(
      UNNotificationRequest(identifier: s.id, content: c, trigger: nil))
  }

  func open(_ id: String?) {
    if let id {
      store.seen(id)
      UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [id])
    }
    if let id, id.hasPrefix("test-") {  // test alerts are gone once acked and focus nothing
      store.sessions[id] = nil
      return
    }
    focus(
      id.flatMap { store.sessions[$0] }, terminal: defaults.string(forKey: "terminal")!,
      mux: defaults.string(forKey: "mux")!)
  }

  func doubleClick() { open(store.pop()) }

  // MARK: Notifications

  func userNotificationCenter(_ c: UNUserNotificationCenter, willPresent n: UNNotification) async
    -> UNNotificationPresentationOptions
  {
    [.banner]
  }

  func userNotificationCenter(_ c: UNUserNotificationCenter, didReceive r: UNNotificationResponse)
    async
  {
    let id = r.notification.request.content.userInfo["id"] as? String
    await MainActor.run { open(id) }
  }

  // MARK: Menu

  func menu() -> NSMenu {
    let m = NSMenu()
    m.addItem(header("Notifications"))
    if store.stack.isEmpty { m.addItem(header("None")) }
    for id in store.stack {
      guard let s = store.sessions[id] else { continue }
      m.addItem(item("\(s.title) — \(ago(s.last))", #selector(openSession(_:)), id))
    }
    m.addItem(.separator())
    m.addItem(header("Sessions"))
    for s in store.sessions.values.sorted(by: { $0.last > $1.last }) {
      let state =
        switch s.state {
        case .working: "◌ \(s.title) — working"
        case .blocked: "? \(s.title) — needs input"
        case .idle: "· \(s.title) — idle"
        }
      m.addItem(item(state, #selector(openSession(_:)), s.id))
    }
    m.addItem(.separator())
    m.addItem(choice("Skin", "skin", skins.map { ("\($0.name) (\($0.theme))", $0.name) }))
    let settings = NSMenu()
    settings.addItem(
      choice(
        "Terminal", "terminal",
        [("Auto", "auto")] + ["Ghostty", "iTerm", "Warp", "Terminal"].map { ($0, $0) }))
    settings.addItem(
      choice(
        "Multiplexer", "mux",
        [
          ("Auto", "auto"), ("herdr", "herdr"), ("zellij", "zellij"), ("tmux", "tmux"),
          ("None", "none"),
        ]))
    settings.addItem(.separator())
    settings.addItem(header("Alert sources"))
    settings.addItem(toggle("Claude Code in the terminal", "src.terminal"))
    settings.addItem(toggle("Claude desktop Code tab", "src.codeTab"))
    settings.addItem(toggle("Claude desktop chat (beta)", "src.chat"))
    settings.addItem(.separator())
    let hooks = item("Claude Code hooks", #selector(toggleHooks), nil)
    hooks.state = Hooks.status() == .current ? .on : .off
    settings.addItem(hooks)
    settings.addItem(toggle("Sound", "sound"))
    let login = item("Open at login", #selector(toggleLogin), nil)
    login.state = SMAppService.mainApp.status == .enabled ? .on : .off
    settings.addItem(login)
    let s = NSMenuItem(title: "Settings", action: nil, keyEquivalent: "")
    s.submenu = settings
    m.addItem(s)
    m.addItem(item("Test alert", #selector(testAlert(_:)), "Stop"))
    m.addItem(item("Test question", #selector(testAlert(_:)), "Blocked"))
    m.addItem(item("Quit", #selector(NSApplication.terminate(_:)), nil, target: NSApp))
    return m
  }

  func header(_ t: String) -> NSMenuItem {
    let i = NSMenuItem(title: t, action: nil, keyEquivalent: "")
    i.isEnabled = false
    return i
  }

  func item(_ t: String, _ a: Selector, _ obj: Any?, target: AnyObject? = nil) -> NSMenuItem {
    let i = NSMenuItem(title: t, action: a, keyEquivalent: "")
    i.target = target ?? self
    i.representedObject = obj
    return i
  }

  func choice(_ title: String, _ key: String, _ opts: [(String, String)]) -> NSMenuItem {
    let sub = NSMenu()
    for (t, v) in opts {
      let i = item(t, #selector(setChoice(_:)), [key, v])
      i.state = defaults.string(forKey: key) == v ? .on : .off
      sub.addItem(i)
    }
    let i = NSMenuItem(title: title, action: nil, keyEquivalent: "")
    i.submenu = sub
    return i
  }

  func toggle(_ t: String, _ key: String) -> NSMenuItem {
    let i = item(t, #selector(flip(_:)), key)
    i.state = defaults.bool(forKey: key) ? .on : .off
    return i
  }

  @objc func openSession(_ i: NSMenuItem) { open(i.representedObject as? String) }

  @objc func setChoice(_ i: NSMenuItem) {
    guard let kv = i.representedObject as? [String] else { return }
    defaults.set(kv[1], forKey: kv[0])
  }

  @objc func flip(_ i: NSMenuItem) {
    guard let key = i.representedObject as? String else { return }
    let on = !defaults.bool(forKey: key)
    defaults.set(on, forKey: key)
    if key == "src.chat", on {
      AXIsProcessTrustedWithOptions(
        [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary)
    }
  }

  @objc func testAlert(_ i: NSMenuItem) {
    let e = Event(
      event: i.representedObject as? String ?? "Stop", session_id: "test-\(tick)",
      title: "Test alert", term_program: "test")
    if let s = store.apply(e) { alert(s) }
  }

  @objc func toggleHooks() { installHooks(Hooks.status() != .current) }

  @objc func toggleLogin() {
    let app = SMAppService.mainApp
    try? app.status == .enabled ? app.unregister() : app.register()
  }
}

func ago(_ d: Date) -> String {
  let m = Int(Date().timeIntervalSince(d) / 60)
  return m < 1 ? "just now" : m < 60 ? "\(m)m ago" : "\(m / 60)h ago"
}

// MARK: - Self-check (`Peep --check`)

func selfCheck() {
  let other: [String: Any] = ["type": "command", "command": "other-tool"]
  let root: [String: Any] = ["model": "x", "hooks": ["Stop": [["hooks": [other]]]]]
  let cmd = "\"/A/Peep\" --hook"
  let installed = Hooks.merged(
    Hooks.merged(root, install: true, command: cmd), install: true, command: cmd)
  let cmds = Hooks.commands(installed)
  assert(
    installed["model"] as? String == "x" && cmds.contains("other-tool"), "other settings survive")
  assert(
    cmds.filter(Hooks.isOurs).count == Hooks.wanted.count, "installing twice adds each hook once")
  assert(
    Hooks.commands(Hooks.merged(installed, install: false, command: cmd)) == ["other-tool"],
    "uninstall")

  let transcript = NSTemporaryDirectory() + "buddy-check.jsonl"
  try! """
  {"type":"ai-title","aiTitle":"Auto"}
  {"type":"custom-title","customTitle":"Renamed"}
  {"type":"ai-title","aiTitle":"Later auto"}
  """.write(toFile: transcript, atomically: true, encoding: .utf8)
  assert(transcriptTitle(transcript) == "Renamed", "a /rename title wins")
  try? FileManager.default.removeItem(atPath: transcript)

  for skin in skins {
    for t in 0..<120 {
      var a = Px()
      skin.draw(&a, t, t % 45 < 2)
      let o = a.outlined()
      for i in 0..<W {
        assert(
          o.a[i] == 0 && o.a[(W - 1) * W + i] == 0 && o.a[i * W] == 0 && o.a[i * W + W - 1] == 0,
          "\(skin.name) touches the edge at t=\(t)")
      }
    }
  }
  assert(badgeText(0) == nil && badgeText(1) == "!" && badgeText(3) == "3" && badgeText(12) == "9+")
  assert(badgeText(1, question: true) == "?" && badgeText(2, question: true) == "2")

  let q = Store()
  assert(q.apply(Event(event: "Blocked", session_id: "p", term_program: "ghostty")) != nil)
  assert(
    q.apply(Event(event: "Blocked", session_id: "p", term_program: "ghostty")) == nil,
    "no re-alert while blocked")
  assert(q.topBlocked && q.stack == ["p"])
  q.apply(Event(event: "PostToolUse", session_id: "p", term_program: "ghostty"))
  assert(
    !q.topBlocked && q.stack.isEmpty && q.sessions["p"]?.state == .working, "answering clears it")
  q.apply(Event(event: "PostToolUse", session_id: "p", term_program: "ghostty"))
  assert(q.sessions["p"]?.state == .working, "ordinary tool use changes nothing")

  let s = Store()
  let term = "ghostty"
  s.apply(Event(event: "SessionStart", session_id: "a", cwd: "/x/alpha", term_program: term))
  assert(s.sessions["a"]?.title == "alpha", "title falls back to the folder")
  s.apply(Event(event: "UserPromptSubmit", session_id: "a", title: "Fix login", term_program: term))
  assert(s.sessions["a"]?.state == .working && s.sessions["a"]?.title == "Fix login")
  assert(s.apply(Event(event: "Stop", session_id: "a", term_program: term)) != nil)
  assert(s.sessions["a"]?.title == "Fix login", "an empty title keeps the old one")
  s.apply(Event(event: "Stop", session_id: "b", cwd: "/x/beta", term_program: term))
  s.apply(Event(event: "Stop", session_id: "a", term_program: term))
  assert(s.stack == ["a", "b"], "a repeated Stop moves to the top without counting twice")
  assert(s.pop() == "a" && s.stack == ["b"], "pop takes the most recent")
  s.apply(Event(event: "Stop", session_id: "a", term_program: term))
  s.apply(Event(event: "UserPromptSubmit", session_id: "b", term_program: term))
  assert(s.stack == ["a"], "a new prompt clears that notification")
  s.apply(Event(event: "SessionEnd", session_id: "a", term_program: term))
  assert(s.stack.isEmpty && s.sessions["a"] == nil, "SessionEnd removes the session")
  assert(Event(event: "Stop", session_id: "c").source == .codeTab)
  assert(autoMux(Event(event: "Stop", session_id: "c", zellij_pane: "3")) == "zellij")
  assert(autoMux(Event(event: "Stop", session_id: "c", tmux_pane: "%1")) == "tmux")
  assert(autoMux(Event(event: "Stop", session_id: "c", term_program: "ghostty")) == "none")
  assert(Event(event: "Stop", session_id: "c", herdr_pane: "w1:p1").source == .terminal)
  s.enabled = { $0 != .codeTab }
  assert(s.apply(Event(event: "Stop", session_id: "c")) == nil, "disabled sources are ignored")
}

if let i = CommandLine.arguments.firstIndex(of: "--hook"), i + 1 < CommandLine.arguments.count {
  runHook(CommandLine.arguments[i + 1])
  exit(0)
}

// For scripts and agents, which can't click the first-launch dialog.
for (flag, on) in [("--install-hooks", true), ("--uninstall-hooks", false)]
where CommandLine.arguments.contains(flag) {
  do {
    try Hooks.write(install: on)
    defaults.set(true, forKey: "hooksAsked")
    print(
      "Peep hooks \(on ? "installed in" : "removed from") \(settingsURL.path) (backup: settings.json.bak)"
    )
    exit(0)
  } catch {
    FileHandle.standardError.write(Data("\(error.localizedDescription)\n".utf8))
    exit(1)
  }
}

if CommandLine.arguments.contains("--check") {
  selfCheck()
  print("ok")
  exit(0)
}

let buddy = Buddy()
let app = NSApplication.shared
app.setActivationPolicy(.accessory)
app.delegate = buddy
app.run()
