"""
NUEVO — script de reporte, no toca ninguna tabla ni pantalla existente.

Piezas de BASE (vaciados.tipo='Piso') vaciadas en un rango de fechas, con su
peso (de public.pesos_base por patron+medida), EXCLUYENDO las que pasaron
por la Estacion de Recuperacion (recuperacion_log en ares) -- esas ya
existian antes, no son vaciado nuevo.

Uso:
    python reporte_piezas_vaciadas_peso.py [YYYY-MM-DD] [YYYY-MM-DD]
    (default: hoy a hoy)
"""
import sys
import paramiko
import time
import requests
from collections import defaultdict

SUP_URL = "https://xzwlbrirzfogbqhywtvj.supabase.co"
SUP_KEY = "sb_publishable_tCmUG5g7RZbqPPFD3G4U7w_jLrsu01G"
HDR = {"apikey": SUP_KEY, "Authorization": f"Bearer {SUP_KEY}"}

ARES_HOST, ARES_PORT = "10.111.9.254", 2020
ARES_USER, ARES_PASS = "showerwalls", "c1t#5HoWa11S5!20"


def skus_recuperados(desde, hasta):
    """SKUs que pasaron por recuperacion_log en el rango -- se excluyen del reporte."""
    s = paramiko.SSHClient()
    s.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    s.connect(ARES_HOST, port=ARES_PORT, username=ARES_USER, password=ARES_PASS, timeout=15)

    # .cnf temporal (evita el bug de escape del "$" del password de MySQL en
    # bash) -- server no soporta SFTP, se escribe con echo en comillas
    # simples para que el shell remoto no expanda el "$".
    _, o, e = s.exec_command(
        "echo '[client]\nhost=127.0.0.1\nuser=connectit\npassword=Db$how3r20!20\ndatabase=db_shower' > /tmp/my_tmp.cnf"
    )
    time.sleep(1)
    o.read(); e.read()

    sql = (
        f"SELECT DISTINCT sku FROM recuperacion_log "
        f"WHERE created_at BETWEEN '{desde} 00:00:00' AND '{hasta} 23:59:59'"
    )
    _, o, e = s.exec_command(
        f'mysql --defaults-file=/tmp/my_tmp.cnf -N -e "{sql}"'
    )
    time.sleep(2)
    out = o.read().decode("utf-8", "replace")
    err = e.read().decode("utf-8", "replace")
    s.close()
    if err.strip() and "Warning" not in err:
        raise RuntimeError(f"Error consultando ares: {err}")
    return set(line.strip() for line in out.splitlines() if line.strip())


def piezas_vaciadas_base(desde, hasta):
    rows, offset = [], 0
    while True:
        params = (
            f"tipo=eq.Piso&fecha=gte.{desde}T00:00:00&fecha=lte.{hasta}T23:59:59"
            f"&select=sku,patron,medida,fecha,linea&order=fecha.asc"
        )
        r = requests.get(
            f"{SUP_URL}/rest/v1/vaciados?{params}",
            headers={**HDR, "Range": f"{offset}-{offset+999}"},
        )
        r.raise_for_status()
        batch = r.json()
        rows.extend(batch)
        if len(batch) < 1000:
            break
        offset += 1000
    return rows


def pesos_base_dict():
    r = requests.get(f"{SUP_URL}/rest/v1/pesos_base?select=patron,medida,peso_kg,confianza", headers=HDR)
    r.raise_for_status()
    return {(p["patron"], p["medida"]): p for p in r.json()}


def main():
    hoy = time.strftime("%Y-%m-%d")
    desde = sys.argv[1] if len(sys.argv) > 1 else hoy
    hasta = sys.argv[2] if len(sys.argv) > 2 else desde

    print(f"Rango: {desde} a {hasta}")
    excluidos = skus_recuperados(desde, hasta)
    print(f"SKUs excluidos (pasaron por Recuperacion): {len(excluidos)}")

    piezas = piezas_vaciadas_base(desde, hasta)
    piezas = [p for p in piezas if p["sku"] not in excluidos]
    print(f"Piezas de base vaciadas (ya sin recuperadas): {len(piezas)}")

    pesos = pesos_base_dict()

    resumen = defaultdict(lambda: {"piezas": 0, "kg": 0.0, "sin_peso": 0})
    for p in piezas:
        key = (p["patron"], p["medida"])
        r = resumen[key]
        r["piezas"] += 1
        peso = pesos.get(key)
        if peso:
            r["kg"] += float(peso["peso_kg"])
        else:
            r["sin_peso"] += 1

    total_kg, total_piezas, total_sin_peso = 0.0, 0, 0
    print(f"\n{'MODELO':45s} {'MEDIDA':8s} {'PIEZAS':>7s} {'KG':>10s} {'SIN PESO':>9s}")
    for (patron, medida), r in sorted(resumen.items()):
        print(f"{patron:45.45s} {medida:8s} {r['piezas']:7d} {r['kg']:10.1f} {r['sin_peso']:9d}")
        total_kg += r["kg"]
        total_piezas += r["piezas"]
        total_sin_peso += r["sin_peso"]

    print(f"\nTOTAL: {total_piezas} piezas, {total_kg:.1f} kg vaciados")
    if total_sin_peso:
        print(f"AVISO: {total_sin_peso} piezas sin peso registrado en pesos_base (no sumadas al total kg).")


if __name__ == "__main__":
    main()
