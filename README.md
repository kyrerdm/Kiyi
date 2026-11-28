# Kıyı

**macOS için kişiselleştirilebilir çentik, müzik ve Dock yardımcısı.**

Kıyı; müzik kontrollerini, şarkı değişimi bildirimlerini, ses/parlaklık göstergelerini ve dosya rafını ekranın üst kısmında bir araya getirir. Kilit ekranında albüm kapağı ve oynatma kontrolleri sunar. **Gelgit**, öndeki uygulamanın Dock simgesine yeniden tıklayınca pencereyi küçültür, sonraki tıklamada geri getirir.

Geliştiren: **[kyrerdm](https://github.com/kyrerdm)** · [Kurulum rehberi](docs/KURULUM.md) · [Hata bildir](https://github.com/kyrerdm/Kiyi/issues)

## Gereksinimler ve destek durumu

| Konu | Durum |
| --- | --- |
| İşletim sistemi | Derleme hedefi macOS 14 Sonoma ve üzeri |
| İşlemci | Paylaşım paketi Universal: Apple Silicon `arm64` ve Intel `x86_64` |
| Donanım | Çentikli MacBook için tasarlanmıştır; çentiksiz ekranlarda yerleşim farklı olabilir |
| Dil | Türkçe, English, Deutsch; Ayarlar → Davranış |
| Müzik | Öncelikle Spotify masaüstü; Music/Now Playing altyapısı da bulunur |
| Xcode | Hazır paketi kullanmak için gerekmez. Kaynaktan derleme için tam Xcode gerekir |
| İmza | Yerel ad-hoc imza; Developer ID ile imzalı / Apple tarafından noter onaylı değildir |

**Her Mac üzerinde test edilmiş bir kararlı sürüm değildir.** Gerçek kullanım doğrulaması geliştirme Mac’inde macOS 27.2 üzerinde yapıldı; macOS 14–26 ve Intel donanımında ayrı fiziksel test yapılmadı. Universal derleme ve paket kontrolleri bu testlerin yerine geçmez. Kilit ekranı, sistem medya erişimi ve parlaklık gibi özellikler macOS sürümüne/donanıma bağlıdır. AirPods sol/sağ/kutu pili yalnız sistem bildiriyorsa gösterilir; gerçek cihaz testi tamamlanmadı. Harici ekran parlaklığı ve her ses çıkışında seviye kontrolü garanti edilmez.

## Kurulum

**[Hazır kurulum paketini indir — GitHub Releases](https://github.com/kyrerdm/Kiyi/releases/latest)**

1. Paylaşılan `Kiyi-…-universal.dmg` dosyasını aç. Depoda derleme varsa [Actions](https://github.com/kyrerdm/Kiyi/actions) bölümündeki **Build portable Kiyi** çalışmasının paketini de indirebilirsin (artifact indirmek GitHub oturumu gerektirebilir).
2. **Kıyı.app** dosyasını **Applications / Uygulamalar** klasörüne sürükle. DMG’yi çıkar, uygulamayı Uygulamalar’dan aç. ZIP kullanıyorsan içindeki `payload/Kıyı.app` dosyasını taşı.
3. Geliştirici doğrulanamıyorsa yalnız kaynağına güvendiğin pakette Sistem Ayarları → Gizlilik ve Güvenlik → **Yine de Aç** yolunu kullan. Bu paket noter onaylı değildir. [Apple’ın açıklaması](https://support.apple.com/en-us/102445). Gatekeeper’ı/SIP’i kapatma; Terminal’den toplu izin veya karantina silme komutları çalıştırma.
4. Menü çubuğundaki Kıyı simgesi → **Ayarlar**. Kullanacağın özelliklerin izinlerini ver; ayrıntılar [kurulum rehberinde](docs/KURULUM.md).
5. Spotify’da bir şarkı çal, adanın üzerine gel ve oynat/duraklatı dene. Ses ve parlaklık tuşlarını, ardından Gelgit’i dene.

Kıyı ayarlar açıkken Dock’ta görünür; ayarlar kapalıyken menü çubuğunda çalışır. **⌘Q ayarları kapatır.** Tam çıkış menü çubuğundaki **Kıyı’yı kapat** seçeneğidir. Aynı anda başka çentik/Dock davranışı uygulamaları çalıştırma.

## Özellikler

- Canlı boyut, kapak konumu, tema ve şeffaflık ayarları; ayarlar otomatik kaydedilir.
- Spotify oynatma, ilerleme/geri sarma, iki parmakla yatay zaman çizgisi hareketi ve beğeni kontrolü.
- Şarkı değişiminde yatay bildirim; ana adayla eşzamanlı şeffaflık.
- Ses/parlaklık tuşlarında kısa ada göstergesi; pil/şarj ve kulaklık bağlantı bildirimleri.
- Kilit ekranında oynatıcı, büyüyen kapak ve bulanık arka plan. Hareketsizlikte gizleme süresi ve kapanış animasyonu ayarlanır. Müzik çalarken ekranı açık tutma seçeneği vardır.
- Dosya rafı ve AirDrop; takvim ve ayna için isteğe bağlı ek izinler.
- Gelgit için ayrı sekme: tek/tüm pencereler, Finder ve etkinleştirme seçenekleri.

## Yapay zekâya verilebilecek kurulum prompt’u

Aşağıdaki metni bilgisayar ve terminal erişimi olan bir yapay zekâ aracına yapıştırabilirsin. Araçların yetkileri farklıdır; gerekli macOS izinlerini ve kimlik doğrulamasını sen tamamlamalısın.

```text
Mac'ime https://github.com/kyrerdm/Kiyi deposundaki Kıyı uygulamasını kurmama yardım et.
Önce depodaki README.md, docs/KURULUM.md ve AGENTS.md dosyalarını oku.
macOS sürümünü, işlemci mimarisini ve mevcut Kıyı kurulumunu kontrol et.
macOS 14 altındaysa kurulumu durdur. Mevcut uygulamamı/ayarlarımı silme.

Varsa bu depoya ait hazır Universal DMG/ZIP paketini kullan; yerel dosya verildiyse
kaynağını ve SHA256SUMS.txt ile bütünlüğünü kontrol et. Hazır paket yoksa tam Xcode'un
kurulu olduğunu doğrula, depoyu yeni bir klasöre klonla ve bash scripts/release.sh ile
derle. Xcode eksikse kullanıcıya kurulum adımını açıkla; otomatik lisans kabul etme.
Hazır pakette Xcode gerekmediğini unutma.

Kıyı.app'i Uygulamalar'a yerleştir. Mevcut çalışan sürüm varsa menüsünden çık;
üzerine yazmadan önce sürümü kontrol et ve mevcut uygulamayı yedekle.
Uygulama ad-hoc imzalıdır, noter onaylı değildir. Güvenlik engeliyle karşılaşırsan
riski açıkla ve Apple'ın Gizlilik ve Güvenlik > Yine de Aç adımını kullanıcıya bırak.
Gatekeeper/SIP kapatma, karantina silme veya TCC veritabanına müdahale etme.

Kıyı'yı aç. Yalnız kullanıcının istediği özelliklerin izinlerini açıklayarak iste:
Erişilebilirlik/Aygıt Denetimi (Gelgit, tuşlar, Spotify beğeni), Otomasyon (müzik),
isteğe bağlı kamera ve takvim. Touch ID/parola ve güvenlik onaylarını kullanıcıya bırak.
İzinleri otomatik verdiğini iddia etme. Spotify yoksa kurmayı dayatma.

Sonunda ayarların açıldığını ve yeniden açılınca korunduğunu kontrol et.
Kullanıcı izin verirse müzik oynat/duraklat, ses/parlaklık göstergesi ve
Gelgit küçültme/geri getirme davranışını dene. Kilit ekranını kullanıcıyla birlikte dene;
bilgisayarı habersiz kilitleme. Doğrulayamadığın özellikleri açıkça belirt.
Kurulu sürümü, konumu, verilen izinleri ve kalan sorunları kısa raporla.
```

## Kaynaktan derleme

Tam Xcode’u açıp ilk kurulumunu tamamla; etkin geliştirici dizini Xcode’u göstermeli (`xcode-select -p`). Bu çalışma Xcode 27.2 ile doğrulandı. Daha eski Xcode sürümleri ayrıca doğrulanmadı; sabitlenmiş Swift paketlerinin araç zinciri gereksinimleri geçerlidir. İlk derleme internet gerektirir.

```sh
git clone https://github.com/kyrerdm/Kiyi.git
cd Kiyi
bash scripts/build.sh                 # Yerel Debug: build/Kıyı.app
bash scripts/test.sh                  # Fork regresyon kontrolleri
bash scripts/release.sh               # Release, arm64+x86_64, DMG+ZIP+SHA256
```

Release çıktısı `build/releases/Kiyi-<sürüm>-<zaman>/` altındadır; log `build/release-build.log`. Paketin içinde karşılık gelen kaynak kodu `Kiyi-source.tar.gz` olarak da bulunur. Script, çalışan yerel uygulamayı veya izinlerini değiştirmez. Tam Xcode dışında Homebrew, Python paketleri veya ücretli hesap gerekmez; test/paket kontrolleri için `python3` gerekir. Gömülü Perl medya yardımcısı `/usr/bin/perl` kullanır. Sadece Terminal komut satırı araçları uygulamayı derlemek için yeterli değildir.

Gerçek Developer ID dağıtımı için Apple Developer hesabı, tüm iç bileşenleri doğru imzalama, noter onayı ve staple adımları ayrıca gerekir; mevcut script bunları yaptığını iddia etmez. Kıyı, GitHub’daki kendi Sparkle akışını uygulama açıkken yaklaşık iki saatte bir kontrol eder. Otomatik indirme varsayılan olarak açıktır; doğrulanan paket Sparkle tarafından uygun kapanışta kurulur, gerektiğinde kurulum onayı istenir. Ayarlar → Güncellemeler bölümünden kapatılabilir veya elle kontrol edilebilir. Upstream Boring Notch güncelleme akışı kullanılmaz. Yeni sürümün çalışması için yayıncının DMG’yi Releases’a yüklemesi ve imzalı `updates/appcast.xml` girdisini yayımlaması gerekir; yalnız kaynak koda push yapmak güncelleme yayımlamaz.

## Geliştirici ve yapay zekâ araçları için harita

| Yol | Görev |
| --- | --- |
| `App/boringNotch.xcodeproj` | Asıl Xcode projesi; scheme `boringNotch` |
| `App/boringNotch/AdaEnhancements.swift` | Kıyı entegrasyonları, kilit ekranı ve Gelgit istemcisi |
| `App/boringNotch/components/Settings/SettingsView.swift` | Kıyı ayar arayüzü |
| `App/BoringNotchXPCHelper/` | Yetki gerektiren yardımcı işlemler, Gelgit, Spotify erişimi |
| `Tests/`, `scripts/test.sh` | Fork regresyon kontrolleri |
| `scripts/release.sh`, `scripts/verify-release.py` | Universal paket ve dağıtım doğrulaması |
| `Sources/`, `scripts/build-prototype.sh`, `scripts/check.sh` | Eski Ada prototipi; güncel ürün değildir |

Paket kimliği `local.kayra.adanotch`, XPC kimliği `local.kayra.adanotch.BoringNotchXPCHelper` olarak korunur; değiştirmek tercih/izin devamlılığını etkiler. İmza değişiklikleri macOS izinlerini yeniden istemesine neden olabilir. Sorun raporlarına macOS sürümünü, işlemciyi, Kıyı sürümünü ve tekrar adımlarını ekle; özel dosyaları/seri numaralarını paylaşma.

## Lisans ve köken

Kıyı, **[TheBoredTeam/boring.notch](https://github.com/TheBoredTeam/boring.notch)** tabanlı bir **GPL-3.0** fork’udur. Bağımsız ad ve arayüz, upstream kaynakların yazarlığını değiştirmez. Gelgit’in Dock gözlemi [WinMin](https://github.com/Bittabola/winmin) projesinden MIT lisansıyla uyarlanmıştır. MediaRemoteAdapter BSD-3-Clause lisanslıdır. Canopy veya upstream ekiplerle resmî bağlantı yoktur.

[LICENSE](LICENSE), [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md), `App/THIRD_PARTY_LICENSES` ve `App/BoringNotchXPCHelper/WinMin-LICENSE.txt` dosyalarını koru. Binary dağıtılırken karşılık gelen kaynak kodunu ve bu bildirimleri de erişilebilir tut.


## Yeni sürüm yayımlama

1. Xcode projesindeki `MARKETING_VERSION` ve `CURRENT_PROJECT_VERSION` değerlerini ana uygulama ve yardımcı için birlikte artır. Yapı numarası önceki sürümden büyük olmalı.
2. `bash scripts/test.sh` ve `bash scripts/release.sh` çalıştır. DMG/ZIP’i değiştirmeden sakla.
3. `python3 scripts/sign-release.py /tam/yol/Kiyi-<sürüm>-universal.dmg` çalıştır. İmzalama anahtarı bu geliştirme Mac’inin Anahtar Zinciri’nde `kiyi-kyrerdm` hesabındadır. Özel anahtarı Git’e, loglara veya sohbetlere koyma; yedeğini güvenli biçimde koru. Başka Mac’te bu anahtar olmadan geçerli güncelleme imzalanamaz.
4. GitHub Releases’ta `v<sürüm>` etiketiyle karşılık gelen kaynak commit’ini ve **tam olarak bu DMG**’yi yayımla. ZIP ve SHA256 dosyasını da ekle.
5. İndirme URL’sini doğruladıktan sonra dağıtım klasöründeki `appcast.xml` dosyasını depodaki `updates/appcast.xml` üzerine koyup push et. Kaynak değişikliği için CI’dan gelen başka bir binary aynı imzayla kullanılamaz.
6. Önceki kurulu sürümden güncelleme kontrolü/indirme/yeniden açılmayı dene. Noter onayı olmayan bu dağıtımda macOS izin veya güvenlik onayı istemeye devam edebilir. Ed25519 arşiv imzası, Apple Developer ID/noter onayının yerine geçmez.

CI iş akışı doğrulanan Universal paket üretir; özel anahtarı barındırmaz ve kendi başına imzalı güncelleme yayımlamaz. Güncel akış başlangıçta boş olabilir; bu durumda kurulabilir yeni sürüm bildirilmez.

Güncellemeler bölümünde kontrol aralığı **1–168 saat** arasında değiştirilebilir (varsayılan 2 saat). Otomatik kontrol ve indirme ayrı seçeneklerdir. Son kontrol zamanı ve elle kontrol düğmesi aynı bölümde yer alır; değişiklikler yeniden açılışta korunur.

Ad-hoc Release paketinde Team ID bulunmadığından hardened runtime kapalı derlenir; aksi halde macOS gömülü medya kütüphanesini yüklemeyi reddeder. Developer ID/noter onaylı dağıtım ayrı, doğru imzalanmış bir hardened build gerektirir. Sistem genelinde Gatekeeper/SIP ayarı değiştirilmez.

## Tam ekran oyunlar

Ayarlar → Davranış → Tam ekranda seçeneği varsayılan olarak **Daima gizle** değerindedir. Kıyı, tam ekran uygulamanın bulunduğu ekranda adayı ve tüm ada bildirimlerini gizler; görünmez panel oyun tıklamalarını yakalamaz. Tam ekrandan çıkınca geri gelir. macOS tam ekran Spaces yanında, ekranı kaplayan çerçevesiz oyun pencereleri de algılanır. Normal, menü çubuğunun altında büyütülmüş pencereler tam ekran sayılmaz. Daha önce açıkça seçilmiş “Medya uygulamasında gizle” veya “Görünür kalsın” tercihleri korunur; oyunlarda gizlemek için “Daima gizle”yi seç. Kilit ekranı oynatıcısı ayrı çalışır.

Bu algılama ek bir Ekran Kaydı veya Erişilebilirlik izni istemez. Çerçevesiz mod değişimleri yaklaşık yarım saniyede kontrol edilir. Farklı oyun motorları ve çoklu ekran donanımları ayrıca gerçek cihazda doğrulanmalıdır.
