"""Bounded, single-page PDF input for the image-based OCR pipeline."""
import io
import math
import threading

import pypdfium2 as pdfium

# PDFium requires serialization even for independent documents.
_pdf_lock = threading.Lock()
MAX_RENDER_EDGE = 3000


def _open_pdf(data: bytes):
    try:
        document = pdfium.PdfDocument(data)
    except pdfium.PdfiumError as exc:
        raise ValueError("PDF is unreadable or password-protected.") from exc
    if len(document) != 1:
        document.close()
        raise ValueError("Upload a single-page PDF. Split multi-page scoresheets into separate files.")
    return document


def validate_pdf(data: bytes) -> None:
    with _pdf_lock:
        with _open_pdf(data):
            pass


def render_pdf(data: bytes) -> bytes:
    with _pdf_lock:
        with _open_pdf(data) as document:
            page = document[0]
            try:
                width, height = page.get_size()
                if not all(math.isfinite(n) and n > 0 for n in (width, height)):
                    raise ValueError("PDF page has invalid dimensions.")
                scale = min(3.0, MAX_RENDER_EDGE / max(width, height))
                bitmap = page.render(scale=scale)
                try:
                    with bitmap.to_pil() as image:
                        output = io.BytesIO()
                        image.save(output, format="PNG")
                        return output.getvalue()
                finally:
                    bitmap.close()
            finally:
                page.close()
