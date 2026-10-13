// Regenerates every launcher icon and splash image from app/assets/brand/reborn-mark.svg.
// Run from the repo root with Playwright installed: node app/tool/brand_icons.js
// (iOS app icons then need their alpha removed, e.g. ImageMagick: -background '#14110E' -alpha remove -alpha off).
const { chromium } = require('playwright'); const fs = require('fs'); const path = require('path');
const APP = path.resolve(__dirname, '..'), WEB = path.resolve(__dirname, '../../web');
const UMBER = '#14110E';
const markSvg = fs.readFileSync(`${APP}/assets/brand/reborn-mark.svg`, 'utf8');
const inner = markSvg.replace(/^[\s\S]*?<svg[^>]*>/, '').replace(/<\/svg>\s*$/, '');
const noGlow = inner.replace(/<circle[^>]*url\(#glow\)[^>]*\/>/, '');
const font = 'data:font/ttf;base64,' + fs.readFileSync(`${APP}/assets/fonts/Fraunces-SemiBold.ttf`).toString('base64');
// Mark scaled about the canvas centre (s=1 is the mark as drawn on its 1024 canvas).
const mark = (s, body = inner) => `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024" width="100%" height="100%"><g transform="translate(512 512) scale(${s}) translate(-512 -512)">${body}</g></svg>`;
const splashBody = `${inner}<text x="512" y="960" font-family="Fraunces" font-size="168" font-weight="600" text-anchor="middle" fill="#F2E8D8">Reborn</text>`;
const splashSrc = (fontUrl) => `<svg xmlns="http://www.w3.org/2000/svg" viewBox="162 150 700 900"><style>@font-face{font-family:Fraunces;src:url(${fontUrl})}</style>${splashBody}</svg>`;
fs.writeFileSync(`${APP}/assets/brand/reborn-splash.svg`, splashSrc('../fonts/Fraunces-SemiBold.ttf') + '\n');
const jobs = [];
const job = (out, w, h, svg, bg = 'transparent', radius = '0') => jobs.push({ out, w, h, svg, bg, radius });
const res = `${APP}/android/app/src/main/res`;
const dens = { mdpi: 1, hdpi: 1.5, xhdpi: 2, xxhdpi: 3, xxxhdpi: 4 };
for (const [d, k] of Object.entries(dens)) {
  job(`${res}/mipmap-${d}/ic_launcher.png`, 48 * k, 48 * k, mark(1), UMBER, '22%');
  job(`${res}/mipmap-${d}/ic_launcher_round.png`, 48 * k, 48 * k, mark(0.92), UMBER, '50%');
  job(`${res}/mipmap-${d}/ic_launcher_foreground.png`, 108 * k, 108 * k, mark(0.88));
  job(`${res}/mipmap-${d}/ic_launcher_monochrome.png`, 108 * k, 108 * k, mark(0.88, noGlow));
  job(`${res}/drawable-${d}/splash_icon.png`, 288 * k, 288 * k, mark(1));
  job(`${res}/drawable-${d}/splash.png`, 140 * k, 180 * k, splashSrc(font).replace('<svg ', '<svg width="100%" height="100%" '));
}
const ios = `${APP}/ios/Runner/Assets.xcassets`;
for (const i of JSON.parse(fs.readFileSync(`${ios}/AppIcon.appiconset/Contents.json`)).images) {
  const px = Math.round(parseFloat(i.size) * parseInt(i.scale));
  job(`${ios}/AppIcon.appiconset/${i.filename}`, px, px, mark(1.05), UMBER);
}
for (const [f, k] of [['LaunchImage.png', 1], ['LaunchImage@2x.png', 2], ['LaunchImage@3x.png', 3]])
  job(`${ios}/LaunchImage.imageset/${f}`, 140 * k, 180 * k, splashSrc(font).replace('<svg ', '<svg width="100%" height="100%" '));
job(`${APP}/web/favicon.png`, 32, 32, mark(1.3, noGlow), UMBER, '22%');
job(`${APP}/web/icons/Icon-192.png`, 192, 192, mark(1), UMBER, '22%');
job(`${APP}/web/icons/Icon-512.png`, 512, 512, mark(1), UMBER, '22%');
job(`${APP}/web/icons/Icon-maskable-192.png`, 192, 192, mark(0.85), UMBER);
job(`${APP}/web/icons/Icon-maskable-512.png`, 512, 512, mark(0.85), UMBER);
job(`${WEB}/app/apple-icon.png`, 180, 180, mark(1.05), UMBER);
// Web favicon as SVG: rounded umber tile, mark without glow so it stays crisp at 16px.
fs.writeFileSync(`${WEB}/app/icon.svg`, `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024"><rect width="1024" height="1024" rx="224" fill="${UMBER}"/><g transform="translate(512 512) scale(1.3) translate(-512 -488)">${noGlow.replace(/\s*\n\s*/g, '')}</g></svg>\n`);
(async () => {
  const b = await chromium.launch(); const p = await b.newPage();
  for (const j of jobs) {
    await p.setViewportSize({ width: Math.round(j.w), height: Math.round(j.h) });
    await p.setContent(`<html><body style="margin:0;background:transparent"><div style="width:${j.w}px;height:${j.h}px;background:${j.bg};border-radius:${j.radius};overflow:hidden">${j.svg}</div></body></html>`, { waitUntil: 'load' });
    await p.evaluate(() => document.fonts.ready);
    fs.mkdirSync(path.dirname(j.out), { recursive: true });
    await p.screenshot({ path: j.out, omitBackground: true });
  }
  await b.close(); console.log('wrote', jobs.length, 'images');
})();
