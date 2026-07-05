# بناء APK بالسحابة عبر GitHub Actions (بدون تنصيب أي شي)

سيرفرات GitHub المجانية تبنيلك الـ APK. المشروع جاي جاهز بكلشي:
- `.github/workflows/build-apk.yml` — سكربت البناء
- `debug.keystore` — مفتاح التوقيع (لازم يوصل لجذر الريبو!)
- `export_presets.cfg` — إعدادات تصدير الأندرويد

## الخطوات

### 1. سوّي ريبو جديد (أو استخدم الموجود)
github.com → **New repository** → سمّيه `metal-arena` → **Create repository**

### 2. ارفع ملفات المشروع

**⚠️ أهم نقطتين:**
- ملف `project.godot` و `debug.keystore` لازم يكونون **بجذر الريبو مباشرة** — ترفع *محتويات* المجلد، مو المجلد نفسه
- مجلد `.github` أغلب المتصفحات ما ترفعه بالسحب والإفلات — له حل بالخطوة 3

**الطريقة أ — من المتصفح:**
بصفحة الريبو: **Add file → Upload files** → اسحب كل محتويات مجلد المشروع → **Commit changes**
(إذا الملفات موجودة من قبل، الرفع يستبدلها تلقائياً)

**الطريقة ب — بأوامر git (أضمن، وترفع .github تلقائياً):**
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
افتح بالريبو المسار `.github/workflows/build-apk.yml`:
- **موجود؟** افتحه → ✏️ Edit → تأكد محتواه مطابق للنسخة بأسفل هالملف (أو الصقها فوقه) → Commit
- **مو موجود؟** Add file → **Create new file** → اسم الملف حرفياً: `.github/workflows/build-apk.yml` → الصق النسخة من أسفل → Commit

### 4. شغّل البناء ونزّل الـ APK
- تبويب **Actions** → البناء يبلش تلقائياً مع كل commit، أو اضغط **Run workflow**
- انتظر ~5-8 دقايق لحد ✅
- افتح الـ run → قسم **Artifacts** → نزّل **metal-arena-apk** → فك الـ zip → داخله `metal-arena.apk`
- انقله لموبايلك ونصّبه (فعّل "تثبيت من مصادر غير معروفة")

## شلون يشتغل التوقيع (حتى تفهم الصورة)

الـ APK لازم يكون موقّع رقمياً وإلا الأندرويد يرفض ينصّبه. ملف `debug.keystore` المرفق هو مفتاح توقيع بالمواصفات القياسية للتطوير (alias: `androiddebugkey` / كلمة السر: `android`). الـ workflow يمرره للبناء بمسار مطلق عن طريق متغيرات البيئة الرسمية مال گودو:

```
GODOT_ANDROID_KEYSTORE_DEBUG_PATH / _USER / _PASSWORD
```

**ملاحظة:** لا تكتب بـ `export_presets.cfg` مسار keystore يبدي بـ `res://` — أداة التوقيع apksigner أداة خارجية ما تفهم مسارات گودو وراح يفشل التصدير. الـ workflow أصلاً محصّن: أي سطور keystore بالـ preset يصلّح مسارها تلقائياً وقت البناء.

هالمفتاح للتجربة والتوزيع بين الأصدقاء فقط. للنشر بالمتاجر لاحقاً نسوي **release keystore** خاص — وذاك **ما ينرفع للريبو أبداً**.

## ملاحظات

- **تطابق الإصدارات:** البناء مثبّت على Godot **4.3**. إذا فتحت المشروع محلياً بنسخة أحدث وحفظت، غيّر `GODOT_VERSION` بالـ workflow لنفس نسختك.
- كل push = APK جديد تلقائياً: تعدّل → ترفع → تنزّل.
- صلاحية Internet مفعّلة بإعدادات التصدير، جاهزة لمرحلة الملتيبلاير LAN.
- إذا فشل البناء: افتح الـ run → **android** → الخطوة الحمرا تنفتح ويطلع اللوگ مفصّل (التصدير شغال بوضع verbose).

## النسخة الكاملة من build-apk.yml

```yaml
name: Build Android APK

on:
  push:
    branches: [ main ]
  workflow_dispatch:

env:
  GODOT_VERSION: "4.3"

jobs:
  android:
    runs-on: ubuntu-latest
    steps:
      - name: Checkout project
        uses: actions/checkout@v4

      - name: Set up Java 17
        uses: actions/setup-java@v4
        with:
          distribution: temurin
          java-version: "17"

      - name: Download Godot and export templates
        run: |
          wget -q "https://github.com/godotengine/godot/releases/download/${GODOT_VERSION}-stable/Godot_v${GODOT_VERSION}-stable_linux.x86_64.zip"
          wget -q "https://github.com/godotengine/godot/releases/download/${GODOT_VERSION}-stable/Godot_v${GODOT_VERSION}-stable_export_templates.tpz"
          unzip -q "Godot_v${GODOT_VERSION}-stable_linux.x86_64.zip"
          chmod +x "Godot_v${GODOT_VERSION}-stable_linux.x86_64"
          TEMPLATE_DIR="$HOME/.local/share/godot/export_templates/${GODOT_VERSION}.stable"
          mkdir -p "$TEMPLATE_DIR"
          unzip -q "Godot_v${GODOT_VERSION}-stable_export_templates.tpz"
          mv templates/* "$TEMPLATE_DIR/"

      - name: Configure Godot editor settings
        run: |
          MINOR="$(echo "$GODOT_VERSION" | cut -d. -f1,2)"
          mkdir -p "$HOME/.config/godot"
          cat > "$HOME/.config/godot/editor_settings-4.tres" <<EOF
          [gd_resource type="EditorSettings" format=3]

          [resource]
          export/android/android_sdk_path = "${ANDROID_HOME}"
          export/android/java_sdk_path = "${JAVA_HOME}"
          EOF
          cp "$HOME/.config/godot/editor_settings-4.tres" "$HOME/.config/godot/editor_settings-${MINOR}.tres"

      - name: Check keystore exists in repo
        run: |
          if [ ! -f debug.keystore ]; then
            echo "::error::debug.keystore is missing from the repository root. Upload it next to project.godot first."
            exit 1
          fi

      - name: Point export preset at the keystore
        run: |
          sed -i "s|^keystore/debug=.*|keystore/debug=\"${GITHUB_WORKSPACE}/debug.keystore\"|" export_presets.cfg
          sed -i 's|^keystore/debug_user=.*|keystore/debug_user="androiddebugkey"|' export_presets.cfg
          sed -i 's|^keystore/debug_password=.*|keystore/debug_password="android"|' export_presets.cfg
          echo "--- keystore lines now: ---"
          grep "^keystore/" export_presets.cfg || echo "(no keystore lines in preset - env vars will be used)"

      - name: Import project resources
        run: |
          ./Godot_v${GODOT_VERSION}-stable_linux.x86_64 --headless --path . --import || true

      - name: Export debug APK
        env:
          GODOT_ANDROID_KEYSTORE_DEBUG_PATH: ${{ github.workspace }}/debug.keystore
          GODOT_ANDROID_KEYSTORE_DEBUG_USER: androiddebugkey
          GODOT_ANDROID_KEYSTORE_DEBUG_PASSWORD: android
        run: |
          mkdir -p build
          ./Godot_v${GODOT_VERSION}-stable_linux.x86_64 --headless --verbose --path . --export-debug "Android" build/metal-arena.apk
          test -f build/metal-arena.apk
          ls -la build/

      - name: Upload APK
        uses: actions/upload-artifact@v4
        with:
          name: metal-arena-apk
          path: build/metal-arena.apk
```
