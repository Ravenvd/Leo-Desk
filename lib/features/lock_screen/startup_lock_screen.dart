import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

/// A lightweight startup overlay for the Windows desktop app.
///
/// This is an in-app privacy screen, not operating-system authentication.
class StartupLockScreen extends StatefulWidget {
  const StartupLockScreen({
    super.key,
    required this.onUnlock,
  });

  final VoidCallback onUnlock;

  static const password = '2818';

  @override
  State<StartupLockScreen> createState() => _StartupLockScreenState();
}

class _StartupLockScreenState extends State<StartupLockScreen> {
  final _passwordController = TextEditingController();
  String? _errorText;

  @override
  void dispose() {
    _passwordController.dispose();
    super.dispose();
  }

  void _unlock() {
    if (_passwordController.text == StartupLockScreen.password) {
      widget.onUnlock();
      return;
    }

    setState(() {
      _errorText = 'Incorrect password. Please try again.';
      _passwordController.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.sizeOf(context).width;
    final logoWidth = (screenWidth * 0.52).clamp(280.0, 620.0).toDouble();

    return Material(
      color: AppColors.warmIvory,
      child: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 36),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Image.asset(
                    'assets/images/leo_logo.png',
                    width: logoWidth,
                    fit: BoxFit.contain,
                  ),
                  const SizedBox(height: 42),
                  const Text(
                    'Welcome back',
                    style: TextStyle(
                      color: AppColors.darkEspresso,
                      fontSize: 25,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.2,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Enter your password to continue',
                    style: TextStyle(
                      color: AppColors.secondaryText,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 26),
                  SizedBox(
                    width: 320,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        TextField(
                          controller: _passwordController,
                          autofocus: true,
                          obscureText: true,
                          keyboardType: TextInputType.number,
                          textInputAction: TextInputAction.done,
                          textAlign: TextAlign.center,
                          onSubmitted: (_) => _unlock(),
                          onChanged: (_) {
                            if (_errorText != null) {
                              setState(() => _errorText = null);
                            }
                          },
                          decoration: InputDecoration(
                            hintText: 'Password',
                            prefixIcon: const Icon(Icons.lock_outline_rounded),
                            errorText: _errorText,
                          ),
                        ),
                        const SizedBox(height: 16),
                        FilledButton(
                          onPressed: _unlock,
                          child: const Padding(
                            padding: EdgeInsets.symmetric(vertical: 3),
                            child: Text('Unlock'),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 32),
                  const Text(
                    'LEO STITCH & DESIGN',
                    style: TextStyle(
                      color: AppColors.mutedTaupe,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 2.2,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
