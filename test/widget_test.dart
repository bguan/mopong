import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mopong/mopong-game.dart';

void main() {
  testWidgets('MoPongGame test', (WidgetTester tester) async {
    final game = MoPongGame();
    runApp(game.widget);
  });
}
