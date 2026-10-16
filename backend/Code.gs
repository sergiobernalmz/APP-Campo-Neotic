/**
 * voz-campo - Backend Google Apps Script
 *
 * Recibe registros desde la app móvil y los escribe en Google Sheets.
 *
 * SETUP (una sola vez):
 *   1. Crear Google Sheet "voz-campo-data" con pestañas:
 *      Registros | Socios | Fincas_Pueblos | Preguntas
 *   2. Copiar ID de la Sheet (parte entre /d/ y /edit en la URL)
 *      y pegarlo en SHEET_ID más abajo.
 *   3. Elegir un API_TOKEN robusto y pegarlo en API_TOKEN más abajo.
 *   4. Deploy: clasp push && clasp deploy
 *
 * ENDPOINTS:
 *   GET  /exec?op=preguntas                 -> lista de preguntas del cuestionario
 *   GET  /exec?op=socios&numSocio=NNNN      -> validación de socio (sin pin)
 *   GET  /exec?op=socios&numSocio=NNNN&pin= -> validación de socio (con pin)
 *   GET  /exec?op=fincas[&numSocio=NNNN]    -> fincas (TODOS o de un socio)
 *   GET  /exec?op=version                   -> version actual + apk_url
 *   GET  /exec?op=crear_socio&...           -> crear/actualizar socio (v1.0.9: GET)
 *   GET  /exec?op=crear_registro&...        -> crear un registro (v1.0.9: GET)
 *
 *   POST /exec                              -> mismo, con body JSON. Apps Script
 *                                              Web Apps con "Anyone" tienen
 *                                              problemas con POST (302->405), por
 *                                              lo que la app usa GET siempre.
 *                                              doPost se conserva por si se migra
 *                                              a backend real (Cloud Functions).
 */

// ============================================================
// CONFIGURACIÓN - EDITAR ANTES DE DESPLEGAR
// ============================================================

const SHEET_ID = '1mC-nV6IelemZDPMZZaGzq6nhoJei5tqnHKnUXJVDk5c';
const API_TOKEN = '458bc7cef5e97c6b5681c7ede1c0a33131ba3ed15b98354837952babaff120ca';

// ============================================================

/**
 * Normaliza un body (objeto JS) construido desde query params (GET) o desde
 * postData.contents (POST). Hace JSON.parse defensivo del body.
 */
function getBody(e) {
  if (e.postData && e.postData.contents) {
    try {
      return JSON.parse(e.postData.contents);
    } catch (err) {
      // body no es JSON valido, fallback a query params
    }
  }
  // query params -> body (todo string, sin tipos)
  const body = {};
  if (e.parameter) {
    Object.keys(e.parameter).forEach((k) => {
      if (k !== 'op' && k !== 'token') body[k] = e.parameter[k];
    });
  }
  // campos anidados comunes: respuestas, metadatosVoz (los enviamos como
  // respuestas.pueblo, respuestas.hectareas, etc. en GET)
  const flat = {};
  Object.keys(body).forEach((k) => {
    if (k.startsWith('respuestas.')) {
      flat.respuestas = flat.respuestas || {};
      flat.respuestas[k.substring('respuestas.'.length)] = body[k];
      delete body[k];
    } else if (k.startsWith('metadatosVoz.')) {
      flat.metadatosVoz = flat.metadatosVoz || {};
      flat.metadatosVoz[k.substring('metadatosVoz.'.length)] = body[k];
      delete body[k];
    }
  });
  Object.assign(body, flat);
  return body;
}

function doPost(e) {
  const lock = LockService.getScriptLock();
  lock.waitLock(30000);

  try {
    const body = getBody(e);
    if (body.token !== API_TOKEN) {
      return jsonResponse({ error: 'unauthorized' }, 401);
    }
    const op = body.op || 'crear_registro';
    switch (op) {
      case 'crear_registro':
        return crearRegistro(body);
      case 'crear_socio':
        return crearSocio(body);
      default:
        return jsonResponse({ error: 'unknown_op', op: op }, 400);
    }
  } catch (err) {
    return jsonResponse({ error: String(err) }, 500);
  } finally {
    lock.releaseLock();
  }
}

function doGet(e) {
  try {
    const op = e.parameter.op;
    if (!op) return jsonResponse({ error: 'missing_op' }, 400);

    if (e.parameter.token !== API_TOKEN) {
      return jsonResponse({ error: 'unauthorized' }, 401);
    }

    switch (op) {
      case 'preguntas':
        return listarPreguntas();
      case 'socios':
        return buscarSocio(e.parameter.numSocio, e.parameter.pin);
      case 'fincas':
        return listarFincas(e.parameter.numSocio);
      case 'version':
        return getVersion();
      case 'debug_socios':
        return debugSocios();
      case 'crear_socio': {
        // Refactor v1.0.9: GET para escrituras (workaround Apps Script POST bug)
        const body = getBody(e);
        body.op = 'crear_socio';
        return crearSocio(body);
      }
      case 'crear_registro': {
        const body = getBody(e);
        body.op = 'crear_registro';
        return crearRegistro(body);
      }
      default:
        return jsonResponse({ error: 'unknown_op', op: op }, 400);
    }
  } catch (err) {
    return jsonResponse({ error: String(err) }, 500);
  }
}

