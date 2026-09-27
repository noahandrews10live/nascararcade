#!/bin/sh
# Sets up everything Godot needs to export the Android APK, without the full
# Android SDK: a stand-in `apksigner` (ApkSignerCli.java, on the apksig library
# from Maven Central), a minimal SDK folder, a debug keystore, and the editor
# settings pointing at them.
#   sh native/android/setup.sh [work_dir]    then
#   godot --headless --export-debug Android build/android/SpeedwayThunder.apk
set -e
HERE=$(cd "$(dirname "$0")" && pwd)
W=${1:-$HOME/.cache/speedway-android}
mkdir -p "$W/sdk/build-tools/34.0.0" "$W/sdk/platform-tools" "$W/sdk/platforms/android-34"
[ -f "$W/apksig.jar" ] || curl -sfo "$W/apksig.jar" https://repo1.maven.org/maven2/com/android/tools/build/apksig/2.3.0/apksig-2.3.0.jar
javac -d "$W" -cp "$W/apksig.jar" "$HERE/ApkSignerCli.java"
cat > "$W/sdk/build-tools/34.0.0/apksigner" <<SH
#!/bin/sh
exec java --add-exports java.base/sun.security.x509=ALL-UNNAMED --add-exports java.base/sun.security.pkcs=ALL-UNNAMED --add-exports java.base/sun.security.util=ALL-UNNAMED -cp "$W/apksig.jar:$W" ApkSignerCli "\$@"
SH
printf '#!/bin/sh\necho "Android Debug Bridge (stand-in)"\n' > "$W/sdk/platform-tools/adb"
chmod +x "$W/sdk/build-tools/34.0.0/apksigner" "$W/sdk/platform-tools/adb"
# The project's debug key (committed, password "android"), so every debug build
# installs over the last one. Release builds for the Play Store need your own key.
cp "$HERE/debug.keystore" "$W/debug.keystore"
# Point Godot's editor settings at them.
for F in "$HOME"/.config/godot/editor_settings-4*.tres; do
	[ -f "$F" ] || continue
	python3 - "$F" "$W" <<'PY'
import re, sys
p, w = sys.argv[1], sys.argv[2]
s = open(p).read()
vals = {"export/android/android_sdk_path": w + "/sdk", "export/android/debug_keystore": w + "/debug.keystore",
        "export/android/debug_keystore_user": "androiddebugkey", "export/android/debug_keystore_pass": "android"}
for k, v in vals.items():
    line = '%s = "%s"' % (k, v)
    if re.search(r'^' + re.escape(k) + r' = .*$', s, re.M):
        s = re.sub(r'^' + re.escape(k) + r' = .*$', line, s, flags=re.M)
    else:
        s = s.replace('[resource]\n', '[resource]\n' + line + '\n', 1)
open(p, 'w').write(s)
PY
done
echo "Android export ready: SDK stand-in in $W/sdk"
