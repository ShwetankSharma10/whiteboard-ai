import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../domain/models/board_object.dart';

const _uuid = Uuid();

/// Gemini API key injected at build time:
///   flutter run --dart-define=GEMINI_API_KEY=your_key
/// In Android Studio: Run > Edit Configurations > Additional run args.
const kGeminiApiKey = String.fromEnvironment('GEMINI_API_KEY');

/// Optional model override (defaults to a fast, inexpensive Flash model).
const kGeminiModel = String.fromEnvironment(
  'GEMINI_MODEL',
  defaultValue: 'gemini-2.5-flash',
);

/// Generated AI mindmap node with position and connector metadata.
class AIMindmapNode {
  const AIMindmapNode({
    required this.id,
    required this.title,
    required this.colorValue,
    this.parentId,
  });

  final String id;
  final String title;
  final int colorValue;
  final String? parentId;
}

/// A mindmap branch (first-level subtopic) with optional leaf children.
class MindmapBranch {
  const MindmapBranch(this.title, [this.children = const []]);
  final String title;
  final List<String> children;
}

/// Result of an AI operation, including whether the real Gemini model was
/// used and a human readable message suitable for a SnackBar.
class AIResult<T> {
  const AIResult({
    required this.value,
    required this.usedGemini,
    required this.message,
  });

  final T value;
  final bool usedGemini;
  final String message;
}

/// Thrown when the Gemini REST API fails; [message] is user-presentable.
class GeminiException implements Exception {
  const GeminiException(this.message);
  final String message;
  @override
  String toString() => 'GeminiException: $message';
}

/// Service handling Gemini AI capabilities:
/// 1. Prompt-to-Mindmap generation (Gemini, with offline fallback)
/// 2. Sketch-to-Diagram shape recognition (on-device geometry)
/// 3. Board content summarization & action items (Gemini, with offline fallback)
class GeminiAIService {
  const GeminiAIService({
    this.apiKey,
    this.model = 'gemini-2.5-flash',
    this.client,
    this.timeout = const Duration(seconds: 30),
  });

  final String? apiKey;
  final String model;
  final http.Client? client;
  final Duration timeout;

  /// True when a Gemini API key is available and network calls will be made.
  bool get isConfigured => (apiKey ?? '').trim().isNotEmpty;

  // ---------------------------------------------------------------------------
  // Gemini REST transport
  // ---------------------------------------------------------------------------

  /// Ordered fallback models tried automatically when the primary model
  /// experiences heavy traffic (HTTP 503) or rate limits (HTTP 429).
  static const List<String> _fallbackModels = [
    'gemini-2.5-flash',
    'gemini-2.5-flash-lite',
    'gemini-2.0-flash',
    'gemini-2.0-flash-lite',
    'gemini-1.5-flash',
  ];