// ============================================================
// HANDLERS
// ============================================================

function crearRegistro(body) {
  const ss = SpreadsheetApp.openById(SHEET_ID);
  const sheet = ss.getSheetByName('Registros');
  if (!sheet) return jsonResponse({ error: 'sheet_Registros_missing' }, 500);

  const lastRow = sheet.getLastRow();
  const lastId = lastRow > 1 ? Number(sheet.getRange(lastRow, 1).getValue()) || 0 : 0;
  const newId = lastId + 1;

  const r = body.respuestas || {};
  const m = body.metadatosVoz || {};

  const row = [
    newId,
    body.fechaHora || new Date().toISOString(),
    body.usuario || '',
    r.numSocio || body.usuario || '',
    r.pueblo || '',
    r.finca || '',
    r.hectareas !== undefined ? r.hectareas : '',
    r.tipoTratamiento || '',
    m.pueblo_original_audio || '',
    m.finca_teaxt_original || '',
    m.confianza_fuzzy !== undefined ? m.confianza_fuzzy : '',
    m.modo_entrada || '',
    body.coordenadasGps || '',
    body.dispositivo || '',
    'Validado'
  ];

  sheet.appendRow(row);

  return jsonResponse({ status: 'ok', id: newId });
}

function listarPreguntas() {
  const ss = SpreadsheetApp.openById(SHEET_ID);
  const sheet = ss.getSheetByName('Preguntas');
  if (!sheet) return jsonResponse({ preguntas: [] });

  const data = sheet.getDataRange().getValues();
  if (data.length < 2) return jsonResponse({ preguntas: [] });

  const headers = data[0];
  const preguntas = [];
  for (let i = 1; i < data.length; i++) {
    const row = data[i];
    const obj = {};
    headers.forEach((h, idx) => { obj[h] = row[idx]; });
    if (obj.Orden) preguntas.push(obj);
  }
  preguntas.sort((a, b) => Number(a.Orden) - Number(b.Orden));

  return jsonResponse({ preguntas: preguntas });
}

function buscarSocio(numSocio, pin) {
  if (!numSocio) return jsonResponse({ error: 'missing_numSocio' }, 400);
  const ss = SpreadsheetApp.openById(SHEET_ID);
  const sheet = ss.getSheetByName('Socios');
  if (!sheet) return jsonResponse({ error: 'sheet_Socios_missing' }, 500);

  const data = sheet.getDataRange().getValues();
  if (data.length < 2) return jsonResponse({ found: false });

  for (let i = 1; i < data.length; i++) {
    if (String(data[i][0]).replace(/^0+/, '') === String(numSocio).replace(/^0+/, '')) {
      const socio = {
        numSocio: data[i][0],
        nombre: data[i][1],
        activo: data[i][4]
      };
      if (pin !== undefined) {
        const stored = String(data[i][2] || '');
        socio.pin_ok = (stored !== "" && stored === pin);
      }
      return jsonResponse({ socio: socio });
    }
  }
  return jsonResponse({ found: false });
}

function listarFincas(numSocio) {
  const ss = SpreadsheetApp.openById(SHEET_ID);
  const sheet = ss.getSheetByName('Fincas_Pueblos');
  if (!sheet) return jsonResponse({ fincas: [] });

  const data = sheet.getDataRange().getValues();
  if (data.length < 2) return jsonResponse({ fincas: [] });

  const fincas = [];
  for (let i = 1; i < data.length; i++) {
    const row = data[i];
    const prop = String(row[2] || '');
    if (prop === 'TODOS' || prop === String(numSocio) || numSocio === undefined) {
      fincas.push({
        nombre_oficial: row[0],
        variantes: String(row[1] || '').split(';').map(s => s.trim()).filter(Boolean),
        numSocio: row[2]
      });
    }
  }
  return jsonResponse({ fincas: fincas });
}

