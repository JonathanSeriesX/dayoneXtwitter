import Link from "next/link";
import type { ReactNode } from "react";
import ReactMarkdown, {
  defaultUrlTransform,
  type Components,
} from "react-markdown";
import remarkGfm from "remark-gfm";

import { CopyButton } from "./copy-button";

/* content/page.md, wearing the classes globals.css already styles. Every entry
   below maps one Markdown construct onto the markup page.tsx used to spell out
   by hand — which is what lets the copy stay plain Markdown and still come out
   as glass cards, numbered circles and terminal snippets. */

/* Long enough that you'd copy it rather than read it — a wallet address, not a
   model name. Those get user-select: all, so one click takes the whole string. */
const COPYABLE_TOKEN = 26;

function isComment(line: string): boolean {
  return /^\s*#/.test(line);
}

function text(node: ReactNode): string {
  if (typeof node === "string") return node;
  if (typeof node === "number") return String(node);
  if (Array.isArray(node)) return node.map(text).join("");
  return "";
}

/* A paragraph whose only job is to introduce the list under it reads as a label
   rather than prose, so it gets the muted .sub treatment. Keying off the
   trailing colon keeps that decision out of the Markdown. */
function isLabel(children: ReactNode): boolean {
  return text(children).trimEnd().endsWith(":");
}

const components: Components = {
  /* `### AI titles` — a named block inside a section, one rung below its title */
  h3: ({ children }) => <h3 className="subhead">{children}</h3>,

  p: ({ children }) => (
    <p className={isLabel(children) ? "sub" : undefined}>{children}</p>
  ),

  /* `- bullet`, accent dash hanging in the margin. Nested lists get the class
     too — .prose-list ul already handles their indent. */
  ul: ({ children }) => <ul className="prose-list">{children}</ul>,

  /* `1. step`. The numbers come from a CSS counter, not from the list marker,
     because each one is drawn as a circle out in the margin. */
  ol: ({ children }) => <ol className="steps">{children}</ol>,

  /* Every link in the copy leaves this site — the http ones and the lone
     dayone:// scheme alike — so Link resolves each to a plain anchor with no
     prefetch. Link needs a defined href, which `[text]()` wouldn't give it,
     hence the guard; an anchor without href was never a link anyway. */
  a: ({ href, children }) =>
    href ? (
      <Link
        className="link"
        href={href}
        {...(href.startsWith("http")
          ? { target: "_blank", rel: "noreferrer" }
          : {})}
      >
        {children}
      </Link>
    ) : (
      <span className="link">{children}</span>
    ),

  /* > quote — the notarization confession, and anything else set aside */
  blockquote: ({ children }) => <div className="note">{children}</div>,

  /* A fenced block becomes the terminal card with its copy button parked in the
     corner; the div can't live inside the <pre>, hence the unwrap below. */
  pre: ({ children }) => <>{children}</>,

  code: ({ className, children }) => {
    const source = text(children);
    if (!className?.includes("language-")) {
      const copyable = source.length >= COPYABLE_TOKEN && !source.includes(" ");
      return (
        <span className={copyable ? "mono select-all" : "mono"}>{children}</span>
      );
    }
    /* `# comment` lines are labels for the reader, not part of the command:
       they render muted and the copy button leaves them behind. */
    const lines = source.replace(/\n$/, "").split("\n");
    const command = lines.filter((line) => !isComment(line)).join("\n").trim();
    return (
      <div className="code-block">
        <pre className="code-card">
          <code>
            {lines.map((line, i) => {
              const tail = i < lines.length - 1 ? "\n" : "";
              return isComment(line) ? (
                <span key={i} className="code-comment">
                  {line + tail}
                </span>
              ) : (
                line + tail
              );
            })}
          </code>
        </pre>
        <CopyButton text={command} label="Copy commands" />
      </div>
    );
  },

  /* ![alt](pics/shot.avif) — served straight from public/, no registration
     anywhere. The screenshots carry their own rounded corners, margin and drop
     shadow, so .shot draws no frame of its own. Plain <img> rather than
     next/image: with `images.unoptimized` there is nothing to optimize, and
     the static site can't know an AVIF's dimensions at build time anyway. */
  // eslint-disable-next-line @next/next/no-img-element
  img: ({ src, alt }) => <img src={`/${src}`} alt={alt} loading="lazy" className="shot" />,
};

/* react-markdown defends against javascript: URLs by blanking every scheme it
   doesn't recognise — which quietly reduced step 3's dayone://preferences to
   href="", a link that just reloaded the page. The copy here is ours rather
   than anything a stranger submitted, so Day One's scheme is waved through and
   everything else still goes past the default sanitiser. */
function urlTransform(url: string): string {
  return url.startsWith("dayone:") ? url : defaultUrlTransform(url);
}

export function Markdown({ children }: { children: string }) {
  return (
    <ReactMarkdown
      remarkPlugins={[remarkGfm]}
      components={components}
      urlTransform={urlTransform}
    >
      {children}
    </ReactMarkdown>
  );
}
