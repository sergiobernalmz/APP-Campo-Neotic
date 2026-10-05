/// voz-campo - Configuración del backend Apps Script
///
/// Centraliza la URL del Web App desplegado y constantes relacionadas.
/// El `apiToken` se considera deuda técnica aceptada para MVP: en producción
/// debería migrarse a OAuth/JWT contra un backend real. Ver
/// `docs/deuda-tecnica.md`.
class ApiConfig {
  /// URL del Web App desplegado en Google Apps Script.
  static const String baseUrl =
      'https://script.google.com/macros/s/AKfycbyUljdQ5ld-YwohjtOpquIGZf-JOJa67MNCYwCqihTwoBJes1CqCZxHNevmMPo6dvuw/exec';

  /// Token API compartido. Validado por `doGet`/`doPost` en `backend/Code.gs`.
  static const String apiToken =
      '458bc7cef5e97c6b5681c7ede1c0a33131ba3ed15b98354837952babaff120ca';

  /// Timeout para todas las llamadas HTTP. 15s da holgura para conexiones
  /// lentas en campo (2G/3G rural).
  static const Duration timeout = Duration(seconds: 15);

  /// Construye una Uri hacia el Web App con los query params dados, incluyendo
  /// siempre el `token` salvo que se desactive con [includeToken]=false.
  static Uri buildUri(Map<String, String> params, {bool includeToken = true}) {
    final all = <String, String>{
      if (includeToken) 'token': apiToken,
      ...params,
    };
    return Uri.parse(baseUrl).replace(queryParameters: all);
  }
}