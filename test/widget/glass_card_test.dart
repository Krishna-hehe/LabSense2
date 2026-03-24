import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:clear_health/widgets/glass_card.dart';

void main() {
  testWidgets('GlassCard renders child and handles tap', (
    WidgetTester tester,
  ) async {
    bool tapped = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: GlassCard(
            onTap: () => tapped = true,
            child: const Text('Hello Glass'),
          ),
        ),
      ),
    );

    // Verify child is rendered
    expect(find.text('Hello Glass'), findsOneWidget);

    // Verify tap
    await tester.tap(find.byType(GlassCard));
    expect(tapped, isTrue);
  });

  testWidgets('GlassCard applies correct opacity in light mode', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        themeMode: ThemeMode.light,
        home: Scaffold(body: GlassCard(child: Text('Light Mode'))),
      ),
    );

    final container = tester.widget<Container>(
      find
          .descendant(
            of: find.byType(GlassCard),
            matching: find.byType(Container),
          )
          .first,
    );

    final decoration = container.decoration as BoxDecoration;
    final gradient = decoration.gradient as LinearGradient;

    // Check that we have a gradient and it's not transparent
    expect(gradient.colors.first.a, greaterThan(0));
  });
}
