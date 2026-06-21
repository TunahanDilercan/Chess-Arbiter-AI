# Arbiter AI

El yazısı satranç skor kağıtlarını fotoğraftan okuyup hamleleri FIDE kurallarına
göre denetleyen bir araç. Turnuvalarda hakemlik yaparken skor kağıtlarını tek tek
elle kontrol etmek hem yavaş hem de gözden kaçmaya açık; bu proje o işi hızlandırmak
için yazıldı ve hâlâ aktif olarak geliştiriliyor.

Mantık basit: kağıdın fotoğrafını çek, sistem hamleleri okusun, her hamleyi tahtada
doğrulasın, okuyamadığı ya da emin olamadığı yerleri sana işaretlesin. Son kararı
her zaman hakem verir — uygulama yalnızca okuduğunu ve doğrulama sonucunu gösterir,
hamle geçerliliğine kendisi karar vermez.

## Nasıl çalışıyor

1. **Okuma (OCR).** Skor kağıdı şu an Claude Vision API ile bütün olarak okunuyor.
   El yazısı doğruluğu yerel modellere göre belirgin biçimde daha iyi ve kağıttaki
   ızgara düzgün çıkmasa bile sonuç verebiliyor.
2. **Doğrulama.** Okunan her hamle backend'de `python-chess` ile o pozisyondaki
   yasal hamlelere karşı eşleştiriliyor. OCR çıktısına asla doğrudan güvenilmiyor;
   bir hamle yasal hamlelerden biriyle eşleşmiyorsa düşük güven puanıyla manuel
   düzeltmeye düşüyor.
3. **FIDE analizi.** Üçlü/beşli tekrar, elli/yetmiş beş hamle kuralı, mat, pat gibi
   durumlar ayrıştırılıyor. Talep edilebilen (üçlü tekrar, elli hamle) ile otomatik
   (beşli tekrar, yetmiş beş hamle) beraberlik durumları ayrı ayrı etiketleniyor —
   bu ayrım yanlış olursa analiz de yanlış olur.
4. **Düzeltme.** Şüpheli ya da okunamayan hamleler özel bir satranç klavyesiyle elle
   düzeltiliyor; backend düzeltmeyi yeniden doğrulayıp oyunu o noktadan itibaren
   tekrar hesaplıyor.

## Yol haritası

Şu anki kurulum okuma için harici API'ye bağlı. Asıl hedef, turnuvalardan toplanan
gerçek skor kağıdı örnekleriyle kendi OCR modelini eğitmek; böylece sistem API'ye
ihtiyaç duymadan, çevrimdışı çalışabilecek. Veri toplama ve etiketleme bu yönde
ilerliyor.

## Stack

- **Backend:** FastAPI, python-chess, OpenCV, Celery + Redis, PostgreSQL
- **Mobil:** Flutter (iOS + Android), Riverpod, Dio
- **Web:** Next.js 14 + TypeScript — hakem inceleme/ayıklama aracı (asıl ürün mobil)
- **OCR:** Claude Vision API (varsayılan), GPU'lu makinelerde TrOCR yedeği

İş kuyruğu uzun süren okuma/analiz işlerini arka plana alıyor; mobil tarafa ilerleme
SSE ile canlı akıyor.

## Geliştirme ortamı

Tüm servisleri tek komutla ayağa kaldırmak için:

```bash
docker-compose up --build
```

- API ve Swagger dokümanı: http://localhost:8000/docs
- Web aracı: `cd web && npm install && npm run dev` → http://localhost:3000

Mobil:

```bash
cd mobile
flutter pub get
flutter run
# Backend farklı bir adresteyse:
flutter run --dart-define=BACKEND_URL=http://192.168.1.x:8000
```

## OCR yapılandırması

Anahtarlar ve ayarlar `backend/.env` dosyasından okunur (`backend/.env.example`
kopyalayıp doldurun — gerçek `.env` git'e dahil değildir):

```bash
ANTHROPIC_API_KEY=...           # OCR_BACKEND=claude için gerekli
OCR_BACKEND=claude              # claude | trocr | tesseract
OCR_FALLBACK_TO_TROCR=true      # Claude hatasında yerel TrOCR'a düş
```

API anahtarı olmadan denemek için `OCR_BACKEND=trocr` kullanılabilir; ancak GPU'suz
makinelerde yavaş ve doğruluğu düşüktür.

## Test

```bash
cd backend && pytest -q      # backend test paketi
cd ../mobile && flutter analyze
cd ../web && npm run build    # TS strict derleme
```

## Üretim

İnternete açık sunucu için `docker-compose.prod.yml` (nginx TLS, rate limiting,
güvenlik başlıkları, root olmayan container). Ayrıntılar
[docs/DEPLOYMENT.md](docs/DEPLOYMENT.md).

```bash
docker compose -f docker-compose.prod.yml up -d
```

## Güvenlik notları

- Yükleme dosyaları magic-byte ile doğrulanır (uzantı/Content-Type'a güvenilmez).
- IP başına rate limit (varsayılan 120/dk, yükleme 10/dk).
- Güvenlik başlıkları (nosniff, frame-deny, opsiyonel HSTS).
- Giriş/hesap yok; oturumlar anonim ve geçicidir.

## Belgeler

- [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) — sistem mimarisi ve veri akışı
- [docs/FIDE_RULES.md](docs/FIDE_RULES.md) — uygulanan FIDE kuralları
- [docs/OCR_PIPELINE.md](docs/OCR_PIPELINE.md) — okuma hattının detayları
