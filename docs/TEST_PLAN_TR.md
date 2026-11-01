# Hakem Masası — test planı

## 1. Otomatik testler (mevcut)

```bash
cd mobile
flutter analyze        # temiz olmalı
flutter test           # 234 test
```

| Paket | İçerik |
| --- | --- |
| `test/core/chess_engine_test.dart` | 6 referans konumda **perft** (197.281 düğüme kadar), FEN, SAN yazma, toleranslı okuma (yazım uyarısı ≠ kural dışı), belirsiz hamle, kural dışı açıklamaları, TR/DE/FR/ES notasyon, PGN, benzerlik sıralaması |
| `test/core/arbiter_test.dart` | 3/5 tekrar, rok hakkı ve geçerken alma farkı (9.2.2), açmazdaki piyonla geçerken alma, 50/75 hamle, mat önceliği, pat, ölü konum, talep (niyet edilen hamle, alma ile sayaç sıfırlanması, kural dışı niyet hamlesi, 9.1.2.3), 7.5.5 ceza merdiveni ve gözetim, 6.9 (mat/pat önceliği, kilitli piyonlar), karne karşılaştırma, rapor, kayıt |
| `test/core/oracle_test.dart` | **python-chess ile diferansiyel test**: 160 yönlendirilmiş rastgele oyun, 21.701 yarım hamlede SAN, FEN, şah/mat/pat, ölü konum, tekrar sayısı, hamle sayacı ve otomatik bitiş birebir aynı |
| `test/services/report_pdf_test.dart` | Türkçe karakterli PDF üretimi |
| `test/widget_test.dart` | İlk açılış uyarısı, örnek oyun, tahtada hamle, konum kurma, önizleme satın alma, kota bitince paywall açılmaması, haftalık kota |

Kâhin fikstürünü yeniden üretmek (python-chess kaynağı PYTHONPATH'te):

```bash
cd mobile && PYTHONPATH=/path/to/python-chess python3 tool/gen_oracle_fixture.py
```

### Büyük ölçekli doğrulama (`mobile/test_slow/`, ~4 dk)

Her sürümden ve `lib/core/` değişikliğinden önce çalıştırılır
(`flutter test test_slow --concurrency=4`). Son çalıştırma — hepsi geçti:

| Kâhin | Kapsam |
| --- | --- |
| python-chess, gerçek oyunlar | 16.679 turnuva oyunu (TWIC, Bundesliga, İngiltere şampiyonaları), 1.362.072 yarım hamle: SAN, şah/mat/pat, ölü konum, tekrar sayıları, sayaç, FEN; `checkClaim` ile 99.540 üç tekrar / 50 hamle talep kontrolü; PGN okuyucu ham dosyalarda |
| Stockfish 17.1 perft | 3.132 konumda perft-divide(3) = 118.293.808 düğüm; 6 referans konumda derin divide (başlangıç derinlik 5: 4.865.609) |
| python-chess SAN | 3.132 konumun tüm yasal SAN listeleri |
| Gidiş-dönüş | 100.244 yasal hamle: SAN, TR/EN/DE/FR/ES, UCI, "+"/"#" eksik yazım, uzun notasyon |
| python-chess, yönlendirilmiş oyunlar | 4.000 oyun, 557.743 yarım hamle; 936 beş tekrar, 487 kez 75 hamle, 1.287 ölü konum |

Bu paketin bulduğu ve düzeltilen hatalar: hamlesiz (bay/hükmen) oyunun PGN'de
sonraki oyunun başlıklarını yutması (oyuncu isimleri kayıyordu); UCI'de küçük
harfli terfi (`c7c8q`); aynı hamlede beş tekrar + 75 hamlenin ikisinin de
kaydedilmesi (9.6).

## 2. Eklenecek otomatik testler

- Kâhin testinin daha büyük oyun arşivleriyle (ör. Lichess açık veritabanı)
  genişletilmesi ve CI'da gece çalıştırılması.
- Aynı yarım hamlede hem 5 tekrar hem 75 hamle; alarak terfinin sayacı sıfırlaması;
  rokun sayacı sıfırlamaması.
- OCR/el yazısı büyük-küçük harf karışıklığı: `Fxe5` ve `fxe5` ikisi de yasalken
  sessiz seçim yapılmaması; `A`/`a`, `Ş`/`S`.
- Terfi taşı yazılmamış `e8`: yazım hatası mı 7.5.2 mi — hakem kararına bırakılmalı.
- Golden (ekran görüntüsü) testleri: inceleme, talep ve paywall ekranları; açık ve
  koyu tema; Türkçe İ/ı/Ş.
- Satın alma: Apple sandbox (haftalık abonelik dakikalar içinde yenilenir), Play
  lisans testçileri; geri yükleme, yeniden kurulum, iade, **internetsiz Pro**
  (RevenueCat önbelleği ve süre bitimi).

## 3. Saha testi

- **Kimlerle:** 8–12 hakem; il, ulusal ve FA/IA karışık, en az bir başhakem.
- **Nerede (3–4 etkinlik):** hafta sonu açık İsviçre, hızlı/yıldırım turnuvası,
  takım ligi, yaş grubu şampiyonası (kural dışı hamle ve karne hatası en sık).
- **Ölçülecekler:**
  - Uygulamayı açmaktan karara kadar süre (hedef < 60 sn).
  - Klavyeyle karne giriş hızı (hamle/dakika).
  - **Uyuşmazlık kaydı:** uygulamanın önerisi ile hakemin/başhakemin kararı
    farklıysa her vaka incelenir.
  - Çökme, çevrimdışı kullanım oranı, en çok kullanılan araç.
- **Gölge mod:** Geçmiş tartışmalı 50+ gerçek karne (KVKK onayıyla, isimler
  anonimleştirilmiş) yeniden girilip sonuçlar karşılaştırılır.

## 4. Mağaza beta süreci

1. **TestFlight**: önce dahili, sonra harici test (Apple beta incelemesi).
2. **Google Play**: kişisel hesapta 12+ testçi × 14 gün kesintisiz kapalı test
   (15–20 hakem davet edin). Hakem WhatsApp grupları en hızlı kanal.
3. Beta süresince uygulama içi "Sorun bildir" yerine kısa bir form bağlantısı ve
   haftalık geri bildirim görüşmesi.

## 5. Yayın öncesi kontrol listesi

- [ ] RevenueCat anahtarları, ürünler, `pro` yetkisi, `default` offering
- [ ] Gizlilik politikası ve kullanım koşulları barındırıldı; `PRIVACY_URL`,
      `TERMS_URL` derlemeye verildi
- [ ] App Privacy / Data Safety formları
- [ ] Android release imzası (şu an debug imzası) ve AAB
- [ ] iOS: gerçek cihaz, kamera/galeri izin metinleri, OCR kapalıyken izin istenmiyor
- [ ] Madde metinlerinin güncel FIDE El Kitabı ile son karşılaştırması
- [ ] Mağaza metninde "FIDE onaylı/resmi" ifadesi yok; logo kullanılmıyor
