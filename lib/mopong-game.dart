import 'dart:ui';

import 'package:flame/game.dart';
import 'package:flame/gestures.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

class MoPongGame extends Game with TapDetector {
  Size screenSize;
  bool hasWon = false;

  void resize(Size size) {
    super.resize(size);
    screenSize = size;
  }

  void render(Canvas canvas) {
    final bgRect = Rect.fromLTWH(0, 0, screenSize.width, screenSize.height);
    final bgPaint = Paint();
    bgPaint.color = Colors.black;
    canvas.drawRect(bgRect, bgPaint);
    double screenCenterX = screenSize.width / 2;
    double screenCenterY = screenSize.height / 2;
    final boxRect = Rect.fromLTWH(
      screenCenterX - 75,
      screenCenterY - 75,
      150,
      150
    );
    Paint boxPaint = Paint();
    if (hasWon) {
      boxPaint.color = Colors.green;
    } else {
      boxPaint.color = Colors.white;
    }
    canvas.drawRect(boxRect, boxPaint);
  }

  void onTapDown(TapDownDetails d) {
    double screenCenterX = screenSize.width / 2;
    double screenCenterY = screenSize.height / 2;
    if (d.globalPosition.dx >= screenCenterX - 75
      && d.globalPosition.dx <= screenCenterX + 75
      && d.globalPosition.dy >= screenCenterY - 75
      && d.globalPosition.dy <= screenCenterY + 75
    ) {
      hasWon = true;
    }
  }
  
  void update(double t) {}
}
