# Dosya Dolabı

> **Dosya Dolabı** ("File Cabinet") is an Android app, designed for tablets and
> responsive on phones, that sorts your PDFs, slides and documents into
> categories that are real folders on the device. Turkish UI, sideload-only
> (APK), no internet permission. Built with Flutter.
> Download the APK from [Releases](https://github.com/tungarix/dosya-dolabi/releases).

Android tablet (ve telefon) için PDF, slayt ve belge düzenleyici. İndirdiğin ya da aldığın
dosyalar **Gelen Kutusu**'nda birikir; sen her birini bir **kategoriye** koyarsın
(ör. `Dersler › Matematik`). Kategoriler cihazında **gerçek klasörlerdir**:
dosyalar oraya taşınır, uygulama silinse bile yerinde kalır, Dosyalar
uygulamasında da aynı düzenle görünür.

## Kurulum (APK)

1. [Releases](https://github.com/tungarix/dosya-dolabi/releases) sayfasından
   `Dosya-Dolabi-X.Y.Z.apk` dosyasını cihazına indir. İstersen release
   notundaki SHA-256 ile dosyayı doğrula.
2. Aç ve kur. Android "bilinmeyen kaynaklardan yükleme" izni isterse ver.
3. İlk açılışta **İzin ver**'e bas, çıkan sayfada "Tüm dosyalara erişime izin
   ver" anahtarını aç ve uygulamaya dön.

Sunum dosyalarını (`.pptx`) açmak için cihazında WPS Office gibi bir sunum
uygulaması kurulu olmalı; PDF için çoğu cihazdaki görüntüleyici yeter.

Arayüz 600 dp'den dar ekranlarda (telefon) kendini uyarlar: arama simgeye iner,
seçim ve satır düğmeleri simgeli olur, kategoriler çekmecede açılır.

## Nasıl çalışır

- **Gelen Kutusu:** `Download`, `Documents`, WhatsApp/Telegram belge
  klasörleri, Bluetooth ve SD kart `Download`/`Documents` klasörlerindeki belge
  türlerini (PDF, PPT/PPTX, DOC/DOCX, XLS/XLSX, görsel, arşiv) listeler. Video,
  `.apk` ve yarım kalmış indirmeler görünmez.
- **Kategoriler:** iç içe olabilir (Dersler › Matematik › Vize). Oluştur, adını
  değiştir, başka kategorinin içine taşı, sil. Bir kategori silinince içindekiler
  silinmez, bir üst kategoriye çıkar.
- **Önizleme:** dosya adı anlamsız olsa bile içeriğini tanıyabilmen için her kartta ve
  satırda önizleme var: PDF'in ilk sayfası, resimler (fotoğraflar doğru yönde, saydam
  PNG beyaz zeminde), sunum/Word/ODF dosyalarında içlerine gömülü küçük resim; yoksa ilk
  slayt ya da sayfanın metni; Excel'de ilk hücre metinleri; metin/CSV dosyalarında ilk
  satırlar. Kart menüsündeki **Önizle** büyük, yakınlaştırılabilir bir pencere açar.
  Önizlemesi çıkarılamayan (bozuk, şifreli) dosyada tür simgesi gösterilir.
- **Dosya işlemleri:** aç, kategoriye koy / taşı, adını değiştir, çöp kutusuna at.
  Birden çok dosyayı uzun basarak seçip toplu taşıyabilirsin.
- **Geri al:** her taşıma ve silmeden sonra alt çubukta "GERİ AL" çıkar.
- **Çöp kutusu:** silinen dosyalar 30 gün saklanır, istersen geri konur.
- **Arama:** dosya adında, Türkçe harfleri ayırt etmeden (`notlari` → `notları`).
- **Dosyayı açma:** dosyayı cihazdaki uygulamalardan biri açar (PDF görüntüleyici,
  WPS/PowerPoint vb.). "Şununla aç…" ile uygulama seçilebilir.

Dolabın klasörü: `Dahili depolama/Dosya Dolabı`. Dosyalar hiçbir yere gönderilmez;
uygulamanın internet izni yoktur.

## İzin

Dosyaları kendi klasöründen alıp kategori klasörüne taşıyabilmesi için Android 11+
"Tüm dosyalara erişim" iznini ister (ilk açılışta açıklayıcı bir ekran çıkar).
Bu izin Google Play'de kısıtlıdır; bu yüzden uygulama APK olarak kurulmak üzere
tasarlandı.

## Derleme

Gereken: Flutter (3.47), Android SDK 36, JDK 17+.

```bash
flutter pub get
flutter test                      # birim + arayüz testleri
flutter build apk --release       # build/app/outputs/flutter-apk/app-release.apk
```

Masaüstünde denemek için (gerçek belgelerine dokunmadan):

```bash
DOSYA_DOLABI_KOK=/tmp/dolap DOSYA_DOLABI_GELEN=/tmp/indirilenler flutter run -d windows
```

Windows sürümü yalnızca geliştirme içindir; hedef Android'dir.

### Derleme notları

- Flutter bu proje için NDK 28.2.13676358'i ister. Gradle'ın otomatik kurulumu
  Windows'ta paket adındaki `;` yüzünden başarısız olur; elle kur:
  `sdkmanager "ndk;28.2.13676358"` (komut satırında `;` bölünürse
  `--package_file` ile ver).
- İzin işi (`Tüm dosyalara erişim`) `permission_handler` yerine
  `MainActivity.kt` içinde yazıldı: eklentinin 14.x sürümü Android 37 API'si
  istiyor ve SDK'da platform adı `android-37.0` olduğundan Gradle bulamıyor.
- APK, hata ayıklama anahtarıyla imzalanır; güncellemenin eskisinin üstüne
  kurulabilmesi için aynı bilgisayardan (aynı `~/.android/debug.keystore`)
  derlemek gerekir.
- Sürüm çıkarma sırası ve güvenlik incelemesi: `guvenlik/incelemeler/README.md`.
  İncelemesi kayıtlı olmayan bir release yayımlanırsa `guvenlik-kapisi.yml`
  onu taslağa geri çeker.

## Yapı

| Dosya | Görev |
| --- | --- |
| `lib/src/preview.dart` | Önizleme: zip tabanlı belgelerden (OOXML/ODF) küçük resim ya da metin çıkarımı, metin dosyası başı, önbellek (en çok 160 önizleme, aynı anda 3 iş, ekrandaki önce). |
| `lib/src/library.dart` | Dosya sistemi katmanı: tarama, kategori/dosya işlemleri, geri alma, çöp kutusu. Arayüzden bağımsız. |
| `lib/src/state.dart` | Arayüzün durumu ve işlem sonuçları (`Outcome`). |
| `lib/src/text.dart` | Türkçe arama katlaması, doğal sıralama, boyut/tarih biçimi, ad doğrulama. |
| `lib/src/file_kind.dart` | Dosya türü, simge, renk, MIME. |
| `lib/src/platform_bridge.dart` | Dolap konumu, izin, dosyayı başka uygulamada açma (Dart tarafı). |
| `lib/src/ui/` | Sidebar, dosya görünümü ve önizleme (`file_preview.dart`), dosya işlemleri, diyaloglar, çöp kutusu, izin ekranı. |
| `android/.../MainActivity.kt` | Android köprüsü: depolama izni, `FileProvider` ile dosyayı açma, önizleme isteği. |
| `android/.../Previews.kt` | PDF'in ilk sayfasını (`PdfRenderer`) ve resimleri (`BitmapFactory`, EXIF yönü) küçük resme çevirir; eklenti kullanmaz. |
