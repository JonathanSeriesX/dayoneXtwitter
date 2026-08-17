"use client";

import { useSyncExternalStore } from "react";
import { flushSync } from "react-dom";
import { useTheme } from "next-themes";

const emptySubscribe = () => () => {};

function SunIcon() {
  return (
    <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
      <circle cx="12" cy="12" r="4" />
      <path d="M12 2v2m0 16v2M4.9 4.9l1.4 1.4m11.4 11.4 1.4 1.4M2 12h2m16 0h2M4.9 19.1l1.4-1.4M17.7 6.3l1.4-1.4" />
    </svg>
  );
}

function MoonIcon() {
  return (
    <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
      <path d="M21 12.8A9 9 0 1 1 11.2 3a7 7 0 0 0 9.8 9.8Z" />
    </svg>
  );
}

function MoonFilledIcon() {
  return (
    <svg viewBox="0 0 24 24" fill="currentColor">
      <path d="M21 12.8A9 9 0 1 1 11.2 3a7 7 0 0 0 9.8 9.8Z" />
    </svg>
  );
}

function CircleHalfIcon() {
  return (
    <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
      <circle cx="12" cy="12" r="9" />
      <path d="M12 3v18" />
      <path d="M12 3a9 9 0 0 1 0 18Z" fill="currentColor" stroke="none" />
    </svg>
  );
}

const OPTIONS = [
  { value: "light", label: "Light", Icon: SunIcon },
  { value: "dark", label: "Dark", Icon: MoonIcon },
  { value: "black", label: "Pitch Black", Icon: MoonFilledIcon },
  { value: "system", label: "System", Icon: CircleHalfIcon },
];

export function ThemeSwitch() {
  const { theme, setTheme } = useTheme();
  // Theme is unknown until hydration; render no active segment before then.
  const mounted = useSyncExternalStore(
    emptySubscribe,
    () => true,
    () => false,
  );

  // Cross-fade with the View Transitions API — except on iOS, where the
  // snapshot animation makes Safari paint an opaque plate behind its glass
  // bottom pill.
  const pickTheme = (next: string) => {
    if (next === theme) return;
    const isIOS =
      /iPhone|iPad|iPod/.test(navigator.userAgent) ||
      (navigator.platform === "MacIntel" && navigator.maxTouchPoints > 1);
    if (
      !isIOS &&
      document.visibilityState === "visible" &&
      typeof document.startViewTransition === "function"
    ) {
      const transition = document.startViewTransition(() => {
        flushSync(() => setTheme(next));
      });
      // A transition can still be skipped (e.g. tab hidden mid-swap); the
      // theme is applied either way, so silence the rejected promise.
      transition.finished.catch(() => {});
    } else {
      const root = document.documentElement;
      root.classList.add("no-theme-fade");
      setTheme(next);
      window.setTimeout(() => root.classList.remove("no-theme-fade"), 60);
    }
  };

  return (
    <div className="seg" role="radiogroup" aria-label="Theme">
      {OPTIONS.map(({ value, label, Icon }) => (
        <button
          key={value}
          type="button"
          role="radio"
          aria-checked={mounted && theme === value}
          data-active={mounted && theme === value}
          aria-label={label}
          title={label}
          onClick={(event) => {
            event.currentTarget.blur();
            pickTheme(value);
          }}
        >
          <Icon />
        </button>
      ))}
    </div>
  );
}
