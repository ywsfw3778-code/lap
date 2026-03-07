# نشر الموقع وتحديثه تلقائيا

## الفكرة
- الموقع ثابت (HTML فقط)، فأنسب طريقة هي GitHub Pages.
- كل مرة تعدل ملفات الموقع وتعمل `push` على فرع `main`، التعديل ينزل تلقائيا على اللينك.

## المطلوب مرة واحدة
1. نزّل Git for Windows: https://git-scm.com/download/win
2. اعمل حساب GitHub (لو مش موجود).
3. اعمل Repository جديد (مثلا: `messenger-site`).

## رفع المشروع لأول مرة
شغل PowerShell داخل نفس المجلد ثم نفّذ:

```powershell
git init
git branch -M main
git add .
git commit -m "first deploy"
git remote add origin https://github.com/<YOUR_USERNAME>/messenger-site.git
git push -u origin main
```

## تفعيل GitHub Pages
1. افتح الـ repo على GitHub.
2. ادخل Settings > Pages.
3. Source اختَر: `GitHub Actions`.
4. انتظر أول تشغيل workflow (حوالي 1-2 دقيقة).

بعدها الموقع هيكون متاح على:
`https://<YOUR_USERNAME>.github.io/messenger-site/`

## التحديث التلقائي بعد أي تعديل
كل مرة تعدل الملفات:

```powershell
git add .
git commit -m "update"
git push
```

أول ما `push` يخلص، GitHub ينشر النسخة الجديدة تلقائيا.

## ملاحظة مهمة
- "على طول" يعني بعد الـ push مباشرة (غالبا خلال دقيقة).
- بدون Git/GitHub لا يوجد نشر تلقائي مستمر على الإنترنت.
