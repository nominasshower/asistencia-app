"""KPIs Calidad: consulta SOLO LECTURA a ConnectIT (ares, por SSH) y escribe kpis_calidad_data.json.
Uso: python generar_kpis_calidad.py [dias_atras=70]   (la version automatica corre en ares: kpis_calidad_sync.py)"""
import paramiko, json, sys, os
from kpis_calidad_lib import calcular
# Credenciales de ares: NO van en el repositorio (publico). Viven en .credenciales_ares.json (ignorado por git)
_CRED = json.load(open(os.path.join(os.path.dirname(os.path.abspath(__file__)), '.credenciales_ares.json'), encoding='utf-8'))
HOST, PORT = '10.111.9.254', 2020
CNF = "[client]\nhost=127.0.0.1\nuser=connectit\npassword=" + _CRED["db_pass"] + "\ndatabase=db_shower\n"


def main():
    dias = int(sys.argv[1]) if len(sys.argv) > 1 else 70
    ssh = paramiko.SSHClient(); ssh.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    ssh.connect(HOST, port=PORT, username=_CRED['ssh_user'], password=_CRED['ssh_pass'], timeout=15)

    def sh(cmd):
        _, o, e = ssh.exec_command(cmd); o.channel.recv_exit_status()
        return o.read().decode('utf-8', 'replace'), e.read().decode('utf-8', 'replace')

    def run(sql):
        sh("cat > /tmp/my_kpi.cnf <<'EOF'\n" + CNF + "EOF\nchmod 600 /tmp/my_kpi.cnf")
        sh("cat > /tmp/kpi.sql <<'EOF'\n" + sql + "\nEOF")
        out, err = sh("mysql --defaults-file=/tmp/my_kpi.cnf -B -N < /tmp/kpi.sql")
        if 'ERROR' in err: raise SystemExit(err)
        return [l.split('\t') for l in out.splitlines() if l.strip()]

    try:
        out = calcular(run, dias)
    finally:
        ssh.close()
    p = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'kpis_calidad_data.json')
    json.dump(out, open(p, 'w', encoding='utf-8'), ensure_ascii=False, indent=1)
    print('OK', p, len(out['dias']), 'dias')


if __name__ == '__main__':
    main()
