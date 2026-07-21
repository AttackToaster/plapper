// Serverless bestie challenges: share a lil code, no backend, all vibes.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../palette.dart';

const _challengePrefix = 'PLAPCHAL1.';

/// A shareable snapshot of someone's plapping prowess.
class Challenge {
  const Challenge({required this.name, required this.best, required this.title});

  /// Pet name of the challenger.
  final String name;

  /// Their best plap count.
  final int best;

  /// Their rank string, e.g. 'plap princess'.
  final String title;
}

/// Encodes [c] as `PLAPCHAL1.` + base64url(utf8(json)).
String encodeChallenge(Challenge c) {
  final json = jsonEncode({'name': c.name, 'best': c.best, 'title': c.title});
  return '$_challengePrefix${base64UrlEncode(utf8.encode(json))}';
}

/// Decodes a challenge code. Tolerant of surrounding chatter, whitespace,
/// and missing padding — returns null instead of ever throwing.
Challenge? decodeChallenge(String s) {
  // Squash whitespace so codes survive line-wrapping in chat apps.
  final cleaned = s.replaceAll(RegExp(r'\s+'), '');
  final start = cleaned.indexOf(_challengePrefix);
  if (start < 0) return null;
  final tail = cleaned.substring(start + _challengePrefix.length);
  // Keep only the leading base64url run; anything past it is garbage.
  final match = RegExp(r'^[A-Za-z0-9_\-=]+').firstMatch(tail);
  if (match == null) return null;
  final run = match.group(0)!;
  // Trailing letters glued on by the whitespace squash still poison the
  // run, so try progressively shorter prefixes until one parses. Codes
  // are ~100 chars, so this stays cheap.
  for (var end = run.length; end >= 4; end--) {
    try {
      final bytes = base64Url.decode(
        base64Url.normalize(run.substring(0, end)),
      );
      final decoded = jsonDecode(utf8.decode(bytes));
      if (decoded is! Map) continue;
      final name = decoded['name'];
      final best = decoded['best'];
      final title = decoded['title'];
      if (name is! String || best is! int || title is! String) continue;
      return Challenge(name: name, best: best, title: title);
    } on FormatException {
      continue;
    }
  }
  return null;
}

/// Opens the challenge bottom sheet: share your code, paste a bestie's.
void showChallengeSheet(
  BuildContext context,
  Palette pal, {
  required String myName,
  required int myBest,
  required String myTitle,
}) {
  final code = encodeChallenge(
    Challenge(name: myName, best: myBest, title: myTitle),
  );
  final shareLine =
      '"beat my $myBest plaps 😤💖" — paste this code in plapper: $code';
  final pasteCtrl = TextEditingController();
  var codeCopied = false;
  var shareCopied = false;

  showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (sheetContext) => StatefulBuilder(
      builder: (context, setSheetState) {
        void flashCopied(String text, void Function(bool) mark) {
          Clipboard.setData(ClipboardData(text: text));
          setSheetState(() => mark(true));
          Future<void>.delayed(const Duration(milliseconds: 1600), () {
            if (context.mounted) setSheetState(() => mark(false));
          });
        }

        final pasted = pasteCtrl.text;
        final theirs = decodeChallenge(pasted);

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
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.85,
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
                Text(
                  'challenge a bestie',
                  style: TextStyle(
                    fontFamily: 'Pacifico',
                    fontSize: 22,
                    color: pal.text,
                  ),
                ),
                Text(
                  'no servers, just plaps 🤝',
                  style: TextStyle(
                    fontSize: 11,
                    color: pal.textSoft,
                    fontVariations: const [wghtSemi],
                  ),
                ),
                const SizedBox(height: 14),
                _ChallengeCard(
                  pal: pal,
                  label: 'your challenge code ♡',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: pal.accent.withValues(alpha: 0.10),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: SelectableText(
                          code,
                          style: TextStyle(
                            fontFamily: 'monospace',
                            fontFamilyFallback: const ['Courier'],
                            fontSize: 11,
                            color: pal.cardText,
                          ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      TextButton.icon(
                        onPressed: () =>
                            flashCopied(code, (v) => codeCopied = v),
                        style: TextButton.styleFrom(
                          foregroundColor: pal.accentDeep,
                        ),
                        icon: const Icon(Icons.copy_rounded, size: 16),
                        label: Text(codeCopied ? 'copied 💖' : 'copy'),
                      ),
                      Divider(color: pal.accent.withValues(alpha: 0.25)),
                      const SizedBox(height: 4),
                      Text(
                        shareLine,
                        style: TextStyle(
                          fontSize: 11,
                          color: pal.cardTextSoft,
                        ),
                      ),
                      TextButton.icon(
                        onPressed: () =>
                            flashCopied(shareLine, (v) => shareCopied = v),
                        style: TextButton.styleFrom(
                          foregroundColor: pal.accentDeep,
                        ),
                        icon: const Icon(Icons.ios_share_rounded, size: 16),
                        label: Text(
                          shareCopied ? 'copied 💖' : 'copy share line',
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                _ChallengeCard(
                  pal: pal,
                  label: 'got a code?',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      TextField(
                        controller: pasteCtrl,
                        onChanged: (_) => setSheetState(() {}),
                        maxLines: 2,
                        minLines: 1,
                        style: TextStyle(
                          fontFamily: 'monospace',
                          fontFamilyFallback: const ['Courier'],
                          fontSize: 11,
                          color: pal.cardText,
                        ),
                        decoration: InputDecoration(
                          hintText: 'paste it here bestie…',
                          hintStyle: TextStyle(
                            fontSize: 12,
                            color: pal.cardTextSoft,
                          ),
                          filled: true,
                          fillColor: pal.accent.withValues(alpha: 0.10),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none,
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                        ),
                      ),
                      if (theirs != null) ...[
                        const SizedBox(height: 10),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: pal.accent.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: pal.accent.withValues(alpha: 0.35),
                            ),
                          ),
                          child: Column(
                            children: [
                              Text(
                                '${theirs.name} · ${theirs.title} · '
                                'best ${theirs.best} plaps',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 13,
                                  color: pal.cardText,
                                  fontVariations: const [wghtBold],
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                myBest > theirs.best
                                    ? 'you already beat them 😌💅'
                                    : 'you need ${theirs.best - myBest + 1} '
                                          'more — get plapping!!',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: pal.accentDeep,
                                  fontVariations: const [wghtSemi],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ] else if (pasted.trim().isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text(
                          "hmm, that code isn't plapping 🥺",
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 11,
                            color: pal.cardTextSoft,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    ),
  ).whenComplete(pasteCtrl.dispose);
}

class _ChallengeCard extends StatelessWidget {
  const _ChallengeCard({
    required this.pal,
    required this.label,
    required this.child,
  });

  final Palette pal;
  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: pal.card,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: pal.accent.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              color: pal.cardText,
              fontVariations: const [wghtBold],
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }
}
