#!/usr/bin/env bash
# Resizes build/icon-*.png (from render_icons_test.dart) into the Android mipmaps and the iOS AppIcon set. macOS (`sips`).
set -euo pipefail
cd "$(dirname "$0")/.."
for pair in mdpi:48 hdpi:72 xhdpi:96 xxhdpi:144 xxxhdpi:192; do
  d="android/app/src/main/res/mipmap-${pair%%:*}"; [ -d "$d" ] || continue
  sips -z "${pair##*:}" "${pair##*:}" build/icon-1024.png --out "$d/ic_launcher.png" >/dev/null
done
set_dir=ios/Runner/Assets.xcassets/AppIcon.appiconset
python3 - "$set_dir" <<'PY'
import json, subprocess, sys
d = sys.argv[1]
for img in json.load(open(f"{d}/Contents.json"))["images"]:
    w = float(img["size"].split("x")[0]) * int(img["scale"].rstrip("x"))
    subprocess.run(["sips", "-z", str(int(w)), str(int(w)), "build/icon-ios-1024.png", "--out", f"{d}/{img['filename']}"], check=True, stdout=subprocess.DEVNULL)
PY
echo "icons applied"
