// Copyright © Luka S (JaffaKetchup) under GPL-v3
// A full license can be found at .\LICENSE

// ignore_for_file: invalid_use_of_internal_member, invalid_use_of_protected_member

import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_map_tile_caching/flutter_map_tile_caching.dart';
import 'package:flutter_map_tile_caching/fmtc_module_api.dart';
import 'package:share_plus/share_plus.dart';

/// Extends [StoreExport] (accessed through [StoreDirectory.export]) with the
/// export functionality
extension FMTCExportSharingModule on StoreExport {
  /// Export the store with the platform specifc file picker interface or share
  /// sheet/dialog
  ///
  /// Set [forceFilePicker] to:
  ///
  /// * `null` (default): uses the platform specific file picker on desktop
  /// platforms, and the share dialog/sheet on mobile platforms.
  /// * `true`: always force an attempt at using the file picker. This will cause
  /// an error on unsupported platforms, and so is not recommended.
  /// * `false`: always force an attempt at using the share sheet. This will
  /// cause an error on unsupported platforms, and so is not recommended.
  ///
  /// [context] ([BuildContext]) must be specified if using the share sheet, so
  /// it is necessary to pass it unless [forceFilePicker] is `true`. Will cause
  /// an unhandled null error if not passed when necessary.
  ///
  /// If the file already exists, it will be deleted without warning. The default
  /// filename includes an 'export_' prefix, which will be removed automatically
  /// if present during importing.
  ///
  /// Returns `true` when successful, otherwise `false` when unsuccessful or
  /// unknown.
  Future<bool> withGUI({
    String fileExtension = 'fmtc',
    bool? forceFilePicker,
    BuildContext? context,
  }) async {
    if (forceFilePicker ??
        Platform.isLinux || Platform.isMacOS || Platform.isWindows) {
      final String? outputPath = await FilePicker.platform.saveFile(
        dialogTitle: 'Export Cache Store',
        fileName: 'export_${storeDirectory.storeName}.$fileExtension',
        type: FileType.custom,
        allowedExtensions: [fileExtension],
      );

      if (outputPath == null) return false;

      await manual(File(outputPath));
      return true;
    } else {
      final File exportFile = FMTC.instance.rootDirectory.directory >>>
          'export_${storeDirectory.storeName}.$fileExtension';
      final box = context!.findRenderObject() as RenderBox?;

      await manual(exportFile);
      final ShareResult result = await Share.shareXFiles(
        [XFile(exportFile.absolute.path)],
        sharePositionOrigin: box!.localToGlobal(Offset.zero) & box.size,
      );
      await exportFile.delete();

      return result.status == ShareResultStatus.success;
    }
  }

  /// Export the store to a specified non-existing [outputFile]
  ///
  /// The [outputFile] should not exist. If it does, it will be deleted without
  /// warning.
  ///
  /// See [withGUI] for a method that provides logic to show appropriate platform
  /// windows/sheets for export.
  Future<void> manual(File outputFile) async {
    if (await outputFile.exists()) await outputFile.delete();
    return FMTCRegistry
        .instance.storeDatabases[DatabaseTools.hash(storeDirectory.storeName)]!
        .copyToFile(outputFile.absolute.path);
  }
}
