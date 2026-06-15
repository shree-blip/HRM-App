import 'dart:ui';

import 'package:flutter/material.dart';

import '../../../../app/theme/app_theme.dart';

/// Premium glassmorphism design system for the auth flow (Login, Sign Up,
/// Forgot Password). Presentation-only — these widgets hold NO auth/business
/// logic. The look: a deep teal-navy aurora backdrop with soft brand light
/// blooms, frosted glass cards with real backdrop blur, a gold→cyan brand
/// ring, translucent glass inputs and a glowing gradient CTA.

// ── Auth palette (visual only) ───────────────────────────────────────────
const _teal = AppColors.primary; // brand teal
const _cyan = AppColors.primaryDark; // bright cyan accent
const _gold = Color(0xFFD9A441); // logo gold ring accent
const _bgTop = Color(0xFF0B2531);
const _bgMid = Color(0xFF0E3C4B);
const _bgBottom = Color(0xFF06161E);
const _glassStroke = Color(0x2EFFFFFF); // white @ ~18%
const _onGlass = Colors.white;
const _onGlassMuted = Color(0xB3FFFFFF); // white @ 70%
const _onGlassFaint = Color(0x80FFFFFF); // white @ 50%

/// Aurora backdrop: deep gradient + soft, blurred brand light blooms.
class AuthGradientBackground extends StatelessWidget {
  const AuthGradientBackground({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    // StackFit.expand makes the gradient (and the content) fill the whole
    // viewport, so no background gap appears below short / scrollable content.
    return Stack(
      fit: StackFit.expand,
      children: [
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [_bgTop, _bgMid, _bgBottom],
            ),
          ),
        ),
        _bloom(top: -110, left: -90, size: 300, color: _cyan, opacity: 0.40),
        _bloom(top: 120, right: -120, size: 280, color: _gold, opacity: 0.22),
        _bloom(bottom: -120, left: -60, size: 340, color: _teal, opacity: 0.45),
        child,
      ],
    );
  }

  Widget _bloom({
    double? top,
    double? bottom,
    double? left,
    double? right,
    required double size,
    required Color color,
    required double opacity,
  }) {
    return Positioned(
      top: top,
      bottom: bottom,
      left: left,
      right: right,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [color.withValues(alpha: opacity), color.withValues(alpha: 0)],
          ),
        ),
      ),
    );
  }
}

/// Logo inside a gold→cyan gradient ring on a dark glass disc + wordmark.
class AuthBrandMark extends StatelessWidget {
  const AuthBrandMark({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: 96,
          height: 96,
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: const SweepGradient(
              colors: [_gold, _cyan, _teal, _gold],
            ),
            boxShadow: [
              BoxShadow(
                color: _cyan.withValues(alpha: 0.45),
                blurRadius: 30,
                spreadRadius: -4,
              ),
            ],
          ),
          child: Container(
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: _bgTop,
            ),
            padding: const EdgeInsets.all(16),
            child: Image.asset('assets/images/focus-logo.png'),
          ),
        ),
        const SizedBox(height: 18),
        const Text(
          'FOCUS',
          style: TextStyle(
            color: _onGlass,
            fontSize: 30,
            fontWeight: FontWeight.w700,
            letterSpacing: 6,
          ),
        ),
        const SizedBox(height: 6),
        const Text(
          'HUMAN RESOURCE MANAGEMENT',
          style: TextStyle(
            color: _onGlassFaint,
            fontSize: 11,
            letterSpacing: 2.4,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

/// Frosted glass card with real backdrop blur and a soft brand glow.
class AuthCard extends StatelessWidget {
  const AuthCard({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.40),
            blurRadius: 40,
            spreadRadius: -10,
            offset: const Offset(0, 24),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(28),
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0x1FFFFFFF), Color(0x0FFFFFFF)],
              ),
              border: Border.all(color: _glassStroke),
            ),
            padding: const EdgeInsets.fromLTRB(22, 26, 22, 26),
            child: child,
          ),
        ),
      ),
    );
  }
}

