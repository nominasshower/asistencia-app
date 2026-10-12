"""KPIs Calidad: consulta SOLO LECTURA a ConnectIT (ares) y escribe kpis_calidad_data.json.
Uso: python generar_kpis_calidad.py [dias_atras=70]
Criterios (alineados con el reporte de vaciados): piezas vaciadas = process_log Vaciado (ws 3),
sin recuperacion_log y sin defectos 76,77,83,85,86,87,88,92. Grado C = piece_status SCRAP (6)
entre esas piezas, fechado por dia de vaciado."""
import paramiko, json, sys, datetime as dt, os
# Credenciales de ares: NO van en el repositorio (publico). Viven en .credenciales_ares.json (ignorado por git)
_CRED = json.load(open(os.path.join(os.path.dirname(os.path.abspath(__file__)), '.credenciales_ares.json'), encoding='utf-8'))

HOST, PORT = '10.111.9.254', 2020
SSH_USER, SSH_PASS = _CRED['ssh_user'], _CRED['ssh_pass']
CNF = "[client]\nhost=127.0.0.1\nuser=connectit\npassword=" + _CRED["db_pass"] + "\ndatabase=db_shower\n"
# Retrabajo MENOR = defecto que se arregla con lijado/resane/pulido (propuesta, por confirmar con calidad).
# Todo defecto que no este aqui cuenta como MAYOR (rehacer gelcoat, mal vaciada, quebrados, etc.). Ajustar aqui.
MENOR = ('despostillado', 'espesor delgado', 'espesor grueso', 'pando', 'mal resanada',
         'marca de dedo', 'marca de molde', 'marcas de molde', 'manchas de molde', 'molde rayado')
EXCL = "76,77,83,85,86,87,88,92"

def mysql(ssh, sql):
    def sh(cmd):
        _, o, e = ssh.exec_command(cmd); o.channel.recv_exit_status()
        return o.read().decode('utf-8', 'replace'), e.read().decode('utf-8', 'replace')
    sh("cat > /tmp/my_kpi.cnf <<'EOF'\n" + CNF + "EOF\nchmod 600 /tmp/my_kpi.cnf")
    sh("cat > /tmp/kpi.sql <<'EOF'\n" + sql + "\nEOF")
    out, err = sh("mysql --defaults-file=/tmp/my_kpi.cnf -B -N < /tmp/kpi.sql")
    if 'ERROR' in err: raise SystemExit(err)
    return [l.split('\t') for l in out.splitlines() if l.strip()]

