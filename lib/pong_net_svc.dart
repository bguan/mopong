import 'dart:io';
import 'dart:typed_data';
import 'package:bonsoir/bonsoir.dart';
import 'package:logging/logging.dart';

/// Pong Data to pack and send, or receive and unpack.
///
/// Need to normalize by assuming screen width and height are 0 to 1.
/// Need to flip Y on send as opponent sees it upside down to us.
/// Need to swap myScore and oppoScore on send.
class PongData {
  static const double NORM_FLOAT_BASE = 1000000.0; // express float as fraction

  final int count; // need to be sent as Int64 or underflow may happen
  final double px, bx, by, bvx, bvy;
  final int myScore, oppoScore;
  final double pause;

  PongData(
    this.count,
    this.px,
    this.bx,
    this.by,
    this.bvx,
    this.bvy,
    this.pause,
    this.myScore,
    this.oppoScore,
  );

  static int normFloatToInt(double nf) =>
      (nf.clamp(-1.0, 1.0) * NORM_FLOAT_BASE).round();

  static double normIntToFloat(int ni) =>
      (ni / NORM_FLOAT_BASE).clamp(-1.0, 1.0);

  PongData.fromPayload(Int64List data)
      : count = data[0],
        px = normIntToFloat(data[1]),
        bx = normIntToFloat(data[2]),
        by = normIntToFloat(data[3]),
        bvx = normIntToFloat(data[4]),
        bvy = normIntToFloat(data[5]),
        pause = normIntToFloat(data[6]),
        myScore = data[7],
        oppoScore = data[8];

  Int64List toNetBundle() {
    return Int64List.fromList([
      count,
      normFloatToInt(px),
      normFloatToInt(bx),
      normFloatToInt(by),
      normFloatToInt(bvx),
      normFloatToInt(bvy),
      normFloatToInt(pause),
      oppoScore,
      myScore,
    ]);
  }
}

/// Pong Networking Service for Host and Guest, incl discovery & communication.
class PongNetSvc {
  static const PONG_SVC_TYPE = '_mopong._udp';
  static const PONG_PORT = 13579;

  static final log = Logger("PongNetSvc");

  String myName;
  BonsoirService? _mySvc; // network game I am hosting
  BonsoirBroadcast? _myBroadcast;
  Map<String, ResolvedBonsoirService> _host2svc = {}; // other hosts
  Function _onDiscovery;
  InternetAddress? _oppoAddress;
  RawDatagramSocket? _sock;

  PongNetSvc(this.myName, this._onDiscovery) {
    _scan();
  }

  Iterable<String> get serviceNames => _host2svc.keys;

  void _scan() async {
    BonsoirDiscovery discovery = BonsoirDiscovery(type: PONG_SVC_TYPE);
    await discovery.ready;
    await discovery.start();

    discovery.eventStream?.listen((e) {
      if (e.service != null && e.service!.name.isNotEmpty) {
        if (e.type == BonsoirDiscoveryEventType.DISCOVERY_SERVICE_RESOLVED) {
          log.info("Found service at ${e.service!.name}...");

          if (_mySvc?.name != e.service!.name) {
            _host2svc[e.service!.name] = (e.service) as ResolvedBonsoirService;
            this._onDiscovery();
          }
        } else if (e.type == BonsoirDiscoveryEventType.DISCOVERY_SERVICE_LOST) {
          log.info("Lost service at ${e.service!.name}...");

          _host2svc.remove(e.service!.name);
          this._onDiscovery();
        }
      }
    });
  }

  void startHosting(Function(PongData p) onMsg, Function() onDone) async {
    _safeCloseSocket();
    await _safeStopBroadcast();

    _mySvc = BonsoirService(
      name: myName,
      type: PONG_SVC_TYPE,
      port: PONG_PORT,
    );

    _myBroadcast = BonsoirBroadcast(service: _mySvc!);
    await _myBroadcast?.ready;
    await _myBroadcast?.start();

    _sock = await RawDatagramSocket.bind(InternetAddress.anyIPv4, PONG_PORT);
    log.info("Start Hosting game @ ${_sock!.address} as $myName...");
    _sock!.listen(
      (evt) => _onEvent(onMsg, evt),
      onError: (err) => _finishedHandler(onDone, err),
      onDone: () => _finishedHandler(onDone),
      cancelOnError: true,
    );
  }

  void stopHosting() async {
    log.info("Stop Hosting game as $myName...");
    await _safeStopBroadcast();
    _safeCloseSocket();
  }

  void joinGame(
    String name,
    void Function(PongData) onMsg,
    void Function() onDone,
  ) async {
    log.info("Joining game hosted by $name...");
    final hostSvc = _host2svc[name];
    if (hostSvc != null && hostSvc.ip != null) {
      _oppoAddress = InternetAddress(hostSvc.ip!);
      log.info("Joining net game $name @ $_oppoAddress as $myName...");
      _sock = await RawDatagramSocket.bind(InternetAddress.anyIPv4, PONG_PORT);
      _sock!.listen(
        (evt) => _onEvent(onMsg, evt),
        onError: (err) => _finishedHandler(onDone, err),
        onDone: () => _finishedHandler(onDone),
        cancelOnError: true,
      );
    }
  }

  void leaveGame() {
    log.info("Leaving net game...");
    _safeCloseSocket();
  }

  void send(PongData data) {
    if (_sock != null) {
      _sock!.send(
        data.toNetBundle().buffer.asInt8List(),
        _oppoAddress!,
        PONG_PORT,
      );
    }
  }

  void _onEvent(Function(PongData) onMsg, RawSocketEvent event) {
    if (event == RawSocketEvent.read && _sock != null) {
      final packet = _sock!.receive();
      if (packet == null) return;
      final data = PongData.fromPayload(packet.data.buffer.asInt64List());
      _oppoAddress = packet.address;
      onMsg(data);
    }
  }

  void _finishedHandler(Function() onDone, [Object? e]) {
    if (e != null) log.severe(e);
    log.info("Finishing net game...");
    onDone();
  }

  void _safeCloseSocket() {
    log.info("Closing socket...");
    _sock?.close();
    _sock = null;
  }

  Future<void> _safeStopBroadcast() async {
    log.info("Stopping broadcast...");
    await _myBroadcast?.stop();
    _myBroadcast = null;
    _mySvc = null;
  }
}
