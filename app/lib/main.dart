import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'plounter_ffi.dart';

void main() => runApp(const PlounterApp());

// Blush + hot pink + lavender palette.
const _bgTop = Color(0xFFFFF4F9);
const _bgBottom = Color(0xFFFFDDEC);
const _pink = Color(0xFFFF4F9A);
const _pinkDeep = Color(0xFFE0187F);
const _lavender = Color(0xFFB388EB);
const _plum = Color(0xFF5C2B52);
const _plumSoft = Color(0x995C2B52);

const _wght = FontVariation('wght', 400);
const _wghtSemi = FontVariation('wght', 600);
const _wghtBold = FontVariation('wght', 700);

class PlounterApp extends StatelessWidget {
  const PlounterApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Plounter',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.light,
        fontFamily: 'Quicksand',
        scaffoldBackgroundColor: _bgTop,
        colorScheme: ColorScheme.fromSeed(
          seedColor: _pink,
          brightness: Brightness.light,
        ),
        sliderTheme: SliderThemeData(
          activeTrackColor: _pink,
          inactiveTrackColor: _pink.withValues(alpha: 0.18),
          thumbColor: _pinkDeep,
          overlayColor: _pink.withValues(alpha: 0.15),
        ),
        textTheme: const TextTheme(
          bodyMedium: TextStyle(
            color: _plum,
            fontVariations: [_wght],
          ),
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

  // Milestone message: shown every N claps. "{count}" expands to the count.
  int _milestoneN = 10;
  final TextEditingController _milestoneCtrl =
      TextEditingController(text: 'yay!! {count} claps 🎀');
  String? _milestoneShown;
  Timer? _milestoneHide;
  SharedPreferences? _prefs;

  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 260),
    lowerBound: 1.0,
    upperBound: 1.22,
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
    SharedPreferences.getInstance().then((prefs) {
      _prefs = prefs;
      if (!mounted) return;
      setState(() {
        _milestoneN = prefs.getInt('milestoneN') ?? _milestoneN;
        _milestoneCtrl.text =
            prefs.getString('milestoneText') ?? _milestoneCtrl.text;
        _sensitivityDb = prefs.getDouble('sensitivityDb') ?? _sensitivityDb;
        _releaseMs = prefs.getDouble('releaseMs') ?? _releaseMs;
      });
      _plounter?.sensitivityDb = _sensitivityDb;
      _plounter?.envReleaseMs = _releaseMs;
    });
  }

  @override
  void dispose() {
    _poll?.cancel();
    _milestoneHide?.cancel();
    _milestoneCtrl.dispose();
    _pulse.dispose();
    _plounter?.dispose();
    super.dispose();
  }

  void _openSettings() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) {
          void both(VoidCallback fn) {
            setSheetState(fn);
            setState(() {});
          }

          return Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [_bgTop, _bgBottom],
              ),
              borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
            ),
            padding: EdgeInsets.only(
              left: 24,
              right: 24,
              top: 14,
              bottom: 24 + MediaQuery.of(context).viewInsets.bottom,
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 44,
                    height: 4,
                    decoration: BoxDecoration(
                      color: _pink.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(height: 10),
                  const Text('settings ✧',
                      style: TextStyle(
                        fontSize: 17,
                        letterSpacing: 3,
                        color: _plum,
                        fontVariations: [_wghtBold],
                      )),
                  const SizedBox(height: 14),
                  _LabeledCard(
                    label: 'SENSITIVITY',
                    trailing:
                        '+${_sensitivityDb.toStringAsFixed(0)} dB over room noise',
                    child: Slider(
                      value: _sensitivityDb,
                      min: 3,
                      max: 40,
                      onChanged: (v) {
                        both(() => _sensitivityDb = v);
                        _plounter?.sensitivityDb = v;
                      },
                      onChangeEnd: (v) =>
                          _prefs?.setDouble('sensitivityDb', v),
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
                        both(() => _releaseMs = v);
                        _plounter?.envReleaseMs = v;
                      },
                      onChangeEnd: (v) => _prefs?.setDouble('releaseMs', v),
                    ),
                  ),
                  const SizedBox(height: 12),
                  _LabeledCard(
                    label: 'MILESTONE MESSAGE',
                    trailing: 'every $_milestoneN claps',
                    child: Column(
                      children: [
                        TextField(
                          controller: _milestoneCtrl,
                          maxLength: 60,
                          style: const TextStyle(
                            fontSize: 14,
                            color: _plum,
                            fontVariations: [_wghtSemi],
                          ),
                          decoration: InputDecoration(
                            counterText: '',
                            isDense: true,
                            hintText: 'your message — {count} = clap count',
                            hintStyle: TextStyle(
                                color: _plum.withValues(alpha: 0.35)),
                            filled: true,
                            fillColor: _pink.withValues(alpha: 0.06),
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 10),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: BorderSide(
                                  color: _pink.withValues(alpha: 0.3)),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide:
                                  const BorderSide(color: _pink, width: 1.5),
                            ),
                          ),
                          onChanged: (v) =>
                              _prefs?.setString('milestoneText', v),
                        ),
                        Slider(
                          value: _milestoneN.toDouble(),
                          min: 2,
                          max: 100,
                          divisions: 98,
                          onChanged: (v) =>
                              both(() => _milestoneN = v.round()),
                          onChangeEnd: (v) =>
                              _prefs?.setInt('milestoneN', v.round()),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  void _maybeShowMilestone(int oldCount, int newCount) {
    if (_milestoneN < 1 || newCount <= 0) return;
    if (newCount ~/ _milestoneN == oldCount ~/ _milestoneN) return;
    final reached = (newCount ~/ _milestoneN) * _milestoneN;
    _milestoneHide?.cancel();
    setState(() {
      _milestoneShown =
          _milestoneCtrl.text.replaceAll('{count}', '$reached');
    });
    _milestoneHide = Timer(const Duration(milliseconds: 2600), () {
      if (mounted) setState(() => _milestoneShown = null);
    });
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
        _maybeShowMilestone(_count, newCount);
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
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [_bgTop, _bgBottom],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
                child: Column(
                  children: [
                    Stack(
                      alignment: Alignment.center,
                      children: [
                        const _Wordmark(),
                        Positioned(
                          right: 0,
                          child: IconButton(
                            tooltip: 'Settings',
                            onPressed: _openSettings,
                            icon: const Icon(Icons.tune_rounded,
                                color: _plumSoft),
                          ),
                        ),
                      ],
                    ),
                    const Spacer(),
                    _SparkleRow(pulse: _pulse),
                    ScaleTransition(
                      scale: _pulse,
                      child: ShaderMask(
                        shaderCallback: (bounds) => const LinearGradient(
                          colors: [_pinkDeep, _lavender],
                        ).createShader(bounds),
                        child: Text(
                          '$_count',
                          style: const TextStyle(
                            fontSize: 128,
                            height: 1.0,
                            color: Colors.white,
                            fontVariations: [_wghtBold],
                            fontFeatures: [FontFeature.tabularFigures()],
                          ),
                        ),
                      ),
                    ),
                    Text(_count == 1 ? 'clap 💖' : 'claps 💖',
                        style: const TextStyle(
                          fontSize: 16,
                          letterSpacing: 3,
                          color: _plumSoft,
                          fontVariations: [_wghtSemi],
                        )),
                    SizedBox(
                      height: 46,
                      child: Center(
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 300),
                          transitionBuilder: (child, anim) => FadeTransition(
                            opacity: anim,
                            child: ScaleTransition(scale: anim, child: child),
                          ),
                          child: _milestoneShown == null
                              ? const SizedBox.shrink()
                              : Container(
                                  key: ValueKey(_milestoneShown),
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 20, vertical: 8),
                                  decoration: BoxDecoration(
                                    gradient: const LinearGradient(
                                        colors: [_pink, _lavender]),
                                    borderRadius: BorderRadius.circular(30),
                                    boxShadow: [
                                      BoxShadow(
                                        color:
                                            _pink.withValues(alpha: 0.35),
                                        blurRadius: 14,
                                        offset: const Offset(0, 4),
                                      ),
                                    ],
                                  ),
                                  child: Text(
                                    _milestoneShown!,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 15,
                                      fontVariations: [_wghtBold],
                                    ),
                                  ),
                                ),
                        ),
                      ),
                    ),
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
                    if (_micError != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Text(_micError!,
                            style: const TextStyle(color: _pinkDeep)),
                      ),
                    const SizedBox(height: 24),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        FilledButton.icon(
                          style: FilledButton.styleFrom(
                            backgroundColor:
                                _listening ? Colors.white : _pink,
                            foregroundColor:
                                _listening ? _pinkDeep : Colors.white,
                            shape: const StadiumBorder(),
                            elevation: _listening ? 0 : 3,
                            shadowColor: _pink.withValues(alpha: 0.5),
                            side: _listening
                                ? const BorderSide(color: _pink, width: 1.5)
                                : BorderSide.none,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 30, vertical: 20),
                            textStyle: const TextStyle(
                              fontFamily: 'Quicksand',
                              fontVariations: [_wghtBold],
                              fontSize: 15,
                            ),
                          ),
                          onPressed: _toggleListening,
                          icon: Icon(_listening ? Icons.mic_off : Icons.mic),
                          label: Text(_listening
                              ? 'Stop listening'
                              : 'Start listening'),
                        ),
                        const SizedBox(width: 16),
                        OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: _plum,
                            shape: const StadiumBorder(),
                            side: BorderSide(
                                color: _plum.withValues(alpha: 0.35)),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 26, vertical: 20),
                            textStyle: const TextStyle(
                              fontFamily: 'Quicksand',
                              fontVariations: [_wghtSemi],
                              fontSize: 15,
                            ),
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
      ),
    );
  }
}

