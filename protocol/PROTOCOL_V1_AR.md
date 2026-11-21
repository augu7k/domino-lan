# Party LAN — بروتوكول الاتصال v1

هذه مواصفة أولية مشتركة للوضع المحلي ووضع الإنترنت. لا تُعدّ بحد ذاتها دليلاً على أن خادم الغرف الحالي يطبقها؛ يجب تنفيذها واختبارها في الخطوات التالية.

## 1. قواعد عامة

- الترميز UTF-8 وJSON.
- كل رسالة تحتوي `protocolVersion: 1`.
- كل أمر من العميل يحتوي `requestId` فريداً لمنع تنفيذ الأمر مرتين.
- `roomId` معرّف داخلي، و`joinCode` رمز قصير للانضمام.
- `playerId` معرّف مؤقت للاعب داخل الغرفة، وليس حساباً دائماً.
- لا تُرسل أسرار الأدوار أو أوراق اللاعبين في أحداث الحالة العامة.
- الخادم/المضيف يتحقق من جميع الأوامر ويولّد النتيجة الرسمية.

## 2. شكل الرسالة

```json
{
  "protocolVersion": 1,
  "type": "room.join",
  "requestId": "client-generated-unique-id",
  "roomId": "internal-room-id",
  "payload": {}
}
```

رسائل الخادم تستخدم الشكل نفسه، ويمكن أن تتضمن `eventId` متزايداً داخل الغرفة لمزامنة الأحداث.

## 3. أحداث الاتصال والغرفة

### أوامر العميل

- `room.create`: إنشاء غرفة وتحديد `gameId` والحد الأقصى.
- `room.join`: الانضمام باستخدام رمز الغرفة واسم العرض.
- `room.leave`: مغادرة الغرفة.
- `player.ready`: تغيير حالة الاستعداد.
- `room.start`: طلب بدء المباراة، ويُقبل من المضيف فقط.
- `session.resume`: استعادة المقعد باستخدام رمز استعادة سري.
- `ping`: فحص الاتصال.

### أحداث الخادم

- `room.created`
- `room.snapshot`
- `player.joined`
- `player.left`
- `player.disconnected`
- `player.reconnected`
- `room.started`
- `room.error`
- `pong`

## 4. أحداث لعبة المافيا

- `mafia.action`: أمر سري من لاعب مخوّل، مثل اختيار هدف أو حماية أو تحقيق.
- `mafia.phase.changed`: انتقال المرحلة.
- `mafia.public.announcement`: إعلان عام لا يكشف معلومات سرية.
- `mafia.vote.cast`: تصويت لاعب.
- `mafia.vote.updated`: ملخص التصويت المسموح بعرضه.
- `mafia.player.eliminated`: إعلان الإقصاء وفق قواعد اللعبة.
- `mafia.private.role`: يرسل إلى اللاعب المعني فقط.
- `mafia.private.result`: نتيجة خاصة ترسل إلى صاحب القدرة فقط.
- `mafia.game.finished`: نتيجة المباراة.

المراحل الأساسية: `lobby`, `night`, `day`, `voting`, `resolution`, `finished`.

## 5. أحداث الدومينو

- `domino.move.play`
- `domino.move.draw` (إذا كانت القواعد/الإعدادات تسمح بالسحب)
- `domino.turn.changed`
- `domino.round.finished`
- `domino.game.finished`

لا تُرسل أحجار يد اللاعب إلى بقية اللاعبين. يستقبل كل لاعب فقط يده الخاصة وحالة الطاولة العامة.

## 6. الأخطاء

تستخدم `room.error` رمزاً ثابتاً ورسالة مناسبة للعرض، مثل:

- `INVALID_ROOM_CODE`
- `ROOM_FULL`
- `PLAYER_NAME_REQUIRED`
- `NOT_ROOM_HOST`
- `NOT_YOUR_TURN`
- `INVALID_ACTION`
- `SESSION_EXPIRED`
- `REQUEST_ALREADY_PROCESSED`
- `PROTOCOL_VERSION_UNSUPPORTED`

## 7. الأمان والموثوقية

1. لا تثق في أي نتيجة أو نقاط يرسلها العميل.
2. تحقق من هوية اللاعب ومقعده وصلاحيته قبل تطبيق الأمر.
3. احتفظ بذاكرة قصيرة لمعرفات `requestId` لمنع التكرار.
4. لا تسجل رموز الاستعادة أو الأدوار السرية في السجلات.
5. افصل بين `publicState` و`privateStateByPlayer`.
6. أرسل `room.snapshot` عند الاتصال أو الاستعادة، ثم الأحداث اللاحقة.
7. أضف `stateVersion` أو `eventId` لاكتشاف الأحداث المفقودة أو القديمة.
8. استخدم TLS/WSS في وضع الإنترنت. في LAN استخدم الشبكة المحلية، مع رمز غرفة عشوائي غير قابل للتخمين بسهولة.

## 8. التوافق

أي تغيير غير متوافق في شكل الرسائل يرفع `protocolVersion`. يجب أن يرفض الخادم النسخ غير المدعومة برسالة خطأ واضحة، لا أن يفسرها بصمت.
