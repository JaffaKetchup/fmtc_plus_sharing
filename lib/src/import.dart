// Copyright © Luka S (JaffaKetchup) under GPL-v3
// A full license can be found at .\LICENSE

// ignore_for_file: invalid_use_of_internal_member, invalid_use_of_protected_member

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
  /// Import store(s) with the platform specifc file picker interface
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
  /// will be overwritten, otherwise the import will fail.
  ///
  /// Returns a [Map] of the store names to the result status of the respective
  /// import (`true` for successful, `false` for failed), if any valid files are
  /// selected.
  Future<Map<String, Future<bool>>?> withGUI({
    String fileExtension = 'fmtc',
    bool emptyCacheBeforePicking = true,
    Future<bool> Function(String storeName)? collisionHandler,
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
    return files
        .map(
          (p) => manual(
            File(p.path!),
            collisionHandler: collisionHandler,
          ),
        )
        .reduce((a, b) => a..addAll(b));
  }

  /// Import a store from a specified [inputFile]
  ///
  /// Setting [collisionHandler] allows for custom behaviour in the event that
  /// a store with the same name already exists. If it returns `true`, the store
  /// will be overwritten, otherwise the import will fail.
  ///
  /// Also see [withGUI] for a prebuilt solution to allow the user to select
  /// files to import.
  ///
  /// Returns a [Map] of the store name to the result status of the import
  /// (`true` for successful, `false` for failed).
  Map<String, Future<bool>> manual(
    File inputFile, {
    Future<bool> Function(String storeName)? collisionHandler,
  }) {
    final storeName = p.basenameWithoutExtension(inputFile.path).substring(
          p.basenameWithoutExtension(inputFile.path).startsWith('export_')
              ? 7
              : 0,
        );

    return {
      storeName: () async {
        if (!await inputFile.exists()) return false;

        if (FMTC.instance(storeName).manage.ready) {
          if (collisionHandler == null || !await collisionHandler(storeName)) {
            return false;
          }
          await FMTC.instance(storeName).manage.delete();
        }

        final id = DatabaseTools.hash(storeName);
        final newStorePath = FMTC.instance.rootDirectory.directory > '$id.isar';

        try {
          await inputFile.copy(newStorePath);
          FMTCRegistry.instance.storeDatabases[id] = await Isar.open(
            [DbStoreDescriptorSchema, DbTileSchema, DbMetadataSchema],
            name: id.toString(),
            directory: FMTC.instance.rootDirectory.directory.path,
            maxSizeMiB: FMTC.instance.settings.databaseMaxSize,
            compactOnLaunch: FMTC.instance.settings.databaseCompactCondition,
          );
        } catch (_) {
          await File(newStorePath).delete();
          FMTCRegistry.instance.storeDatabases.remove(id);
          return false;
        }

        return true;
      }(),
    };
  }
}
