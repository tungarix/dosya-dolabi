# Dosya Dolabı sürüm imza anahtarını BİR KEZ oluşturur ve GitHub secret'larına yükler.
#
# - Anahtar ve şifresi depo DIŞINA yazılır (varsayılan: Belgeler\dosya-dolabi-imza).
#   O klasörü USB'ye / Drive'a yedekle: anahtar kaybolursa sonraki sürümler eskisinin
#   üstüne kurulamaz (v1.1.0 -> v1.1.1'de yaşandı).
# - Şifre rastgele üretilir, ekrana basılmaz; secret'lara stdin'den gider.
# - Ekrana yalnız sertifikanın SHA-256 parmak izi basılır (gizli değil).
#
# Kullanım (depo kökünde, gh oturumu açıkken):
#   powershell -ExecutionPolicy Bypass -File scripts\imza_anahtari_olustur.ps1

param(
    [string]$Klasor = (Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'dosya-dolabi-imza'),
    [string]$Repo = 'tungarix/dosya-dolabi'
)
$ErrorActionPreference = 'Stop'

$anahtar = Join-Path $Klasor 'dosya-dolabi-surum.jks'
if (Test-Path $anahtar) {
    throw "Anahtar zaten var: $anahtar. Üzerine yazılmaz; yeni anahtar eski APK'larla uyumsuz olur."
}

$keytool = (Get-Command keytool -ErrorAction SilentlyContinue).Source
if (-not $keytool) {
    # PATH'teki java çoğu zaman Oracle'ın javapath kısayolu; keytool JDK'nın bin'inde.
    $keytool = Get-ChildItem 'C:\Program Files\Java', 'C:\Program Files\Eclipse Adoptium' `
        -Recurse -Depth 3 -Filter keytool.exe -ErrorAction SilentlyContinue |
        Select-Object -Last 1 -ExpandProperty FullName
}
if (-not $keytool -or -not (Test-Path $keytool)) { throw 'keytool bulunamadı (Java ile gelir).' }

New-Item -ItemType Directory -Force $Klasor | Out-Null

# 32 karakter rastgele şifre (harf + rakam; keytool argümanında kaçış gerektirmez).
$harfler = [char[]]'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789'
$rng = [Security.Cryptography.RandomNumberGenerator]::Create()
$bayt = New-Object byte[] 32
$rng.GetBytes($bayt)
$sifre = -join ($bayt | ForEach-Object { $harfler[$_ % $harfler.Length] })

& $keytool -genkeypair -keystore $anahtar -storetype PKCS12 -alias dosya-dolabi `
    -keyalg RSA -keysize 4096 -validity 10000 `
    -storepass $sifre -keypass $sifre `
    -dname 'CN=Aktenak Dosya Dolabi, O=Aktenak, C=TR' 2>&1 | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'keytool anahtarı oluşturamadı.' }

Set-Content -Path (Join-Path $Klasor 'sifre.txt') -Value $sifre -Encoding ascii -NoNewline
@"
Dosya Dolabı sürüm imza anahtarı ($(Get-Date -Format yyyy-MM-dd))
Alias: dosya-dolabi. Şifre: sifre.txt (anahtar ve alias için aynı).
GitHub secret'ları: DOSYA_DOLABI_KEYSTORE_BASE64, DOSYA_DOLABI_KEYSTORE_PASSWORD ($Repo).
Bu klasörü yedekle. Kaybolursa sonraki APK'lar eskisinin üstüne kurulmaz.
"@ | Set-Content -Path (Join-Path $Klasor 'BENIOKU.txt') -Encoding utf8

# --body: PowerShell native programa pipe ederken sona satır sonu ekler, şifreyi bozardı.
gh secret set DOSYA_DOLABI_KEYSTORE_BASE64 -R $Repo --body ([Convert]::ToBase64String([IO.File]::ReadAllBytes($anahtar)))
if ($LASTEXITCODE -ne 0) { throw 'Secret yüklenemedi (gh auth status?).' }
gh secret set DOSYA_DOLABI_KEYSTORE_PASSWORD -R $Repo --body $sifre
if ($LASTEXITCODE -ne 0) { throw 'Secret yüklenemedi (gh auth status?).' }
$sifre = $null

Write-Host "Tamam. Anahtar: $Klasor"
Write-Host 'Sertifika parmak izi:'
& $keytool -list -v -keystore $anahtar -storepass (Get-Content (Join-Path $Klasor 'sifre.txt') -Raw) -alias dosya-dolabi |
    Select-String 'SHA256:'
Write-Host "Şimdi bu klasörü yedekle: $Klasor"
