import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/models.dart';
import 'api_config.dart';

/// Excepciones tipadas lanzadas por [AuthService]. Permiten que la UI
/// muestre mensajes específicos sin parsear strings.
class AuthException implements Exception {
  final String code;
  final String message;

  const AuthException(this.code, this.message);

  @override
  String toString() => 'AuthException($code): $message';
}

/// Servicio de autenticación con Nº socio + PIN contra el backend Apps Script.
/// Persiste sesión en SharedPreferences (local, sin expiración en MVP).
///
/// Para tests, inyectar [client] y [prefs] mockeados.
class AuthService {
  final http.Client client;
  final SharedPreferencesAsync prefs;

  AuthService({http.Client? client, SharedPreferencesAsync? prefs})
      : client = client ?? http.Client(),
        prefs = prefs ?? SharedPreferencesAsync();

  static const _kNumSocio = 'session_numSocio';
  static const _kNombre = 'session_nombre';
  static const _kTimestamp = 'session_timestamp';

  /// Valida [numSocio] + [pin] contra el backend y, si OK, persiste la sesión.
  /// Lanza [AuthException] con códigos:
  /// - socio_not_found: el número no está dado de alta
  /// - socio_inactive: socio existe pero activo=false
  /// - pin_incorrect: PIN no coincide
  /// - network_error: timeout / sin conexión
  /// - server_error: respuesta inesperada
  Future<Socio> login(String numSocio, String pin) async {
    final trimmedSocio = numSocio.trim();
    if (trimmedSocio.isEmpty) {
      throw const AuthException('socio_not_found', 'Número de socio vacío');
    }
    if (pin.isEmpty) {
      throw const AuthException('pin_incorrect', 'PIN vacío');
    }

    final uri = ApiConfig.buildUri({
      'op': 'socios',
      'numSocio': trimmedSocio,
      'pin': pin,
    });

    final http.Response response;
    try {
      response = await client.get(uri).timeout(ApiConfig.timeout);
    } on TimeoutException {
      throw const AuthException(
          'network_timeout', 'Tiempo de espera agotado');
    } on SocketException catch (e) {
      throw AuthException(
          'network_unreachable',
          'Sin conexión al servidor: ${e.message}');
    } catch (e) {
      throw AuthException('network_other', 'Error de red: $e');
    }

    final Map<String, dynamic> body;
    try {
      body = json.decode(response.body) as Map<String, dynamic>;
    } catch (e) {
      throw AuthException('server_error',
          'Respuesta no es JSON válido (status ${response.statusCode})');
    }

    if (body['found'] == false) {
      throw const AuthException(
          'socio_not_found', 'Número de socio no encontrado');
    }

    final socioJson = body['socio'] as Map<String, dynamic>?;
    if (socioJson == null) {
      throw const AuthException(
          'server_error', 'Respuesta sin datos de socio');
    }

    final socio = Socio.fromJson(socioJson);

    if (!socio.activo) {
      throw const AuthException(
          'socio_inactive', 'Tu cuenta está inactiva');
    }

    final pinOk = socioJson['pin_ok'];
    if (pinOk == false) {
      throw const AuthException('pin_incorrect', 'PIN incorrecto');
    }

    await _saveSession(socio);
    return socio;
  }

  /// Devuelve el [Socio] persistido si hay sesión, o null si no la hay.
  /// NO valida contra el backend (la sesión es 100% local en MVP).
  Future<Socio?> checkSession() async {
    final numSocio = await prefs.getString(_kNumSocio);
    final nombre = await prefs.getString(_kNombre);
    if (numSocio == null || numSocio.isEmpty) return null;
    return Socio(
      numSocio: numSocio,
      nombre: nombre ?? '',
      activo: true,
    );
  }

  /// Borra la sesión local.
  Future<void> logout() async {
    await prefs.remove(_kNumSocio);
    await prefs.remove(_kNombre);
    await prefs.remove(_kTimestamp);
  }

  Future<void> _saveSession(Socio socio) async {
    await prefs.setString(_kNumSocio, socio.numSocio);
    await prefs.setString(_kNombre, socio.nombre);
    await prefs.setString(_kTimestamp, DateTime.now().toIso8601String());
  }
}