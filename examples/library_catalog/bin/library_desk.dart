import 'dart:convert';
import 'dart:io';

import 'package:library_catalog/library_catalog.dart';

Future<void> main() async {
  final desk = CheckoutController();
  final bindings = CatalogBindings();
  final branches = <String, BranchPeerServer>{};

  stdout
    ..writeln('Library Checkout Desk')
    ..writeln('Type "help" for commands, "quit" to exit.')
    ..writeln();

  final lines = stdin
      .cast<List<int>>()
      .transform(utf8.decoder)
      .transform(const LineSplitter());
  try {
    await for (final line in lines) {
      final input = line.trim();
      if (input.isEmpty) continue;
      final parts = input.split(RegExp(r'\s+'));
      final command = parts.first.toLowerCase();
      final args = parts.skip(1).toList();

      switch (command) {
        case 'help':
          _printHelp(bindings);
        case 'catalog':
          _printCatalog();
        case 'checkout':
          if (args.isEmpty) {
            stdout.writeln('usage: checkout <isbn>');
          } else {
            desk.checkout(args.first);
            _printDeskState(desk);
          }
        case 'return':
          if (args.isEmpty) {
            stdout.writeln('usage: return <isbn>');
          } else {
            desk.returnLoan(args.first);
            _printDeskState(desk);
          }
        case 'loans':
          _printDeskState(desk, includeEmptyList: true);
        case 'status':
          _printMessages(desk);
        case 'reset':
          desk.reset();
          stdout.writeln('Loan register cleared.');
          _printDeskState(desk);
        case 'peer':
          await _handlePeer(args, branches);
        case 'quit':
        case 'exit':
        case 'q':
          stdout.writeln('Goodbye.');
          await _closeBranches(branches);
          exit(0);
        default:
          stdout.writeln('Unknown command "$command". Type "help".');
      }
      stdout.writeln();
    }
  } finally {
    await _closeBranches(branches);
  }
  stdout.writeln();
}

Future<void> _closeBranches(Map<String, BranchPeerServer> branches) async {
  for (final branch in branches.values) {
    await branch.close();
  }
  branches.clear();
}

Future<void> _handlePeer(
  List<String> args,
  Map<String, BranchPeerServer> branches,
) async {
  final action = args.isEmpty ? 'demo' : args.first.toLowerCase();
  final rest = args.isEmpty ? const <String>[] : args.skip(1).toList();
  try {
    switch (action) {
      case 'demo':
      case 'simulate':
      case 'run':
        await _peerDemo(branches);
      case 'listen':
        if (rest.isEmpty) {
          stdout.writeln('usage: peer listen <branchId>');
          return;
        }
        final id = rest.first;
        if (branches.containsKey(id)) {
          stdout.writeln('Branch "$id" already exists.');
          return;
        }
        final server = BranchPeerServer(id);
        await server.listen();
        branches[id] = server;
        stdout.writeln('Branch "$id" listening on 127.0.0.1:${server.port}');
      case 'connect':
        if (rest.length < 2) {
          stdout.writeln('usage: peer connect <from> <to>');
          return;
        }
        final from = _requireBranch(branches, rest[0]);
        final to = _requireBranch(branches, rest[1]);
        await from.connectTo(to);
        stdout.writeln(
          'Connected ${from.branchId} -> ${to.branchId} '
          '(from=${from.isConnected ? 'connected' : 'disconnected'}, '
          'to=${to.isConnected ? 'connected' : 'disconnected'}).',
        );
      case 'seed':
        if (rest.length < 2) {
          stdout.writeln('usage: peer seed <branchId> <isbn>');
          return;
        }
        final branch = _requireBranch(branches, rest[0]);
        branch.seedLocalLoan(rest[1]);
        stdout.writeln(
          'Branch "${branch.branchId}" local loans: ${branch.localLoans}',
        );
      case 'share':
        if (rest.length < 2) {
          stdout.writeln('usage: peer share <from> <to>');
          return;
        }
        final from = _requireBranch(branches, rest[0]);
        final to = _requireBranch(branches, rest[1]);
        await from.shareLoansWith(to);
        stdout.writeln(
          'Shared ${from.branchId} -> ${to.branchId}. '
          '${to.branchId} received: ${to.peerLoans}',
        );
      case 'status':
        _printPeerStatus(branches);
      case 'loans':
      case 'view':
        if (rest.isEmpty) {
          _printPeerLoans(branches);
        } else {
          final branch = _requireBranch(branches, rest.first);
          _printBranchLoans(branch);
        }
      case 'close':
      case 'down':
        if (rest.isEmpty || rest.first == 'all') {
          if (branches.isEmpty) {
            stdout.writeln('No peer branches to close.');
            return;
          }
          await _closeBranches(branches);
          stdout.writeln('Peer closed.');
          return;
        }
        final branch = _requireBranch(branches, rest.first);
        await branch.close();
        branches.remove(branch.branchId);
        stdout.writeln('Closed branch "${branch.branchId}".');
      default:
        stdout.writeln(
          'Unknown peer action "${args.first}". '
          'Use peer, peer loans, peer status, or peer close.',
        );
    }
  } on Object catch (error) {
    stdout.writeln('peer error: $error');
  }
}

