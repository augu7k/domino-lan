# إعداد وبناء Android

يمكن تجهيز ملفات Android على جهاز التطوير باستخدام:

```bash
flutter create --platforms=android --org com.domino.lan .
flutter pub get
flutter test
flutter run
```

## أذونات الشبكة

يحتاج التطبيق إلى أذونات الإنترنت وحالة الشبكة وقراءة حالة Wi-Fi لاستخدام WebSocket وUDP على الشبكة المحلية. يضيفها مسار البناء الآلي في GitHub Actions إلى ملف Manifest.

تسمح نسخة التطوير باتصالات HTTP غير المشفرة لأن WebSocket المحلي يستخدم `ws://` داخل شبكة نقطة الاتصال. لا تستخدم هذا الإعداد لإرسال بيانات حساسة عبر شبكات عامة. قبل إصدار متجر أو استخدام شبكات غير موثوقة، ينبغي تضييق سياسة cleartext أو اعتماد تشفير ومصادقة مناسبة.

## بناء APK عبر GitHub Actions

كل تحديث على فرع `main` يشغّل:
1. تنسيق Dart.
2. تحليل Flutter.
3. اختبارات المحرك.
4. إنشاء ملفات Android.
5. بناء APK تجريبي.
6. رفع APK كـ Artifact باسم `domino-lan-debug-apk`.

من صفحة Actions افتح آخر تشغيل ناجح، ثم نزّل Artifact. رابط Artifact مؤقت ويحتفظ به GitHub لمدة 14 يوماً.

هذا APK تجريبي Debug وليس إصداراً نهائياً موقعاً. لا ترفع ملفات keystore أو كلمات المرور إلى المستودع.
