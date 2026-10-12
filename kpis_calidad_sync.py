#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""KPIs Calidad: corre EN ARES (lo dispara n8n cada hora). Calcula los datos con mysql local (SOLO LECTURA)
y los sube a Supabase (tabla public.calidad_kpis_data, fila 'principal') para que kpis_calidad.html los lea.
Compatible con Python 3.6 (el de ares). Requiere kpis_calidad_lib.py en la misma carpeta y que ya se haya
corrido kpis_calidad_setup2.sql en Supabase."""
import json, os, subprocess, sys, urllib.request, urllib.parse
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from kpis_calidad_lib import calcular

MYSQL_CNF = '/home/showerwalls/n8n/scripts/.mysql_connectit.cnf'
SUP_URL = 'https://xzwlbrirzfogbqhywtvj.supabase.co'
SUP_KEY = 'sb_publishable_tCmUG5g7RZbqPPFD3G4U7w_jLrsu01G'
TELEGRAM_TOKEN = '8626905716:AAHNfR4qrloIzseXIetoh7ky_CEHx6k_qmc'
TELEGRAM_CHAT_ID = '6877339324'
DIAS = 70


def run(sql):
    p = subprocess.run(['mysql', '--defaults-file=' + MYSQL_CNF, '--default-character-set=utf8', '-B', '-N'],
                       input=sql.encode('utf-8'), stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=240)
    if p.returncode != 0 or b'ERROR' in p.stderr:
        raise RuntimeError('SQL: ' + p.stderr.decode('utf-8', 'replace')[:300])
    return [l.split('\t') for l in p.stdout.decode('utf-8', 'replace').splitlines() if l.strip()]


def subir(datos):
    body = json.dumps({'id': 'principal', 'datos': datos, 'generado': datos['generado'].replace(' ', 'T') + ':00-06:00'}).encode('utf-8')
    req = urllib.request.Request(
        SUP_URL + '/rest/v1/calidad_kpis_data?on_conflict=id', data=body, method='POST',
        headers={'apikey': SUP_KEY, 'Authorization': 'Bearer ' + SUP_KEY, 'Content-Type': 'application/json',
                 'Prefer': 'resolution=merge-duplicates,return=minimal'})
    urllib.request.urlopen(req, timeout=30).read()


def avisar(texto):
    try:
        data = urllib.parse.urlencode({'chat_id': TELEGRAM_CHAT_ID, 'text': texto}).encode('utf-8')
        urllib.request.urlopen(urllib.request.Request('https://api.telegram.org/bot%s/sendMessage' % TELEGRAM_TOKEN, data=data), timeout=15)
    except Exception as e:
        print('No se pudo avisar por Telegram: %s' % e)


def main():
    try:
        datos = calcular(run, DIAS)
        if '--seco' in sys.argv:
            print('SECO (no se sube): %s, %d dias' % (datos['generado'], len(datos['dias']))); return
        subir(datos)
        print('OK %s, %d dias' % (datos['generado'], len(datos['dias'])))
    except Exception as e:
        print('ERROR: %s' % e)
        avisar('KPIs Calidad: no se pudo actualizar los datos de la pagina. %s' % str(e)[:200])
        sys.exit(1)


if __name__ == '__main__':
    main()