Future<void> _peerDemo(Map<String, BranchPeerServer> branches) async {
  if (branches.isNotEmpty) {
    await _closeBranches(branches);
  }
  stdout.writeln('Simulating branch peer sync (north -> south)...');

  final north = BranchPeerServer('north');
  final south = BranchPeerServer('south');
  branches['north'] = north;
  branches['south'] = south;
  await north.listen();
  await south.listen();
  stdout.writeln('  north listening on 127.0.0.1:${north.port}');
  stdout.writeln('  south listening on 127.0.0.1:${south.port}');

  await north.connectTo(south);
  stdout.writeln('  north connected to south');

  north.seedLocalLoan(validPeerDemoIsbn);
  stdout.writeln('  north local loans: ${north.localLoans}');

  await north.shareLoansWith(south);
  stdout.writeln('  south received: ${south.peerLoans}');

  _printPeerStatus(branches);
  stdout.writeln();
  _printPeerLoans(branches);
  stdout.writeln(
    'Done. View anytime with: peer loans  |  Tear down: peer close',
  );
}

const validPeerDemoIsbn = '9780134685991';

String _describeIsbns(List<String> isbns) {
  if (isbns.isEmpty) return '(none)';
  return isbns
      .map((isbn) {
        final title = CheckoutController.catalogByIsbn[isbn];
        return title == null ? isbn : '$isbn  $title';
      })
      .join('\n    ');
}

void _printBranchLoans(BranchPeerServer branch) {
  stdout.writeln('${branch.branchId}:');
  stdout.writeln('  local loans:');
  stdout.writeln('    ${_describeIsbns(branch.localLoans)}');
  stdout.writeln('  peer loans (received):');
  stdout.writeln('    ${_describeIsbns(branch.peerLoans)}');
}

void _printPeerLoans(Map<String, BranchPeerServer> branches) {
  if (branches.isEmpty) {
    stdout.writeln('No peer branches. Run: peer');
    return;
  }
  for (final branch in branches.values) {
    _printBranchLoans(branch);
  }
}

void _printPeerStatus(Map<String, BranchPeerServer> branches) {
  if (branches.isEmpty) {
    stdout.writeln('No peer branches. Run: peer');
    return;
  }
  for (final branch in branches.values) {
    stdout.writeln(
      '  ${branch.branchId}: '
      'listening=${branch.isListening} port=${branch.port} '
      'connected=${branch.isConnected} '
      'local=${branch.localLoans} peer=${branch.peerLoans}',
    );
  }
}

BranchPeerServer _requireBranch(
  Map<String, BranchPeerServer> branches,
  String id,
) {
  final branch = branches[id];
  if (branch == null) {
    throw StateError('No branch "$id". Create it with: peer listen $id');
  }
  return branch;
}

void _printHelp(CatalogBindings bindings) {
  stdout.writeln('''
Commands:
  help                 Show this help
  catalog              List books available for checkout
  checkout <isbn>      Check out a book via ${bindings.isbnInput.id} + ${bindings.checkoutButton.id}
  return <isbn>        Return an active loan
  loans                Show ${bindings.loanCountDisplay.id} and ${bindings.loanList.id}
  status               Show ${bindings.statusMessage.id} / ${bindings.errorMessage.id}
  reset                Clear the loan register

Peer (loopback TCP, pure dart:io):
  peer                   Simulate north <-> south connect + loan share
  peer loans [branch]    View local + received peer loans (with titles)
  peer status            Show branch peer state
  peer close             Close peer branches
  peer listen/connect/seed/share   Advanced step-by-step control

  quit                 Exit the desk''');
}

void _printCatalog() {
  stdout.writeln('Catalog:');
  final isbns = CheckoutController.catalogByIsbn.keys.toList()..sort();
  for (final isbn in isbns) {
    stdout.writeln('  $isbn  ${CheckoutController.catalogByIsbn[isbn]}');
  }
}

void _printDeskState(CheckoutController desk, {bool includeEmptyList = false}) {
  stdout.writeln(desk.loanCountDisplay);
  _printMessages(desk);
  if (includeEmptyList || desk.loans.isNotEmpty) {
    if (desk.loans.isEmpty) {
      stdout.writeln('(no active loans)');
    } else {
      stdout.writeln(desk.loanList);
    }
  }
}

void _printMessages(CheckoutController desk) {
  if (desk.errorMessage.isNotEmpty) {
    stdout.writeln('error: ${desk.errorMessage}');
  }
  if (desk.statusMessage.isNotEmpty) {
    stdout.writeln(desk.statusMessage);
  }
}
