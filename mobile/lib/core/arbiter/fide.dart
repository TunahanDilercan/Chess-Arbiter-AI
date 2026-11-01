/// FIDE Laws of Chess references used by the arbiter tools.
///
/// Summaries are Turkish paraphrases of the Laws effective 1 January 2023
/// (FIDE Handbook E.01), not verbatim quotes. The app always tells the arbiter
/// that the final decision is theirs and the Handbook text prevails.
library;

class FideArticle {
  const FideArticle(this.number, this.title, this.summary);

  final String number;
  final String title;
  final String summary;

  String get label => 'Madde $number';
}

abstract final class Fide {
  static const lawsVersion = 'FIDE Satranç Kuralları, 1 Ocak 2023 (E.01)';

  static const a3_9 = FideArticle('3.9', 'Şahın şah altında kalmaması',
      'Bir hamle, oynayanın kendi şahını rakip taşın saldırısı altında bırakamaz.');
  static const a4_3 = FideArticle('4.3', 'Dokunulan taş',
      'Bilerek dokunulan kendi taşı, oynanabiliyorsa oynanmalıdır; rakip taşa '
          'dokunulduysa alınabiliyorsa alınmalıdır.');
  static const a5_1_1 = FideArticle('5.1.1', 'Mat',
      'Mat eden oyuncu kazanır; mat eden hamle yasalsa oyun hemen sona erer.');
  static const a5_2_1 = FideArticle('5.2.1', 'Pat',
      'Sırası gelen oyuncunun yasal hamlesi yoksa ve şahı şah altında değilse '
          'oyun berabere biter.');
  static const a5_2_2 = FideArticle('5.2.2', 'Ölü konum',
      'Hiçbir tarafın hiçbir yasal hamle dizisiyle mat edemeyeceği konum oluşursa '
          'oyun hemen berabere biter (talep gerekmez).');
  static const a6_9 = FideArticle('6.9', 'Süre aşımı (bayrak)',
      'Süresi biten oyuncu kaybeder; ancak rakip hiçbir yasal hamle dizisiyle mat '
          'edemeyecekse oyun berabere biter.');
  static const a7_5_1 = FideArticle('7.5.1', 'Kural dışı hamle',
      'Oyuncu saatine bastığında kural dışı hamle tamamlanmış sayılır. Hakem '
          'kural dışı hamleden hemen önceki konumu yeniden kurar; yeni hamleye 4.3 '
          've 4.7 uygulanır.');
  static const a7_5_2 = FideArticle('7.5.2', 'Hatalı terfi',
      'Piyon son sıraya ulaşıp yerine taş konmadan saate basılırsa kural dışı '
          'hamle sayılır; piyon aynı renkten bir vezirle değiştirilir.');
  static const a7_5_3 = FideArticle('7.5.3', 'Hamle yapmadan saate basmak',
      'Hamle yapmadan saate basmak kural dışı hamle gibi değerlendirilir.');
  static const a7_5_4 = FideArticle('7.5.4', 'İki elle hamle',
      'Bir hamleyi (rok, alma, terfi dahil) iki elle yapmak kural dışı hamle gibi '
          'değerlendirilir.');
  static const a7_5_5 = FideArticle('7.5.5', 'Kural dışı hamle cezası',
      'Bir oyuncunun ilk tamamlanmış kural dışı hamlesinde rakibine ek süre '
          'verilir; aynı oyuncunun ikincisinde oyuncu kaybeder. Rakip hiçbir yasal '
          'hamle dizisiyle mat edemiyorsa oyun berabere biter.');
  static const a8_4 = FideArticle('8.4', 'Kayıt muafiyeti',
      'Süresi 5 dakikanın altına düşen ve hamle başına 30 sn+ eklenmeyen oyuncu, '
          'o periyodun geri kalanında hamle kaydetmek zorunda değildir.');
  static const a9_2_1_1 = FideArticle('9.2.1.1', 'Üç tekrar — oluşmak üzere',
      'Sırası gelen oyuncu hamlesini değiştirilemez şekilde karneye yazar ve '
          'hakeme bu hamleyi yapacağını bildirirse; hamle aynı konumu en az 3. kez '
          'oluşturacaksa talep doğrudur.');
  static const a9_2_1_2 = FideArticle('9.2.1.2', 'Üç tekrar — oluştu',
      'Aynı konum en az 3. kez az önce oluştuysa ve talep eden oyuncunun hamle '
          'sırası ise talep doğrudur.');
  static const a9_2_2 = FideArticle('9.2.2', 'Aynı konum tanımı',
      'Aynı oyuncunun sırası, aynı taşlar aynı karelerde ve iki tarafın olası '
          'hamleleri aynıysa konumlar aynıdır. Geçerken alma imkânı veya rok hakkı '
          'farkı konumu farklı kılar.');
  static const a9_3 = FideArticle('9.3', '50 hamle',
      'Sırası gelen oyuncu, son 50 hamlede (her iki taraf) piyon oynanmadığını ve '
          'alma yapılmadığını gösterirse (ya da yazdığı hamleyle bu oluşacaksa) '
          'beraberlik talep edebilir.');
  static const a9_4 = FideArticle('9.4', 'Talep hakkının kaybı',
      'Oyuncu 4.3 uyarınca bir taşa dokunursa o hamlede 9.2/9.3 talep hakkını '
          'kaybeder.');
  static const a9_5_1 = FideArticle('9.5.1', 'Talep usulü',
      'Talepte saat durdurulur; talep geri alınamaz.');
  static const a9_5_2 = FideArticle('9.5.2', 'Doğru talep',
      'Talep doğruysa oyun hemen berabere biter.');
  static const a9_5_3 = FideArticle('9.5.3', 'Yanlış talep',
      'Talep yanlışsa hakem rakibin süresine ek süre ekler ve oyun devam eder. '
          'Talep niyet edilen hamleye dayanıyorsa bu hamle Madde 3 ve 4\'e göre '
          'oynanmalıdır.');
  static const a9_6_1 = FideArticle('9.6.1', 'Beş tekrar (otomatik)',
      'Aynı konum (9.2.2 anlamında) en az 5 kez oluşursa oyun berabere biter; '
          'talep gerekmez.');
  static const a9_6_2 = FideArticle('9.6.2', '75 hamle (otomatik)',
      'Her iki taraf en az 75 hamle piyon oynamadan ve alma yapmadan oynarsa oyun '
          'berabere biter. Son hamle mat ise mat önceliklidir.');
  static const appendixA = FideArticle('Ek A', 'Hızlı satranç',
      'Yeterli hakem gözetimi yoksa hakem, rakip bir sonraki hamlesini yapmadan '
          'önce kural dışı hamleye müdahale eder; rakip hamle yaptıysa kural dışı '
          'hamle düzeltilmez. Cezalarda ek süre 1 dakikadır.');
  static const appendixB = FideArticle('Ek B', 'Yıldırım satranç',
      'Yeterli gözetim yoksa hızlı satranç (Ek A) kuralları uygulanır; cezalarda '
          'ek süre 1 dakikadır.');
}
