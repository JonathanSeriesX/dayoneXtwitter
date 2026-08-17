import Image from "next/image";

import twatterShot from "@/public/pics/twatter.jpg";

import { intro, sections } from "./content";
import { CoffeeIcon, DownloadIcon, GitHubIcon } from "./icons";
import { Markdown } from "./markdown";
import { ThemeSwitch } from "./theme-switch";

const repo = "https://github.com/JonathanSeriesX/twixodus";
const releases = `${repo}/releases`;

/* One collapsible glass section. Every section on this page is a `##` heading in
   content/page.md, folded into one of these — the copy lives there, the chrome
   (hero, buttons, footer) lives here. */
function Dash({
  title,
  badge,
  open = false,
  children,
}: {
  title: React.ReactNode;
  badge?: string;
  open?: boolean;
  children: React.ReactNode;
}) {
  return (
    <details className="dash" open={open}>
      <summary>
        <span className="dash-title">{title}</span>
        {badge && <span className="badge">{badge}</span>}
        <span className="chevron" aria-hidden />
      </summary>
      <div className="dash-body">{children}</div>
    </details>
  );
}

export default function Page() {
  return (
    <div className="wrap stagger">
      <header className="hero flow-root">
        <div className="hero-shot">
          <Image
            src={twatterShot}
            alt="The bird, freed"
            fill
            sizes="216px"
            priority
            className="object-cover"
          />
        </div>
        <h1>Twixodus</h1>
        <div className="hero-tag">
          <Markdown>{intro}</Markdown>
        </div>
        <div className="cta-row">
          <a className="cta" href={releases} target="_blank" rel="noreferrer">
            <DownloadIcon />
            Download Twixodus.zip
          </a>
          <a className="cta ghost" href={repo} target="_blank" rel="noreferrer">
            <GitHubIcon />
            Source
          </a>
        </div>
        <p className="hero-meta">
          native macOS app · your data never leaves your Mac
        </p>
      </header>

      {sections.map((section) => (
        <Dash key={section.title} title={section.title} badge={section.badge}>
          <Markdown>{section.body}</Markdown>
        </Dash>
      ))}

      <footer className="site-footer">
        <p>
          Twixodus is open source — the code, the issues and the releases all
          live in{" "}
          <a className="link" href={repo} target="_blank" rel="noreferrer">
            the repo
          </a>
          .
        </p>
        <div className="flex items-center gap-3">
          <nav className="seg" aria-label="Links">
            <a
              href={repo}
              aria-label="GitHub"
              title="GitHub"
              target="_blank"
              rel="noreferrer"
            >
              <GitHubIcon />
            </a>
            <a
              href={releases}
              aria-label="Releases"
              title="Releases"
              target="_blank"
              rel="noreferrer"
            >
              <DownloadIcon />
            </a>
            <a
              href="https://coff.ee/jonathunky"
              aria-label="Buy me a coffee"
              title="Buy me a coffee"
              target="_blank"
              rel="noreferrer"
            >
              <CoffeeIcon />
            </a>
          </nav>
          <ThemeSwitch />
        </div>
      </footer>
    </div>
  );
}
