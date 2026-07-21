import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../palette.dart';

/// One finished clap session, frozen for posterity.
class SessionRecord {
  const SessionRecord({
    required this.endedAt,
    required this.claps,
    required this.peakRate,
    required this.durationSecs,
  });

  factory SessionRecord.fromJson(Map<String, dynamic> json) => SessionRecord(
    endedAt: DateTime.fromMillisecondsSinceEpoch(json['endedAt'] as int),
    claps: json['claps'] as int,
    peakRate: (json['peakRate'] as num).toDouble(),
    durationSecs: json['durationSecs'] as int,
  );

  final DateTime endedAt;
  final int claps;
  final double peakRate;
  final int durationSecs;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'endedAt': endedAt.millisecondsSinceEpoch,
    'claps': claps,
    'peakRate': peakRate,
    'durationSecs': durationSecs,
  };
}

/// Persists session records as a JSON list in SharedPreferences.
class HistoryStore {
  HistoryStore(this._prefs);

  static const _key = 'sessionHistory';
  static const _maxRecords = 200;

  final SharedPreferences _prefs;

  /// All saved sessions, newest first. Corrupt data comes back empty.
  List<SessionRecord> load() {
    final raw = _prefs.getString(_key);
    if (raw == null || raw.isEmpty) return [];
    try {
      final decoded = jsonDecode(raw) as List<dynamic>;
      return [
        for (final e in decoded)
          SessionRecord.fromJson(e as Map<String, dynamic>),
      ];
    } on Object {
      return [];
    }
  }

  /// Prepends [r] and persists, keeping only the newest [_maxRecords].
  void add(SessionRecord r) {
    final records = [r, ...load()];
    if (records.length > _maxRecords) {
      records.removeRange(_maxRecords, records.length);
    }
    _prefs.setString(
      _key,
      jsonEncode([for (final rec in records) rec.toJson()]),
    );
  }
}

String _two(int v) => v.toString().padLeft(2, '0');

String _mmss(int secs) => '${_two(secs ~/ 60)}:${_two(secs % 60)}';

/// Shows the session history sheet. [records] should be newest first
/// (as returned by [HistoryStore.load]).
void showHistorySheet(
  BuildContext context,
  Palette pal,
  List<SessionRecord> records,
) {
  showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (context) {
      final totalClaps = records.fold<int>(0, (sum, r) => sum + r.claps);
      final best = records.fold<int>(0, (m, r) => math.max(m, r.claps));
      final avg = records.isEmpty ? 0 : (totalClaps / records.length).round();
      // Oldest → newest so the newest session lands on the right.
      final chartClaps = records
          .take(30)
          .map((r) => r.claps)
          .toList()
          .reversed
          .toList();

      return Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [pal.bgTop, pal.bgBottom],
          ),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        ),
        padding: const EdgeInsets.fromLTRB(24, 14, 24, 24),
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.85,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'history',
              style: TextStyle(
                fontFamily: 'Pacifico',
                fontSize: 22,
                color: pal.text,
              ),
            ),
            const SizedBox(height: 12),
            if (records.isEmpty)
              Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'no plaps on record yet — go make some noise 💖',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: pal.textSoft),
                ),
              )
            else ...[
              Row(
                children: [
                  _StatChip(pal: pal, value: '${records.length}', label: 'sessions'),
                  const SizedBox(width: 8),
                  _StatChip(pal: pal, value: '$totalClaps', label: 'plaps'),
                  const SizedBox(width: 8),
                  _StatChip(pal: pal, value: '$best', label: 'best'),
                  const SizedBox(width: 8),
                  _StatChip(pal: pal, value: '$avg', label: 'avg'),
                ],
              ),
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
                decoration: BoxDecoration(
                  color: pal.card,
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(
                    color: pal.accent.withValues(alpha: 0.25),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      height: 96,
                      width: double.infinity,
                      child: CustomPaint(
                        painter: _BarChartPainter(claps: chartClaps, pal: pal),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'last ${chartClaps.length} sessions · newest on the right',
                      style: TextStyle(color: pal.cardTextSoft, fontSize: 10),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: records.length,
                  itemBuilder: (context, i) {
                    final r = records[i];
                    final d = r.endedAt;
                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: pal.card,
                        borderRadius: BorderRadius.circular(22),
                        border: Border.all(
                          color: pal.accent.withValues(alpha: 0.25),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${r.claps} plaps · ${_mmss(r.durationSecs)} · '
                            '${r.peakRate.toStringAsFixed(1)}/s',
                            style: TextStyle(
                              color: pal.cardText,
                              fontSize: 13,
                              fontVariations: const [wghtSemi],
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${d.year}-${_two(d.month)}-${_two(d.day)} '
                            '${_two(d.hour)}:${_two(d.minute)}',
                            style: TextStyle(
                              color: pal.cardTextSoft,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
          ],
        ),
      );
    },
  );
}

class _StatChip extends StatelessWidget {
  const _StatChip({required this.pal, required this.value, required this.label});

  final Palette pal;
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: pal.card,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: pal.accent.withValues(alpha: 0.25)),
        ),
        child: Column(
          children: [
            Text(
              value,
              style: TextStyle(
                color: pal.cardText,
                fontSize: 15,
                fontVariations: const [wghtBold],
              ),
            ),
            const SizedBox(height: 1),
            Text(
              label,
              style: TextStyle(color: pal.cardTextSoft, fontSize: 10),
            ),
          ],
        ),
      ),
    );
  }
}

/// Rounded-top bars for up to 30 sessions, oldest left → newest right.
/// The tallest bar gets a direct label; everything else stays quiet.
class _BarChartPainter extends CustomPainter {
  _BarChartPainter({required this.claps, required this.pal});

  /// Clap counts, oldest first.
  final List<int> claps;
  final Palette pal;

  @override
  void paint(Canvas canvas, Size size) {
    if (claps.isEmpty) return;
    const labelSpace = 16.0;
    final maxClaps = claps.reduce(math.max);
    final plotH = size.height - labelSpace;
    final slotW = size.width / claps.length;
    final barW = math.max(2.0, slotW * 0.68);
    final radius = Radius.circular(math.min(5.0, barW / 2));
    final paint = Paint()..color = pal.accent;
    final tallestIndex = claps.indexOf(maxClaps);

    for (var i = 0; i < claps.length; i++) {
      final frac = maxClaps == 0 ? 0.0 : claps[i] / maxClaps;
      // Keep even zero-ish sessions visible as a cute little stub.
      final h = math.max(3.0, frac * plotH);
      final left = i * slotW + (slotW - barW) / 2;
      final top = size.height - h;
      canvas.drawRRect(
        RRect.fromRectAndCorners(
          Rect.fromLTWH(left, top, barW, h),
          topLeft: radius,
          topRight: radius,
        ),
        paint,
      );
      if (i == tallestIndex && maxClaps > 0) {
        final tp = TextPainter(
          text: TextSpan(
            text: '$maxClaps',
            style: TextStyle(
              color: pal.cardText,
              fontSize: 10,
              fontFamily: 'Quicksand',
              fontVariations: const [wghtBold],
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        final x = (left + barW / 2 - tp.width / 2).clamp(
          0.0,
          size.width - tp.width,
        );
        tp.paint(canvas, Offset(x, top - tp.height - 2));
      }
    }
  }

  @override
  bool shouldRepaint(_BarChartPainter oldDelegate) =>
      oldDelegate.pal != pal || !listEquals(oldDelegate.claps, claps);
}
