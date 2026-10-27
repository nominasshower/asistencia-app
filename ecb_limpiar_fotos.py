#!/usr/bin/env python3
"""EC Barton reclamos: borra las fotos con mas de 120 dias (4 meses).

Pide a Supabase la lista de reclamos con fotos vencidas (ecb_fotos_vencidas), borra las dos fotos
de Storage (bucket ecb-reclamos) y marca el reclamo (ecb_foto_borrada). El registro del reclamo
(orden, nombre, defectos, comentario) se conserva; solo se vacian las URLs de las fotos.

La clave INTERNA se lee de la variable ECB_ADMIN o del archivo .ecb_admin junto a este script
(chmod 600, fuera de git). Solo biblioteca estandar (Python 3.6 ok).

Uso:  python3 ecb_limpiar_fotos.py            # borra
      python3 ecb_limpiar_fotos.py --simular  # solo muestra lo que borraria
"""
import json, os, sys, random, urllib.request, urllib.error

SUP = "https://xzwlbrirzfogbqhywtvj.supabase.co"
KEY = "sb_publishable_tCmUG5g7RZbqPPFD3G4U7w_jLrsu01G"   # llave publica (la misma de las paginas)
DIAS = 120
PREFIJO = SUP + "/storage/v1/object/public/ecb-reclamos/"


def admin():
    c = os.environ.get("ECB_ADMIN", "").strip()
    if not c:
        ruta = os.path.join(os.path.dirname(os.path.abspath(__file__)), ".ecb_admin")
        with open(ruta) as f:
            c = f.read().strip()
    return c


def llamar(metodo, url, cuerpo=None, extra=None):
    h = {"apikey": KEY, "Authorization": "Bearer " + KEY}
    h.update(extra or {})
    datos = None
    if cuerpo is not None:
        datos = json.dumps(cuerpo).encode()
        h["Content-Type"] = "application/json"
    req = urllib.request.Request(url, data=datos, headers=h, method=metodo)
    try:
        with urllib.request.urlopen(req, timeout=30) as r:
            t = r.read().decode()
            return r.status, (json.loads(t) if t else None)
    except urllib.error.HTTPError as e:
        return e.code, e.read().decode()


def ya_no_existe(url):
    # con ?v=aleatorio se salta la cache de Supabase: 400/404 = ya no esta
    st, _ = llamar("GET", url + "?v=%d" % random.randint(1, 10**9))
    return st in (400, 404)


def borrar_foto(url, clave):
    if not url:
        return True
    if not url.startswith(PREFIJO):
        print("  URL ajena, no se toca:", url)
        return False
    ruta = url[len(PREFIJO):]
    st, resp = llamar("DELETE", SUP + "/storage/v1/object/ecb-reclamos/" + ruta, extra={"x-ecb-admin": clave})
    if st == 200 and resp:
        return True
    if st == 200 and not resp and ya_no_existe(url):   # 200 [] = nada que borrar (ya no estaba)
        return True
    print("  no se pudo borrar %s (HTTP %s %s)" % (ruta, st, resp))
    return False


def main():
    simular = "--simular" in sys.argv
    clave = admin()
    st, filas = llamar("POST", SUP + "/rest/v1/rpc/ecb_fotos_vencidas", {"p_admin": clave, "p_dias": DIAS})
    if st != 200 or not isinstance(filas, list):
        print("ERROR al pedir la lista:", st, filas)
        sys.exit(1)
    print("Reclamos con fotos de mas de %d dias: %d" % (DIAS, len(filas)))
    borrados = fallos = 0
    for f in filas:
        print("ECB-%05d" % f["id"])
        if simular:
            continue
        if borrar_foto(f.get("foto_lavabo_url"), clave) and borrar_foto(f.get("foto_etiqueta_url"), clave):
            st, resp = llamar("POST", SUP + "/rest/v1/rpc/ecb_foto_borrada", {"p_admin": clave, "p_id": f["id"]})
            if st in (200, 204):
                borrados += 1
                continue
            print("  no se pudo marcar:", st, resp)
        fallos += 1
    print("Listo. Borrados: %d, con fallo: %d%s" % (borrados, fallos, " (simulacion)" if simular else ""))
    sys.exit(1 if fallos else 0)


if __name__ == "__main__":
    main()
