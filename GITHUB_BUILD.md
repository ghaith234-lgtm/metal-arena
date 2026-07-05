# بناء APK بالسحابة عبر GitHub Actions (بدون تنصيب أي شي)

سيرفرات GitHub المجانية تبنيلك الـ APK. المشروع جاي جاهز بكلشي:
- `.github/workflows/build-apk.yml` — سكربت البناء (يشتغل داخل حاوية جاهزة بيها گودو 4.3 + القوالب + Java + Android SDK)
- `debug.keystore` — مفتاح التوقيع (لازم يوصل لجذر الريبو!)
- `export_presets.cfg` — إعدادات تصدير الأندرويد
- `project.godot` — بيه إعداد ضغط النسجات للأندرويد مفعّل (ETC2/ASTC) — **لا تشيله**، بدونه التصدير يفشل بصمت

## الخطوات

### 1. سوّي ريبو جديد (أو استخدم الموجود)
github.com → **New repository** → سمّيه `metal-arena` → **Create repository**

### 2. ارفع ملفات المشروع

**⚠️ أهم نقطة:** `project.godot` و `debug.keystore` لازم يكونون **بجذر الريبو مباشرة** — ترفع *محتويات* المجلد، مو المجلد نفسه.

**من المتصفح:** بصفحة الريبو: **Add file → Upload files** → اسحب كل محتويات مجلد المشروع → **Commit changes**. (الملفات الموجودة تنستبدل تلقائياً.)

**أو بأوامر git:**
```bash
cd metal-arena
git init
git add -A
git commit -m "v1"
git branch -M main
git remote add origin https://github.com/اسم_حسابك/metal-arena.git
git push -u origin main
```

### 3. تأكد من ملف الـ workflow
المتصفح أحياناً ما يرفع مجلد `.github` بالسحب والإفلات. افتح بالريبو المسار `.github/workflows/build-apk.yml`:
- **موجود ومحتواه مطابق للنسخة بأسفل هالملف؟** خلاص، لا تلمسه.
- **مو موجود؟** Add file → **Create new file** → اسم الملف حرفياً: `.github/workflows/build-apk.yml` → الصق النسخة من أسفل → Commit.

### 4. شغّل البناء ونزّل الـ APK
- تبويب **Actions** → البناء يبلش تلقائياً مع كل commit، أو اضغط **Run workflow**
- أول مرة ياخذ ~7-10 دقايق (يسحب الحاوية)، بعدين أسرع
- افتح الـ run بعد ✅ → قسم **Artifacts** → نزّل **metal-arena-apk** → فك الـ zip → داخله `metal-arena.apk`
- انقله لموبايلك ونصّبه (فعّل "تثبيت من مصادر غير معروفة")

## شلون يشتغل التوقيع

الـ APK لازم يكون موقّع وإلا الأندرويد يرفضه. ملف `debug.keystore` المرفق مفتاح توقيع بالمواصفات القياسية للتطوير (alias: `androiddebugkey` / كلمة السر: `android`)، والـ workflow يمرره بمسار مطلق عبر متغيرات البيئة الرسمية مال گودو للـ CI:

```
GODOT_ANDROID_KEYSTORE_DEBUG_PATH / _USER / _PASSWORD
```

**تحذير:** لا تكتب بـ `export_presets.cfg` مسار keystore يبدي بـ `res://` — أداة apksigner خارجية ما تفهم مسارات گودو ويفشل التوقيع.

هالمفتاح للتجربة والتوزيع بين الأصدقاء. للنشر بالمتاجر نسوي **release keystore** خاص — وذاك **ما ينرفع للريبو أبداً**.

## ملاحظات

- **الإصدار مثبّت** عبر وسم الحاوية `barichello/godot-ci:4.3`. إذا اشتغلت محلياً بنسخة گودو أحدث وحفظت المشروع، غيّر الوسم بالـ workflow لنفس نسختك (مثلاً `:4.4`).
- كل push = APK جديد تلقائياً.
- صلاحية Internet مفعّلة بإعدادات التصدير، جاهزة للملتيبلاير LAN.
- إذا فشل البناء: افتح الـ run → **android** → الخطوة الحمرا، والتصدير شغال بوضع verbose فاللوگ مفصّل.

## النسخة الكاملة من build-apk.yml

```yaml
name: Build Android APK

on:
  push:
    branches: [ main ]
  workflow_dispatch:

jobs:
  android:
    runs-on: ubuntu-latest
    container:
      image: barichello/godot-ci:4.3
    steps:
      - name: Checkout project
        uses: actions/checkout@v4

      - name: Setup Godot templates and editor settings
        run: |
          mkdir -p ~/.local/share/godot/export_templates
          mkdir -p ~/.config
          mv /root/.config/godot ~/.config/godot || true
          mv /root/.local/share/godot/export_templates/4.3.stable ~/.local/share/godot/export_templates/4.3.stable || true
          grep -q "export/android/java_sdk_path" ~/.config/godot/editor_settings-4.3.tres || echo 'export/android/java_sdk_path = "/usr/lib/jvm/java-17-openjdk-amd64"' >> ~/.config/godot/editor_settings-4.3.tres
          echo "--- editor settings android/java lines: ---"
          grep -E "export/android" ~/.config/godot/editor_settings-4.3.tres || true

      - name: Check keystore exists in repo
        run: |
          if [ ! -f debug.keystore ]; then
            echo "::error::debug.keystore is missing from the repository root. Upload it next to project.godot first."
            exit 1
          fi

      - name: Import project resources
        run: |
          godot --headless --path . --import || true

      - name: Export debug APK
        env:
          GODOT_ANDROID_KEYSTORE_DEBUG_PATH: ${{ github.workspace }}/debug.keystore
          GODOT_ANDROID_KEYSTORE_DEBUG_USER: androiddebugkey
          GODOT_ANDROID_KEYSTORE_DEBUG_PASSWORD: android
        run: |
          mkdir -p build
          godot --headless --verbose --path . --export-debug "Android" build/metal-arena.apk
          test -f build/metal-arena.apk
          ls -la build/

      - name: Upload APK
        uses: actions/upload-artifact@v4
        with:
          name: metal-arena-apk
          path: build/metal-arena.apk
```
