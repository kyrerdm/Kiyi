# Kıyı kurulum ve ilk kullanım

Kıyı, kyrerdm tarafından geliştirilen GPL-3.0 lisanslı bir Boring Notch fork’udur.
Kaynak kodu: https://github.com/kyrerdm/Kiyi

## 1. Uygunluk

- macOS 14 veya üzeri gerekir. Apple menüsü → Bu Mac Hakkında’dan sürümünü kontrol et.
- Universal paket hem Apple Silicon hem Intel kodu içerir. Intel/macOS 14–26 üzerinde fiziksel doğrulama henüz yapılmadı; esas test ortamı macOS 27.2’dir.
- Hazır uygulamayı kullanmak için Xcode, Git veya Homebrew gerekmez.
- Müzik için öncelikli test edilen uygulama Spotify masaüstüdür.
- Başka notch uygulamalarını ve Dock tıklamasını değiştiren araçları kapat.

## 2. Dosyayı yükle

DMG’yi açıp Kıyı.app’i Applications kısayoluna sürükle. DMG’yi çıkar ve Uygulamalar’dan Kıyı’yı aç. ZIP paylaşıldıysa açılan payload klasöründeki Kıyı.app’i Uygulamalar’a taşı. İndirilenler veya DMG içinden kalıcı olarak çalıştırma; izinler kurulu konuma verilmelidir.

İstersen dağıtım klasöründeki SHA256SUMS.txt ile indirilen dosyanın SHA-256 değerini karşılaştır. Bu kontrol dosya bozulmasını gösterir; yayıncının kimliğini doğrulayan Apple imzasının yerine geçmez.

**Bu sürüm Developer ID imzalı veya Apple noter onaylı değildir.** macOS geliştiriciyi doğrulayamayabilir. Yalnız kaynağına güvendiğin pakette, açmayı denedikten sonra Sistem Ayarları → Gizlilik ve Güvenlik → Yine de Aç seçeneğini kullan. Apple rehberi: https://support.apple.com/en-us/102445

Gatekeeper/SIP’i kapatman veya Terminal’de güvenlik engelini kaldıran komutlar çalıştırman gerekmez. Yönetilen/kurumsal Mac bu kurulumu engelleyebilir; kurum politikasını aşmaya çalışma.

## 3. İzinler

Menü çubuğundaki Kıyı simgesi → Ayarlar. macOS sürümüne göre izin bölümünün adı farklı olabilir.

| Özellik | Gerekli erişim |
| --- | --- |
| Gelgit Dock küçültme/geri getirme | Gizlilik ve Güvenlik → Erişilebilirlik; yeni sürümlerde Aygıt Denetimi ve Veri Erişimi |
| Ses/parlaklık tuşlarını adada gösterme, Spotify beğeni | Aynı Erişilebilirlik/Aygıt Denetimi izni |
| Spotify/Music parça ve oynatma denetimi | Sorulduğunda Otomasyon → Spotify/Music |
| Kamera aynası | İsteğe bağlı Kamera |
| Takvim içeriği | İsteğe bağlı Takvim |

Erişilebilirlik geniş bir uygulama denetimi yetkisidir; yalnız bu özellikleri istiyorsan aç. İzin penceresinden **Uygulamalar/Kıyı.app** dosyasını seç. Mac parola/Touch ID isterse kendin onayla. Uygulama izinleri otomatik veremez. Gerekirse Kıyı menüsünden çıkıp tekrar aç. Gelgit sayfasında “Gelgit hazır” görünmeli. Yardımcıya ayrıca bir dosya yolu kurman gerekmez; XPC hizmeti uygulamanın içindedir.

## 4. İlk kontrol

1. Ayarlar → Davranış bölümünden Türkçe, English veya Deutsch seç; menüyü tekrar açıp dili kontrol et.
2. Boyut/şeffaflığı değiştir; ayarları kapatıp aç, değerin korunduğunu gör.
3. Spotify’da şarkı çal. Adanın üzerine gel; duraklat/oynat ve beğeni/geri almayı dene. Spotify yeniden açılınca da dene.
4. Fiziksel ses/parlaklık tuşlarına bas; kısa göstergeyi kontrol et. Bazı harici ekran/ses aygıtlarında seviye değiştirilemez.
5. Gelgit’i aç. Normal pencereli Finder/Chrome öndeyken kendi Dock simgesine tıkla; küçülmeli. Bir kez daha tıkla; geri gelmeli. Tam ekran, modal pencere, sağ tık ve simge sürükleme aynı davranışı hedeflemez.
6. Kilit ekranında kartı etkinleştir. Hazır olduğunda kendin kilitle; müzik kontrollerini dene. Duraklatınca ayarlanan süre sonra kart gizlenmeli. Ekranı açık tutma seçeneği güç tüketimini artırabilir; yalnız müzik çalarken uygulanır, güvenlik kilidini kaldırmaz.
7. Dosya rafına önemsiz bir test dosyası bırak; AirDrop paylaşımını istersen kendi cihazınla dene. Dosyalarını silmez veya otomatik olarak başka birine göndermez.

