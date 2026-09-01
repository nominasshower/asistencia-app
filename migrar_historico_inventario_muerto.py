#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Migra el histórico de INVENTARIO MUERTO (Google Sheets / AppSheet) a Supabase.
Solo trae filas con FECHA INVENTARIO >= 2026-08-01 (lo viejo se queda en el Sheet).

Uso:
    python migrar_historico_inventario_muerto.py [--dry-run]
"""
import csv
import datetime
import json
import re
import sys
import urllib.request
import urllib.error

SHEET_ID = "1j0x1QlTGxMQZNguAoC5ZAXIctMjie92f0vW-dGrhbic"
GID = "405935404"  # pestaña INVENTARIO MUERTO
CSV_URL = f"https://docs.google.com/spreadsheets/d/{SHEET_ID}/export?format=csv&gid={GID}"

SUP_URL = "https://xzwlbrirzfogbqhywtvj.supabase.co"
SUP_KEY = "sb_publishable_tCmUG5g7RZbqPPFD3G4U7w_jLrsu01G"
HEADERS = {"apikey": SUP_KEY, "Authorization": f"Bearer {SUP_KEY}", "Content-Type": "application/json"}

CORTE_DESDE = datetime.datetime(2026, 8, 1)

LINEA_MAP = {"LINEA 1": "LINEA 1", "LINEA 2": "LINEA 2", "": "Sin Linea"}


def parse_fecha(d):
    d = (d or "").strip()
    if not d:
        return None
    try:
        return datetime.datetime.strptime(d, "%d/%m/%Y %H:%M:%S")
    except ValueError:
        pass
    # formato de los botones de AppSheet: "Tue Aug 11 2026 08:58:53 GMT-0600 (hora estándar central)"
    m = re.match(r"^\w+ (\w+ \d+ \d+ \d+:\d+:\d+) GMT([+-]\d{4})", d)
    if m:
        try:
            base = datetime.datetime.strptime(m.group(1), "%b %d %Y %H:%M:%S")
            return base  # se guarda en hora local tal cual, sin convertir zona
        except ValueError:
            return None
    return None


def norm_acabado(a):
    a = (a or "").strip().upper()
    if a == "MATE":
        return "Mate"
    if a == "BRILLO":
        return "Brillo"
    if a == "METAL":
        return "Metal"
    return None


def norm_estatus(s):
    s = (s or "").strip()
    return s if s else "EN INVENTARIO"


ANOMALIAS = []


def parse_num(valor, id_inventario, campo):
    valor = (valor or "").strip()
    if not valor:
        return None
    valor = valor.replace(",", ".")
    try:
        return float(valor)
    except ValueError:
        ANOMALIAS.append(f"{id_inventario}: {campo}='{valor}' no es numérico, se dejó vacío")
        return None


def parse_medida_pair(ancho_raw, alto_raw, medidas_raw, id_inventario):
    """Ancho/Alto normales, o rescata casos donde capturaron todo junto en ANCHO (ej. '30\"X84')."""
    ancho_raw, alto_raw = (ancho_raw or "").strip(), (alto_raw or "").strip()
    try:
        ancho = float(ancho_raw) if ancho_raw else None
        alto = float(alto_raw) if alto_raw else None
        if ancho_raw and alto_raw:
            return ancho, alto
    except ValueError:
        ancho, alto = None, None

    if ancho is not None and alto is None and not alto_raw:
        # ANCHO trae ambos numeros pegados (30"X84, 48X88, 51z90, etc.)
        pass
    fuente = ancho_raw if not alto_raw else f"{ancho_raw}x{alto_raw}"
    numeros = re.findall(r"\d+(?:\.\d+)?", fuente or medidas_raw or "")
    if len(numeros) == 2:
        return float(numeros[0]), float(numeros[1])

    if ancho_raw and ancho is None:
        ANOMALIAS.append(f"{id_inventario}: ANCHO/ALTO='{ancho_raw}'/'{alto_raw}' no se pudo interpretar, se dejó vacío")
    return (ancho, alto) if (ancho_raw or alto_raw) else (None, None)


def fetch_csv():
    req = urllib.request.Request(CSV_URL, headers={"User-Agent": "Mozilla/5.0"})
    with urllib.request.urlopen(req) as resp:
        data = resp.read().decode("utf-8")
    return list(csv.DictReader(data.splitlines()))


def post(path, body, extra_headers=None):
    url = f"{SUP_URL}/rest/v1/{path}"
    headers = {**HEADERS, **(extra_headers or {})}
    req = urllib.request.Request(url, data=json.dumps(body).encode("utf-8"), headers=headers, method="POST")
    try:
        with urllib.request.urlopen(req) as resp:
            return json.loads(resp.read().decode("utf-8") or "[]")
    except urllib.error.HTTPError as e:
        print("ERROR", e.code, e.read().decode())
        raise


def main():
    dry_run = "--dry-run" in sys.argv

    rows = fetch_csv()
    print(f"Total filas en el Sheet: {len(rows)}")

    filtradas = [r for r in rows if (parse_fecha(r.get("FECHA INVENTARIO")) or datetime.datetime(1970, 1, 1)) >= CORTE_DESDE]
    print(f"Filas desde agosto 2026: {len(filtradas)}")

    registros = []
    for r in filtradas:
        oid = r["ID_INVENTARIO"]
        fecha_inv = parse_fecha(r.get("FECHA INVENTARIO"))
        ancho, alto = parse_medida_pair(r.get("ANCHO"), r.get("ALTO"), r.get("MEDIDAS"), oid)
        registros.append({
            "origen_appsheet_id": oid,
            "burrito": r.get("BURRITO", "").strip() or None,
            "pieza": r.get("PIEZA", "").strip(),
            "modelo": r.get("MODELO", "").strip() or None,
            "color": r.get("COLOR", "").strip() or None,
            "ancho": ancho,
            "alto": alto,
            "medidas": r.get("MEDIDAS", "").strip() or None,
            "acabado": norm_acabado(r.get("ACABADO")),
            "linea": LINEA_MAP.get(r.get("LINEA", "").strip(), r.get("LINEA", "").strip() or None),
            "tipo_entrada": r.get("TIPO DE ENTRADA", "").strip() or None,
            "estatus": norm_estatus(r.get("SALIDA")),
            "notas": r.get("DEFECTOS", "").strip() or None,
            "created_at": fecha_inv.isoformat() if fecha_inv else None,
            "_fecha_patio": r.get("FECHA_PATIO", "").strip(),
            "_fecha_stock": r.get("FECHA_STOCK", "").strip(),
            "_fecha_grado_c": r.get("FECHA_GRADO_C", "").strip(),
            "_fecha_recuperada": r.get("FECHA RECUPERADA", "").strip(),
        })

    if ANOMALIAS:
        print(f"\nAnomalías encontradas ({len(ANOMALIAS)}):")
        for a in ANOMALIAS:
            print(" -", a)
        print()

    if dry_run:
        print(json.dumps(registros[:3], indent=2, ensure_ascii=False))
        print(f"(dry-run) se insertarían/actualizarían {len(registros)} registros")
        return

    # 1) upsert de los registros principales, en lotes de 200, pidiendo que regrese id + origen_appsheet_id
    BATCH = 200
    id_por_origen = {}
    for i in range(0, len(registros), BATCH):
        lote = registros[i:i + BATCH]
        payload = [{k: v for k, v in reg.items() if not k.startswith("_")} for reg in lote]
        resultado = post(
            "inventario_muerto?on_conflict=origen_appsheet_id",
            payload,
            {"Prefer": "resolution=merge-duplicates,return=representation"},
        )
        for row in resultado:
            id_por_origen[row["origen_appsheet_id"]] = row["id"]
        print(f"  upsert {i + len(lote)}/{len(registros)}")

    print(f"Registros guardados/actualizados: {len(id_por_origen)}")

    # 2) reconstruir historial de movimientos a partir de las fechas por estatus
    movimientos = []
    for reg in registros:
        inv_id = id_por_origen.get(reg["origen_appsheet_id"])
        if not inv_id:
            continue
        eventos = [
            (reg["_fecha_patio"], "EN PATIO"),
            (reg["_fecha_stock"], "EN STOCK"),
            (reg["_fecha_grado_c"], "GRADO C"),
            (reg["_fecha_recuperada"], "RECUPERADA"),
        ]
        for fecha_txt, estatus_nuevo in eventos:
            fecha = parse_fecha(fecha_txt)
            if fecha:
                movimientos.append({
                    "inventario_id": inv_id,
                    "estatus_anterior": None,
                    "estatus_nuevo": estatus_nuevo,
                    "usuario": "migracion_historico",
                    "created_at": fecha.isoformat(),
                })

    print(f"Movimientos históricos a insertar: {len(movimientos)}")
    for i in range(0, len(movimientos), BATCH):
        lote = movimientos[i:i + BATCH]
        post("inventario_muerto_movimientos", lote, {"Prefer": "return=minimal"})
        print(f"  movimientos {i + len(lote)}/{len(movimientos)}")

    print("Listo.")


if __name__ == "__main__":
    main()
