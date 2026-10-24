import 'package:eripoo/design_system/design_system.dart';
import 'package:flutter_test/flutter_test.dart';

/// Activates what [finder] designates as a user would: slides it when it
/// is inside a swipe action (the main "go on" actions), taps it otherwise.
Future<void> activate(WidgetTester tester, Finder finder) async {
  final swipe = find.ancestor(
    of: finder,
    matching: find.byType(EripooSwipeAction),
  );
  if (swipe.evaluate().isEmpty) {
    await tester.tap(finder);
    return;
  }
  final box = tester.getRect(swipe.first);
  final gesture = await tester.startGesture(
    Offset(box.left + 28, box.center.dy),
  );
  for (var i = 0; i < 10; i++) {
    await gesture.moveBy(Offset(box.width / 10, 0));
    await tester.pump();
  }
  await gesture.up();
}
