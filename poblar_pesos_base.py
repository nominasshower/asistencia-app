"""
NUEVO — no toca `vaciados` ni ninguna tabla existente.
Carga a `public.pesos_base` los pesos reales medidos en planta que estan en
D:\\mis documentos\\Peso Bases.xlsx, ya agrupados y con el `patron` normalizado
al mismo texto exacto que usa `vaciados.patron` (para que el join funcione).

Requiere que la tabla ya exista (correr antes supabase_pesos_base_schema.sql
en el SQL editor de Supabase).
"""
import requests

SUP_URL = "https://xzwlbrirzfogbqhywtvj.supabase.co"
SUP_KEY = "sb_publishable_tCmUG5g7RZbqPPFD3G4U7w_jLrsu01G"  # anon/publishable, tabla sin RLS
HEADERS = {
    "apikey": SUP_KEY, "Authorization": f"Bearer {SUP_KEY}",
    "Content-Type": "application/json", "Prefer": "resolution=merge-duplicates",
}

# patron ya normalizado EXACTO a como aparece en vaciados.patron (verificado
# contra 1000 filas reales tipo='Piso' el 2026-09-07). Los dos casos marcados
# "sin verificar" no aparecieron en esa muestra -- confirmar cuando se vacie
# ese modelo, o ajustar el texto si no hace match.
FILAS = [
    dict(patron="BASE TRENCH DRAIN (TR) LEFT/ IZQ", medida="34x60", peso_kg=96.5, peso_kg_min=96.5, peso_kg_max=96.5, n_muestras=1),
    dict(patron="BASE TRENCH DRAIN (TR) LEFT/ IZQ", medida="32x60", peso_kg=96.0, peso_kg_min=96.0, peso_kg_max=96.0, n_muestras=1),
    dict(patron="BASE TRENCH DRAIN (TR) RIGHT/DER", medida="32x60", peso_kg=93.0, peso_kg_min=92.5, peso_kg_max=93.5, n_muestras=2),
    dict(patron="BASE TRENCH DRAIN (TR) RIGHT/DER", medida="34x60", peso_kg=91.5, peso_kg_min=91.5, peso_kg_max=91.5, n_muestras=1),
    dict(patron="BASE TRENCH DRAIN (TR) LEFT/ IZQ", medida="30x58", peso_kg=70.5, peso_kg_min=70.0, peso_kg_max=71.5, n_muestras=3),
    dict(patron="BASE TRENCH DRAIN (TR) RIGHT/DER", medida="30x58", peso_kg=70.33, peso_kg_min=69.0, peso_kg_max=71.5, n_muestras=3),
    dict(patron="BASE CENTER DRAIN (CD) CENTER", medida="34x48", peso_kg=73.0, peso_kg_min=72.5, peso_kg_max=73.5, n_muestras=2),
    dict(patron="BASE CENTER DRAIN (CD) CENTER", medida="30x60", peso_kg=52.0, peso_kg_min=52.0, peso_kg_max=52.0, n_muestras=1),
    dict(patron="BASE CENTER DRAIN (CD) CENTER", medida="36x48", peso_kg=71.83, peso_kg_min=69.0, peso_kg_max=75.0, n_muestras=3),
    # sin verificar contra vaciados real -- no aparecio en la muestra de 1000 filas
    dict(patron="BASE REVERSIBLE DRAIN (RV) LEFT/IZQ", medida="32x60", peso_kg=91.0, peso_kg_min=91.0, peso_kg_max=91.0, n_muestras=1,
         notas="Patron sin verificar contra vaciados real (no aparecio en muestra de 1000 filas) -- confirmar texto exacto cuando se vacie este modelo."),
    # offset: el excel no distingue lado, se duplica el mismo peso para L y R
    dict(patron="BASE OFFSET DRAIN (OF) RIGHT/DER", medida="30x60", peso_kg=94.88, peso_kg_min=93.0, peso_kg_max=97.0, n_muestras=8,
         notas="Excel origen no distinguia lado L/R -- mismo dato aplicado a ambos patrones OF hasta pesar por separado."),
    dict(patron="BASE OFFSET DRAIN(OF) LEFT/ IZQ", medida="30x60", peso_kg=94.88, peso_kg_min=93.0, peso_kg_max=97.0, n_muestras=8,
         notas="Excel origen no distinguia lado L/R -- mismo dato aplicado a ambos patrones OF hasta pesar por separado."),
]

for f in FILAS:
    f.setdefault("fuente", "medido_planta")
    f.setdefault("confianza", "alta")
    f.setdefault("notas", None)

def main():
    r = requests.post(f"{SUP_URL}/rest/v1/pesos_base", headers=HEADERS, json=FILAS)
    print(r.status_code)
    print(r.text[:3000])

if __name__ == "__main__":
    main()
