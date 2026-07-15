// ============================================================
//  ALTA DE EMPLEADO - Google Apps Script Backend
//  Pegar este código en: script.google.com > Nuevo proyecto
//  Luego: Implementar > Nueva implementación > Aplicación web
//    - Ejecutar como: Yo (mi cuenta)
//    - Quién tiene acceso: Cualquier persona
//  Copiar la URL generada y pegarla en index.html → APPS_SCRIPT_URL
// ============================================================

// Columnas de la hoja EMPLEADOS (en orden):
// nomina | nombre | empresa | puesto | tipo_nomina | mano_obra | turno | area | sexo |
// fecha_nac | direccion | colonia | municipio | estado | pais | cp | fecha_alta | ...

function doPost(e) {
  var result;
  try {
    var data = JSON.parse(e.postData.contents);
    if (data.accion === 'baja') {
      result = bajaEmpleado(data);
    } else {
      result = altaEmpleado(data);
    }
  } catch(err) {
    result = { ok: false, error: 'Error al procesar: ' + err.message };
  }

  return ContentService
    .createTextOutput(JSON.stringify(result))
    .setMimeType(ContentService.MimeType.JSON);
}

// Mantiene el script activo — trigger cada 10 min (opcional)
function keepAlive() {
  // No hace nada, solo evita cold starts
}

function altaEmpleado(data) {
  if (!data.sheets_id) return { ok: false, error: 'Falta sheets_id' };
  if (!data.nomina)    return { ok: false, error: 'Falta nómina' };
  if (!data.nombre)    return { ok: false, error: 'Falta nombre' };

  var ss    = SpreadsheetApp.openById(data.sheets_id);
  var hoja  = ss.getSheetByName('EMPLEADOS');
  if (!hoja) return { ok: false, error: 'No existe pestaña EMPLEADOS' };

  // Verificar que la nómina no exista ya
  var col1 = hoja.getRange(2, 1, Math.max(hoja.getLastRow() - 1, 1), 1).getValues();
  for (var i = 0; i < col1.length; i++) {
    if (String(col1[i][0]).trim() === String(data.nomina).trim()) {
      return { ok: false, error: 'La nómina ' + data.nomina + ' ya existe' };
    }
  }

  // Leer headers para saber el orden de columnas
  var headers = hoja.getRange(1, 1, 1, hoja.getLastColumn()).getValues()[0];
  var fila    = new Array(headers.length).fill('');

  var map = {
    'nomina':          data.nomina    || '',
    'nombe':           (data.nombre + ' ' + data.apellido).trim(),
    'nombre':          (data.nombre + ' ' + data.apellido).trim(),
    'empresa':         data.empresa   || '',
    'puesto':          data.puesto    || '',
    'tipo de nomina':  data.tipo_nomina || 'S',
    'mano de obra':    data.mano_obra  || '',
    'turno':           data.turno      || '',
    'area':            data.area       || '',
    'sexo':            data.sexo       || '',
    'fecha_alta':      Utilities.formatDate(new Date(), 'America/Mexico_City', 'dd/MM/yyyy'),
    'vale_importe':    data.vale_importe  || 0,
    'puntualidad_5':   data.puntualidad_5 || 0,
    'asistencia_10':   data.asistencia_10 || 0
  };

  headers.forEach(function(h, idx) {
    var key = h.toString().trim().toLowerCase();
    if (map.hasOwnProperty(key)) fila[idx] = map[key];
  });

  hoja.appendRow(fila);

  return {
    ok:  true,
    msg: 'Empleado ' + data.nombre + ' ' + data.apellido + ' (' + data.nomina + ') dado de alta correctamente'
  };
}

function bajaEmpleado(data) {
  if (!data.sheets_id) return { ok: false, error: 'Falta sheets_id' };
  if (!data.nomina)    return { ok: false, error: 'Falta nómina' };

  var ss   = SpreadsheetApp.openById(data.sheets_id);
  var hoja = ss.getSheetByName('EMPLEADOS');
  if (!hoja) return { ok: false, error: 'No existe pestaña EMPLEADOS' };

  var lastCol  = hoja.getLastColumn();
  var lastRow  = hoja.getLastRow();
  var headers  = hoja.getRange(1, 1, 1, lastCol).getValues()[0];
  var col1     = hoja.getRange(2, 1, Math.max(lastRow - 1, 1), 1).getValues();

  // Buscar fila del empleado por nómina
  var filaIdx = -1;
  for (var i = 0; i < col1.length; i++) {
    if (String(col1[i][0]).trim() === String(data.nomina).trim()) {
      filaIdx = i + 2; // +2: encabezado + base 1
      break;
    }
  }
  if (filaIdx === -1) return { ok: false, error: 'Nómina ' + data.nomina + ' no encontrada en EMPLEADOS' };

  // Buscar o crear columnas status y fecha_baja
  var colStatus   = -1;
  var colFechaBaja = -1;
  var colMotivo   = -1;
  headers.forEach(function(h, idx) {
    var k = h.toString().trim().toLowerCase();
    if (k === 'status' || k === 'estatus') colStatus    = idx + 1;
    if (k === 'fecha_baja')                colFechaBaja = idx + 1;
    if (k === 'motivo_baja')               colMotivo    = idx + 1;
  });

  // Si no existen, agregar al final
  if (colStatus === -1) {
    lastCol++; colStatus = lastCol;
    hoja.getRange(1, colStatus).setValue('status');
  }
  if (colFechaBaja === -1) {
    lastCol++; colFechaBaja = lastCol;
    hoja.getRange(1, colFechaBaja).setValue('fecha_baja');
  }
  if (colMotivo === -1) {
    lastCol++; colMotivo = lastCol;
    hoja.getRange(1, colMotivo).setValue('motivo_baja');
  }

  var fechaBaja = data.fecha_baja || Utilities.formatDate(new Date(), 'America/Mexico_City', 'dd/MM/yyyy');
  hoja.getRange(filaIdx, colStatus).setValue('BAJA');
  hoja.getRange(filaIdx, colFechaBaja).setValue(fechaBaja);
  hoja.getRange(filaIdx, colMotivo).setValue(data.motivo || '');

  return {
    ok:  true,
    msg: 'Empleado ' + data.nombre + ' (' + data.nomina + ') dado de baja el ' + fechaBaja
  };
}
