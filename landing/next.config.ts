import type { NextConfig } from "next";

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
