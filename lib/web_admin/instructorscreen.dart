import 'package:flutter/material.dart';

import '../loginscreen.dart';

class InstructorLoginScreen extends StatelessWidget {
  const InstructorLoginScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const LoginScreen(isInstructor: true);
  }
}