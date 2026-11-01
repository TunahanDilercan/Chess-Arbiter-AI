# Hakem Masası (Arbiter AI)

Satranç hakemlerinin **inceleme masası** için mobil uygulama: oyunu tahtada oynayarak,
karneden özel satranç klavyesiyle yazarak ya da PGN yapıştırarak girersiniz; uygulama
her hamleyi **FIDE Satranç Kuralları (1 Ocak 2023)** açısından denetler ve hakeme ne
yapması gerektiğini madde numarasıyla söyler. **Sunucu gerektirmez, internetsiz çalışır.**
Karne fotoğrafından okuma (OCR) isteğe bağlı bir giriş yöntemidir.

## Asıl kullanım senaryosu — itiraz anı

Turnuvada "üç kez tekrar oldu", "elli hamle doldu", "rakibim kural dışı hamle yaptı",
"karneler tutmuyor", "bayrağım düştü ama rakip mat edemez" gibi bir uyuşmazlıkta hakem:

1. Oyunu girer (tahtada oynar / karneden yazar / PGN yapıştırır / iki karneyi karşılaştırır).
2. Uygulama ilk kural dışı, belirsiz veya okunamayan hamlede durur; nedenini ("açmazdaki
   taş", "rok hakkı kaybedilmiş", "hamle sırası kaymış — karnede bir hamle eksik olabilir")
   ve en yakın yasal hamleleri gösterir. Karnedeki ham yazı asla silinmez.
3. Kural zaman çizelgesi: mat, pat, ölü konum (5.2.2), **talep edilebilir** üç tekrar
   (9.2.1.1 / 9.2.1.2) ve 50 hamle (9.3), **otomatik** beş tekrar (9.6.1) ve 75 hamle
   (9.6.2, mat önceliği). Tekrar tablosu 9.2.2 farklarını (rok hakkı, geçerken alma) ayrıca uyarır.
4. Hakem araçları: beraberlik talebi doğrulama (niyet edilen hamle dahil; doğru/yanlış
   talep sonucu ve ceza süresi), kural dışı hamle danışmanı (7.5.1–7.5.5 ceza merdiveni,
   hızlı/yıldırım gözetim kuralları), süre aşımı (6.9 — rakip mat edebilir mi?), iki karneyi
   hizalayıp eksik/fazla hamleyi bulma, zaman damgalı hakem kaydı ve PDF/metin raporu.

**Son kararı her zaman hakem verir.** Uygulama madde özetleri sunar; resmî metin FIDE El
Kitabı'dır.

## Mimari

- **mobile/** — ürünün kendisi (Flutter, iOS + Android). Satranç ve FIDE mantığı
  `mobile/lib/core/` altında saf Dart olarak cihazda çalışır: kendi hamle üreticimiz
  (perft ile doğrulanmış), toleranslı SAN/PGN okuyucu, Türkçe/Almanca/Fransızca/İspanyolca
  notasyon, FIDE katmanı. Oyunlar cihazda saklanır. GPL bağımlılığı yoktur.
- **backend/** — yalnızca isteğe bağlı bulut OCR servisi (FastAPI + Claude Vision, TrOCR
  yedeği). `BACKEND_URL` verilmezse uygulamada fotoğraf seçeneği görünmez.
- **web/** — eski hakem inceleme/ayıklama aracı (Next.js, backend'e bağlı).

## Abonelik

Hamle girişi, yasallık kontrolü, FIDE zaman çizelgesi ve PGN paylaşımı her zaman ücretsiz.
**Hakem Masası Pro** (talep doğrulama, kural dışı hamle danışmanı, süre aşımı, karne
karşılaştırma, PDF rapor, sınırsız arşiv, OCR) haftalık **Turnuva Haftası**, aylık ve yıllık
planlarla sunulur; Pro araçları her hafta 3 kez ücretsiz denenebilir. Ayrıntılar ve mağaza
kurulumu: [docs/MONETIZATION_TR.md](docs/MONETIZATION_TR.md).

## Mobil geliştirme

```bash
cd mobile
flutter pub get
flutter analyze && flutter test          # 60+ test: perft, FIDE kuralları, widget akışları
flutter run                              # sunucusuz; abonelik "önizleme" modunda
# Gerçek mağaza ve OCR ile:
flutter run --dart-define=REVENUECAT_ANDROID_KEY=goog_xxx \
            --dart-define=REVENUECAT_IOS_KEY=appl_xxx \
            --dart-define=BACKEND_URL=https://ocr.example.com
```

## OCR servisi (isteğe bağlı) — geliştirme ortamı

Tüm servisleri tek komutla ayağa kaldırmak için:

```bash
docker-compose up --build
```

- API ve Swagger dokümanı: http://localhost:8000/docs
- Web aracı: `cd web && npm install && npm run dev` → http://localhost:3000

Mobil uygulamayı bu servise bağlamak için:
`flutter run --dart-define=BACKEND_URL=http://192.168.1.x:8000`

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
cd ../mobile && flutter analyze && flutter test
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
- [docs/MONETIZATION_TR.md](docs/MONETIZATION_TR.md) — abonelik tasarımı, fiyatlar, mağaza kurulumu
- [docs/OFFLINE_FIRST_OPTIONS_TR.md](docs/OFFLINE_FIRST_OPTIONS_TR.md) — çevrimdışı mimari araştırması