  /// Sends [prompt] to Gemini and returns the decoded JSON response object.
  Future<Map<String, dynamic>> _generateJson(String prompt) async {
    final modelsToTry = client != null
        ? <String>[model]
        : <String>{model, ..._fallbackModels}.toList();

    final body = jsonEncode({
      'contents': [
        {
          'role': 'user',
          'parts': [
            {'text': prompt},
          ],
        },
      ],
      'generationConfig': {
        'responseMimeType': 'application/json',
        'temperature': 0.6,
      },
    });

    final c = client ?? http.Client();
    GeminiException? lastError;

    try {
      for (final candidateModel in modelsToTry) {
        final uri = Uri.parse(
          'https://generativelanguage.googleapis.com/v1beta/models/'
          '$candidateModel:generateContent',
        );

        http.Response res;
        try {
          res = await c
              .post(
                uri,
                headers: {
                  'Content-Type': 'application/json',
                  'x-goog-api-key': apiKey!.trim(),
                },
                body: body,
              )
              .timeout(timeout);
        } on TimeoutException {
          lastError = const GeminiException('Gemini request timed out.');
          continue;
        } catch (e) {
          throw GeminiException(
            'Network error: check internet connection ($e).',
          );
        }

        if (res.statusCode == 200) {
          try {
            final decoded = jsonDecode(res.body) as Map<String, dynamic>;
            final text =
                decoded['candidates'][0]['content']['parts'][0]['text']
                    as String;
            return jsonDecode(_stripCodeFence(text)) as Map<String, dynamic>;
          } catch (_) {
            lastError = const GeminiException(
              'Gemini returned an unexpected response.',
            );
            continue;
          }
        }

        var detail = 'HTTP ${res.statusCode}';
        try {
          final err = jsonDecode(res.body) as Map<String, dynamic>;
          detail = (err['error']?['message'] as String?) ?? detail;
        } catch (_) {}

        if (res.statusCode == 400 && detail.toLowerCase().contains('api key')) {
          throw const GeminiException('Invalid Gemini API key.');
        }
        if (res.statusCode == 403) {
          throw GeminiException('Gemini access denied: $detail');
        }

        // If 503 (heavy traffic / overloaded), 429 (quota), or 404, try next model in chain
        if (res.statusCode == 503 ||
            res.statusCode == 429 ||
            res.statusCode == 404 ||
            res.statusCode == 500) {
          lastError = res.statusCode == 429
              ? const GeminiException('Gemini quota exceeded, try again later.')
              : res.statusCode == 404
              ? GeminiException('Gemini model "$candidateModel" not found.')
              : GeminiException('Gemini error: $detail');
          continue;
        }

        throw GeminiException('Gemini error: $detail');
      }
    } finally {
      if (client == null) c.close();
    }

    throw lastError ?? const GeminiException('Gemini request failed.');
  }

  static String _stripCodeFence(String text) {
    var t = text.trim();
    if (t.startsWith('```')) {
      t = t.replaceFirst(RegExp(r'^```[a-zA-Z]*\s*'), '');
      t = t.replaceFirst(RegExp(r'```\s*$'), '');
    }
    return t.trim();
  }

  // ---------------------------------------------------------------------------
  // 1. Mindmap
  // ---------------------------------------------------------------------------

  /// Generates a mindmap using Gemini when configured, falling back to the
  /// offline template engine otherwise (or on any API failure).
  Future<AIResult<List<BoardObject>>> generateMindmapSmart(
    String topic, {
    Offset origin = const Offset(200, 200),
  }) async {
    final sanitized = topic.trim().isEmpty ? 'Project Roadmap' : topic.trim();
    if (!isConfigured) {
      return AIResult(
        value: _layoutMindmap(sanitized, _offlineBranches(sanitized), origin),
        usedGemini: false,
        message: 'AI mindmap generated for "$sanitized".',
      );
    }
    try {
      final json = await _generateJson(
        'You are helping build a whiteboard mindmap.\n'
        'Topic: "$sanitized"\n'
        'Return ONLY JSON of the form '
        '{"branches":[{"title":"...","children":["...","..."]}]}.\n'
        'Rules: 4 to 6 branches, 0 to 3 children per branch, '
        'every label at most 4 words, no numbering, no emojis.',
      );
      final branches = <MindmapBranch>[];
      for (final b in (json['branches'] as List? ?? const [])) {
        if (b is! Map) continue;
        final title = (b['title'] ?? '').toString().trim();
        if (title.isEmpty) continue;
        final children = (b['children'] as List? ?? const [])
            .map((c) => c.toString().trim())
            .where((c) => c.isNotEmpty)
            .take(3)
            .toList();
        branches.add(MindmapBranch(title, children));
        if (branches.length == 6) break;
      }
      if (branches.isEmpty) {
        throw const GeminiException('Gemini returned an empty mindmap.');
      }
      return AIResult(
        value: _layoutMindmap(sanitized, branches, origin),
        usedGemini: true,
        message: 'Gemini mindmap generated for "$sanitized".',
      );
    } on GeminiException catch (e) {
      return AIResult(
        value: _layoutMindmap(sanitized, _offlineBranches(sanitized), origin),
        usedGemini: false,
        message: '${e.message} Showing offline mindmap instead.',
      );
    }
  }

