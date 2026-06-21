import type {
  GameAnalysisResponse,
  GameSummary,
  UploadResponse,
} from "./types";

// Requests go through the Next.js rewrite proxy (next.config.mjs), so the
// browser always talks to the web app's own origin.

class ApiError extends Error {
  constructor(public status: number, detail: string) {
    super(detail);
    this.name = "ApiError";
  }
}

async function request<T>(path: string, init?: RequestInit): Promise<T> {
  // ngrok's free tier serves an HTML "browser warning" interstitial for
  // browser-looking requests; without this header an XHR/fetch could receive
  // that HTML page instead of JSON and fail to parse. The header is harmless
  // off ngrok. (Do NOT set Content-Type here — the browser must set the
  // multipart boundary for FormData uploads.)
  const headers = new Headers(init?.headers);
  headers.set("ngrok-skip-browser-warning", "1");
  const resp = await fetch(path, { ...init, headers });
  if (!resp.ok) {
    let detail = `HTTP ${resp.status}`;
    try {
      const body = (await resp.json()) as { detail?: unknown };
      if (typeof body.detail === "string") detail = body.detail;
    } catch {
      // non-JSON error body — keep the status text
    }
    throw new ApiError(resp.status, detail);
  }
  return (await resp.json()) as T;
}

export function getGame(
  gameId: string,
  sessionId: string,
): Promise<GameAnalysisResponse> {
  return request(
    `/api/games/${encodeURIComponent(gameId)}?session_id=${encodeURIComponent(sessionId)}`,
  );
}

export function listGames(sessionId: string): Promise<GameSummary[]> {
  return request(`/api/games/?session_id=${encodeURIComponent(sessionId)}`);
}

export function correctMove(
  gameId: string,
  plyIndex: number,
  correctedSan: string,
  sessionId: string,
  locale = "en",
): Promise<GameAnalysisResponse> {
  return request(
    `/api/games/${encodeURIComponent(gameId)}/moves/${plyIndex}/correct` +
      `?session_id=${encodeURIComponent(sessionId)}`,
    {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ corrected_san: correctedSan, locale }),
    },
  );
}

// Phone photos are often 5–12 MB, which exceeds the request-body limit of the
// remote tunnel (and is wasteful — the backend downscales to ~2576 px for OCR
// anyway). Downscale to a long edge of 2200 px and re-encode as JPEG before
// upload. This also normalises iOS HEIC photos to JPEG (Safari decodes HEIC
// into the <img>, the canvas re-encodes as JPEG). PDFs are sent untouched.
const MAX_UPLOAD_EDGE = 2000;
const MAX_UPLOAD_BYTES = 2_000_000; // stay well under the tunnel body cap (~2–3 MB)

// Decode a File to bitmap dimensions + a drawable source. createImageBitmap
// decodes large/HEIC photos far more reliably than an <img> element on mobile
// Safari (which silently fails above a decode-size limit); fall back to <img>.
async function decodeImage(
  file: File,
): Promise<{ src: CanvasImageSource; w: number; h: number }> {
  if ("createImageBitmap" in window) {
    try {
      const bmp = await createImageBitmap(file);
      return { src: bmp, w: bmp.width, h: bmp.height };
    } catch {
      /* fall through to <img> */
    }
  }
  const url = URL.createObjectURL(file);
  try {
    const img = document.createElement("img");
    await new Promise<void>((resolve, reject) => {
      img.onload = () => resolve();
      img.onerror = () => reject(new Error("image decode failed"));
      img.src = url;
    });
    return { src: img, w: img.naturalWidth, h: img.naturalHeight };
  } finally {
    URL.revokeObjectURL(url);
  }
}

async function downscaleImage(file: File): Promise<File> {
  if (!file.type.startsWith("image/")) return file;

  try {
    const { src, w: srcW, h: srcH } = await decodeImage(file);
    const longEdge = Math.max(srcW, srcH);
    const scale = longEdge > MAX_UPLOAD_EDGE ? MAX_UPLOAD_EDGE / longEdge : 1;
    const w = Math.max(1, Math.round(srcW * scale));
    const h = Math.max(1, Math.round(srcH * scale));

    const canvas = document.createElement("canvas");
    canvas.width = w;
    canvas.height = h;
    const ctx = canvas.getContext("2d");
    if (!ctx) return file;
    ctx.drawImage(src, 0, 0, w, h);

    // Re-encode, lowering quality until the result is comfortably small.
    let blob: Blob | null = null;
    for (const q of [0.85, 0.7, 0.55, 0.4]) {
      blob = await new Promise<Blob | null>((resolve) =>
        canvas.toBlob(resolve, "image/jpeg", q),
      );
      if (blob && blob.size <= MAX_UPLOAD_BYTES) break;
    }
    if (!blob) return file;

    const name = file.name.replace(/\.[^.]+$/, "") + ".jpg";
    return new File([blob], name, { type: "image/jpeg" });
  } catch {
    return file; // any failure → upload the original, let the backend decide
  }
}

export async function uploadScoresheet(
  file: File,
  sessionId: string,
  locale: string,
): Promise<UploadResponse> {
  const prepared = await downscaleImage(file);
  const mb = (n: number) => (n / 1024 / 1024).toFixed(2);
  // Diagnostic suffix so a failure surfaces the actual sent size in the UI —
  // tells us instantly whether client-side downscaling ran.
  const diag = `[orijinal ${mb(file.size)}MB → gönderilen ${mb(prepared.size)}MB]`;
  const form = new FormData();
  form.append("file", prepared);
  form.append("session_id", sessionId);
  form.append("locale", locale);
  try {
    // No trailing slash: see the explicit rewrite in next.config.mjs — this
    // reaches the backend's canonical "/api/upload/" with zero redirects, so the
    // multipart body is sent exactly once.
    return await request("/api/upload", { method: "POST", body: form });
  } catch (err) {
    const base = err instanceof ApiError ? err.message : "ağ hatası (tünel/bağlantı)";
    throw new Error(`Yükleme başarısız ${diag}: ${base}`);
  }
}

export { ApiError };
