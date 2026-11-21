import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';

import '../network/discovered_host.dart';
import '../network/local_discovery.dart';
import '../network/local_discovery_host.dart';
import '../network/local_web_socket.dart';

class ConnectionTestScreen extends StatefulWidget {
  const ConnectionTestScreen({super.key});

  @override
  State<ConnectionTestScreen> createState() => _ConnectionTestScreenState();
}

class _ConnectionTestScreenState extends State<ConnectionTestScreen> {
  final TextEditingController _ipController = TextEditingController();
  final List<String> _logs = <String>[];
  final List<DiscoveredHost> _hosts = <DiscoveredHost>[];

  LocalWebSocketHost? _hostServer;
  LocalDiscoveryHost? _discoveryHost;
  LocalWebSocketClient? _client;
  StreamSubscription<dynamic>? _clientMessages;
  bool _isHosting = false;
  bool _isSearching = false;
  bool _isConnecting = false;
  int _connectedClients = 0;
  String _status = 'لم يبدأ الاتصال';

  void _log(String message) {
    if (!mounted) return;
    setState(() {
      _logs.insert(0, '${DateTime.now().toLocal().toString().substring(11, 19)}  $message');
      if (_logs.length > 40) _logs.removeLast();
    });
  }

  Future<void> _startHost() async {
    if (_isHosting) return;
    setState(() => _status = 'جارٍ تشغيل خادم الاختبار...');
    try {
      final server = LocalWebSocketHost(port: 40405);
      server.onClientConnected = (_) {
        if (mounted) setState(() => _connectedClients = server.connectedClients);
        _log('اتصل جهاز جديد بالمضيف');
      };
      server.onClientDisconnected = (_) {
        if (mounted) setState(() => _connectedClients = server.connectedClients);
        _log('انقطع اتصال أحد الأجهزة');
      };
      server.onMessage = (client, message) {
        try {
          final decoded = jsonDecode(message.toString());
          if (decoded is Map<String, dynamic> && decoded['type'] == 'ping') {
            server.sendTo(client, <String, Object?>{
              'v': 1,
              'type': 'pong',
              'payload': <String, Object?>{'receivedAt': DateTime.now().toIso8601String()},
            });
            _log('استقبل المضيف اختباراً وأرسل رداً');
          }
        } on FormatException {
          _log('وصلت رسالة غير مفهومة');
        }
      };
      await server.start();

      final discovery = LocalDiscoveryHost(
        roomId: 'test-${DateTime.now().millisecondsSinceEpoch}',
        roomName: 'اختبار دومينو الشبكة',
      );
      await discovery.start();

      if (!mounted) {
        await discovery.stop();
        await server.stop();
        return;
      }
      setState(() {
        _hostServer = server;
        _discoveryHost = discovery;
        _isHosting = true;
        _status = 'المضيف يعمل — بانتظار اتصالات الأجهزة';
      });
      _log('بدأ المضيف على المنفذ 40405');
      _log('خدمة اكتشاف الغرفة تعمل على المنفذ 40406');
    } on Object catch (error) {
      if (mounted) setState(() => _status = 'تعذر تشغيل المضيف');
      _log('خطأ تشغيل المضيف: $error');
    }
  }

  Future<void> _searchHosts() async {
    if (_isSearching) return;
    setState(() => _isSearching = true);
    try {
      final hosts = await LocalDiscovery.discover();
      if (!mounted) return;
      setState(() {
        _hosts
          ..clear()
          ..addAll(hosts);
      });
      _status = hosts.isEmpty ? 'لم يتم العثور على غرفة؛ جرّب إدخال IP يدوياً' : 'تم العثور على ${hosts.length} غرفة';
      _log(_status);
    } on Object catch (error) {
      _log('تعذر البحث عن الغرف: $error');
    } finally {
      if (mounted) setState(() => _isSearching = false);
    }
  }

  Future<void> _connect({String? address, int port = 40405}) async {
    final target = (address ?? _ipController.text).trim();
    if (target.isEmpty || _isConnecting) return;
    setState(() {
      _isConnecting = true;
      _status = 'جارٍ الاتصال بـ $target...';
    });
    try {
      await _clientMessages?.cancel();
      await _client?.close();
      final client = await LocalWebSocketClient.connect(host: target, port: port);
      if (!mounted) {
        await client.close();
        return;
      }
      _client = client;
      _clientMessages = client.messages.listen(
        (message) {
          try {
            final decoded = jsonDecode(message.toString());
            if (decoded is Map<String, dynamic> && decoded['type'] == 'pong') {
              _log('وصل رد المضيف — الاتصال يعمل');
              if (mounted) setState(() => _status = 'متصل بالمضيف $target');
            } else {
              _log('وصلت رسالة من المضيف');
            }
          } on FormatException {
            _log('وصلت بيانات غير مفهومة');
          }
        },
        onDone: () {
          if (mounted) setState(() => _status = 'انقطع الاتصال بالمضيف');
          _log('أغلق المضيف الاتصال');
        },
        onError: (Object error) => _log('خطأ في الاتصال: $error'),
      );
      setState(() => _status = 'اتصلت بالمضيف؛ اضغط اختبار الاتصال');
      _log('تم فتح اتصال WebSocket مع $target');
    } on Object catch (error) {
      if (mounted) setState(() => _status = 'فشل الاتصال بالمضيف');
      _log('فشل الاتصال: $error');
    } finally {
      if (mounted) setState(() => _isConnecting = false);
    }
  }

