"use client";

import { useCallback, useEffect, useRef, useState } from "react";

import { copyToClipboard } from "./clipboard";
import { CheckIcon, CopyIcon } from "./icons";

/** How long the tick stays up before flipping back to the copy glyph. */
const RESET_MS = 1000;

export function CopyButton({ text, label }: { text: string; label: string }) {
  const [copied, setCopied] = useState(false);
  const timer = useRef<ReturnType<typeof setTimeout> | undefined>(undefined);

  useEffect(() => () => clearTimeout(timer.current), []);

  const copy = useCallback(
    (event: React.MouseEvent<HTMLButtonElement>) => {
      // drop focus so the button doesn't keep its focus ring after a click
      event.currentTarget.blur();
      void copyToClipboard(text).then((landed) => {
        if (!landed) return;
        setCopied(true);
        // a second click mid-flash restarts the window rather than letting
        // the earlier timer cut the new one short
        clearTimeout(timer.current);
        timer.current = setTimeout(() => setCopied(false), RESET_MS);
      });
    },
    [text],
  );

  return (
    <button
      type="button"
      className="copy-btn"
      data-copied={copied}
      onClick={copy}
      aria-label={copied ? "Copied" : label}
      title={copied ? "Copied" : label}
    >
      {/* both glyphs stay mounted and stacked, swapping on opacity+scale, so
          the flash never reflows the button */}
      <span className="icon-swap" aria-hidden>
        <CopyIcon className={copied ? "icon-hidden" : "icon-visible"} />
        <CheckIcon className={copied ? "icon-visible" : "icon-hidden"} />
      </span>
    </button>
  );
}