  /// Offline (template based) mindmap generation. Kept for tests and as the
  /// fallback path when Gemini is unavailable.
  Future<List<BoardObject>> generateMindmap(
    String topic, {
    Offset origin = const Offset(200, 200),
  }) async {
    final sanitized = topic.trim().isEmpty ? 'Project Roadmap' : topic.trim();
    return _layoutMindmap(sanitized, _offlineBranches(sanitized), origin);
  }

  List<BoardObject> _layoutMindmap(
    String title,
    List<MindmapBranch> branches,
    Offset origin,
  ) {
    final objects = <BoardObject>[];
    final mindmapGroupId = 'ai-mindmap-${_uuid.v4()}';

    double widthFor(String label, double fontSize, double min, double max) =>
        (label.length * fontSize * 0.62 + 32).clamp(min, max);

    // Root node
    final rootId = 'ai-root-${_uuid.v4().substring(0, 8)}';
    final rootWidth = widthFor(title, 16, 180, 320);
    const rootHeight = 70.0;
    objects.add(
      RectangleObject(
        id: rootId,
        rect: Rect.fromCenter(
          center: origin,
          width: rootWidth,
          height: rootHeight,
        ),
        color: const Color(0xFF2563EB),
        strokeWidth: 2.5,
        isFilled: true,
        fillColor: const Color(0xFFEFF6FF),
        cornerRadius: 12.0,
        groupId: mindmapGroupId,
      ),
    );
    objects.add(
      TextObject(
        id: 'ai-text-$rootId',
        position: Offset(origin.dx - rootWidth / 2 + 16, origin.dy - 12),
        text: title,
        color: const Color(0xFF1E3A8A),
        fontSize: 16.0,
        isBold: true,
        groupId: mindmapGroupId,
      ),
    );

    final count = branches.length;
    const branchRadius = 270.0;
    const leafRadius = 470.0;

    for (var i = 0; i < count; i++) {
      final branch = branches[i];
      final angle = (2.0 * math.pi * i / count) - (math.pi / 2.0);
      final center = Offset(
        origin.dx + branchRadius * math.cos(angle),
        origin.dy + branchRadius * math.sin(angle),
      );
      final id = 'ai-child-${_uuid.v4().substring(0, 8)}';
      final w = widthFor(branch.title, 13, 130, 220);
      const h = 55.0;

      objects.add(
        RectangleObject(
          id: id,
          rect: Rect.fromCenter(center: center, width: w, height: h),
          color: _subtopicColor(i),
          strokeWidth: 2.0,
          isFilled: true,
          fillColor: _subtopicFillColor(i),
          cornerRadius: 8.0,
          groupId: mindmapGroupId,
        ),
      );
      objects.add(
        TextObject(
          id: 'ai-text-$id',
          position: Offset(center.dx - w / 2 + 12, center.dy - 10),
          text: branch.title,
          color: const Color(0xFF0F172A),
          fontSize: 13.0,
          isBold: true,
          groupId: mindmapGroupId,
        ),
      );
      objects.add(
        LineObject(
          id: 'ai-arrow-$id',
          start: Offset(
            origin.dx + (rootWidth / 2) * math.cos(angle),
            origin.dy + (rootHeight / 2) * math.sin(angle),
          ),
          end: Offset(
            center.dx - (w / 2) * math.cos(angle),
            center.dy - (h / 2) * math.sin(angle),
          ),
          color: const Color(0xFF64748B),
          strokeWidth: 2.0,
          isArrow: true,
          groupId: mindmapGroupId,
        ),
      );

      // Leaf children fanned around the branch direction.
      final leaves = branch.children;
      final spread = math.min(0.9, (2 * math.pi / count) * 0.8);
      for (var j = 0; j < leaves.length; j++) {
        final t = leaves.length == 1 ? 0.0 : (j / (leaves.length - 1)) - 0.5;
        final leafAngle = angle + t * spread;
        final leafCenter = Offset(
          origin.dx + leafRadius * math.cos(leafAngle),
          origin.dy + leafRadius * math.sin(leafAngle),
        );
        final leafId = 'ai-leaf-${_uuid.v4().substring(0, 8)}';
        final lw = widthFor(leaves[j], 12, 110, 200);
        const lh = 40.0;
        objects.add(
          RectangleObject(
            id: leafId,
            rect: Rect.fromCenter(center: leafCenter, width: lw, height: lh),
            color: _subtopicColor(i).withValues(alpha: 0.7),
            strokeWidth: 1.5,
            isFilled: true,
            fillColor: Colors.white,
            cornerRadius: 6.0,
            groupId: mindmapGroupId,
          ),
        );
        objects.add(
          TextObject(
            id: 'ai-text-$leafId',
            position: Offset(leafCenter.dx - lw / 2 + 10, leafCenter.dy - 9),
            text: leaves[j],
            color: const Color(0xFF334155),
            fontSize: 12.0,
            groupId: mindmapGroupId,
          ),
        );
        objects.add(
          LineObject(
            id: 'ai-arrow-$leafId',
            start: center,
            end: leafCenter,
            color: const Color(0xFF94A3B8),
            strokeWidth: 1.5,
            groupId: mindmapGroupId,
          ),
        );
      }
    }
    // Connectors first so nodes render on top of them (stable partition so
    // every label stays above its own node rectangle).
    return [
      ...objects.whereType<LineObject>(),
      ...objects.where((o) => o is! LineObject),
    ];
  }

