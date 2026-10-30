// Lays out GUI trees exported by tools/lune/gui_export.luau as HTML and screenshots them, to look
// at the game's UI and billboard ads offline (Chromium via Playwright).
//
//   node tools/preview/gui.mjs <guis.json> <out.png> [columns]
//
// Approximates Roblox: UDim2 sizes and positions, AnchorPoint, Rotation, SizeConstraint,
// UICorner, UIStroke, UIGradient, UIPadding, UIListLayout, UIGridLayout, TextScaled (fits the
// text to its box). Fonts: Inter stands in for Gotham and Fredoka One.
import fs from "node:fs";
import { chromium } from "playwright";

const [inPath, outPath, colsArg] = process.argv.slice(2);
const guis = JSON.parse(fs.readFileSync(inPath, "utf8"));
const columns = Number(colsArg || 2);

const page = `<!doctype html><html><head><meta charset="utf-8"><style>
body { margin: 0; background: #2a2d33; font-family: Inter, sans-serif; }
#sheet { display: flex; flex-wrap: wrap; gap: 16px; padding: 16px; width: max-content; max-width: ${columns} * 1000px; }
.card { position: relative; background: #555; }
.card > .label { position: absolute; top: -14px; left: 0; color: #aaa; font: 11px monospace; }
.n { position: absolute; box-sizing: border-box; }
.t { position: absolute; inset: 0; display: flex; overflow: hidden; line-height: 1.05; }
</style></head><body><div id="sheet"></div>
<script>
const guis = ${JSON.stringify(guis)};
const columns = ${columns};
function fontOf(n) {
  const f = (n.font || "") + " " + (n.fontEnum || "");
  if (/Code|Mono/.test(f)) return ["JetBrains Mono", 700];
  if (/PermanentMarker/.test(f)) return ["FreeSans", 700];
  if (/Fredoka/.test(f)) return ["Inter Display", 800];
  if (/Black/.test(f) || /Heavy/.test(f)) return ["Inter", 900];
  if (/Bold/.test(f)) return ["Inter", 700];
  if (/Medium/.test(f)) return ["Inter", 500];
  return ["Inter", 400];
}
function rgba(c, t) { return "rgba(" + Math.round(c[0]*255) + "," + Math.round(c[1]*255) + "," + Math.round(c[2]*255) + "," + (1 - (t||0)) + ")"; }
function gradientCss(n) {
  const g = n.gradient, base = n.bg || [1,1,1];
  const stops = [];
  const times = new Set(g.colors.map(c => c[0]).concat(g.transp.map(t => t[0])));
  const sorted = [...times].sort((a,b) => a-b);
  const lerp = (arr, t, k) => { for (let i = 0; i < arr.length - 1; i++) { const a = arr[i], b = arr[i+1]; if (t >= a[0] && t <= b[0]) { const f = (t - a[0]) / Math.max(1e-6, b[0] - a[0]); return a[k] + (b[k] - a[k]) * f; } } return arr[arr.length-1][k]; };
  for (const t of sorted) {
    const c = [lerp(g.colors, t, 1) * base[0], lerp(g.colors, t, 2) * base[1], lerp(g.colors, t, 3) * base[2]];
    const tr = 1 - (1 - lerp(g.transp, t, 1)) * (1 - (n.bgT || 0));
    stops.push(rgba(c, tr) + " " + (t*100) + "%");
  }
  return "linear-gradient(" + (g.rot + 90) + "deg," + stops.join(",") + ")";
}
function place(n, parentEl, pw, ph, slot) {
  if (n.visible === false) return;
  const sxBase = n.yy ? ph : pw, syBase = n.xx ? pw : ph;
  let w = n.size[0] * sxBase + n.size[1];
  let h = n.size[2] * syBase + n.size[3];
  if (n.autoX && n.text !== undefined) w = Math.max(w, n.text.length * h * 0.5 + 8);
  let x, y;
  if (slot) { x = slot.x; y = slot.y; if (slot.w !== undefined) { w = slot.w; h = slot.h; } }
  else { x = n.pos[0] * pw + n.pos[1] - n.anchor[0] * w; y = n.pos[2] * ph + n.pos[3] - n.anchor[1] * h; }
  const el = document.createElement("div");
  el.className = "n";
  Object.assign(el.style, { left: x + "px", top: y + "px", width: w + "px", height: h + "px", zIndex: n.z || 1 });
  if (n.rot) el.style.transform = "rotate(" + n.rot + "deg)";
  if (n.clips) el.style.overflow = "hidden";
  const bgVisible = n.bgT < 1 && !(n.class === "TextLabel" && n.bgT >= 1);
  if (n.gradient && n.bgT < 1) el.style.background = gradientCss(n);
  else if (bgVisible) el.style.background = rgba(n.bg, n.bgT);
  if (n.corner) el.style.borderRadius = (n.corner[0] * Math.min(w, h) + n.corner[1]) + "px";
  if (n.stroke && n.text === undefined) el.style.outline = n.stroke.thick + "px solid " + rgba(n.stroke.color, n.stroke.t);
  if (n.image !== undefined) { el.style.background = "repeating-linear-gradient(45deg,#666,#666 10px,#777 10px,#777 20px)"; el.innerHTML = '<div style="color:#fff;font:bold 14px Inter;padding:4px">IMAGE ' + n.image + '</div>'; }
  if (n.text !== undefined && n.text !== "") {
    const t = document.createElement("div");
    t.className = "t";
    const [fam, wt] = fontOf(n);
    const xa = { Left: "flex-start", Right: "flex-end", Center: "center" }[n.xAlign] || "center";
    const ya = { Top: "flex-start", Bottom: "flex-end", Center: "center" }[n.yAlign] || "center";
    Object.assign(t.style, { fontFamily: "'" + fam + "', 'Noto Color Emoji', sans-serif", fontWeight: wt, color: rgba(n.textColor, n.textT), justifyContent: xa, alignItems: ya, textAlign: n.xAlign === "Left" ? "left" : n.xAlign === "Right" ? "right" : "center", whiteSpace: (n.wrapped || n.scaled) ? "pre-wrap" : "pre" });
    if (n.stroke) { const s = n.stroke.thick, c = rgba(n.stroke.color, n.stroke.t); t.style.textShadow = [[s,0],[-s,0],[0,s],[0,-s],[s,s],[-s,-s],[s,-s],[-s,s]].map(([a,b]) => a + "px " + b + "px 0 " + c).join(","); }
    const span = document.createElement("span");
    span.textContent = n.text;
    t.appendChild(span);
    t.dataset.scaled = n.scaled ? "1" : "";
    t.style.fontSize = n.scaled ? "100px" : (n.textSize || 14) + "px";
    el.appendChild(t);
  }
  parentEl.appendChild(el);
  // children: inside the padding, laid out by a list or grid if there is one
  let cx = 0, cy = 0, cw = w, ch = h;
  if (n.padding) { const p = n.padding; const l = p[0]*w + p[1], r = p[2]*w + p[3], tp = p[4]*h + p[5], b = p[6]*h + p[7]; cx = l; cy = tp; cw = w - l - r; ch = h - tp - b; }
  const inner = document.createElement("div");
  inner.className = "n";
  Object.assign(inner.style, { left: cx + "px", top: cy + "px", width: cw + "px", height: ch + "px" });
  el.appendChild(inner);
  const kids = (Array.isArray(n.children) ? n.children : []).filter(c => c.visible !== false);
  if (n.list) {
    kids.sort((a, b) => (a.order || 0) - (b.order || 0));
    const horiz = n.list.dir === "Horizontal";
    const gap = horiz ? n.list.pad[0] * cw + n.list.pad[1] : n.list.pad[0] * ch + n.list.pad[1];
    const sizes = kids.map(k => { const kw = k.size[0] * (k.yy ? ch : cw) + k.size[1]; const kh = k.size[2] * (k.xx ? cw : ch) + k.size[3]; return [k.autoX && k.text !== undefined ? Math.max(kw, k.text.length * kh * 0.5 + 8) : kw, kh]; });
    const total = sizes.reduce((s, z) => s + (horiz ? z[0] : z[1]), 0) + gap * Math.max(0, kids.length - 1);
    let at = 0;
    if (horiz && n.list.h === "Center") at = (cw - total) / 2; else if (horiz && n.list.h === "Right") at = cw - total;
    if (!horiz && n.list.v === "Center") at = (ch - total) / 2; else if (!horiz && n.list.v === "Bottom") at = ch - total;
    kids.forEach((k, i) => {
      const [kw, kh] = sizes[i];
      let sx = horiz ? at : 0, sy = horiz ? 0 : at;
      if (!horiz && n.list.h === "Center") sx = (cw - kw) / 2; else if (!horiz && n.list.h === "Right") sx = cw - kw;
      if (horiz && n.list.v === "Center") sy = (ch - kh) / 2; else if (horiz && n.list.v === "Bottom") sy = ch - kh;
      place(k, inner, cw, ch, { x: sx, y: sy, w: kw, h: kh });
      at += (horiz ? kw : kh) + gap;
    });
  } else if (n.grid) {
    kids.sort((a, b) => (a.order || 0) - (b.order || 0));
    const g = n.grid; const kw = g.cell[0] * cw + g.cell[1], kh = g.cell[2] * ch + g.cell[3];
    const gx = g.pad[0] * cw + g.pad[1], gy = g.pad[2] * ch + g.pad[3];
    const per = Math.max(1, Math.floor((cw + gx) / (kw + gx)));
    kids.forEach((k, i) => place(k, inner, cw, ch, { x: (i % per) * (kw + gx), y: Math.floor(i / per) * (kh + gy), w: kw, h: kh }));
  } else {
    for (const k of kids) place(k, inner, cw, ch, null);
  }
}
const sheet = document.getElementById("sheet");
sheet.style.maxWidth = (columns * 1000) + "px";
for (const g of guis) {
  const card = document.createElement("div");
  card.className = "card";
  Object.assign(card.style, { width: g.w + "px", height: g.h + "px", marginTop: "14px" });
  card.innerHTML = '<div class="label">' + g.name + '</div>';
  if (g.bg) card.style.background = g.bg;
  sheet.appendChild(card);
  const root = document.createElement("div");
  root.className = "n";
  Object.assign(root.style, { left: 0, top: 0, width: g.w + "px", height: g.h + "px", overflow: "hidden" });
  card.appendChild(root);
  place(g.tree, root, g.w, g.h, null);
}
// fit TextScaled text to its box
document.fonts.ready.then(() => {
  for (const t of document.querySelectorAll(".t")) {
    if (!t.dataset.scaled) continue;
    let lo = 2, hi = 160;
    while (hi - lo > 1) {
      const mid = (lo + hi) / 2;
      t.style.fontSize = mid + "px";
      const s = t.firstChild;
      if (s.offsetHeight <= t.clientHeight + 1 && s.offsetWidth <= t.clientWidth + 1 && t.scrollWidth <= t.clientWidth + 1) lo = mid; else hi = mid;
    }
    t.style.fontSize = lo + "px";
  }
  document.body.dataset.ready = "1";
});
</script></body></html>`;

const browser = await chromium.launch();
const tab = await browser.newPage({ viewport: { width: 1200, height: 800 } });
tab.on("pageerror", (e) => console.error("page error:", e.message));
await tab.setContent(page);
await tab.waitForSelector("body[data-ready='1']", { state: "attached", timeout: 120000 });
await tab.screenshot({ path: outPath, fullPage: true });
await browser.close();
console.log("wrote", outPath);
