import 'package:flutter_test/flutter_test.dart';
import 'package:InstructorMate/main.dart';

void main() {
  testWidgets('App builds without crashing', (WidgetTester tester) async {
    await tester.pumpWidget(const SyllabusApp());
    await tester.pump();

    // If the app bar title exists, this confirms the UI built.
    expect(find.text("Syllabus Q&A (Convert + Ask)"), findsOneWidget);
  });
}
