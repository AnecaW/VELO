import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

class AppStorage {
  const AppStorage();

  static const String _selectedProfileIdKey = 'selected_activity_profile_id';

  Future<String?> readSelectedProfileId() async {
    final file = await _file();
    if (!await file.exists()) {
      return null;
    }

    final contents = await file.readAsString();
    if (contents.trim().isEmpty) {
      return null;
    }

    return contents.trim();
  }

  Future<void> writeSelectedProfileId(String profileId) async {
    final file = await _file();
    await file.writeAsString(profileId);
  }

  Future<void> clearSelectedProfileId() async {
    final file = await _file();
    if (await file.exists()) {
      await file.delete();
    }
  }

  Future<File> _file() async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      return File(
        '${directory.path}${Platform.pathSeparator}$_selectedProfileIdKey.txt',
      );
    } on MissingPluginException {
      final directory = Directory(
        '${Directory.systemTemp.path}${Platform.pathSeparator}bike_computer_storage',
      );
      if (!await directory.exists()) {
        await directory.create(recursive: true);
      }
      return File(
        '${directory.path}${Platform.pathSeparator}$_selectedProfileIdKey.txt',
      );
    } on PlatformException {
      final directory = Directory(
        '${Directory.systemTemp.path}${Platform.pathSeparator}bike_computer_storage',
      );
      if (!await directory.exists()) {
        await directory.create(recursive: true);
      }
      return File(
        '${directory.path}${Platform.pathSeparator}$_selectedProfileIdKey.txt',
      );
    }
  }
}
