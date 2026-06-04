// Minimal smoke test that does not require Supabase initialization.
// Full auth/flow tests are added alongside their feature phases.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hrm_focus_flutter/app/theme/app_theme.dart';

void main() {
  testWidgets('App theme builds a MaterialApp', (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: const Scaffold(body: Center(child: Text('Focus HRM'))),
      ),
    );
    expect(find.text('Focus HRM'), findsOneWidget);
  });
}
