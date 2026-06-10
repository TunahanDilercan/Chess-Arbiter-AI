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
  const resp = await fetch(path, init);
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

export function getGame(gameId: string): Promise<GameAnalysisResponse> {
  return request(`/api/games/${encodeURIComponent(gameId)}`);
}

export function listGames(sessionId: string): Promise<GameSummary[]> {
  return request(`/api/games/?session_id=${encodeURIComponent(sessionId)}`);
}

export function correctMove(
  gameId: string,
  plyIndex: number,
  correctedSan: string,
  locale = "en",
): Promise<GameAnalysisResponse> {
  return request(
    `/api/games/${encodeURIComponent(gameId)}/moves/${plyIndex}/correct`,
    {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ corrected_san: correctedSan, locale }),
    },
  );
}

export async function uploadScoresheet(
  file: File,
  sessionId: string,
  locale: string,
): Promise<UploadResponse> {
  const form = new FormData();
  form.append("file", file);
  form.append("session_id", sessionId);
  form.append("locale", locale);
  return request("/api/upload/", { method: "POST", body: form });
}

export { ApiError };
