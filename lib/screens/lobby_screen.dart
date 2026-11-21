import 'dart:async';

import 'package:flutter/material.dart';

import '../domain/domino_lobby.dart';
import '../network/discovered_host.dart';
import '../network/domino_lobby_session.dart';
import '../network/local_discovery.dart';

class LobbyScreen extends StatefulWidget {
  const LobbyScreen({super.key});

  @override
  State<LobbyScreen> createState() => _LobbyScreenState();
}

class _LobbyScreenState extends State<LobbyScreen> {
  final _nameController = TextEditingController();
  final _ipController = TextEditingController();
  final _codeController = TextEditingController();
  final _hostNameController = TextEditingController();
  final _host = DominoLobbyHost(hostName: 'المضيف');
  final _client = DominoLobbyClient();
  final List<DiscoveredHost> _rooms = [];
  Map<String, dynamic>? _remoteLobby;
  bool _hosting = false;
  bool _joining = false;
  bool _ready = false;
  bool _hostReady = true;
  String? _playerId;
  int? _seat;
  String _status = 'أنشئ غرفة أو انضم إلى غرفة موجودة.';

  bool get _isHost => _hosting;
  List<dynamic> get _remotePlayers =>
      (_remoteLobby?['players'] as List<dynamic>?) ?? const [];
  List<LobbyPlayer> get _hostPlayers =>
      _hosting ? _host.lobby.players : const [];
  bool get _hostCanStart => _hosting && _host.lobby.canStart;

  @override
  void initState() {
    super.initState();
    _host.onChanged = () {
      if (mounted) setState(() {});
    };
    _host.onError = _showStatus;
    _host.onGameStarted = (_) => _showStatus('بدأت المباراة. المرحلة التالية: طاولة اللعب.');
    _client.onLobby = (lobby) {
      if (mounted) setState(() => _remoteLobby = lobby);
    };
    _client.onJoined = (id, seat) {
      if (!mounted) return;
      setState(() {
        _playerId = id;
        _seat = seat;
        _status = 'انضممت إلى الغرفة في المقعد ${seat + 1}.';
      });
    };
    _client.onError = _showStatus;
    _client.onDisconnected = () => _showStatus('انقطع الاتصال بالمضيف.');
    _client.onGameStarted = (_) => _showStatus('بدأ المضيف المباراة.');
  }

  void _showStatus(String value) {
    if (mounted) setState(() => _status = value);
  }

  Future<void> _createRoom() async {
    final name = _hostNameController.text.trim();
    if (name.isEmpty) {
      _showStatus('أدخل اسمك أولاً.');
      return;
    }
    try {
      // Recreate the host service with the name chosen in the form.
      await _host.stop();
      final host = DominoLobbyHost(hostName: name);
      host.onChanged = () { if (mounted) setState(() {}); };
      host.onError = _showStatus;
      host.onGameStarted = (_) => _showStatus('بدأت المباراة.');
      await host.start();
      if (!mounted) {
        await host.stop();
        return;
      }
      _activeHost = host;
      setState(() {
        _hosting = true;
        _status = 'الغرفة جاهزة. شارك رمزها مع بقية اللاعبين.';
      });
    } on Object catch (error) {
      _showStatus('تعذر إنشاء الغرفة: $error');
    }
  }

  DominoLobbyHost? _activeHost;

  Future<void> _searchRooms() async {
    setState(() => _joining = true);
    try {
      final found = await LocalDiscovery.discover();
      if (!mounted) return;
      setState(() {
        _rooms
          ..clear()
          ..addAll(found);
        _status = found.isEmpty
            ? 'لم نعثر على غرف. أدخل عنوان IP يدوياً.'
            : 'تم العثور على ${found.length} غرفة.';
      });
    } on Object catch (error) {
      _showStatus('تعذر البحث: $error');
    } finally {
      if (mounted) setState(() => _joining = false);
    }
  }

