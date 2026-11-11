# Kıyı

**Ekranının kıyısında.** kyrerdm tarafından geliştirilen kişisel macOS çentik uygulaması.

Kıyı, [TheBoredTeam/boring.notch](https://github.com/TheBoredTeam/boring.notch) temelinde geliştirilen GPL-3.0 lisanslı bir türev çalışmadır. Özgün telif bildirimleri ve üçüncü taraf lisansları korunur. Kıyı arayüzü ve ek özellikler kyrerdm tarafından hazırlanmıştır.

## Özellikler

- Spotify ve desteklenen medya kaynakları için oynatıcı.
- Ayarlanabilir şarkı değişimi bildirimi; kapak, metin, süre ve ana adayla eşzamanlı şeffaflık.
- Ses/parlaklık tuşlarında kompakt gösterge.
- Kilit ekranında müzik kartı ve genişletilebilir kapak.
- Dosya rafı ve macOS paylaşım menüsü/AirDrop.
- AirPods bağlantı bildirimi, macOS raporladığında pil değerleri.
- Takvim, hatırlatıcılar ve kamera aynası.
- Türkçe, aranabilir ve yeniden tasarlanmış ayarlar. Sistem/özel vurgu rengi.
- Ayarlar açıkken Dock simgesi. ⌘Q ayarları kapatır; tam çıkış menü çubuğundandır.

## Derleme

macOS ve Xcode gerekir. Projenin deployment hedefi macOS 14 olsa da geliştirme kontrolleri macOS 27.2 / Xcode 27.2 üzerinde yapılmıştır; eski sürümler ayrı doğrulanmamıştır.

```sh
bash scripts/build.sh
open 'build/Kıyı.app' --args --settings
python3 Tests/check-fork.py
```

Xcode projesi `App/boringNotch.xcodeproj`, scheme `boringNotch`. Çıktı `build/Kıyı.app`. Swift paketleri ilk derlemede indirilir. Yerel ad-hoc imza kullanılır; ücretli geliştirici hesabı gerekmez. Her yeni derlemede macOS tuş erişimi için yeniden kullanıcı onayı isteyebilir.

## İzinler ve sınırlar

Ses/parlaklık tuşları için macOS erişilebilirlik/aygıt denetimi, medya kontrolünde Otomasyon, takvim ve kamera için ilgili izinler gerekir. İzinler uygulama tarafından otomatik verilmez. Gerekenleri yalnız kullandığınız özellikler için açın.

Kilit ekranı entegrasyonu özel WindowServer API'leri kullanır ve macOS güncellemelerinden etkilenebilir. Spotify kilit kartı ve oynatma kontrolü geliştirme sırasında doğrulanmıştır. AirPods donanım, AirDrop ve uyku/uyanma senaryoları tüm cihazlarda doğrulanmış değildir. Dönen AirPods görseli yerel simge animasyonudur. Sözler veri sağlayıcısına bağlıdır. EQ, hava durumu ve AirPods dinleme modu değiştirme uygulanmamıştır.

Güncelleme altyapısı upstream güncellemelerini otomatik kurmaz. Bu depo henüz notarize edilmiş dağıtım veya otomatik sürüm kanalı sunmaz.

## Kaynak düzeni

- `App/`: macOS uygulaması, XPC yardımcısı, lisanslar ve upstream temeli.
- `Assets/`, `scripts/`: Kıyı simgesi ve derleme araçları.
- `Tests/check-fork.py`: tercihler, Türkçe çeviri ve paket kimliği kontrolleri.
- `Sources/`: önceki bağımsız prototip; güncel uygulama değildir.

## Lisans

[GPL-3.0](LICENSE), [upstream lisansı](App/LICENSE) ve [üçüncü taraf bildirimleri](App/THIRD_PARTY_LICENSES). Ayrıntılı köken bilgisi için [NOTICE](NOTICE.md).
