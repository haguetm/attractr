// All editable content of the page lives here.
// Values in [brackets] are placeholders to replace.

const ph = (file: string) => `/placeholders/${file}`;

export const profile = {
  firstName: 'Maxime',
  fullName: 'Maxime Haguet',
  role: 'Software engineering apprentice, cybersecurity and AI/data',
  portrait: ph('portrait.svg'),
};

export const navLinks = [
  { label: 'About', href: '#about' },
  { label: 'Skills', href: '#skills' },
  { label: 'Projects', href: '#projects' },
  { label: 'Contact', href: '#contact' },
];

export const marqueeImages: string[] = Array.from({ length: 21 }, (_, i) =>
  ph(`marquee-${String(i + 1).padStart(2, '0')}.svg`),
);

export const about = {
  // [Ton texte] - replace with your own paragraph.
  text: "I'm a software engineering apprentice working at the crossroads of cybersecurity and AI/data. I like building reliable systems, understanding how they break, and turning data into tools people actually use. Let's build something solid together!",
  decorations: {
    topLeft: ph('deco-top-left.svg'),
    bottomLeft: ph('deco-bottom-left.svg'),
    topRight: ph('deco-top-right.svg'),
    bottomRight: ph('deco-bottom-right.svg'),
  },
};

// [Tes 5 domaines] - replace names and descriptions.
export const skills = [
  {
    name: 'Cybersecurity',
    description: '[Network security, pentesting, hardening, secure-by-design practices.]',
  },
  {
    name: 'AI & Machine Learning',
    description: '[Model training, evaluation and integration of LLMs into real products.]',
  },
  {
    name: 'Data Engineering',
    description: '[Pipelines, SQL, data modeling and analytics that turn raw data into decisions.]',
  },
  {
    name: 'Software Development',
    description: '[TypeScript, Python, backend APIs and mobile apps, tested and maintainable.]',
  },
  {
    name: 'Cloud & DevOps',
    description: '[CI/CD, containers, cloud services and infrastructure as code.]',
  },
];

export type Project = {
  name: string;
  category: string;
  github: string;
  images: { col1Top: string; col1Bottom: string; col2: string };
};

// [Tes 3 projets] - replace name, category and GitHub link.
export const projects: Project[] = [
  {
    name: '[Project One]',
    category: '[Cybersecurity]',
    github: 'https://github.com/[username]/[project-one]',
    images: { col1Top: ph('project-1-a.svg'), col1Bottom: ph('project-1-b.svg'), col2: ph('project-1-c.svg') },
  },
  {
    name: '[Project Two]',
    category: '[AI / Data]',
    github: 'https://github.com/[username]/[project-two]',
    images: { col1Top: ph('project-2-a.svg'), col1Bottom: ph('project-2-b.svg'), col2: ph('project-2-c.svg') },
  },
  {
    name: '[Project Three]',
    category: '[Software]',
    github: 'https://github.com/[username]/[project-three]',
    images: { col1Top: ph('project-3-a.svg'), col1Bottom: ph('project-3-b.svg'), col2: ph('project-3-c.svg') },
  },
];

export const contact = {
  email: '[you@example.com]',
  linkedin: 'https://www.linkedin.com/in/[username]',
  github: 'https://github.com/[username]',
};
