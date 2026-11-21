# إعداد منصة Android

أنشئ منصة Android من Flutter SDK بالأمر:

```bash
flutter create --platforms=android .
```

ثم راجع `android/app/src/main/AndroidManifest.xml` وأضف إذن الإنترنت للشبكة المحلية:

```xml
<uses-permission android:name="android.permission.INTERNET" />
<uses-permission android:name="android.permission.ACCESS_NETWORK_STATE" />
<uses-permission android:name="android.permission.ACCESS_WIFI_STATE" />
```

قد تتطلب بعض نسخ Android أو أساليب اكتشاف الشبكة أذونات إضافية. لا تطلب أذونات الموقع أو الأجهزة القريبة إلا إذا استُخدمت واجهة نظام تستلزمها فعلاً.

يجب السماح باتصال HTTP/WebSocket غير المشفر إلى عنوان محلي داخل شبكة Hotspot فقط عند استخدام `ws://`، مع عدم فتح هذا الاستثناء لاتصالات إنترنت عامة. يمكن لاحقاً استخدام TLS محلي إذا ظهرت حاجة حقيقية لذلك.

لا تضع مفاتيح توقيع APK أو كلمات مرور أو ملفات keystore في المستودع.
