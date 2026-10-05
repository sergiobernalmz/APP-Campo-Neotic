import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import 'home_screen.dart';

/// Pantalla de login con Nº socio + PIN. Tamaño de botones ≥56x56dp
/// para uso con guantes en campo (ver `docs/arquitectura.md`).
class LoginScreen extends StatefulWidget {
  final AuthService auth;

  const LoginScreen({super.key, required this.auth});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _numSocioCtrl = TextEditingController();
  final _pinCtrl = TextEditingController();
  bool _loading = false;
  String? _errorMessage;

  @override
  void dispose() {
    _numSocioCtrl.dispose();
    _pinCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _loading = true;
      _errorMessage = null;
    });

    try {
      final socio = await widget.auth.login(
        _numSocioCtrl.text,
        _pinCtrl.text,
      );
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => HomeScreen(socio: socio, auth: widget.auth)),
      );
    } on AuthException catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = _mapError(e.code);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Error inesperado: $e';
      });
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  String _mapError(String code) {
    switch (code) {
      case 'socio_not_found':
        return 'Número de socio no encontrado. Verifica el número.';
      case 'socio_inactive':
        return 'Tu cuenta está inactiva. Contacta al administrador.';
      case 'pin_incorrect':
        return 'PIN incorrecto. Inténtalo de nuevo.';
      case 'network_timeout':
        return 'El servidor tardó demasiado en responder. Reintenta.';
      case 'network_unreachable':
        return 'Sin conexión con el servidor. Verifica que tienes internet.';
      case 'network_other':
        return 'Error de red inesperado. Reintenta en unos segundos.';
      case 'server_error':
        return 'Error del servidor. Inténtalo más tarde.';
      default:
        return 'Error: $code';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: Form(
                key: _formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      'Voz del Campo',
                      style: TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Identifícate para empezar',
                      style: TextStyle(fontSize: 16, color: Colors.black54),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 48),
                    TextFormField(
                      controller: _numSocioCtrl,
                      keyboardType: TextInputType.number,
                      enabled: !_loading,
                      decoration: const InputDecoration(
                        labelText: 'Nº de socio',
                        border: OutlineInputBorder(),
                      ),
                      style: const TextStyle(fontSize: 18),
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) {
                          return 'Introduce tu número de socio';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _pinCtrl,
                      obscureText: true,
                      keyboardType: TextInputType.number,
                      enabled: !_loading,
                      decoration: const InputDecoration(
                        labelText: 'PIN',
                        border: OutlineInputBorder(),
                      ),
                      style: const TextStyle(fontSize: 18),
                      validator: (v) {
                        if (v == null || v.isEmpty) {
                          return 'Introduce tu PIN';
                        }
                        if (v.length < 4) {
                          return 'PIN demasiado corto';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 32),
                    SizedBox(
                      height: 56,
                      child: ElevatedButton(
                        onPressed: _loading ? null : _submit,
                        style: ElevatedButton.styleFrom(
                          textStyle: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        child: _loading
                            ? const SizedBox(
                                width: 24,
                                height: 24,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Text('INICIAR SESIÓN'),
                      ),
                    ),
                    if (_errorMessage != null) ...[
                      const SizedBox(height: 24),
                      Text(
                        _errorMessage!,
                        style: const TextStyle(color: Colors.red, fontSize: 16),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}