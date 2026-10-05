import 'dart:io';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:path_provider/path_provider.dart';

/// Información de una versión disponible.
class VersionInfo {
  final String version;
  final String apkUrl;
  final String releaseNotes;
  final bool hayActualizacion;

  const VersionInfo({
    required this.version,
    required this.apkUrl,
    required this.releaseNotes,
    required this.hayActualizacion,
  });
}

/// Servicio de actualizaciones OTA (over-the-air) vía GitHub Releases.
///
/// Flujo:
///   1. checkUpdate() → consulta https://api.github.com/repos/{owner}/{repo}/releases/latest
///   2. Compara `tag_name` con [currentVersion]; si es mayor, hay actualización
///   3. downloadAndInstall() descarga el asset, lo guarda en cache y lanza el instalador
class UpdateService {
  /// Owner del repo en GitHub.
  static const String _repoOwner = 'ElCoronaoV2';
  static const String _repoName = 'APP-Campo-Neotic';

  /// URL del API de releases (público, sin token).
  static const String _releasesApi =
      'https://api.github.com/repos/$_repoOwner/$_repoName/releases/latest';

  /// Versión actual instalada. Debe coincidir con `pubspec.yaml:version`.
  /// La actualiza automáticamente GitHub Actions al crear un release con tag.
  static const String currentVersion = '1.0.8';

  final http.Client client;

  UpdateService({http.Client? client}) : client = client ?? http.Client();

  /// Comprueba si hay una versión más nueva disponible en GitHub Releases.
  /// Devuelve null si no hay conexión, falla la llamada, o el repo no tiene releases.
  Future<VersionInfo?> checkUpdate() async {
    try {
      final response = await client.get(
        Uri.parse(_releasesApi),
        headers: {'Accept': 'application/vnd.github+json'},
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode != 200) return null;

      final data = json.decode(response.body) as Map<String, dynamic>;
      final remoteVersion = (data['tag_name'] as String?)?.replaceFirst('v', '') ?? '';
      final notes = (data['body'] as String?) ?? '';
      if (remoteVersion.isEmpty) return null;

      // Buscar el asset .apk en la release
      final assets = (data['assets'] as List?) ?? const [];
      String? apkUrl;
      for (final a in assets) {
        final name = (a as Map<String, dynamic>)['name'] as String? ?? '';
        if (name.toLowerCase().endsWith('.apk')) {
          apkUrl = a['browser_download_url'] as String?;
          break;
        }
      }
      if (apkUrl == null) return null;

      final hayActualizacion = _isNewerVersion(remoteVersion, currentVersion);
      return VersionInfo(
        version: remoteVersion,
        apkUrl: apkUrl,
        releaseNotes: notes,
        hayActualizacion: hayActualizacion,
      );
    } catch (_) {
      return null;
    }
  }

  /// Descarga el APK desde [apkUrl] y lanza el instalador del sistema.
  Future<bool> downloadAndInstall(String apkUrl,
      {void Function(double progress)? onProgress}) async {
    try {
      final dir = await getTemporaryDirectory();
      final apkFile = File('${dir.path}/voz-campo-update.apk');

      final request = http.Request('GET', Uri.parse(apkUrl));
      final streamed = await client.send(request);
      final total = streamed.contentLength ?? 0;
      var received = 0;
      final sink = apkFile.openWrite();
      await for (final chunk in streamed.stream) {
        sink.add(chunk);
        received += chunk.length;
        if (total > 0) onProgress?.call(received / total);
      }
      await sink.close();

      await _launchInstaller(apkFile.path);
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> _launchInstaller(String filePath) async {
    const channel = MethodChannel('com.vozcampo.voz_campo/installer');
    await channel.invokeMethod('installApk', {'path': filePath});
  }

  bool _isNewerVersion(String remote, String current) {
    final r = _parseVersion(remote);
    final c = _parseVersion(current);
    for (int i = 0; i < 3; i++) {
      if (r[i] > c[i]) return true;
      if (r[i] < c[i]) return false;
    }
    return false;
  }

  List<int> _parseVersion(String v) {
    final parts = v.replaceAll(RegExp(r'[^0-9.]'), '').split('.');
    return List.generate(3, (i) => i < parts.length ? (int.tryParse(parts[i]) ?? 0) : 0);
  }
}
