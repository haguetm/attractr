# Portfolio - Maxime Haguet

Single-page portfolio (React, TypeScript, Tailwind CSS, Framer Motion, Lucide React, Vite). Standalone: not part of the Attractr npm workspaces.

```bash
cd portfolio
npm install
npm run dev      # http://localhost:5173
npm run build    # type-check + production build in dist/
```

## Edit the content
Everything editable lives in `src/content.ts`. Values in `[brackets]` are placeholders:
- `about.text` - About paragraph
- `skills` - 5 domains (name + description)
- `projects` - 3 projects (name, category, GitHub link, 3 images each)
- `contact` - email, LinkedIn, GitHub

## Replace the images
Neutral SVG placeholders sit in `public/placeholders/`. Drop your own files there (keep the names, or change the paths in `src/content.ts`):
- `portrait.svg` - hero portrait (ideally a transparent PNG cut-out, ~520px wide)
- `deco-*.svg` - the 4 decorative visuals of the About section (transparent PNG)
- `marquee-01..21.svg` - marquee tiles (420x270, rows of 11 + 10)
- `project-N-a/b/c.svg` - project images (a: left top, b: left bottom, c: right tall column)

`npm run placeholders` regenerates the placeholders.
