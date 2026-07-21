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
  bool _listening = false;
  String? _micError;

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
                    label: 'INPUT LEVEL',
                    trailing: _listening
                        ? '${_envDb.toStringAsFixed(0)} dB'
                        : 'mic off',
                    child: LevelMeter(
                      envelopeDb: _listening ? _envDb : -120,
                      floorDb: _listening ? _floorDb : -120,
                      thresholdDb: _listening ? thresholdDb : -120,
                    ),
                  ),
                  const SizedBox(height: 16),
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

/// Horizontal dB meter: envelope bar with a grey noise-floor tick and an
/// amber trigger-threshold tick. Range -80..0 dBFS.
class LevelMeter extends StatelessWidget {
  const LevelMeter({
    super.key,
    required this.envelopeDb,
    required this.floorDb,
    required this.thresholdDb,
  });

  final double envelopeDb;
  final double floorDb;
  final double thresholdDb;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 26,
      child: CustomPaint(
        size: Size.infinite,
        painter: _MeterPainter(envelopeDb, floorDb, thresholdDb),
      ),
    );
  }
}

class _MeterPainter extends CustomPainter {
  _MeterPainter(this.envDb, this.floorDb, this.thresholdDb);

  final double envDb, floorDb, thresholdDb;

  static double _norm(double db) => ((db + 80) / 80).clamp(0.0, 1.0);

  @override
  void paint(Canvas canvas, Size size) {
    final track = Paint()..color = Colors.white.withValues(alpha: 0.06);
    final rrect = RRect.fromRectAndRadius(
        Rect.fromLTWH(0, 6, size.width, 14), const Radius.circular(7));
    canvas.drawRRect(rrect, track);

    final envW = _norm(envDb) * size.width;
    if (envW > 0) {
      final fill = Paint()
        ..shader = const LinearGradient(colors: [_meterGreen, _accent])
            .createShader(Rect.fromLTWH(0, 0, size.width, 26));
      canvas.save();
      canvas.clipRRect(rrect);
      canvas.drawRect(Rect.fromLTWH(0, 6, envW, 14), fill);
      canvas.restore();
    }

    void tick(double db, Color color) {
      final x = _norm(db) * size.width;
      canvas.drawRect(
          Rect.fromLTWH(x - 1, 0, 2, size.height), Paint()..color = color);
    }

    tick(floorDb, Colors.white.withValues(alpha: 0.35));
    tick(thresholdDb, _accent);
  }

  @override
  bool shouldRepaint(_MeterPainter old) =>
      old.envDb != envDb ||
      old.floorDb != floorDb ||
      old.thresholdDb != thresholdDb;
}
