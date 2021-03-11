// ignore: import_of_legacy_library_into_null_safe
import 'package:flame/flame.dart';
// ignore: import_of_legacy_library_into_null_safe
import 'package:flame/game.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'constants.dart';
import 'namer.dart';
import 'net.dart';
import 'game.dart';

final String gameHostHandle = genHostHandle();
final PongNetSvc? pongNetSvc =
    kIsWeb ? null : PongNetSvc(gameHostHandle, onDiscovery);
final pongGame = MoPongGame(pongNetSvc);

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  Flame.device.fullScreen();
  Flame.device.setOrientation(DeviceOrientation.portraitUp);
  runApp(MoPongApp());
}

void onDiscovery() {
  pongGame.onDiscovery();
}

class MoPongApp extends StatelessWidget {
  Widget mainMenuBuilder(BuildContext buildContext, MoPongGame game) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (pongGame.topMsg.length > 0)
            Padding(
              padding: EdgeInsets.symmetric(vertical: 20.0),
              child: Text(pongGame.topMsg),
            ),
          gameButton('Single Player', pongGame.startSinglePlayer),
          if (!kIsWeb) gameButton('Host Network Game', pongGame.hostNetGame),
          if (!kIsWeb)
            for (var svc in pongGame.pongNetSvc!.serviceNames)
              gameButton('Play $svc', () => pongGame.joinNetGame(svc))
        ],
      ),
    );
  }

  Widget hostWaitingBuilder(BuildContext buildContext, MoPongGame game) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Padding(
            padding: EdgeInsets.symmetric(vertical: 20.0),
            child: Text('Hosting Game as ${pongGame.gameHostHandle}...'),
          ),
          gameButton('Cancel', pongGame.stopHosting),
        ],
      ),
    );
  }

  Widget gameButton(String txt, void Function() handler) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 20.0),
      child: SizedBox(
        width: BUTTON_SIZE_RATIO * pongGame.width,
        child: ElevatedButton(child: Text(txt), onPressed: handler),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GameWidget<MoPongGame>(
      game: pongGame,
      overlayBuilderMap: {
        MAIN_MENU_OVERLAY_ID: mainMenuBuilder,
        HOST_WAITING_OVERLAY_ID: hostWaitingBuilder,
      },
      initialActiveOverlays: const [MAIN_MENU_OVERLAY_ID],
    );
  }
}