/// Card heading + supporting line, styled for the glass surface.
class AuthHeading extends StatelessWidget {
  const AuthHeading({required this.title, required this.subtitle, super.key});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w700,
            color: _onGlass,
            letterSpacing: 0.2,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          subtitle,
          style: const TextStyle(
            fontSize: 13.5,
            height: 1.35,
            color: _onGlassMuted,
          ),
        ),
      ],
    );
  }
}

/// Glass pill switch with a glowing gradient active segment.
class AuthSegmentedSwitch extends StatelessWidget {
  const AuthSegmentedSwitch({
    required this.index,
    required this.labels,
    required this.onChanged,
    super.key,
  });

  final int index;
  final List<String> labels;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(5),
      decoration: BoxDecoration(
        color: const Color(0x12FFFFFF),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0x1AFFFFFF)),
      ),
      child: Row(
        children: [
          for (var i = 0; i < labels.length; i++)
            Expanded(
              child: GestureDetector(
                onTap: () => onChanged(i),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 240),
                  curve: Curves.easeOut,
                  height: 46,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    gradient: i == index
                        ? const LinearGradient(colors: [_teal, _cyan])
                        : null,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: i == index
                        ? [
                            BoxShadow(
                              color: _cyan.withValues(alpha: 0.45),
                              blurRadius: 16,
                              offset: const Offset(0, 6),
                            ),
                          ]
                        : null,
                  ),
                  child: Text(
                    labels[i],
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: i == index ? _onGlass : _onGlassMuted,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Translucent glass text field. Forwards controller/validator/keyboard so the
/// caller keeps full control — only the look is centralised.
class AuthTextField extends StatelessWidget {
  const AuthTextField({
    required this.controller,
    required this.label,
    this.hint,
    this.icon,
    this.suffix,
    this.obscureText = false,
    this.readOnly = false,
    this.keyboardType,
    this.autofillHints,
    this.validator,
    this.onFieldSubmitted,
    this.errorText,
    this.helperText,
    this.helperMaxLines,
    super.key,
  });

  final TextEditingController controller;
  final String label;
  final String? hint;
  final IconData? icon;
  final Widget? suffix;
  final bool obscureText;
  final bool readOnly;
  final TextInputType? keyboardType;
  final List<String>? autofillHints;
  final String? Function(String?)? validator;
  final void Function(String)? onFieldSubmitted;
  final String? errorText;
  final String? helperText;
  final int? helperMaxLines;

  OutlineInputBorder _border(Color color, [double width = 1]) =>
      OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: color, width: width),
      );

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      obscureText: obscureText,
      readOnly: readOnly,
      keyboardType: keyboardType,
      autofillHints: autofillHints,
      validator: validator,
      onFieldSubmitted: onFieldSubmitted,
      cursorColor: _cyan,
      style: const TextStyle(color: _onGlass, fontSize: 15.5),
      decoration: InputDecoration(
        filled: true,
        fillColor: const Color(0x12FFFFFF),
        labelText: label,
        labelStyle: const TextStyle(color: _onGlassMuted),
        floatingLabelStyle: const TextStyle(color: _cyan),
        hintText: hint,
        hintStyle: const TextStyle(color: _onGlassFaint),
        prefixIcon: icon == null ? null : Icon(icon, color: _onGlassMuted),
        // Keep explicit-coloured suffix icons (check/error/spinner) as-is, but
        // tint plain icons (e.g. the password visibility toggle) for contrast.
        suffixIcon: suffix == null
            ? null
            : IconTheme.merge(
                data: const IconThemeData(color: _onGlassMuted),
                child: suffix!,
              ),
        errorText: errorText,
        errorStyle: const TextStyle(color: Color(0xFFFF8A8A)),
        helperText: helperText,
        helperStyle: const TextStyle(color: _onGlassFaint),
        helperMaxLines: helperMaxLines,
        enabledBorder: _border(_glassStroke),
        border: _border(_glassStroke),
        focusedBorder: _border(_cyan, 1.6),
        errorBorder: _border(const Color(0xFFFF8A8A)),
        focusedErrorBorder: _border(const Color(0xFFFF8A8A), 1.6),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
      ),
    );
  }
}

