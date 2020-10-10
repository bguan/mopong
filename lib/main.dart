import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flame/util.dart';

import './mopong-game.dart';

void main() {
  final game = MoPongGame();
  runApp(game.widget);

  final flameUtil = Util();
  flameUtil.fullScreen();
  flameUtil.setOrientation(DeviceOrientation.portraitUp);
}