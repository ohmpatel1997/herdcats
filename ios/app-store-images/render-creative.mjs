import {copyFile, mkdir, mkdtemp, rm, readFile} from 'node:fs/promises';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {parseArgs} from 'node:util';

// Renders App Store creatives and/or the site OG card.
// Usage:
//   node render-creative.mjs --og-only
//   node render-creative.mjs [--input=<dir with iPhone 03_spaces.png>] [--output=<dir>]
// iPad and iPhone Duo screens come from ios/maestro/screenshots-output/{ipad,iphone-duo/inner}.
const packageDir = path.dirname(fileURLToPath(import.meta.url));
const iosDir = path.dirname(packageDir);
const repoDir = path.dirname(iosDir);
const {values} = parseArgs({
  options: {
    input: {type: 'string'},
    output: {type: 'string'},
    'og-only': {type: 'boolean', default: false},
  },
});
const ogOnly = values['og-only'] === true;
const input = path.resolve(values.input || path.join(iosDir, 'maestro/screenshots-output/iPhone_17_Pro_Max'));
const parent = path.resolve(values.output || path.join(iosDir, 'maestro/app-store-output'));
const ogPath = path.join(repoDir, 'web/public/og.png');

const {bundle} = await import('@remotion/bundler');
const {renderStill, selectComposition, openBrowser} = await import('@remotion/renderer');
const pngSize = async file => {
  const bytes = await readFile(file);
  if (bytes.subarray(0, 8).toString('hex') !== '89504e470d0a1a0a') throw new Error(`${file}: invalid PNG.`);
  return {width: bytes.readUInt32BE(16), height: bytes.readUInt32BE(20)};
};

let inputProps = {};
const cache = path.join(packageDir, '.cache');
await mkdir(cache, {recursive: true});
const work = await mkdtemp(path.join(cache, 'creative-'));
const publicDir = path.join(work, 'public');
await mkdir(publicDir, {recursive: true});
await copyFile(path.join(repoDir, 'web/public/assets/logo.png'), path.join(publicDir, 'logo.png'));

const phoneSource = ogOnly
  ? path.join(repoDir, 'assets/screenshots/01-spaces.png')
  : path.join(input, '03_spaces.png');
const sourceFiles = {
  phone: phoneSource,
  ipad: path.join(iosDir, 'maestro/screenshots-output/ipad/03_spaces.png'),
  duo: path.join(iosDir, 'maestro/screenshots-output/iphone-duo/inner/03_spaces.png'),
};
const sizes = {};
for (const [name, file] of Object.entries(sourceFiles)) {
  sizes[name] = await pngSize(file);
  const {width, height} = sizes[name];
  const ratio = height / width;
  const ok = name === 'phone' ? width >= 600 && ratio >= 1.9 && ratio <= 2.3 : width >= 1600 && ratio >= 0.6 && ratio <= 0.85;
  if (!ok) throw new Error(`${name}: unexpected capture size ${width}x${height} (${file}).`);
  await copyFile(file, path.join(publicDir, `${name}.png`));
}
inputProps = {sources: {phone: 'phone.png', ipad: 'ipad.png', duo: 'duo.png'}, sizes};
if (!ogOnly) await mkdir(parent, {recursive: true});

const output = ogOnly
  ? null
  : await mkdtemp(path.join(parent, `creative-${new Date().toISOString().replace(/[:.]/g, '-')}-`));

const jobs = ogOnly
  ? [['OgCard', ogPath]]
  : [
      ['ProductHeader', path.join(output, 'product-page-header.png')],
      ['SearchResult', path.join(output, 'search-results.png')],
    ];

let browser;
try {
  const serveUrl = await bundle({
    entryPoint: path.join(packageDir, 'src/creative-index.jsx'),
    publicDir,
    outDir: path.join(work, 'bundle'),
    webpackOverride: c => ({
      ...c,
      resolve: {...c.resolve, extensions: ['.ts', '.tsx', ...(c.resolve?.extensions || [])]},
    }),
  });
  browser = await openBrowser('chrome');
  for (const [id, file] of jobs) {
    const composition = await selectComposition({serveUrl, id, inputProps, puppeteerInstance: browser});
    await renderStill({
      serveUrl,
      composition,
      inputProps,
      output: file,
      imageFormat: 'png',
      frame: 0,
      puppeteerInstance: browser,
    });
    console.log(`${id}: ${file}`);
  }
  if (ogOnly) {
    const {width, height} = await pngSize(ogPath);
    if (width !== 1200 || height !== 630) {
      throw new Error(`og.png: expected 1200x630, got ${width}x${height}`);
    }
  }
} finally {
  if (browser) await browser.close({silent: true});
  await rm(work, {recursive: true, force: true});
}
