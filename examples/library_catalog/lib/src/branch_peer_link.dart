import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// One library branch endpoint that accepts peer connections from sibling
/// branches and exchanges loan-register snapshots over a plain TCP socket.
final class BranchPeerServer {
  final String branchId;
  final List<String> localLoans = [];
  final List<String> peerLoans = [];
  ServerSocket? _server;
  Socket? _outbound;
  final _listening = Completer<void>();
  final _connected = Completer<void>();
  final _loanReceived = Completer<void>();

  BranchPeerServer(this.branchId);

  int? get port => _server?.port;
  bool get isListening => _listening.isCompleted;
  bool get isConnected => _connected.isCompleted;

  Future<void> listen() async {
    _server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    _server!.listen((socket) {
      socket.listen(
        (data) => _onMessage(utf8.decode(data)),
        onDone: () {},
        onError: (_) {},
      );
      if (!_connected.isCompleted) _connected.complete();
    });
    if (!_listening.isCompleted) _listening.complete();
  }

  Future<void> connectTo(BranchPeerServer peer) async {
    await _listening.future;
    await peer._listening.future;
    final port = peer.port;
    if (port == null) {
      throw StateError('Peer branch ${peer.branchId} is not listening.');
    }
    final socket = await Socket.connect(InternetAddress.loopbackIPv4, port);
    _outbound = socket;
    socket.listen(
      (data) => _onMessage(utf8.decode(data)),
      onDone: () {},
      onError: (_) {},
    );
    socket.write('HELLO $branchId\n');
    await socket.flush();
    if (!_connected.isCompleted) _connected.complete();
    await peer._connected.future.timeout(const Duration(seconds: 2));
  }

  Future<void> shareLoansWith(BranchPeerServer peer) async {
    final socket = _outbound;
    if (socket == null || !isConnected) {
      throw StateError('Branch $branchId has no active peer connection.');
    }
    socket.write('LOANS ${jsonEncode(localLoans)}\n');
    await socket.flush();
    await peer._loanReceived.future.timeout(
      const Duration(seconds: 2),
      onTimeout: () {},
    );
  }

  void seedLocalLoan(String isbn) {
    if (!localLoans.contains(isbn)) localLoans.add(isbn);
  }

  void _onMessage(String message) {
    for (final line in const LineSplitter().convert(message)) {
      if (line.startsWith('LOANS ')) {
        final decoded = jsonDecode(line.substring(6)) as List<dynamic>;
        peerLoans
          ..clear()
          ..addAll(decoded.cast<String>());
        if (!_loanReceived.isCompleted) _loanReceived.complete();
      }
    }
  }

  Future<void> close() async {
    await _outbound?.close();
    await _server?.close();
    _outbound = null;
    _server = null;
  }
}