  Future<void> _joinRoom({String? address, String? code}) async {
    final ip = (address ?? _ipController.text).trim();
    final roomCode = (code ?? _codeController.text).trim();
    final name = _nameController.text.trim();
    if (ip.isEmpty || roomCode.isEmpty || name.isEmpty) {
      _showStatus('أدخل اسم اللاعب وعنوان IP ورمز الغرفة.');
      return;
    }
    setState(() {
      _joining = true;
      _status = 'جارٍ الانضمام إلى الغرفة...';
      _remoteLobby = null;
      _playerId = null;
      _seat = null;
    });
    try {
      await _client.close();
      await _client.connect(
        address: ip,
        roomCode: roomCode,
        playerName: name,
      );
      _showStatus('تم الاتصال. بانتظار قبول طلب الانضمام من المضيف...');
    } on Object catch (error) {
      _showStatus('فشل الاتصال: $error');
    } finally {
      if (mounted) setState(() => _joining = false);
    }
  }

  void _toggleReady(bool value) {
    setState(() => _ready = value);
    _client.setReady(value);
  }

  Future<void> _leave() async {
    await _client.close();
    await _activeHost?.stop();
    _activeHost = null;
    if (!mounted) return;
    setState(() {
      _hosting = false;
      _remoteLobby = null;
      _playerId = null;
      _seat = null;
      _ready = false;
      _hostReady = true;
      _status = 'غادرت الغرفة.';
    });
  }

