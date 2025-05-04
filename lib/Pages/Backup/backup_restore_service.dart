import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as path;

class BackupRestoreService {
  static const String _backupUrl = 'http://localhost/countronics/backup.php';
  static const String _restoreUrl = 'http://localhost/countronics/restore.php';

  /// Initiates a backup by downloading the database file and saving it to a user-selected location.
  Future<String> backupDatabase() async {
    try {
      print('Initiating backup request to: $_backupUrl');
      final response = await http.get(Uri.parse(_backupUrl));

      print('Backup response status: ${response.statusCode}');
      print('Backup response headers: ${response.headers}');

      if (response.statusCode == 200) {
        // Get filename from Content-Disposition header or use default
        String filename = 'backup_${DateTime.now().toIso8601String()}.db';
        final contentDisposition = response.headers['content-disposition'];
        if (contentDisposition != null) {
          final match = RegExp(r'filename="(.+)"').firstMatch(contentDisposition);
          if (match != null) filename = match.group(1)!;
        }

        // Let user choose save location
        String? outputPath = await FilePicker.platform.saveFile(
          dialogTitle: 'Save Backup File',
          fileName: filename,
          allowedExtensions: ['db'],
          type: FileType.custom,
        );

        if (outputPath == null) {
          print('Backup cancelled: No save location selected');
          return 'Backup cancelled: Please select a save location.';
        }

        // Save the file
        final file = File(outputPath);
        await file.writeAsBytes(response.bodyBytes);
        print('Backup saved to: $outputPath');
        return 'Backup saved successfully to $outputPath';
      } else {
        final errorMessage = response.headers['content-type']?.contains('json') == true
            ? response.body
            : 'Failed to download backup (Status: ${response.statusCode})';
        print('Backup error: $errorMessage');
        return 'Backup failed: $errorMessage';
      }
    } catch (e) {
      print('Backup exception: $e');
      return 'Backup failed: $e';
    }
  }

  /// Initiates a restore by uploading a user-selected .db file to the server.
  Future<String> restoreDatabase() async {
    try {
      // Let user select a .db file
      final result = await FilePicker.platform.pickFiles(
        dialogTitle: 'Select Database File to Restore',
        allowedExtensions: ['db'],
        type: FileType.custom,
      );

      if (result == null || result.files.isEmpty) {
        print('Restore cancelled: No file selected');
        return 'Restore cancelled: Please select a database file.';
      }

      final file = result.files.single;
      final filePath = file.path;
      if (filePath == null || !filePath.endsWith('.db')) {
        print('Restore error: Invalid file selected ($filePath)');
        return 'Restore failed: Please select a valid .db file.';
      }

      print('Initiating restore with file: $filePath');
      final request = http.MultipartRequest('POST', Uri.parse(_restoreUrl));
      request.files.add(await http.MultipartFile.fromPath('dbfile', filePath));

      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);

      print('Restore response status: ${response.statusCode}');
      print('Restore response body: ${response.body}');

      if (response.statusCode == 200) {
        print('Restore successful');
        return 'Database restored successfully.';
      } else {
        final errorMessage = response.headers['content-type']?.contains('json') == true
            ? response.body
            : 'Failed to restore database (Status: ${response.statusCode})';
        print('Restore error: $errorMessage');
        return 'Restore failed: $errorMessage';
      }
    } catch (e) {
      print('Restore exception: $e');
      return 'Restore failed: $e';
    }
  }
}