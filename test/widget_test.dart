// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:interviewer/main.dart';

void main() {
  testWidgets('Counter increments smoke test', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const MyApp());

    expect(find.text('采访点 1'), findsOneWidget);
    expect(find.text('未就绪'), findsOneWidget);
    expect(find.text('点击切换状态'), findsOneWidget);

    await tester.tap(find.text('未就绪'));
    await tester.pump();

    expect(find.text('准备中'), findsOneWidget);
    expect(find.text('未就绪'), findsNothing);
  });
}
