import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { execFileSync } from 'node:child_process';
import { resolve } from 'node:path';
const read = path => readFileSync(path, 'utf8');
execFileSync(process.execPath, ['../../scripts/check-air-design.mjs'], { stdio: 'inherit' });
const pages = ['index.html', 'privacy/index.html', '404.html'];
for (const page of pages) {
  const html = read(`dist/${page}`);
  const ids = [...html.matchAll(/\bid="([^"]+)"/g)].map(m => m[1]);
  assert.equal(new Set(ids).size, ids.length, `Duplicate IDs: ${page}`);
  assert.match(html, /https:\/\/roll\.cloakyard\.com/);
  assert.doesNotMatch(html, /localhost|127\.0\.0\.1|CloakDrop|drop\.cloakyard/);
  for (const match of html.matchAll(/\b(?:href|src|srcset)="([^"\s]+)"/g)) {
    const link = match[1];
    if (/^(https?:|data:|mailto:)/.test(link)) continue;
    const url = new URL(link, `https://roll.cloakyard.com/${page === 'index.html' ? '' : page}`);
    const file = url.pathname.endsWith('/') ? url.pathname + 'index.html' : url.pathname;
    const path = resolve('dist', '.' + file);
    assert.ok(existsSync(path), `Missing internal target ${link} in ${page}`);
    if (url.hash && path.endsWith('.html')) {
      assert.ok(read(path).includes(`id="${decodeURIComponent(url.hash.slice(1))}"`), `Missing anchor ${link}`);
    }
  }
}
const home = read('dist/index.html');
assert.match(home, /href="#download"[^>]*>.*?Download CloakRoll/s);
assert.match(home, /https:\/\/github\.com\/cloakyard\/cloakroll\/releases/);
assert.match(read('dist/404.html'), /name="robots" content="noindex"/);
assert.ok(existsSync('dist/sitemap-index.xml'));
console.log('Verified Air provenance, generated routes, anchors, local assets, canonical domain and release destination.');
