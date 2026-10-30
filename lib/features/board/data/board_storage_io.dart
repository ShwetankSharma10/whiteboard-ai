import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'board_storage_platform.dart';
export 'board_storage_platform.dart';

class BoardStorageIo implements BoardStoragePlatform {
  Future<Directory> _getBoardsDir() async {
    final docsDir = await getApplicationDocumentsDirectory();
    final boardsDir = Directory('${docsDir.path}/boards');
    if (!await boardsDir.exists()) {
      await boardsDir.create(recursive: true);
    }
    return boardsDir;
  }

  @override
  Future<void> save(String boardId, String jsonStr) async {
    final dir = await _getBoardsDir();
    final file = File('${dir.path}/$boardId.json');
    await file.writeAsString(jsonStr, flush: true);
  }

  @override
  Future<String?> load(String boardId) async {
    final dir = await _getBoardsDir();
    final file = File('${dir.path}/$boardId.json');
    if (!await file.exists()) return null;
    return await file.readAsString();
  }

  @override
  Future<void> delete(String boardId) async {
    final dir = await _getBoardsDir();
    final file = File('${dir.path}/$boardId.json');
    if (await file.exists()) {
      await file.delete();
    }
  }

  @override
  Future<String?> saveExportedPng(String fileName, List<int> bytes) async {
    // 1. On Android, try public Downloads folder first so it appears in Files app
    if (Platform.isAndroid) {
      try {
        final androidDownloadDir = Directory('/storage/emulated/0/Download');
        if (await androidDownloadDir.exists()) {
          final out = File('${androidDownloadDir.path}/$fileName');
          await out.writeAsBytes(bytes, flush: true);
          return out.path;
        }
      } catch (_) {
        // Fall through to app-specific external / documents directory
      }
      try {
        final extDir = await getExternalStorageDirectory();
        if (extDir != null) {
          final out = File('${extDir.path}/$fileName');
          await out.writeAsBytes(bytes, flush: true);
          return out.path;
        }
      } catch (_) {}
    }

    // 2. Desktop Downloads directory or Application Documents directory
    try {
      final downloadsDir = await getDownloadsDirectory();
      if (downloadsDir != null && await downloadsDir.exists()) {
        final out = File('${downloadsDir.path}/$fileName');
        await out.writeAsBytes(bytes, flush: true);
        return out.path;
      }
    } catch (_) {}

    final docsDir = await getApplicationDocumentsDirectory();
    final exportsDir = Directory('${docsDir.path}/exports');
    if (!await exportsDir.exists()) {
      await exportsDir.create(recursive: true);
    }
    final out = File('${exportsDir.path}/$fileName');
    await out.writeAsBytes(bytes, flush: true);
    return out.path;
  }
}

BoardStoragePlatform getBoardStoragePlatform() => BoardStorageIo();
