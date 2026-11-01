# Hakem Masası — App Store / Google Play uyumluluk dosyası

Bu belge, App Store İnceleme Yönergeleri'nde en sık red sebebi olan maddeleri
uygulamadaki karşılıklarıyla eşler ve gönderim öncesi yapılacakları listeler.
Kaynaklar sonda.

## 1. Red sebepleri → uygulamadaki karşılığı

| Yönerge | Sık red sebebi | Hakem Masası'nda | Durum |
| --- | --- | --- | --- |
| **2.1** Uygulama bütünlüğü | Çökme, boş ekran, çalışmayan düğme, "yakında" özellikler, inceleyicinin deneyemediği satın alma | Tüm ekranlar çevrimdışı çalışır; örnek oyun tek dokunuşla yüklenir. RevenueCat anahtarı olmayan release derlemesi **ücretsiz sürüm** olur: her şey açık, satın alma arayüzü gizli (yarım kalmış paywall yok). OCR adresi verilmemişse fotoğraf seçeneği hiç görünmez | ✅ |
| **2.1** | Küçük ekran / büyük yazıda taşma | `test/ux_matrix_test.dart`: iPhone SE, 360 dp Android, iPhone 15 Pro, iPad × yazı ölçeği 1.0/1.35/2.0 × açık/koyu; 11 ekran + 3 sayfa. Taşma testi kırar | ✅ |
| **2.3** Doğru meta veri | Ekran görüntüsünde olmayan özellik, "FIDE onaylı" gibi yanlış iddia | Ekran görüntüleri gerçek uygulamadan (bkz. §4). Metinde "FIDE onaylı/resmi" yok; FIDE yalnızca "FIDE Satranç Kuralları'na göre" şeklinde tanımlayıcı olarak geçer | ⚠️ metinde dikkat |
| **2.3.7** | Ad/alt başlıkta anahtar kelime doldurma, marka adı | Ad: "Hakem Masası" (30 karakter sınırı). Alt başlıkta "FIDE" yok | ✅ |
| **2.5.2** | İndirilen kod çalıştırma | Yok | ✅ |
| **3.1.1** Uygulama içi satın alma | Dijital özelliği harici ödemeyle satmak | Yalnızca StoreKit/Play Billing (RevenueCat) | ✅ |
| **3.1.2(a)** Abonelik süresi | 7 günden kısa abonelik | En kısa plan 1 hafta | ✅ |
| **3.1.2(c)** Abonelik bilgisi | Tahsil edilen tutar en belirgin fiyat değil; deneme sonrası ücret gizli; yenileme/iptal açıklanmamış | Paywall'da her plan fiyatı/periyodu büyük yazılır; CTA'nın hemen altında "₺79,99 her hafta tahsil edilir; iptal edene kadar otomatik yenilenir." Denemeli planda "7 gün ücretsiz, sonra ₺699,99/yıl …". Alt metin: Apple ID/Google hesabından tahsil, dönem bitiminden 24 saat önce iptal edilmezse yenileme, iptal edince dönem sonuna kadar Pro sürer | ✅ |
| **3.1.2(c)** | Gizlilik politikası ve Kullanım Koşulları (EULA) bağlantısı yok | Paywall altında ve Ayarlar → "Abonelik ve yasal" bölümünde: Gizlilik, Kullanım koşulları (varsayılan Apple standart EULA), Destek | ✅ (URL'ler barındırılmalı) |
| **3.1.1 / 3.1.2** | "Satın alımları geri yükle" yok | Paywall ve Ayarlar'da | ✅ |
| **3.1.2** | Aboneliği yönetme/iptal yolu yok | Pro kartında ve Ayarlar'da "Aboneliği yönet / iptal et" → RevenueCat `managementURL` ya da mağaza abonelik sayfası | ✅ |
| **3.1.2** | Paywall kapatılamıyor, uygulama kullanılamıyor | Paywall her zaman kapatılabilir (✕); temel doğrulama her zaman ücretsiz; anlaşmazlık araçları kota bitince bile sonucun başlığını gösterir | ✅ |
| **4.0** Tasarım | Varsayılan Flutter ikonu, boş açılış ekranı | Özel ikon (iOS AppIcon, Android adaptif, web), markalı açılış ekranı (açık/koyu) | ✅ |
| **4.2** Asgari işlev | "Web sitesini sarmalayan" uygulama | Yerel satranç motoru, FIDE araçları, PDF rapor — tamamen çevrimdışı | ✅ |
| **5.1.1** Veri toplama | İzin metni belirsiz, gereksiz izin, hesap zorunluluğu | Hesap yok. Kamera/galeri metinleri amaç belirtir ve yalnızca OCR seçilince istenir | ✅ |
| **5.1.1(v)** | Hesap silme yok | Hesap oluşturulmuyor; "Tüm verileri sil" ayarlarda | ✅ |
| **5.1.2** | Gizlilik bildirimi ile gerçek davranış uyuşmuyor | Bkz. §3 | ⚠️ form doldurulacak |
| **Gizlilik bildirimi (2024+)** | `PrivacyInfo.xcprivacy` eksik veya "required reason API" beyanı yok (ITMS-91053) | `ios/Runner/PrivacyInfo.xcprivacy`: izleme yok; UserDefaults `CA92.1`, dosya zaman damgası `C617.1`. RevenueCat ve diğer SDK'lar kendi bildirimlerini getirir | ✅ |
| **Şifreleme beyanı** | Her yüklemede ihracat uyumu sorusu | `ITSAppUsesNonExemptEncryption = false` (yalnızca HTTPS) | ✅ |
| **5.2.1** Fikri mülkiyet | Başkasının logosu/markası | FIDE logosu yok. Taşlar Chessnut (Apache-2.0), fontlar OFL; lisanslar Ayarlar → Lisanslar'da | ✅ |
| **1.4 / sorumluluk** | Yanlış yönlendirme riski olan "karar veren" uygulama | Her sonuçta FIDE maddesi; ilk açılışta ve sonuçlarda "uygulama önerir, karar hakemindir" | ✅ |

## 2. Gönderim öncesi yapılacaklar

1. **Bağlantıları herkese açık barındırın.** Repo özelse GitHub adresleri
   inceleyiciye 404 verir → red (3.1.2, 5.1.1). GitHub Pages / basit bir site:
   ```bash
   flutter build ipa --release \
     --dart-define=REVENUECAT_IOS_KEY=appl_xxx \
     --dart-define=PRIVACY_URL=https://.../gizlilik \
     --dart-define=TERMS_URL=https://.../kosullar \
     --dart-define=SUPPORT_URL=https://.../destek
   ```
   Aynı gizlilik adresi App Store Connect → App Privacy'ye, destek adresi
   "Support URL" alanına yazılır. Kendi EULA'nız yoksa Apple standart EULA
   kullanılır; açıklamanın sonuna da EULA bağlantısı eklenir.
2. **App Store Connect abonelikleri:** Tek abonelik grubu "Hakem Masası Pro";
   `hakem_pro_weekly`, `hakem_pro_monthly`, `hakem_pro_yearly` (yıllıkta 1 haftalık
   ücretsiz tanıtım teklifi). Her ürüne yerelleştirilmiş ad/açıklama ve **inceleme
   ekran görüntüsü** (paywall). Abonelikler ilk sürümle **birlikte** incelemeye
   gönderilmeli; "Missing Metadata" durumunda ürün sandbox'ta görünmez → 2.1 reddi.
3. **Paid Apps sözleşmesi**, banka ve vergi bilgileri aktif olmalı; yoksa paketler
   inceleme ortamında yüklenmez.
4. **İnceleme notu (App Review Information → Notes):**
   > Hesap gerekmez; uygulama tamamen çevrimdışı çalışır. Ana sayfada "Örnek oyunu
   > aç" → hamle listesinde kırmızı 25…gxh6 kural dışı hamledir; "Talep kontrolü" ve
   > "Kural dışı hamle" araçları FIDE maddeleriyle sonuç verir. Pro abonelik ekranı:
   > Ayarlar → Hakem Masası Pro. Haftada 3 Pro kullanım ücretsizdir; satın almayı
   > sandbox hesabıyla deneyebilirsiniz. OCR (karne fotoğrafı) bu sürümde kapalıdır.
5. **Yaş derecelendirmesi:** 4+ (şiddet, kumar, kullanıcı içeriği yok).
6. **Kategori:** Birincil "Spor" ya da "Yardımcı Araçlar"; ikincil "Referans".
7. **Android:** `android/key.properties` ile release imzası (aşağıda), AAB,
   Play Console → Data Safety: "Veri toplanmıyor / paylaşılmıyor" (OCR kapalıyken).
   Kişisel hesapta yayın öncesi 12+ testçi × 14 gün kapalı test.

### Android imzası

```properties
# mobile/android/key.properties  (git'e EKLEMEYİN)
storeFile=/abs/path/upload-keystore.jks
storePassword=...
keyAlias=upload
keyPassword=...
```
`keytool -genkey -v -keystore upload-keystore.jks -keyalg RSA -keysize 2048
-validity 10000 -alias upload`. Dosya yoksa release derlemesi debug imzasına
düşer (yalnızca yerel deneme içindir).

## 3. Gizlilik formları

| Durum | App Store "App Privacy" | Play "Data Safety" |
| --- | --- | --- |
| OCR kapalı (varsayılan) | Uygulama verisi **toplanmıyor**. RevenueCat: "Satın alımlar" + "Kimlikler (kullanıcı kimliği, anonim)" — uygulama işlevi için, kimliğe bağlı değil, izleme yok | Satın alma geçmişi (RevenueCat); şifreli aktarım; silme talebi destek adresinden |
| OCR açık (`BACKEND_URL`) | Ek olarak "Fotoğraflar" (kullanıcı içeriği) — uygulama işlevi, kimliğe bağlı değil, saklanmıyor | Ek olarak "Fotoğraflar" — işlev için, geçici |

Oyunlar, notlar ve raporlar yalnızca cihazda tutulur (docs/PRIVACY_TR.md).

## 4. Mağaza metni (TR)

- **Ad (30):** Hakem Masası
- **Alt başlık (30):** Satranç hakemi analiz masası
- **Tanıtım metni (170):** Karnedeki hamleleri saniyeler içinde kontrol et: kural
  dışı hamle, üç tekrar, 50 hamle ve bayrak düşmesi kararları madde numarasıyla.
- **Anahtar kelimeler (100):** satranç,hakem,karne,tekrar,50 hamle,kural dışı,pgn,turnuva,arbiter,notasyon
- **Açıklama (özet):** Ne işe yarar → nasıl girilir (tahta, karne klavyesi, PGN,
  iki karne karşılaştırma) → araçlar → çevrimdışı/gizlilik → Pro planlar ve
  yenileme koşulları → "FIDE ile bağlantılı değildir; kararı hakem verir." →
  Gizlilik ve Kullanım Koşulları bağlantıları.

### Ekran görüntüsü planı (6,9" ve 6,5" iPhone, 13" iPad; Play telefon + 7"/10")

1. Analiz: kırmızı işaretli kural dışı hamle + madde ("25…gxh6 — 7.5.1")
2. Talep kontrolü sonucu (üç tekrar, "talep edilebilir" — otomatik değil)
3. Karne klavyesi (Ş V K F A) ve öneri çipleri
4. İki karne karşılaştırma
5. Bayrak düşmesi / mat imkânı
6. PDF hakem raporu
7. Paywall (fiyatlar ve yenileme metni görünür)

Görüntüler `flutter build web --profile` + Playwright ile ya da simülatörden
alınabilir; gerçek ekran dışında mockup metni eklenmez.

## 5. Kaynaklar

- [App Store Review Guidelines](https://developer.apple.com/app-store/review/guidelines/)
- [Auto-renewable subscriptions — App Store](https://developer.apple.com/app-store/subscriptions/)
- [Privacy manifest files](https://developer.apple.com/documentation/bundleresources/privacy-manifest-files)
- [Describing use of required reason API](https://developer.apple.com/documentation/bundleresources/describing-use-of-required-reason-api)
- [App Privacy details](https://developer.apple.com/app-store/app-privacy-details/)
- [Apple Developer Forums — 3.1.2 subscription rejections](https://developer.apple.com/forums/thread/807082)
- [Google Play — Data safety](https://support.google.com/googleplay/android-developer/answer/10787469)
- [Google Play — Subscriptions policy](https://support.google.com/googleplay/android-developer/answer/9900533)
