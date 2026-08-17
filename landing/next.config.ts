import type { NextConfig } from "next";

/* Static export: `pnpm build` writes a plain-HTML site to out/, which is what
   Netlify publishes — no server runtime, no functions, nothing to keep warm.
   next/image can't run its optimizer without a server, hence `unoptimized`;
   the screenshots ship as-is. */
const nextConfig: NextConfig = {
  //output: "export",
  images: { unoptimized: true },
  experimental: {
    turbopackFileSystemCacheForDev: true,
  },
};

export default nextConfig;
