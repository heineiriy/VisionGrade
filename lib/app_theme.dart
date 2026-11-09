import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

abstract final class AppPalette {
  static const burgundy = Color(0xFFA44859);
  static const burgundyDark = Color(0xFF3B141A);
  static const rose = Color(0xFFD3A1A6);
  static const cream = Color(0xFFEFE8DE);
  static const background = Colors.white;
  static const ink = Color(0xFF241C1B);
  static const muted = Color(0xFF766C68);
  static const subjectCard = Color(0xFF59151D);
}

class VisionGradeWordmark extends StatelessWidget {
  final double fontSize;
  final bool light;

  const VisionGradeWordmark({
    super.key,
    this.fontSize = 22,
    this.light = false,
  });

  @override
  Widget build(BuildContext context) {
    return RichText(
      text: TextSpan(
        children: [
          TextSpan(
            text: 'Vision',
            style: GoogleFonts.inter(
              color: light ? Colors.white : AppPalette.ink,
              fontSize: fontSize,
              fontWeight: FontWeight.w800,
            ),
          ),
          TextSpan(
            text: 'Grade',
            style: GoogleFonts.brunoAceSc(
              color: light ? const Color(0xFFF0C7C8) : AppPalette.burgundy,
              fontSize: fontSize,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }
}
