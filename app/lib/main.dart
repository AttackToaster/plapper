import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'plounter_ffi.dart';

void main() => runApp(const PlounterApp());

const _wghtSemi = FontVariation('wght', 600);
const _wghtBold = FontVariation('wght', 700);

/// A full look: background gradient, accents, text tones.
class Palette {
  const Palette({
    required this.name,
    required this.emoji,
    required this.bgTop,
    required this.bgBottom,
    required this.accent,
    required this.accentDeep,
    required this.secondary,
    required this.text,
    this.card = const Color(0xBFFFFFFF),
    Color? cardText,
    this.floaties = const ['♡', '✧', '💗', '✦', '🎀', '♡', '✧', '♡'],
    // ignore: prefer_initializing_formals — private field, named public param
  }) : _cardText = cardText;

  final String name;
  final String emoji;
  final Color bgTop, bgBottom, accent, accentDeep, secondary, text;
  final Color card;
  final Color? _cardText;
  final List<String> floaties;

  Color get cardText => _cardText ?? text;
  Color get textSoft => text.withValues(alpha: 0.6);
  Color get cardTextSoft => cardText.withValues(alpha: 0.6);
}

const palettes = [
  Palette(
    name: 'bubblegum',
    emoji: '🍬',
    bgTop: Color(0xFFFFF4F9),
    bgBottom: Color(0xFFFFD9EB),
    accent: Color(0xFFFF4F9A),
    accentDeep: Color(0xFFE0187F),
    secondary: Color(0xFFB388EB),
    text: Color(0xFF5C2B52),
  ),
  Palette(
    name: 'trans pride',
    emoji: '🏳️‍⚧️',
    bgTop: Color(0xFFEAF6FF),
    bgBottom: Color(0xFFFFE4F1),
    accent: Color(0xFFF48FB1),
    accentDeep: Color(0xFFE85D93),
    secondary: Color(0xFF55CDFC),
    text: Color(0xFF4B3A5E),
  ),
  Palette(
    name: 'lavender dream',
    emoji: '💜',
    bgTop: Color(0xFFF7F1FF),
    bgBottom: Color(0xFFE7D6FF),
    accent: Color(0xFFA968FF),
    accentDeep: Color(0xFF8A3FFC),
    secondary: Color(0xFFFF9BDD),
    text: Color(0xFF43305C),
  ),
  Palette(
    name: 'emo kitty',
    emoji: '🖤',
    bgTop: Color(0xFF140A11),
    bgBottom: Color(0xFF321021),
    accent: Color(0xFFFF2E88),
    accentDeep: Color(0xFFFF0066),
    secondary: Color(0xFF9BA0B0), // chrome silver
    text: Color(0xFFFFD3E4),
    card: Color(0xE6201018),
    cardText: Color(0xFFFFC9DE),
    floaties: ['🖤', '✧', '💀', '✦', '🎀', '♡', '⛓️', '🖤'],
  ),
];

class PlounterApp extends StatelessWidget {
  const PlounterApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'plounter ♡',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.light,
        fontFamily: 'Quicksand',
        colorScheme: ColorScheme.fromSeed(
          seedColor: palettes.first.accent,
          brightness: Brightness.light,
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
    with TickerProviderStateMixin {
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

  // Clap rate over a rolling 5 s window, and per-session bookkeeping.
  // A session = one listening run (Start -> Stop).
  static const _rateWindow = Duration(seconds: 5);
  final List<DateTime> _clapTimes = [];
  double _rate = 0;
  int _sessionStart = 0; // total count when the session began
  int _sessionClaps = 0;
  int _bestSession = 0;

  // Milestone message: shown every N claps. "{count}" expands to the count.
  int _milestoneN = 10;
  final TextEditingController _milestoneCtrl =
      TextEditingController(text: 'yay!! {count} claps 🎀');
  String? _milestoneShown;
  Timer? _milestoneHide;
  SharedPreferences? _prefs;

  int _paletteIdx = 0;
  Palette get pal => palettes[_paletteIdx];

  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 260),
    lowerBound: 1.0,
    upperBound: 1.22,
  );

