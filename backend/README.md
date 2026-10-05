# Apps Script backend

## ⚠️ Cómo desplegar ACTUALIZACIONES sin romper el Web App

**Regla de oro**: `clasp push` sube el código fuente al editor de Apps Script, **PERO invalida el deployment Web App** que sirve la URL `/macros/s/{id}/exec`. Esto ocurre porque Apps Script considera el código del editor como "HEAD" pero el Web App está atado a un deployment inmutable (versión 1, 2, 3...).

Si haces `clasp push` y luego el Web App deja de responder con **410 "No se puede abrir el archivo en estos momentos"** o **redirect al sandbox vacío**, es esto. Lo vimos en:
- 2026-10-02 — primera vez, tras añadir handler `crear_socio`
- 2026-10-02 — segunda vez, tras añadir `getVersion` endpoint
- Y seguramente más veces si no se lee este README

### Procedimiento correcto para actualizar el backend

**Nunca usar `clasp redeploy`** sobre un deployment Web App existente.

En su lugar, **cada vez que cambies `Code.gs`**:

1. `clasp push --force` — sube el código al editor (no falla, solo sube)
2. **OJO**: el Web App que estés usando deja de funcionar en este momento
3. Abre el editor de Apps Script en el navegador
4. **Deploy** → **Manage deployments**
5. Click en **+** o **New deployment**
6. Engranaje ⚙️ → **Web app**
7. Configuración: Execute as: Me / Anyone
8. **Deploy** → copia la URL nueva
9. Pega la nueva URL en `app/lib/services/api_config.dart`
10. Rebuild del APK

### Cómo verificar que el Web App responde

```bash
curl -L 'https://script.google.com/macros/s/NUEVA_URL/exec?op=preguntas&token=TU_TOKEN'
# Debe devolver: {"preguntas":[]}
```

Si devuelve HTML con "Página no encontrada" o "No se puede abrir el archivo", **el deployment está roto** y necesitas repetir el paso 3-8.

### Endpoints

| Método | URL params | Función |
|---|---|---|
| POST | `{op: 'crear_registro', usuario, fechaHora, respuestas, metadatosVoz, ...}` | Escribe fila en `Registros` con ID correlativo y LockService |
| POST | `{op: 'crear_socio', numSocio, nombre, pin, pueblosHabituales, activo}` | Crea/actualiza socio en `Socios` |
| GET  | `?op=preguntas&token=...` | Devuelve lista de preguntas de `Preguntas` |
| GET  | `?op=socios&numSocio=X&pin=Y&token=...` | Busca socio, valida PIN, devuelve `pin_ok` |
| GET  | `?op=fincas&numSocio=X&token=...` | Lista de fincas del socio desde `Fincas_Pueblos` |
| GET  | `?op=version&token=...` | (DEPRECADO — versión ahora se consulta a GitHub Releases) |

**Importante**: las respuestas de `POST` desde clientes no-navegador (curl, Flutter con `http` package, etc.) **parecen fallar** porque redirigen a un sandbox de Google (`script.googleusercontent.com/macros/echo`) que no hace echo de POSTs. **Los datos SÍ se escriben** (verificarlo en la Sheet), solo ajustar la app para no esperar cuerpo en la respuesta de POST.