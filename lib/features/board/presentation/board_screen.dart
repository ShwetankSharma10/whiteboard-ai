import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../auth/presentation/providers/auth_provider.dart';
import '../data/board_export_service.dart';
import '../data/board_storage_service.dart';
import 'providers/board_provider.dart';
import 'providers/sync_provider.dart';
import '../domain/models/board_object.dart';
import '../domain/models/map_projection.dart';
import 'widgets/board_canvas.dart';
import 'widgets/board_toolbar.dart';

class BoardScreen extends ConsumerStatefulWidget {
  const BoardScreen({super.key, required this.boardId});

  final String boardId;

  @override
  ConsumerState<BoardScreen> createState() => _BoardScreenState();
}

class _BoardScreenState extends ConsumerState<BoardScreen> {
  final FocusNode _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(boardProvider.notifier).initBoard(widget.boardId);
      _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  void _handleKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent) return;

    final isCtrlOrCmd =
        HardwareKeyboard.instance.isControlPressed ||
        HardwareKeyboard.instance.isMetaPressed;
    final isShift = HardwareKeyboard.instance.isShiftPressed;
    final board = ref.read(boardProvider.notifier);

    // Ctrl + Z -> Undo
    if (isCtrlOrCmd &&
        !isShift &&
        event.logicalKey == LogicalKeyboardKey.keyZ) {
      board.undo();
      return;
    }

    // Ctrl + Shift + Z or Ctrl + Y -> Redo
    if ((isCtrlOrCmd &&
            isShift &&
            event.logicalKey == LogicalKeyboardKey.keyZ) ||
        (isCtrlOrCmd && event.logicalKey == LogicalKeyboardKey.keyY)) {
      board.redo();
      return;
    }

    // Ctrl + D -> Duplicate selected
    if (isCtrlOrCmd && event.logicalKey == LogicalKeyboardKey.keyD) {
      board.duplicateSelected();
      return;
    }

    // Delete or Backspace -> Delete selected
    if (event.logicalKey == LogicalKeyboardKey.delete ||
        event.logicalKey == LogicalKeyboardKey.backspace) {
      board.deleteSelected();
      return;
    }

    // Escape -> Deselect
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      board.selectById(null);
      return;
    }
  }

  void _showAIDialog(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Wrap(
          children: [
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: Row(
                children: [
                  Icon(Icons.auto_awesome, color: Colors.purpleAccent),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'AI Assistant',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                      ),
                    ),
                  ),
                  Chip(
                    avatar: Icon(
                      Icons.check_circle,
                      size: 16,
                      color: Colors.green,
                    ),
                    label: Text('AI Active'),
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
            ),
            const Divider(),
            ListTile(
              leading: const Icon(
                Icons.account_tree_outlined,
                color: Colors.blueAccent,
              ),
              title: const Text('Generate Mindmap from Prompt'),
              subtitle: const Text(
                'Convert any concept into an auto-aligned diagram',
              ),
              onTap: () {
                Navigator.of(ctx).pop();
                _promptMindmapCreation(context);
              },
            ),
            ListTile(
              leading: const Icon(Icons.auto_fix_high, color: Colors.amber),
              title: const Text('Clean Rough Sketch (Shape Recognition)'),
              subtitle: const Text(
                'Beautifies selected hand-drawn stroke into vector shape',
              ),
              onTap: () {
                Navigator.of(ctx).pop();
                final msg = ref
                    .read(boardProvider.notifier)
                    .cleanSelectedStrokeWithAI();
                _showAIMessage(msg);
              },
            ),
            ListTile(
              leading: const Icon(Icons.summarize_outlined, color: Colors.teal),
              title: const Text('Summarize Board & Action Items'),
              subtitle: const Text(
                'Scans all board objects and pins an AI summary card',
              ),
              onTap: () async {
                Navigator.of(ctx).pop();
                _showAIProgress('Summarising board…');
                final center = _visibleSceneCenter();
                final msg = await ref
                    .read(boardProvider.notifier)
                    .generateBoardSummaryWithAI(
                      position: center - const Offset(140, 100),
                    );
                _showAIMessage(msg);
              },
            ),
          ],
        ),
      ),
    );
  }

  /// Scene-space point currently at the centre of the screen, so generated
  /// content always appears where the user is looking.
  Offset _visibleSceneCenter() {
    final size = MediaQuery.of(context).size;
    return ref
        .read(viewportProvider)
        .toScene(Offset(size.width / 2, size.height / 2));
  }

  void _showAIProgress(String text) {
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 30),
        content: Row(
          children: [
            const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 12),
            Expanded(child: Text(text)),
          ],
        ),
      ),
    );
  }

  void _showAIMessage(String text) {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(content: Text(text), duration: const Duration(seconds: 4)),
    );
  }

  Future<void> _runMindmap(String topic) async {
    _showAIProgress('Generating mindmap for "$topic"…');
    final msg = await ref
        .read(boardProvider.notifier)
        .generateMindmapFromPrompt(topic, origin: _visibleSceneCenter());
    _showAIMessage(msg);
  }

  void _promptMindmapCreation(BuildContext context) {
    final controller = TextEditingController(text: 'E-Commerce Architecture');
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.auto_awesome, color: Colors.purpleAccent),
            SizedBox(width: 8),
            Text('Generate AI Mindmap'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Enter a topic or architecture prompt to generate connected nodes and arrows:',
              style: TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Topic Prompt',
                hintText: 'e.g. Microservices Architecture, Marketing Sprint',
              ),
              onSubmitted: (v) {
                Navigator.of(ctx).pop();
                if (v.trim().isNotEmpty) _runMindmap(v.trim());
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton.icon(
            icon: const Icon(Icons.auto_awesome, size: 16),
            label: const Text('Generate'),
            onPressed: () {
              Navigator.of(ctx).pop();
              final topic = controller.text.trim();
              if (topic.isNotEmpty) _runMindmap(topic);
            },
          ),
        ],
      ),
    );
  }

  void _showLocationExplorerDialog(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => _LocationExplorerSheet(
        onPanTo: (preset) {
          ref
              .read(boardProvider.notifier)
              .panToLocation(preset, screenSize: MediaQuery.of(context).size);
        },
        onDropPin: (preset) {
          final pos = const MercatorProjection().latLngToScene(
            preset.latitude,
            preset.longitude,
          );
          ref
              .read(boardProvider.notifier)
              .addMapPinAt(
                pos,
                label: preset.name,
                description:
                    '${preset.category} in ${preset.country} (${preset.region})',
              );
          ref
              .read(boardProvider.notifier)
              .panToLocation(preset, screenSize: MediaQuery.of(context).size);
        },
      ),
    );
  }

  void _showCollaborationHubDialog(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => _CollaborationHubSheet(boardId: widget.boardId),
    );
  }

  void _showExportShareDialog(BuildContext context) {
    var selectedAccess = ShareAccess.readWrite;

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) {
          final shareLink = ref
              .read(boardProvider.notifier)
              .getShareLink(access: selectedAccess);

          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.ios_share,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      const SizedBox(width: 10),
                      const Text(
                        'Share & Export Board',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Collaborative Access Link',
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      ChoiceChip(
                        label: const Text('Can Edit'),
                        selected: selectedAccess == ShareAccess.readWrite,
                        onSelected: (val) {
                          if (val) {
                            setModalState(
                              () => selectedAccess = ShareAccess.readWrite,
                            );
                          }
                        },
                      ),
                      const SizedBox(width: 8),
                      ChoiceChip(
                        label: const Text('View Only'),
                        selected: selectedAccess == ShareAccess.readOnly,
                        onSelected: (val) {
                          if (val) {
                            setModalState(
                              () => selectedAccess = ShareAccess.readOnly,
                            );
                          }
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: Theme.of(context)
                          .colorScheme
                          .surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            shareLink,
                            style: const TextStyle(
                              fontSize: 12,
                              fontFamily: 'monospace',
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.copy, size: 18),
                          tooltip: 'Copy Link',
                          onPressed: () {
                            Clipboard.setData(ClipboardData(text: shareLink));
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'Share link copied to clipboard!',
                                ),
                                duration: Duration(seconds: 2),
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Divider(),
                  const Text(
                    'Export Document Formats',
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                  ),
                  const SizedBox(height: 8),
                  ListTile(
                    leading: const Icon(
                      Icons.image_outlined,
                      color: Colors.blueAccent,
                    ),
                    title: const Text('High-Resolution PNG (2x Retina)'),
                    subtitle: const Text(
                      'Crisp raster image with white background',
                    ),
                    contentPadding: EdgeInsets.zero,
                    trailing: FilledButton.tonal(
                      child: const Text('Export'),
                      onPressed: () async {
                        Navigator.of(ctx).pop();
                        try {
                          final bytes = await ref
                              .read(boardProvider.notifier)
                              .exportPng();
                          final savedPath = await ref
                              .read(boardStorageServiceProvider)
                              .saveExportedPng(widget.boardId, bytes);
                          if (context.mounted) {
                            _showExportedPngPreviewDialog(
                              context,
                              bytes: bytes,
                              savedPath: savedPath,
                            );
                          }
                        } catch (e) {
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('Failed to export PNG: $e'),
                              ),
                            );
                          }
                        }
                      },
                    ),
                  ),
                  ListTile(
                    leading: const Icon(
                      Icons.polyline_outlined,
                      color: Colors.orangeAccent,
                    ),
                    title: const Text('Vector SVG (Scalable)'),
                    subtitle: const Text(
                      'Editable vectors for Illustrator, Figma, or Web',
                    ),
                    contentPadding: EdgeInsets.zero,
                    trailing: FilledButton.tonal(
                      child: const Text('Copy SVG'),
                      onPressed: () {
                        Navigator.of(ctx).pop();
                        final svg = ref
                            .read(boardProvider.notifier)
                            .exportSvg();
                        Clipboard.setData(ClipboardData(text: svg));
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              'SVG markup copied to clipboard (${(svg.length / 1024).toStringAsFixed(1)} KB)!',
                            ),
                            duration: const Duration(seconds: 3),
                          ),
                        );
                      },
                    ),
                  ),
                  ListTile(
                    leading: const Icon(
                      Icons.data_object_outlined,
                      color: Colors.teal,
                    ),
                    title: const Text('Board JSON Backup'),
                    subtitle: const Text(
                      'Complete raw backup of all objects & layers',
                    ),
                    contentPadding: EdgeInsets.zero,
                    trailing: FilledButton.tonal(
                      child: const Text('Copy JSON'),
                      onPressed: () {
                        Navigator.of(ctx).pop();
                        final json = ref
                            .read(boardProvider.notifier)
                            .exportJson();
                        Clipboard.setData(ClipboardData(text: json));
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Board JSON copied to clipboard!'),
                            duration: Duration(seconds: 2),
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  void _showExportedPngPreviewDialog(
    BuildContext context, {
    required Uint8List bytes,
    String? savedPath,
  }) {
    final sizeKb = (bytes.lengthInBytes / 1024).toStringAsFixed(1);
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.check_circle, color: Color(0xFF10B981)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'PNG Exported ($sizeKb KB)',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: 480,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                height: 260,
                width: double.infinity,
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                clipBehavior: Clip.antiAlias,
                child: InteractiveViewer(
                  minScale: 0.5,
                  maxScale: 4.0,
                  child: Center(
                    child: Image.memory(bytes, fit: BoxFit.contain),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              if (savedPath != null && savedPath.isNotEmpty) ...[
                const Text(
                  'Saved to device storage:',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF334155),
                  ),
                ),
                const SizedBox(height: 4),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: SelectableText(
                    savedPath,
                    style: const TextStyle(
                      fontSize: 11,
                      fontFamily: 'monospace',
                      color: Color(0xFF0F172A),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        actions: [
          if (savedPath != null && savedPath.isNotEmpty)
            TextButton.icon(
              icon: const Icon(Icons.copy, size: 16),
              label: const Text('Copy Path'),
              onPressed: () {
                Clipboard.setData(ClipboardData(text: savedPath));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('File path copied to clipboard!'),
                    duration: Duration(seconds: 2),
                  ),
                );
              },
            ),
          TextButton.icon(
            icon: const Icon(Icons.image_outlined, size: 16),
            label: const Text('Copy Base64 Image'),
            onPressed: () {
              final dataUri = 'data:image/png;base64,${base64Encode(bytes)}';
              Clipboard.setData(ClipboardData(text: dataUri));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('PNG Data URI copied to clipboard!'),
                  duration: Duration(seconds: 2),
                ),
              );
            },
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authStateProvider).value;
    final readOnly = user?.isAnonymous ?? false;
    final scale = ref.watch(viewportProvider.select((v) => v.scale));
    final hasObjects = ref.watch(
      boardProvider.select((s) => s.objects.isNotEmpty),
    );
    final isSaving = ref.watch(boardProvider.select((s) => s.isSaving));
    final statusMsg = ref.watch(boardProvider.select((s) => s.statusMessage));
    final syncMode = ref.watch(syncModeProvider);
    final isMapMode = ref.watch(boardProvider.select((s) => s.isMapMode));
    final canUndo = ref.watch(boardProvider.select((s) => s.canUndo));
    final canRedo = ref.watch(boardProvider.select((s) => s.canRedo));
    final collaborators = ref.watch(
      remoteCollaboratorsProvider(widget.boardId),
    );
    final screenWidth = MediaQuery.of(context).size.width;
    final isCompact = screenWidth < 680;

    return KeyboardListener(
      focusNode: _focusNode,
      autofocus: true,
      onKeyEvent: _handleKeyEvent,
      child: Scaffold(
        backgroundColor: Colors.white,
        appBar: PreferredSize(
          preferredSize: const Size.fromHeight(kToolbarHeight),
          child: Container(
            decoration: const BoxDecoration(
              color: Colors.white,
              border: Border(
                bottom: BorderSide(color: Color(0xFFE5E7EB), width: 1),
              ),
            ),
            child: AppBar(
              backgroundColor: Colors.white,
              surfaceTintColor: Colors.transparent,
              elevation: 0,
              leading: IconButton(
                icon: const Icon(Icons.arrow_back, color: Color(0xFF050038)),
                tooltip: 'Back',
                onPressed: () =>
                    context.canPop() ? context.pop() : context.go('/'),
              ),
              titleSpacing: 0,
              title: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFD02F), // Miro Yellow
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Center(
                      child: Text(
                        'S',
                        style: TextStyle(
                          color: Color(0xFF050038),
                          fontWeight: FontWeight.w900,
                          fontSize: 16,
                          letterSpacing: -0.5,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      widget.boardId == 'demo' ? 'SyncBoard Demo' : 'SyncBoard',
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFF050038),
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                        letterSpacing: -0.2,
                      ),
                    ),
                  ),
                  if (!isCompact) ...[
                    const SizedBox(width: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (isSaving)
                            const SizedBox(
                              width: 10,
                              height: 10,
                              child: CircularProgressIndicator(
                                strokeWidth: 1.5,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  Color(0xFF0D54FF),
                                ),
                              ),
                            )
                          else
                            Container(
                              width: 6,
                              height: 6,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: syncMode.isCloud
                                    ? const Color(0xFF10B981)
                                    : const Color(0xFF3B82F6),
                              ),
                            ),
                          const SizedBox(width: 6),
                          Text(
                            statusMsg,
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                              color: Color(0xFF64748B),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
              actions: [
                // Active Collaborators Avatar Stack with Miro borders
                if (collaborators.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (final col in collaborators.take(2))
                          Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 1.5,
                            ),
                            child: Tooltip(
                              message: '${col.userName} (${col.toolName})',
                              child: Container(
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: Colors.white,
                                    width: 2,
                                  ),
                                ),
                                child: CircleAvatar(
                                  radius: 12,
                                  backgroundColor: col.color,
                                  child: Text(
                                    col.userName.isNotEmpty
                                        ? col.userName[0].toUpperCase()
                                        : 'C',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        if (collaborators.length > 2)
                          Container(
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 2),
                            ),
                            child: CircleAvatar(
                              radius: 12,
                              backgroundColor: Colors.grey.shade700,
                              child: Text(
                                '+${collaborators.length - 2}',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 9,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),

                if (!isCompact && !readOnly)
                  IconButton(
                    icon: const Icon(
                      Icons.auto_awesome,
                      color: Color(0xFF8B5CF6),
                    ),
                    tooltip: 'Gemini AI Assistant',
                    onPressed: () => _showAIDialog(context),
                  ),
                if (!isCompact) ...[
                  IconButton(
                    icon: Icon(
                      isMapMode ? Icons.map : Icons.map_outlined,
                      color: isMapMode
                          ? const Color(0xFF0D54FF)
                          : const Color(0xFF64748B),
                    ),
                    tooltip: isMapMode
                        ? 'Switch to Whiteboard'
                        : 'Switch to Map Layer (Last Editor Location)',
                    onPressed: () => ref
                        .read(boardProvider.notifier)
                        .toggleMapMode(screenSize: MediaQuery.of(context).size),
                  ),
                  IconButton(
                    icon: const Icon(
                      Icons.explore_outlined,
                      color: Color(0xFF64748B),
                    ),
                    tooltip: 'Location Explorer',
                    onPressed: () => _showLocationExplorerDialog(context),
                  ),
                  IconButton(
                    icon: const Icon(
                      Icons.group_outlined,
                      color: Color(0xFF64748B),
                    ),
                    tooltip: 'Collaboration & Rooms',
                    onPressed: () => _showCollaborationHubDialog(context),
                  ),
                ],

                // Miro Yellow Share Pill Button
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 10,
                  ),
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFFFFD02F), // Miro Yellow
                      foregroundColor: const Color(0xFF050038), // Miro Charcoal
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(6),
                      ),
                      textStyle: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                    icon: const Icon(Icons.share, size: 14),
                    label: const Text('Share'),
                    onPressed: () => _showExportShareDialog(context),
                  ),
                ),

                if (!readOnly)
                  PopupMenuButton<String>(
                    tooltip: 'More options',
                    icon: const Icon(Icons.more_vert, color: Color(0xFF050038)),
                    onSelected: (v) {
                      if (v == 'clear') {
                        ref.read(boardProvider.notifier).clear();
                      } else if (v == 'simulate') {
                        ref.read(boardProvider.notifier).simulateCollaborator();
                      } else if (v == 'ai') {
                        _showAIDialog(context);
                      } else if (v == 'map') {
                        ref
                            .read(boardProvider.notifier)
                            .toggleMapMode(
                              screenSize: MediaQuery.of(context).size,
                            );
                      } else if (v == 'location') {
                        _showLocationExplorerDialog(context);
                      } else if (v == 'collab') {
                        _showCollaborationHubDialog(context);
                      } else if (v == 'export') {
                        _showExportShareDialog(context);
                      }
                    },
                    itemBuilder: (_) => [
                      if (isCompact) ...[
                        const PopupMenuItem(
                          value: 'ai',
                          child: ListTile(
                            leading: Icon(
                              Icons.auto_awesome,
                              color: Color(0xFF8B5CF6),
                            ),
                            title: Text('Gemini AI Assistant'),
                            contentPadding: EdgeInsets.zero,
                          ),
                        ),
                        PopupMenuItem(
                          value: 'map',
                          child: ListTile(
                            leading: Icon(
                              isMapMode ? Icons.brush : Icons.map_outlined,
                            ),
                            title: Text(
                              isMapMode
                                  ? 'Switch to Whiteboard'
                                  : 'Switch to Map Layer',
                            ),
                            contentPadding: EdgeInsets.zero,
                          ),
                        ),
                      ],
                      const PopupMenuItem(
                        value: 'location',
                        child: ListTile(
                          leading: Icon(Icons.travel_explore),
                          title: Text('Location Explorer...'),
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                      const PopupMenuItem(
                        value: 'collab',
                        child: ListTile(
                          leading: Icon(Icons.group_work_outlined),
                          title: Text('Collaboration Hub...'),
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                      const PopupMenuItem(
                        value: 'export',
                        child: ListTile(
                          leading: Icon(Icons.ios_share),
                          title: Text('Share & Export...'),
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                      const PopupMenuItem(
                        value: 'simulate',
                        child: ListTile(
                          leading: Icon(Icons.person_add_alt_1_outlined),
                          title: Text('Simulate collaborator'),
                          subtitle: Text(
                            'Demo real-time cursor & sync',
                            style: TextStyle(fontSize: 11),
                          ),
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                      const PopupMenuDivider(),
                      PopupMenuItem(
                        value: 'clear',
                        enabled: hasObjects,
                        child: const ListTile(
                          leading: Icon(Icons.delete_sweep_outlined),
                          title: Text('Clear board'),
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                    ],
                  ),
                const SizedBox(width: 4),
              ],
            ),
          ),
        ),
        body: LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 600;
            return Stack(
              children: [
                Positioned.fill(child: BoardCanvas(readOnly: readOnly)),

                if (readOnly)
                  Positioned(
                    top: 12,
                    left: 0,
                    right: 0,
                    child: Center(
                      child: Material(
                        color: const Color(0xFFFEF3C7),
                        elevation: 2,
                        borderRadius: BorderRadius.circular(20),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(20),
                          onTap: () {
                            ref
                                .read(authNotifierProvider.notifier)
                                .signInAsDemoEditor();
                          },
                          child: const Padding(
                            padding: EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 8,
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.visibility_outlined,
                                  size: 16,
                                  color: Color(0xFF92400E),
                                ),
                                SizedBox(width: 8),
                                Text(
                                  'View-Only Guest Mode • Tap here to Enable Editing',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xFF92400E),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),

                // Floating Miro Toolbar
                SafeArea(
                  child: Align(
                    alignment: wide
                        ? Alignment.centerLeft
                        : Alignment.bottomCenter,
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: SingleChildScrollView(
                        scrollDirection: wide ? Axis.vertical : Axis.horizontal,
                        child: BoardToolbar(vertical: wide, readOnly: readOnly),
                      ),
                    ),
                  ),
                ),

                // Miro Floating Bottom-Left Undo / Redo HUD
                if (!readOnly)
                  Positioned(
                    left: wide ? 80 : 16,
                    bottom: wide ? 16 : 84,
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFFE5E7EB)),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x14000000),
                            blurRadius: 14,
                            offset: Offset(0, 3),
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.undo_rounded, size: 18),
                            tooltip: 'Undo (Ctrl+Z)',
                            visualDensity: VisualDensity.compact,
                            onPressed: canUndo
                                ? () => ref.read(boardProvider.notifier).undo()
                                : null,
                            color: canUndo
                                ? const Color(0xFF050038)
                                : const Color(0xFFCBD5E1),
                          ),
                          Container(
                            width: 1,
                            height: 18,
                            color: const Color(0xFFE5E7EB),
                          ),
                          IconButton(
                            icon: const Icon(Icons.redo_rounded, size: 18),
                            tooltip: 'Redo (Ctrl+Y)',
                            visualDensity: VisualDensity.compact,
                            onPressed: canRedo
                                ? () => ref.read(boardProvider.notifier).redo()
                                : null,
                            color: canRedo
                                ? const Color(0xFF050038)
                                : const Color(0xFFCBD5E1),
                          ),
                        ],
                      ),
                    ),
                  ),

                // Miro Floating Bottom-Right Zoom HUD
                Positioned(
                  right: 16,
                  bottom: wide ? 16 : 84,
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFFE5E7EB)),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x14000000),
                          blurRadius: 14,
                          offset: Offset(0, 3),
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.remove, size: 18),
                          tooltip: 'Zoom out',
                          visualDensity: VisualDensity.compact,
                          color: const Color(0xFF050038),
                          onPressed: () {
                            final size = MediaQuery.of(context).size;
                            ref
                                .read(viewportProvider.notifier)
                                .zoomAt(
                                  Offset(size.width / 2, size.height / 2),
                                  0.8,
                                );
                          },
                        ),
                        InkWell(
                          onTap: ref.read(viewportProvider.notifier).reset,
                          borderRadius: BorderRadius.circular(4),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 4,
                            ),
                            child: Text(
                              '${(scale * 100).round()}%',
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF050038),
                              ),
                            ),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.add, size: 18),
                          tooltip: 'Zoom in',
                          visualDensity: VisualDensity.compact,
                          color: const Color(0xFF050038),
                          onPressed: () {
                            final size = MediaQuery.of(context).size;
                            ref
                                .read(viewportProvider.notifier)
                                .zoomAt(
                                  Offset(size.width / 2, size.height / 2),
                                  1.25,
                                );
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _LocationExplorerSheet extends ConsumerStatefulWidget {
  const _LocationExplorerSheet({
    required this.onPanTo,
    required this.onDropPin,
  });

  final ValueChanged<MapLocationPreset> onPanTo;
  final ValueChanged<MapLocationPreset> onDropPin;

  @override
  ConsumerState<_LocationExplorerSheet> createState() =>
      _LocationExplorerSheetState();
}

class _LocationExplorerSheetState extends ConsumerState<_LocationExplorerSheet>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  final TextEditingController _searchCtrl = TextEditingController();
  String _selectedCategory = 'All';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  static const _categories = [
    'All',
    'Tech Hub',
    'Cloud Region',
    'Capital',
    'Finance',
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pins = ref.watch(
      boardProvider.select((s) => s.objects.whereType<MapPinObject>().toList()),
    );

    final query = _searchCtrl.text;
    final allResults = MapLocationPreset.search(query);
    final filtered = _selectedCategory == 'All'
        ? allResults
        : allResults.where((p) => p.category == _selectedCategory).toList();

    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.82,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            child: Row(
              children: [
                const Icon(Icons.explore, color: Colors.blueAccent),
                const SizedBox(width: 10),
                const Text(
                  'Global Location Explorer & Tools',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),
          TabBar(
            controller: _tabController,
            tabs: [
              Tab(
                icon: const Icon(Icons.travel_explore, size: 20),
                text: 'Directory (${MapLocationPreset.presets.length})',
              ),
              Tab(
                icon: const Icon(Icons.straighten, size: 20),
                text: 'Pin Distance (${pins.length})',
              ),
            ],
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                // Tab 1: Directory & Search
                Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                      child: TextField(
                        controller: _searchCtrl,
                        onChanged: (_) => setState(() {}),
                        decoration: InputDecoration(
                          hintText:
                              'Search 60+ tech hubs, cloud regions, cities...',
                          prefixIcon: const Icon(Icons.search),
                          suffixIcon: _searchCtrl.text.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(Icons.clear),
                                  onPressed: () {
                                    _searchCtrl.clear();
                                    setState(() {});
                                  },
                                )
                              : null,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                          ),
                        ),
                      ),
                    ),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 4,
                      ),
                      child: Row(
                        children: [
                          for (final cat in _categories)
                            Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: ChoiceChip(
                                label: Text(cat),
                                selected: _selectedCategory == cat,
                                onSelected: (val) {
                                  if (val) {
                                    setState(() => _selectedCategory = cat);
                                  }
                                },
                              ),
                            ),
                        ],
                      ),
                    ),
                    const Divider(height: 12),
                    Expanded(
                      child: filtered.isEmpty
                          ? Center(
                              child: Text(
                                'No matching locations found for "${_searchCtrl.text}"',
                                style: TextStyle(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            )
                          : ListView.builder(
                              itemCount: filtered.length,
                              itemBuilder: (ctx, i) {
                                final p = filtered[i];
                                final isCloud = p.category == 'Cloud Region';
                                final isTech = p.category == 'Tech Hub';
                                return ListTile(
                                  leading: CircleAvatar(
                                    backgroundColor: isCloud
                                        ? Colors.amber.withValues(alpha: 0.2)
                                        : isTech
                                        ? Colors.blue.withValues(alpha: 0.2)
                                        : Colors.teal.withValues(alpha: 0.2),
                                    child: Icon(
                                      isCloud
                                          ? Icons.cloud
                                          : isTech
                                          ? Icons.memory
                                          : Icons.location_city,
                                      size: 18,
                                      color: isCloud
                                          ? Colors.orange
                                          : isTech
                                          ? Colors.blue
                                          : Colors.teal,
                                    ),
                                  ),
                                  title: Text(
                                    p.name,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  subtitle: Text(
                                    '${p.country} • ${p.region}  (${p.latitude.toStringAsFixed(2)}°, ${p.longitude.toStringAsFixed(2)}°)',
                                  ),
                                  trailing: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      IconButton(
                                        icon: const Icon(
                                          Icons.my_location,
                                          size: 20,
                                        ),
                                        tooltip: 'Pan Camera Here',
                                        onPressed: () {
                                          Navigator.of(context).pop();
                                          widget.onPanTo(p);
                                        },
                                      ),
                                      IconButton(
                                        icon: const Icon(
                                          Icons.add_location_alt_outlined,
                                          size: 20,
                                          color: Colors.blueAccent,
                                        ),
                                        tooltip: 'Drop Pin',
                                        onPressed: () {
                                          Navigator.of(context).pop();
                                          widget.onDropPin(p);
                                        },
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                    ),
                  ],
                ),

                // Tab 2: Geodesic Pin Distance Tool
                _PinDistanceCalculator(pins: pins),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PinDistanceCalculator extends StatefulWidget {
  const _PinDistanceCalculator({required this.pins});
  final List<MapPinObject> pins;

  @override
  State<_PinDistanceCalculator> createState() => _PinDistanceCalculatorState();
}

class _PinDistanceCalculatorState extends State<_PinDistanceCalculator> {
  String? _pinIdA;
  String? _pinIdB;

  @override
  void initState() {
    super.initState();
    if (widget.pins.length >= 2) {
      _pinIdA = widget.pins[0].id;
      _pinIdB = widget.pins[1].id;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.pins.length < 2) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.straighten, size: 48, color: Colors.grey),
              const SizedBox(height: 12),
              const Text(
                'Pin Distance Measurement',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              const SizedBox(height: 6),
              const Text(
                'Drop at least two map pins on your whiteboard canvas to measure real-world geodesic (Haversine) distance between them.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey),
              ),
            ],
          ),
        ),
      );
    }

    final pinA = widget.pins.firstWhere(
      (p) => p.id == _pinIdA,
      orElse: () => widget.pins.first,
    );
    final pinB = widget.pins.firstWhere(
      (p) => p.id == _pinIdB,
      orElse: () => widget.pins.length > 1 ? widget.pins[1] : widget.pins.first,
    );

    final distKm = MercatorProjection.distanceBetweenKm(
      pinA.latitude,
      pinA.longitude,
      pinB.latitude,
      pinB.longitude,
    );
    final distMiles = distKm * 0.621371;
    final flightHours = distKm / 850.0;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Measure Geodesic Distance Between Whiteboard Pins',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  initialValue: pinA.id,
                  decoration: const InputDecoration(
                    labelText: 'Pin 1 (Origin)',
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    for (final p in widget.pins)
                      DropdownMenuItem(
                        value: p.id,
                        child: Text(
                          p.label.isEmpty ? 'Pin' : p.label,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  onChanged: (id) => setState(() => _pinIdA = id),
                ),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 10),
                child: Icon(Icons.arrow_forward),
              ),
              Expanded(
                child: DropdownButtonFormField<String>(
                  initialValue: pinB.id,
                  decoration: const InputDecoration(
                    labelText: 'Pin 2 (Destination)',
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    for (final p in widget.pins)
                      DropdownMenuItem(
                        value: p.id,
                        child: Text(
                          p.label.isEmpty ? 'Pin' : p.label,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  onChanged: (id) => setState(() => _pinIdB = id),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Card(
            elevation: 2,
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      Column(
                        children: [
                          Text(
                            '${distKm.toStringAsFixed(1)} km',
                            style: const TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                              color: Colors.blueAccent,
                            ),
                          ),
                          const Text(
                            'Kilometers',
                            style: TextStyle(color: Colors.grey, fontSize: 12),
                          ),
                        ],
                      ),
                      Column(
                        children: [
                          Text(
                            '${distMiles.toStringAsFixed(1)} mi',
                            style: const TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                              color: Colors.green,
                            ),
                          ),
                          const Text(
                            'Miles',
                            style: TextStyle(color: Colors.grey, fontSize: 12),
                          ),
                        ],
                      ),
                      Column(
                        children: [
                          Text(
                            '~${flightHours.toStringAsFixed(1)} hrs',
                            style: const TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                              color: Colors.purpleAccent,
                            ),
                          ),
                          const Text(
                            'Flight Time (850 km/h)',
                            style: TextStyle(color: Colors.grey, fontSize: 12),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const Divider(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(
                        Icons.info_outline,
                        size: 14,
                        color: Colors.grey,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'From (${pinA.latitude.toStringAsFixed(2)}°, ${pinA.longitude.toStringAsFixed(2)}°) to (${pinB.latitude.toStringAsFixed(2)}°, ${pinB.longitude.toStringAsFixed(2)}°)',
                        style: const TextStyle(
                          fontSize: 11,
                          color: Colors.grey,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CollaborationHubSheet extends ConsumerStatefulWidget {
  const _CollaborationHubSheet({required this.boardId});

  final String boardId;

  @override
  ConsumerState<_CollaborationHubSheet> createState() =>
      _CollaborationHubSheetState();
}

class _CollaborationHubSheetState
    extends ConsumerState<_CollaborationHubSheet> {
  final TextEditingController _roomCtrl = TextEditingController();
  final TextEditingController _nameCtrl = TextEditingController();
  String? _followingCollaboratorId;

  @override
  void initState() {
    super.initState();
    _roomCtrl.text = widget.boardId;
    final user = ref.read(authStateProvider).value;
    _nameCtrl.text = user?.displayName ?? 'Collaborator';
  }

  @override
  void dispose() {
    _roomCtrl.dispose();
    _nameCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final collaborators = ref.watch(
      remoteCollaboratorsProvider(widget.boardId),
    );
    final syncMode = ref.watch(syncModeProvider);

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.group_work, color: Colors.green),
                const SizedBox(width: 10),
                const Text(
                  'Real-Time Collaboration Hub',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Room & Board ID',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _roomCtrl,
                            decoration: const InputDecoration(
                              labelText: 'Active Room Code',
                              border: OutlineInputBorder(),
                              contentPadding: EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 8,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        IconButton.filledTonal(
                          icon: const Icon(Icons.copy),
                          tooltip: 'Copy Room Code',
                          onPressed: () {
                            Clipboard.setData(
                              ClipboardData(text: _roomCtrl.text.trim()),
                            );
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Room code copied!'),
                              ),
                            );
                          },
                        ),
                        const SizedBox(width: 4),
                        FilledButton(
                          child: const Text('Switch'),
                          onPressed: () {
                            final target = _roomCtrl.text.trim();
                            if (target.isNotEmpty && target != widget.boardId) {
                              Navigator.of(context).pop();
                              context.go('/board/$target');
                            }
                          },
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Your Profile in this Room',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _nameCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Display Name',
                        prefixIcon: Icon(Icons.person_outline),
                        border: OutlineInputBorder(),
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                      ),
                      onSubmitted: (name) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Display name updated to $name'),
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                const Text(
                  'Active Collaborators',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                ),
                const SizedBox(width: 8),
                Chip(
                  label: Text('${collaborators.length + 1} online'),
                  visualDensity: VisualDensity.compact,
                ),
                const Spacer(),
                OutlinedButton.icon(
                  icon: const Icon(Icons.person_add_alt_1, size: 16),
                  label: const Text('Simulate User'),
                  onPressed: () {
                    ref.read(boardProvider.notifier).simulateCollaborator();
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Simulated collaborator joined!'),
                      ),
                    );
                  },
                ),
              ],
            ),
            const SizedBox(height: 8),
            ListTile(
              leading: const CircleAvatar(
                backgroundColor: Colors.blueAccent,
                child: Icon(Icons.person, color: Colors.white, size: 18),
              ),
              title: Text('${_nameCtrl.text} (You)'),
              subtitle: Text(
                'Sync: ${syncMode.isCloud ? "Cloud RTDB" : "Local Multi-client Broadcast"}',
              ),
              trailing: const Chip(
                label: Text('Active Host'),
                backgroundColor: Colors.greenAccent,
                visualDensity: VisualDensity.compact,
              ),
            ),
            for (final col in collaborators)
              ListTile(
                leading: CircleAvatar(
                  backgroundColor: col.color,
                  child: Text(
                    col.userName.isNotEmpty
                        ? col.userName[0].toUpperCase()
                        : 'C',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                title: Text(col.userName),
                subtitle: Text(
                  'Tool: ${col.toolName} • Pos: (${col.x.toInt()}, ${col.y.toInt()})',
                ),
                trailing: TextButton.icon(
                  icon: Icon(
                    _followingCollaboratorId == col.userId
                        ? Icons.videocam
                        : Icons.videocam_outlined,
                    size: 16,
                  ),
                  label: Text(
                    _followingCollaboratorId == col.userId
                        ? 'Following'
                        : 'Follow',
                  ),
                  onPressed: () {
                    setState(() {
                      if (_followingCollaboratorId == col.userId) {
                        _followingCollaboratorId = null;
                      } else {
                        _followingCollaboratorId = col.userId;
                        ref
                            .read(viewportProvider.notifier)
                            .centerOn(
                              Offset(col.x, col.y),
                              screenSize: MediaQuery.of(context).size,
                            );
                      }
                    });
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}
