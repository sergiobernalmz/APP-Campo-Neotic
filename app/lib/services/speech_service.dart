import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:speech_to_text/speech_recognition_error.dart';

/// Resultado de una sesión de escucha.
class SpeechResult {
  final String text;
  final bool isFinal;
  SpeechResult({required this.text, required this.isFinal});
}

/// Estados posibles del servicio de voz.
enum SpeechStatus { notInitialized, ready, listening, stopping, unavailable, permissionDenied }

/// Servicio de reconocimiento de voz (speech_to_text).
///
/// Uso:
///   1. await init()      — pide permiso y prepara el motor (una vez)
///   2. await listen(...) — inicia escucha
///   3. await stop()      — detiene la escucha
class SpeechService {
  final SpeechToText _stt = SpeechToText();
  SpeechStatus status = SpeechStatus.notInitialized;
  String? lastError;

  static const List<String> _preferredLocales = [
    'es_ES', 'ca_ES', 'es-ES', 'ca-ES'
  ];

  /// Inicializa el motor pidiendo permiso de micrófono primero.
  /// Devuelve true si está listo para grabar.
  /// No lanza excepciones: si el motor nativo falla (emulador, sin paquete
  /// de idioma, etc.) devuelve false y deja `status=unavailable`.
  Future<bool> init() async {
    // 1. Pedir permiso de micrófono
    final permStatus = await Permission.microphone.request();
    if (!permStatus.isGranted) {
      status = SpeechStatus.permissionDenied;
      lastError = 'Permiso de micrófono denegado';
      return false;
    }

    // 2. Inicializar speech_to_text
    bool available;
    try {
      available = await _stt.initialize(
        onError: _onError,
        onStatus: _onStatus,
        debugLogging: kDebugMode,
      );
    } on PlatformException catch (e) {
      // Caso típico: emulador sin motor STT, o dispositivo sin paquete
      // de idioma instalado. Antes esto crasheaba la app entera.
      available = false;
      lastError = 'Reconocimiento de voz no disponible (${e.code})';
      if (kDebugMode) {
        debugPrint('SpeechService.init: PlatformException ${e.code}: ${e.message}');
      }
    } catch (e, st) {
      available = false;
      lastError = 'Error inesperado al inicializar voz: $e';
      if (kDebugMode) {
        debugPrint('SpeechService.init: $e\n$st');
      }
    }
    status = available ? SpeechStatus.ready : SpeechStatus.unavailable;
    if (!available && (lastError == null || lastError!.isEmpty)) {
      lastError = 'Reconocimiento de voz no disponible en este dispositivo';
    }
    return available;
  }

  bool get isListening => _stt.isListening;
  bool get isReady => status == SpeechStatus.ready || status == SpeechStatus.stopping;
  bool get isPermissionDenied => status == SpeechStatus.permissionDenied;

  Future<void> listen({
    required void Function(SpeechResult result) onResult,
    List<String> phraseHints = const [],
  }) async {
    if (!isReady) return;
    lastError = null;
    status = SpeechStatus.listening;

    final localeId = await _resolveLocale();

    await _stt.listen(
      onResult: (r) => onResult(SpeechResult(
        text: r.recognizedWords,
        isFinal: r.finalResult,
      )),
      listenOptions: SpeechListenOptions(
        partialResults: true,
        cancelOnError: false,
        listenMode: ListenMode.dictation,
        localeId: localeId,
      ),
    );
  }

  Future<void> stop() async {
    await _stt.stop();
    status = SpeechStatus.ready;
  }

  Future<void> cancel() async {
    await _stt.cancel();
    status = SpeechStatus.ready;
  }

  void _onError(SpeechRecognitionError error) {
    lastError = error.errorMsg;
    status = SpeechStatus.ready;
  }

  void _onStatus(String s) {
    if (s == 'listening') {
      status = SpeechStatus.listening;
    } else if (s == 'notListening' || s == 'done') {
      status = SpeechStatus.ready;
    }
  }

  Future<String?> _resolveLocale() async {
    try {
      final locales = await _stt.locales();
      final available = locales.map((l) => l.localeId).toSet();
      for (final pref in _preferredLocales) {
        if (available.contains(pref)) return pref;
      }
    } catch (_) {}
    return null;
  }
}
