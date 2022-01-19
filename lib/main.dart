import 'package:flame/flame.dart';
import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:logging/logging.dart';

import 'pong_game.dart';

void main() {
  Logger.root.level = Level.ALL;
  Logger.root.onRecord.listen((r) {
    print('${r.loggerName} ${r.level.name} ${r.time}: ${r.message}');
  });

  WidgetsFlutterBinding.ensureInitialized();
  Flame.device.fullScreen();
  Flame.device.setOrientation(DeviceOrientation.portraitUp);

  final pongGame = PongGame();

  runApp(
    GameWidget(
      game: pongGame,
      overlayBuilderMap: pongGame.overlayMap,
    ),
  );
}
