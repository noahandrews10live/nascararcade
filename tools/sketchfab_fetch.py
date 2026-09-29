#!/usr/bin/env python3
"""Download the shortlisted Sketchfab models (CC0 / CC BY only) into
assets/models/sketchfab/<name>/ and write CREDITS.md with each author and licence.

Needs a Sketchfab API token (free account: Settings > Password & API) in the
environment variable SKETCHFAB_API_TOKEN.

    python3 tools/sketchfab_fetch.py            # everything on the shortlist
    python3 tools/sketchfab_fetch.py tyres_std  # just some
"""
import io, json, os, sys, urllib.request, zipfile

# name: (uid, what it's for)
SHORTLIST = {
    "tyres_std": ("65cc7bcf581646a3bc42cf31d0580bcb", "racetrack tyre stack (standard): road-course run-off"),
    "tyres_yellow": ("1ff7e7b4c7aa4058ac87420abd45f052", "racetrack tyre stack (yellow-orange): road-course run-off"),
    "start_lights": ("4f3bd911404a4952bedc5c9aa5f5d9e3", "starting lights gantry over the start/finish line"),
    "starting_line": ("ecb35b3e5b424f9dbf54174e6c5907de", "start/finish gantry"),
    "tow_truck": ("568eecbaaff347d5b62c952d591605ac", "tow truck for wrecked cars under caution"),
    "ambulance": ("b78313c16c9d46a7a67643245cf278d2", "ambulance at the infield care centre / on track after a wreck"),
    "barrel": ("36eed80bde5b4346be3c8de19c15a006", "plastic barrels in the paddock and pit road"),
    "fuel_can": ("a20a6b9c97fb4197817e5e1c99756f5e", "fuel can for the pit crews"),
}
ALLOWED = {"cc0", "by"}  # CC0 and CC Attribution only
API = "https://api.sketchfab.com/v3/models/"
OUT = os.path.join(os.path.dirname(__file__), "..", "assets", "models", "sketchfab")


def get(url, token=None):
    req = urllib.request.Request(url, headers={"Authorization": "Token " + token} if token else {})
    with urllib.request.urlopen(req, timeout=120) as r:
        return r.read()


def main():
    token = os.environ.get("SKETCHFAB_API_TOKEN", "")
    if not token:
        sys.exit("Set SKETCHFAB_API_TOKEN (Sketchfab: Settings > Password & API).")
    names = sys.argv[1:] or list(SHORTLIST)
    os.makedirs(OUT, exist_ok=True)
    credits = []
    for name in names:
        uid, use = SHORTLIST[name]
        info = json.loads(get(API + uid))
        lic = (info.get("license") or {}).get("slug", "")
        if lic not in ALLOWED:
            print(f"skip {name}: licence {lic!r} isn't CC0 / CC BY")
            continue
        dl = json.loads(get(API + uid + "/download", token))
        g = dl.get("glb") or dl.get("gltf")
        if not g:
            print(f"skip {name}: no glTF download")
            continue
        data = get(g["url"])
        d = os.path.join(OUT, name)
        os.makedirs(d, exist_ok=True)
        if "glb" in dl:
            open(os.path.join(d, name + ".glb"), "wb").write(data)
        else:
            zipfile.ZipFile(io.BytesIO(data)).extractall(d)
        who = info["user"]["displayName"] or info["user"]["username"]
        credits.append(f"| `{name}/` | [{info['name']}]({info['viewerUrl']}) | {who} | {info['license']['label']} | {use} |")
        print(f"got {name}: {info['name']} by {who} ({lic}), {info.get('faceCount')} faces")
    with open(os.path.join(OUT, "CREDITS.md"), "a") as f:
        if f.tell() == 0:
            f.write("# Models from Sketchfab\n\nEach is CC0 or CC Attribution (credit below).\n\n")
            f.write("| Folder | Model | Author | Licence | Used for |\n|---|---|---|---|---|\n")
        f.write("\n".join(credits) + ("\n" if credits else ""))


if __name__ == "__main__":
    main()
