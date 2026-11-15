import 'package:flutter/material.dart';

import '../../../core/config/brand_constants.dart';
import '../../../design.dart';

class SplashView extends StatelessWidget {
  const SplashView({super.key, this.failed = false, this.errorText});

  final bool failed;
  final String? errorText;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: navy,
      body: SafeArea(
        child: Stack(
          children: [
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 28),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 112,
                      height: 112,
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: .08),
                        borderRadius: BorderRadius.circular(32),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: .12),
                        ),
                      ),
                      child: Image.asset(
                        'assets/brand/poche-mark.png',
                        fit: BoxFit.contain,
                        filterQuality: FilterQuality.medium,
                      ),
                    ),
                    const SizedBox(height: 22),
                    const Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: 'Poche',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 34,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          TextSpan(
                            text: 'Nette',
                            style: TextStyle(
                              color: mint,
                              fontSize: 34,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      failed
                          ? (errorText ?? 'Impossible de charger les données.')
                          : 'Ton argent, clairement.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: failed ? const Color(0xffffb4c0) : mint,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (!failed) ...[
                      const SizedBox(height: 28),
                      const SizedBox(
                        width: 28,
                        height: 28,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.6,
                          color: mint,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 28,
              child: Column(
                children: [
                  Text(
                    'par ${BrandConstants.publisherName}',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: .72),
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.3,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    BrandConstants.publisherHost,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: mint.withValues(alpha: .9),
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
