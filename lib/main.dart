// ignore: import_of_legacy_library_into_null_safe
import 'package:flame/flame.dart';
// ignore: import_of_legacy_library_into_null_safe
import 'package:flame/game.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'constants.dart';
import 'game.dart';

MoPongGame mopongGame = MoPongGame();

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  Flame.device.fullScreen();
  Flame.device.setOrientation(DeviceOrientation.portraitUp);
  runApp(MoPongApp());
}

class MoPongApp extends StatelessWidget {
  Widget mainMenuBuilder(BuildContext buildContext, MoPongGame game) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (mopongGame.topMsg.length > 0)
            Padding(
              padding: EdgeInsets.symmetric(vertical: 20.0),
              child: Text(mopongGame.topMsg),
            ),
          gameButton('Single Player', mopongGame.startSinglePlayer),
          if (!kIsWeb) gameButton('Host Network Game', mopongGame.hostNetGame),
          if (!kIsWeb)
            for (var svcname in mopongGame.pongNetSvc!.serviceNames)
              gameButton('Play $svcname', () => mopongGame.joinNetGame(svcname))
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
            child: Text('Hosting Game as ${mopongGame.gameHostHandle}...'),
          ),
          gameButton('Cancel', mopongGame.stopHosting),
        ],
      ),
    );
  }

  Widget gameButton(String txt, void Function() handler) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 20.0),
      child: SizedBox(
        width: BUTTON_SIZE_RATIO * mopongGame.width,
        child: ElevatedButton(child: Text(txt), onPressed: handler),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GameWidget<MoPongGame>(
      game: mopongGame,
      overlayBuilderMap: {
        MAIN_MENU_OVERLAY_ID: mainMenuBuilder,
        HOST_WAITING_OVERLAY_ID: hostWaitingBuilder,
      },
      initialActiveOverlays: const [MAIN_MENU_OVERLAY_ID],
    );
  }
}
