/// Goal mode UI pieces: progress ring, milestone praise, goal picker sheet.
///
/// Pure presentation + one tiny logic helper. No persistence in here —
/// the caller owns the goal value and the clap count.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../palette.dart';

// ---------------------------------------------------------------------------
// GoalProgressRing
// ---------------------------------------------------------------------------

/// A circular progress ring painted around [child].
///
/// ## Sizing contract
/// The ring fills whatever box the caller gives it, so **wrap it in a
/// bounded (ideally square) `SizedBox`**:
///
/// ```dart
/// SizedBox(
///   width: 320,
///   height: 320,
///   child: GoalProgressRing(
///     progress: count / goal,
///     pal: pal,
///     child: counterText, // the big ~128pt number
///   ),
/// )
/// ```
///
/// The ring is a circle inscribed in the shortest side of that box (inset a
/// few px so the tip glow/glyph stays inside), and [child] is centered.
/// Pick a box at least `childWidestDimension + 2 * 18` px so the ring clears
/// the child by ~18px. If the constraints are unbounded the widget shrinks
/// to the child and the ring hugs it — functional, but cramped.
class GoalProgressRing extends StatelessWidget {
  const GoalProgressRing({
    super.key,
    required this.child,
    required this.progress,
    required this.pal,
    this.celebrating = false,
  });

  /// Widget the ring wraps (centered).
  final Widget child;

  /// 0..1 fraction of the goal reached. Values outside are clamped.
  final double progress;

  final Palette pal;

  /// When true the arc is drawn thicker (10 vs 7) with a brighter tip glow —
  /// used the moment the goal is reached.
  final bool celebrating;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      foregroundPainter: _RingPainter(
        progress: progress.clamp(0.0, 1.0),
        pal: pal,
        celebrating: celebrating,
      ),
      child: Center(child: child),
    );
  }
}

class _RingPainter extends CustomPainter {
  const _RingPainter({
    required this.progress,
    required this.pal,
    required this.celebrating,
  });

  final double progress;
  final Palette pal;
  final bool celebrating;

  static const _topAngle = -math.pi / 2;

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = celebrating ? 10.0 : 7.0;
    final center = size.center(Offset.zero);
    final radius = size.shortestSide / 2 - stroke / 2 - 4;
    if (radius <= 0) return;
    final rect = Rect.fromCircle(center: center, radius: radius);

