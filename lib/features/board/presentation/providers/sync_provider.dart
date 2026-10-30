import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../auth/presentation/providers/auth_provider.dart';
import '../../data/board_sync_repository.dart';
import '../../domain/models/board_object.dart';
import '../../domain/models/presence.dart';

enum SyncMode {
  cloud('Live (Firebase RTDB)', true),
  local('Local Sync', false);

  const SyncMode(this.label, this.isCloud);
  final String label;
  final bool isCloud;
}

/// Streams the real-time presence map {userId: UserPresence} for a board.
final boardPresenceStreamProvider =
    StreamProvider.family<Map<String, UserPresence>, String>((ref, boardId) {
      final repo = ref.watch(boardSyncRepositoryProvider);
      return repo.watchPresence(boardId);
    });

/// Streams discrete remote board objects for a board.
final boardRemoteObjectsStreamProvider =
    StreamProvider.family<List<BoardObject>, String>((ref, boardId) {
      final repo = ref.watch(boardSyncRepositoryProvider);
      return repo.watchObjects(boardId);
    });

/// Returns only remote collaborators (excluding current logged-in user).
final remoteCollaboratorsProvider = Provider.family<List<UserPresence>, String>(
  (ref, boardId) {
    final presenceAsync = ref.watch(boardPresenceStreamProvider(boardId));
    final currentUserId =
        ref.watch(authStateProvider).value?.uid ?? 'editor-demo-1';

    return presenceAsync.when(
      data: (presenceMap) {
        return presenceMap.values
            .where((p) => p.userId != currentUserId && p.isOnline())
            .toList();
      },
      loading: () => const [],
      error: (_, _) => const [],
    );
  },
);

/// Active sync mode (Cloud vs Local Broadcast).
final syncModeProvider = Provider<SyncMode>((ref) {
  final repo = ref.watch(boardSyncRepositoryProvider);
  return repo.isCloudSync ? SyncMode.cloud : SyncMode.local;
});
