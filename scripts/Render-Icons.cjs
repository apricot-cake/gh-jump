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
  const repo = fs.readFileSync(path.join(assets, 'Octicons/repo.svg'), 'utf8').replace('<svg ', '<svg fill="#ffffff" ');
  for (const [name, size] of [['StoreLogo', 50], ['Square44x44Logo', 44], ['Square150x150Logo', 150]]) {
    const icon = await sharp(Buffer.from(repo)).resize(Math.round(size * 0.65), Math.round(size * 0.65)).png().toBuffer();
    await sharp({ create: { width: size, height: size, channels: 4, background: '#0969da' } }).composite([{ input: icon, gravity: 'centre' }]).png().toFile(path.join(assets, `${name}.png`));
  }
})().catch(error => { console.error(error.message); process.exitCode = 1; });