  void _sendPing() {
    final client = _client;
    if (client == null || !client.isConnected) {
      _log('لا يوجد اتصال نشط لإجراء الاختبار');
      return;
    }
    client.send(<String, Object?>{
      'v': 1,
      'type': 'ping',
      'payload': <String, Object?>{'sentAt': DateTime.now().toIso8601String()},
    });
    _log('أُرسل طلب اختبار إلى المضيف');
  }

  Future<void> _stopAll() async {
    await _clientMessages?.cancel();
    _clientMessages = null;
    await _client?.close();
    _client = null;
    await _discoveryHost?.stop();
    _discoveryHost = null;
    await _hostServer?.stop();
    _hostServer = null;
  }

  @override
  void dispose() {
    _ipController.dispose();
    unawaited(_stopAll());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('اختبار الاتصال المحلي')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('حالة الشبكة', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Icon(_isHosting ? Icons.wifi_tethering : Icons.wifi, color: _isHosting ? Colors.green : Colors.black54),
                        const SizedBox(width: 8),
                        Expanded(child: Text(_status)),
                      ],
                    ),
                    if (_isHosting) ...[
                      const SizedBox(height: 8),
                      Text('الأجهزة المتصلة: $_connectedClients / 3'),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            const Text('على هاتف المضيف', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            FilledButton.icon(
              onPressed: _isHosting ? null : _startHost,
              icon: const Icon(Icons.wifi_tethering),
              label: const Text('تشغيل المضيف وخدمة اكتشاف الغرفة'),
            ),
            const SizedBox(height: 16),
            const Text('على هاتف اللاعب', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            OutlinedButton.icon(
              onPressed: _isSearching ? null : _searchHosts,
              icon: _isSearching
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.search),
              label: const Text('البحث عن المضيفين في الشبكة'),
            ),
            if (_hosts.isNotEmpty) ...[
              const SizedBox(height: 8),
              ..._hosts.map((host) => Card(
                    child: ListTile(
                      leading: const Icon(Icons.meeting_room_outlined),
                      title: Text(host.roomName),
                      subtitle: Text('${host.address}:${host.port}'),
                      trailing: IconButton(
                        tooltip: 'اتصال',
                        onPressed: _isConnecting ? null : () => _connect(address: host.address, port: host.port),
                        icon: const Icon(Icons.link),
                      ),
                    ),
                  )),
            ],
            const SizedBox(height: 8),
            TextField(
              controller: _ipController,
              keyboardType: TextInputType.text,
              decoration: InputDecoration(
                labelText: 'عنوان IP للمضيف',
                hintText: 'مثال: 192.168.43.1',
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  tooltip: 'اتصال بالعنوان',
                  onPressed: _isConnecting ? null : () => _connect(),
                  icon: const Icon(Icons.link),
                ),
              ),
            ),
            const SizedBox(height: 8),
            FilledButton.tonalIcon(
              onPressed: _client?.isConnected == true ? _sendPing : null,
              icon: const Icon(Icons.network_ping),
              label: const Text('اختبار إرسال واستقبال البيانات'),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                const Expanded(child: Text('سجل الاختبار', style: TextStyle(fontWeight: FontWeight.bold))),
                TextButton(
                  onPressed: () => setState(_logs.clear),
                  child: const Text('مسح'),
                ),
              ],
            ),
            Container(
              constraints: const BoxConstraints(minHeight: 90, maxHeight: 230),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFE9EEEA),
                borderRadius: BorderRadius.circular(12),
              ),
              child: _logs.isEmpty
                  ? const Text('ستظهر أحداث الاتصال هنا.', style: TextStyle(color: Colors.black54))
                  : ListView.builder(
                      shrinkWrap: true,
                      itemCount: _logs.length,
                      itemBuilder: (context, index) => Padding(
                        padding: const EdgeInsets.only(bottom: 5),
                        child: Text(_logs[index], style: const TextStyle(fontSize: 12)),
                      ),
                    ),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _isHosting || _client != null ? () async {
                await _stopAll();
                if (mounted) {
                  setState(() {
                    _isHosting = false;
                    _connectedClients = 0;
                    _status = 'تم إيقاف الاتصال';
                  });
                }
                _log('تم إيقاف خدمات الاتصال');
              } : null,
              icon: const Icon(Icons.stop_circle_outlined),
              label: const Text('إيقاف الاتصال'),
            ),
            const SizedBox(height: 8),
            const Text(
              'ملاحظة: هذه شاشة اختبار للنقل المحلي فقط، وليست غرفة لعبة مكتملة. يلزم اختبارها على أجهزة فعلية؛ وقد لا يعمل اكتشاف UDP في بعض نقاط الاتصال، وعندها استخدم عنوان IP يدوياً.',
              style: TextStyle(fontSize: 12, color: Colors.black54),
            ),
          ],
        ),
      ),
    );
  }
}
