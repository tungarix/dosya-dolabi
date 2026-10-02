# Sürüm güvenlik incelemeleri

Her `vX.Y.Z` sürümü yayımlanmadan önce, önceki sürümden bu yana değişen kod
güvenlik açısından incelenir ve sonuç bu klasöre `vX.Y.Z.md` olarak yazılır.
APK yerelde derlendiği için kapı yayımlama anında çalışır: bir release
yayımlandığında `.github/workflows/guvenlik-kapisi.yml`, `scripts/guvenlik_kapisi.py`
ile kaydı denetler. Kayıt yoksa ya da güncel değilse release taslağa geri çekilir.

## Sıra

1. Sürümü `pubspec.yaml`'da (`version:`) yükselt, commit et.
2. Önceki etiketten bu yana olan farkı incele (`git diff vÖNCEKİ..HEAD`).
   Claude Code'da `/security-review` bu iş için kullanılır.
3. Açık yüksek/orta bulgu varsa önce düzelt, commit et, 2. adıma dön.
4. Kaydı yaz, commit et ve `main`'e push et. Bu commit'te kayıt dışında dosya olmasın.
5. Etiketle ve kapıyı yerelde dene:
   `git tag vX.Y.Z && python scripts/guvenlik_kapisi.py vX.Y.Z && git push origin vX.Y.Z`
6. APK'yı bu bilgisayarda derle (aynı `~/.android/debug.keystore`), `dagitim/`
   altına `Dosya-Dolabi-X.Y.Z.apk` olarak koy ve taslak release aç:
   `gh release create vX.Y.Z dagitim/Dosya-Dolabi-X.Y.Z.apk --draft`.
7. Taslaktaki APK'yı cihazda dene, sonra yayımla. Kapı yayımlamada yeniden denetler.

İncelemeden sonra kayıt dışında bir dosya değişirse kapı kapanır: incelemeyi
yenile, `Kapsam:`'ın sonundaki commit'i güncelle.

## Kayıt biçimi

İlk üç alan kapının okuduğu satırlardır, gerisi serbest:

```markdown
# v1.2.0 güvenlik incelemesi

Sürüm: v1.2.0
Kapsam: v1.1.0..<incelenen commit, 7-40 karakter sha>
Sonuç: geçti

## Bulgular
- (yoksa "Yüksek/orta bulgu yok.")

## Kabul edilen riskler
- (varsa gerekçesiyle)
```

`Sonuç:` yalnız `geçti` olduğunda kapı açılır. Önceki etiket yoksa (ilk sürüm)
`Kapsam:`'ın başı `başlangıç` olur.
