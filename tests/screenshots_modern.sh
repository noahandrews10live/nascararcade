#!/bin/sh
# Renders screenshots with the Forward+ (modern) renderer on a headless Linux box.
# Needs xvfb and a Vulkan driver (mesa lavapipe works). Usage: OUT=/tmp/shots tests/screenshots_modern.sh
exec xvfb-run -a -s "-screen 0 1280x1024x24" "${GODOT:-godot}" --rendering-driver vulkan --fixed-fps 60 --resolution 1280x960 --path "$(dirname "$0")/.." -s tests/screenshots.gd