  // ---------------------------------------------------------------------------
  // 2. Shape recognition (on-device, instant)
  // ---------------------------------------------------------------------------

  /// Converts a rough hand-drawn freehand stroke into an aligned vector primitive
  /// (Rectangle, Circle, or Line).
  BoardObject? recognizeRoughShape(StrokeObject stroke) {
    final pts = stroke.points;
    if (pts.length < 5) return null;

    final bounds = stroke.bounds;
    final start = pts.first;
    final end = pts.last;
    final isClosed =
        (start - end).distance < math.max(bounds.width, bounds.height) * 0.35;

    // Check 1: Is it a straight line or arrow?
    final directDistance = (end - start).distance;
    var totalDistance = 0.0;
    for (var i = 1; i < pts.length; i++) {
      totalDistance += (pts[i] - pts[i - 1]).distance;
    }

    if (!isClosed &&
        directDistance > 0 &&
        (totalDistance / directDistance) < 1.25) {
      return LineObject(
        id: stroke.id,
        start: start,
        end: end,
        color: stroke.color,
        strokeWidth: stroke.strokeWidth,
        isArrow: true,
      );
    }

    // Check 2: Closed loop -> Rectangle or Circle
    if (isClosed && bounds.height > 0) {
      final aspectRatio = bounds.width / bounds.height;
      final isRoughlySquareOrCircle = aspectRatio > 0.75 && aspectRatio < 1.35;

      if (isRoughlySquareOrCircle) {
        return CircleObject(
          id: stroke.id,
          rect: bounds,
          color: stroke.color,
          strokeWidth: stroke.strokeWidth,
        );
      } else {
        return RectangleObject(
          id: stroke.id,
          rect: bounds,
          color: stroke.color,
          strokeWidth: stroke.strokeWidth,
          cornerRadius: 8.0,
        );
      }
    }

    return null;
  }

  // ---------------------------------------------------------------------------
  // 3. Board summary
  // ---------------------------------------------------------------------------

