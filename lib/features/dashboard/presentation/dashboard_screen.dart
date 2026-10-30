import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../auth/presentation/providers/auth_provider.dart';
import '../../board/data/board_storage_service.dart';
import '../../board/presentation/providers/sync_provider.dart';

class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  List<String> _boards = const ['demo'];
  bool _loadingBoards = true;

  @override
  void initState() {
    super.initState();
    _loadBoards();
  }

  Future<void> _loadBoards() async {
    setState(() => _loadingBoards = true);
    final storage = ref.read(boardStorageServiceProvider);
    final localBoards = await storage.getRecentBoards();
    final combined = <String>{...localBoards, 'demo'};

    // Also pull board IDs stored in Firebase Realtime Database if connected
    try {
      if (Firebase.apps.isNotEmpty) {
        final snap = await FirebaseDatabase.instance
            .ref('board_objects')
            .get()
            .timeout(const Duration(seconds: 4));
        final val = snap.value;
        if (val is Map) {
          for (final key in val.keys) {
            final id = key.toString().trim();
            if (id.isNotEmpty) combined.add(id);
          }
        }
      }
    } catch (_) {
      // Offline or RTDB rules not yet enabled; local boards still shown
    }

    if (!mounted) return;
    setState(() {
      _boards = combined.toList();
      _loadingBoards = false;
    });
  }

  Future<void> _openBoard(String boardId) async {
    await context.push('/board/$boardId');
    if (mounted) {
      _loadBoards();
    }
  }

  void _promptCreateOrJoinBoard() {
    final controller = TextEditingController();
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.add_box_outlined, color: Color(0xFF2563EB)),
            SizedBox(width: 8),
            Text('Create or Join Board'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Enter a board name or shared room ID (e.g. "architecture-v1" or "sprint-board"):',
              style: TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Board Name / Room ID',
                hintText: 'e.g. system-design',
                border: OutlineInputBorder(),
              ),
              onSubmitted: (v) {
                Navigator.of(ctx).pop();
                final slug = _sanitizeBoardId(v);
                _openBoard(slug);
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
            icon: const Icon(Icons.arrow_forward, size: 16),
            label: const Text('Open Board'),
            onPressed: () {
              Navigator.of(ctx).pop();
              final slug = _sanitizeBoardId(controller.text);
              _openBoard(slug);
            },
          ),
        ],
      ),
    );
  }

  String _sanitizeBoardId(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) {
      return 'board-${DateTime.now().millisecondsSinceEpoch.toString().substring(7)}';
    }
    // Firebase RTDB keys cannot contain . $ # [ ] /
    return trimmed.replaceAll(RegExp(r'[.$#\[\]/\s]+'), '-').toLowerCase();
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authStateProvider).value;
    final isGuest = user?.isAnonymous ?? false;
    final syncMode = ref.watch(syncModeProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('SyncBoard Workspace'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh Boards',
            onPressed: _loadBoards,
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Sign Out',
            onPressed: () {
              ref.read(authNotifierProvider.notifier).signOut();
            },
          ),
        ],
      ),
      floatingActionButton: isGuest
          ? null
          : FloatingActionButton.extended(
              icon: const Icon(Icons.add),
              label: const Text('New / Join Board'),
              onPressed: _promptCreateOrJoinBoard,
            ),
      body: RefreshIndicator(
        onRefresh: _loadBoards,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            // User & Database Status Header Card
            Card(
              elevation: 0,
              color: syncMode.isCloud
                  ? const Color(0xFFECFDF5)
                  : const Color(0xFFEFF6FF),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
                side: BorderSide(
                  color: syncMode.isCloud
                      ? const Color(0xFFA7F3D0)
                      : const Color(0xFFBFDBFE),
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    CircleAvatar(
                      backgroundColor: syncMode.isCloud
                          ? const Color(0xFF10B981)
                          : const Color(0xFF3B82F6),
                      foregroundColor: Colors.white,
                      child: Icon(
                        syncMode.isCloud ? Icons.cloud_done : Icons.storage,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Hello, ${user?.displayName ?? 'Demo Editor'}',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Collaborative Whiteboard Workspace Ready',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey.shade800,
                            ),
                          ),
                          if (isGuest)
                            const Padding(
                              padding: EdgeInsets.only(top: 4),
                              child: Text(
                                'Currently in View-Only Guest mode.',
                                style: TextStyle(
                                  color: Colors.deepOrange,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Your Whiteboards (${_boards.length})',
                  style: Theme.of(context).textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
                if (_loadingBoards)
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            for (final boardId in _boards)
              Card(
                margin: const EdgeInsets.only(bottom: 10),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: boardId == 'demo'
                        ? const Color(0xFFFFD02F)
                        : const Color(0xFFDBEAFE),
                    child: Icon(
                      boardId == 'demo'
                          ? Icons.star_rounded
                          : Icons.dashboard_outlined,
                      color: const Color(0xFF050038),
                    ),
                  ),
                  title: Text(
                    boardId == 'demo' ? 'SyncBoard Demo (Default)' : boardId,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  subtitle: Text(
                    'Interactive Whiteboard • ID: $boardId',
                    style: const TextStyle(fontSize: 12),
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (boardId != 'demo' && !isGuest)
                        IconButton(
                          icon: const Icon(
                            Icons.delete_outline,
                            color: Colors.redAccent,
                          ),
                          tooltip: 'Delete board',
                          onPressed: () async {
                            await ref
                                .read(boardStorageServiceProvider)
                                .deleteBoard(boardId);
                            _loadBoards();
                          },
                        ),
                      const Icon(Icons.chevron_right),
                    ],
                  ),
                  onTap: () => _openBoard(boardId),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
