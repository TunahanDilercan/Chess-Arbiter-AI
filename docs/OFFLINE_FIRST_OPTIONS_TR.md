# Arbiter AI: mobil öncelikli, çevrimdışı mimari seçenekleri

Araştırma tarihi: 9 Ekim 2026.

Durum: 9 Ekim 2026 tarihli araştırma ve uygulama planı. Araştırma sırasında
dal açılmadı, commit/push yapılmadı, ücretli OCR çağrısı çalıştırılmadı.
10 Ekim'deki mevcut sürüm kaydı `BASELINE_BEFORE_OFFLINE_TR.md` içinde açıklanır.
Bu belge uygulamanın mimari kurallarını veya lisansını değiştirmez. Lisans değerlendirmesi teknik
ön incelemedir; özellikle GPL ile App Store dağıtımı yayımdan önce ayrıca incelenmelidir.

## 1. Önerilen karar

Flutter mobil uygulamasını ve mevcut Next.js web arayüzünü koruyalım. Hamle
doğrulama, notasyon dönüşümü, inceleme, düzeltme, PGN ve oyun arşivini cihazda
çalıştıralım. Bulut OCR isteğe bağlı olsun; temel kullanım OCR olmadan da çalışsın.

Henüz açık/kapalı kaynak kararı kesin değilse önce izin verici lisanslı
`chess.dart` + `chess.js` seçeneğini küçük bir doğruluk prototipinde değerlendirelim.
Bu seçenek testleri geçerse kapalı dağıtım veya kendi kodumuzu açık yayımlama
seçeneğini korur. Testleri geçmeden tüm uygulamayı buna taşımayalım.

