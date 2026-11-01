// Store screenshot composer: raw app screenshots -> captioned store images.
// Usage: node compose.js <raw_phone_dir> <raw_tablet_dir> <out_dir> <fonts_dir> <icon_png>
// (raw shots are produced from the web build with the same app UI.)
const { chromium } = require('playwright');
const fs = require('fs');
const path = require('path');
const [rawPhone, rawTablet, out, fonts, icon] = process.argv.slice(2);

const captions = {
  '01_analysis': ['Kural dışı hamleyi anında yakala', 'Karnedeki her hamle FIDE kurallarına göre denetlenir'],
  '03_claim': ['Beraberlik talebini saniyede doğrula', 'Üç tekrar ve 50 hamle; niyet edilen hamle dahil'],
  '02_illegal': ['Ne yapacağın, maddesiyle', '7.5 ceza adımları: klasik, hızlı, yıldırım'],
  '04_keyboard': ['Karneden hızlı giriş', 'Türkçe notasyon klavyesi ve yasal hamle önerileri'],
  '06_compare': ['İki karneyi karşılaştır', 'Ayrışan ve eksik yazılan hamleyi hemen bul'],
  '05_home': ['İnternetsiz. Hesapsız.', 'Oyunların ve notların yalnızca cihazında kalır'],
  '08_analysis_dark': ['Salonun ışığına uygun', 'Koyu tema ve büyük yazı desteği'],
  '07_paywall': ['Turnuva Haftası ile Pro', 'Haftalık, aylık ya da yıllık · istediğin an iptal'],
};
const order = ['01_analysis', '03_claim', '02_illegal', '04_keyboard', '06_compare', '05_home', '08_analysis_dark', '07_paywall'];

const targets = [
  { name: 'ios-iphone-6.9', w: 1290, h: 2796, raw: rawPhone, head: 150, title: 96, sub: 50, gap: 70, pad: 100 },
  { name: 'ios-ipad-13', w: 2048, h: 2732, raw: rawTablet, head: 150, title: 104, sub: 54, gap: 80, pad: 130 },
  { name: 'android-phone', w: 1080, h: 1920, raw: rawPhone, head: 90, title: 64, sub: 34, gap: 44, pad: 60 },
];

const b64 = f => fs.readFileSync(f).toString('base64');
const fontCss = `
@font-face{font-family:Fraunces;src:url(data:font/ttf;base64,${b64(path.join(fonts, 'Fraunces.ttf'))})}
@font-face{font-family:Inter;src:url(data:font/ttf;base64,${b64(path.join(fonts, 'Inter.ttf'))})}`;

function html(t, img, [title, sub]) {
  return `<!doctype html><html><head><meta charset="utf-8"><style>${fontCss}
  html,body{margin:0;width:${t.w}px;height:${t.h}px;overflow:hidden}
  body{background:radial-gradient(120% 80% at 50% 0%,#5a4430 0%,#2a2018 60%,#1b1511 100%);
       font-family:Inter;color:#f6efe4;display:flex;flex-direction:column;align-items:center}
  h1{font-family:Fraunces;font-weight:700;font-size:${t.title}px;line-height:1.08;margin:${t.head}px ${t.pad}px 0;text-align:center;letter-spacing:-.5px}
  p{font-size:${t.sub}px;line-height:1.3;margin:${t.title * 0.32}px ${t.pad}px 0;text-align:center;color:#e3cfae}
  .shot{margin-top:${t.gap}px;flex:1;min-height:0;display:flex;align-items:flex-start;justify-content:center;width:100%}
  .frame{height:calc(100% - ${t.pad * 0.6}px);border-radius:${t.w * 0.045}px;overflow:hidden;
         box-shadow:0 ${t.w * 0.02}px ${t.w * 0.06}px rgba(0,0,0,.55),0 0 0 ${Math.round(t.w * 0.008)}px #0e0b09}
  .frame img{height:100%;display:block}
  </style></head><body><h1>${title}</h1><p>${sub}</p>
  <div class="shot"><div class="frame"><img src="data:image/png;base64,${img}"></div></div></body></html>`;
}

(async () => {
  const b = await chromium.launch();
  for (const t of targets) {
    const dir = path.join(out, t.name);
    fs.mkdirSync(dir, { recursive: true });
    const p = await b.newPage({ viewport: { width: t.w, height: t.h }, deviceScaleFactor: 1 });
    let i = 0;
    for (const key of order) {
      const f = path.join(t.raw, key + '.png');
      if (!fs.existsSync(f)) continue;
      if (t.name.startsWith('ios-ipad') && key === '04_keyboard') continue;
      i++;
      await p.setContent(html(t, b64(f), captions[key]), { waitUntil: 'load' });
      await p.waitForTimeout(150);
      await p.screenshot({ path: path.join(dir, `${String(i).padStart(2, '0')}_${key}.png`), type: 'png' });
    }
    await p.close();
  }
  // Google Play feature graphic 1024x500.
  const p = await b.newPage({ viewport: { width: 1024, height: 500 }, deviceScaleFactor: 1 });
  const board = b64(path.join(rawPhone, '01_analysis.png'));
  await p.setContent(`<!doctype html><html><head><meta charset="utf-8"><style>${fontCss}
   body{margin:0;width:1024px;height:500px;overflow:hidden;font-family:Inter;color:#f6efe4;
     background:radial-gradient(120% 120% at 20% 0%,#5a4430 0%,#2a2018 60%,#1b1511 100%);display:flex;align-items:center}
   .l{padding-left:64px;width:520px}
   .icon{width:112px;height:112px;border-radius:26px;box-shadow:0 10px 30px rgba(0,0,0,.5)}
   h1{font-family:Fraunces;font-size:62px;margin:22px 0 8px;line-height:1}
   p{font-size:26px;color:#e3cfae;margin:0;line-height:1.3}
   .r{flex:1;height:500px;position:relative}
   .r img{position:absolute;right:60px;top:56px;width:400px;border-radius:22px;box-shadow:0 18px 50px rgba(0,0,0,.6)}
   </style></head><body><div class="l"><img class="icon" src="data:image/png;base64,${b64(icon)}">
   <h1>Hakem Masası</h1><p>Satranç hakeminin analiz masası.<br>Kural dışı hamle, talep, süre aşımı.</p></div>
   <div class="r"><img src="data:image/png;base64,${board}" style="object-fit:cover;object-position:top;height:388px"></div></body></html>`, { waitUntil: 'load' });
  await p.waitForTimeout(150);
  fs.mkdirSync(path.join(out, 'android-graphics'), { recursive: true });
  await p.screenshot({ path: path.join(out, 'android-graphics', 'feature_graphic_1024x500.png') });
  await b.close();
})();
