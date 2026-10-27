import CoreGraphics
import Foundation

// 32×32 procedural pixel sprites, ported from the picker preview.
let W = 32

func rgb(_ v: UInt32) -> UInt32 { 0xFF00_0000 | v }

enum Col {
  static let k = rgb(0x2B2118), w = rgb(0xFFFFFF), cl = rgb(0xD97757), cd = rgb(0xB85C3E)
  static let cL = rgb(0xF0A07E), cr = rgb(0xFBF3E8), pk = rgb(0xF49C9C)
}

struct Px {
  var a = [UInt32](repeating: 0, count: W * W)

  mutating func p(_ x: Double, _ y: Double, _ c: UInt32) {
    let xi = Int(x.rounded())
    let yi = Int(y.rounded())
    if xi >= 0, yi >= 0, xi < W, yi < W { a[yi * W + xi] = c }
  }

  mutating func r(_ x: Int, _ y: Int, _ w: Int, _ h: Int, _ c: UInt32) {
    for j in 0..<max(h, 0) { for i in 0..<max(w, 0) { p(Double(x + i), Double(y + j), c) } }
  }

  mutating func e(
    _ cx: Double, _ cy: Double, _ rx: Double, _ ry: Double, _ c: UInt32, _ y0: Int = -1,
    _ y1: Int = 99
  ) {
    for y in 0..<W where y >= y0 && y <= y1 {
      for x in 0..<W {
        let dx = (Double(x) + 0.5 - cx) / rx
        let dy = (Double(y) + 0.5 - cy) / ry
        if dx * dx + dy * dy <= 1 { a[y * W + x] = c }
      }
    }
  }

  func empty(_ x: Double, _ y: Double) -> Bool {
    let xi = Int(x.rounded())
    let yi = Int(y.rounded())
    return xi >= 0 && yi >= 0 && xi < W && yi < W && a[yi * W + xi] == 0
  }

  mutating func eye(_ x: Int, _ y: Int, _ bl: Bool, _ c: UInt32 = Col.k, _ h: Int = 3) {
    if bl {
      r(x, y + h - 1, 2, 1, c)
    } else {
      r(x, y, 2, h, c)
      p(Double(x), Double(y), Col.w)
    }
  }

  mutating func face(
    _ y: Int, _ g: Int, _ bl: Bool, ec: UInt32 = Col.k, eh: Int = 3, cheeks: Bool = true,
    mc: UInt32 = Col.k
  ) {
    let L = 16 - g - 2
    let R = 30 - L
    eye(L, y, bl, ec, eh)
    eye(R, y, bl, ec, eh)
    if cheeks {
      r(L - 2, y + eh, 2, 1, Col.pk)
      r(R + 2, y + eh, 2, 1, Col.pk)
    }
    let yy = y + eh + 1
    r(14, yy, 1, 1, mc)
    r(17, yy, 1, 1, mc)
    r(15, yy + 1, 2, 1, mc)
  }

  // 1px dark outline, then 1px white rim, so the buddy reads on any background.
  func outlined() -> Px {
    var o = self
    for i in 0..<W * W where a[i] == 0 {
      let x = i % W
      let y = i / W
      if (x > 0 && a[i - 1] != 0) || (x < W - 1 && a[i + 1] != 0) || (y > 0 && a[i - W] != 0)
        || (y < W - 1 && a[i + W] != 0)
      {
        o.a[i] = Col.k
      }
    }
    var o2 = o
    for i in 0..<W * W where o.a[i] == 0 {
      let x = i % W
      let y = i / W
      outer: for dy in -1...1 {
        for dx in -1...1 {
          let X = x + dx
          let Y = y + dy
          if X >= 0, Y >= 0, X < W, Y < W, o.a[Y * W + X] != 0 {
            o2.a[i] = Col.w
            break outer
          }
        }
      }
    }
    return o2
  }

