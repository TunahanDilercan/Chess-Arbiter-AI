# Arbiter AI — El yazısı OCR modeli eğitimi

Bu dizin, satranç skor kağıdı hücrelerindeki el yazısı hamleleri tanıyan kendi
modelimizi eğitmek içindir. Hedef: backend'in Claude Vision API bağımlılığını
zamanla kendi fine-tune edilmiş TrOCR modeliyle değiştirmek.

Backend runtime'ından **ayrıdır** — Docker imajına girmez, kendi venv'inde çalışır.

## Mimari karar

- **Hücre-bazlı tanıma.** Backend'in CV hattı her hamleyi ayrı bir hücre olarak
  kesip PNG saklar (`crops/{game_id}/{ply}.png`). Model girdisi = tek hücre crop'u.
  Bu, backend'deki `OCRProvider.recognise_batch` arayüzüne birebir oturur.
- **Çıktı = canonical İngilizce SAN** (örn. `Nf3`, `Qxf7+`, `O-O`, `e8=Q`).
  Türkçe el yazısı girdisi (ŞVKFA) de doğrudan canonical SAN'a eşlenir; tanıma +
  çeviri tek adımda. Böylece gerçek etiketler (`MoveEntry.selected_san` zaten
  canonical) ve `candidate_matcher` beklentisi tek tip kalır.
- **TrOCR fine-tune.** Taban: `microsoft/trocr-base-handwritten`. Çıkan checkpoint
  mevcut `TrOCRProvider`'a `TROCR_MODEL_ID=<checkpoint>` ile takılır (sıfır kod).

## Kurulum

```bash
python -m venv .venv-ml
.venv-ml/Scripts/activate        # Windows ; Linux/mac: source .venv-ml/bin/activate
pip install -r ml/requirements.txt
```

El yazısı fontları (sentetik veri için) `ml/data/fonts/` altına konur. Serbest/lisanslı
el yazısı TTF'leri (örn. Google Fonts: Caveat, Shadows Into Light, Reenie Beanie,
Patrick Hand, ...) indirip buraya koyun. (TTF'ler repoya dahil edilmez.)

## Akış

### Faz 0 — Veri
```bash
# Sentetik veri (başlangıçta ana kaynak — gerçek veri ~yok)
python ml/data/synth_generator.py --n 20000 --locales tr en --out ml/data/datasets/synth

# Gerçek doğrulanmış veri (DB + storage'dan; backend venv/.env gerekir)
python ml/data/export_labels.py --out ml/data/datasets/real
```

### Faz 1 — Eğitim + değerlendirme
```bash
python ml/train/train_trocr.py --config ml/train/config.yaml
python ml/eval/evaluate.py --checkpoint ml/checkpoints/best --data ml/data/datasets/real/test.jsonl
```

### Faz 3 — Backend entegrasyonu
`backend/.env`:
```
OCR_BACKEND=trocr
TROCR_MODEL_ID=/abs/path/to/ml/checkpoints/best
```

## Veri formatı

Her split bir `*.jsonl` + yanında görüntü dosyaları:
```json
{"image": "images/000123.png", "text": "Nf3", "locale": "tr", "source": "synth"}
```
- `text` her zaman canonical İngilizce SAN (etiket).
- `locale` girdinin yazıldığı dil (sadece analiz/filtre için; model çıktısını
  etkilemez).
- Train/val/test ayrımı **oyun/kağıt bazında** yapılır (hücre bazında değil — sızıntı
  olmasın).

## Metrikler (`eval/evaluate.py`)
- **CER** (karakter hata oranı)
- **exact-move accuracy** (top-1 = etiket)
- **top-3 accuracy** (etiket ilk 3 adayda — backend `TROCR_NUM_CANDIDATES=3`)
- **legal-match** (model çıktısı `candidate_matcher` ile gerçek pozisyonda yasal
  hamleye eşleşiyor mu) — asıl uçtan uca hedef metrik.
