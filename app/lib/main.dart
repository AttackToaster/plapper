import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import 'plounter_ffi.dart';

void main() => runApp(const PlounterApp());

const _bg = Color(0xFF14151A);
const _surface = Color(0xFF1E2028);
const _accent = Color(0xFFFFB454);
const _meterGreen = Color(0xFF6FCF97);

class PlounterApp extends StatelessWidget {
  const PlounterApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Plounter',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: _bg,
        colorScheme: ColorScheme.fromSeed(
          seedColor: _accent,
          brightness: Brightness.dark,
        ),
        sliderTheme: const SliderThemeData(
          activeTrackColor: _accent,
          thumbColor: _accent,
        ),
      ),
      home: const CounterPage(),
    );
  }
}

class CounterPage extends StatefulWidget {
  const CounterPage({super.key});

  @override
  State<CounterPage> createState() => _CounterPageState();
}

class _CounterPageState extends State<CounterPage>
    with SingleTickerProviderStateMixin {
  Plounter? _plounter;
  String? _initError;

  Timer? _poll;
  int _count = 0;
  double _envDb = -120, _floorDb = -120, _sensitivityDb = 12;
  double _releaseMs = 20;
  bool _listening = false;
  String? _micError;

  /// ~4 s of envelope history at the 33 ms poll rate.
  static const int _histLen = 120;
  final List<double> _envHist = List.filled(_histLen, -120, growable: false);
  int _histHead = 0;

  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 220),
    lowerBound: 1.0,
    upperBound: 1.18,
  );

  @override
  void initState() {
    super.initState();
    try {
      _plounter = Plounter();
      _sensitivityDb = _plounter!.sensitivityDb;
      _releaseMs = _plounter!.envReleaseMs;
    } catch (e) {
      _initError = '$e';
    }
  }

  @override
  void dispose() {
    _poll?.cancel();
    _pulse.dispose();
    _plounter?.dispose();
    super.dispose();
  }

  Future<void> _toggleListening() async {
    final p = _plounter;
    if (p == null) return;

    if (_listening) {
      p.stopListening();
      _poll?.cancel();
      _poll = null;
      setState(() => _listening = false);
      return;
    }

    // Mobile requires an explicit runtime permission request; desktop
    // platforms prompt (or just work) on first device open.
    if (Platform.isAndroid || Platform.isIOS) {
      final status = await Permission.microphone.request();
      if (!status.isGranted) {
        setState(() => _micError = 'Microphone permission denied.');
        return;
      }
    }

    if (!p.startListening()) {
      setState(() => _micError = 'Could not open the microphone.');
      return;
    }
    setState(() {
      _listening = true;
      _micError = null;
    });
    _poll = Timer.periodic(const Duration(milliseconds: 33), (_) {
      final newCount = p.count;
      if (newCount > _count) {
        _pulse.forward(from: 1.0).then((_) => _pulse.reverse());
      }
      setState(() {
        _count = newCount;
        _envDb = p.envelopeDb;
        _floorDb = p.noiseFloorDb;
        _envHist[_histHead] = _envDb;
        _histHead = (_histHead + 1) % _histLen;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_initError != null) {
      return Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Text('Failed to load plounter core:\n$_initError',
                textAlign: TextAlign.center),
          ),
        ),
      );
    }

    final thresholdDb = _floorDb + _sensitivityDb;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
              child: Column(
                children: [
                  Text('PLOUNTER',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 8,
                        color: _accent.withValues(alpha: 0.9),
                      )),
                  const Spacer(),
                  ScaleTransition(
                    scale: _pulse,
                    child: Text(
                      '$_count',
                      style: const TextStyle(
                        fontSize: 128,
                        fontWeight: FontWeight.w200,
                        height: 1.0,
                        fontFeatures: [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                  Text(_count == 1 ? 'CLAP' : 'CLAPS',
                      style: TextStyle(
                        fontSize: 14,
                        letterSpacing: 4,
                        color: Colors.white.withValues(alpha: 0.45),
                      )),
                  const Spacer(),
                  _LabeledCard(
                    label: 'ENVELOPE — LAST 4 S',
                    trailing: _listening
                        ? '${_envDb.toStringAsFixed(0)} dB'
                        : 'mic off',
                    child: EnvelopeGraph(
                      history: _envHist,
                      head: _histHead,
                      floorDb: _listening ? _floorDb : -120,
                      thresholdDb: _listening ? thresholdDb : -120,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _LabeledCard(
                    label: 'SENSITIVITY',
                    trailing:
                        '+${_sensitivityDb.toStringAsFixed(0)} dB over room noise',
                    child: Slider(
                      value: _sensitivityDb,
                      min: 3,
                      max: 40,
                      onChanged: (v) {
                        setState(() => _sensitivityDb = v);
                        _plounter?.sensitivityDb = v;
                      },
                    ),
                  ),
                  const SizedBox(height: 12),
                  _LabeledCard(
                    label: 'SMOOTHING',
                    trailing:
                        'release ${_releaseMs.toStringAsFixed(0)} ms — lower keeps up with fast claps',
                    child: Slider(
                      value: _releaseMs,
                      min: 5,
                      max: 80,
                      onChanged: (v) {
                        setState(() => _releaseMs = v);
                        _plounter?.envReleaseMs = v;
                      },
                    ),
                  ),
                  if (_micError != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text(_micError!,
                          style: const TextStyle(color: Colors.redAccent)),
                    ),
                  const SizedBox(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: _listening ? _surface : _accent,
                          foregroundColor:
                              _listening ? Colors.white : Colors.black,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 28, vertical: 18),
                        ),
                        onPressed: _toggleListening,
                        icon: Icon(_listening ? Icons.mic_off : Icons.mic),
                        label: Text(
                            _listening ? 'Stop listening' : 'Start listening'),
                      ),
                      const SizedBox(width: 16),
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 24, vertical: 18),
                        ),
                        onPressed: () {
                          _plounter?.resetCount();
                          setState(() => _count = 0);
                        },
                        icon: const Icon(Icons.restart_alt),
                        label: const Text('Reset count'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _LabeledCard extends StatelessWidget {
  const _LabeledCard({required this.label, required this.child, this.trailing});

  final String label;
  final String? trailing;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(14),
      ),
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(label,
                  style: TextStyle(
                    fontSize: 11,
                    letterSpacing: 2,
                    fontWeight: FontWeight.w600,
                    color: Colors.white.withValues(alpha: 0.45),
                  )),
              const Spacer(),
              if (trailing != null)
                Text(trailing!,
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.white.withValues(alpha: 0.55),
                    )),
            ],
          ),
          const SizedBox(height: 8),
          child,
        ],
      ),
    );
  }
}