class _Wordmark extends StatelessWidget {
  const _Wordmark();

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Text('✧ ', style: TextStyle(fontSize: 18, color: _lavender)),
        ShaderMask(
          shaderCallback: (bounds) => const LinearGradient(
            colors: [_pinkDeep, _lavender],
          ).createShader(bounds),
          child: const Text(
            'plounter',
            style: TextStyle(
              fontSize: 26,
              letterSpacing: 6,
              color: Colors.white,
              fontVariations: [_wghtBold],
            ),
          ),
        ),
        const Text(' ✧', style: TextStyle(fontSize: 18, color: _lavender)),
      ],
    );
  }
}

/// Sparkles that fade in with the count pulse.
class _SparkleRow extends StatelessWidget {
  const _SparkleRow({required this.pulse});

  final AnimationController pulse;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: pulse,
      builder: (context, _) {
        final t = ((pulse.value - 1.0) / 0.22).clamp(0.0, 1.0);
        return Opacity(
          opacity: t,
          child: Transform.translate(
            offset: Offset(0, -6 * t),
            child: const Text('✨ 💗 ✨', style: TextStyle(fontSize: 20)),
          ),
        );
      },
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
        color: Colors.white.withValues(alpha: 0.75),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: _pink.withValues(alpha: 0.25)),
        boxShadow: [
          BoxShadow(
            color: _pink.withValues(alpha: 0.12),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(label,
                  style: const TextStyle(
                    fontSize: 11,
                    letterSpacing: 2,
                    color: _plumSoft,
                    fontVariations: [_wghtBold],
                  )),
              const Spacer(),
              if (trailing != null)
                Text(trailing!,
                    style: const TextStyle(
                      fontSize: 11,
                      color: _plumSoft,
                      fontVariations: [_wghtSemi],
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
/// noise floor (lavender) and trigger threshold (hot pink) drawn as lines.
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
    final bg = Paint()..color = _pink.withValues(alpha: 0.05);
    canvas.drawRRect(
        RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(12)),
        bg);

    void hline(double db, Color color) {
      if (db < _bottom || db > _top) return;
      final y = _y(db, size);
      canvas.drawRect(
          Rect.fromLTWH(0, y - 0.75, size.width, 1.5), Paint()..color = color);
    }

    hline(floorDb, _lavender.withValues(alpha: 0.6));
    hline(thresholdDb, _pinkDeep.withValues(alpha: 0.85));

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

    canvas.drawPath(fillPath, Paint()..color = _pink.withValues(alpha: 0.14));
    canvas.drawPath(
        path,
        Paint()
          ..color = _pink
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.8);
  }

  @override
  bool shouldRepaint(_GraphPainter old) => true;
}
