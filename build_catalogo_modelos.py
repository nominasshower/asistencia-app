import json
import urllib.request

SUP_URL = "https://xzwlbrirzfogbqhywtvj.supabase.co"
SUP_KEY = "sb_publishable_tCmUG5g7RZbqPPFD3G4U7w_jLrsu01G"
HEADERS = {"apikey": SUP_KEY, "Authorization": f"Bearer {SUP_KEY}"}

patrones = set()
colores = set()
acabados = set()
medidas_por_patron = {}

page_size = 1000
offset = 0
total = None

while True:
    url = f"{SUP_URL}/rest/v1/vaciados?select=patron,medida,color,acabado&fecha=gte.2026-01-01&order=id.asc"
    req = urllib.request.Request(url, headers={**HEADERS, "Range-Unit": "items", "Range": f"{offset}-{offset+page_size-1}"})
    with urllib.request.urlopen(req) as resp:
        rows = json.loads(resp.read().decode())
        content_range = resp.headers.get("Content-Range", "")
        if "/" in content_range:
            total = content_range.split("/")[-1]

    print(f"  fetched {len(rows)} rows at offset {offset}")
    if not rows:
        break

    for r in rows:
        p, m, col, ac = r.get("patron"), r.get("medida"), r.get("color"), r.get("acabado")
        if p:
            patrones.add(p)
            if m:
                medidas_por_patron.setdefault(p, set()).add(m)
        if col:
            colores.add(col)
        if ac:
            acabados.add(ac)

    offset += page_size
    print(f"offset={offset} total={total} patrones={len(patrones)} colores={len(colores)}")
    if len(rows) < page_size:
        break

catalogo = {
    "patrones": sorted(patrones),
    "colores": sorted(colores),
    "acabados": sorted(acabados),
    "medidas_por_patron": {k: sorted(v) for k, v in medidas_por_patron.items()},
}

out_path = "C:/Users/sistemas/AppData/Local/Temp/claude/D--asistencia-app/73f31e65-5bbd-4a9e-966e-36f03d8f5152/scratchpad/catalogo.json"
with open(out_path, "w", encoding="utf-8") as f:
    json.dump(catalogo, f, ensure_ascii=False, indent=2)

print("DONE")
print("patrones:", len(patrones))
print("colores:", len(colores))
print("acabados:", acabados)
print("saved to", out_path)
