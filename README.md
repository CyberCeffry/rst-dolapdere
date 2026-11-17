# RST Dolapdere Sozlesme Takip

Reklam alanlarini, kiracilari ve kira sozlesmelerini yonetir. Kayitlar SharedPreferences ile cihazda onbelleklenir ve Firebase Firestore ile es zamanli calisir.

Firestore koleksiyonlari `workspaces/rst_dolapdere/customers`, `adSpaces`, `contracts` ve `settings/reminders` yollarindadir. Android baglantisi `android/app/google-services.json` ile eslesir. Ilk acilista cihazdaki yerel kayitlar Firestore'a birlestirilir; Firestore degisiklikleri cihaz onbellegine akar. Windows Firestore plugini desteklenmediginden Windows'ta SharedPreferences kullanilir.

## Cihaz Bildirimleri

**Ayarlar > Bildirim günleri** sözlesme bitisinden kac gun once cihaz hatirlatmasi gonderilecegini belirler. **Çalışma günleri** seciminde isaretli olmayan bir gune denk gelen hatirlatma, sonraki isaretli gune tasinir. Bildirim metnindeki kalan gun sayisi ertelenmis gonderim tarihine gore hesaplanir; ayni sozlesmenin birden cok hatirlatmasi ayni is gunune denk gelirse tek bildirime indirilir. Varsayilan calisma gunleri Pazartesi-Cuma'dir ve en az bir gun secili kalmalidir. **Bildirim gönderme saati** cihaz bildirim saatini ayarlar.

Hatirlatma bildirimi **Ertele...** eylemi, uygulamayi acip 5 dakika, 10 dakika, 30 dakika, 1 saat, 2 saat, 1 gun veya 2 gun sonrasi icin erteleme secenegi sunar. **Sözleşmeyi aç** bildirimi konu olan sozlesmeye, **Yaklaşanları aç** ise yaklasan sozlesmelere gider. Windows'ta bildirim uzun gosterim suresi ister; banner suresi iOS, Android ve Windows tarafindan yonetilir. Uygulama isletim sisteminin otomatik kapatma davranisini tum platformlarda engelleyemez; bildirim merkezi/notification center'da kalicilik sistem ayarlarina baglidir.

Yaklaşan sözleşmeler ekranında **Kiracıya WhatsApp gönder** eylemi yalnızca admin rolüne görünür ve kayıtlı kiracı numarasıyla WhatsApp'ta mesaj taslağı açar. Mesajı göndermek için WhatsApp içinde ayrıca onay vermek gerekir. Uygulama otomatik WhatsApp ve e-posta hatırlatması göndermez.

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
  "notificationPreferences": { "inApp": true, "push": true },
  "assignedContractIds": [],
  "assignedCustomerIds": [],
  "assignedAdSpaceIds": []
}
```

`workspaces/rst_dolapdere/usernameIndex/yonetici` dokumanini `{ "uid": "..." }` olarak ekleyin. Ilk admin olusturma/yetki atama uygulamadan yapilmaz; boylece istemci kendisini admin yapamaz. Sonraki kullanicilar Ayarlar > Kullanıcılar ve roller panelinden eklenir. Sorumlulara modullere erisim izni verilir ve goruntuleyecekleri sozlesmelere yonetici tarafindan sorumlu atanir. Sorumlu yeni sozlesme eklediginde veya uzattiginda pozitif birim fiyat girmeli; islem yonetici onayina kadar sozlesmeye uygulanmaz. Sorumlular atanmis sozlesmeleri etkin/pasif yapabilir, silemez.

Push icin Firebase Cloud Messaging platform kurulumunu tamamlayin: iOS'ta APNs anahtari, web'de Firebase Web Push VAPID anahtari gereklidir. Android icin Firebase Messaging konfigurasyonunun `google-services.json` ile ayni projeye ait oldugunu kontrol edin.

Guvenlik kurallarini yayinlamadan once mevcut verilerinizin `workspaces/rst_dolapdere` altinda oldugunu dogrulayin. Eski bir kurulumda belgeler `workspaces/dst_dolapdere` altindaysa, yayin oncesi Console veya guvenilir bir Admin SDK migration ile `rst_dolapdere` altina tasi. Supervisor hesaplari sadece sorumlu atandigi sozlesme, kiraci ve reklam alanlarini okuyabilir; sozlesme yazma/onay islemleri callable Functions tarafinda yetkilendirilir.

Functions'i kurup dagitmak icin `firebase login`, `cd functions`, `npm install`, sonra proje kokunde `firebase deploy --only functions` calistirin. Onceki surumde `sendContractReminders` zamanlanmis islevi yayinlandiysa, kaldirmak icin `firebase functions:delete sendContractReminders --region=europe-west1` calistirin.

## Erisim Notu

Uygulama kullanici girisi olmadan acilir. `firestore.rules`, `workspaces/rst_dolapdere` altindaki tum belgelere kimlik dogrulamasi olmadan okuma/yazma izni verir. Bu veriler proje kimligini bilen herkes tarafindan okunabilir ve degistirilebilir; yalnizca herkese acik kullanimi kabul ediyorsaniz yayinlayin.

Kurallari uygulamanin kullandigi Firebase projesinde etkinlestirmek icin proje kokunde `firebase deploy --only firestore:rules --project deresozlesmetakip` calistirin.

Windows masaustu hatirlatmalari Ayarlar ekraninda varsayilan olarak kapali gelir. Acildiginda uygulama Windows **Ayarlar > Sistem > Bildirimler** sayfasini acar ve bir test bildirimi gosterir; Windows'ta masaustu uygulamalari icin Chrome'daki gibi bir izin popup'i API'si yoktur, bildirim izni isletim sisteminden verilir. RST Dolapdere icin bildirimleri ve basliklari etkinlestirin. Uygulama Windows baslangic menusune AppUserModelID iceren bir kisayol kaydeder; Windows toast bildirimleri icin bu gereklidir.

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