  static let glyphs: [Character: [String]] = [
    "0": ["###", "#.#", "#.#", "#.#", "###"], "1": [".#.", "##.", ".#.", ".#.", "###"],
    "2": ["###", "..#", "###", "#..", "###"], "3": ["###", "..#", "###", "..#", "###"],
    "4": ["#.#", "#.#", "###", "..#", "..#"], "5": ["###", "#..", "###", "..#", "###"],
    "6": ["###", "#..", "###", "#.#", "###"], "7": ["###", "..#", "..#", "..#", "..#"],
    "8": ["###", "#.#", "###", "#.#", "###"], "9": ["###", "#.#", "###", "..#", "###"],
    "+": ["...", ".#.", "###", ".#.", "..."], "!": [".#.", ".#.", ".#.", "...", ".#."],
    "?": ["###", "..#", ".##", "...", ".#."],
  ]

  mutating func badge(_ s: String) {
    let n = s.count
    let w = n * 4 + 3
    let x0 = W - w
    r(x0, 0, w, 9, Col.k)
    r(x0 + 1, 1, w - 2, 7, Col.cl)
    for (i, ch) in s.enumerated() {
      for (dy, row) in (Px.glyphs[ch] ?? []).enumerated() {
        for (dx, c) in row.enumerated() where c == "#" {
          p(Double(x0 + 2 + i * 4 + dx), Double(2 + dy), Col.w)
        }
      }
    }
  }
}

func badgeText(_ n: Int, question: Bool = false) -> String? {
  n == 0 ? nil : n == 1 ? (question ? "?" : "!") : n < 10 ? "\(n)" : "9+"
}

struct Skin {
  let name: String
  let theme: String
  let draw: (inout Px, Int, Bool) -> Void
  var overlay: ((inout Px, Int) -> Void)? = nil
}

