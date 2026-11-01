# Hakem Masası — App Store / Google Play uyumluluk dosyası

Bu belge, App Store İnceleme Yönergeleri'nde en sık red sebebi olan maddeleri
uygulamadaki karşılıklarıyla eşler ve gönderim öncesi yapılacakları listeler.
Kaynaklar sonda.

## 1. Red sebepleri → uygulamadaki karşılığı

| Yönerge | Sık red sebebi | Hakem Masası'nda | Durum |
| --- | --- | --- | --- |
| **2.1** Uygulama bütünlüğü | Çökme, boş ekran, çalışmayan düğme, "yakında" özellikler, inceleyicinin deneyemediği satın alma | Tüm ekranlar çevrimdışı çalışır; örnek oyun tek dokunuşla yüklenir. RevenueCat anahtarı olmayan release derlemesi **ücretsiz sürüm** olur: her şey açık, satın alma arayüzü gizli (yarım kalmış paywall yok). OCR adresi verilmemişse fotoğraf seçeneği hiç görünmez | ✅ |
| **2.1** | Küçük ekran / büyük yazıda taşma | `test/ux_matrix_test.dart`: iPhone SE, 360 dp Android, iPhone 15 Pro, iPad, yatay iPhone × yazı ölçeği 1.0/1.35/2.0 × açık/koyu; 11 ekran + 3 sayfa. Taşma testi kırar | ✅ |
| **2.1** | Pro kullanıcıdan derin bağlantıda ücretsiz hak düşmesi | Abonelik durumu ilk okumada senkron (`EntitlementNotifier`); regresyon testi var | ✅ (düzeltildi) |
| **2.3** Doğru meta veri | Ekran görüntüsünde olmayan özellik, "FIDE onaylı" gibi yanlış iddia | Ekran görüntüleri gerçek uygulamadan (bkz. §4). Metinde "FIDE onaylı/resmi" yok; FIDE yalnızca "FIDE Satranç Kuralları'na göre" şeklinde tanımlayıcı olarak geçer | ⚠️ metinde dikkat |
| **2.3.7** | Ad/alt başlıkta anahtar kelime doldurma, marka adı | Ad "Hakem Masası: Satranç Hakemi", alt başlık "Kural dışı hamle, talep, PGN"; ad, alt başlık ve anahtar kelimelerde "FIDE" yok (`test/store_metadata_test.dart` denetler) | ✅ |
| **2.3.8** | Cihazdaki ad mağaza adından çok farklı | Ana ekran adı "Hakem Masası", mağaza adı "Hakem Masası: Satranç Hakemi" | ✅ |
| **2.3.10** | Uygulamada/metinde başka platform adı ("Google Play", "Android") | Abonelik metni platforma göre: iOS'ta yalnızca "Apple (App Store)", Android'de "Google Play" (`storeAccountName()`); iOS meta verisinde Android/Play geçmez (test) | ✅ (düzeltildi) |
| **2.3 / dil** | Uygulama Türkçe ama sistem metinleri İngilizce, mağazada dil "English" | `flutter_localizations` + `Locale('tr')` (kopyala/yapıştır, geri, lisans sayfası Türkçe); iOS `CFBundleDevelopmentRegion=tr`, `CFBundleLocalizations=[tr]`, `tr.lproj/InfoPlist.strings` → App Store dil olarak Türkçe gösterir | ✅ (düzeltildi) |
| **2.5.2** | İndirilen kod çalıştırma | Yok | ✅ |
| **3.1.1** Uygulama içi satın alma | Dijital özelliği harici ödemeyle satmak | Yalnızca StoreKit/Play Billing (RevenueCat) | ✅ |
| **3.1.2(a)** Abonelik süresi | 7 günden kısa abonelik | En kısa plan 1 hafta | ✅ |
| **3.1.2(c)** Abonelik bilgisi | Tahsil edilen tutar en belirgin fiyat değil; deneme sonrası ücret gizli; yenileme/iptal açıklanmamış | Paywall'da her plan fiyatı/periyodu büyük yazılır; CTA'nın hemen altında "₺79,99 her hafta tahsil edilir; iptal edene kadar otomatik yenilenir." Denemeli planda "7 gün ücretsiz, sonra ₺699,99/yıl …". Alt metin: Apple ID/Google hesabından tahsil, dönem bitiminden 24 saat önce iptal edilmezse yenileme, iptal edince dönem sonuna kadar Pro sürer | ✅ |
| **3.1.2(c)** | Gizlilik politikası ve Kullanım Koşulları (EULA) bağlantısı yok | Paywall altında ve Ayarlar → "Abonelik ve yasal" bölümünde: Gizlilik, Kullanım koşulları (varsayılan Apple standart EULA), Destek | ✅ (URL'ler barındırılmalı) |
| **3.1.1 / 3.1.2** | "Satın alımları geri yükle" yok | Paywall ve Ayarlar'da | ✅ |
| **3.1.2** | Aboneliği yönetme/iptal yolu yok | Pro kartında ve Ayarlar'da "Aboneliği yönet / iptal et" → RevenueCat Customer Center (iptal, iade talebi, geri yükleme); olmazsa mağaza abonelik sayfası | ✅ |
| **3.1.2 / 2.3.1** | Kullanıcının alamayacağı ücretsiz deneme gösterilmesi | iOS'ta deneme uygunluğu RevenueCat ile sorgulanır; uygun değilse deneme metni ve "Ücretsiz denemeyi başlat" gösterilmez | ✅ |
| **3.1.2** | Satın alma düğmesi ile ücret metni arasında mesafe | CTA ve tahsilat cümlesi ekranın altına sabit; kaydırmadan her zaman görünür. "%… tasarruf" ve haftalık eşdeğer fiyat ikincil, faturalanan tutar en büyük yazı | ✅ |
| **3.1.2** | Paywall kapatılamıyor, uygulama kullanılamıyor | Paywall her zaman kapatılabilir (✕); temel doğrulama her zaman ücretsiz; anlaşmazlık araçları kota bitince bile sonucun başlığını gösterir | ✅ |
| **4.0** Tasarım | Varsayılan Flutter ikonu, boş açılış ekranı | Özel ikon (iOS AppIcon, Android adaptif, web), markalı açılış ekranı (açık/koyu) | ✅ |
| **4.2** Asgari işlev | "Web sitesini sarmalayan" uygulama | Yerel satranç motoru, FIDE araçları, PDF rapor — tamamen çevrimdışı | ✅ |
| **5.1.1** Veri toplama | İzin metni belirsiz, gereksiz izin, hesap zorunluluğu | Hesap yok. Kamera/galeri metinleri amaç belirtir ve yalnızca OCR seçilince istenir | ✅ |
| **5.1.1(v)** | Hesap/veri silme yok | Hesap oluşturulmuyor; Ayarlar → "Tüm verileri sil" (oyunlar, kayıtlar, notlar, ayarlar; onaylı) | ✅ (eklendi) |
| **5.1.1(i)** | Gizlilik politikasında iletişim yok / erişilemiyor | `docs/gizlilik.html` + `docs/index.html` (destek) hazır; **iletişim e-postası eklenmeli ve sayfalar yayımlanmalı** | ⚠️ sizde |
| **5.1.2** | Gizlilik bildirimi ile gerçek davranış uyuşmuyor | Bkz. §3 | ⚠️ form doldurulacak |
| **Gizlilik bildirimi (2024+)** | `PrivacyInfo.xcprivacy` eksik veya "required reason API" beyanı yok (ITMS-91053) | `ios/Runner/PrivacyInfo.xcprivacy`: izleme yok; UserDefaults `CA92.1`, dosya zaman damgası `C617.1`. RevenueCat ve diğer SDK'lar kendi bildirimlerini getirir | ✅ |
| **Şifreleme beyanı** | Her yüklemede ihracat uyumu sorusu | `ITSAppUsesNonExemptEncryption = false` (yalnızca HTTPS) | ✅ |
| **5.2.1** Fikri mülkiyet | Başkasının logosu/markası | FIDE logosu yok. Taşlar Celtic/Spatial/Fantasy (MIT) ve Chessnut (Apache-2.0), fontlar OFL; lisanslar Ayarlar → Lisanslar'da | ✅ |
| **Derleme SDK'sı** | Eski Xcode/SDK ile yükleme reddi | 28 Nisan 2026'dan beri Xcode 26 + iOS 26 SDK zorunlu; dağıtım hedefi iOS 13 kalabilir | ⚠️ Mac'te Xcode 26 ile derleyin |
| **Yaş derecelendirmesi** | Yeni anket (31 Ocak 2026) cevaplanmamış | Tüm sorulara "Hayır/Yok" → 4+ (kullanıcı içeriği, sohbet, kumar, tıbbi içerik, reklam yok; sosyal medya sorularına "Hayır") | ⚠️ App Store Connect'te |
| **AB DSA** | AB'de yayın için "trader" beyanı | App Store Connect → Business: tacir/tacir değil beyanı; tacirse adres/telefon/e-posta ürün sayfasında görünür | ⚠️ sizde |
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
   Play Console → Data Safety: yalnızca satın alma geçmişi + anonim kimlik (bkz. `GOOGLE_PLAY_TR.md`).
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

## 4. ASO / PSO — mağaza metinleri ve görseller

Metinler `mobile/store/` altında fastlane düzeninde; `test/store_metadata_test.dart`
her test çalışmasında karakter/bayt sınırlarını, anahtar kelime tekrarını, yasak
ifadeleri ("#1", "en iyi", "FIDE onaylı"), iOS'ta Android/Play, Play'de
Apple/App Store geçmesini denetler.

| Alan | App Store (tr) | App Store (en-GB) | Google Play (tr-TR) |
| --- | --- | --- | --- |
| Ad / başlık (30) | Hakem Masası: Satranç Hakemi | Hakem Masası: Chess Arbiter | Hakem Masası: Satranç Hakemi |
| Alt başlık (30) / kısa açıklama (80) | Kural dışı hamle, talep, PGN | Claims, illegal moves, rules | Kural dışı hamle, üç tekrar, 50 hamle, süre aşımı: maddesiyle karar, internetsiz |
| Anahtar kelimeler (100 bayt) | tekrar, beraberlik, karne, notasyon, turnuva, arbiter, chess, yasal, analiz, süre, bayrak, rapor, referee | referee, threefold, repetition, fifty, draw, scoresheet, notation, tournament, laws, flag, pgn, kurallar | (Play anahtar kelime alanı yok; açıklama dizinlenir) |

ASO kararları:
- **Ad + alt başlık en güçlü sinyal:** "satranç hakemi", "kural dışı hamle",
  "talep", "PGN" burada; anahtar kelime alanında bunlar tekrarlanmaz (bayt israfı).
- **Çapraz yerelleştirme:** Türkiye mağazası Türkçe'nin yanında **İngilizce (BK)**
  yerelleştirmesini de dizinler; en-GB alanı ikinci 100 baytlık anahtar kelime
  hakkı olarak kullanıldı. Açıklamada arayüzün Türkçe olduğu yazılı.
- **FIDE** yalnızca açıklamada tanımlayıcı olarak ve "bağlantılı değildir"
  notuyla geçer; ad/alt başlık/anahtar kelimede kullanılmaz (2.3.7, 5.2.1).
- **Tanıtım metni (170)** güncelleme gerektirmeden değiştirilebilir: turnuva
  sezonunda kampanya için kullanın.
- **Play:** tam açıklama dizinlenir; "satranç hakemi", "kural dışı hamle",
  "üç tekrar", "50 hamle", "PGN" doğal cümlelerde 2–3 kez geçer, liste halinde
  anahtar kelime doldurma yok. Başlıkta emoji, büyük harf, "ücretsiz/en iyi" yok.
- **Kategori:** App Store birincil *Spor*, ikincil *Referans*; Play *Spor*.
- **Değerlendirme isteği:** ilk sürümde yok; ileride bir itiraz başarıyla
  sonuçlandıktan sonra `SKStoreReviewController` (in_app_review) önerilir.

### Görseller (`mobile/store/screenshots/`)

| Klasör | Boyut | Adet | Kullanım |
| --- | --- | --- | --- |
| `ios-iphone-6.9/` | 1290×2796 | 8 | iPhone 6,9" (App Store diğer iPhone boyutlarına ölçekler) |
| `ios-ipad-13/` | 2048×2732 | 5 | iPad 13" (uygulama iPad'i desteklediği için zorunlu) |
| `android-phone/` | 1080×1920 | 8 | Play telefon (9:16; Play en-boy oranı 2:1'i aşamaz) |
| `android-graphics/feature_graphic_1024x500.png` | 1024×500 | 1 | Play öne çıkan görsel (zorunlu) |
| `android-graphics/icon_512.png` | 512×512 | 1 | Play yüksek çözünürlüklü simge |

Sıra (ilk 3 görüntü arama sonucunda görünür): kural dışı hamle → beraberlik
talebi → 7.5 ceza adımları → karne klavyesi → karne karşılaştırma → çevrimdışı
ana ekran → koyu tema → Pro. Görüntüler gerçek uygulama arayüzüdür (aynı Flutter
kodunun web derlemesi, örnek veriyle); sadece üstte başlık eklenmiştir. Yeniden
üretmek: `flutter build web --profile`, örnek veriyle Playwright çekimi, sonra
`node store/tool/compose.js <ham_telefon> <ham_ipad> store/screenshots assets/fonts assets/icon/icon_full.png`.
`07_paywall` aynı zamanda abonelik ürünlerinin **inceleme ekran görüntüsü**dür.

Yükleme: `fastlane deliver --metadata_path store/ios --screenshots_path ...` ve
`fastlane supply --metadata_path store/android` ya da konsollara elle kopyalama.

## 5. Yayın kontrol listesi

**Kodda hazır (bu depoda doğrulandı):** yukarıdaki tablo ✅ satırları;
`flutter analyze` temiz; tüm testler (taşma matrisi, meta veri doğrulayıcı,
perft/oracle) geçiyor; Android `targetSdk 36` / `compileSdk 36` / `minSdk 24`
(Google Play: 31 Ağustos 2026'dan beri yeni uygulamalar API 36 hedeflemeli);
Flutter 3.47 motoru 16 KB bellek sayfasını destekler; tek izin `INTERNET`.

**Sizin yapmanız gerekenler:**
1. `docs/gizlilik.html` ve `docs/index.html` içindeki **[iletişim e-postası]**
   yerlerini doldurun ve yayımlayın (GitHub Pages: Settings → Pages → `main` /
   `docs`; özel depoda Pages ücretli plan ister, alternatif: Netlify/Cloudflare
   Pages'e iki dosyayı yüklemek). Adres değişirse `PRIVACY_URL`/`SUPPORT_URL`
   ile derleyin ve `store/*/privacy_url.txt` dosyalarını güncelleyin.
2. Mac'te **Xcode 26** ile `flutter build ipa` (RevenueCat iOS paketi için
   `MONETIZATION_TR.md` → teknik notlar).
3. App Store Connect: uygulama kaydı, abonelik grubu + 3 ürün (inceleme görüntüsü
   `07_paywall`), Paid Apps sözleşmesi, **yaş anketi**, **App Privacy**, **AB
   tacir beyanı**, kategori, inceleme notu (`store/ios/review_information/notes.txt`).
4. TestFlight'ta sandbox ile satın alma, geri yükleme, iptal (Customer Center).
5. Google Play (adım adım: `docs/GOOGLE_PLAY_TR.md`): GitHub Actions ile imzalı AAB, Data safety, içerik derecelendirme
   anketi (IARC), hedef kitle (18+ önerilir: çocuklara yönelik değil), reklam yok
   beyanı, 12+ testçi × 14 gün kapalı test, ardından üretim.

## 5. Kaynaklar

- [App Store Review Guidelines](https://developer.apple.com/app-store/review/guidelines/)
- [Auto-renewable subscriptions — App Store](https://developer.apple.com/app-store/subscriptions/)
- [Privacy manifest files](https://developer.apple.com/documentation/bundleresources/privacy-manifest-files)
- [Describing use of required reason API](https://developer.apple.com/documentation/bundleresources/describing-use-of-required-reason-api)
- [App Privacy details](https://developer.apple.com/app-store/app-privacy-details/)
- [Apple Developer Forums — 3.1.2 subscription rejections](https://developer.apple.com/forums/thread/807082)
- [Google Play — Data safety](https://support.google.com/googleplay/android-developer/answer/10787469)
- [Google Play — Subscriptions policy](https://support.google.com/googleplay/android-developer/answer/9900533)
- [Apple — SDK minimum requirements (Xcode 26)](https://developer.apple.com/news/upcoming-requirements/)
- [Google Play — Target API level requirements](https://support.google.com/googleplay/android-developer/answer/11926878)
- [Android — 16 KB page sizes](https://developer.android.com/guide/practices/page-sizes)
- [Mobile Action — App Store cross-localization](https://www.mobileaction.co/blog/app-store-cross-localization/)
- [AppTweak — Primary and secondary localizations](https://www.apptweak.com/en/aso-blog/how-to-benefit-from-cross-localization-on-the-app-store)
