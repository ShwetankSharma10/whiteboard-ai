abstract class BoardStoragePlatform {
  Future<void> save(String boardId, String jsonStr);
  Future<String?> load(String boardId);
  Future<void> delete(String boardId);

  /// Saves exported PNG [bytes] with [fileName] to device Downloads/Documents
  /// and returns the saved file path (or null on web/unsupported).
  Future<String?> saveExportedPng(String fileName, List<int> bytes);
}

BoardStoragePlatform getBoardStoragePlatform() =>
    throw UnsupportedError('Cannot create platform storage');