/// Scrolling envelope history (detection band, dBFS -90..-10) with the
/// noise floor (grey) and trigger threshold (amber) drawn as lines.
class EnvelopeGraph extends StatelessWidget {
  const EnvelopeGraph({
    super.key,
    required this.history,
    required this.head,
    required this.floorDb,
    required this.thresholdDb,
  });

  /// Ring buffer of envelope dB values; [head] is the write position
  /// (= oldest sample).
  final List<double> history;
  final int head;
  final double floorDb;
  final double thresholdDb;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 96,
      child: CustomPaint(
        size: Size.infinite,
        painter: _GraphPainter(List.of(history), head, floorDb, thresholdDb),
      ),
    );
  }
}

class _GraphPainter extends CustomPainter {
  _GraphPainter(this.hist, this.head, this.floorDb, this.thresholdDb);

  final List<double> hist;
  final int head;
  final double floorDb, thresholdDb;

  static const double _top = -10, _bottom = -90;

  double _y(double db, Size s) =>
      ((_top - db) / (_top - _bottom)).clamp(0.0, 1.0) * s.height;

  @override
  void paint(Canvas canvas, Size size) {
    final bg = Paint()..color = Colors.white.withValues(alpha: 0.04);
    canvas.drawRRect(
        RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(8)),
        bg);

    void hline(double db, Color color) {
      if (db < _bottom || db > _top) return;
      final y = _y(db, size);
      canvas.drawRect(
          Rect.fromLTWH(0, y - 0.75, size.width, 1.5), Paint()..color = color);
    }

    hline(floorDb, Colors.white.withValues(alpha: 0.3));
    hline(thresholdDb, _accent.withValues(alpha: 0.85));

    final n = hist.length;
    final path = Path();
    final fillPath = Path()..moveTo(0, size.height);
    for (var i = 0; i < n; i++) {
      final db = hist[(head + i) % n]; // oldest -> newest
      final x = i / (n - 1) * size.width;
      final y = _y(db, size);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
      fillPath.lineTo(x, y);
    }
    fillPath
      ..lineTo(size.width, size.height)
      ..close();

    canvas.drawPath(
        fillPath, Paint()..color = _meterGreen.withValues(alpha: 0.12));
    canvas.drawPath(
        path,
        Paint()
          ..color = _meterGreen
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.6);
  }

  @override
  bool shouldRepaint(_GraphPainter old) => true;
}