function crearSocio(body) {
  Logger.log('crearSocio INICIO body=' + JSON.stringify(body));
  try {
    const ss = SpreadsheetApp.openById(SHEET_ID);
    let sheet = ss.getSheetByName('Socios');

    Logger.log('sheet tras getByName: ' + (sheet ? sheet.getName() : 'NULL'));

    // Auto-crear pestaña si no existe
    if (!sheet) {
      sheet = ss.insertSheet('Socios');
      Logger.log('pestana Socios creada');
    }

    // Auto-crear cabeceras si la pestana esta vacia
    if (sheet.getLastRow() === 0) {
      sheet.appendRow(['NumSocio', 'Nombre', 'PIN', 'PueblosHabituales', 'Activo']);
      Logger.log('cabeceras creadas');
    }

    const numSocio = String(body.numSocio || '').trim();
    const nombre = String(body.nombre || '').trim();
    const pin = String(body.pin || '');
    const pueblosHabituales = String(body.pueblosHabituales || '');
    const activo = String(body.activo || 'Si');

    if (!numSocio || !nombre) {
      Logger.log('error: missing numSocio or nombre');
      return jsonResponse({ error: 'missing_numSocio_or_nombre' }, 400);
    }

    // Buscar socio existente por numSocio
    const data = sheet.getDataRange().getValues();
    let existingRow = -1;
    for (let i = 1; i < data.length; i++) {
      if (String(data[i][0]) === numSocio) {
        existingRow = i + 1; // 1-indexed
        break;
      }
    }

    const row = [numSocio, nombre, pin, pueblosHabituales, activo];

    if (existingRow > 0) {
      sheet.getRange(existingRow, 1, 1, 5).setValues([row]);
      Logger.log('socio actualizado fila=' + existingRow);
      return jsonResponse({ status: 'ok', action: 'updated', numSocio: numSocio });
    } else {
      sheet.appendRow(row);
      Logger.log('socio creado fila=' + sheet.getLastRow());
      return jsonResponse({ status: 'ok', action: 'created', numSocio: numSocio });
    }
  } catch (err) {
    Logger.log('ERROR crearSocio: ' + String(err));
    return jsonResponse({ error: String(err) }, 500);
  }
}

function getVersion() {
  // v1.0.9: NO auto-crear pestaña Config (eso requiere permisos de
  // escritura adicionales y rompe con "Anyone" access). Si no existe
  // Config, devolvemos valores por defecto.
  try {
    const ss = SpreadsheetApp.openById(SHEET_ID);
    const sheet = ss.getSheetByName('Config');
    if (!sheet) {
      return jsonResponse({ version: '1.0.9', apk_url: 'https://github.com/sergiobernalmz/APP-Campo-Neotic/releases/latest' });
    }
    const data = sheet.getDataRange().getValues();
    if (data.length < 2) {
      return jsonResponse({ version: '1.0.9', apk_url: 'https://github.com/sergiobernalmz/APP-Campo-Neotic/releases/latest' });
    }
    // Formato esperado: fila 1 = cabeceras, fila 2 = [version, apk_url]
    const version = String(data[1][1] || data[1][0] || '1.0.9');
    const apkUrl  = String(data[1][2] || data[1][1] || 'https://github.com/sergiobernalmz/APP-Campo-Neotic/releases/latest');
    return jsonResponse({ version: version, apk_url: apkUrl });
  } catch (err) {
    // Fallback silencioso: devolver version por defecto
    return jsonResponse({ version: '1.0.9', apk_url: 'https://github.com/sergiobernalmz/APP-Campo-Neotic/releases/latest' });
  }
}

function debugSocios() {
  const ss = SpreadsheetApp.openById(SHEET_ID);
  const sheets = ss.getSheets().map(function(s) { return s.getName(); });
  Logger.log('Pestanas encontradas: ' + JSON.stringify(sheets));
  const sheet = ss.getSheetByName('Socios');
  if (!sheet) {
    Logger.log('ERROR: pestana Socios no existe');
    return;
  }
  const lastRow = sheet.getLastRow();
  const lastCol = sheet.getLastColumn();
  Logger.log('lastRow=' + lastRow + ' lastCol=' + lastCol);
  if (lastRow > 0) {
    const maxR = Math.min(lastRow, 5);
    const maxC = Math.max(lastCol, 5);
    const data = sheet.getRange(1, 1, maxR, maxC).getValues();
    for (var i = 0; i < data.length; i++) {
      Logger.log('Fila ' + (i+1) + ': ' + JSON.stringify(data[i]));
    }
  } else {
    Logger.log('La pestana Socios esta vacia (0 filas)');
  }
}

// ============================================================
// HELPERS
// ============================================================

function jsonResponse(obj, status) {
  const output = ContentService.createTextOutput(JSON.stringify(obj));
  output.setMimeType(ContentService.MimeType.JSON);
  if (status) console.log('status', status);
  return output;
}

// ============================================================
// HEALTH CHECK (opcional)
// ============================================================

function doGet_health() {
  return jsonResponse({ status: 'ok', version: '0.1.0-mvp' });
}
