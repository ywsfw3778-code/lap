# نشر الموقع على Google (Firebase) + تحديث تلقائي

## النتيجة
- الموقع يُنشر على Google عبر Firebase Hosting.
- أي تعديل تعمل له `git push` على فرع `main` ينزل تلقائيا على الموقع.

## 1) تجهيز Firebase (مرة واحدة)
1. افتح Firebase Console: https://console.firebase.google.com
2. اعمل Project جديد أو استخدم Project موجود.
3. ادخل Hosting ثم اضغط Get started.
4. انسخ `Project ID` (مثال: `my-messenger-web`).

## 2) إضافة Secrets في GitHub (مرة واحدة)
في GitHub repo > Settings > Secrets and variables > Actions:

1. أضف Secret باسم `FIREBASE_PROJECT_ID` والقيمة = Project ID.
2. أضف Secret باسم `FIREBASE_SERVICE_ACCOUNT`:
   - من Google Cloud Console > IAM & Admin > Service Accounts.
   - اعمل Service Account جديد (أو استخدم واحد موجود).
   - امنحه دور: `Firebase Hosting Admin` (وممكن `Firebase Admin` لو محتاج).
   - أنشئ JSON Key.
   - افتح ملف JSON وانسخ محتواه بالكامل وضعه كقيمة Secret `FIREBASE_SERVICE_ACCOUNT`.

## 3) تشغيل أول نشر
- اعمل push على `main`.
- افتح تبويب Actions في GitHub وتابع Workflow: `Deploy to Firebase Hosting`.
- بعد النجاح، هتلاقي رابط الموقع في Firebase Hosting.

## 4) التحديث التلقائي بعد أي تعديل
استخدم نفس أوامرك العادية:

```powershell
git add .
git commit -m "update"
git push
```

أي `push` جديد على `main` = نشر تلقائي مباشر.

## ملاحظات مهمة
- قبل نشر أي نسخة: شغّل `FULL_DATABASE_SETUP.sql` ثم
  `supabase_friend_requests_rebuild.sql` ثم `SECURITY_HARDENING.sql` داخل
  Supabase SQL Editor. الملف الأخير يقفل صلاحيات SQL وStorage بعد أي سكربت
  إعداد قديم، لذلك يجب تشغيله أخيرا.
- لا تضع `service_role` أو مفاتيح Supabase السرية أو ملفات `.env` داخل GitHub.
- عندك حاليا Workflow قديم لـ GitHub Pages في `.github/workflows/deploy-pages.yml`.
- لو هتعتمد Firebase فقط، يفضل تعطّل/تحذف Workflow Pages لتفادي نشر مزدوج.
