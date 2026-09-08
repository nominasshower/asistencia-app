"""
NUEVO — no toca recuperacion_log (ares) ni ninguna tabla existente de Supabase.
Sincroniza los SKUs de recuperacion_log (ares) hacia public.recuperacion_skus
(Supabase), para que piezas_vaciadas_peso.html (GitHub Pages, HTTPS) pueda
excluirlos sin llamar directo a ares (HTTP, LAN-only, bloqueado por
mixed-content -- ver memoria connectit-pagina-standalone-metodo).

Pensado para correr periodico (cron/Task Scheduler), igual que los demas
sync_*.py de este repo. Trae TODO recuperacion_log cada vez (tabla chica,
upsert por sku es barato) -- si crece mucho, cambiar a incremental por fecha.

Requiere que supabase_recuperacion_skus_schema.sql ya se haya corrido.
"""
import paramiko
import time
import requests

ARES_HOST, ARES_PORT = "10.111.9.254", 2020
ARES_USER, ARES_PASS = "showerwalls", "c1t#5HoWa11S5!20"

SUP_URL = "https://xzwlbrirzfogbqhywtvj.supabase.co"
SUP_KEY = "sb_publishable_tCmUG5g7RZbqPPFD3G4U7w_jLrsu01G"
HEADERS = {
    "apikey": SUP_KEY, "Authorization": f"Bearer {SUP_KEY}",
    "Content-Type": "application/json", "Prefer": "resolution=merge-duplicates",
}


def leer_recuperacion_log():
    s = paramiko.SSHClient()
    s.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    s.connect(ARES_HOST, port=ARES_PORT, username=ARES_USER, password=ARES_PASS, timeout=15)
    _, o, e = s.exec_command(
        "echo '[client]\nhost=127.0.0.1\nuser=connectit\npassword=Db$how3r20!20\ndatabase=db_shower' > /tmp/my_tmp.cnf"
    )
    time.sleep(1); o.read(); e.read()

    sql = "SELECT sku, MIN(created_at) FROM recuperacion_log GROUP BY sku"
    _, o, e = s.exec_command(f'mysql --defaults-file=/tmp/my_tmp.cnf -N -e "{sql}"')
    time.sleep(2)
    out = o.read().decode("utf-8", "replace")
    err = e.read().decode("utf-8", "replace")
    s.close()
    if err.strip() and "Warning" not in err:
        raise RuntimeError(f"Error consultando ares: {err}")

    filas = []
    for line in out.splitlines():
        line = line.strip()
        if not line:
            continue
        sku, fecha = line.split("\t")
        filas.append({"sku": sku, "fecha": fecha.replace(" ", "T") + "Z"})
    return filas


def main():
    filas = leer_recuperacion_log()
    print(f"{len(filas)} SKUs en recuperacion_log (ares)")
    if not filas:
        return
    r = requests.post(
        f"{SUP_URL}/rest/v1/recuperacion_skus?on_conflict=sku", headers=HEADERS, json=filas
    )
    print(r.status_code)
    if r.status_code >= 300:
        print(r.text[:2000])


if __name__ == "__main__":
    main()