  late final AnimationController _drift = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 14),
  )..repeat();

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
        _bestSession = prefs.getInt('bestSession') ?? 0;
        _paletteIdx =
            (prefs.getInt('paletteIdx') ?? 0).clamp(0, palettes.length - 1);
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
    _drift.dispose();
    _plounter?.dispose();
    super.dispose();
  }

  Future<void> _share() async {
    final text = 'I got $_sessionClaps claps in one plounter session!! 👏💖'
        '${_bestSession > 0 ? ' (best ever: $_bestSession)' : ''}';
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: pal.accentDeep,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        content: const Text(
          'copied to clipboard — paste it anywhere 💖',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontFamily: 'Quicksand',
            fontVariations: [_wghtSemi],
            color: Colors.white,
          ),
        ),
      ),
    );
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
            setState(fn);
          }

          return Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [pal.bgTop, pal.bgBottom],
              ),
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(28)),
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
                      color: pal.accent.withValues(alpha: 0.35),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text('settings',
                      style: TextStyle(
                        fontFamily: 'Pacifico',
                        fontSize: 22,
                        color: pal.text,
                      )),
                  const SizedBox(height: 14),
                  _LabeledCard(
                    pal: pal,
                    label: 'theme ♡',
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        for (var i = 0; i < palettes.length; i++)
                          GestureDetector(
                            onTap: () {
                              both(() => _paletteIdx = i);
                              _prefs?.setInt('paletteIdx', i);
                            },
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  width: 44,
                                  height: 44,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    gradient: LinearGradient(
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                      colors: [
                                        palettes[i].accent,
                                        palettes[i].secondary,
                                      ],
                                    ),
                                    border: Border.all(
                                      color: i == _paletteIdx
                                          ? palettes[i].accentDeep
                                          : Colors.transparent,
                                      width: 3,
                                    ),
                                  ),
                                  child: Center(
                                      child: Text(palettes[i].emoji,
                                          style: const TextStyle(
                                              fontSize: 16))),
                                ),
                                const SizedBox(height: 6),
                                Text(palettes[i].name,
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: pal.textSoft,
                                      fontVariations: const [_wghtSemi],
                                    )),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  _LabeledCard(
                    pal: pal,
                    label: 'sensitivity ♡',
                    trailing:
                        '+${_sensitivityDb.toStringAsFixed(0)} dB over room noise',
                    child: _slider(
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
                    pal: pal,
                    label: 'smoothing ♡',
                    trailing:
                        'release ${_releaseMs.toStringAsFixed(0)} ms — lower keeps up with fast claps',
                    child: _slider(
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
                    pal: pal,
                    label: 'milestone message ♡',
                    trailing: 'every $_milestoneN claps',
                    child: Column(
                      children: [
                        TextField(
                          controller: _milestoneCtrl,
                          maxLength: 60,
                          style: TextStyle(
                            fontSize: 14,
                            color: pal.cardText,
                            fontVariations: const [_wghtSemi],
                          ),
                          decoration: InputDecoration(
                            counterText: '',
                            isDense: true,
                            hintText: 'your message — {count} = clap count',
                            hintStyle: TextStyle(
                                color: pal.cardText.withValues(alpha: 0.35)),
                            filled: true,
                            fillColor: pal.accent.withValues(alpha: 0.06),
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 10),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: BorderSide(
                                  color:
                                      pal.accent.withValues(alpha: 0.3)),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: BorderSide(
                                  color: pal.accent, width: 1.5),
                            ),
                          ),
                          onChanged: (v) =>
                              _prefs?.setString('milestoneText', v),
                        ),
                        _slider(
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

  Widget _slider({
    required double value,
    required double min,
    required double max,
    int? divisions,
    required ValueChanged<double> onChanged,
    ValueChanged<double>? onChangeEnd,
  }) {
    return SliderTheme(
      data: SliderThemeData(
        activeTrackColor: pal.accent,
        inactiveTrackColor: pal.accent.withValues(alpha: 0.18),
        thumbColor: pal.accentDeep,
        overlayColor: pal.accent.withValues(alpha: 0.15),
      ),
      child: Slider(
        value: value,
        min: min,
        max: max,
        divisions: divisions,
        onChanged: onChanged,
        onChangeEnd: onChangeEnd,
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
      setState(() {
        _listening = false;
        _rate = 0;
        _clapTimes.clear();
      });
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
      _sessionStart = _count;
      _sessionClaps = 0;
      _clapTimes.clear();
      _rate = 0;
    });
    _poll = Timer.periodic(const Duration(milliseconds: 33), (_) {
      final newCount = p.count;
      final now = DateTime.now();
      if (newCount > _count) {
        _pulse.forward(from: 1.0).then((_) => _pulse.reverse());
        _maybeShowMilestone(_count, newCount);
        for (var i = 0; i < newCount - _count; i++) {
          _clapTimes.add(now);
        }
      }
      _clapTimes.removeWhere((t) => now.difference(t) > _rateWindow);
      setState(() {
        _count = newCount;
        _rate = _clapTimes.length / _rateWindow.inSeconds;
        _sessionClaps = newCount - _sessionStart;
        if (_sessionClaps > _bestSession) {
          _bestSession = _sessionClaps;
          _prefs?.setInt('bestSession', _bestSession);
        }
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
      body: AnimatedContainer(
        duration: const Duration(milliseconds: 500),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [pal.bgTop, pal.bgBottom],
          ),
        ),
        child: Stack(
          children: [
            Positioned.fill(
              child: IgnorePointer(
                child: AnimatedBuilder(
                  animation: _drift,
                  builder: (context, _) => CustomPaint(
                    painter: _FloatiesPainter(
                      t: _drift.value,
                      pal: pal,
                      lively: _listening,
                    ),
                  ),
                ),
              ),
            ),
            SafeArea(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 560),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 32, vertical: 24),
                    child: Column(
                      children: [
                        Stack(
                          alignment: Alignment.center,
                          children: [
                            _Wordmark(pal: pal),
                            Positioned(
                              right: 0,
                              child: IconButton(
                                tooltip: 'Settings',
                                onPressed: _openSettings,
                                icon: Icon(Icons.tune_rounded,
                                    color: pal.textSoft),
                              ),
                            ),
                          ],
                        ),
                        const Spacer(),
                        _SparkleRow(pulse: _pulse),
                        ScaleTransition(
                          scale: _pulse,
                          child: ShaderMask(
                            shaderCallback: (bounds) => LinearGradient(
                              colors: [pal.accentDeep, pal.secondary],
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
                        Text(_count == 1 ? 'clap' : 'claps',
                            style: TextStyle(
                              fontFamily: 'Pacifico',
                              fontSize: 22,
                              color: pal.textSoft,
                            )),
                        SizedBox(
                          height: 46,
                          child: Center(
                            child: AnimatedSwitcher(
                              duration: const Duration(milliseconds: 300),
                              transitionBuilder: (child, anim) =>
                                  FadeTransition(
                                opacity: anim,
                                child: ScaleTransition(
                                    scale: anim, child: child),
                              ),
                              child: _milestoneShown == null
                                  ? const SizedBox.shrink()
                                  : Container(
                                      key: ValueKey(_milestoneShown),
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 22, vertical: 7),
                                      decoration: BoxDecoration(
                                        gradient: LinearGradient(colors: [
                                          pal.accent,
                                          pal.secondary
                                        ]),
                                        borderRadius:
                                            BorderRadius.circular(30),
                                        boxShadow: [
                                          BoxShadow(
                                            color: pal.accent
                                                .withValues(alpha: 0.35),
                                            blurRadius: 14,
                                            offset: const Offset(0, 4),
                                          ),
                                        ],
                                      ),
                                      child: Text(
                                        _milestoneShown!,
                                        style: const TextStyle(
                                          fontFamily: 'Pacifico',
                                          color: Colors.white,
                                          fontSize: 16,
                                        ),
                                      ),
                                    ),
                            ),
                          ),
                        ),
                        const Spacer(),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            _StatChip(
                                pal: pal,
                                emoji: '👏',
                                label: 'this session',
                                value: '$_sessionClaps'),
                            const SizedBox(width: 10),
                            _StatChip(
                                pal: pal,
                                emoji: '⚡',
                                label: 'claps / sec',
                                value: _rate.toStringAsFixed(1)),
                            const SizedBox(width: 10),
                            _StatChip(
                                pal: pal,
                                emoji: '🏆',
                                label: 'best session',
                                value: '$_bestSession'),
                          ],
                        ),
                        const SizedBox(height: 14),
                        _LabeledCard(
                          pal: pal,
                          label: 'envelope — last 4 s',
                          trailing: _listening
                              ? '${_envDb.toStringAsFixed(0)} dB'
                              : 'mic off',
                          child: EnvelopeGraph(
                            history: _envHist,
                            head: _histHead,
                            floorDb: _listening ? _floorDb : -120,
                            thresholdDb: _listening ? thresholdDb : -120,
                            palette: pal,
                          ),
                        ),
                        if (_micError != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 12),
                            child: Text(_micError!,
                                style: TextStyle(color: pal.accentDeep)),
                          ),
                        const SizedBox(height: 24),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            _GradientPill(
                              pal: pal,
                              outlined: _listening,
                              icon: _listening
                                  ? Icons.mic_off_rounded
                                  : Icons.favorite_rounded,
                              label: _listening
                                  ? 'stop listening'
                                  : 'start listening',
                              onTap: _toggleListening,
                            ),
                            const SizedBox(width: 14),
                            _GradientPill(
                              pal: pal,
                              outlined: true,
                              icon: Icons.restart_alt_rounded,
                              label: 'reset',
                              onTap: () {
                                _plounter?.resetCount();
                                setState(() {
                                  _count = 0;
                                  _sessionStart = 0;
                                  _sessionClaps = 0;
                                  _clapTimes.clear();
                                  _rate = 0;
                                });
                              },
                            ),
                            const SizedBox(width: 14),
                            _GradientPill(
                              pal: pal,
                              outlined: true,
                              icon: Icons.ios_share_rounded,
                              label: 'share',
                              onTap: _share,
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
          ],
        ),
      ),
    );
  }
}

class _Wordmark extends StatelessWidget {
  const _Wordmark({required this.pal});

  final Palette pal;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text('✧ ', style: TextStyle(fontSize: 18, color: pal.secondary)),
        ShaderMask(
          shaderCallback: (bounds) => LinearGradient(
            colors: [pal.accentDeep, pal.secondary],
          ).createShader(bounds),
          child: const Text(
            'plounter',
            style: TextStyle(
              fontFamily: 'Pacifico',
              fontSize: 30,
              color: Colors.white,
            ),
          ),
        ),
        Text(' ♡', style: TextStyle(fontSize: 20, color: pal.accent)),
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

/// Hearts and sparkles drifting up the background.
class _FloatiesPainter extends CustomPainter {
  _FloatiesPainter({required this.t, required this.pal, required this.lively});

  final double t;
  final Palette pal;
  final bool lively;

  static const _emojiGlyphs = {'💗', '🎀', '🖤', '💀', '⛓️'};

  @override
  void paint(Canvas canvas, Size size) {
    final rng = math.Random(7);
    const n = 16;
    for (var i = 0; i < n; i++) {
      final baseX = rng.nextDouble();
      final speed = 0.5 + rng.nextDouble() * 0.9;
      final phase = rng.nextDouble();
      final wobble = rng.nextDouble() * 24;
      final fontSize = 10.0 + rng.nextDouble() * 14;
      final glyph = pal.floaties[i % pal.floaties.length];

      final progress = (t * speed + phase) % 1.0;
      final y = size.height * (1.05 - progress * 1.1);
      final x = baseX * size.width +
          math.sin((t * speed + phase) * 2 * math.pi * 2) * wobble;

      // fade at both ends of the journey
      final edge = math.min(progress, 1 - progress).clamp(0.0, 0.25) / 0.25;
      final alpha = edge * (lively ? 0.5 : 0.22);
      if (alpha <= 0.01) continue;

      final isEmoji = _emojiGlyphs.contains(glyph);
      final tp = TextPainter(
        text: TextSpan(
          text: glyph,
          style: TextStyle(
            fontSize: fontSize,
            color: isEmoji
                ? Colors.white.withValues(alpha: alpha)
                : (i.isEven ? pal.accent : pal.secondary)
                    .withValues(alpha: alpha),
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(x, y));
    }
  }

  @override
  bool shouldRepaint(_FloatiesPainter old) => true;
}

class _GradientPill extends StatelessWidget {
  const _GradientPill({
    required this.pal,
    required this.icon,
    required this.label,
    required this.onTap,
    this.outlined = false,
  });

  final Palette pal;
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool outlined;

  @override
  Widget build(BuildContext context) {
    final fg = outlined ? pal.accentDeep : Colors.white;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(40),
        child: Ink(
          decoration: BoxDecoration(
            gradient: outlined
                ? null
                : LinearGradient(colors: [pal.accentDeep, pal.secondary]),
            color: outlined ? pal.card : null,
            border: outlined
                ? Border.all(color: pal.accent.withValues(alpha: 0.6))
                : null,
            borderRadius: BorderRadius.circular(40),
            boxShadow: outlined
                ? null
                : [
                    BoxShadow(
                      color: pal.accent.withValues(alpha: 0.45),
                      blurRadius: 16,
                      offset: const Offset(0, 5),
                    ),
                  ],
          ),
          child: Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 19, color: fg),
                const SizedBox(width: 8),
                Text(label,
                    style: TextStyle(
                      fontSize: 15,
                      color: fg,
                      fontVariations: const [_wghtBold],
                    )),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  const _StatChip({
    required this.pal,
    required this.emoji,
    required this.label,
    required this.value,
  });

  final Palette pal;
  final String emoji;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: pal.card,
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: pal.accent.withValues(alpha: 0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(emoji, style: const TextStyle(fontSize: 14)),
          const SizedBox(width: 6),
          Text(value,
              style: TextStyle(
                fontSize: 14,
                color: pal.cardText,
                fontVariations: const [_wghtBold],
              )),
          const SizedBox(width: 5),
          Text(label,
              style: TextStyle(
                fontSize: 11,
                color: pal.cardTextSoft,
                fontVariations: const [_wghtSemi],
              )),
        ],
      ),
    );
  }
}

class _LabeledCard extends StatelessWidget {
  const _LabeledCard({
    required this.pal,
    required this.label,
    required this.child,
    this.trailing,
  });

  final Palette pal;
  final String label;
  final String? trailing;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: pal.card,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: pal.accent.withValues(alpha: 0.25)),
        boxShadow: [
          BoxShadow(
            color: pal.accent.withValues(alpha: 0.12),
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
                  style: TextStyle(
                    fontSize: 12,
                    letterSpacing: 1.5,
                    color: pal.cardTextSoft,
                    fontVariations: const [_wghtBold],
                  )),
              const Spacer(),
              if (trailing != null)
                Text(trailing!,
                    style: TextStyle(
                      fontSize: 11,
                      color: pal.cardTextSoft,
                      fontVariations: const [_wghtSemi],
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
/// noise floor and trigger threshold drawn as lines.
class EnvelopeGraph extends StatelessWidget {
  const EnvelopeGraph({
    super.key,
    required this.history,
    required this.head,
    required this.floorDb,
    required this.thresholdDb,
    this.palette,
  });

  /// Ring buffer of envelope dB values; [head] is the write position
  /// (= oldest sample).
  final List<double> history;
  final int head;
  final double floorDb;
  final double thresholdDb;
  final Palette? palette;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 96,
      child: CustomPaint(
        size: Size.infinite,
        painter: _GraphPainter(List.of(history), head, floorDb, thresholdDb,
            palette ?? palettes.first),
      ),
    );
  }
}

class _GraphPainter extends CustomPainter {
  _GraphPainter(this.hist, this.head, this.floorDb, this.thresholdDb, this.pal);

  final List<double> hist;
  final int head;
  final double floorDb, thresholdDb;
  final Palette pal;

  static const double _top = -10, _bottom = -90;

  double _y(double db, Size s) =>
      ((_top - db) / (_top - _bottom)).clamp(0.0, 1.0) * s.height;

  @override
  void paint(Canvas canvas, Size size) {
    final bg = Paint()..color = pal.accent.withValues(alpha: 0.05);
    canvas.drawRRect(
        RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(12)),
        bg);

    void hline(double db, Color color) {
      if (db < _bottom || db > _top) return;
      final y = _y(db, size);
      canvas.drawRect(
          Rect.fromLTWH(0, y - 0.75, size.width, 1.5), Paint()..color = color);
    }

    hline(floorDb, pal.secondary.withValues(alpha: 0.7));
    hline(thresholdDb, pal.accentDeep.withValues(alpha: 0.85));

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
        fillPath, Paint()..color = pal.accent.withValues(alpha: 0.14));
    canvas.drawPath(
        path,
        Paint()
          ..color = pal.accent
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.8);
  }

  @override
  bool shouldRepaint(_GraphPainter old) => true;
}