AirPods göstergesi bağlı cihazın macOS tarafından bildirilen verilerine bağlıdır; kutu pili her zaman gelmeyebilir. Çentiksiz ekranlarda boyut ve yerleşimi ayarlamak gerekebilir.

## 5. Güncelleme ve sorun giderme

Uygulama açıkken yaklaşık iki saatte bir GitHub güncelleme akışı kontrol edilir. Yeni imzalı sürüm otomatik indirilir ve uygun kapanışta kurulur; macOS gerektiğinde onay isteyebilir. Ayarlar → Güncellemeler bölümünden kontrol ve indirme ayrı ayrı kapatılabilir. Yayıncı yalnız kaynak kodunu güncellerse güncelleme gelmez; imzalı dağıtım paketi ve güncelleme akışı gerekir.

Elle güncellemek için önce menüden Kıyı’yı kapat, eski uygulamayı yedekle ve yeni Kıyı.app’i aynı Uygulamalar konumuna koy. Tercihler korunur. Ad-hoc imza değiştiğinde macOS izin kaydını yenilemeni isteyebilir; Sistem Ayarları’ndan eski Kıyı kaydını kaldırıp kurulu yeni Kıyı’yı yeniden ekle. İzin veritabanını elle düzenleme.

- **Simge görünmüyor:** menü çubuğunda yer aç, başka notch uygulamasını kapat. Kıyı ayarlar kapalıyken Dock’ta görünmez.
- **⌘Q kapatmıyor:** tasarlanan davranış; tam çıkış menü çubuğundan yapılır.
- **Gelgit/tuşlar çalışmıyor:** doğru konumdaki uygulamanın iznini ve Gelgit durumunu kontrol et; uygulamayı menüden kapatıp yeniden aç.
- **Spotify beğeni çalışmıyor:** Spotify masaüstünde bir parça aç, erişilebilirlik ve otomasyon izinlerini kontrol et. Spotify arayüz güncellemeleri uyumluluğu etkileyebilir.
- **Kilit ekranı kartı yok:** müzik çalıyor mu ve Kilit ekranı seçeneği açık mı kontrol et. macOS güncellemeleri bu entegrasyonu etkileyebilir.
- **Paket açılamıyor:** dosyayı yeniden indir ve hash değerini karşılaştır. Güvenlik uyarısını körlemesine aşma; kaynağı veya kaynak koddan derlemeyi doğrula.

Sorunu https://github.com/kyrerdm/Kiyi/issues adresine macOS sürümü, işlemci, Kıyı sürümü ve tekrar adımlarıyla bildir. Kişisel dosya, hesap veya seri numarası ekleme.

## 6. Kaldırma

Menüden Kıyı’yı kapat. Uygulamalar/Kıyı.app’i Çöp Sepeti’ne taşı. Giriş öğesi etkinse Sistem Ayarları → Genel → Giriş Öğeleri’nden kapat. Gizlilik izinlerindeki Kıyı kaydını kaldırabilirsin. Tercihleri silmek zorunda değilsin; yeniden kurulum için kalabilir.

Güncellemeler bölümünde kontrol aralığı **1–168 saat** arasında değiştirilebilir (varsayılan 2 saat). Otomatik kontrol ve indirme ayrı seçeneklerdir. Son kontrol zamanı ve elle kontrol düğmesi aynı bölümde yer alır; değişiklikler yeniden açılışta korunur.

## Tam ekran oyunlar

Ayarlar → Davranış → Tam ekranda seçeneği varsayılan olarak **Daima gizle** değerindedir. Kıyı, tam ekran uygulamanın bulunduğu ekranda adayı ve tüm ada bildirimlerini gizler; görünmez panel oyun tıklamalarını yakalamaz. Tam ekrandan çıkınca geri gelir. macOS tam ekran Spaces yanında, ekranı kaplayan çerçevesiz oyun pencereleri de algılanır. Normal, menü çubuğunun altında büyütülmüş pencereler tam ekran sayılmaz. Daha önce açıkça seçilmiş “Medya uygulamasında gizle” veya “Görünür kalsın” tercihleri korunur; oyunlarda gizlemek için “Daima gizle”yi seç. Kilit ekranı oynatıcısı ayrı çalışır.

Bu algılama ek bir Ekran Kaydı veya Erişilebilirlik izni istemez. Çerçevesiz mod değişimleri yaklaşık yarım saniyede kontrol edilir. Farklı oyun motorları ve çoklu ekran donanımları ayrıca gerçek cihazda doğrulanmalıdır.
