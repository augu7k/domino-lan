import 'package:flutter/material.dart';

import '../domain/domino_tile.dart';
import '../network/domino_lobby_session.dart';

class DominoGameScreen extends StatefulWidget {
  const DominoGameScreen({required this.seat, this.host, this.client, super.key});
  final int seat;
  final DominoLobbyHost? host;
  final DominoLobbyClient? client;

  @override
  State<DominoGameScreen> createState() => _DominoGameScreenState();
}

class _DominoGameScreenState extends State<DominoGameScreen> {
  Map<String, dynamic>? state;
  List<DominoTile> hand = [];
  DominoTile? selected;
  String? error;

  @override
  void initState() {
    super.initState();
    if (widget.host != null) {
      state = widget.host!.gameSnapshot == null
          ? null
          : Map<String, dynamic>.from(widget.host!.gameSnapshot!);
      hand = widget.host!.hostHand;
      widget.host!.onGameState = (snapshot, tiles) {
        if (mounted) setState(() { state = Map<String, dynamic>.from(snapshot); hand = List.of(tiles); selected = null; error = null; });
      };
    } else {
      state = widget.client!.lastGameState;
      hand = List.of(widget.client!.hand);
      widget.client!.onGameState = (snapshot) { if (mounted) setState(() { state = snapshot; selected = null; }); };
      widget.client!.onHand = (tiles) { if (mounted) setState(() => hand = List.of(tiles)); };
      widget.client!.onError = (message) { if (mounted) setState(() => error = message); };
    }
  }

  @override
  void dispose() {
    if (widget.host != null) widget.host!.onGameState = null;
    if (widget.client != null) {
      widget.client!.onGameState = null;
      widget.client!.onHand = null;
      widget.client!.onError = null;
    }
    super.dispose();
  }

  int get currentSeat => state?['currentSeat'] as int? ?? -1;
  List<dynamic> get board => state?['board'] as List<dynamic>? ?? [];
  List<dynamic> get scores => state?['teamScores'] as List<dynamic>? ?? [0, 0];
  bool get finished => state?['isFinished'] == true;
  bool get myTurn => currentSeat == widget.seat && !finished;

  List<BoardSide> legalSides(DominoTile tile) {
    if (board.isEmpty) return tile == DominoTile(6, 6) ? [BoardSide.right] : [];
    final left = (board.first as Map<String, dynamic>)['leftPip'] as int;
    final right = (board.last as Map<String, dynamic>)['rightPip'] as int;
    return [
      if (tile.matches(left)) BoardSide.left,
      if (tile.matches(right)) BoardSide.right,
    ];
  }

  bool get hasMove => hand.any((tile) => legalSides(tile).isNotEmpty);

  void play(BoardSide side) {
    final tile = selected;
    if (tile == null || !myTurn) return;
    try {
      if (widget.host != null) {
        widget.host!.playHostTile(tile, side);
      } else {
        widget.client!.playTile(tile, side);
      }
      setState(() { selected = null; error = null; });
    } on Object catch (exception) {
      setState(() => error = exception.toString());
    }
  }

  void pass() {
    try {
      if (widget.host != null) {
        widget.host!.passHostTurn();
      } else {
        widget.client!.passTurn();
      }
    } on Object catch (exception) {
      setState(() => error = exception.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final result = state?['result'] as Map<String, dynamic>?;
    return Scaffold(
      appBar: AppBar(title: const Text('مباراة الدومينو')),
      body: ListView(
        padding: const EdgeInsets.all(14),
        children: [
          Card(child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
              Text('الفريق 1: \${scores.isNotEmpty ? scores[0] : 0}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              Text('الفريق 2: \${scores.length > 1 ? scores[1] : 0}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            ]),
          )),
          Card(
            color: const Color(0xFF174E3A),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(children: [
                Text(finished ? 'انتهت الجولة' : myTurn ? 'دورك الآن' : 'دور اللاعب \${currentSeat + 1}', style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                if (board.isEmpty) const Text('ابدأ بحجر 6 | 6', style: TextStyle(color: Colors.white))
                else SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(children: board.map((value) {
                    final item = value as Map<String, dynamic>;
                    return Padding(
                      padding: const EdgeInsets.all(3),
                      child: _tile(item['leftPip'] as int, item['rightPip'] as int, false),
                    );
                  }).toList()),
                ),
              ]),
            ),
          ),
          Card(child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text('أحجارك (\${hand.length})', style: const TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 7,
                runSpacing: 8,
                children: hand.map((tile) => InkWell(
                  onTap: myTurn ? () => setState(() { selected = tile == selected ? null : tile; error = null; }) : null,
                  child: _tile(tile.first, tile.second, tile == selected),
                )).toList(),
              ),
              if (selected != null) ...[
                const SizedBox(height: 10),
                const Text('اختر طرف وضع الحجر', textAlign: TextAlign.center),
                Row(children: [
                  Expanded(child: OutlinedButton(onPressed: legalSides(selected!).contains(BoardSide.left) ? () => play(BoardSide.left) : null, child: const Text('يسار'))),
                  const SizedBox(width: 8),
                  Expanded(child: OutlinedButton(onPressed: legalSides(selected!).contains(BoardSide.right) ? () => play(BoardSide.right) : null, child: const Text('يمين'))),
                ]),
              ],
              OutlinedButton(onPressed: myTurn && !hasMove ? pass : null, child: const Text('تمرير الدور عند عدم وجود حركة')),
            ]),
          )),
          if (error != null) Text(error!, style: const TextStyle(color: Colors.red)),
          if (finished && result != null)
            Card(child: Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                result['winningTeam'] == null ? 'انتهت الجولة بالتعادل' : 'فاز الفريق \${(result['winningTeam'] as int) + 1} • النقاط \${result['pointsAwarded']}',
                textAlign: TextAlign.center,
              ),
            )),
        ],
      ),
    );
  }

  Widget _tile(int first, int second, bool isSelected) => Container(
    width: 64,
    height: 42,
    decoration: BoxDecoration(
      color: isSelected ? const Color(0xFFFFE6A6) : Colors.white,
      border: Border.all(color: isSelected ? const Color(0xFFB8860B) : Colors.black26, width: isSelected ? 2 : 1),
      borderRadius: BorderRadius.circular(7),
    ),
    child: Row(children: [
      Expanded(child: Center(child: Text('$first', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17)))),
      Container(width: 1, color: Colors.black26),
      Expanded(child: Center(child: Text('$second', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17)))),
    ]),
  );
}
