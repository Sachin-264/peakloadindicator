import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:archive/archive_io.dart';
import 'package:peakloadindicator/constants/database_manager.dart';

import '../../constants/sessionmanager.dart';


class BackupRestoreService {
  static const String _diskMainDbName = 'Countronics.db';
  static const String _diskDataFolderName = 'CountronicsData';
  static const String _zipEntryMainDbInternalName = 'Countronics_Root.db';
  static const String _zipEntryDataFolderInternalPrefix = 'Countronics_User_Data/';

  BackupRestoreService();

  Future<String> _getMainDatabasePathOnDisk() async {
    final databasesPath = await getDatabasesPath();
    return path.join(databasesPath, _diskMainDbName);
  }

  Future<String> _getDataFolderPathOnDisk() async {
    final appSupportDir = await getApplicationSupportDirectory();
    return path.join(appSupportDir.path, _diskDataFolderName);
  }

  Future<String> backupDatabase() async {
    print("[BACKUP] Starting backup process...");
    try {
      final String mainDbPathOnDisk = await _getMainDatabasePathOnDisk();
      final File mainDbFileOnDisk = File(mainDbPathOnDisk);
      print("[BACKUP] Main DB path on disk: $mainDbPathOnDisk");

      final String dataFolderPathOnDisk = await _getDataFolderPathOnDisk();
      final Directory dataDirOnDisk = Directory(dataFolderPathOnDisk);
      print("[BACKUP] Data folder path on disk: $dataFolderPathOnDisk");

      bool mainDbExists = await mainDbFileOnDisk.exists();
      print("[BACKUP] Main DB exists: $mainDbExists");
      bool dataDirExists = await dataDirOnDisk.exists();
      print("[BACKUP] Data folder exists: $dataDirExists");

      List<File> filesInDataDir = [];
      if (dataDirExists) {
        print("[BACKUP] Listing files in data folder...");
        await for (final entity in dataDirOnDisk.list(recursive: false)) {
          if (entity is File) {
            filesInDataDir.add(entity);
            print("[BACKUP] Found data file: ${entity.path}");
          }
        }
        print("[BACKUP] Found ${filesInDataDir.length} files in data folder.");
      }

      if (!mainDbExists && filesInDataDir.isEmpty) {
        print("[BACKUP] No data found to back up. Aborting.");
        return 'Backup failed: No data found to back up (main database or files in data folder).';
      }

      String defaultFileName =
          'Countronics_AppBackup_${DateTime.now().toIso8601String().replaceAll(':', '-').split('.')[0]}.zip';
      print("[BACKUP] Default backup filename: $defaultFileName");

      String? outputPath = await FilePicker.platform.saveFile(
        dialogTitle: 'Save Application Backup',
        fileName: defaultFileName,
        allowedExtensions: ['zip'],
        type: FileType.custom,
        lockParentWindow: true,
      );

      if (outputPath == null) {
        print("[BACKUP] User cancelled save file dialog. Aborting.");
        return 'Backup cancelled by user.';
      }
      print("[BACKUP] User selected output path: $outputPath");

      if (!outputPath.toLowerCase().endsWith('.zip')) {
        outputPath += '.zip';
        print("[BACKUP] Appended .zip extension. New path: $outputPath");
      }

      final encoder = ZipFileEncoder();
      print("[BACKUP] Creating ZIP file at path: $outputPath");
      encoder.create(outputPath);
      bool contentAddedToZip = false;

      if (mainDbExists) {
        print("[BACKUP] Adding main DB to archive: $mainDbPathOnDisk as $_zipEntryMainDbInternalName");
        await encoder.addFile(mainDbFileOnDisk, _zipEntryMainDbInternalName);
        contentAddedToZip = true;
        print("[BACKUP] Main DB added to archive.");
      } else {
        print("[BACKUP] Main DB file not found on disk, skipping.");
      }

      if (dataDirExists && filesInDataDir.isNotEmpty) {
        print("[BACKUP] Adding ${filesInDataDir.length} data files to archive...");
        for (var fileEntityOnDisk in filesInDataDir) {
          final String fileNameOnDisk = path.basename(fileEntityOnDisk.path);
          final String pathInZip = path.join(_zipEntryDataFolderInternalPrefix, fileNameOnDisk);
          print("[BACKUP] Adding data file to archive: ${fileEntityOnDisk.path} as $pathInZip");
          await encoder.addFile(fileEntityOnDisk, pathInZip);
          print("[BACKUP] Data file ${fileEntityOnDisk.path} added.");
        }
        contentAddedToZip = true;
      } else {
        print("[BACKUP] Data folder not found or empty, skipping files from it.");
      }

      if (!contentAddedToZip) {
        print("[BACKUP] No content was added to the ZIP. Closing and deleting empty ZIP.");
        encoder.close();
        try {
          await File(outputPath).delete();
          print("[BACKUP] Empty ZIP file deleted: $outputPath");
        } catch (e) {
          print("[BACKUP] Could not delete empty ZIP file $outputPath: $e");
        }
        return 'Backup failed: Nothing was added to the backup archive.';
      }

      print("[BACKUP] Closing ZIP encoder.");
      encoder.close();
      print("[BACKUP] Backup archive created successfully at: $outputPath");
      return 'Backup saved successfully to $outputPath';
    } catch (e, s) {
      print("[BACKUP] EXCEPTION: $e\nStackTrace: $s");
      return 'Backup failed: An error occurred: $e';
    }
  }

