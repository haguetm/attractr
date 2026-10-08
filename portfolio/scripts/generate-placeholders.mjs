// Generates neutral SVG placeholders in public/placeholders.
// Replace any file with your own image (same name, or update src/content.ts).
import { mkdirSync, writeFileSync } from 'node:fs';

const dir = new URL('../public/placeholders/', import.meta.url);
mkdirSync(dir, { recursive: true });

const palette = ['#1A1C20', '#22252B', '#2A2E35', '#1E2127', '#262A31'];

function tile(name, w, h, label, shade) {
  const svg = `<svg xmlns="http://www.w3.org/2000/svg" width="${w}" height="${h}" viewBox="0 0 ${w} ${h}">
  <defs>
    <linearGradient id="g" x1="0" y1="0" x2="1" y2="1">
      <stop offset="0" stop-color="${shade}"/>
      <stop offset="1" stop-color="#3A3F47"/>
    </linearGradient>
  </defs>
  <rect width="${w}" height="${h}" fill="url(#g)"/>
  <rect x="1" y="1" width="${w - 2}" height="${h - 2}" fill="none" stroke="#646973" stroke-opacity="0.35" stroke-dasharray="8 8"/>
  <text x="50%" y="50%" fill="#BBCCD7" fill-opacity="0.55" font-family="Kanit, sans-serif" font-size="${Math.round(Math.min(w, h) / 10)}" text-anchor="middle" dominant-baseline="middle" letter-spacing="2">${label}</text>
</svg>
`;
  writeFileSync(new URL(name, dir), svg);
}

function shape(name, size, label, body) {
  const svg = `<svg xmlns="http://www.w3.org/2000/svg" width="${size}" height="${size}" viewBox="0 0 ${size} ${size}">
  <defs>
    <linearGradient id="g" x1="0" y1="0" x2="1" y2="1">
      <stop offset="0" stop-color="#BBCCD7"/>
      <stop offset="1" stop-color="#646973"/>
    </linearGradient>
  </defs>
  ${body}
  <text x="50%" y="94%" fill="#BBCCD7" fill-opacity="0.5" font-family="Kanit, sans-serif" font-size="${Math.round(size / 14)}" text-anchor="middle">${label}</text>
</svg>
`;
  writeFileSync(new URL(name, dir), svg);
}

// Marquee tiles (420x270)
for (let i = 1; i <= 21; i++) {
  const n = String(i).padStart(2, '0');
  tile(`marquee-${n}.svg`, 840, 540, `MARQUEE ${n}`, palette[i % palette.length]);
}

// Project images
for (let p = 1; p <= 3; p++) {
  tile(`project-${p}-a.svg`, 800, 500, `PROJECT ${p} · A`, palette[p]);
  tile(`project-${p}-b.svg`, 800, 700, `PROJECT ${p} · B`, palette[p + 1]);
  tile(`project-${p}-c.svg`, 900, 1100, `PROJECT ${p} · C`, palette[p - 1]);
}

// Hero portrait (transparent background, silhouette)
writeFileSync(
  new URL('portrait.svg', dir),
  `<svg xmlns="http://www.w3.org/2000/svg" width="520" height="640" viewBox="0 0 520 640">
  <defs>
    <linearGradient id="g" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0" stop-color="#3A3F47"/>
      <stop offset="1" stop-color="#1A1C20"/>
    </linearGradient>
  </defs>
  <circle cx="260" cy="210" r="110" fill="url(#g)"/>
  <path d="M40 640 C40 470 140 360 260 360 C380 360 480 470 480 640 Z" fill="url(#g)"/>
  <text x="260" y="560" fill="#BBCCD7" fill-opacity="0.5" font-family="Kanit, sans-serif" font-size="28" text-anchor="middle" letter-spacing="4">PORTRAIT</text>
</svg>
`,
);

// About decorations (transparent background)
shape('deco-top-left.svg', 420, 'DECO 1', '<circle cx="210" cy="190" r="140" fill="url(#g)" fill-opacity="0.8"/>');
shape('deco-bottom-left.svg', 360, 'DECO 2', '<rect x="70" y="60" width="220" height="220" rx="40" fill="url(#g)" fill-opacity="0.8" transform="rotate(12 180 170)"/>');
shape('deco-top-right.svg', 420, 'DECO 3', '<polygon points="210,40 360,320 60,320" fill="url(#g)" fill-opacity="0.8"/>');
shape('deco-bottom-right.svg', 440, 'DECO 4', '<circle cx="160" cy="200" r="100" fill="url(#g)" fill-opacity="0.8"/><circle cx="290" cy="170" r="80" fill="url(#g)" fill-opacity="0.6"/>');

console.log('Placeholders written to public/placeholders');
