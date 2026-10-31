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

    return Material(
      color: AppColors.warmIvory,
      child: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            // Keep the complete password form visible on compact desktop
            // windows (including the 800x600 test/default viewport).
            final compact = constraints.maxHeight < 700;
            final heightBasedLogoWidth = constraints.maxHeight * 0.34;
            final desiredLogoWidth = screenWidth * 0.52;
            final logoWidth = (desiredLogoWidth < heightBasedLogoWidth
                    ? desiredLogoWidth
                    : heightBasedLogoWidth)
                .clamp(180.0, 620.0)
                .toDouble();
            final verticalPadding = compact ? 12.0 : 36.0;

            return Center(
              child: SingleChildScrollView(
                padding: EdgeInsets.symmetric(
                  horizontal: 28,
                  vertical: verticalPadding,
                ),
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
                      SizedBox(height: compact ? 20 : 42),
                      Text(
                        'Welcome back',
                        style: TextStyle(
                          color: AppColors.darkEspresso,
                          fontSize: compact ? 23 : 25,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.2,
                        ),
                      ),
                      SizedBox(height: compact ? 6 : 8),
                      const Text(
                        'Enter your password to continue',
                        style: TextStyle(
                          color: AppColors.secondaryText,
                          fontSize: 14,
                        ),
                      ),
                      SizedBox(height: compact ? 18 : 26),
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
                                prefixIcon:
                                    const Icon(Icons.lock_outline_rounded),
                                errorText: _errorText,
                              ),
                            ),
                            SizedBox(height: compact ? 10 : 16),
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
                      SizedBox(height: compact ? 18 : 32),
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
            );
          },
        ),
      ),
    );
  }
}
