# Hakem Masası — Google Play yayın rehberi

Bu uygulamaya özel, sırasıyla yapılacaklar. Metinler ve görseller
`mobile/store/android/` ve `mobile/store/screenshots/` altında hazır.

## Kimlik

| Alan | Değer | Not |
| --- | --- | --- |
| Paket adı (applicationId) | `com.hanova.chessarbiter` | İlk yüklemeden sonra **asla değişmez**. "ai" eklenmedi: çekirdek bir kural motoru, yapay zekâ değil; "AI" iddiası yanıltıcı olur ve Play'in üretken yapay zekâ politikasının ek yükümlülüklerini çağrıştırır |
| iOS paket kimliği | `com.hanova.chessarbiter` | App Store'da da aynı |
| Ana ekrandaki ad | Hakem Masası | |
| Mağaza başlığı | Hakem Masası: Satranç Hakemi (tr-TR) · Hakem Masası: Chess Arbiter (en-US) | |
| Geliştirici adı | Hanova | Play hesabınızdaki ad |
| Abonelik | `hakem_pro` → temel planlar `weekly`, `monthly`, `yearly` | RevenueCat bunları `hakem_pro:weekly` … olarak görür; uygulama ikisini de tanır |

## 1. Bir kerelik hazırlık (bilgisayarınızda)

1. **Yükleme anahtarı:** JDK yüklü bir bilgisayarda
   `bash mobile/tool/create_upload_keystore.sh` çalıştırın. Oluşan `.jks`
   dosyasını yedekleyin; depoya **koymayın**. Play App Signing kullanıldığı için
   asıl imza anahtarı Google'da durur; yükleme anahtarı kaybolursa Play
   Console'dan sıfırlanabilir.
2. **GitHub secrets** (Settings → Secrets and variables → Actions):
   `ANDROID_KEYSTORE_BASE64` (betiğin ürettiği `.b64` dosyasının içeriği),
   `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_PASSWORD`, `ANDROID_KEY_ALIAS`
   (= `upload`), `REVENUECAT_ANDROID_KEY` (RevenueCat → Project → API keys →
   Google Play, `goog_…`). İsteğe bağlı değişkenler: `PRIVACY_URL`, `SUPPORT_URL`.
3. **Gizlilik ve destek sayfaları:** `docs/gizlilik.html` ve `docs/index.html`
   içindeki iletişim e-postasını doldurup yayımlayın (bkz. `APP_STORE_TR.md` §5).

## 2. AAB üretimi

