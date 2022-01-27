import 'dart:typed_data';

import 'package:flame/flame.dart';
import 'package:flame/game.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:logging/logging.dart';
import 'package:network_info_plus/network_info_plus.dart';

import 'pong_game.dart';

void main() async {
  Logger.root.level = Level.ALL;
  Logger.root.onRecord.listen((r) {
    print('${r.loggerName} ${r.level.name} ${r.time}: ${r.message}');
  });

  final log = Logger("main");

  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setEnabledSystemUIMode(
    SystemUiMode.manual,
    overlays: [SystemUiOverlay.bottom, SystemUiOverlay.top],
  );
  Flame.device.fullScreen();
  Flame.device.setOrientation(DeviceOrientation.portraitUp);

  final networkInfo = NetworkInfo();

  late final Uint8List addressIPv4;
  if (kIsWeb) {
    addressIPv4 = Uint8List.fromList(const [0, 0, 0, 0]);
  } else {
    try {
      String? wifiName = await networkInfo.getWifiName();
      String? wifiIPv4 = await networkInfo.getWifiIP();
      log.info("Wifi IPv4 address is $wifiIPv4 on ${wifiName ?? 'network'}.");
      addressIPv4 =
          Uint8List.fromList(wifiIPv4!.split("\.").map(int.parse).toList());
    } on Exception catch (e) {
      log.warning('Failed to get Wifi IPv4', e);
      addressIPv4 = Uint8List.fromList(const [0, 0, 0, 0]);
    }
  }

  final pongGame = PongGame(addressIPv4);

  runApp(
    GameWidget(
      game: pongGame,
      overlayBuilderMap: pongGame.overlayMap,
    ),
  );
}
