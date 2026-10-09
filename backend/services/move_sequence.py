"""Keep persisted scoresheet cells aligned with the chess replay."""

from typing import List

from chess import STARTING_FEN
from sqlalchemy.ext.asyncio import AsyncSession

from models.game import MoveEntry, OCRResult
from schemas.analysis import GameAnalysisResponse, GameStatus, ReviewReason
from services.chess.normalizer import MoveNormalizer

MAX_GAME_PLIES = 1024


async def ensure_move_sequence(
    db: AsyncSession, game_id: str, entries: List[MoveEntry],
) -> List[MoveEntry]:
    by_ply = {entry.ply_index: entry for entry in entries}
    if not by_ply:
        return []
    last_ply = max(by_ply)
    if min(by_ply) < 0 or last_ply >= MAX_GAME_PLIES:
        raise ValueError("Scoresheet move numbers exceed the supported range.")
    for ply in range(last_ply + 1):
        if ply not in by_ply:
            entry = MoveEntry(
                game_id=game_id, ply_index=ply, move_number=ply // 2 + 1,
                color="white" if ply % 2 == 0 else "black",
                fen_before="", fen_after="", is_legal=False,
                confidence=0.0, needs_review=True,
                ocr_result=None, crop=None, review_actions=[],
            )
            db.add(entry)
            by_ply[ply] = entry
        by_ply[ply].move_number = ply // 2 + 1
        by_ply[ply].color = "white" if ply % 2 == 0 else "black"
        entry = by_ply[ply]
        if entry.ocr_result is None and entry.selected_san:
            # Legacy/manual records have no OCR row. Snapshot their source before
            # an earlier correction can invalidate and clear the selected move.
            entry.ocr_result = OCRResult(
                raw_text=entry.selected_san, normalized_text=entry.selected_san,
                notation_locale="en",
                candidates_json=[{"text": entry.selected_san, "confidence": entry.confidence}],
            )
    await db.flush()
    return [by_ply[ply] for ply in range(last_ply + 1)]


def ocr_input(entry: MoveEntry, game_locale: str) -> tuple[str, float]:
    ocr = entry.ocr_result
    if ocr is None:
        return entry.selected_san or "", entry.confidence if entry.selected_san else 0.0
    text = MoveNormalizer().normalize(ocr.raw_text, ocr.notation_locale or game_locale)
    candidates = ocr.candidates_json or []
    confidence = float(candidates[0]["confidence"]) if candidates else entry.confidence
    return text, confidence


def apply_move_analysis(
    entries: List[MoveEntry], analysis: GameAnalysisResponse, start_ply: int = 0,
) -> None:
    by_ply = {move.ply_index: move for move in analysis.moves}
    last_fen = analysis.moves[-1].fen_after if analysis.moves else STARTING_FEN
    for entry in entries:
        if entry.ply_index < start_ply:
            continue
        move = by_ply.get(entry.ply_index)
        if move is None:
            # Retain the source and review history so replay can resume after a fix.
            entry.selected_san = entry.selected_uci = None
            entry.fen_before = entry.fen_after = last_fen
            entry.is_legal = False
            entry.needs_review = True
            entry.confidence = 0.0
            reason = (ReviewReason.BLOCKED_BY_PREVIOUS_MOVE
                      if analysis.failure_point_ply is not None else ReviewReason.AFTER_GAME_END)
            entry.review_reasons_json = [reason.value]
            entry.fide_alerts_csv = ""
            continue
        entry.selected_san = move.selected_san
        entry.selected_uci = move.selected_uci
        entry.fen_before = move.fen_before
        entry.fen_after = move.fen_after
        entry.is_legal = move.is_legal
        entry.needs_review = move.needs_manual_review
        entry.confidence = move.confidence
        entry.review_reasons_json = [reason.value for reason in move.review_reasons]
        entry.fide_alerts_csv = ",".join(move.fide_alerts)


def status_for_entries(entries: List[MoveEntry]) -> GameStatus:
    return (GameStatus.NEEDS_REVIEW
            if any(entry.needs_review or not entry.is_legal for entry in entries)
            else GameStatus.COMPLETED)