  @override
  void dispose() {
    _nameController.dispose();
    _ipController.dispose();
    _codeController.dispose();
    _hostNameController.dispose();
    unawaited(_client.close());
    unawaited(_activeHost?.stop());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final active = _hosting || _remoteLobby != null;
    return Scaffold(
      appBar: AppBar(
        title: const Text('غرفة الدومينو'),
        actions: [
          if (active)
            IconButton(
              tooltip: 'مغادرة الغرفة',
              onPressed: _leave,
              icon: const Icon(Icons.exit_to_app),
            ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _statusCard(),
            if (!active) ...[
              _createRoomCard(),
              const SizedBox(height: 12),
              _joinRoomCard(),
            ] else ...[
              _roomDetails(),
              const SizedBox(height: 12),
              _playersCard(),
              const SizedBox(height: 12),
              if (!_isHost)
                SwitchListTile(
                  value: _ready,
                  onChanged: _playerId == null ? null : _toggleReady,
                  title: const Text('أنا مستعد'),
                  subtitle: const Text('أبلغ المضيف عندما تكون جاهزاً.'),
                )
              else
                SwitchListTile(
                  value: _hostReady,
                  onChanged: (value) {
                    setState(() => _hostReady = value);
                    _activeHost?.setHostReady(value);
                  },
                  title: const Text('المضيف مستعد'),
                ),
              if (_isHost)
                FilledButton.icon(
                  onPressed: _hostCanStart
                      ? () {
                          try {
                            _activeHost?.startGame();
                          } on Object catch (error) {
                            _showStatus('$error');
                          }
                        }
                      : null,
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('بدء المباراة'),
                ),
              const SizedBox(height: 8),
              const Text(
                'ملاحظة: هذه غرفة انتظار أولية. بدء المباراة يرسل حدث البداية إلى الأجهزة؛ لم تُربط طاولة اللعب بعد.',
                style: TextStyle(fontSize: 12, color: Colors.black54),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _statusCard() => Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              const Icon(Icons.info_outline),
              const SizedBox(width: 10),
              Expanded(child: Text(_status)),
            ],
          ),
        ),
      );

  Widget _createRoomCard() => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('إنشاء غرفة', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
              const SizedBox(height: 8),
              TextField(
                controller: _hostNameController,
                decoration: const InputDecoration(
                  labelText: 'اسم المضيف',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 10),
              FilledButton.icon(
                onPressed: _hosting ? null : _createRoom,
                icon: const Icon(Icons.add_circle_outline),
                label: const Text('إنشاء غرفة جديدة'),
              ),
            ],
          ),
        ),
      );

  Widget _joinRoomCard() => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('الانضمام إلى غرفة', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
              const SizedBox(height: 8),
              TextField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: 'اسم اللاعب',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: _joining ? null : _searchRooms,
                icon: const Icon(Icons.search),
                label: const Text('البحث عن الغرف القريبة'),
              ),
              if (_rooms.isNotEmpty)
                ..._rooms.map((room) => ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.wifi),
                      title: Text(room.roomName),
                      subtitle: Text('${room.address} • رمز ${room.roomId}'),
                      trailing: IconButton(
                        onPressed: _joining
                            ? null
                            : () {
                                _codeController.text = room.roomId;
                                _ipController.text = room.address;
                                _joinRoom(address: room.address, code: room.roomId);
                              },
                        icon: const Icon(Icons.login),
                      ),
                    )),
              const SizedBox(height: 8),
              TextField(
                controller: _ipController,
                decoration: const InputDecoration(
                  labelText: 'عنوان IP للمضيف',
                  hintText: 'مثال: 192.168.43.1',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _codeController,
                keyboardType: TextInputType.number,
                maxLength: 6,
                decoration: const InputDecoration(
                  labelText: 'رمز الغرفة',
                  border: OutlineInputBorder(),
                  counterText: '',
                ),
              ),
              const SizedBox(height: 8),
              FilledButton(
                onPressed: _joining ? null : () => _joinRoom(),
                child: const Text('انضمام'),
              ),
            ],
          ),
        ),
      );

  Widget _roomDetails() {
    final code = _hosting
        ? _activeHost?.lobby.roomCode ?? '------'
        : (_remoteLobby?['roomCode']?.toString() ?? '------');
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            const Text('رمز الغرفة'),
            const SizedBox(height: 4),
            SelectableText(
              code,
              style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold, letterSpacing: 5),
            ),
            const SizedBox(height: 4),
            const Text('تأكدوا أن الهواتف متصلة بنقطة الاتصال نفسها.'),
          ],
        ),
      ),
    );
  }

  Widget _playersCard() {
    final rows = _hosting
        ? _hostPlayers.map((player) => _playerTile(
              name: player.name,
              seat: player.seat,
              team: player.team,
              ready: player.isReady,
              isHost: player.isHost,
            )).toList()
        : _remotePlayers.map((value) {
            final player = value as Map<String, dynamic>;
            return _playerTile(
              name: player['name']?.toString() ?? 'لاعب',
              seat: player['seat'] as int? ?? 0,
              team: player['team'] as int? ?? 0,
              ready: player['isReady'] == true,
              isHost: player['isHost'] == true,
            );
          }).toList();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('اللاعبون ${rows.length} / 4', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
            const SizedBox(height: 8),
            ...List.generate(4, (seat) {
              final index = rows.indexWhere((widget) {
                // Each occupied tile carries its seat in the key.
                return widget.key == ValueKey<int>(seat);
              });
              return index >= 0
                  ? rows[index]
                  : ListTile(
                      leading: CircleAvatar(child: Text('${seat + 1}')),
                      title: const Text('بانتظار لاعب'),
                      subtitle: Text('الفريق ${seat.isEven ? 1 : 2}'),
                      trailing: const Icon(Icons.hourglass_empty, color: Colors.black38),
                    );
            }),
          ],
        ),
      ),
    );
  }

  Widget _playerTile({
    required String name,
    required int seat,
    required int team,
    required bool ready,
    required bool isHost,
  }) =>
      ListTile(
        key: ValueKey<int>(seat),
        leading: CircleAvatar(child: Text('${seat + 1}')),
        title: Text(name),
        subtitle: Text('الفريق ${team + 1}${isHost ? ' • المضيف' : ''}'),
        trailing: Chip(
          avatar: Icon(
            ready ? Icons.check_circle : Icons.schedule,
            size: 16,
            color: ready ? Colors.green : Colors.black45,
          ),
          label: Text(ready ? 'مستعد' : 'ينتظر'),
        ),
      );
}
