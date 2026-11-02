// JS port of Px from Sources/Peep/Sprites.swift. Keep in sync if Px changes.
// Empty pixels are -1 (Swift uses 0). Colors are 0xRRGGBB numbers.
const W = 32, K = 0x2B2118, WH = 0xFFFFFF, PK = 0xF49C9C
function Px() { this.a = new Array(W * W).fill(-1) }
Px.prototype.p = function (x, y, c) { const xi = Math.round(x), yi = Math.round(y); if (xi >= 0 && yi >= 0 && xi < W && yi < W) this.a[yi * W + xi] = c }
Px.prototype.get = function (x, y) { return this.a[y * W + x] }
Px.prototype.r = function (x, y, w, h, c) { for (let j = 0; j < h; j++) for (let i = 0; i < w; i++) this.p(x + i, y + j, c) }
Px.prototype.e = function (cx, cy, rx, ry, c) { for (let y = 0; y < W; y++) for (let x = 0; x < W; x++) { const dx = (x + .5 - cx) / rx, dy = (y + .5 - cy) / ry; if (dx * dx + dy * dy <= 1) this.a[y * W + x] = c } }
Px.prototype.empty = function (x, y) { const xi = Math.round(x), yi = Math.round(y); return xi >= 0 && yi >= 0 && xi < W && yi < W && this.a[yi * W + xi] < 0 }
Px.prototype.eye = function (x, y, bl, c, h) { if (bl) this.r(x, y + h - 1, 2, 1, c); else { this.r(x, y, 2, h, c); this.p(x, y, WH) } }
Px.prototype.face = function (y, g, bl, eh) { eh = eh || 3; const L = 16 - g - 2, R = 30 - L; this.eye(L, y, bl, K, eh); this.eye(R, y, bl, K, eh); this.r(L - 2, y + eh, 2, 1, PK); this.r(R + 2, y + eh, 2, 1, PK); const yy = y + eh + 1; this.r(14, yy, 1, 1, K); this.r(17, yy, 1, 1, K); this.r(15, yy + 1, 2, 1, K) }
Px.prototype.outlined = function () { const a = this.a, o = a.slice(); for (let i = 0; i < W * W; i++) if (a[i] < 0) { const x = i % W, y = (i / W) | 0; if ((x > 0 && a[i - 1] >= 0) || (x < W - 1 && a[i + 1] >= 0) || (y > 0 && a[i - W] >= 0) || (y < W - 1 && a[i + W] >= 0)) o[i] = K } const o2 = o.slice(); for (let i = 0; i < W * W; i++) if (o[i] < 0) { const x = i % W, y = (i / W) | 0; outer: for (let dy = -1; dy <= 1; dy++) for (let dx = -1; dx <= 1; dx++) { const X = x + dx, Y = y + dy; if (X >= 0 && Y >= 0 && X < W && Y < W && o[Y * W + X] >= 0) { o2[i] = WH; break outer } } } const n = new Px(); n.a = o2; return n }
// Same edge rule as selfCheck() in main.swift: the outlined sprite must leave the border row/column empty.
function touchesEdge(o) { for (let i = 0; i < W; i++) if (o.a[i] >= 0 || o.a[(W - 1) * W + i] >= 0 || o.a[i * W] >= 0 || o.a[i * W + W - 1] >= 0) return true; return false }

// skins: [{ name, draw(a, t, bl), overlay?(a, t) }]. Canvases: id `c<i>` (big) and `s<i>` (small).
function run(skins) {
  skins.forEach((s, k) => { for (let t = 0; t < 120; t++) { const a = new Px(); s.draw(a, t, t % 45 < 2); if (touchesEdge(a.outlined())) { document.getElementById('w' + k).textContent = 'Touches the edge at t=' + t; break } } })
  let t = 0
  setInterval(() => {
    skins.forEach((s, k) => {
      const a = new Px(); s.draw(a, t, t % 45 < 2); const o = a.outlined(); if (s.overlay) s.overlay(o, t)
      for (const c of [document.getElementById('c' + k), document.getElementById('s' + k)]) {
        const g = c.getContext('2d'), sc = c.width / W; g.clearRect(0, 0, c.width, c.height)
        for (let i = 0; i < W * W; i++) { const v = o.a[i]; if (v < 0) continue; g.fillStyle = '#' + v.toString(16).padStart(6, '0'); g.fillRect((i % W) * sc, ((i / W) | 0) * sc, sc, sc) }
      }
    }); t++
  }, 100)
}
