import 'package:flutter/material.dart';

import 'loginscreen.dart';

class StudentLoginScreen extends StatelessWidget {
  const StudentLoginScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const LoginScreen(isInstructor: false);
  }
}
