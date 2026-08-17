import source from "@/content/page.md";

/* content/page.md, cut into the sections page.tsx renders. The Markdown arrives
   as a string through tools/raw-loader.cjs — imported rather than read off disk
   so the bundler watches it and an edit to the copy hot-reloads. Runs at build
   time only; the parsing cost never reaches the browser. */

export type Section = {
  /* the `##` text, minus any {braces} */
  title: string;
  /* the {braces}, if the heading had them — rendered as the pill beside it */
  badge?: string;
  /* everything under the heading, still Markdown */
  body: string;
};

/* `## Preparation {one-time}` → title "Preparation", badge "one-time" */
const HEADING = /^##\s+(.*?)(?:\s*\{(.+)\})?\s*$/;

/* The file opens with a note to whoever edits it; `---` hands over to the copy
   the site actually shows. */
function stripEditorPreamble(md: string): string {
  const handover = md.indexOf("\n---\n");
  return handover === -1 ? md : md.slice(handover + 5);
}

/* Drop `<!-- … -->` regions before splitting. react-markdown would ignore a
   commented-out heading, but the splitter below would not — it'd hand back an
   empty section and the page would grow a blank card. */
function stripComments(md: string): string {
  return md.replace(/<!--[\s\S]*?-->/g, "");
}

/* Headings inside a fenced block are code, not headings. Tracked rather than
   regex-split for the sake of the `##` that will eventually appear in a snippet. */
function parse(md: string): { intro: string; sections: Section[] } {
  const intro: string[] = [];
  const sections: Section[] = [];
  let current: Section | null = null;
  let inFence = false;

  for (const line of md.split("\n")) {
    if (/^\s*(```|~~~)/.test(line)) inFence = !inFence;

    const heading = inFence ? null : HEADING.exec(line);
    if (heading) {
      current = { title: heading[1], badge: heading[2], body: "" };
      sections.push(current);
      continue;
    }

    if (current) current.body += line + "\n";
    else intro.push(line);
  }

  for (const section of sections) section.body = section.body.trim();
  return { intro: intro.join("\n").trim(), sections };
}

export const { intro, sections } = parse(
  stripComments(stripEditorPreamble(source)),
);