Açık kaynakta kalma kararı kesinse `dartchess` + `chessops` güçlü bir alternatif.
Lichess'in Flutter uygulaması `dartchess` kullanıyor; bu üretim kullanımı için
iyi bir referans, Arbiter'ın özel kuralları için otomatik doğruluk garantisi değil.
[Lichess mobil bağımlılıkları](https://github.com/lichess-org/mobile/blob/main/pubspec.yaml)

## 2. Projede doğrulanan mevcut durum

| Konu | Gözlem | Geçişe etkisi |
| --- | --- | --- |
| Mobil | Flutter; Riverpod, Dio, SSE; oyunlar ve analiz API'den geliyor | Arayüzü atmak yerine yerel analiz ve kayıt eklenebilir |
| Fotoğraf | Yön düzeltme, boyutlandırma ve dört köşeden perspektif düzeltme mobilde var | Fotoğraf hazırlığının bir kısmı yeniden yazılmaz |
| Satranç | Python'da normalleştirme, aday eşleştirme, sıra bütünlüğü, FIDE bulguları | Sadece bir hamle kütüphanesi eklemek tüm davranışı taşımaz |
| Kalıcı kayıt | PostgreSQL ve sunucu dosyaları; mobilde yerel oyun veritabanı yok | Yerel kayıt, şema geçişi ve dışa aktarma gerekiyor |
| Web | Next.js 14; API/storage yönlendirmeleri ve dinamik oyun yolu | Statik dağıtım için veri erişimi ve yollar değişmeli |
| OCR dışı görüntü işleri | PDF sayfalarını görüntüye çevirme ve OpenCV hücre bulma/kırpma sunucuda | Satranç mantığını taşımak bunları kendiliğinden kaldırmaz |
| Android yayımlama | `com.example.mobile`; release yapılandırmasında debug imzası | Bugünkü paket mağazaya hazır değil |
| iOS yayımlama | Görünen ad `Mobile`; incelenen Info.plist'te kamera/fotoğraf izin açıklamaları yok | İzinler, kimlik, gerçek cihaz ve Mac üzerinde derleme doğrulanmalı |

Bu araştırmada üç çekirdek Python test dosyası çalıştırıldı: **108 test geçti**.
Bu sonuç mevcut referans davranış içindir. Yeni Dart/JavaScript çekirdeği,
telefon performansı, Android mağaza paketi veya iOS derlemesi doğrulanmış değil.

Git kontrolünde yerel `main`, kayıtlı `origin/main` ve uzaktaki `main` commit'i
`b639a320bdc2d86753919d2b212c434013bfb9fd` olarak eşleşti. Ancak bu belge
eklenmeden önce **43 değiştirilmiş takipli dosya ve 6 yeni dosya** vardı.
Dolayısıyla GitHub'daki kayıt ile bilgisayardaki çalışma dosyaları aynı değil.
Uzakta yalnızca `main` dalı görüldü. GitHub API'si depo görünürlüğünü `public`
olarak doğruladı. Kök uygulama lisansı bulunmadı; herkese açık depo tek başına
açık kaynak lisansı yerine geçmez.

## 3. İki dağıtım seçeneği

| Başlık | A: GPL tabanlı açık kaynak | B: Kapalı kaynağa uygun bağımlılıklar |
| --- | --- | --- |
| Mobil arayüz | Mevcut Flutter | Mevcut Flutter |
| Mobil satranç | `dartchess`, GPL-3.0 | `chess` / chess.dart, MIT ve BSD-2-Clause bildirimleri |
| Web satranç | `chessops`, GPL-3.0-or-later | `chess.js`, BSD-2-Clause |
| FIDE uygulama katmanı | Bizim geçmiş, talep ve otomatik bitiş kontrollerimiz | Aynı katman gerekli; hazır `game_over` kullanılmamalı |
| Mobil kayıt | SQLite + Drift | SQLite + Drift |
| Web kayıt | IndexedDB | IndexedDB |
| Google Play | Açık kaynak olmak engel değil; lisans ve mağaza şartları karşılanmalı | Lisans bildirimleri ve mağaza şartları karşılanmalı |
| App Store | GPL hakları ile mağaza koşulları ayrıca incelenmeli | İzin verici bağımlılıklar bu incelemeyi kolaylaştırır; kabul garantisi vermez |
| Gelir elde etme | Mümkün; açık kaynak ücretsiz dağıtmak zorunda olmak değildir | Mümkün; kaynak yayımlama zorunluluğu bu kütüphanelerden doğmaz |
| Ana ödünleşim | Copyleft dağıtım yükümlülükleri | Daha eski Dart paketinin doğruluğu/bakımı için daha fazla inceleme |

Kütüphane kaynakları: [dartchess](https://github.com/lichess-org/dartchess),
[chessops](https://github.com/niklasf/chessops),
[chess.dart paket bilgisi](https://pub.dev/packages/chess),
[chess.dart lisansı](https://raw.githubusercontent.com/davecom/chess.dart/master/LICENSE),
[chess.js lisansı](https://github.com/jhlywa/chess.js/blob/master/LICENSE).
Dağıtıma alınan kesin sürümler ve geçişli bağımlılıklar ayrıca sabitlenip denetlenmeli.

### A. Açık kaynak yolu

GPL kütüphanelerini uygulamaya bağlayarak dağıttığımızda birleşik uygulama için
GPL yükümlülüklerini karşılayan bir dağıtım planlamalıyız: uygun kaynak kodu,
derleme bilgileri ve lisans bildirimleri alıcılara sağlanmalı. Bunun pratik yolu
her mağaza sürümüne karşılık gelen kaynak sürümünü yayımlamak. Ticari kullanım
ve ücret almak GPL tarafından yasaklanmaz. API anahtarları ve kullanıcı verileri
kaynak kodu değildir; yayımlanmaz.
[GNU GPL açıklamaları](https://www.gnu.org/licenses/gpl-faq.en.html)

Lichess'in Google Play'de bulunması açık kaynak uygulamanın mağazada
yayımlanabileceğinin somut örneği; bizim paketimizin onayını garanti etmez.
[Lichess Google Play sayfası](https://play.google.com/store/apps/details?id=org.lichess.mobileV2)

App Store için "GPL kesin yasak" veya "hiç sorun yok" demek doğru değil.
FSF'nin geçmişte GPL ile App Store kısıtlamaları arasında çatışma bildirdiği
örnekler var. Bunlar eski olaylar; güncel paket lisansları, hak sahiplerinin
izinleri ve seçilen dağıtım koşulları birlikte değerlendirilmeden sonuca varılmaz.
[FSF'nin tarihsel değerlendirmesi](https://www.fsf.org/blogs/licensing/more-about-the-app-store-gpl-enforcement)

### B. Kapalı kaynak yolu

Mobilde `chess.dart`, webde `chess.js` adaylarıyla başlayabiliriz. MIT/BSD
telif ve lisans bildirimlerini koruruz. Başkasının GPL kodunu kopyalayıp yalnızca
paket adını değiştirerek kapalı kaynak yapmak mümkün bir geçiş yöntemi değildir.
Mevcut kod, görseller, model dosyaları ve geçişli bağımlılıklar da denetlenmeli.

`chess.dart` kaynak kodunda `in_draw` üç tekrar ve 100 yarım hamleyi kapsıyor;
`game_over` bunu bitiş sayıyor. Arbiter'da bu alanı doğrudan kullanmak yanlış
otomatik beraberlik üretebilir. Paketi yasal hamle ve konum işlemleri için
kullanıp, talep/otomatik bitiş kararını kendi katmanımızda vermeliyiz.
[İncelenen kütüphane kodu](https://raw.githubusercontent.com/davecom/chess.dart/master/lib/chess.dart)

Bu teknik yığınla kendi kodumuzu ayrıca MIT/Apache gibi bir lisansla açık
yayımlamak da mümkün olabilir; açık kaynak seçmek mutlaka GPL seçmek değildir.
Ancak kendi kodumuz üzerindeki hak sahipliği ve bağımlılık uyumu önce doğrulanmalı.
Önceden verilmiş açık kaynak hakları, sonradan depoyu gizleyerek geri alınmaz.

"Kapalı kaynak web" de tarayıcıya gönderilen JavaScript'in gizli tutulacağı
anlamına gelmez. Kaynak deposu ve kullanım lisansı kapalı olabilir; istemciye
gönderilen kod incelenebilir. Hiçbir yolda ortak API anahtarı istemciye gömülmez.

### Görseller iki yolda da ayrı denetlenmeli

| Lichess varlığı | Kaynakta belirtilen lisans | Öneri |
| --- | --- | --- |
| Mevcut cburnett taşları | GPLv2+ | Açık kaynak yolunda yükümlülükleriyle değerlendir |
| Chessnut taşları | Apache-2.0 | Kapalı kaynak için daha sade aday |
| Spatial / Fantasy / Celtic taşları | MIT | Kapalı kaynak için alternatifler |
| RhosGFX taşları | CC0 | Alternatif |
| `public/images/board` | AGPLv3+ | Serbestçe lisanssız kullanılabilir varsayma |

Ticari kullanım kısıtlı başka setler de var. Bütün Lichess görselleri tek bir
lisansa sahip değil. Tahta için kendi düz renk tasarımımızı korumak en sade yol.
Görsel lisansı ile uygulama kodu lisansını birbirine otomatik olarak eşitlemiyoruz.
[Lichess resmi varlık lisansları](https://github.com/lichess-org/lila/blob/master/COPYING.md)

## 4. Flutter mı, Kotlin/Swift mi?

Bu projede Flutter'ı korumak mühendislik açısından önerim. Kamera/kırpma,
tahta, düzeltme ekranları ve durum yönetimi zaten var. Kotlin ve Swift'e
geçmek tek başına ne FIDE doğruluğunu artırır ne OCR ücretini kaldırır;
iki ayrı mobil arayüzü yeniden geliştirmeyi gerektirir.

Platforma özel bir tarayıcı veya cihaz içi model gerektiğinde o küçük parçaya
yerel eklenti eklenebilir. Bütün uygulamayı yeniden yazmayı ancak ölçülmüş bir
performans veya platform engeli gerekçelendirmeli.

`dartchess` bugün web desteği sunmuyor. Bu yüzden "Flutter seçersek aynı
satranç paketi webde de çalışır" varsayımı yanlış. Mevcut Next.js arayüzünü
koruyup iki platformu ortak test örnekleriyle denetlemek ilk geçişte daha küçük
iş. İzin verici `chess.dart` webi de destekliyor; Flutter Web mümkün bir alternatif,
ancak mevcut web arayüzünü yeniden kurmanın bu aşamada zorunlu bir faydası yok.
[dartchess platform kapsamı](https://github.com/lichess-org/dartchess)

Python'u telefona gömmek ilk tercih değil: Chaquopy Android odaklı ve iOS'u
desteklemiyor; tarayıcıda Pyodide ise ayrı Python/WASM çalışma ortamı getiriyor.
Bunlar "mevcut Python dosyasını her yerde aynı şekilde çalıştırma" çözümü değil.
[Chaquopy](https://chaquo.com/chaquopy/doc/current/faq.html),
[Pyodide](https://pyodide.org/en/stable/usage/index.html)

Rust + yerel bağlayıcı + web WASM ile gerçekten ortak çekirdek kurulabilir.
Ama bu, Flutter/TypeScript/Python yanında yeni derleme ve dağıtım bakımı demek.
Örneğin `shakmaty` de GPL'dir; Rust kullanmak lisans sorununu kendiliğinden çözmez.
İlk sürüme önermiyorum.
[shakmaty](https://github.com/niklasf/shakmaty),
[Flutter Rust Bridge platformları](https://cjycode.com/flutter_rust_bridge/guides/cross-platform/overview)

## 5. FIDE doğruluğu ve kapsam

`python-chess`, `dartchess` veya `chessops` için resmi FIDE sertifikası
doğrulanamadı. Mart 2026 tarihli FIDE listesinde eşlendirme yazılımları ve
elektronik kayıt cihazları gibi başka kategoriler var. Bir kütüphanenin kuralları
uygulaması, bu uygulamanın turnuvada elektronik notasyon cihazı olarak
onaylandığı anlamına gelmez.
[FIDE sertifikalı/onaylı ekipman listesi](https://handbook.fide.com/chapter/FIDECertifiedAndEndorsedEquipment032026)

Temel ayrım korunmalı: üç tekrar ve 50 hamle talep hakkıdır; beş tekrar ve
75 hamle otomatik beraberliktir. Talebi mümkün kılan planlanan sonraki hamleler
de test edilmeli. Son hamlede matın önceliği dikkate alınmalı. Saat, taş tutma,
oyuncunun gerçekten talepte bulunması gibi bilgiler yalnız scoresheet'ten
çıkarılamaz; bunlar hakem kararı yerine geçecek şekilde sunulmamalı.
[FIDE kuralları, özellikle 9.2, 9.3 ve 9.6](https://handbook.fide.com/chapter/E012023)

"Yetersiz materyal" tüm ölü konumları çözmekle aynı şey değil. python-chess'in
ilgili kontrolü de materyal temelli sınırlamalara sahip. Bilinmeyen durumlar
kesin hüküm gibi gösterilmemeli; tüm FIDE vakalarını kapsadığımız iddia edilmemeli.
[python-chess materyal kontrolü](https://python-chess.readthedocs.io/en/stable/core.html#chess.Board.has_insufficient_material)

## 6. Sunucudan cihaza taşınacak yapı

### Analiz çekirdeği

Flutter'dan bağımsız, test edilebilir bir Dart paketi öneriyorum. Girdisi ham
OCR veya elle girilen hamleler; çıktısı konumlar, adaylar, inceleme nedenleri,
FIDE bulguları ve PGN olsun. Kamera, HTTP ve veritabanı bu pakete girmesin.
Web için aynı veri sözleşmesini uygulayan TypeScript katmanı olsun.

İki uygulamada ortak, sürümlü JSON örnekleri tutulmalı. Her örnek başlangıç
FEN'ini, dili, yarım hamle indeksini, boş satırları, ham OCR metnini, güven
değerini ve insan onaylarını içermeli. Sonuçta SAN/UCI, konum, bulgular ve
inceleme gerekçeleri karşılaştırılmalı; değişken zaman/kimlik alanları değil.

Taşınırken özellikle korunacak mevcut davranışlar:

- Türkçe `Ş/V/K/F/A` dönüşümü; örneğin `Vh4+` ile `Qh4+` ilişkisinin korunması.
- Eksik hamle beyaz/siyah sırasını kaydırmamalı; boşluk silinip liste sıkıştırılmamalı.
- Hatalı hamleden sonra gelen hamleler yanlış konumdan doğrulanmamalı; ham veri kaybolmamalı.
- İnsan onayı/düzeltmesi sonraki analizle ezilmemeli; değişiklikler kayıtlı olmalı.
- Onaylanan hamle kesin doğrulanmalı; otomatik benzerlik seçimiyle sessizce değiştirilmemeli.
- Oyun sonrasındaki satırlar saklanmalı, bitmiş oyuna geçerli devam gibi eklenmemeli.
- Bir satır değiştiğinde devamı yeniden hesaplanmalı; eski analiz sonucu yeni düzeltmeyi ezmemeli.

Mevcut aday puanlaması benzerlik, OCR güveni ve karışma bonusu kullanıyor.
Python'daki Levenshtein ve yedek SequenceMatcher aynı sayısal algoritma değil.
Geçişte bir algoritma açıkça seçilip sabitlenmeli; eşit puanların sıralaması da
belirlenmeli. Kütüphanelerin hamle üretme sırası kararı değiştirmemeli. Sarı
inceleme sayısını azaltmak için eşikleri körlemesine düşürmek geçiş hedefi değil.

Tekrar anahtarı yalnız taş dizilişi değildir: sıra, rok hakları ve yasal en
passant olanağı hesaba katılmalı; hamle sayaçları konum eşitliğine katılmamalı.
Kütüphanelerin FEN en passant yazım farklılıkları karşılaştırmada normalize edilmeli.
Bu testler Python ile karşılaştırmanın yanında bağımsız, kurala dayalı beklenen
sonuçlar da içermeli; mevcut Python sonucunu yanılmaz kabul etmiyoruz.

### Kayıt ve çevrimdışı kullanım

Mobilde SQLite/Drift, webde IndexedDB öneriyorum. Uygulama ekranları doğrudan
API yerine bir kayıt katmanına bağlansın. Geçiş süresince eski sunucu kaydı ve
yeni cihaz kaydı ayrı uygulamalarla aynı arayüzün arkasında tutulabilir.
Drift'in yerel ve web seçenekleri var; Next.js uygulaması Dart veritabanı
arayüzünü doğrudan paylaşmayacak.
[Drift platform desteği](https://drift.simonbinder.eu/platforms/),
[Flutter çevrimdışı mimari rehberi](https://docs.flutter.dev/app-architecture/design-patterns/offline-first)

Görüntüler yerel dosya/blob, oyunlar sürümlü veri, insan düzeltmeleri revizyon
olarak saklanmalı. Kayıt işlemleri atomik olmalı. İşlemciyi meşgul eden analiz
mobilde ayrı isolate, webde worker üzerinde ölçülmeli; ekranı kilitlememeli.

PGN yalnız oyunu taşır; fotoğraf, OCR alternatifleri ve inceleme geçmişi için
ayrı, sürümlü bir yedek paketi gerekir. Eski sunucu kayıtları buna aktarılıp
mobil/webde içe alınmalı. İçe aktarmada kimlik çakışması, bozuk/arşivden taşan
dosya yolları, boyut limitleri ve aynı oyunun yeniden alınması test edilmeli.

Bu ilk sürümde cihazlar arasında otomatik eşitleme olmayacak. Kullanıcı dosya
aktarır. Tarayıcı verileri temizlenirse veya uygulama silinirse yerel kayıtlar
kaybolabilir; yedekleme açıkça sağlanmalı. Otomatik eşitleme ayrı ve isteğe bağlı
bir sonraki özellik olmalı, temel kullanımın sunucu bağımlılığı yapılmamalı.

### Webin korunması

Mevcut web bileşenlerini koruyup API/storage yönlendirmelerini kaldırmak ve
oyun sayfasını statik bir yola, örneğin `/review?id=...`, taşımak gerekir.
Bugünkü `/games/[id]` yapısına yalnız `output: export` eklemek yeterli değil:
kullanıcı cihazında sonradan oluşacak oyunlar derleme anında bilinmez.
[Next.js 14 statik dışa aktarma kısıtları](https://nextjs.org/docs/14/app/building-your-application/deploying/static-exports)

Statik barındırma ile çevrimdışı çalışma aynı şey değil. Uygulama kabuğu,
taş görselleri ve gerekli dosyalar için ayrıca önbellek/service worker,
güncelleme ve veri şeması geçişi tasarlanmalı. İlk yüklemeden sonra uçak modunda
açılış, düzeltme, kayıt, yeniden açılış ve PGN dışa aktarma doğrulanmalı.

## 7. OCR ve gerçekte sıfırlanabilecek gider

| İşlem | İlk hedefte nerede? | Sürekli hizmet gideri |
| --- | --- | --- |
| Elle hamle / PGN, doğrulama, düzeltme, arşiv | Telefon veya tarayıcı | Kendi analiz sunucumuz gerekmez |
| Fotoğraf yönü ve perspektif düzeltme | Telefon | Mevcut yerel kod kullanılabilir |
| Web dosyalarını yayımlama | Statik barındırma | Ücretsiz kota içinde sıfır olabilir |
| Bulut OCR | İsteğe bağlı sağlayıcı | Kullanıma bağlı API gideri devam eder |
| Cihaz içi OCR | Ayrı araştırma aşaması | API gideri yok; geliştirme, model boyutu ve doğruluk maliyeti var |
| Otomatik cihazlar arası eşitleme | İlk sürüm dışında | Ek hizmet ihtiyacı yaratabilir |

Cloudflare Pages statik istekleri ücretsiz sunabiliyor; Functions ayrı
kotalara tabi. Workers Free, günde 100.000 istek ve istek başına 10 ms CPU
sınırıyla küçük bir OCR geçidi için aday. Bu, mevcut Python/OpenCV/PyTorch
sunucusunu aynı yere ücretsiz taşıyabileceğimiz anlamına gelmez. Büyük görüntü
işleme ve kodlama maliyeti ayrıca ölçülmeli. Kotalar ve koşullar yayımdan önce
yeniden doğrulanmalı; sınırsız ve kalıcı ücretsiz hizmet sözü verilmez.
[Pages yönlendirme/ücret kapsamı](https://developers.cloudflare.com/pages/functions/routing/),
[Workers fiyatlandırması](https://developers.cloudflare.com/workers/platform/pricing/)

Ortak OCR API anahtarı mobil pakete veya web dosyalarına konmamalı. Güvenli,
sınırlı bir geçit; kimlik/kötüye kullanım kontrolü, dosya sınırı, toplam harcama
limiti ve kullanıcı başına kota uygulamalı. Yalnız CORS bir güvenlik kontrolü
olarak yeterli değil. Sağlayıcı SDK'sının tarayıcı uyarısı da bu anahtar riskini
belirtiyor.
[Anthropic SDK gereksinimleri](https://github.com/anthropics/anthropic-sdk-typescript#requirements)

Bu geçit de teknik olarak dış sunucuda çalışır; fark, sürekli kiralanan VPS ve
zorunlu oyun veritabanı olmamasıdır. Hiç dış servis istenmiyorsa bulut OCR da
olamaz: elle/PGN giriş veya doğrulanmış cihaz içi OCR gerekir. Kendi anahtarını
giren kullanıcı modeli geliştirici giderini azaltabilir ama API ücretini yok
etmez ve genel tüketici uygulamasının varsayılan deneyimi olarak önermiyorum.

OCR yanıtı bir kez saklanmalı; hamle düzeltme ve yeniden doğrulama tekrar OCR
çağırmamalı. Kesintide isteğin sağlayıcıda tamamlanıp tamamlanmadığı belirsizse
otomatik ücretli tekrar yapılmamalı. Sonuç önbelleği + istek kimliği kullanılmalı;
kesin yinelenmeme garantisi gerekiyorsa kalıcı istek kaydı ve sağlayıcı desteği
tasarlanmalı. Tamamen durumsuz bir geçit böyle bir garantiyi tek başına vermez.

Mevcut hücre kırpma, PDF sayfa çevirme ve TrOCR yedeği de planın kapsamı:

- İlk fotoğraf akışında mevcut yerel perspektif düzeltme ve tam sayfa yakınlaştırma korunabilir.
- Hücre bazlı inceleme yerelde ayrıca taşınana kadar otomatik hücre kırpma eşdeğerliği iddia edilmemeli.
- PDF için yerel sayfa işleme, sayfa/boyut sınırları ve kötü dosya testleri gerekir.
- TrOCR modelini telefona eklemek ayrı model dönüşümü ve gerçek cihaz çalışmasıdır; hazır kabul edilmez.

Bu araştırma OCR motorlarını karşılaştıran bir ölçüm yapmadı. Başarı yüzdesi
ve sayfa başına ücret vermek için temsilî el yazılarıyla gerçek deneme gerekir.
Özellikle OCR güven puanı ölçülmüş başarı olasılığı değildir. Yanlış okunan
hamle de yasal olabilir; satranç kontrolü tek başına bunu kesin düzeltemez.

## 8. Aşamalı uygulama ve kabul koşulları

| Aşama | Yapılacak iş | Bir sonraki aşamaya geçiş koşulu |
| --- | --- | --- |
| 0. Sabit başlangıç | Mevcut düzeltmeleri incele/kaydet; veri yedeklerini doğrula; lisans yolu seç | Temiz ve test edilmiş başlangıç; sırlar ve kullanıcı dosyaları Git dışında |
| 1. Çekirdek prototip | Seçilen Dart/JS kütüphaneleri, ortak örnekler ve FIDE katmanı | Aynı hamle dizisinde beklenen SAN, FEN, inceleme ve bulgular |
| 2. Mobil çevrimdışı | Yerel kayıt, hamle girişi, düzeltme ve PGN; mevcut arayüzü bağla | Uçak modunda tam akış, uygulamayı kapatıp açınca veri kaybı yok |
| 3. Web çevrimdışı | Yerel çekirdek/kayıt, statik yollar, önbellek ve içe/dışa aktarma | Backend kapalıyken web akışı; mobil/web dosya alışverişi |
| 4. OCR ayrıştırma | Yerel fotoğraf hazırlığı, isteğe bağlı güvenli geçit, maliyet sınırları | Düzeltmede yeni OCR çağrısı yok; kesinti ve kota testleri geçiyor |
| 5. Dağıtım | Lisans envanteri, gizlilik, Android imza/AAB, mağaza testi; ardından iOS | İmzalı gerçek cihaz sürümü; mağaza gereksinimleri karşılanmış |

Öncelikli test örnekleri: rok ve rok hakkının kaybı; pinli en passant;
terfi/eksik terfi; aynı hedefe giden taşların SAN ayrımı; şah/mat eki;
üç/beş tekrar; 50/75 hamle; planlanan hamleyle talep hakkı; matın önceliği;
Türkçe notasyon; boş beyaz/siyah hücresi; önceki hamleyi düzeltme;
oyun sonrasındaki satırlar; insan onayının korunması.

Doğruluk kapısı: tanımlı test kümesinde beklenen sonuçlarla tam eşleşme ve
bilinen kritik yanlış otomatik kabul olmaması. Bu, bütün gerçek dünyada
%100 doğruluk iddiası değildir. OCR için ayrıca izinli ve çeşitlendirilmiş
scoresheet kümesinde hamle doğruluğu, yanlış otomatik kabul oranı, inceleme
oranı, sayfa süresi ve gerçek API kullanımı ölçülmeli.

Performans hedefi cihaz üzerinde belirlenecek; henüz ölçülmüş hızlanma yüzdesi
yok. Eski Python servisi eşdeğerlik testi ve veri aktarımı bitmeden silinmemeli.
Normal kullanıcı akışı sunucu olmadan doğrulandıktan sonra dağıtım gereksinimi
olmaktan çıkarılabilir; geliştirici test aracı olarak kalabilir.

## 9. GitHub dalı ve gizlilik planı

Yeni dal doğru araç, fakat önce yereldeki mevcut çalışmalar korunmalı.
GitHub arayüzünden bugünkü `main` üstüne dal açmak, commit edilmemiş 49 dosyayı
kendiliğinden o dala taşımaz.

1. Mevcut çalışma dizininde `fix/stabilize-current` gibi bir dalda bekleyen değişiklikler incelenir; ilgili düzeltmeler anlamlı commit'lere ayrılır.
2. Gizli anahtar, yedek, yüklenen scoresheet ve imzalama anahtarı denetimi yapılır. `.env` dosyalarının takipli olmaması tek başına tüm geçmişin temiz olduğunu kanıtlamaz.
3. Test edilen sabit başlangıç kaydedilir; seçilen görünürlük ve yayın kararı doğrultusunda GitHub'a gönderilir. Uygunsa `main` ile birleştirilir.
4. Geçiş `feat/offline-first` gibi bir dalda bu düzeltilmiş başlangıçtan başlatılır; kaynak GitHub'daki eski commit değil doğrulanan başlangıçtır.
5. Çalışır kopyayı korumak için ayrı çalışma klasörü/worktree kullanılabilir. Commit edilmemiş dosyalar, `.env` ve yerel veriler oraya otomatik kopyalanmaz.
6. Ortak test sözleşmesi, yerel çekirdek, yerel kayıt, web ve OCR geçidi küçük değişiklik gruplarıyla incelenir; çalışan aşamalar düzenli olarak ana dala alınır.

Tek, aylarca birleştirilmeyen yeniden yazım dalı önermiyorum. Eski ve yeni
analiz seçenekleri geçişte ayrılabilir; her aşama geri dönülebilir kalır.
[GitHub dal rehberi](https://docs.github.com/en/pull-requests/how-tos/commit-changes/managing-branches-within-your-repository),
[Git worktree davranışı](https://git-scm.com/docs/git-worktree.html)

**Açık kaynak yolu:** mevcut depoda ilerlemek uygundur; lisans kararı ve
üçüncü taraf bildirimleri kaynak sürümleriyle kaydedilir.

**Kapalı kaynak yolu:** mevcut depo public olduğundan yeni dal da public olur.
Özel tutulacak yeni çalışmayı bu depoya göndermeyiz. Ya kullanıcı kararıyla
depo görünürlüğü değiştirilir ya da özel bir geliştirme deposu kullanılır.
Bu işlemler geçmişte alınmış kopyaları geri çekmez. Ayrı özel depo, mevcut
herkese açık geçmişi koruyup gelecekteki geliştirmeyi ayırmak için daha açık
bir sınır olabilir. Lisans ve katkı hakları yine geçerlidir.

Açık ve kapalı sürümleri iki bağımsız uzun ömürlü dala ayırıp aynı özellikleri
iki kere geliştirmek ilk öneri değil. Önce bir dağıtım/lisans stratejisi seçilmeli.

## 10. Mağazaya hazırlık ve maliyetler

| Kalem | Doğrulanan durum / yapılacak iş |
| --- | --- |
| Google Play hesabı | Bir defalık 25 USD; hesap/kimlik doğrulama gerekiyor |
| Yeni kişisel Play hesabı | 13 Kasım 2023 sonrası hesaplarda en az 12 testçi, kesintisiz 14 günlük kapalı test; sonra üretim erişimine başvuru |
| Apple Developer | Standart üyelik 99 USD/yıl; bölgesel fiyat ve vergiler değişebilir |
| iOS geliştirme | macOS/Xcode erişimi; mevcut Windows ortamında iOS derlemesi doğrulanmadı |
| Android paketi | Kalıcı applicationId, release anahtarı, AAB, sürüm numarası; güncel hedef SDK şartları yayımdan önce kontrol edilmeli |
| Gizlilik | Yerel/bulut veri akışını doğru açıklama; OCR sağlayıcısına gönderilen fotoğraf için açık bilgilendirme/izin |
| Lisanslar | Paket, görsel, font ve varsa model dosyalarının bildirimleri; seçilen dağıtım biçimine uygun kaynak sunumu |
| Ek giderler | Özel alan adı, bulut OCR, olası Mac/derleme hizmeti; ücretli satışta mağaza koşulları ayrıca incelenmeli |

Kaynaklar: [Google Play hesap açılışı](https://support.google.com/googleplay/android-developer/answer/6112435?hl=en),
[Play test şartları](https://support.google.com/googleplay/android-developer/answer/14151465),
[Apple üyelik](https://developer.apple.com/help/account/membership/program-enrollment/),
[Flutter Android dağıtımı](https://docs.flutter.dev/deployment/android),
[Flutter iOS dağıtımı](https://docs.flutter.dev/deployment/ios).

Apple kuralları kişisel verilerin üçüncü taraf AI ile paylaşımı için açık
bilgilendirme ve izin ister. Scoresheet'teki oyuncu adları da veri akışı
tasarlanırken dikkate alınmalı. Sunucusuz çekirdeği "bulut OCR de hiç veri
göndermiyor" şeklinde tanıtmamalıyız.
[App Store inceleme kuralları, 5.1.2](https://developer.apple.com/app-store/review/guidelines/)

İlk somut geliştirme adımı, bütün uygulamayı dönüştürmek değil: sabit başlangıcı
koruyup seçilen lisans yolunda **aynı örnek oyunları telefonda ve tarayıcıda
internetsiz doğrulayan küçük çekirdek prototipi**. Doğruluk kanıtlandıktan sonra
kayıt ve arayüz taşınır. Böylece hem mevcut çalışma korunur hem kütüphane kararı
gerçek test sonucu üzerinden verilir.
