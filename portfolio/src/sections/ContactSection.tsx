import { Github, Linkedin, Mail, type LucideIcon } from 'lucide-react';
import FadeIn from '../components/FadeIn';
import { contact } from '../content';

const links: { label: string; value: string; href: string; icon: LucideIcon }[] = [
  { label: 'Email', value: contact.email, href: `mailto:${contact.email}`, icon: Mail },
  { label: 'LinkedIn', value: 'LinkedIn', href: contact.linkedin, icon: Linkedin },
  { label: 'GitHub', value: 'GitHub', href: contact.github, icon: Github },
];

export default function ContactSection() {
  return (
    <section
      id="contact"
      className="relative z-10 flex min-h-[80vh] flex-col items-center justify-center gap-14 bg-[#0C0C0C] px-5 py-20 sm:gap-16 sm:px-8 md:gap-20 md:px-10 md:py-32"
    >
      <FadeIn
        as="h2"
        y={40}
        className="hero-heading text-center font-black uppercase leading-none tracking-tight"
        style={{ fontSize: 'clamp(3rem, 12vw, 160px)' }}
      >
        Contact
      </FadeIn>

      <ul className="flex w-full max-w-4xl flex-col">
        {links.map(({ label, value, href, icon: Icon }, i) => (
          <FadeIn as="li" key={label} delay={i * 0.1} className="border-t border-[#D7E2EA]/15 last:border-b">
            <a
              href={href}
              target={href.startsWith('mailto:') ? undefined : '_blank'}
              rel="noreferrer"
              className="flex items-center justify-between gap-4 py-6 text-[#D7E2EA] transition-opacity duration-200 hover:opacity-70 sm:py-8"
            >
              <span className="flex items-center gap-4 sm:gap-6">
                <Icon className="h-6 w-6 shrink-0 sm:h-8 sm:w-8" />
                <span className="font-light uppercase tracking-widest opacity-60" style={{ fontSize: 'clamp(0.75rem, 1.2vw, 1rem)' }}>
                  {label}
                </span>
              </span>
              <span className="break-all text-right font-medium uppercase" style={{ fontSize: 'clamp(1rem, 2.2vw, 2.1rem)' }}>
                {value}
              </span>
            </a>
          </FadeIn>
        ))}
      </ul>

      <p className="text-sm font-light uppercase tracking-widest text-[#D7E2EA]/40">
        © {new Date().getFullYear()} Maxime Haguet
      </p>
    </section>
  );
}
