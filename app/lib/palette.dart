import 'package:flutter/material.dart';

const wghtSemi = FontVariation('wght', 600);
const wghtBold = FontVariation('wght', 700);

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
    this.unlockAt = 0,
    // ignore: prefer_initializing_formals — private field, named public param
  }) : _cardText = cardText;

  final String name;
  final String emoji;
  final Color bgTop, bgBottom, accent, accentDeep, secondary, text;
  final Color card;
  final Color? _cardText;
  final List<String> floaties;

  /// Lifetime claps needed to unlock this theme.
  final int unlockAt;

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
    unlockAt: 25,
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
    unlockAt: 75,
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
    unlockAt: 150,
  ),
  Palette(
    name: 'scene queen',
    emoji: '💚',
    bgTop: Color(0xFF17101E),
    bgBottom: Color(0xFF261337),
    accent: Color(0xFFFF3FA4),
    accentDeep: Color(0xFFFF1493),
    secondary: Color(0xFF76FF03), // neon lime
    text: Color(0xFFEBD6FF),
    card: Color(0xE61E1428),
    cardText: Color(0xFFE8D9F5),
    floaties: ['💚', '✧', '🦝', '✦', '💕', '♡', '⭐', '💚'],
    unlockAt: 300,
  ),
  Palette(
    name: 'y2k cyber',
    emoji: '🦋',
    bgTop: Color(0xFFE8F4FF),
    bgBottom: Color(0xFFE2DcFF),
    accent: Color(0xFF00A8E8),
    accentDeep: Color(0xFF0077D6),
    secondary: Color(0xFFFF6EC7), // holo pink
    text: Color(0xFF2E3A5C),
    floaties: ['🦋', '✧', '💿', '✦', '🫧', '♡', '⭐', '🦋'],
    unlockAt: 500,
  ),
  Palette(
    name: 'cottage-core',
    emoji: '🍄',
    bgTop: Color(0xFFF9F6E9),
    bgBottom: Color(0xFFDDEBD2),
    accent: Color(0xFFE86A8A), // strawberry
    accentDeep: Color(0xFFD04A6E),
    secondary: Color(0xFF7FAE7C), // sage
    text: Color(0xFF4E4034),
    floaties: ['🍓', '✧', '🍄', '✦', '🌼', '♡', '🐝', '🍓'],
    unlockAt: 1000,
  ),
];

