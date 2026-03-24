import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:clear_health/features/home/dashboard_page.dart';
import 'package:clear_health/core/providers.dart';
import 'package:clear_health/core/models.dart';

void main() {
  testWidgets('DashboardPage renders loading state correctly', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          home: DashboardPage(),
        ),
      ),
    );

    // Initial state should render key dashboard shell without crashing.
    expect(find.byType(DashboardPage), findsOneWidget);
    expect(find.textContaining('Welcome back'), findsOneWidget);
  });

  testWidgets('DashboardPage renders summary stats when data loads', skip: true, (
    WidgetTester tester,
  ) async {
    final mockResults = [
      LabReport(
        id: '1',
        date: DateTime.now(),
        labName: 'Lab A',
        testCount: 5,
        abnormalCount: 1,
        status: 'Abnormal',
        testResults: [],
      ),
    ];

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          userProfileProvider.overrideWith(
            (ref) => Future.value({'first_name': 'TestUser'}),
          ),
          recentLabResultsProvider.overrideWith(
            (ref) => Future.value(mockResults),
          ),
          activePrescriptionsCountProvider.overrideWith(
            (ref) => Future.value(2),
          ),
          labResultsProvider.overrideWith(
            () => LabResultsNotifierMock(mockResults),
          ),
        ],
        child: const MaterialApp(
          debugShowCheckedModeBanner: false,
          home: DashboardPage(),
        ),
      ),
    );

    // We need to wait for futures
    await tester.pumpAndSettle();

    expect(find.text('Welcome back, TestUser'), findsOneWidget);
    expect(find.text('Total Lab Reports'), findsOneWidget);
    expect(
      find.text('1'),
      findsOneWidget,
    ); // abnormal count logic might sum it up as 1
  });
}

class LabResultsNotifierMock extends LabResultsNotifier {
  final List<LabReport> _initialData;
  LabResultsNotifierMock(this._initialData);

  @override
  Future<List<LabReport>> build() async {
    return _initialData;
  }
}

