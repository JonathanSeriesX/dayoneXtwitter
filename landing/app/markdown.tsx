import type { Element } from "hast";
import Image, { type StaticImageData } from "next/image";
import type { ReactNode } from "react";
import ReactMarkdown, { type Components } from "react-markdown";
import remarkGfm from "remark-gfm";

import repliesShot from "@/public/pics/replies.png";
import threadsShot from "@/public/pics/threads.png";

import { CopyButton } from "./copy-button";

/* content/page.md, wearing the classes globals.css already styles. Every entry
   below maps one Markdown construct onto the markup page.tsx used to spell out
   by hand — which is what lets the copy stay plain Markdown and still come out
   as glass cards, numbered circles and terminal snippets. */

/* Screenshots are imported rather than looked up by path at runtime: the static
   import is what hands next/image the intrinsic size, so the page doesn't jump
   while the PNG loads. A filename the Markdown names but this map doesn't know
   renders nothing — better a gap than a broken-image icon. */
const SHOTS: Record<string, StaticImageData> = {
  "pics/threads.png": threadsShot,
  "pics/replies.png": repliesShot,
};

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

function isLoneImage(node: Element | undefined): boolean {
  const content = node?.children.filter(
    (child) => child.type !== "text" || child.value.trim() !== "",
  );
  const only = content?.length === 1 ? content[0] : undefined;
  return only?.type === "element" && only.tagName === "img";
}

const components: Components = {
  /* `### AI titles` — a named block inside a section, one rung below its title */
  h3: ({ children }) => <h3 className="subhead">{children}</h3>,

  /* An image on a line of its own is still a paragraph as far as Markdown is
     concerned, and <figure> inside <p> is invalid HTML the browser silently
     reparents — which breaks hydration. Hand the figure straight through. */
  p: ({ children, node }) => {
    if (isLoneImage(node)) return <>{children}</>;
    return <p className={isLabel(children) ? "sub" : undefined}>{children}</p>;
  },

  /* `- bullet`, accent dash hanging in the margin. Nested lists get the class
     too — .prose-list ul already handles their indent. */
  ul: ({ children }) => <ul className="prose-list">{children}</ul>,

  /* `1. step`. The numbers come from a CSS counter, not from the list marker,
     because each one is drawn as a circle out in the margin. */
  ol: ({ children }) => <ol className="steps">{children}</ol>,

  a: ({ href, children }) => (
    <a
      className="link"
      href={href}
      {...(href?.startsWith("http")
        ? { target: "_blank", rel: "noreferrer" }
        : {})}
    >
      {children}
    </a>
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

  /* ![alt](pics/shot.png) — the PNGs carry their own rounded corners, margin and
     drop shadow, so .shot draws no frame of its own. */
  img: ({ src, alt }) => {
    const shot = typeof src === "string" ? SHOTS[src] : undefined;
    if (!shot) return null;
    return (
      <figure className="shot">
        <Image src={shot} alt={alt ?? ""} />
      </figure>
    );
  },
};

export function Markdown({ children }: { children: string }) {
  return (
    <ReactMarkdown remarkPlugins={[remarkGfm]} components={components}>
      {children}
    </ReactMarkdown>
  );
}
