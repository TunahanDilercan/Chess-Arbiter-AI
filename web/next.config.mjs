/** @type {import('next').NextConfig} */

// All API and storage traffic is proxied through Next so the browser only
// ever talks to one origin (no CORS configuration needed in dev).
const BACKEND_URL = process.env.BACKEND_URL ?? "http://localhost:8000";

const nextConfig = {
  reactStrictMode: true,
  async rewrites() {
    return [
      // Upload is a multipart POST. Next (trailingSlash:false) would redirect
      // "/api/upload/" → "/api/upload", and the backend would then 307 back to
      // "/api/upload/" — two redirects, each forcing the browser to re-POST the
      // whole image body (fragile and slow on mobile). Map the no-slash form the
      // client posts to directly to the backend's canonical slash form so the
      // upload reaches the backend with ZERO redirects.
      { source: "/api/upload", destination: `${BACKEND_URL}/api/upload/` },
      // Same trailing-slash trap for the games *collection*. The client calls
      // "/api/games/", Next (trailingSlash:false) 308s to "/api/games", and the
      // backend would then 307 to an ABSOLUTE "http://localhost:8000/api/games/"
      // — which breaks over a tunnel (the phone would chase localhost). Proxy
      // the no-slash form straight to the backend's canonical slash form so the
      // request resolves on the public origin with zero backend redirects.
      { source: "/api/games", destination: `${BACKEND_URL}/api/games/` },
      { source: "/api/:path*", destination: `${BACKEND_URL}/api/:path*` },
      { source: "/storage/:path*", destination: `${BACKEND_URL}/storage/:path*` },
    ];
  },
};

export default nextConfig;
