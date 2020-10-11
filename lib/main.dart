import 'package:flame/util.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import './mopong-game.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  final flameUtil = Util();
  flameUtil.fullScreen();
  flameUtil.setOrientation(DeviceOrientation.portraitUp);

  final game = MoPongGame();
  runApp(game.widget);
}
