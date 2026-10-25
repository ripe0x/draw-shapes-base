import type { NextConfig } from "next";

// A static export: every page is a client page reading the chain directly, and the deployment record
// is bundled at build time, so the site needs no server. @wagmi/connectors imports Coinbase's optional
// x402 packages behind literal dynamic imports that this app never reaches; listing them as server
// externals stops the bundler from resolving them at build time.
const nextConfig: NextConfig = {
  output: "export",
  trailingSlash: true,
  images: { unoptimized: true },
  reactStrictMode: true,
  allowedDevOrigins: ["127.0.0.1"],
  serverExternalPackages: ["@coinbase/cdp-sdk", "@base-org/account"],
};

export default nextConfig;
