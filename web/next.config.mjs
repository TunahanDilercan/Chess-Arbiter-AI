/** @type {import('next').NextConfig} */

// All API and storage traffic is proxied through Next so the browser only
// ever talks to one origin (no CORS configuration needed in dev).
const BACKEND_URL = process.env.BACKEND_URL ?? "http://localhost:8000";

const nextConfig = {
  reactStrictMode: true,
  async rewrites() {
    return [
      { source: "/api/:path*", destination: `${BACKEND_URL}/api/:path*` },
      { source: "/storage/:path*", destination: `${BACKEND_URL}/storage/:path*` },
    ];
  },
};

export default nextConfig;
