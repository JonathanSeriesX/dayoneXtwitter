"use client";

import * as basicLightbox from "basiclightbox";
import "basiclightbox/dist/basicLightbox.min.css";
import { useEffect } from "react";

/* Click a screenshot to see it full size. The .shot images are the native
   ~2600px AVIFs, which is the reason they were never downscaled.

   Deliberately NOT a medium.com-style zoom: those scale the thumbnail with
   `transform: scale()` and mark it `will-change: transform`, so the browser
   rasterises it at its ~650px layout size and then stretches that bitmap —
   bigger, but blurry. A lightbox lays a fresh <img> out at full size instead,
   so the pixels are actually there.

   Renders nothing; it only listens. Mounted once from page.tsx. */
export function ImageZoom() {
  useEffect(() => {
    const onClick = (event: MouseEvent) => {
      const target = event.target as HTMLElement | null;
      const img = target?.closest?.("img.shot") as HTMLImageElement | null;
      if (!img) return;

      /* Delegated from document rather than bound per image: the screenshots
         live inside <details> and only get a layout box once opened, so there's
         nothing to enumerate up front. */
      const shell = document.createElement("div");
      const full = document.createElement("img");
      full.src = img.currentSrc || img.src;
      full.alt = img.alt;
      shell.append(full);

      const box = basicLightbox.create(shell.innerHTML, {
        className: "shot-zoom",
      });
      box.show();

      /* basiclightbox only dismisses on a click that lands on its root, so the
         image itself would swallow the click — while wearing a zoom-out cursor
         that says otherwise. Close on the image too. */
      box.element()
        .querySelector("img")
        ?.addEventListener("click", () => box.close());
    };

    document.addEventListener("click", onClick);
    return () => document.removeEventListener("click", onClick);
  }, []);

  return null;
}
