# DST Dolapdere Sozlesme Takip

Reklam alanlarini, kiracilari ve kira sozlesmelerini yonetir. Kayitlar SharedPreferences ile cihazda onbelleklenir ve Firebase Firestore ile es zamanli calisir.

Firestore koleksiyonlari `workspaces/rst_dolapdere/customers`, `adSpaces`, `contracts` ve `settings/reminders` yollarindadir. Android baglantisi `android/app/google-services.json` ile eslesir. Ilk acilista cihazdaki yerel kayitlar Firestore'a birlestirilir; Firestore degisiklikleri cihaz onbellegine akar. Windows Firestore plugini desteklenmediginden Windows'ta SharedPreferences kullanilir.

## Otomatik E-posta

Firebase Cloud Function her 5 dakikada bir calisir, ayarlardaki Istanbul saat araligina geldiginde aktif sozlesmeleri kontrol eder. Bitise 10, 5 ve 0 gun kalinca yoneticiye e-posta/WhatsApp gonderir. Fonksiyonlar `workspaces/rst_dolapdere` altindaki ayni koleksiyonlari kullanir.

Uygulamada Ayarlar'dan yonetici e-posta adresini girip **Otomatik e-posta bildirimi** anahtarini acin. Firestore'daki `reminderDeliveries` koleksiyonu yinelenen gonderimi onler.

## Cihaz Bildirimleri

**Ayarlar > Bildirim gönderme saati** Android/iOS cihaz bildirimleri ve Windows bildirimleri icin saati belirler. Windows masaustu bildirimi yalnizca Windows uygulamasinda gosterilir. Anahtar ilk kez acilinca uygulama kendi izin onay penceresini gosterir; kullanici **Izin ver** demeden Windows bildirimi etkinlesmez. Bu, uygulama ici onaydir; Windows ayarlarinda bildirimler sistem genelinde kapaliysa Windows sistem ayarlarindan da izin verilmelidir. Windows uygulamasinin toast bildirimleri icin kayitli/kurulu uygulama kimligi ve Windows bildirim altyapisi gerekir.

Bildirim tetikleme zamanlari Android/iOS ve Windows'ta secilen saate gore 10, 5 ve bitis gunu icin planlanir. Biten veya yaklasan sozlesme bildirimi secilince **Incele** ile sozlesme detayina gidilir.

## Sozlesme Yasam Dongusu

Aktif **Sozlesmeler** ekraninda tumu/yaklasan/suresi dolan filtreleri ve bitis tarihine gore yakin-uzak siralama bulunur. **Biten Sozlesmeler** ayri menude hem suresi dolmus kayitlari hem kullanicinin elle bitirdigi kayitlari gosterir. Bir sozlesme bitirildiginde eski kayit ayni kimlikle yeniden acilamaz. **Sozlesmeyi uzat** eski kaydi biten olarak kilitler ve ayni musteri/alan icin yeni tarih ve yeni aylik fiyatla yeni bir sozlesme olusturur.

Uzatma mevcut sozlesme kimligini ve baslangic tarihini korur; bitis tarihini ileri alir. Her iki sozlesme listesinde PDF duzen/aktar dugmesi gorunen kayitlari sistemin PDF kaydet/yazdir penceresinde acar. PDF'ye `assets/fonts/NotoSans-Variable.ttf` fontu gomulur; Turkce karakterler dis sistem fontuna bagli kalmaz.

## Kullanici, Rol ve Onay Kurulumu

Uygulamayi kimlik dogrulama ile kullanmadan once Firebase Console'da Authentication > Sign-in method altindan **Email/Password** saglayicisini etkinlestirin. Firestore Security Rules ve Cloud Functions'i proje kokunden yayinlayin:

```powershell
firebase deploy --only firestore:rules,functions
```

Ilk sistem yoneticisi Firebase Console > Authentication > Users bolumunde e-posta adresi `yonetici@login.rst-dolapdere.invalid` olacak sekilde olusturulur. Bu kullanicinin UID'si ile Firestore'da `workspaces/rst_dolapdere/users/{UID}` dokumani olusturun. Ornek profil:

```json
{
  "username": "yonetici",
  "authEmail": "yonetici@login.rst-dolapdere.invalid",
  "email": "yonetici@ornek.com",
  "role": "admin",
  "isActive": true,
  "permissions": {},
  "notificationPreferences": { "inApp": true, "push": true, "email": true },
  "assignedContractIds": [],
  "assignedCustomerIds": [],
  "assignedAdSpaceIds": []
}
```

`workspaces/rst_dolapdere/usernameIndex/yonetici` dokumanini `{ "uid": "..." }` olarak ekleyin. Ilk admin olusturma/yetki atama uygulamadan yapilmaz; boylece istemci kendisini admin yapamaz. Sonraki kullanicilar Ayarlar > Kullanıcılar ve roller panelinden eklenir. Sorumlulara modullere erisim izni verilir ve goruntuleyecekleri sozlesmelere yonetici tarafindan sorumlu atanir. Sorumlu yeni sozlesme eklediginde veya uzattiginda pozitif birim fiyat girmeli; islem yonetici onayina kadar sozlesmeye uygulanmaz. Sorumlular atanmis sozlesmeleri etkin/pasif yapabilir, silemez.

Kisiye ozel e-posta bildirimi icin Functions secrets olarak SMTP bilgilerini (`SMTP_HOST`, `SMTP_PORT`, `SMTP_USER`, `SMTP_PASSWORD`, `MAIL_FROM`) tanimlayin. Push icin Firebase Cloud Messaging platform kurulumunu tamamlayin: iOS'ta APNs anahtari, web'de Firebase Web Push VAPID anahtari gereklidir. Android icin Firebase Messaging konfigurasyonunun `google-services.json` ile ayni projeye ait oldugunu kontrol edin. E-posta adresi olmayan kullanici uygulama ici ve push bildirimlerini alabilir.

Guvenlik kurallarini yayinlamadan once mevcut verilerinizin `workspaces/rst_dolapdere` altinda oldugunu dogrulayin. Eski bir kurulumda belgeler `workspaces/dst_dolapdere` altindaysa, yayin oncesi Console veya guvenilir bir Admin SDK migration ile `rst_dolapdere` altina tasi. Supervisor hesaplari sadece sorumlu atandigi sozlesme, kiraci ve reklam alanlarini okuyabilir; sozlesme yazma/onay islemleri callable Functions tarafinda yetkilendirilir.

## Otomatik WhatsApp

WhatsApp gonderimi icin Meta WhatsApp Business Cloud API ve onayli bir mesaj sablonu gerekir:

1. Meta Developer hesabinda WhatsApp Business uygulamasi ve gonderici phone number ID olusturun.
2. WhatsApp Manager'da `dst_contract_expiry` adli, Turkce ve **dort body parametreli** sablon olusturup Meta onayina gonderin. Ornek body: `Hatirlatma: {{1}} kiracisinin {{2}} reklam alani sozlesmesi {{3}} tarihinde sona eriyor. Bu hatirlatma {{4}}.`
3. Firebase Functions secrets olarak `SMTP_HOST`, `SMTP_PORT`, `SMTP_USER`, `SMTP_PASSWORD`, `MAIL_FROM`, `WHATSAPP_ACCESS_TOKEN`, `WHATSAPP_PHONE_NUMBER_ID`, `WHATSAPP_TEMPLATE_NAME` secret'larini tanimlayin.
4. Uygulamada yonetici WhatsApp numarasini ulke koduyla girin ve **WhatsApp bildirimi** anahtarini acin.

Mesaj, Meta Business API gonderici numarasindan yoneticinin WhatsApp numarasina gider. Alinti/yanit kurallari ve Meta ucretleri hesabiniza tabidir. Token'i Flutter koduna koymayin; Firebase Functions secret olarak saklayin.

Functions'i kurup dagitmak icin `firebase login`, `cd functions`, `npm install`, sonra proje kokunde `firebase deploy --only functions` calistirin. Cloud Scheduler icin Firebase projesinde billing etkin olmalidir.

## Erisim Notu

Firestore Security Rules, istemci uygulamasinin kullandigi yollar icin Firebase Console'da etkin olmalidir. Functions Admin SDK kurallardan bagimsiz calisir.

## Uygulamayi Calistirma

```powershell
flutter pub get
flutter run
```

## Kontroller

```powershell
flutter analyze
flutter test
flutter build web
flutter build windows
flutter build apk --release
```