GitHub → Actions → **Android** → *Run workflow* (track: `none`). İş akışı
analiz + testleri çalıştırır, imzalı `app-release.aab` üretir ve "Artifacts"
altına koyar. Anahtarlar eksikse mağaza derlemesi bilerek durur (debug imzalı
veya RevenueCat'siz paket yüklenemez). Her çalıştırmada `versionCode` otomatik
artar (100 + çalışma numarası).

Yerelde: `android/key.properties` oluşturup
`flutter build appbundle --release --dart-define=REVENUECAT_ANDROID_KEY=goog_…`.

## 3. Play Console

### Uygulama oluşturma
- Uygulama adı: **Hakem Masası: Satranç Hakemi**; varsayılan dil **Türkçe – tr-TR**;
  Uygulama; **Ücretsiz** (abonelik uygulama içi satın alımdır; ücretsiz →
  ücretli geçiş yapılamaz).
- Beyanlar: geliştirici program politikaları ve ABD ihracat yasaları ✓.

### İlk yükleme (elle)
Yeni bir uygulamaya ilk paket API ile yüklenemez: Test → **Dahili test** →
Yeni sürüm → Actions'tan indirdiğiniz `app-release.aab`'yi sürükleyin →
*Play Uygulama İmzalama*'yı kabul edin. Sürüm notu:
`mobile/store/android/whatsnew/`. Bu yükleme `BILLING` iznini Play'e tanıtır;
abonelikler ancak bundan sonra oluşturulabilir.

### Para kazanma → Abonelikler
Önce ödeme profili (satıcı hesabı) gerekir.
- Abonelik kimliği **`hakem_pro`**, ad "Hakem Masası Pro".
- Temel planlar (otomatik yenilenen):
  - `weekly` — 1 hafta — ₺79,99
  - `monthly` — 1 ay — ₺149,99
  - `yearly` — 1 yıl — ₺699,99; teklif **`trial-7d`**: 7 gün ücretsiz,
    uygunluk "Yeni müşteri edinme — bu aboneliği hiç almamış".
- Diğer ülkelerin fiyatları otomatik dönüşümle; sonra elle yuvarlayın.

### RevenueCat
- Projeye Play uygulaması ekleyin: paket `com.hanova.chessarbiter`.
- **Hizmet hesabı kimlik bilgileri** (RevenueCat'in satın almaları doğrulaması
  için; RevenueCat dokümanındaki adımlar) ve isteğe bağlı gerçek zamanlı
  bildirimler (Pub/Sub).
- Ürünleri içe aktarın → `pro` yetkisine bağlayın → `default` offering'e
  Weekly / Monthly / Annual paketleri.

### Uygulama içeriği (Politika → Uygulama içeriği)
| Bölüm | Cevap |
| --- | --- |
| Gizlilik politikası | yayımladığınız `gizlilik.html` adresi |
| Uygulama erişimi | Tüm işlevler özel erişim olmadan kullanılabilir (giriş yok) |
| Reklamlar | Hayır, reklam içermiyor |
| İçerik derecelendirmesi (IARC) | Kategori: Referans/araç; şiddet, cinsellik, dil, uyuşturucu, kumar, kullanıcı etkileşimi, konum paylaşımı, dijital satın alma: yalnızca "dijital ürün satın alma: evet" → beklenen sonuç PEGI 3 / Herkes |
| Hedef kitle | 18 yaş ve üzeri (hakemlere yönelik; çocuk politikası kapsamı dışında) |
| Haber uygulaması / Devlet / Finansal özellik / Sağlık | Hayır |
| Veri güvenliği | Toplanan: **Finansal bilgiler → Satın alma geçmişi** (RevenueCat): toplanıyor, paylaşılmıyor, amaç *Uygulama işlevi*, aktarımda şifreli, isteğe bağlı değil, silme talebi destek adresinden. **Uygulama kimlikleri** yok sayılmaz: RevenueCat anonim kullanıcı kimliği → *Cihaz veya diğer kimlikler*, amaç *Uygulama işlevi*. Konum, kişiler, fotoğraf (OCR kapalı), analitik: **yok** |
| Üretken yapay zekâ | Hayır (OCR kapalı derleme) |

### Mağaza girişi
- Metinler: `mobile/store/android/tr-TR/` (başlık, kısa açıklama, tam açıklama)
  ve İngilizce için `en-US/` (Çeviri ekle → İngilizce).
- Grafikler: simge `android-graphics/icon_512.png`; öne çıkan görsel
  `android-graphics/feature_graphic_1024x500.png`; telefon `android-phone/`
  (8 adet); 7" ve 10" tablet için `ios-ipad-13/` görselleri kullanılabilir.
- Kategori: **Spor**; etiketler: Satranç, Spor araçları.
- İletişim e-postası (herkese açık) ve web sitesi (`index.html` adresi).

### Test ve yayın
1. **Dahili test** (100 kişiye kadar, inceleme beklemeden): sandbox lisans
   testçileri (Ayarlar → Lisans testi) ile satın alma, geri yükleme, iptal.
2. **Kapalı test**: 13 Kasım 2023'ten sonra açılmış **kişisel** hesaplarda
   üretime başvurmadan önce **en az 12 testçi 14 gün kesintisiz** kapalı testte
   kalmalı. Kuruluş (D-U-N-S) hesabıysa bu şart yok.
3. Üretime erişim başvurusu → üretim sürümü (önce %10–20 kademeli yayın).

Sonraki sürümler: Actions'ta *Run workflow* → track `internal` (hizmet hesabı
JSON'u `PLAY_SERVICE_ACCOUNT_JSON` secret'ı olarak eklendiyse paket taslak
olarak otomatik yüklenir).
