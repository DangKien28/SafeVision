import 'package:flutter/material.dart';

import '../../../../core/utils/permission_handler.dart';
import '../../../../core/error/exceptions.dart';
import '../detection/presentation/pages/detection_page.dart';

/// Splash / permission-gate page.
///
/// Shown at app start.  Requests camera permission then routes to
/// [DetectionPage].  If the permission is denied, shows a clear explanation
/// with a deep-link to device Settings.
class SplashPage extends StatefulWidget {
  const SplashPage({super.key});

  static const routeName = '/';

  @override
  State<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends State<SplashPage> {
  String? _errorMessage;
  bool _requesting = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _requestAndNavigate());
  }

  Future<void> _requestAndNavigate() async {
    if (_requesting) return;
    setState(() {
      _requesting = true;
      _errorMessage = null;
    });

    try {
      await AppPermissionHandler.requestCamera();
      if (mounted) {
        Navigator.of(context).pushReplacementNamed(DetectionPage.routeName);
      }
    } on PermissionException catch (e) {
      if (mounted) setState(() => _errorMessage = e.message);
    } catch (e) {
      if (mounted) setState(() => _errorMessage = e.toString());
    } finally {
      if (mounted) setState(() => _requesting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // App logo
              Image.asset(
                'assets/images/sv_logo.png',
                width: 120,
                height: 120,
                errorBuilder: (_, __, ___) => const Icon(
                  Icons.visibility,
                  size: 100,
                  color: Color(0xFF00E5FF),
                ),
              ),
              const SizedBox(height: 32),
              const Text(
                'SafeVision',
                style: TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 2,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Hỗ trợ người khiếm thị nhận diện vật thể',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 16, color: Colors.white70),
              ),
              const SizedBox(height: 48),

              if (_requesting)
                const CircularProgressIndicator(color: Color(0xFF00E5FF))
              else if (_errorMessage != null) ...[
                const Icon(Icons.camera_alt_outlined,
                    size: 48, color: Colors.orange),
                const SizedBox(height: 16),
                Text(
                  _errorMessage!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.orange, fontSize: 16),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  height: 80,
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.refresh),
                    label: const Text('Thử lại'),
                    onPressed: _requestAndNavigate,
                  ),
                ),
              ] else
                const SizedBox(height: 48),
            ],
          ),
        ),
      ),
    );
  }
}