  static List<String> _collectTexts(List<BoardObject> objects) {
    final texts = <String>[];
    for (final obj in objects) {
      if (obj is TextObject && obj.text.trim().isNotEmpty) {
        texts.add(obj.text.trim());
      } else if (obj is StickyNoteObject && obj.text.trim().isNotEmpty) {
        // Skip previous AI summaries to avoid summarising summaries.
        if (!obj.text.startsWith('📋 AI Board Summary')) {
          texts.add(obj.text.trim());
        }
      }
    }
    return texts;
  }

  /// Summarises the board with Gemini when configured and the board contains
  /// text; otherwise uses the offline statistical summary.
  Future<AIResult<StickyNoteObject>> generateBoardSummarySmart(
    List<BoardObject> objects, {
    Offset position = const Offset(50, 50),
  }) async {
    final texts = _collectTexts(objects);
    if (!isConfigured || texts.isEmpty) {
      return AIResult(
        value: generateBoardSummary(objects, position: position),
        usedGemini: false,
        message: !isConfigured
            ? 'AI board summary generated.'
            : 'Board summary generated.',
      );
    }
    try {
      final joined = texts.take(80).map((t) => '- $t').join('\n');
      final json = await _generateJson(
        'Summarise these whiteboard notes for a team.\n$joined\n\n'
        'Return ONLY JSON: {"summary":"2-3 short sentences",'
        '"actionItems":["short imperative item", "..."]} '
        'with at most 5 action items.',
      );
      final summary = (json['summary'] ?? '').toString().trim();
      final items = (json['actionItems'] as List? ?? const [])
          .map((e) => e.toString().trim())
          .where((e) => e.isNotEmpty)
          .take(5)
          .toList();
      if (summary.isEmpty && items.isEmpty) {
        throw const GeminiException('Gemini returned an empty summary.');
      }
      final buffer = StringBuffer('📋 AI Board Summary\n\n');
      if (summary.isNotEmpty) buffer.writeln(summary);
      if (items.isNotEmpty) {
        buffer.writeln('\nAction Items:');
        for (final i in items) {
          buffer.writeln('☐ $i');
        }
      }
      final text = buffer.toString().trimRight();
      final lineCount = _estimateLines(text, charsPerLine: 34);
      return AIResult(
        value: StickyNoteObject(
          id: 'ai-summary-${_uuid.v4().substring(0, 8)}',
          rect: Rect.fromLTWH(
            position.dx,
            position.dy,
            280,
            (lineCount * 17.0 + 40).clamp(160.0, 520.0),
          ),
          text: text,
          color: const Color(0xFF065F46),
          noteColor: const Color(0xFFD1FAE5),
          fontSize: 12.0,
        ),
        usedGemini: true,
        message: 'Gemini summary added to the board.',
      );
    } on GeminiException catch (e) {
      return AIResult(
        value: generateBoardSummary(objects, position: position),
        usedGemini: false,
        message: '${e.message} Created an offline summary instead.',
      );
    }
  }

  static int _estimateLines(String text, {required int charsPerLine}) {
    var lines = 0;
    for (final l in text.split('\n')) {
      lines += math.max(1, (l.length / charsPerLine).ceil());
    }
    return lines;
  }

  /// Offline statistical summary card.
  StickyNoteObject generateBoardSummary(
    List<BoardObject> objects, {
    Offset position = const Offset(50, 50),
  }) {
    final texts = _collectTexts(objects);
    var stickyCount = 0;
    var shapeCount = 0;

    for (final obj in objects) {
      if (obj is StickyNoteObject) {
        stickyCount++;
      } else if (obj is RectangleObject ||
          obj is CircleObject ||
          obj is GeometricShapeObject) {
        shapeCount++;
      }
    }

    final buffer = StringBuffer('📋 AI Board Summary\n\n');
    buffer.writeln('• Total Elements: ${objects.length}');
    buffer.writeln('• Notes: $stickyCount | Diagrams: $shapeCount\n');

    if (texts.isNotEmpty) {
      buffer.writeln('Key Topics:');
      for (final t in texts.take(4)) {
        final oneLine = t.replaceAll('\n', ' ');
        buffer.writeln(
          '→ ${oneLine.length > 30 ? "${oneLine.substring(0, 27)}..." : oneLine}',
        );
      }
    } else {
      buffer.writeln('Brainstorming board ready for collaboration.');
    }

    return StickyNoteObject(
      id: 'ai-summary-${_uuid.v4().substring(0, 8)}',
      rect: Rect.fromLTWH(position.dx, position.dy, 240, 210),
      text: buffer.toString().trimRight(),
      color: const Color(0xFF065F46),
      noteColor: const Color(0xFFD1FAE5),
      fontSize: 12.0,
    );
  }

