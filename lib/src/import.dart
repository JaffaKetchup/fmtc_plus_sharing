// Copyright © Luka S (JaffaKetchup) under GPL-v3
// A full license can be found at .\LICENSE

// ignore_for_file: invalid_use_of_internal_member, invalid_use_of_protected_member

import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map_tile_caching/flutter_map_tile_caching.dart';
import 'package:flutter_map_tile_caching/fmtc_module_api.dart';
import 'package:isar/isar.dart';
import 'package:path/path.dart' as p;

/// Extends [RootImport] (accessed through [RootDirectory.import]) with the
/// import functionality
extension FMTCImportSharingModule on RootImport {
  /// Import store files with the platform specifc file picker interface
  ///
  /// Where supported, the user will only be able to pick files with the
  /// [fileExtension] extension ('fmtc' by default). If not supported, any file
  /// can be picked, but only those with the [fileExtension] extension will be
  /// processed.
  ///
  /// Disabling [emptyCacheBeforePicking] is not recommended (defaults to
  /// `true`). When disabled, the picker may use cached files as opposed to the
  /// real files, which may yield unexpected results. This is only effective on
  /// Android and iOS - other platforms cannot use caching.
  ///
  /// Setting [collisionHandler] allows for custom behaviour in the event that
  /// a store with the same name already exists. If it returns `true`, the store
  /// will be overwritten, otherwise (and by default) the import will fail.
  ///
  /// Returns a [Map] of the input filename to its corresponding [ImportResult].
  Future<Map<String, Future<ImportResult>>?> withGUI({
    String fileExtension = 'fmtc',
    bool emptyCacheBeforePicking = true,
    FutureOr<bool> Function(String filename, String storeName)?
        collisionHandler,
  }) async {
    if (emptyCacheBeforePicking && (Platform.isAndroid || Platform.isIOS)) {
      await FilePicker.platform.clearTemporaryFiles();
    }

    late final FilePickerResult? importPaths;
    try {
      importPaths = await FilePicker.platform.pickFiles(
        dialogTitle: 'Import Cache Stores',
        type: FileType.custom,
        allowedExtensions: [fileExtension],
        allowMultiple: true,
      );
    } on PlatformException catch (_) {
      importPaths = await FilePicker.platform.pickFiles(
        dialogTitle: 'Import Cache Stores',
        allowMultiple: true,
      );
    }

    final files = importPaths?.files.where((f) => f.extension == fileExtension);
    if (files == null || files.isEmpty) return null;
    return manual(
      files.map((e) => File(e.path!)).toList(),
      collisionHandler: collisionHandler,
    );
  }

  /// Import stores from specified [inputFiles]
  ///
  /// Setting [collisionHandler] allows for custom behaviour in the event that
  /// a store with the same name already exists. If it returns `true`, the store
  /// will be overwritten, otherwise (and by default) the import will fail.
  ///
  /// Note that there are no checks to confirm that the listed [inputFiles] are
  /// valid Isar databases. Attempting to import other files or corrupted
  /// databases may cause the app to crash.
  ///
  /// Also see [withGUI] for a prebuilt solution to allow the user to select
  /// files to import.
  ///
  /// Returns a [Map] of the input filename to its corresponding [ImportResult].
  Map<String, Future<ImportResult>> manual(
    List<File> inputFiles, {
    FutureOr<bool> Function(String filename, String storeName)?
        collisionHandler,
  }) =>
      Map.fromEntries(
        inputFiles.map(
          (f) => MapEntry(
            p.basename(f.path),
            () async {
              // Quit if the input file no longer exists
              if (!await f.exists()) {
                return const ImportResult._(storeName: null, successful: false);
              }

              // Create the temporary directory
              final tmpDir =
                  FMTC.instance.rootDirectory.directory >> 'temporary';
              await tmpDir.create();

              // Construct temporary structures to read the Isar database at an
              // appropriate location
              final tmpPath = tmpDir >
                  '.import${DateTime.now().millisecondsSinceEpoch}.isar';
              final tmpFile = File(tmpPath);
              Isar? tmpDb;

              // Copy the target file to the temporary file and try to open it
              await f.copy(tmpPath);
              try {
                tmpDb = await Isar.open(
                  [DbStoreDescriptorSchema, DbTileSchema, DbMetadataSchema],
                  name: tmpPath.replaceAll('.isar', ''),
                  directory:
                      (FMTC.instance.rootDirectory.directory >> 'temporary')
                          .absolute
                          .path,
                  maxSizeMiB: FMTC.instance.settings.databaseMaxSize,
                  compactOnLaunch:
                      FMTC.instance.settings.databaseCompactCondition,
                  inspector: FMTC.instance.debugMode,
                );
              } catch (_) {
                if (tmpDb != null && tmpDb.isOpen) await tmpDb.close();
                if (await tmpDir.exists()) await tmpDir.delete(recursive: true);
                return const ImportResult._(storeName: null, successful: false);
              }

              // Read the store name from within the temporary database, closing
              // it afterward
              final storeName = (await tmpDb.storeDescriptor.get(0))?.name;
              if (storeName == null) {
                return const ImportResult._(storeName: null, successful: false);
              }
              if (tmpDb.isOpen) await tmpDb.close();

              // Check if there is a conflict with an existing store
              if (FMTC.instance(storeName).manage.ready) {
                if (!await (collisionHandler?.call(
                      p.basename(f.path),
                      storeName,
                    ) ??
                    false)) {
                  if (await tmpDir.exists()) {
                    await tmpDir.delete(recursive: true);
                  }
                  return ImportResult._(
                    storeName: storeName,
                    successful: false,
                  );
                }
                await FMTC.instance(storeName).manage.delete();
              }

              // Calculate the store's ID, and rename the temporary file to it
              final storeId = DatabaseTools.hash(storeName);
              await tmpFile.rename(
                (FMTC.instance.rootDirectory.directory >> '$storeId.isar')
                    .absolute
                    .path,
              );

              // Register the new store instance
              // Doesn't require error catching, as the same database has already
              // been opened.
              FMTCRegistry.instance.register(
                storeId,
                await Isar.open(
                  [DbStoreDescriptorSchema, DbTileSchema, DbMetadataSchema],
                  name: storeId.toString(),
                  directory: FMTC.instance.rootDirectory.directory.path,
                  maxSizeMiB: FMTC.instance.settings.databaseMaxSize,
                  compactOnLaunch:
                      FMTC.instance.settings.databaseCompactCondition,
                  inspector: FMTC.instance.debugMode,
                ),
              );

              // Delete temporary structures
              if (await tmpDir.exists()) await tmpDir.delete(recursive: true);

              return ImportResult._(storeName: storeName, successful: true);
            }(),
          ),
        ),
      );
}

/// Represents the state of an import
///
/// Note that [storeName] may be different to the import file's name. In this
/// case, the [MapEntry] for which this object is the value will have the
/// filename as the key.
class ImportResult {
  /// The store name, as it will be imported
  ///
  /// Note that this may be different to the import file's name. In this case,
  /// the [MapEntry] for which this object is the value will have the filename
  /// as the key.
  final String? storeName;

  /// Whether or not this import was successfully completed
  ///
  /// Will be false if the collision handler prevents this store's import.
  final bool successful;

  const ImportResult._({
    required this.storeName,
    required this.successful,
  });
}
