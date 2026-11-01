# Hakem Masası Pro — abonelik tasarımı ve mağaza kurulumu

Bu belge uygulamadaki gelir modelini, nedenlerini ve mağazaya çıkış adımlarını
anlatır. Kod tarafı: `mobile/lib/monetization/` (planlar, RevenueCat, kota) ve
`mobile/lib/widgets/pro_gate.dart` (erişim kapısı).

## 1. Hakem ne zaman öder?

Bağımsız inceleme ve hakem iş akışından çıkan üç ödeme anı:

1. **Turnuvadan önceki akşam**: "Bu hafta sonu başhakemim / masa hakemiyim."
2. **İlk uyuşmazlıkta**: araç bir kararı gösterdiğinde ve hakem gerekçeyi,
   madde dayanağını ve kaydı istediğinde.
3. **İtiraz kurulu / başhakem için rapor gerektiğinde.**

Kritik kural: **oyuncular masada beklerken paywall açılmaz.** Kota bittiğinde bile
araç karar başlığını (ör. "Üç tekrar: talep DOĞRU", "2. kural dışı hamle —
Siyah kaybeder") ve ilk yapılacak adımı gösterir; gerekçe, madde dayanakları,
hakem kaydı ve rapor kilitlidir. Böylece uygulama tartışma anında güven kazanır,
ödeme isteği "bunu kayda geçireyim / rapor yazayım" anında doğar.

## 2. Ücretsiz ve Pro

| Özellik | Ücretsiz | Pro |
| --- | --- | --- |
| Tahtada oyna, karneden yaz (TR/EN/DE/FR/ES), PGN içe aktar | ✓ | ✓ |
| Yasallık kontrolü, kural dışı/belirsiz hamle tespiti ve nedeni | ✓ | ✓ |
| FIDE zaman çizelgesi (mat, pat, ölü konum, 3/5 tekrar, 50/75 hamle) | ✓ | ✓ |
| Tekrar tablosu ve 9.2.2 uyarıları, tahtadaki konumu kurma | ✓ | ✓ |
| PGN paylaşımı | ✓ | ✓ |
| Talep doğrulama, kural dışı hamle danışmanı, süre aşımı, karne karşılaştırma | Haftada 3 tam kullanım; sonra karar başlığı | Sınırsız, tam gerekçe + kayıt |
| Hakem raporu (PDF / metin) | Haftalık kotadan | ✓ |
| Oyun arşivi | 10 oyun | Sınırsız |
| Fotoğraftan karne okuma (bulut OCR) | — | ✓ (sunucu yapılandırılmışsa) |

Haftalık kota Pazartesi sıfırlanır (`UsageQuota`, yerel saat).

## 3. Planlar ve fiyatlar

Kullanıcının tercihi doğrultusunda ana ürün **haftalık otomatik yenilenen**
"Turnuva Haftası"dır; aylık ve yıllık seçenekler aynı abonelik grubundadır.

| Plan | Ürün kimliği | TR (öneri) | ABD (öneri) | Not |
| --- | --- | --- | --- | --- |
| Turnuva Haftası | `hakem_pro_weekly` | ₺79,99 / hafta | $2.99 | Varsayılan seçili; deneme yok (haftalık kota zaten deneme) |
| Aylık | `hakem_pro_monthly` | ₺149,99 / ay | $5.99 | Ayda 2+ turnuva |
| Yıllık | `hakem_pro_yearly` | ₺699,99 / yıl | $24.99 | 7 gün ücretsiz deneme; haftalığa göre %80+ tasarruf |

Uygulamada gösterilen fiyat her zaman mağazadan gelir; `plans.dart` içindeki
fiyatlar yalnızca önizleme modunda görünür.

### Haftalık modelin riskleri ve önlemler

- *"Abonelik tuzağı" algısı / Türk kullanıcının otomatik yenilemeden çekinmesi:*
  paywall ve plan kartında "otomatik yenilemeyi mağaza ayarlarından tek dokunuşla
  kapatabilirsin" açıkça yazıyor; yıllık plan haftalığın ~4 katı fiyatla sezon
  boyu kullananları korur.
- *Hakem haftaları düzensiz:* deney olarak **yenilenmeyen 7 günlük "Turnuva Pası"**
  (App Store: non-renewing subscription, Play: prepaid plan, ürün kimliği önerisi
  `hakem_pass_7d`) eklenebilir. RevenueCat aynı `pro` yetkisini verebilir; ilk
  sürümde değil, A/B testi olarak önerilir. Yenilenmeyen ürünlerde Apple, satın
  almanın kullanıcının tüm cihazlarında geri yüklenebilmesini bekler.
- *Kurum satışları:* organizatör/kulüp/il temsilciliği için etkinlik başına lisans
  (Apple Offer Code / Play promosyon kodu ile hakemlere dağıtım) ikinci aşamada.
- *Erken destekçiler:* sınırlı süreli "kurucu ömür boyu" (₺1.499 / $39.99)
  lansmanın ilk 3 ayında değerlendirilebilir.

## 4. Mağaza kurulumu

### RevenueCat
1. Proje oluşturun; iOS ve Android uygulamalarını ekleyin
   (paket kimliği: `com.tunahandilercan.hakemmasasi` — Play'e ilk yüklemeden
   sonra değiştirilemez, gerekiyorsa şimdi değiştirin).
2. **Entitlement:** `pro`.
3. Ürünleri içe aktarın, **Offering** `default` içine paketleri koyun:
   Weekly → `hakem_pro_weekly`, Monthly → `hakem_pro_monthly`,
   Annual → `hakem_pro_yearly`. Uygulama paketleri türüne göre eşler.
4. Genel SDK anahtarlarını derlemede verin:
   ```bash
   flutter build appbundle --dart-define=REVENUECAT_ANDROID_KEY=goog_xxx \
     --dart-define=PRIVACY_URL=https://.../gizlilik --dart-define=TERMS_URL=https://.../kosullar
   flutter build ipa --dart-define=REVENUECAT_IOS_KEY=appl_xxx ...
   ```
   Anahtar yoksa uygulama **önizleme modunda** çalışır (debug'da sahte satın alma,
   release'te **ücretsiz sürüm**: her şey açık, satın alma arayüzü gizli — yarım
   kalmış paywall ile 2.1 reddi alınmaz).

### App Store Connect
- Abonelik grubu "Hakem Masası Pro"; üç otomatik yenilenen ürün, Türkçe ve
  İngilizce görünen adlar/açıklamalar.
- Yıllık ürüne 1 haftalık ücretsiz tanıtım teklifi.
- Uygulama gizlilik bilgileri: veri toplanmıyor; satın alma RevenueCat'te anonim
  kimlikle işleniyor; bulut OCR açıksa fotoğraf işleniyor (aşağıdaki gizlilik
  belgesi).
- İnceleme notu: "Sunucusuz satranç hakemi aracı; Pro araçları her hafta 3 kez
  ücretsiz denenebilir, sonra karar başlığı ücretsiz kalır. Sürekli değer: kural
  güncellemeleri ve yeni hakem araçları." (3.1.2(a))
- Paywall'da fiyat, süre, otomatik yenileme metni, Kullanım Koşulları ve Gizlilik
  bağlantıları var (3.1.2).

### Google Play Console
- Abonelik "hakem_pro" altında haftalık, aylık, yıllık temel planlar (ya da üç
  ayrı abonelik — RevenueCat ürün kimliklerini buna göre eşleyin); yıllığa
  7 günlük ücretsiz deneme teklifi.
- Veri güvenliği formu: veri toplanmıyor/paylaşılmıyor; OCR açıksa fotoğraf
  "isteğe bağlı, işleme amaçlı" olarak beyan edilir.
- 13 Kasım 2023 sonrası açılmış kişisel hesaplarda üretime çıkmadan önce
  **en az 12 testçi 14 gün kesintisiz kapalı testte** kalmalı (15–20 hakem
  davet edin). Kurumsal (D-U-N-S) hesaplar bu kuraldan muaftır.

## 5. Ölçülecekler

- Kurulumdan ilk karar ekranına süre; örnek oyunu açanların oranı.
- Haftalık kotayı bitiren kullanıcı oranı ve bitirdikten sonra 24 saat içinde
  satın alma oranı (asıl dönüşüm anı).
- Paywall açılış kaynağı (`feature` parametresi: talep, kural dışı, rapor, arşiv…).
- Haftalık planın 2. haftaya yenilenme oranı; iptal nedenleri.
- Cuma–Pazar satın alma yoğunluğu (turnuva hafta sonu etkisi).

## 6. Ödeme isteğini artıracak sonraki özellikler

Bağımsız incelemeden, etki/efor sırasıyla:

1. **Zaman kontrolü motoru**: 40. hamle kontrolü, 8.4 kayıt muafiyeti başlangıcı,
   iki bayrak birden düştüğünde ne olacağı.
2. **Oyun yeniden kurma**: karnedeki boşluğu diğer karne ve tahtadaki son konumla
   dolduran yasal diziler; karşılaştırma sonucunu tek tıkla birleştirme.
3. **Olay tutanağı**: saat değerleri, tanıklar, tahta fotoğrafı; tek PDF.
4. **"Oyunculara göster" modu**: tam ekran, tekrar eden konumlar yan yana.
5. **Çevrimdışı kural kütüphanesi ve karar ağaçları**: telefon (11.3.2), geç gelme
   (6.7), dokunulan taş (4.x), beraberlik teklifi kuralları.
6. Kilitli piyon yapıları için şah erişilebilirlik analizi (şu an "hakem
   değerlendirmeli" diyor).
7. Turnuva çalışma alanı: TRF/Swiss-Manager eşleştirme içe aktarma, takım maçı.
