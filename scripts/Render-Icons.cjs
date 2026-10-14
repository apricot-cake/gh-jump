// Optional asset regeneration: node Render-Icons.cjs <path-to-sharp-module>.
// The packaged PNGs are committed, so builds do not need Node.js or sharp.
const fs = require('node:fs');
const path = require('node:path');
const sharp = require(process.argv[2] || 'sharp');
const assets = path.resolve(__dirname, '../src/GHJump/Assets');
(async () => {
  for (const filename of fs.readdirSync(path.join(assets, 'Octicons'))) {
    if (!filename.endsWith('.svg')) continue;
    const source = fs.readFileSync(path.join(assets, 'Octicons', filename), 'utf8');
    for (const [theme, color] of [['light', '#24292f'], ['dark', '#f0f6fc']]) {
      const svg = source.replace('<svg ', `<svg fill="${color}" `);
      await sharp(Buffer.from(svg)).resize(64, 64).png().toFile(path.join(assets, 'Icons', filename.replace('.svg', `-${theme}.png`)));
    }
  }
  const appIcon = path.resolve(__dirname, '../design/app-icon.png');
  for (const [name, size] of [['StoreLogo', 50], ['Square44x44Logo', 44], ['Square150x150Logo', 150]]) {
    for (const scale of [100, 125, 150, 200, 400]) {
      const pixels = Math.round(size * scale / 100);
      const suffix = scale === 100 ? '' : `.scale-${scale}`;
      await sharp(appIcon).resize(pixels, pixels).png().toFile(path.join(assets, `${name}${suffix}.png`));
    }
  }
  await sharp(appIcon).resize(64, 64).png().toFile(path.join(assets, 'AppIcon.png'));
  await sharp(appIcon).resize(300, 300).png().toFile(path.resolve(__dirname, '../store/images/icon.png'));
})().catch(error => { console.error(error.message); process.exitCode = 1; });
