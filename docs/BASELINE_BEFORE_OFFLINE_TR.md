# Çevrimdışı geçiş öncesi sürüm kaydı

Tarih: 10 Ekim 2026, Europe/Istanbul.

Bu kayıt, mevcut sunucu tabanlı uygulamanın bekleyen düzeltmelerini korur.
Çevrimdışı çekirdek bu sürümde henüz uygulanmadı. Başlangıç commit'i
`b639a320bdc2d86753919d2b212c434013bfb9fd`; düzeltme dalı
`fix/stabilize-current`, geçiş dalı `feat/offline-first` olarak ayrılır.
Kaydedilen başlangıç `baseline-before-offline-2026-10-10` etiketiyle işaretlenir.

## Kaydedilen düzeltmeler

- İnsan tarafından onaylanan hamleler, önceki hamle düzeltildiğinde korunur.
- Eksik hücreler hamle sırasını kaydırmaz; doğrulanamayan devam satırlarının
  OCR metni, görselleri ve inceleme geçmişi silinmez.
- Düzeltme yanıtı veritabanındaki inceleme işaretleri ve görsellerle eşleşir.
- Beraberlik özeti, geçmişte oluşmuş talep hakkı yerine güncel konumu ve
  tekrar geçmişini kullanır.
- OCR çıktısının notasyon dili saklanır; İngilizce model çıktısı Türkçe
  notasyon gibi ikinci kez dönüştürülmez.
- Yükleme boyutu sınırlanır; tek sayfalı PDF desteklenir ve büyük görseller
  reddedilir. Kuyruğa gönderme başarısızlığı iş kaydına yansıtılır.
- Tamamlanmış işin yeniden teslimi tekrar OCR çağırmaz; SSE bağlantısı
  kaçırılmış bitiş durumunu kontrol eder ve mobilde yeniden bağlanabilir.
- Mobil anonim oturum uygulama yeniden açıldığında korunur; kırpma seçimi
  gerçekten yüklenen fotoğrafa uygulanır; reddedilen düzeltme mevcut oyunu gizlemez.
- Web inceleme durumları ve küçük ekran düzeni düzeltilir.
- Docker açılışında şema geçişi beklenir; API ve işçi ortak uygulama imajını
  kullanır. Windows başlatma/durdurma araçları ilgili servisleri kontrol eder.

## Doğrulama

| Kontrol | Sonuç |
| --- | --- |
| Windows/Python 3.13 sunucu testleri | 298 geçti |
| Docker/Python 3.11 sunucu testleri | 298 geçti |
| Flutter analiz | Sorun bulunmadı |
| Flutter testleri | 6 geçti |
| Flutter kod ve varlık paketi | Derleme geçti |
| Web TypeScript kontrolü | Geçti |
| Next.js üretim derlemesi | Ayrı doğrulama klasöründe geçti |
| Windows başlatma/durdurma betiklerinin sözdizimi | Hata bulunmadı |
| Git değişiklik biçimi kontrolü | Hata bulunmadı |

Web derlemesi Google Fonts dosyasını kısıtlı ağ ortamında indiremeyip font
optimizasyonunu atladı; derleme başarılı oldu. Web fontlarının çevrimdışı
kullanımı geçiş sırasında ayrıca ele alınmalı.

Testlerde ücretli OCR çağrısı yapılmadı. Docker testleri geçici dosya alanı
ve test veritabanı oturumları kullandı. Bu kontroller Android mağaza imzası,
iOS derlemesi veya yeni yerel satranç çekirdeğinin doğrulandığı anlamına gelmez.

## Kayıt ve veri sınırı

`.env` dosyaları, API anahtarları, oyun verileri ve yerel yedekler bu kaynak
kaydı kapsamına alınmaz. Kayda girebilecek 147 metin dosyasında yaygın sağlayıcı
anahtarı, GitHub token'ı, AWS anahtarı ve özel anahtar başlığı desenleri tarandı;
eşleşme bulunmadı. Bu kontrol geçmişin kapsamlı bir sır denetimi değildir.

Mevcut veritabanı/dosya yedeği `output/backups/20261009-before-upgrade`
klasöründe bulundu; Git dışında tutulur. Kaynak kodu etiketi veritabanı
yedeğinin yerine geçmez. Şema güncelleme ve mevcut kayıtları koruma adımları
`docs/DEPLOYMENT.md` içinde açıklanır.

`main` bu kayıt için doğrudan değiştirilmez. Mevcut sürüm düzeltme dalında
incelenebilir; çevrimdışı çalışma aynı doğrulanmış commit'ten başlatılır.
İlk geçiş aşaması, izin verici lisanslı kütüphane adaylarıyla mevcut Python
davranışı ve bağımsız FIDE örneklerini karşılaştıran küçük bir prototiptir.
Dağıtım lisansı ve depo görünürlüğü bu sürüm kaydıyla değiştirilmez.

Ayrıntılı seçenekler: `docs/OFFLINE_FIRST_OPTIONS_TR.md`.
