import type { NextConfig } from "next";

/* Static export: `pnpm build` writes a plain-HTML site to out/, which is what
   Netlify publishes — no server runtime, no functions, nothing to keep warm.
   next/image can't run its optimizer without a server, hence `unoptimized`;
   the screenshots ship as-is. */
const nextConfig: NextConfig = {
  images: { unoptimized: true },
  /* content/page.md comes in as a plain string (tools/raw-loader.cjs), so the
     copy is a watched module: edit it and the page hot-reloads. */
  turbopack: {
    rules: {
      "*.md": {
        loaders: ["./tools/raw-loader.cjs"],
        as: "*.js",
      },
    },
  },
  experimental: {
    turbopackFileSystemCacheForDev: true,
  },
};

export default nextConfig;
