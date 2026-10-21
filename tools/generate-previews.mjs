import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));
const root = path.resolve(here, '..');
const schemes = JSON.parse(fs.readFileSync(path.join(root, 'schemes.json'), 'utf8'));
const outDir = path.join(root, 'previews');
fs.mkdirSync(outDir, { recursive: true });

function slug(name) {
  return name.toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/^-|-$/g, '');
}
function xml(value) {
  return String(value).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
}
function mix(top, bottom, ratio) {
  const ch = (x, y) => Math.round(parseInt(y, 16) + ratio * (parseInt(x, 16) - parseInt(y, 16))).toString(16).padStart(2, '0');
  return '#' + ch(top.slice(1, 3), bottom.slice(1, 3)) + ch(top.slice(3, 5), bottom.slice(3, 5)) + ch(top.slice(5, 7), bottom.slice(5, 7));
}

const swatchKeys = [
  'black', 'red', 'green', 'yellow', 'blue', 'purple', 'cyan', 'white',
  'brightBlack', 'brightRed', 'brightGreen', 'brightYellow',
  'brightBlue', 'brightPurple', 'brightCyan', 'brightWhite'
];

const lines = [
  { parts: [['PS C:\\dev>', 'green'], [' git status', 'foreground']] },
  { parts: [['On branch main', 'brightBlack']] },
  { parts: [['✓', 'green'], [' build complete', 'foreground'], [' in 1.24s', 'brightBlack']] },
  { parts: [['info', 'blue'], ['  watching for changes...', 'foreground']] },
  { parts: [['warn', 'yellow'], ['  unused variable ', 'foreground'], ["'x'", 'purple']] },
  { parts: [['error', 'red'], ['  TS2304: Cannot find name ', 'foreground'], ["'foo'", 'cyan'], ['.', 'foreground']] }
];

for (const scheme of schemes) {
  const titleBg = mix(scheme.foreground, scheme.background, 0.08);
  const lineHeight = 29;
  const startY = 82;
  const text = lines.map((line, index) => {
    const spans = line.parts.map(([value, color]) => `<tspan fill="${scheme[color]}">${xml(value)}</tspan>`).join('');
    return `    <text x="26" y="${startY + index * lineHeight}">${spans}</text>`;
  }).join('\n');

  const swatches = swatchKeys.map((key, index) => {
    const x = 12 + index * 44;
    return `    <rect x="${x}" y="298" width="40" height="30" rx="4" fill="${scheme[key]}" stroke="${scheme.foreground}" stroke-opacity="0.12"/>`;
  }).join('\n');

  const svg = `<svg xmlns="http://www.w3.org/2000/svg" width="720" height="360" viewBox="0 0 720 360" role="img" aria-label="${xml(scheme.name)} terminal preview">
  <rect width="720" height="360" fill="${scheme.background}"/>
  <rect width="720" height="40" fill="${titleBg}"/>
  <circle cx="22" cy="20" r="6" fill="${scheme.red}"/>
  <circle cx="42" cy="20" r="6" fill="${scheme.yellow}"/>
  <circle cx="62" cy="20" r="6" fill="${scheme.green}"/>
  <text x="86" y="25" fill="${scheme.foreground}" fill-opacity="0.86" font-family="'Cascadia Code',Consolas,monospace" font-size="13">${xml(scheme.name)} — Windows Terminal</text>
  <g font-family="'Cascadia Code','Fira Code',Consolas,monospace" font-size="15">
${text}
  </g>
${swatches}
</svg>
`;
  fs.writeFileSync(path.join(outDir, slug(scheme.name) + '.svg'), svg, 'utf8');
  console.log(slug(scheme.name) + '.svg');
}