/// Full-width glowing gradient CTA with an integrated loading state.
class AuthPrimaryButton extends StatelessWidget {
  const AuthPrimaryButton({
    required this.label,
    required this.busy,
    required this.onPressed,
    super.key,
  });

  final String label;
  final bool busy;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null && !busy;
    return Opacity(
      opacity: enabled || busy ? 1 : 0.5,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: busy ? null : onPressed,
          child: Ink(
            height: 54,
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [_teal, _cyan]),
              borderRadius: BorderRadius.circular(14),
              boxShadow: enabled
                  ? [
                      BoxShadow(
                        color: _cyan.withValues(alpha: 0.45),
                        blurRadius: 18,
                        offset: const Offset(0, 8),
                      ),
                    ]
                  : null,
            ),
            child: Center(
              child: busy
                  ? const SizedBox(
                      height: 22,
                      width: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.4,
                        color: Colors.white,
                      ),
                    )
                  : Text(
                      label,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.3,
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Outlined glass button (e.g. "Continue with Google").
class AuthOutlineButton extends StatelessWidget {
  const AuthOutlineButton({
    required this.label,
    required this.icon,
    required this.onPressed,
    super.key,
  });

  final String label;
  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onPressed,
        child: Container(
          height: 52,
          decoration: BoxDecoration(
            color: const Color(0x0AFFFFFF),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: _glassStroke),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: _onGlass, size: 24),
              const SizedBox(width: 8),
              Text(
                label,
                style: const TextStyle(
                  color: _onGlass,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Subtle "or" divider for the glass surface.
class AuthOrDivider extends StatelessWidget {
  const AuthOrDivider({super.key});

  @override
  Widget build(BuildContext context) {
    return const Row(
      children: [
        Expanded(child: Divider(color: _glassStroke)),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: 12),
          child: Text('or', style: TextStyle(color: _onGlassFaint, fontSize: 12.5)),
        ),
        Expanded(child: Divider(color: _glassStroke)),
      ],
    );
  }
}

/// Light-on-glass text button (links like "Forgot password?" / "Back to Login").
class AuthLinkButton extends StatelessWidget {
  const AuthLinkButton({required this.label, required this.onPressed, super.key});

  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(foregroundColor: _cyan),
      child: Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
    );
  }
}

/// Inline message banner for professional error/success feedback on glass.
class AuthMessage extends StatelessWidget {
  const AuthMessage({required this.text, this.isError = true, super.key});

  final String text;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    final color = isError ? const Color(0xFFFF8A8A) : const Color(0xFF6EE7B7);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.40)),
      ),
      child: Row(
        children: [
          Icon(
            isError ? Icons.error_outline : Icons.check_circle_outline,
            color: color,
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: color,
                fontSize: 13,
                height: 1.3,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Circular glass icon badge used as a focal accent (e.g. reset / sent states).
class AuthIconBadge extends StatelessWidget {
  const AuthIconBadge({required this.icon, this.accent = _cyan, super.key});

  final IconData icon;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 64,
      height: 64,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: accent.withValues(alpha: 0.16),
        border: Border.all(color: accent.withValues(alpha: 0.40)),
      ),
      child: Icon(icon, size: 32, color: accent),
    );
  }
}

/// Floating, rounded snackbar styling for transient auth feedback. Keeps the
/// existing ScaffoldMessenger flow — only the presentation is upgraded.
void showAuthSnack(BuildContext context, String message, {bool isError = true}) {
  final color = isError ? const Color(0xFFFF8A8A) : const Color(0xFF6EE7B7);
  ScaffoldMessenger.of(context)
    ..clearSnackBars()
    ..showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: const Color(0xFF0E2A36),
        elevation: 8,
        margin: const EdgeInsets.all(16),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: color.withValues(alpha: 0.40)),
        ),
        content: Row(
          children: [
            Icon(
              isError ? Icons.error_outline : Icons.check_circle_outline,
              color: color,
              size: 20,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(color: Colors.white, fontSize: 13.5),
              ),
            ),
          ],
        ),
      ),
    );
}
