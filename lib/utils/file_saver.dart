// lib/utils/file_saver.dart

import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class FileSaver {
  static Future<String> saveToDownloads({
    required List<int> bytes,
    required String fileName,
  }) async {
    Directory dir;

    if (Platform.isAndroid) {
      dir = Directory('/storage/emulated/0/Download');
      if (!await dir.exists()) {
        dir = Directory('/storage/emulated/0/download');
      }
    } else if (Platform.isWindows) {
      final userProfile = Platform.environment['USERPROFILE'];

      if (userProfile == null) {
        throw Exception("USERPROFILE not found");
      }
      final downloadsPath = p.join(userProfile, 'Downloads');
      dir = Directory(downloadsPath);

      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
    } else {
      dir = await getApplicationDocumentsDirectory();
    }
    await dir.create(recursive: true);

    return _writeWithRename(dir: dir, bytes: bytes, fileName: fileName);
  }

  static Future<String> _writeWithRename({
    required Directory dir,
    required List<int> bytes,
    required String fileName,
  }) async {
    final dot = fileName.lastIndexOf('.');
    final hasExt = dot > 0 && dot < fileName.length - 1;

    final base = hasExt ? fileName.substring(0, dot) : fileName;
    final ext = hasExt ? fileName.substring(dot) : '';

    int n = 0;

    String makeName(int n) => (n == 0) ? '$base$ext' : '$base ($n)$ext';

    while (true) {
      final name = makeName(n);
      final path = p.join(dir.path, name);
      final file = File(path);

      try {
        await file.create(exclusive: true);
        await file.writeAsBytes(bytes, flush: true);
        return file.path;
      } catch (e) {
        n++;
      }
    }
  }
}