  Future<String> restoreDatabase() async {
    print("[RESTORE] Starting restore process...");
    InputFileStream? inputStream;

    try {
      // File picker logic
      final result = await FilePicker.platform.pickFiles(
        dialogTitle: 'Select Application Backup to Restore',
        allowedExtensions: ['zip'],
        type: FileType.custom,
        lockParentWindow: true,
      );

      if (result == null || result.files.isEmpty) {
        print("[RESTORE] User cancelled file picker. Aborting.");
        return 'Restore cancelled by user.';
      }

      final PlatformFile selectedPlatformFile = result.files.single;
      final String? backupZipPath = selectedPlatformFile.path;

      if (backupZipPath == null || !backupZipPath.toLowerCase().endsWith('.zip')) {
        print("[RESTORE] Invalid file selected (not a .zip or path is null): $backupZipPath");
        return 'Restore failed: Please select a valid .zip archive.';
      }
      print("[RESTORE] Selected backup archive: $backupZipPath");

      final String activeMainDbPathOnDisk = await _getMainDatabasePathOnDisk();
      print("[RESTORE] Target main DB path on disk for restore: $activeMainDbPathOnDisk");
      final String activeDataFolderPathOnDisk = await _getDataFolderPathOnDisk();
      print("[RESTORE] Target data folder path on disk for restore: $activeDataFolderPathOnDisk");

      // Ensure the data folder's parent directory exists before permissions check
      final Directory dataDirParent = Directory(path.dirname(activeDataFolderPathOnDisk));
      print("[RESTORE] Ensuring parent directory exists: ${dataDirParent.path}");
      try {
        await dataDirParent.create(recursive: true);
        print("[RESTORE] Parent directory ensured/created: ${dataDirParent.path}");
      } catch (e) {
        print("[RESTORE] FAILED to create parent directory ${dataDirParent.path}: $e");
        return "Restore failed: Could not create parent directory for $activeDataFolderPathOnDisk. Please check permissions or run as administrator. Error: $e";
      }

      // Check write permissions for data folder
      print("[RESTORE] Checking write permissions for data folder: $activeDataFolderPathOnDisk");
      try {
        final Directory tempDataDir = Directory(activeDataFolderPathOnDisk);
        if (!await tempDataDir.exists()) {
          print("[RESTORE] Data folder does not exist. Creating for permissions check...");
          await tempDataDir.create(recursive: true);
          print("[RESTORE] Data folder created for permissions check.");
        }
        final tempFile = File(path.join(activeDataFolderPathOnDisk, '.test_permissions'));
        await tempFile.writeAsString('test');
        await tempFile.delete();
        print("[RESTORE] Write permissions verified for data folder.");
      } catch (e) {
        print("[RESTORE] No write permissions for data folder: $e");
        return "Restore failed: Application lacks permission to modify $activeDataFolderPathOnDisk. Please run as administrator or check folder permissions. Error: $e";
      }

      // Close all database connections
      print("[RESTORE] Closing current main database connection (Countronics.db)...");
      await DatabaseManager().close();
      print("[RESTORE] Main database connection (Countronics.db) reported closed.");

      print("[RESTORE] Closing ALL session databases (from CountronicsData folder)...");
      await SessionDatabaseManager().closeAllSessionDatabases();
      print("[RESTORE] Session databases closed. Any open databases left: ${SessionDatabaseManager().hasOpenDatabases}");

      // Extended delay to ensure file locks are released
      print("[RESTORE] Waiting 2 seconds to ensure file locks are released...");
      await Future.delayed(Duration(seconds: 2));

      // Deletion Logic with Retry and Fallback Rename
      final File activeMainDbFileOnDisk = File(activeMainDbPathOnDisk);
      if (await activeMainDbFileOnDisk.exists()) {
        print("[RESTORE] Existing main DB file found. Deleting: $activeMainDbPathOnDisk");
        try {
          await activeMainDbFileOnDisk.delete();
          print("[RESTORE] Successfully deleted existing main DB file.");
        } catch (e) {
          print("[RESTORE] FAILED to delete existing main DB file: $e. Aborting restore.");
          return "Restore failed: Could not delete existing main database file. Error: $e";
        }
      } else {
        print("[RESTORE] No existing main DB file found at $activeMainDbPathOnDisk. No deletion needed.");
      }

      final Directory activeDataDirOnDisk = Directory(activeDataFolderPathOnDisk);
      if (await activeDataDirOnDisk.exists()) {
        print("[RESTORE] Existing data folder found. Attempting to delete: $activeDataFolderPathOnDisk");
        bool deletedSuccessfully = false;
        for (int i = 0; i < 5; i++) {
          try {
            await activeDataDirOnDisk.delete(recursive: true);
            deletedSuccessfully = true;
            print("[RESTORE] Successfully deleted existing data folder on attempt ${i + 1}.");
            break;
          } catch (e) {
            print("[RESTORE] FAILED to delete existing data folder on attempt ${i + 1}: $e.");
            if (i < 4) {
              print("[RESTORE] Waiting for 2 seconds before retrying deletion...");
              await Future.delayed(Duration(seconds: 2));
            }
          }
        }

        // Fallback: Rename the folder if deletion fails
        if (!deletedSuccessfully) {
          print("[RESTORE] Deletion failed after 5 attempts. Attempting to rename folder...");
          final String timestamp = DateTime.now().toIso8601String().replaceAll(':', '-');
          final String renamedPath = "${activeDataFolderPathOnDisk}_backup_$timestamp";
          try {
            await activeDataDirOnDisk.rename(renamedPath);
            print("[RESTORE] Successfully renamed folder to: $renamedPath");
            deletedSuccessfully = true;
          } catch (e) {
            print("[RESTORE] FAILED to rename folder to $renamedPath: $e.");
            return "Restore failed: Could not delete or rename existing data folder. Files may be in use (e.g., by another application). Please close all applications and try again. Error: $e";
          }
        }

        if (!deletedSuccessfully) {
          return "Restore failed: Could not delete or rename existing data folder after multiple attempts.";
        }
      } else {
        print("[RESTORE] No existing data folder found at $activeDataFolderPathOnDisk. No deletion needed.");
      }

      // Re-create data folder structure
      print("[RESTORE] Re-creating data folder structure: $activeDataFolderPathOnDisk");
      try {
        await activeDataDirOnDisk.create(recursive: true);
        print("[RESTORE] Data folder structure re-created.");
      } catch (e) {
        print("[RESTORE] FAILED to re-create data folder structure: $e. Aborting restore.");
        return "Restore failed: Could not re-create data folder structure. Error: $e";
      }

      // ZIP extraction logic
      print("[RESTORE] Reading backup ZIP archive from: $backupZipPath");
      final Archive archive;
      inputStream = InputFileStream(backupZipPath);
      try {
        archive = ZipDecoder().decodeBuffer(inputStream);
        await inputStream.close();
        inputStream = null;
        print("[RESTORE] Backup ZIP archive decoded. Found ${archive.files.length} total entries (files and directories).");
      } catch (e) {
        print("[RESTORE] FAILED to read or decode ZIP archive: $e. Aborting restore.");
        if (inputStream != null) {
          try {
            await inputStream.close();
          } catch (_) {}
        }
        return "Restore failed: Could not read or decode the selected backup archive. Error: $e";
      }

      bool mainDbRestored = false;
      int dataFilesRestoredCount = 0;
      print("[RESTORE] Starting extraction loop for ${archive.files.length} archive entries...");

      for (final fileInArchive in archive.files) {
        print("[RESTORE] >> Processing archive entry: Name='${fileInArchive.name}', IsFile=${fileInArchive.isFile}, Size=${fileInArchive.size}, IsCompressed=${fileInArchive.isCompressed}, EndsWithSlash=${fileInArchive.name.endsWith('/')}");

        if (!fileInArchive.isFile) {
          print("[RESTORE] ---- Entry is not a file (likely a directory entry). Skipping '${fileInArchive.name}'.");
          continue;
        }

        final String outputPathOnDisk;
        bool isMainDbEntry = false;
        bool isDataFolderEntry = false;

        if (fileInArchive.name == _zipEntryMainDbInternalName) {
          print("[RESTORE] ---- Matched MAIN DB internal name: '${fileInArchive.name}'.");
          outputPathOnDisk = activeMainDbPathOnDisk;
          isMainDbEntry = true;
        } else if (fileInArchive.name.startsWith(_zipEntryDataFolderInternalPrefix)) {
          print("[RESTORE] ---- Matched DATA FOLDER prefix for: '${fileInArchive.name}'.");
          final String relativePath = fileInArchive.name.substring(_zipEntryDataFolderInternalPrefix.length);
          print("[RESTORE] ------ Calculated relativePath: '$relativePath'");

          if (relativePath.isEmpty) {
            print("[RESTORE] ------ Relative path is empty. Skipping '${fileInArchive.name}'.");
            continue;
          }
          if (relativePath.contains('..') || path.isAbsolute(relativePath)) {
            print("[RESTORE] ------ Potentially problematic relativePath '$relativePath'. Skipping '${fileInArchive.name}'.");
            continue;
          }
          outputPathOnDisk = path.join(activeDataFolderPathOnDisk, relativePath);
          isDataFolderEntry = true;
        } else {
          print("[RESTORE] ---- Unrecognized archive entry name '${fileInArchive.name}'. Skipping.");
          continue;
        }

        print("[RESTORE] ------ Determined outputPathOnDisk: '$outputPathOnDisk'");
        final File outFileOnDisk = File(outputPathOnDisk);
        final String parentDir = path.dirname(outFileOnDisk.path);

        print("[RESTORE] ------ Ensuring parent directory exists: '$parentDir'");
        try {
          await Directory(parentDir).create(recursive: true);
          print("[RESTORE] ------ Parent directory ensured/created.");
        } catch (e) {
          print("[RESTORE] ------ FAILED to create parent directory '$parentDir' for '$outputPathOnDisk': $e. Skipping this file.");
          continue;
        }

        final List<int> fileBytes;
        if (fileInArchive.content is List<int>) {
          fileBytes = fileInArchive.content as List<int>;
        } else {
          print("[RESTORE] ------ UNEXPECTED content type for ${fileInArchive.name}: ${fileInArchive.content.runtimeType}. Cannot process. Skipping this file.");
          continue;
        }

        print("[RESTORE] ------ Attempting to write ${fileBytes.length} bytes (Original Size in ZIP: ${fileInArchive.size}) to '$outputPathOnDisk'...");
        OutputFileStream? outputStream;
        try {
          outputStream = OutputFileStream(outputPathOnDisk);
          outputStream.writeBytes(fileBytes);
          print("[RESTORE] ------ Successfully wrote file: '$outputPathOnDisk'");
          if (isMainDbEntry) mainDbRestored = true;
          if (isDataFolderEntry) dataFilesRestoredCount++;
        } catch (e) {
          print("[RESTORE] ------ FAILED to write file '$outputPathOnDisk': $e. Skipping this file.");
        } finally {
          if (outputStream != null) {
            try {
              await outputStream.close();
              print("[RESTORE] ------ Output stream closed for '$outputPathOnDisk'.");
            } catch (closeError) {
              print("[RESTORE] ------ Error closing output stream for '$outputPathOnDisk': $closeError");
            }
          }
        }
      }
      print("[RESTORE] Finished extraction loop.");

      if (!mainDbRestored && dataFilesRestoredCount == 0) {
        print("[RESTORE] WARNING: No recognized files were successfully restored from the archive.");
        return 'Restore failed: Archive did not contain expected application data or files could not be written.';
      }
      if (!mainDbRestored) {
        print("[RESTORE] WARNING: Main database ('$_zipEntryMainDbInternalName') was not found or restored from the archive.");
      }
      bool dataFilesWereExpectedInZip = archive.files.any((f) => f.isFile && f.name.startsWith(_zipEntryDataFolderInternalPrefix) && f.name.substring(_zipEntryDataFolderInternalPrefix.length).isNotEmpty);
      if (dataFilesWereExpectedInZip && dataFilesRestoredCount == 0) {
        print("[RESTORE] WARNING: Data folder files were expected based on ZIP content under '$_zipEntryDataFolderInternalPrefix', but none were restored.");
      } else if (!dataFilesWereExpectedInZip && dataFilesRestoredCount == 0) {
        print("[RESTORE] INFO: No data folder files were restored, and none seemed to be actual files under '$_zipEntryDataFolderInternalPrefix' in the ZIP.");
      }

      print("[RESTORE] Restore process completed. Main DB restored flag: $mainDbRestored. Data files restored count: $dataFilesRestoredCount.");
      return 'Application data restored successfully from $backupZipPath. Please restart the application for changes to take full effect.';
    } catch (e, s) {
      print("[RESTORE] GLOBAL EXCEPTION: $e\nStackTrace: $s");
      if (inputStream != null) {
        try {
          await inputStream.close();
          print("[RESTORE] Input stream closed in global exception handler.");
        } catch (closeError) {
          print("[RESTORE] Error closing input stream in global exception handler: $closeError");
        }
      }
      return 'Restore failed: A global error occurred ($e). The application might be in an unstable state. Please restart.';
    }
  }
}



