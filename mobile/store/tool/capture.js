// Captures raw screenshots from the web build (served on :8765) by tapping
// semantics labels. SEED=<seed.json> node capture.js <out> <w> <h> <dpr> <dark 0|1> <plan.json>
// Usage: node nav.js <outdir> <width> <height> <dpr> <dark 0|1> <plan.json>
const { chromium } = require('playwright');
const fs = require('fs');
(async () => {
  const [out, w, h, dpr, dark, planFile] = process.argv.slice(2);
  const seed = JSON.parse(fs.readFileSync(process.env.SEED, 'utf8'));
  if (dark === '1') seed['flutter.theme_mode'] = JSON.stringify('dark');
  const plan = JSON.parse(fs.readFileSync(planFile, 'utf8'));
  const b = await chromium.launch();
  const ctx = await b.newContext({ viewport: { width: +w, height: +h }, deviceScaleFactor: +dpr,
    colorScheme: dark === '1' ? 'dark' : 'light' });
  await ctx.addInitScript(s => { if (!sessionStorage.getItem('seeded')) { localStorage.clear(); for (const [k, v] of Object.entries(s)) localStorage.setItem(k, v); sessionStorage.setItem('seeded', '1'); } }, seed);
  const p = await ctx.newPage();
  p.on('pageerror', e => console.log('PAGEERROR', e.message.slice(0, 200)));
  const sem = async () => { await p.evaluate(() => { const e = document.querySelector('flt-semantics-placeholder'); if (e) e.click(); }); await p.waitForTimeout(400); };
  const tap = async (text, nth = 0) => {
    await sem();
    const box = await p.evaluate(([t, n]) => {
      const els = [...document.querySelectorAll('flt-semantics')].filter(e => {
        const l = (e.getAttribute('aria-label') || '').trim();
        const c = (e.textContent || '').trim();
        return l === t || c === t || l.startsWith(t + '\n') || (t.startsWith('~') && (l.includes(t.slice(1)) || c.includes(t.slice(1))));
      });
      els.sort((a, b) => a.getBoundingClientRect().width * a.getBoundingClientRect().height - b.getBoundingClientRect().width * b.getBoundingClientRect().height);
      const e = els[n]; if (!e) return null;
      const r = e.getBoundingClientRect(); return { x: r.x + r.width / 2, y: r.y + r.height / 2 };
    }, [text, nth]);
    if (!box) { console.log('NOT FOUND', text); return false; }
    await p.mouse.click(box.x, box.y); await p.waitForTimeout(900); return true;
  };
  for (const s of plan) {
    if (s.goto !== undefined) { await p.goto('http://localhost:8765/' + s.goto, { waitUntil: 'networkidle' }); await p.waitForTimeout(s.wait ?? 3000); }
    if (s.tap) await tap(s.tap, s.nth ?? 0);
    if (s.click) { await p.mouse.click(s.click[0], s.click[1]); await p.waitForTimeout(900); }
    if (s.wheel) { await p.mouse.move(s.wheel[0], s.wheel[1]); await p.mouse.wheel(0, s.wheel[2]); await p.waitForTimeout(800); }
    if (s.type) { await p.keyboard.type(s.type, { delay: 30 }); await p.waitForTimeout(800); }
    if (s.wait && s.goto === undefined) await p.waitForTimeout(s.wait);
    if (s.dump) { await sem(); console.log(await p.$$eval('flt-semantics', els => [...new Set(els.map(e => (e.getAttribute('aria-label') || '').trim()).filter(Boolean))].slice(0, 80).join(' | '))); }
    if (s.shot) { await p.screenshot({ path: `${out}/${s.shot}.png` }); console.log('shot', s.shot); }
  }
  await b.close();
})();