    // Track: full faint circle.
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..color = pal.accent.withValues(alpha: 0.12),
    );

    if (progress <= 0) return;

    final sweep = 2 * math.pi * progress;

    // Progress arc: accentDeep -> secondary swept across the drawn portion,
    // starting at 12 o'clock, round caps.
    final arcPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..shader = SweepGradient(
        startAngle: 0,
        endAngle: math.max(sweep, 0.05),
        colors: [pal.accentDeep, pal.secondary],
        transform: const GradientRotation(_topAngle),
      ).createShader(rect);
    canvas.drawArc(rect, _topAngle, sweep, false, arcPaint);

    // Tip: subtle blurred glow behind, small sparkle glyph on top.
    final tipAngle = _topAngle + sweep;
    final tip =
        center + Offset(math.cos(tipAngle), math.sin(tipAngle)) * radius;

    canvas.drawCircle(
      tip,
      stroke * (celebrating ? 1.3 : 1.0),
      Paint()
        ..color = pal.secondary.withValues(alpha: celebrating ? 0.85 : 0.5)
        ..maskFilter =
            MaskFilter.blur(BlurStyle.normal, celebrating ? 10 : 6),
    );

    final glyph = TextPainter(
      text: TextSpan(
        text: '✧',
        style: TextStyle(
          fontSize: celebrating ? 16 : 13,
          color: Colors.white,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    glyph.paint(
      canvas,
      tip - Offset(glyph.width / 2, glyph.height / 2),
    );
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.progress != progress ||
      old.pal != pal ||
      old.celebrating != celebrating;
}

// ---------------------------------------------------------------------------
// GoalMilestones
// ---------------------------------------------------------------------------

/// Stateless milestone logic: which praise line (if any) fires on a count
/// change. Callers should check `current >= goal` first and use
/// [goalReached] for that case — [checkpoint] returns null once the goal
/// itself is met so the two never double-fire.
class GoalMilestones {
  GoalMilestones._();

  /// Returns a praise line the first time [current] crosses 25% / 50% /
  /// 75% / 90% of [goal] (i.e. [previous] was below the threshold and
  /// [current] is at/above it), null otherwise. If several thresholds are
  /// crossed in one jump, the highest one wins.
  static String? checkpoint(
    int previous,
    int current,
    int goal,
    String petName,
  ) {
    if (goal <= 0 || current <= previous || current >= goal) return null;

    for (final (fraction, line) in [
      (0.90, 'almost… 90% $petName 😳'),
      (0.75, '75% — so close $petName 🎀'),
      (0.50, 'halfway!! keep going $petName ✨'),
      (0.25, 'quarter way there, $petName 💖'),
    ]) {
      final threshold = goal * fraction;
      if (previous < threshold && current >= threshold) return line;
    }
    return null;
  }

  /// The big one. Fire when `current >= goal` for the first time.
  static String goalReached(String petName, int goal) =>
      'GOAL!! $goal plaps, $petName — legendary 👑💖';
}

// ---------------------------------------------------------------------------
// Goal picker sheet
// ---------------------------------------------------------------------------

/// Opens the goal picker bottom sheet. Calls [onChanged] with the chosen
/// goal (or null for "clear goal") and pops the sheet.
void showGoalPickerSheet(
  BuildContext context,
  Palette pal, {
  required int? currentGoal,
  required void Function(int?) onChanged,
}) {
  showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (context) => _GoalPickerSheet(
      pal: pal,
      currentGoal: currentGoal,
      onChanged: onChanged,
    ),
  );
}

class _GoalPickerSheet extends StatefulWidget {
  const _GoalPickerSheet({
    required this.pal,
    required this.currentGoal,
    required this.onChanged,
  });

  final Palette pal;
  final int? currentGoal;
  final void Function(int?) onChanged;

  @override
  State<_GoalPickerSheet> createState() => _GoalPickerSheetState();
}

class _GoalPickerSheetState extends State<_GoalPickerSheet> {
  static const _presets = [25, 50, 100, 250, 500];

  late final TextEditingController _customCtrl = TextEditingController(
    text: widget.currentGoal != null &&
            !_presets.contains(widget.currentGoal)
        ? '${widget.currentGoal}'
        : '',
  );

  @override
  void dispose() {
    _customCtrl.dispose();
    super.dispose();
  }

  void _pick(int? goal) {
    widget.onChanged(goal);
    Navigator.of(context).pop();
  }

  void _submitCustom() {
    final value = int.tryParse(_customCtrl.text.trim());
    if (value != null && value > 0) _pick(value);
  }

  @override
  Widget build(BuildContext context) {
    final pal = widget.pal;
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [pal.bgTop, pal.bgBottom],
        ),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        top: 14,
        bottom: 24 + MediaQuery.of(context).viewInsets.bottom,
      ),
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
          Text(
            'goal ♡',
            style: TextStyle(
              fontFamily: 'Pacifico',
              fontSize: 22,
              color: pal.text,
            ),
          ),
          Text(
            widget.currentGoal == null
                ? 'no goal set — vibes only'
                : 'current goal: ${widget.currentGoal} plaps',
            style: TextStyle(
              fontSize: 11,
              color: pal.textSoft,
              fontVariations: const [wghtSemi],
            ),
          ),
          const SizedBox(height: 16),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 10,
            runSpacing: 10,
            children: [
              for (final preset in _presets)
                _PresetChip(
                  pal: pal,
                  label: '$preset',
                  selected: preset == widget.currentGoal,
                  onTap: () => _pick(preset),
                ),
            ],
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _customCtrl,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            maxLength: 6,
            textAlign: TextAlign.center,
            onSubmitted: (_) => _submitCustom(),
            style: TextStyle(
              fontSize: 14,
              color: pal.cardText,
              fontVariations: const [wghtSemi],
            ),
            decoration: InputDecoration(
              counterText: '',
              isDense: true,
              hintText: 'custom goal… ✨',
              hintStyle: TextStyle(
                color: pal.cardText.withValues(alpha: 0.35),
              ),
              filled: true,
              fillColor: pal.card,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide.none,
              ),
              suffixIcon: IconButton(
                icon: Icon(Icons.favorite, size: 18, color: pal.accentDeep),
                onPressed: _submitCustom,
                tooltip: 'set goal',
              ),
            ),
          ),
          const SizedBox(height: 12),
          TextButton(
            onPressed: () => _pick(null),
            child: Text(
              'clear goal',
              style: TextStyle(
                fontSize: 13,
                color: pal.textSoft,
                fontVariations: const [wghtSemi],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PresetChip extends StatelessWidget {
  const _PresetChip({
    required this.pal,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final Palette pal;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          gradient: selected
              ? LinearGradient(colors: [pal.accentDeep, pal.secondary])
              : null,
          color: selected ? null : pal.card,
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            color: selected ? Colors.white : pal.cardText,
            fontVariations: const [wghtBold],
          ),
        ),
      ),
    );
  }
}