let skins: [Skin] = [
  Skin(
    name: "Nimbus", theme: "Whimsical",
    draw: { a, t, bl in
      let c = rgb(0xF4F7FB)
      for (x, y, R) in [(11.0, 17.0, 6.0), (20, 14, 7), (14, 13, 5.5), (25, 19, 4.5), (7, 20, 4)] {
        a.e(x, y, R, R, c)
      }
      a.r(6, 19, 21, 5, c)
      a.r(6, 23, 21, 1, rgb(0xD6E0EE))
      a.face(16, 3, bl)
    },
    overlay: { a, t in
      for k in 0..<3 {
        let y = Double(26 + (t / 2 + k * 3) % 5)
        let x = Double(10 + k * 6)
        a.p(x, y, rgb(0x378ADD))
        a.p(x, y + 1, rgb(0x378ADD))
      }
    }),
  Skin(
    name: "Truffle", theme: "Whimsical",
    draw: { a, t, bl in
      a.r(10, 15, 12, 11, Col.cr)
      a.e(16, 25, 6, 2, Col.cr)
      a.e(16, 14, 13, 10, rgb(0xE0533D), 0, 15)
      a.r(3, 15, 26, 1, rgb(0xB23A2A))
      for (x, y, R) in [(9.0, 10.0, 2.2), (21, 8, 2.6), (15, 6, 1.5), (25, 13, 1.6), (14, 12, 1.4)]
      { a.e(x, y, R, R, Col.cr) }
      a.face(17, 2, bl)
    },
    overlay: { a, t in
      let k = t % 36
      guard k < 18 else { return }
      for (x, o) in [(8, 0), (16, 3), (24, 1)] {
        let y = 3 - ((k + o * 2) >> 2)
        if y >= 0, a.empty(Double(x), Double(y)) {
          a.p(Double(x + (k >> 3) % 2), Double(y), rgb(0xF0997B))
        }
      }
    }),
  Skin(
    name: "Clawd", theme: "Cute",
    draw: { a, t, bl in
      let wave = t % 60 < 14 && (t >> 1) % 2 == 1
      a.r(6, 9, 20, 12, Col.cl)
      a.r(6, 9, 20, 1, Col.cL)
      a.r(6, 20, 20, 1, Col.cd)
      a.r(3, wave ? 10 : 13, 3, 4, Col.cl)
      a.r(26, 13, 3, 4, Col.cl)
      for x in [7, 11, 19, 23] { a.r(x, 21, 2, 5, Col.cl) }
      a.eye(10, 12, bl, Col.k, 4)
      a.eye(20, 12, bl, Col.k, 4)
    }),
  Skin(
    name: "Hop", theme: "Cute",
    draw: { a, t, bl in
      let tw = t % 70 < 6
      a.e(12, 9, 2.6, 6.5, Col.cr)
      a.e(20, tw ? 11 : 9, 2.6, tw ? 4.5 : 6.5, Col.cr)
      a.e(12, 9, 1, 4.5, Col.pk)
      a.e(20, tw ? 11 : 9, 1, tw ? 3 : 4.5, Col.pk)
      a.e(16, 19, 9.5, 8, Col.cr)
      a.e(11, 27, 3, 1.6, Col.cr)
      a.e(21, 27, 3, 1.6, Col.cr)
      a.face(16, 3, bl)
      a.r(15, 19, 2, 1, Col.pk)
    }),
  Skin(
    name: "Visor", theme: "Cyber",
    draw: { a, t, bl in
      let m = rgb(0xC9CED6)
      let md = rgb(0x8D96A3)
      a.r(15, 5, 2, 2, md)
      a.r(15, 3, 2, 2, t % 20 < 10 ? Col.cl : Col.cL)
      a.r(7, 7, 18, 13, m)
      a.r(7, 19, 18, 1, md)
      a.r(5, 11, 2, 5, md)
      a.r(25, 11, 2, 5, md)
      a.r(9, 10, 14, 6, rgb(0x141B2D))
      a.r(9 + (t >> 1) % 14, 10, 1, 6, rgb(0x2E4A6B))
      if bl {
        a.r(11, 13, 2, 1, Col.cl)
        a.r(19, 13, 2, 1, Col.cl)
      } else {
        a.r(11, 11, 2, 3, Col.cl)
        a.r(19, 11, 2, 3, Col.cl)
      }
      a.r(9, 17, 2, 1, Col.pk)
      a.r(21, 17, 2, 1, Col.pk)
      a.r(10, 20, 12, 6, m)
      a.r(15, 22, 2, 2, t % 14 < 7 ? Col.cl : rgb(0x4FE3E8))
      a.r(7, 21, 2, 4, md)
      a.r(23, 21, 2, 4, md)
      a.r(11, 26, 3, 2, md)
      a.r(18, 26, 3, 2, md)
    }),
  Skin(
    name: "Orbit", theme: "Cyber",
    draw: { a, t, bl in
      a.e(16, 17, 9.5, 9.5, rgb(0x1F2A44))
      a.e(12, 12, 2, 1.5, rgb(0x3A4A6E))
      a.r(7, 20, 18, 1, rgb(0xE255A1))
      a.r(15, 5, 2, 3, rgb(0x8D96A3))
      let pw = t % 4 < 2 ? 8 : 4
      a.r(16 - pw, 4, pw * 2, 1, rgb(0xC9CED6))
      if bl {
        a.r(13, 16, 6, 1, rgb(0x4FE3E8))
      } else {
        a.e(16, 16, 3.5, 3.5, rgb(0xE6F7FF))
        a.e(16, 16, 2, 2, Col.cl)
        a.p(15, 15, Col.w)
      }
    },
    overlay: { a, t in
      let f = t % 3
      a.r(14, 27, 4, 1, Col.cL)
      if f > 0 { a.r(15, 28, 2, 1, rgb(0xFAC775)) }
      if f == 2 { a.p(15, 29, rgb(0xFAC775)) }
    }),
  Skin(
    name: "Ember", theme: "Fantasy",
    draw: { a, t, bl in
      let g = rgb(0x6CBF6A)
      let gd = rgb(0x3F8F4F)
      let wy = t % 16 < 8 ? 9 : 12
      for j in 0..<6 {
        a.r(3, wy + j, j + 1, 1, gd)
        a.r(28 - j, wy + j, j + 1, 1, gd)
      }
      a.e(16, 19, 9, 8, g)
      a.e(16, 22, 5, 4.5, Col.cr)
      a.r(11, 9, 2, 3, Col.cr)
      a.r(19, 9, 2, 3, Col.cr)
      a.r(24, 23, 4, 2, g)
      a.r(27, 21, 2, 2, Col.cl)
      a.r(10, 26, 4, 2, gd)
      a.r(18, 26, 4, 2, gd)
      a.face(15, 3, bl)
    },
    overlay: { a, t in
      let k = t % 50
      guard k < 12 else { return }
      a.p(Double(22 + (k >> 2)), Double(8 - (k >> 2)), rgb(0xB4B2A9))
      a.p(Double(23 + (k >> 2)), Double(8 - (k >> 2)), rgb(0xD3D1C7))
    }),
  Skin(
    name: "Merlin", theme: "Fantasy",
    draw: { a, t, bl in
      let h = rgb(0x3C3489)
      let star = rgb(0xFAC775)
      a.e(16, 22, 11, 6.5, rgb(0x8E7CF0))
      a.r(9, 18, 2, 2, rgb(0xCECBF6))
      for y in 3...13 {
        let hw = Double(y - 3) * 0.55 + 1
        let cx = 16 + Double(13 - y) * 0.3
        a.r(Int((cx - hw).rounded()), y, Int((2 * hw).rounded()), 1, h)
      }
      a.r(10, 12, 12, 1, Col.cl)
      a.r(7, 14, 18, 2, h)
      a.p(18, 7, star)
      if t % 20 < 10 {
        a.p(17, 7, star)
        a.p(19, 7, star)
        a.p(18, 6, star)
        a.p(18, 8, star)
      }
      a.face(20, 3, bl)
    }),
  Skin(
    name: "Atomo", theme: "Scientific",
    draw: { a, t, bl in
      a.e(16, 16, 7, 7, Col.cl)
      a.r(11, 11, 2, 1, Col.cL)
      a.face(13, 2, bl)
    },
    overlay: { a, t in
      for k in 0..<3 {
        let ph = Double(k) * .pi / 3
        func pos(_ u: Double) -> (Double, Double) {
          (
            15.5 + 12.5 * cos(u) * cos(ph) - 4.5 * sin(u) * sin(ph),
            15.5 + 12.5 * cos(u) * sin(ph) + 4.5 * sin(u) * cos(ph)
          )
        }
        for s in stride(from: 0, to: 60, by: 2) {
          let (x, y) = pos(Double(s) / 60 * 6.283)
          if a.empty(x, y) { a.p(x, y, rgb(0x85B7EB)) }
        }
        let (x, y) = pos(Double(t) * 0.18 + Double(k) * 2.1)
        a.r(Int(x.rounded()) - 1, Int(y.rounded()) - 1, 2, 2, rgb(0x185FA5))
      }
    }),
  Skin(
    name: "Fizz", theme: "Scientific",
    draw: { a, t, bl in
      let gl = rgb(0xDDEFF5)
      let wv = (t >> 2) % 2
      a.r(11, 4, 10, 2, rgb(0xB5D4F4))
      a.r(13, 6, 6, 6, gl)
      for y in 12...27 {
        let hw = 3 + Double(y - 12) * 0.6
        a.r(
          Int((16 - hw).rounded()), y, Int((2 * hw).rounded()), 1,
          y >= 18 ? (y == 27 ? Col.cl : rgb(0xF0997B)) : gl)
      }
      for x in 8..<24 where (x + wv) % 3 == 0 { a.p(Double(x), 18, rgb(0xF5C4B3)) }
      a.face(20, 3, bl)
    },
    overlay: { a, t in
      for k in 0..<3 {
        let y = Double(17 - (t / 2 + k * 4) % 12)
        let x = 14 + Double(k) * 1.5
        if !a.empty(x, y) { a.p(x, y, Col.w) }
      }
    }),
  Skin(
    name: "Jack", theme: "Seasonal",
    draw: { a, t, bl in
      let o = rgb(0xE8822A)
      let od = rgb(0xC2621B)
      let glow = t % 10 < 5 ? rgb(0xFFD25A) : rgb(0xFAC775)
      a.e(10, 19, 7, 7.5, o)
      a.e(22, 19, 7, 7.5, o)
      a.e(16, 19, 8, 8.5, o)
      a.r(9, 14, 1, 10, od)
      a.r(22, 14, 1, 10, od)
      a.r(15, 7, 2, 4, rgb(0x5E7B2E))
      a.e(20, 8, 3, 1.5, rgb(0x7FA83A))
      a.face(16, 3, bl, ec: glow, cheeks: false, mc: glow)
    }),
  Skin(
    name: "Frost", theme: "Seasonal",
    draw: { a, t, bl in
      let s = rgb(0xF4F7FB)
      a.e(16, 22.5, 8, 6, s)
      a.r(10, 28, 12, 1, rgb(0xD6E0EE))
      a.e(16, 12, 6, 5.5, s)
      a.r(11, 3, 10, 4, Col.k)
      a.r(11, 6, 10, 1, Col.cl)
      a.r(9, 7, 14, 1, Col.k)
      a.r(10, 16, 12, 2, Col.cl)
      a.r(19, 18, 2, 4, Col.cl)
      a.r(15, 21, 2, 1, Col.k)
      a.r(15, 24, 2, 1, Col.k)
      a.face(10, 2, bl, eh: 2)
      a.r(16, 12, 3, 1, rgb(0xE8822A))
    },
    overlay: { a, t in
      for (x, o) in [(4, 0), (27, 9), (7, 17), (25, 24)] {
        let y = Double((t / 3 + o) % 30)
        if a.empty(Double(x), y) { a.p(Double(x), y, rgb(0x85B7EB)) }
      }
    }),
]

