#!/usr/bin/env python3
"""Builds the single-page version of web/shell.html used where the game is hosted
as a page with size-limited files (the claude.ai artifact): the engine is split
into three parts, the game data ships as gamedata.pck.wasm, and the host supplies
the <html>/<head>/<body> skeleton.

    python3 web/make_artifact_page.py build/web OUT_DIR

reads the plain "Web" export in build/web and writes OUT_DIR/speedway-thunder.html
plus the engine parts, the game data and the loader scripts.
"""
import json
import os
import re
import shutil
import sys

PART = 13_200_000  # bytes per engine part (the host caps each file at 15 MB)

SHIM = """<script>
  // The engine is published in parts (the host caps file size), so rebuild
  // index.wasm on the fly whenever Godot's loader asks for it.
  (function () {
    const parts = %s;
    const realFetch = window.fetch.bind(window);
    window.fetch = function (input, init) {
      const url = typeof input === "string" ? input : (input && input.url) || "";
      if (/(^|\\/)index\\.wasm(\\?|$)/.test(url)) {
        return Promise.all(parts.map(function (p) {
          return realFetch(p).then(function (r) {
            if (!r.ok) throw new Error("Could not load " + p + " (HTTP " + r.status + ")");
            return r.blob();
          });
        })).then(function (blobs) {
          const blob = new Blob(blobs, { type: "application/wasm" });
          return new Response(blob, { status: 200, headers: { "Content-Type": "application/wasm", "Content-Length": String(blob.size) } });
        });
      }
      // The host only serves web file types, so the game data ships under a .wasm name.
      if (/(^|\\/)index\\.pck(\\?|$)/.test(url)) {
        return realFetch("gamedata.pck.wasm").then(function (r) {
          if (!r.ok) throw new Error("Could not load game data (HTTP " + r.status + ")");
          return r.blob();
        }).then(function (blob) {
          return new Response(blob, { status: 200, headers: { "Content-Type": "application/octet-stream", "Content-Length": String(blob.size) } });
        });
      }
      return realFetch(input, init);
    };
  })();
</script>"""


def main() -> None:
    src, out = sys.argv[1], sys.argv[2]
    here = os.path.dirname(os.path.abspath(__file__))
    shell = open(os.path.join(here, "shell.html"), encoding="utf-8").read()
    os.makedirs(out, exist_ok=True)
    # Engine parts.
    wasm = open(os.path.join(src, "index.wasm"), "rb").read()
    parts = []
    for i in range(0, len(wasm), PART):
        name = "engine.part%d.wasm" % (i // PART)
        open(os.path.join(out, name), "wb").write(wasm[i:i + PART])
        parts.append(name)
    shutil.copy(os.path.join(src, "index.pck"), os.path.join(out, "gamedata.pck.wasm"))
    for f in ("index.js", "index.audio.worklet.js", "index.audio.position.worklet.js"):
        if os.path.exists(os.path.join(src, f)):
            shutil.copy(os.path.join(src, f), os.path.join(out, f))
    config = {
        "args": [], "canvasResizePolicy": 2, "ensureCrossOriginIsolationHeaders": False,
        "executable": "index", "experimentalVK": False, "focusCanvas": True, "gdextensionLibs": [],
        "fileSizes": {"index.pck": os.path.getsize(os.path.join(src, "index.pck")), "index.wasm": len(wasm)},
    }
    page = shell
    # The host provides the document skeleton, charset and viewport.
    page = re.sub(r"^.*?(<title>)", r"\1", page, count=1, flags=re.S)
    page = page.replace("$GODOT_HEAD_INCLUDE\n", "")
    page = re.sub(r'<link rel="apple-touch-icon"[^\n]*\n', "", page)
    page = page.replace("</head>\n<body>\n", "")
    page = page.replace("</body>\n</html>\n", "")
    page = page.replace('<script src="$GODOT_URL"></script>', SHIM % json.dumps(parts) + '\n<script src="index.js"></script>')
    page = page.replace("$GODOT_CONFIG", json.dumps(config))
    assert "$GODOT" not in page, "unfilled placeholder"
    open(os.path.join(out, "speedway-thunder.html"), "w", encoding="utf-8").write(page)
    print("wrote", os.path.join(out, "speedway-thunder.html"), "with", len(parts), "engine parts")


if __name__ == "__main__":
    main()
