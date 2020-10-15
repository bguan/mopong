import 'package:flame/util.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'game.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final flameUtil = Util();
  flameUtil.fullScreen();
  flameUtil.setOrientation(DeviceOrientation.portraitUp);

  final game = MoPong();
  runApp(game.widget);
}
