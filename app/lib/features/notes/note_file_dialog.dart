import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

class NotePickedFile {
  const NotePickedFile(this.name, this.bytes);
  final String name;
  final Uint8List bytes;
}

class NoteFileDialog {
  static const _channel = MethodChannel('worknotes/notes_files');

  static Future<NotePickedFile?> pick() async {
    if (Platform.isAndroid) {
      final value = await _channel.invokeMapMethod<String, dynamic>('pick');
      if (value == null) return null;
      return NotePickedFile(
        value['name'] as String,
        value['bytes'] as Uint8List,
      );
    }
    if (Platform.isWindows) {
      const script = r'''
Add-Type -AssemblyName System.Windows.Forms
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$dialog = New-Object System.Windows.Forms.OpenFileDialog
$dialog.Filter = 'Фото и аудио|*.jpg;*.jpeg;*.png;*.gif;*.webp;*.mp3;*.wav;*.ogg;*.m4a;*.mp4;*.webm'
if ($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
  [Console]::WriteLine($dialog.FileName)
}
''';
      final result = await Process.run('powershell.exe', [
        '-NoProfile',
        '-STA',
        '-Command',
        script,
      ], stdoutEncoding: utf8);
      if (result.exitCode != 0) {
        throw FileSystemException(
          'Не удалось выбрать файл',
          result.stderr.toString(),
        );
      }
      final path = (result.stdout as String).trim();
      if (path.isEmpty) return null;
      final file = File(path);
      return NotePickedFile(
        path.split(Platform.pathSeparator).last,
        await file.readAsBytes(),
      );
    }
    throw UnsupportedError('Выбор вложений доступен на Windows и Android');
  }

  static Future<void> save(String filename, Uint8List bytes) async {
    if (Platform.isAndroid) {
      await _channel.invokeMethod<void>('save', {
        'name': filename,
        'bytes': bytes,
      });
      return;
    }
    if (Platform.isWindows) {
      const script = r'''
Add-Type -AssemblyName System.Windows.Forms
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$dialog = New-Object System.Windows.Forms.SaveFileDialog
$dialog.FileName = $env:WORKNOTES_FILENAME
if ($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
  [Console]::WriteLine($dialog.FileName)
}
''';
      final result = await Process.run(
        'powershell.exe',
        ['-NoProfile', '-STA', '-Command', script],
        stdoutEncoding: utf8,
        environment: {'WORKNOTES_FILENAME': filename},
      );
      if (result.exitCode != 0) {
        throw FileSystemException(
          'Не удалось сохранить файл',
          result.stderr.toString(),
        );
      }
      final path = (result.stdout as String).trim();
      if (path.isNotEmpty) await File(path).writeAsBytes(bytes);
      return;
    }
    throw UnsupportedError('Сохранение вложений доступно на Windows и Android');
  }
}
