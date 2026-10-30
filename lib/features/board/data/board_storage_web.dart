import 'package:shared_preferences/shared_preferences.dart';

import 'board_storage_platform.dart';
export 'board_storage_platform.dart';

class BoardStorageWeb implements BoardStoragePlatform {
  @override
  Future<void> save(String boardId, String jsonStr) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('syncboard_board_$boardId', jsonStr);
  }

  @override
  Future<String?> load(String boardId) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('syncboard_board_$boardId');
  }

  @override
  Future<void> delete(String boardId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('syncboard_board_$boardId');
  }

  @override
  Future<String?> saveExportedPng(String fileName, List<int> bytes) async {
    return 'Browser Memory ($fileName)';
  }
}

BoardStoragePlatform getBoardStoragePlatform() => BoardStorageWeb();
