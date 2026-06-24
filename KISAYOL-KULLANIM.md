# Arbiter AI — Sahada kullanım (kısayol + telefon erişimi)

## Bilgisayarda başlat (tek tık)
Masaüstündeki **"Arbiter AI Baslat"** kısayoluna çift tıkla
(ya da proje klasöründe `Arbiter-Baslat.cmd`).

Sırayla şunları yapar ve bittiğinde URL + şifreyi ekrana yazar:
1. Docker Desktop'ı açar (kapalıysa)
2. backend + worker + postgres + redis
3. web arayüzünü **üretim modunda** (`next start`, :3000)
4. **ngrok** stabil tünelini (basic-auth korumalı)

Kod değiştiyse bir kereliğine yeniden derlemek için:
PowerShell'de `./start-arbiter.ps1 -Rebuild`

Durdurmak: **"Arbiter-Durdur.cmd"** (ya da açılan minimize pencereleri kapat).

## Telefondan bağlan

### Site (tarayıcı) — en pratik
Telefonun tarayıcısında:

    https://stubbly-flatfoot-trimming.ngrok-free.dev

Şifre sorar:
- kullanıcı: **arbiter**
- şifre: launcher ekranında yazar; kaynağı `~/AppData/Local/ngrok/ngrok.yml`
  (`basic_auth` satırı). *Bu repoda düz şifre tutulmaz.*

> İlk açılışta ngrok bir "Visit Site" uyarı sayfası gösterebilir — bir kez tıkla, geç.

### Uygulama (APK)
APK'yı şu komutla derleyip telefona kur (URL ve şifre derlemeye gömülür):

```bash
cd mobile
# <SIFRE> yerine ngrok.yml'deki gerçek şifreyi yaz (repoya yazma!)
flutter build apk --release \
  --dart-define=BACKEND_URL=https://stubbly-flatfoot-trimming.ngrok-free.dev \
  --dart-define=ARBITER_AUTH=arbiter:<SIFRE>
# Çıktı: build/app/outputs/flutter-apk/app-release.apk
```

Aynı wifi'deyseniz şifresiz yerel erişim de mümkün (launcher ekranda `http://192.168.x.x:3000` yazar) — ama dışarıdayken hep ngrok URL'ini kullan.

## Güvenlik (özet)
- **Basic-auth**: URL'i bilen ama şifreyi bilmeyen kimse uygulamaya **ulaşamaz** (tünel kenarında 401).
- **HTTPS**: ngrok TLS sağlar, trafik şifreli.
- `SECRET_KEY` güçlü ve gizli — imzalı, süreli `/storage` görsel linkleri.
- Rate-limit açık; yükleme magic-byte ile doğrulanır; `DEBUG=false` (Swagger kapalı).
- Şifreyi değiştirmek istersen: `~/AppData/Local/ngrok/ngrok.yml` içindeki
  `basic_auth: ["arbiter:..."]` satırını düzenle, tüneli yeniden başlat.
