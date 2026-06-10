"""
verificar_supabase.py — Verificación post-fix de paginación
Corre:  python verificar_supabase.py
Confirma que el fix de paginación en produccion.html / consumos.html
trae TODOS los registros y que vaciados tiene columna sku.
"""
import urllib.request, json

KEY = "sb_publishable_tCmUG5g7RZbqPPFD3G4U7w_jLrsu01G"
URL = "https://xzwlbrirzfogbqhywtvj.supabase.co"

def req(path, rng=None, count=False):
    h = {"apikey": KEY, "Authorization": "Bearer " + KEY}
    if rng:   h.update({"Range-Unit": "items", "Range": rng})
    if count: h["Prefer"] = "count=exact"
    r = urllib.request.urlopen(urllib.request.Request(URL + path, headers=h), timeout=60)
    return r, json.loads(r.read())

# 1) Tope real por request (request "viejo" estilo pre-fix)
r, data = req("/rest/v1/vaciados?select=fecha&limit=50000&order=fecha.desc", rng="0-49999")
print(f"1) Filas por request unico : {len(data)}  (si es 1000 → el tope existia, fix necesario)")

# 2) Columna sku en vaciados
r, d2 = req("/rest/v1/vaciados?select=*&limit=1")
cols = sorted(d2[0].keys())
print(f"2) vaciados tiene sku      : {'sku' in cols}  | columnas: {cols}")

# 3) Paginacion simulada (igual que el JS nuevo): contar Jun 1-9
r, _ = req("/rest/v1/vaciados?select=id&fecha=gte.2026-06-01&fecha=lte.2026-06-09T23:59:59&limit=1", count=True)
total = r.headers.get("content-range", "?").split("/")[-1]
rows, off = [], 0
while True:
    r, chunk = req(f"/rest/v1/vaciados?select=id&fecha=gte.2026-06-01&fecha=lte.2026-06-09T23:59:59&order=fecha.desc,id.desc", rng=f"{off}-{off+999}")
    rows += chunk
    if len(chunk) < 1000: break
    off += 1000
ids = [x["id"] for x in rows]
print(f"3) Paginado Jun1-9         : {len(rows)} filas (esperado {total}) | duplicados: {len(ids)-len(set(ids))}")

# 4) Distribucion de horas (¿timestamps UTC o locales?)
r, d4 = req("/rest/v1/vaciados?select=fecha&fecha=gte.2026-06-04T00:00:00&fecha=lte.2026-06-04T23:59:59&order=fecha.asc", rng="0-999")
horas = {}
for x in d4: horas[x["fecha"][11:13]] = horas.get(x["fecha"][11:13], 0) + 1
print(f"4) Horas en 2026-06-04     : {dict(sorted(horas.items()))}")
print("   → si las horas van de ~06 a ~20: son hora LOCAL (slice(0,10) correcto)")
print("   → si van de ~12 a ~02: son UTC (habria que ajustar el dia local)")

# 5) order id funciona en todas las tablas
for t, c in [("vaciados","fecha"),("inspeccion","fecha"),("plan_diario","fecha"),
             ("ventas","fecha"),("liberado","fecha_liberado"),
             ("producto_terminado","fecha_liberacion"),("empaque","fecha_empaque"),
             ("consumos_diarios","fecha"),("salidas_fabricacion","fecha"),
             ("llegadas_almacen","fecha"),("inventarios","semana"),
             ("precios_materiales","anio_mes"),("consumos_bases","fecha"),
             ("ref_peso_bases","modelo")]:
    try:
        req(f"/rest/v1/{t}?select=*&order={c}.desc,id.desc&limit=1")
        print(f"5) {t:22s}: order por id OK")
    except Exception as e:
        print(f"5) {t:22s}: SIN id (usara fallback) — {e}")
