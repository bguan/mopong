import 'dart:io';
import 'dart:typed_data';

import 'package:bonsoir/bonsoir.dart';

import 'constants.dart';

/// Pong Data to pack and send, or receive and unpack.
///
/// Need to normalize to 256 i.e. byte size, for diff screen width & height.
/// Need to flip Y on send as opponent sees it upside down to us.
/// Need to swap myScore and oppoScore on send.
class PongData {
  final double px, bx, by, bvx, bvy;
  final int sc, osc; // myScore, oppoScore

  PongData(this.px, this.bx, this.by, this.bvx, this.bvy, [this.sc, this.osc]);

  PongData.fromPayload(Uint8List data, double width, double height)
      : px = data != null && data.length >= 1 ? width * data[0] / 256 : null,
        bx = data != null && data.length >= 2 ? width * data[1] / 256 : null,
        by = data != null && data.length >= 3 ? height * data[2] / 256 : null,
        bvx = data != null && data.length >= 4 ? width * data[3] / 256 : null,
        bvy = data != null && data.length >= 5 ? height * data[4] / 256 : null,
        sc = data != null && data.length >= 6 ? data[5] : null,
        osc = data != null && data.length >= 7 ? data[6] : null;

  Uint8List bundle(double width, double height) {
    int padX = 256 * px ~/ width;
    int ballX = 256 * bx ~/ width;
    int ballY = 256 * (height - by) ~/ height;
    int ballVX = 256 * bvx ~/ width;
    int ballVY = 256 * -bvy ~/ height;
    return Uint8List.fromList([padX, ballX, ballY, ballVX, ballVY, osc, sc]);
  }
}

/// Pong Networking Service for Host and Guest, incl discovery & communication.
class PongNetSvc {
  String myName;
  double width, height; // size of my world
  BonsoirService _mySvc = null; // network game I am hosting
  BonsoirBroadcast _myBroadcast = null;
  Map<String, ResolvedBonsoirService> _host2svc = {}; // other hosts
  Function _onDiscovery;
  InternetAddress _oppoAddress = null;
  RawDatagramSocket _sock = null;

  PongNetSvc(this.myName, this._onDiscovery, this.width, this.height) {
    _scan();
  }

  Iterable<String> get serviceNames => _host2svc.keys;

  void _scan() async {
    BonsoirDiscovery discovery = BonsoirDiscovery(type: PONG_SVC_TYPE);
    await discovery.ready;
    await discovery.start();

    discovery.eventStream.listen((e) {
      if (e.type == BonsoirDiscoveryEventType.DISCOVERY_SERVICE_RESOLVED) {
        if (_mySvc?.name != e.service.name) {
          _host2svc[e.service.name] = e.service;
          this._onDiscovery();
        }
      } else if (e.type == BonsoirDiscoveryEventType.DISCOVERY_SERVICE_LOST) {
        _host2svc.remove(e.service.name);
        this._onDiscovery();
      }
    });
  }

  void startHosting(Function(PongData p) onMsg, Function() onDone) async {
    _safeCloseSocket();
    await _safeStopBroadcast();

    _mySvc = BonsoirService(
      name: 'Pong with ${myName}',
      type: PONG_SVC_TYPE,
      port: PONG_PORT,
    );

    _myBroadcast = BonsoirBroadcast(service: _mySvc);
    await _myBroadcast.ready;
    await _myBroadcast.start();

    _sock = await RawDatagramSocket.bind(InternetAddress.anyIPv4, PONG_PORT);
    _sock.listen(
      (evt) => _onEvent(onMsg, evt),
      onError: (err) => _finishedHandler(onDone, err),
      onDone: () => _finishedHandler(onDone),
      cancelOnError: true,
    );
  }

  void stopHosting() async {
    await _safeStopBroadcast();
    _safeCloseSocket();
  }

  void joinGame(String name, Function(PongData) onMsg, Function onDone) async {
    final hostSvc = _host2svc[name];
    _oppoAddress = InternetAddress(hostSvc.ip);
    _sock = await RawDatagramSocket.bind(InternetAddress.anyIPv4, PONG_PORT);
    _sock.listen(
      (evt) => _onEvent(onMsg, evt),
      onError: (err) => _finishedHandler(onDone, err),
      onDone: () => _finishedHandler(onDone),
      cancelOnError: true,
    );
  }

  void leaveGame() {
    _safeCloseSocket();
  }

  void send(PongData data) {
    _sock.send(data.bundle(width, height), _oppoAddress, PONG_PORT);
  }

  void _onEvent(Function(PongData) onMsg, RawSocketEvent event) {
    final packet = _sock?.receive();
    if (packet == null) return;
    final data = PongData.fromPayload(packet.data, width, height);
    if (data.px == null) return; // bad data packet?
    _oppoAddress = packet.address;
    onMsg(data);
  }

  void _finishedHandler(Function() onDone, [Object e = null]) {
    if (e != null) print(e);
    onDone();
  }

  void _safeCloseSocket() {
    if (_sock != null) {
      _sock.close();
      _sock = null;
    }
  }

  void _safeStopBroadcast() async {
    if (_myBroadcast != null) {
       await _myBroadcast.stop();
      _myBroadcast = null;
    }
    if (_mySvc != null)_mySvc = null;
  }
}