def main():
    dias = int(sys.argv[1]) if len(sys.argv) > 1 else 70
    desde = (dt.date.today() - dt.timedelta(days=dias)).strftime('%Y-%m-%d')
    base = f"""
DROP TEMPORARY TABLE IF EXISTS v;
CREATE TEMPORARY TABLE v AS SELECT pl.sku, MIN(DATE(pl.created_at)) d FROM process_log pl
 WHERE pl.workstation_id=3 AND pl.created_at>='{desde}' GROUP BY pl.sku;
DROP TEMPORARY TABLE IF EXISTS vn;
CREATE TEMPORARY TABLE vn AS SELECT v.sku, v.d, p.id piece_id, p.piece_status_id, pt.name tipo
 FROM v JOIN piece p ON p.sku=v.sku JOIN product pr ON pr.id=p.product_id JOIN product_type pt ON pt.id=pr.product_type_id
 WHERE v.sku NOT IN (SELECT sku FROM recuperacion_log)
   AND p.id NOT IN (SELECT piece_id FROM piece_defect WHERE active=1 AND defect_id IN ({EXCL}));
"""
    ssh = paramiko.SSHClient(); ssh.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    ssh.connect(HOST, port=PORT, username=SSH_USER, password=SSH_PASS, timeout=15)
    try:
        q = lambda s: mysql(ssh, base + s)
        prod = q("SELECT d, tipo, COUNT(*) FROM vn GROUP BY d, tipo;")
        gc = q("SELECT d, tipo, COUNT(*) FROM vn WHERE piece_status_id=6 GROUP BY d, tipo;")
        gcdef = q(f"""SELECT vn.d, df.name, COUNT(DISTINCT vn.piece_id) FROM vn JOIN piece_defect pd ON pd.piece_id=vn.piece_id AND pd.active=1
                      JOIN defect df ON df.id=pd.defect_id WHERE vn.piece_status_id=6 GROUP BY vn.d, df.name;""")
        insp = q(f"SELECT DATE(created_at), COUNT(DISTINCT sku) FROM process_log WHERE workstation_id=12 AND created_at>='{desde}' GROUP BY 1;")
        # inspeccionadas ese dia con algun defecto registrado ese mismo dia
        insp_def = q(f"""SELECT DATE(pl.created_at), COUNT(DISTINCT pl.sku) FROM process_log pl JOIN piece p ON p.sku=pl.sku
                         JOIN piece_defect pd ON pd.piece_id=p.id AND pd.active=1 AND DATE(pd.created_at)=DATE(pl.created_at)
                         WHERE pl.workstation_id=12 AND pl.created_at>='{desde}' GROUP BY 1;""")
        rw = q(f"SELECT DATE(created_at), COUNT(*), SUM(release_date IS NOT NULL) FROM rework WHERE created_at>='{desde}' GROUP BY 1;")
        # defectos registrados al mismo momento en que la pieza se manda a Retrabajo (+-2 min); una fila por (retrabajo, defecto); la clasificacion menor/mayor se hace abajo por tipo de defecto
        rw_def = q(f"""SELECT DATE(r.created_at), r.id, df.name FROM rework r JOIN piece p ON p.sku=r.sku
                         JOIN piece_defect pd ON pd.piece_id=p.id AND pd.active=1
                           AND ABS(TIMESTAMPDIFF(SECOND, r.created_at, pd.created_at))<=120
                         JOIN defect df ON df.id=pd.defect_id
                         WHERE r.created_at>='{desde}' GROUP BY 1,2,3;""")
    finally:
        ssh.close()
    days = {}
    def D(d): return days.setdefault(d, {'fecha': d, 'vaciadas': 0, 'pared': 0, 'piso': 0, 'otros': 0,
        'gc': 0, 'gc_pared': 0, 'gc_piso': 0, 'gc_otros': 0, 'inspeccionadas': 0, 'insp_con_defecto': 0,
        'retrabajos': 0, 'retrabajos_liberados': 0, 'retrabajo_mayor': 0, 'defectos_gc': {}, 'defectos_rw': {}})
    k = {'Pared': 'pared', 'Piso': 'piso'}
    for d, t, n in prod:
        x = D(d); n = int(n); x['vaciadas'] += n; x[k.get(t, 'otros')] += n
    for d, t, n in gc:
        x = D(d); n = int(n); x['gc'] += n; x['gc_' + k.get(t, 'otros')] += n
    for d, nm, n in gcdef: D(d)['defectos_gc'][nm] = int(n)
    for d, n in insp: D(d)['inspeccionadas'] = int(n)
    for d, n in insp_def: D(d)['insp_con_defecto'] = int(n)
    for d, n, l in rw: x = D(d); x['retrabajos'] = int(n); x['retrabajos_liberados'] = int(l or 0)
    por_rw = {}
    for d, rid, nm in rw_def:
        e = por_rw.setdefault(rid, [d, set()]); e[1].add(nm)
        x = D(d); x['defectos_rw'][nm] = x['defectos_rw'].get(nm, 0) + 1
    for rid, (d, nms) in por_rw.items():
        if not all(n.lower().startswith(MENOR) for n in nms): D(d)['retrabajo_mayor'] += 1
    out = {'generado': dt.datetime.now().strftime('%Y-%m-%d %H:%M'), 'desde': desde, 'meta_gc': 0.015,
           'dias': [days[d] for d in sorted(days)]}
    p = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'kpis_calidad_data.json')
    json.dump(out, open(p, 'w', encoding='utf-8'), ensure_ascii=False, indent=1)
    print('OK', p, len(out['dias']), 'dias')

if __name__ == '__main__': main()
