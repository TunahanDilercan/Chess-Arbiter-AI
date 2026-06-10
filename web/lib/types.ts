// API contract types — mirror backend/schemas/analysis.py and upload.py.
// Field names are snake_case to match the wire format exactly.

export interface OCRCandidate {
  text: string;
  confidence: number;
}

export interface RuleFinding {
  type: string;
  ply_index: number;
  description: string;
  /** true → game ends here unconditionally; false → claimable by a player */
  is_automatic: boolean;
}

export interface GameStats {
  total_moves: number;
  auto_resolved: number;
  manual_review_required: number;
  illegal_moves: number;
  ocr_avg_confidence: number;
}

export interface UploadMetadata {
  filename: string | null;
  uploaded_at: string | null;
}

export interface MoveAnalysis {
  move_number: number;
  ply_index: number;
  color: "white" | "black";
  ocr_raw_text: string;
  ocr_candidates: OCRCandidate[];
  normalized_text: string;
  selected_san: string | null;
  selected_uci: string | null;
  fen_before: string;
  fen_after: string;
  is_legal: boolean;
  needs_manual_review: boolean;
  confidence: number;
  review_reasons: string[];
  fide_alerts: string[];
  crop_image_url: string | null;
}

export interface GameAnalysisResponse {
  game_id: string;
  session_id: string;
  status: string;
  upload_metadata: UploadMetadata;
  moves: MoveAnalysis[];
  findings: RuleFinding[];
  pgn: string;
  failure_point_ply: number | null;
  stats: GameStats;
  draw_decision: "none" | "claimable_draw" | "automatic_draw" | string;
  draw_reason: string | null;
  arbiter_must_end: boolean;
  requires_player_claim: boolean;
}

export interface GameSummary {
  game_id: string;
  session_id: string;
  status: string;
  locale: string;
  created_at: string;
  total_moves: number | null;
  has_findings: boolean | null;
  upload_filename: string | null;
}

export interface UploadResponse {
  game_id: string;
  job_id: string;
  status: string;
  sse_url: string;
  game_url: string;
}
