#!/usr/bin/env python3
"""Sucht je Material bis zu 3 Bilder auf Wikimedia Commons, lädt Vorschauen, baut Kontaktbogen. Eingabe: commons-suche.json {mat: query}."""
import json, sys, time, urllib.parse, urllib.request, os
from PIL import Image, ImageDraw
src, out = sys.argv[1], sys.argv[2]
os.makedirs(out, exist_ok=True)
UA = "fambach-taxmod/1.0 (https://www.fambach.net)"
def get(u):
    return urllib.request.urlopen(urllib.request.Request(u, headers={"User-Agent": UA}), timeout=60).read()
res = {}
for mat, q in json.load(open(src)).items():
    u = ("https://commons.wikimedia.org/w/api.php?action=query&generator=search&gsrnamespace=6&gsrlimit=6&gsrsearch="
         + urllib.parse.quote(q) + "&prop=imageinfo&iiprop=url%7Csize%7Cextmetadata&iiurlwidth=1200&format=json")
    try:
        d = json.loads(get(u))
    except Exception as e:
        print(mat, "fehler", e, flush=True); time.sleep(10); continue
    c = []
    for p in sorted(d.get("query", {}).get("pages", {}).values(), key=lambda p: p.get("index", 0)):
        if not p["title"].lower().endswith((".jpg", ".jpeg", ".png")): continue
        ii = p["imageinfo"][0]; em = ii["extmetadata"]
        c.append({"file": p["title"][5:], "thumb": ii.get("thumburl"), "page": ii["descriptionurl"],
                  "lic": em.get("LicenseShortName", {}).get("value", "?"),
                  "artist": em.get("Artist", {}).get("value", "")})
        if len(c) == 3: break
    for i, x in enumerate(c):
        try:
            open(f"{out}/{mat}_{i}.jpg", "wb").write(get(x["thumb"])); time.sleep(1)
        except Exception as e:
            x["fehler"] = str(e)
    res[mat] = {"q": q, "kandidaten": c}
    json.dump(res, open(f"{out}/kandidaten.json", "w"), indent=1, ensure_ascii=False)
    print(mat, len(c), flush=True); time.sleep(3)
mats = list(res)
tw = 260; sheet = Image.new("RGB", (3 * tw + 200, len(mats) * (tw // 2 + 20)), "white"); dr = ImageDraw.Draw(sheet)
for r, mat in enumerate(mats):
    y = r * (tw // 2 + 20); dr.text((2, y + 2), f"{mat}\n{res[mat]['q'][:28]}", fill="black")
    for i in range(3):
        f = f"{out}/{mat}_{i}.jpg"
        if os.path.exists(f):
            try:
                im = Image.open(f).convert("RGB"); im.thumbnail((tw, tw // 2)); sheet.paste(im, (200 + i * tw, y))
            except Exception: pass
sheet.save(f"{out}/bogen.jpg", quality=70)
print("fertig")
