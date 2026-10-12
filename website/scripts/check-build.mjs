import { readFile, access } from 'node:fs/promises';
import { resolve } from 'node:path';

const pages = ['index.html', 'privacy/index.html'];
for (const page of pages) {
  const html = await readFile(resolve('dist', page), 'utf8');
  if (!html.includes('lang="ja"') || !html.includes('https://apricot-cake.com/gh-jump')) {
    throw new Error(`Missing language or canonical URL in ${page}`);
  }
  for (const match of html.matchAll(/(?:src|href)="(\/gh-jump\/[^"?#]+)"/g)) {
    const asset = match[1].slice('/gh-jump/'.length);
    await access(resolve('dist', asset.endsWith('/') ? `${asset}index.html` : asset));
  }
}
console.log('Built pages and local links validated.');