  // ---------------------------------------------------------------------------
  // Offline helpers
  // ---------------------------------------------------------------------------

  List<MindmapBranch> _offlineBranches(String topic) =>
      _deriveSubtopics(topic).map(MindmapBranch.new).toList();

  List<String> _deriveSubtopics(String topic) {
    final lower = topic.toLowerCase();
    if (lower.contains('architecture') || lower.contains('backend')) {
      return [
        'Client Apps',
        'API Gateway',
        'Microservices',
        'Database Cache',
        'Auth & Security',
      ];
    } else if (lower.contains('product') || lower.contains('roadmap')) {
      return [
        'User Research',
        'Core Features',
        'Design System',
        'Beta Release',
        'Analytics',
      ];
    } else if (lower.contains('marketing') || lower.contains('launch')) {
      return [
        'Landing Page',
        'Social Ads',
        'Influencer Demo',
        'PR & Press',
        'Email Funnel',
      ];
    }
    return ['Key Objectives', 'Milestones', 'Technical Risks', 'Deliverables'];
  }

  Color _subtopicColor(int index) {
    const colors = [
      Color(0xFF0D9488), // Teal
      Color(0xFF8B5CF6), // Purple
      Color(0xFFF59E0B), // Amber
      Color(0xFFE11D48), // Rose
      Color(0xFF2563EB), // Blue
      Color(0xFF16A34A), // Green
    ];
    return colors[index % colors.length];
  }

  Color _subtopicFillColor(int index) {
    const fills = [
      Color(0xFFCCFBF1), // Light Teal
      Color(0xFFEDE9FE), // Light Purple
      Color(0xFFFEF3C7), // Light Amber
      Color(0xFFFFE4E6), // Light Rose
      Color(0xFFDBEAFE), // Light Blue
      Color(0xFFDCFCE7), // Light Green
    ];
    return fills[index % fills.length];
  }
}

/// Holds the active Gemini API key (either passed via `--dart-define=GEMINI_API_KEY=...`
/// or entered in-app and saved to SharedPreferences).
class GeminiApiKeyNotifier extends Notifier<String> {
  static const _prefsKey = 'boardmate_gemini_api_key';

  @override
  String build() {
    _loadSavedKey();
    return kGeminiApiKey;
  }

  Future<void> _loadSavedKey() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(_prefsKey);
      if (saved != null && saved.trim().isNotEmpty && state.isEmpty) {
        state = saved.trim();
      }
    } catch (_) {
      // Ignore in test environments where SharedPreferences is not mocked
    }
  }

  Future<void> setApiKey(String key) async {
    final trimmed = key.trim();
    state = trimmed;
    try {
      final prefs = await SharedPreferences.getInstance();
      if (trimmed.isEmpty) {
        await prefs.remove(_prefsKey);
      } else {
        await prefs.setString(_prefsKey, trimmed);
      }
    } catch (_) {}
  }
}

final geminiApiKeyProvider = NotifierProvider<GeminiApiKeyNotifier, String>(
  GeminiApiKeyNotifier.new,
);

final geminiAIServiceProvider = Provider<GeminiAIService>((ref) {
  final activeKey = ref.watch(geminiApiKeyProvider);
  return GeminiAIService(
    apiKey: activeKey.isNotEmpty ? activeKey : kGeminiApiKey,
    model: kGeminiModel,
  );
});
