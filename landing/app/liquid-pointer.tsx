"use client";

import { useEffect } from "react";

/* Pointer plumbing for the liquid-glass effects. Writes two pairs of custom
   properties and renders nothing:

   --mxn / --myn on <html>          pointer position, [-1, 1] from the viewport
                                    centre, lerp-smoothed — the "virtual light"
                                    every shadow in globals.css leans away from
   --gx / --gy on a hovered section pointer position, 0–100 inside it —
                                    drives the specular glint

   The rAF loop runs only while the light is still converging on the pointer,
   so an idle cursor costs nothing. Skipped entirely for reduced-motion and
   touch-only devices: the CSS falls back to static shadows. */

const CARD_SELECTOR = ".dash";

export function LiquidPointer() {
  useEffect(() => {
    if (
      window.matchMedia("(prefers-reduced-motion: reduce)").matches ||
      window.matchMedia("(hover: none)").matches
    ) {
      return;
    }

    const root = document.documentElement;
    let targetX = 0;
    let targetY = 0;
    let lightX = 0;
    let lightY = 0;
    let raf = 0;
    let card: HTMLElement | null = null;

    const step = () => {
      lightX += (targetX - lightX) * 0.12;
      lightY += (targetY - lightY) * 0.12;
      root.style.setProperty("--mxn", lightX.toFixed(3));
      root.style.setProperty("--myn", lightY.toFixed(3));
      raf =
        Math.abs(targetX - lightX) + Math.abs(targetY - lightY) > 0.002
          ? requestAnimationFrame(step)
          : 0;
    };

    const clearCard = () => {
      if (!card) return;
      card.style.removeProperty("--gx");
      card.style.removeProperty("--gy");
      card = null;
    };

    const onMove = (e: PointerEvent) => {
      targetX = (e.clientX / window.innerWidth) * 2 - 1;
      targetY = (e.clientY / window.innerHeight) * 2 - 1;
      if (!raf) raf = requestAnimationFrame(step);

      const hit = (e.target as Element | null)?.closest?.(
        CARD_SELECTOR,
      ) as HTMLElement | null;
      if (hit !== card) clearCard();
      if (hit) {
        const r = hit.getBoundingClientRect();
        hit.style.setProperty(
          "--gx",
          (((e.clientX - r.left) / r.width) * 100).toFixed(1),
        );
        hit.style.setProperty(
          "--gy",
          (((e.clientY - r.top) / r.height) * 100).toFixed(1),
        );
        card = hit;
      }
    };

    window.addEventListener("pointermove", onMove, { passive: true });
    root.addEventListener("pointerleave", clearCard);
    return () => {
      window.removeEventListener("pointermove", onMove);
      root.removeEventListener("pointerleave", clearCard);
      if (raf) cancelAnimationFrame(raf);
      clearCard();
      root.style.removeProperty("--mxn");
      root.style.removeProperty("--myn");
    };
  }, []);

  return null;
}