// Confused: quick double blink plus a sweat drop; the view adds a side-to-side sway.
func frame(_ skin: Skin, t: Int, badge: String?, confused: Bool = false) -> Px {
  var a = Px()
  let k = t % 24
  skin.draw(&a, t, confused ? (k < 2 || (k >= 4 && k < 6)) : t % 45 < 2)
  var o = a.outlined()
  skin.overlay?(&o, t)
  if confused {
    let y = 3 + (t / 4) % 2
    o.r(4, y + 1, 3, 2, rgb(0x85B7EB))
    o.p(5, Double(y), rgb(0x85B7EB))
    o.p(4, Double(y + 1), Col.w)
  }
  if let badge { o.badge(badge) }
  return o
}

func cgImage(_ px: Px) -> CGImage? {
  var bytes = [UInt8](repeating: 0, count: W * W * 4)
  for (i, v) in px.a.enumerated() {
    bytes[i * 4] = UInt8((v >> 16) & 0xFF)
    bytes[i * 4 + 1] = UInt8((v >> 8) & 0xFF)
    bytes[i * 4 + 2] = UInt8(v & 0xFF)
    bytes[i * 4 + 3] = UInt8(v >> 24)
  }
  guard let provider = CGDataProvider(data: Data(bytes) as CFData) else { return nil }
  return CGImage(
    width: W, height: W, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: W * 4,
    space: CGColorSpace(name: CGColorSpace.sRGB)!,
    bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
    provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
}
