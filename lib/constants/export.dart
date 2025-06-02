// export.dart

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:google_fonts/google_fonts.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:pdf/pdf.dart';
import 'package:path_provider/path_provider.dart';
import 'package:open_filex/open_filex.dart';
import 'package:csv/csv.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // REQUIRED for ByteData
// Removed unused 'colors.dart' import if not needed
import 'package:peakloadindicator/constants/theme.dart'; // Ensure this path is correct
import 'package:syncfusion_flutter_xlsio/xlsio.dart' as xlsio;
import 'package:image/image.dart' as img;

import '../Pages/logScreen/log.dart';
import 'database_manager.dart';

class ExportUtils {
  static String get _currentTime => DateTime.now().toIso8601String().substring(0, 19);

  // Utility to resize images dynamically based on document constraints
  static Future<Uint8List> _resizeImage(Uint8List imageBytes, {int? maxWidth, int? maxHeight, bool isLogo = false}) async {
    try {
      final image = img.decodeImage(imageBytes);
      if (image == null) {
        LogPage.addLog('[$_currentTime] Image resizing: Failed to decode image.');
        return imageBytes;
      }
      // Increased for logo
      final targetMaxWidth = isLogo ? 150 : (maxWidth ?? 800);
      final targetMaxHeight = isLogo ? 50 : (maxHeight ?? 400); // Changed from 50 to 50 for consistency with DOC
      final scale = (targetMaxWidth != null && targetMaxHeight != null)
          ? (image.width / targetMaxWidth > image.height / targetMaxHeight
          ? targetMaxWidth / image.width
          : targetMaxHeight / image.height)
          : 1.0;
      final targetWidth = (image.width * scale).round();
      final targetHeight = (image.height * scale).round();
      final resized = img.copyResize(image, width: targetWidth, height: targetHeight, interpolation: img.Interpolation.cubic);
      final resizedBytes = img.encodePng(resized, level: 0);
      LogPage.addLog('[$_currentTime] Image resized to ${resized.width}x${resized.height}, size: ${resizedBytes.length} bytes, isLogo: $isLogo');
      return Uint8List.fromList(resizedBytes);
    } catch (e) {
      LogPage.addLog('[$_currentTime] Image resizing error: $e');
      return imageBytes;
    }
  }

  // Utility to calculate rows per page dynamically based on page height and content
  static int _calculateRowsPerPage(double pageHeight, double rowHeight, int tableHeaderRowCount, bool hasGraph) {
    // Approximate space for top header (company info, report title, custom header) and footer
    const double fixedHeaderFooterHeight = 200; // Increased to accommodate custom header/footer
    const double graphHeight = 350; // Approx. height if graph is included

    // Calculate space available for table data rows, accounting for table's own header rows
    final availableHeightForTableData = pageHeight - fixedHeaderFooterHeight - (hasGraph ? graphHeight : 0) - (rowHeight * tableHeaderRowCount);
    final rows = (availableHeightForTableData / rowHeight).floor();
    LogPage.addLog('[$_currentTime] Calculated rows per page: $rows (pageHeight: $pageHeight, rowHeight: $rowHeight, tableHeaderRowCount: $tableHeaderRowCount, hasGraph: $hasGraph)');
    // Ensure a reasonable range of rows per page to avoid extreme density or too few rows
    return rows.clamp(15, 60);
  }

  // NEW: Dialog to collect custom header and footer text
  static Future<Map<String, String>?> _showCustomHeaderFooterDialog(BuildContext context, bool isDarkMode) async {
    final headerController = TextEditingController();
    final footerController = TextEditingController();
    String? errorMessage;

    return await showDialog<Map<String, String>>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: ThemeColors.getColor('dialogBackground', isDarkMode),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              title: Text(
                'Custom Header & Footer',
                style: GoogleFonts.roboto(
                  color: ThemeColors.getColor('dialogText', isDarkMode),
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                ),
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: headerController,
                    decoration: InputDecoration(
                      labelText: 'Header Text (optional)',
                      hintText: 'e.g., Confidential Report',
                      labelStyle: GoogleFonts.roboto(color: ThemeColors.getColor('dialogSubText', isDarkMode), fontSize: 13),
                      hintStyle: GoogleFonts.roboto(color: ThemeColors.getColor('dialogSubText', isDarkMode).withOpacity(0.5), fontSize: 13),
                      filled: true, fillColor: ThemeColors.getColor('textFieldBackground', isDarkMode),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      isDense: true,
                    ),
                    style: GoogleFonts.roboto(color: ThemeColors.getColor('dialogText', isDarkMode), fontSize: 14),
                    maxLines: 2,
                  ),
                  const SizedBox(height: 15),
                  TextField(
                    controller: footerController,
                    decoration: InputDecoration(
                      labelText: 'Footer Text (optional)',
                      hintText: 'e.g., Property of Countronics Pvt. Ltd.',
                      labelStyle: GoogleFonts.roboto(color: ThemeColors.getColor('dialogSubText', isDarkMode), fontSize: 13),
                      hintStyle: GoogleFonts.roboto(color: ThemeColors.getColor('dialogSubText', isDarkMode).withOpacity(0.5), fontSize: 13),
                      filled: true, fillColor: ThemeColors.getColor('textFieldBackground', isDarkMode),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      isDense: true,
                    ),
                    style: GoogleFonts.roboto(color: ThemeColors.getColor('dialogText', isDarkMode), fontSize: 14),
                    maxLines: 2,
                  ),
                  if (errorMessage != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 10.0),
                      child: Text(errorMessage!, style: GoogleFonts.roboto(color: ThemeColors.getColor('errorText', isDarkMode), fontSize: 11.5)),
                    ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    Navigator.of(dialogContext).pop(null); // Return null if cancelled
                  },
                  child: Text(
                    'Cancel',
                    style: GoogleFonts.roboto(color: ThemeColors.getColor('dialogSubText', isDarkMode), fontWeight: FontWeight.w500, fontSize: 14),
                  ),
                ),
                ElevatedButton(
                  onPressed: () {
                    Navigator.of(dialogContext).pop({
                      'headerText': headerController.text,
                      'footerText': footerController.text,
                    });
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: ThemeColors.getColor('submitButton', isDarkMode),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                  ),
                  child: Text(
                    'Continue',
                    style: GoogleFonts.roboto(color: Colors.white, fontWeight: FontWeight.w500, fontSize: 14),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  static Future<void> exportBasedOnMode({
    required BuildContext context,
    required String mode,
    required List<dynamic> tableData,
    required String fileName,
    Uint8List? graphImage,
    required Map<String, dynamic>? authSettings,
    required Map<int, String> channelNames,
    required bool isDarkMode,
    Map<int, String>? channelUnits, // Added for consistency, though currently derived in PDF/DOC exports
  }) async {
    LogPage.addLog('[$_currentTime] Export initiated. Mode: $mode, File: $fileName, TableData items: ${tableData.length}, Channels: ${channelNames.length}, GraphImage: ${graphImage != null}, Units: ${channelUnits?.length ?? 0}');
    if (tableData.isEmpty) LogPage.addLog('[$_currentTime] Warning: tableData is empty for mode $mode.');
    if (channelNames.isEmpty) LogPage.addLog('[$_currentTime] Warning: channelNames is empty for mode $mode.');

    // Only show large dataset warning if combined/table mode and actual data exists
    if ((mode == 'Combined' || mode == 'Table') && tableData.length > 10000) {
      LogPage.addLog('[$_currentTime] Warning: Large dataset detected (${tableData.length} rows). PDF will be split into multiple files.');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Large dataset detected (${tableData.length} rows). PDF will be split into multiple files.', style: GoogleFonts.roboto()),
          backgroundColor: ThemeColors.getColor('warningSnackbarBackground', isDarkMode), // Using a warning color
        ),
      );
    }

    // NEW: Get custom header/footer text before proceeding
    final customTexts = await _showCustomHeaderFooterDialog(context, isDarkMode);
    if (customTexts == null) {
      LogPage.addLog('[$_currentTime] Export cancelled by user in custom header/footer dialog.');
      return; // User cancelled the header/footer dialog
    }
    final customHeaderText = customTexts['headerText'] ?? '';
    final customFooterText = customTexts['footerText'] ?? '';

    // Now proceed with the original export dialog, passing the custom text
    showExportDialog(
      context: context,
      tableData: tableData,
      fileName: fileName,
      graphImage: graphImage,
      includeTable: mode == 'Combined' || mode == 'Table',
      includeGraph: mode == 'Combined' || mode == 'Graph',
      authSettings: authSettings,
      channelNames: channelNames,
      channelUnits: channelUnits,
      isDarkMode: isDarkMode,
      customHeaderText: customHeaderText, // Pass custom text
      customFooterText: customFooterText, // Pass custom text
    );
  }

  static Future<void> exportToPDF({
    required List<dynamic> tableData,
    required String fileName,
    Uint8List? graphImage,
    bool includeTable = true,
    bool includeGraph = true,
    required Map<String, dynamic>? authSettings,
    required Map<int, String> channelNamesMap,
    Map<int, String>? channelUnitsMap, // Already present but we derive it locally for PDF
    required BuildContext context,
    String customHeaderText = '', // NEW: Custom header text parameter
    String customFooterText = '', // NEW: Custom footer text parameter
  }) async {
    LogPage.addLog('[$_currentTime] Starting PDF export. Table: $includeTable (${tableData.length} items), Graph: $includeGraph (img: ${graphImage != null}), Channels: ${channelNamesMap.length}, Units: ${channelUnitsMap?.length ?? 0}');

    // FIX: Correct font loading by awaiting the ByteData
    final ByteData regularFontData = await DefaultAssetBundle.of(context).load('assets/fonts/Roboto-Regular.ttf');
    final regularFont = pw.Font.ttf(regularFontData);
    final ByteData boldFontData = await DefaultAssetBundle.of(context).load('assets/fonts/Roboto-Bold.ttf');
    final boldFont = pw.Font.ttf(boldFontData);

    // Dynamic font sizes based on channel count
    final fontSize = channelNamesMap.length > 10 ? 7.0 : 8.0;
    final headerFontSize = channelNamesMap.length > 10 ? 8.0 : 9.0;
    final baseStyle = pw.TextStyle(font: regularFont, fontSize: fontSize, color: PdfColors.black);
    final boldStyle = pw.TextStyle(font: boldFont, fontWeight: pw.FontWeight.bold, fontSize: headerFontSize, color: PdfColors.black);

    // 1. Pre-load Logo outside any build methods or loops for efficiency
    pw.Image? logoImageWidget;
    if (authSettings?['logoPath'] != null && (authSettings!['logoPath'] as String).isNotEmpty) {
      final logoPath = authSettings['logoPath'] as String;
      try {
        final logoFile = File(logoPath);
        if (await logoFile.exists()) {
          final logoBytes = await logoFile.readAsBytes();
          final resizedLogoBytes = await _resizeImage(logoBytes, maxHeight: 50, isLogo: true);
          logoImageWidget = pw.Image(pw.MemoryImage(resizedLogoBytes), height: 25, fit: pw.BoxFit.contain);
        }
      } catch (e) {
        LogPage.addLog('[$_currentTime] PDF: Logo pre-loading error: $e');
      }
    }

    // Declare headers and units at a scope accessible by pw.Table.fromTextArray
    List<String> headers = ['No.', 'Date', 'Time'];
    List<String> units = ['#', 'YYYY-MM-DD', 'HH:MM:SS'];

    // Prepare data rows
    List<List<String>> dataRows = [];
    if (includeTable && tableData.isNotEmpty) {
      List<int> sortedChannelKeys = channelNamesMap.keys.toList()..sort();

      final db = await DatabaseManager().database;
      Map<int, String> updatedUnitsMap = {};
      for (int key in sortedChannelKeys) {
        final channelName = channelNamesMap[key] ?? 'Ch $key';
        final result = await db.query(
          'ChannelSetup',
          columns: ['Unit'],
          where: 'ChannelName = ?',
          whereArgs: [channelName],
          limit: 1,
        );
        updatedUnitsMap[key] = result.isNotEmpty && result.first['Unit'] != null ? result.first['Unit'] as String : '%';
      }

      // Populate the outer 'headers' and 'units' lists
      for (int key in sortedChannelKeys) {
        headers.add(channelNamesMap[key] ?? 'Ch $key');
        units.add(updatedUnitsMap[key] ?? '%');
      }
      LogPage.addLog('[$_currentTime] PDF: Headers: $headers');
      LogPage.addLog('[$_currentTime] PDF: Units: $units');

      for (var dataRowMap in tableData) {
        if (dataRowMap is! Map<String, dynamic>) {
          LogPage.addLog('[$_currentTime] PDF: Invalid row data: $dataRowMap');
          continue;
        }
        final data = dataRowMap;

        String displayDate = 'N/A';
        if (data['AbsDate'] != null && (data['AbsDate'] as String).isNotEmpty) {
          try {
            DateTime parsedDate = DateTime.parse(data['AbsDate'] as String);
            displayDate = "${parsedDate.year}-${parsedDate.month.toString().padLeft(2, '0')}-${parsedDate.day.toString().padLeft(2, '0')}";
          } catch (e) {
            String dateStr = data['AbsDate'] as String;
            if (dateStr.length >= 10) {
              displayDate = dateStr.substring(0, 10);
            }
            LogPage.addLog('[$_currentTime] PDF: AbsDate parsing error: $e');
          }
        }

        List<String> row = [
          data['SNo']?.toString() ?? '-',
          displayDate,
          data['AbsTime']?.toString() ?? '-',
        ];
        for (int key in sortedChannelKeys) {
          var val = data['AbsPer$key'];
          row.add(val is num ? val.toStringAsFixed(2) : (val?.toString() ?? '-'));
        }
        dataRows.add(row);
      }
    }

    // Table settings
    const double rowHeight = 10.0;
    // FIX: Limit pages per individual PDF file to avoid "too many pages" exception
    const int maxPagesPerFile = 100; // Max pages per PDF document
    final pageHeight = PdfPageFormat.a4.height - 50; // Total height minus standard margins
    // Pass correct tableHeaderRowCount (2 for headers + units) to calculation
    final rowsPerPage = _calculateRowsPerPage(pageHeight, rowHeight, 2, includeGraph);
    final maxRowsPerChunk = maxPagesPerFile * rowsPerPage; // Max rows in one PDF file

    // Split data into multiple PDFs based on maxRowsPerChunk
    for (int fileIndex = 0; fileIndex < dataRows.length; fileIndex += maxRowsPerChunk) {
      final pdf = pw.Document();
      List<pw.Widget> content = []; // Reset content for each new PDF part

      // **Build content for the current PDF part**
      // Table data chunks
      if (includeTable && dataRows.isNotEmpty) {
        final currentFileChunk = dataRows.sublist(
          fileIndex,
          fileIndex + maxRowsPerChunk > dataRows.length ? dataRows.length : fileIndex + maxRowsPerChunk,
        );

        int pageCountInChunk = 0;
        for (int i = 0; i < currentFileChunk.length; i += rowsPerPage) {
          final pageChunk = currentFileChunk.sublist(i, i + rowsPerPage > currentFileChunk.length ? currentFileChunk.length : i + rowsPerPage);

          content.add(
            pw.Table.fromTextArray(
              data: [
                headers, // First header row (column names)
                units,   // Second header row (units)
                ...pageChunk,
              ],
              cellAlignment: pw.Alignment.center,
              headerStyle: boldStyle.copyWith(color: PdfColors.white),
              cellStyle: baseStyle,
              border: pw.TableBorder.all(color: PdfColors.grey800, width: 0.5),
              headerCellDecoration: const pw.BoxDecoration(color: PdfColors.blue800),
              cellHeight: rowHeight,
              cellPadding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              headerCount: 2, // Tells pdf to repeat the first 2 rows of 'data' as headers
              columnWidths: {
                0: const pw.FixedColumnWidth(35),
                1: const pw.FixedColumnWidth(65),
                2: const pw.FixedColumnWidth(55),
                for (int j = 3; j < headers.length; j++) j: pw.FlexColumnWidth(channelNamesMap.length > 10 ? 0.8 : 0.9),
              },
            ),
          );
          pageCountInChunk++;
          LogPage.addLog('[$_currentTime] PDF: Added page $pageCountInChunk with ${pageChunk.length} rows to part ${fileIndex ~/ maxRowsPerChunk + 1}');
          // Only add a new page if there are more rows in the current chunk
          if (i + rowsPerPage < currentFileChunk.length) {
            content.add(pw.NewPage());
          }
        }
      } else if (includeTable) {
        content.add(pw.Text('No tabular data available.', style: baseStyle.copyWith(color: PdfColors.red)));
      }

      // **GRAPH SECTION**
      // Graph should only be added to the first part of the PDF, if table data is split
      if (includeGraph && graphImage != null && fileIndex == 0) {
        try {
          final resizedGraphBytes = await _resizeImage(graphImage, maxWidth: 800, maxHeight: 400, isLogo: false);

          // If table data was included, add a new page *before* the graph content
          if (includeTable && dataRows.isNotEmpty) {
            content.add(pw.NewPage());
          }

          content.add(
              pw.Partition( // Use Partition to ensure the entire graph block moves together if it doesn't fit
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.center,
                  mainAxisSize: pw.MainAxisSize.min, // Essential for Partition to work correctly
                  children: [
                    pw.SizedBox(height: 20), // Add some space from the top of the new page
                    pw.Text('Graph: $fileName', style: boldStyle.copyWith(fontSize: channelNamesMap.length > 10 ? 10 : 12)),
                    pw.SizedBox(height: 8),
                    pw.Image(pw.MemoryImage(resizedGraphBytes), fit: pw.BoxFit.contain, height: channelNamesMap.length > 10 ? 300 : 350),
                    // REMOVED "Figure 1: Data Visualization" hardcoded text
                  ],
                ),
              )
          );
        } catch (e) {
          LogPage.addLog('[$_currentTime] PDF: Graph error: $e');
          if (includeTable && dataRows.isNotEmpty) {
            content.add(pw.NewPage());
          }
          content.add(
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.center,
                children: [
                  pw.SizedBox(height: 20),
                  pw.Text('Error displaying graph.', style: baseStyle.copyWith(color: PdfColors.red)),
                ],
              )
          );
        }
      } else if (includeGraph && graphImage == null && fileIndex == 0) {
        // If graph was requested but no image available
        if (includeTable && dataRows.isNotEmpty) {
          content.add(pw.NewPage());
        }
        content.add(
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.center,
              children: [
                pw.SizedBox(height: 20),
                pw.Text('No graph image available.', style: baseStyle.copyWith(color: PdfColors.red)),
              ],
            )
        );
      }

      final pageOrientation = (includeTable && tableData.isNotEmpty && (channelNamesMap.length > 8 || (includeGraph && graphImage != null)))
          ? pw.PageOrientation.landscape
          : pw.PageOrientation.portrait;

      try {
        pdf.addPage(
          pw.MultiPage(
            pageFormat: PdfPageFormat.a4,
            orientation: pageOrientation,
            margin: const pw.EdgeInsets.all(25),
            build: (context) => content, // The complete content list is passed here
            header: (context) {
              // Header logic: detailed for first page, simple for subsequent pages
              if (context.pageNumber == 1) { // First page of this MultiPage instance
                return pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.center,
                  children: [
                    if (customHeaderText.isNotEmpty) ...[
                      pw.SizedBox(height: 10),
                      pw.Text(
                        customHeaderText,
                        style: boldStyle.copyWith(fontSize: channelNamesMap.length > 10 ? 12 : 14),
                        textAlign: pw.TextAlign.center,
                      ),
                      pw.SizedBox(height: 10),
                    ],
                    if (logoImageWidget != null) // Use the pre-loaded image widget
                      pw.Container(child: logoImageWidget, alignment: pw.Alignment.center, margin: const pw.EdgeInsets.only(bottom: 8)),
                    pw.Text(
                      authSettings?['companyName'] ?? 'Countronics',
                      style: boldStyle.copyWith(fontSize: channelNamesMap.length > 10 ? 14 : 16),
                      textAlign: pw.TextAlign.center,
                    ),
                    pw.Text(
                      authSettings?['companyAddress'] ?? 'Near Crossing Republic, ABES Eng College, Ghaziabad 210209',
                      style: baseStyle.copyWith(fontSize: channelNamesMap.length > 10 ? 8 : 10),
                      textAlign: pw.TextAlign.center,
                    ),
                    pw.Text(
                      'Test Report: $fileName${fileIndex > 0 ? ' (Part ${fileIndex ~/ maxRowsPerChunk + 1})' : ''}',
                      style: boldStyle.copyWith(fontSize: channelNamesMap.length > 10 ? 12 : 14),
                    ),
                    pw.Text(
                      'Generated on: $_currentTime',
                      style: baseStyle.copyWith(fontSize: channelNamesMap.length > 10 ? 8 : 10),
                    ),
                    pw.SizedBox(height: 30),
                    pw.Divider(thickness: 0.5, color: PdfColors.blue800),
                    pw.SizedBox(height: 8),
                  ],
                );
              } else { // Subsequent pages of this MultiPage instance
                return pw.Container(
                  margin: const pw.EdgeInsets.only(bottom: 8),
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.center,
                    children: [
                      if (customHeaderText.isNotEmpty) ...[
                        pw.SizedBox(height: 10),
                        pw.Text(customHeaderText, style: boldStyle.copyWith(fontSize: channelNamesMap.length > 10 ? 10 : 12)),
                        pw.SizedBox(height: 5),
                      ],
                      pw.Text(
                        authSettings?['companyName'] ?? 'Countronics',
                        style: boldStyle.copyWith(fontSize: channelNamesMap.length > 10 ? 10 : 12),
                      ),
                      pw.Text(
                        'Test Report: $fileName${fileIndex > 0 ? ' (Part ${fileIndex ~/ maxRowsPerChunk + 1})' : ''}',
                        style: baseStyle.copyWith(fontSize: channelNamesMap.length > 10 ? 8 : 10),
                      ),
                      pw.SizedBox(height: 8),
                      pw.Divider(thickness: 0.5, color: PdfColors.grey800),
                    ],
                  ),
                );
              }
            },
            footer: (context) {
              return pw.Container(
                margin: const pw.EdgeInsets.only(top: 8),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.center,
                  children: [
                    pw.Divider(thickness: 0.5, color: PdfColors.grey800),
                    pw.SizedBox(height: 8),
                    pw.Text('Page ${context.pageNumber} of ${context.pagesCount}', style: baseStyle.copyWith(color: PdfColors.grey700)),
                    pw.Text(authSettings?['companyName'] ?? 'Countronics', style: baseStyle),
                    // Removed company address and contact info as requested (already done, just confirming)
                    pw.Text('Generated by Countronics Smart Logger', style: baseStyle.copyWith(fontStyle: pw.FontStyle.italic)),
                    // NEW: Custom Footer Text
                    if (customFooterText.isNotEmpty) ...[
                      pw.SizedBox(height: 5),
                      pw.Text(customFooterText, style: baseStyle.copyWith(fontSize: channelNamesMap.length > 10 ? 8 : 10)),
                    ],
                    pw.SizedBox(height: 30),
                  ],
                ),
              );
            },
          ),
        );

        final directory = await getApplicationDocumentsDirectory();
        final downloadsDir = Platform.isAndroid || Platform.isIOS ? directory : (await getDownloadsDirectory() ?? directory);
        final sanitizedFileName = fileName.replaceAll(RegExp(r'[^\w\s.-]'), '_');
        final filePath = '${downloadsDir.path}/$sanitizedFileName${fileIndex > 0 ? '_part${fileIndex ~/ maxRowsPerChunk + 1}' : ''}.pdf';
        final file = File(filePath);
        LogPage.addLog('[$_currentTime] PDF: Saving to $filePath');
        await file.writeAsBytes(await pdf.save());
        LogPage.addLog('[$_currentTime] PDF: Exported to $filePath');
        if (fileIndex == 0) { // Only open the first generated PDF file
          try {
            await OpenFilex.open(filePath);
          } catch (e) {
            LogPage.addLog('[$_currentTime] PDF: Error opening PDF: $e');
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Failed to open PDF: $e', style: GoogleFonts.roboto()), backgroundColor: Colors.red),
            );
          }
        }
      } catch (e) {
        LogPage.addLog('[$_currentTime] PDF: Error generating/saving PDF: $e');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to generate PDF: $e', style: GoogleFonts.roboto()), backgroundColor: Colors.red),
        );
      }
    }
  }

  static Future<void> exportToDOC({
    required List<dynamic> tableData,
    required String fileName,
    Uint8List? graphImage,
    bool includeTable = true,
    bool includeGraph = true,
    required Map<String, dynamic>? authSettings,
    required Map<int, String> channelNamesMap,
    Map<int, String>? channelUnitsMap, // Already present but we derive it locally for DOC
    BuildContext? context,
    String customHeaderText = '', // NEW: Custom header text parameter
    String customFooterText = '', // NEW: Custom footer text parameter
  }) async {
    LogPage.addLog('[$_currentTime] Starting DOC (HTML) export. Table: $includeTable (${tableData.length} items), Graph: ${graphImage != null}, Channels: ${channelNamesMap.length}, Units: ${channelUnitsMap?.length ?? 0}');
    StringBuffer htmlContent = StringBuffer();

    final fontSize = channelNamesMap.length > 10 ? '8pt' : '9pt';
    final minWidth = channelNamesMap.length > 10 ? '60px' : '70px';

    htmlContent.writeln('<!DOCTYPE html>');
    htmlContent.writeln('<html lang="en">');
    htmlContent.writeln('<head>');
    htmlContent.writeln('<meta charset="UTF-8">');
    htmlContent.writeln('<meta name="viewport" content="width=device-width, initial-scale=1.0">');
    htmlContent.writeln('<title>$fileName</title>');
    htmlContent.writeln('<style>');
    htmlContent.writeln('body { font-family: Arial, sans-serif; margin: 25px; line-height: 1.6; color: #000; }');
    htmlContent.writeln('table { border-collapse: collapse; width: 100%; margin-bottom: 20px; font-size: $fontSize; }');
    htmlContent.writeln('th, td { border: 1px solid #666; padding: 6px; text-align: center; min-width: $minWidth; }');
    htmlContent.writeln('th { background-color: #1565C0; color: white; font-weight: bold; }');
    htmlContent.writeln('td { background-color: #fff; }');
    htmlContent.writeln('.header-container { text-align: center; margin-bottom: 20px; padding-bottom: 8px; border-bottom: 1px solid #1565C0; }');
    htmlContent.writeln('.header-container img.logo { max-height: 50pt; margin-bottom: 12px; }'); // INCREASED LOGO SIZE
    htmlContent.writeln('.header-container h1.company-name { margin: 0 0 6px 0; font-size: ${channelNamesMap.length > 10 ? '14pt' : '16pt'}; }');
    htmlContent.writeln('.header-container p.company-address { margin: 0 0 8px 0; font-size: ${channelNamesMap.length > 10 ? '8pt' : '10pt'}; }');
    htmlContent.writeln('p.report-title { font-size: ${channelNamesMap.length > 10 ? '12pt' : '14pt'}; font-weight: bold; margin: 0 0 6px 0; }');
    htmlContent.writeln('p.generated-date { font-size: ${channelNamesMap.length > 10 ? '8pt' : '10pt'}; margin-bottom: 8px; }');
    htmlContent.writeln('.footer-container { text-align: center; margin-top: 20px; padding-top: 8px; border-top: 1px solid #1565C0; font-size: $fontSize; }');
    htmlContent.writeln('.graph-container { text-align: center; margin-top: 20px; page-break-inside: avoid; }');
    htmlContent.writeln('.graph-container h2 { font-size: ${channelNamesMap.length > 10 ? '10pt' : '12pt'}; margin-bottom: 8px; }');
    htmlContent.writeln('.graph-container img { max-width: 800px; max-height: 400px; border: 1px solid #ccc; }');
    htmlContent.writeln('.graph-container p.caption { font-size: $fontSize; font-style: italic; margin-top: 5px; }');
    htmlContent.writeln('.page-break { page-break-before: always; }');
    htmlContent.writeln('@media print { body { font-size: ${channelNamesMap.length > 10 ? '7pt' : '8pt'}; } .header-container h1.company-name { font-size: ${channelNamesMap.length > 10 ? '12pt' : '14pt'}; } p.report-title { font-size: ${channelNamesMap.length > 10 ? '10pt' : '12pt'}; } }');
    htmlContent.writeln('</style>');
    htmlContent.writeln('</head>');
    htmlContent.writeln('<body>');

    htmlContent.writeln('<div class="header-container">');
    // NEW: Custom Header Text
    if (customHeaderText.isNotEmpty) {
      htmlContent.writeln('<div style="font-size: ${channelNamesMap.length > 10 ? '12pt' : '14pt'}; font-weight: bold; margin-bottom: 10px;">$customHeaderText</div>');
    }
    htmlContent.writeln('<div style="height: 10pt;"></div>'); // Add some vertical space if no custom header
    if (authSettings != null && authSettings['logoPath'] != null && (authSettings['logoPath'] as String).isNotEmpty) {
      final logoPath = authSettings['logoPath'] as String;
      try {
        final logoFile = File(logoPath);
        if (await logoFile.exists()) {
          final logoBytes = await logoFile.readAsBytes();
          final resizedLogoBytes = await _resizeImage(logoBytes, maxHeight: 50, isLogo: true);
          final base64Logo = base64Encode(resizedLogoBytes);
          String mimeType = logoPath.toLowerCase().endsWith('.jpg') || logoPath.toLowerCase().endsWith('.jpeg') ? 'image/jpeg' : 'image/png';
          htmlContent.writeln('<img class="logo" src="data:$mimeType;base64,$base64Logo" alt="Company Logo">');
          LogPage.addLog('[$_currentTime] DOC: Embedded resized logo from $logoPath');
        } else {
          LogPage.addLog('[$_currentTime] DOC: Logo file not found at $logoPath');
        }
      } catch (e) {
        LogPage.addLog('[$_currentTime] DOC: Error embedding logo: $e');
      }
    }
    htmlContent.writeln('<h1 class="company-name">${authSettings?['companyName'] ?? 'Countronics'}</h1>');
    htmlContent.writeln('<p class="company-address">${authSettings?['companyAddress'] ?? 'Near Crossing Republic, ABES Eng College, Ghaziabad 210209'}</p>');
    htmlContent.writeln('<p class="report-title">Test Report: $fileName</p>');
    htmlContent.writeln('<p class="generated-date">Generated on: $_currentTime</p>');
    htmlContent.writeln('<div style="height: 30pt;"></div>');
    htmlContent.writeln('</div>');

    if (includeTable && tableData.isNotEmpty) {
      htmlContent.writeln('<table>');
      htmlContent.writeln('<thead>');
      htmlContent.writeln('<tr>');
      List<String> headers = ['No.', 'Date', 'Time'];
      List<int> sortedChannelKeys = channelNamesMap.keys.toList()..sort();

      final db = await DatabaseManager().database;
      Map<int, String> updatedUnitsMap = {};
      for (int key in sortedChannelKeys) {
        final channelName = channelNamesMap[key] ?? 'Ch $key';
        final result = await db.query(
          'ChannelSetup',
          columns: ['Unit'],
          where: 'ChannelName = ?',
          whereArgs: [channelName],
          limit: 1,
        );
        updatedUnitsMap[key] = result.isNotEmpty && result.first['Unit'] != null ? result.first['Unit'] as String : '%';
      }

      for (int key in sortedChannelKeys) {
        headers.add(channelNamesMap[key] ?? 'Ch $key');
      }
      for (String header in headers) {
        htmlContent.writeln('<th>${header.padRight(channelNamesMap.length > 10 ? 15 : 20)}</th>');
      }
      htmlContent.writeln('</tr>');

      htmlContent.writeln('<tr>');
      List<String> units = ['#', 'YYYY-MM-DD', 'HH:MM:SS'];
      for (int key in sortedChannelKeys) {
        units.add(updatedUnitsMap[key] ?? '%');
      }
      for (String unit in units) {
        htmlContent.writeln('<th><em>${unit.padRight(channelNamesMap.length > 10 ? 15 : 20)}</em></th>');
      }
      htmlContent.writeln('</tr>');
      htmlContent.writeln('</thead>');
      htmlContent.writeln('<tbody>');

      for (var dataRowMap in tableData.take(10000)) {
        if (dataRowMap is! Map<String, dynamic>) {
          LogPage.addLog('[$_currentTime] DOC: Invalid row data: $dataRowMap');
          continue;
        }
        final data = dataRowMap;

        String displayDate = 'N/A';
        if (data['AbsDate'] != null && (data['AbsDate'] as String).isNotEmpty) {
          try {
            DateTime parsedDate = DateTime.parse(data['AbsDate'] as String);
            displayDate = "${parsedDate.year}-${parsedDate.month.toString().padLeft(2, '0')}-${parsedDate.day.toString().padLeft(2, '0')}";
          } catch (e) {
            String dateStr = data['AbsDate'] as String;
            if (dateStr.length >= 10) {
              displayDate = dateStr.substring(0, 10);
            }
            LogPage.addLog('[$_currentTime] DOC: AbsDate parsing error: $e');
          }
        }

        htmlContent.writeln('<tr>');
        htmlContent.writeln('<td>${(data['SNo']?.toString() ?? '-').padRight(channelNamesMap.length > 10 ? 15 : 20)}</td>');
        htmlContent.writeln('<td>${displayDate.padRight(channelNamesMap.length > 10 ? 15 : 20)}</td>');
        htmlContent.writeln('<td>${(data['AbsTime']?.toString() ?? '-').padRight(channelNamesMap.length > 10 ? 15 : 20)}</td>');
        for (int key in sortedChannelKeys) {
          var val = data['AbsPer$key'];
          htmlContent.writeln('<td>${(val is num ? val.toStringAsFixed(2) : (val?.toString() ?? '-')).padRight(channelNamesMap.length > 10 ? 15 : 20)}</td>');
        }
        htmlContent.writeln('</tr>');
      }
      htmlContent.writeln('</tbody>');
      htmlContent.writeln('</table>');
      if (tableData.length > 10000) {
        htmlContent.writeln('<p style="color:red;">Warning: Data truncated to 10,000 rows.</p>');
      }
    } else if (includeTable) {
      htmlContent.writeln('<p>No tabular data available.</p>');
    }

    if (includeGraph && graphImage != null) {
      // Only add page break if table data was included and had data.
      if (includeTable && tableData.isNotEmpty) {
        htmlContent.writeln('<div class="page-break"></div>');
      }
      htmlContent.writeln('<div class="graph-container">');
      htmlContent.writeln('<h2>Graph: $fileName</h2>');
      try {
        final resizedGraphBytes = await _resizeImage(graphImage, maxWidth: 800, maxHeight: 400, isLogo: false);
        String base64Image = base64Encode(resizedGraphBytes);
        htmlContent.writeln('<img src="data:image/png;base64,$base64Image" alt="Data Graph">');
        // REMOVED "Figure 1: Data Visualization" hardcoded text
      } catch (e) {
        LogPage.addLog('[$_currentTime] DOC: Error encoding graph image: $e');
        htmlContent.writeln('<p style="color:red;">Error displaying graph.</p>');
      }
      htmlContent.writeln('</div>');
    } else if (includeGraph && graphImage == null) {
      // If graph was requested but no image available
      if (includeTable && tableData.isNotEmpty) {
        htmlContent.writeln('<div class="page-break"></div>');
      }
      htmlContent.writeln('<div class="graph-container">'); // Use graph-container for consistent layout
      htmlContent.writeln('<p style="color:red; margin-top: 20px;">No graph image available.</p>');
      htmlContent.writeln('</div>');
    }

    htmlContent.writeln('<div style="height: 30pt;"></div>');
    htmlContent.writeln('<div class="footer-container">');
    htmlContent.writeln('<p>${authSettings?['companyName'] ?? 'Countronics'}</p>');
    // Removed company address and contact info as requested (already done, just confirming)
    htmlContent.writeln('<p><em>Generated by PeakLoadIndicator</em></p>');
    // NEW: Custom Footer Text
    if (customFooterText.isNotEmpty) {
      htmlContent.writeln('<div style="font-size: ${channelNamesMap.length > 10 ? '8pt' : '10pt'}; margin-top: 5px;">$customFooterText</div>');
    }
    htmlContent.writeln('<div style="height: 30pt;"></div>');
    htmlContent.writeln('</div>');

    htmlContent.writeln('</body>');
    htmlContent.writeln('</html>');

    try {
      final directory = await getApplicationDocumentsDirectory();
      final downloadsDir = Platform.isAndroid || Platform.isIOS ? directory : (await getDownloadsDirectory() ?? directory);
      final sanitizedFileName = fileName.replaceAll(RegExp(r'[^\w\s.-]'), '_');
      final filePath = '${downloadsDir.path}/$sanitizedFileName.doc';
      final file = File(filePath);
      LogPage.addLog('[$_currentTime] DOC: Saving to $filePath');
      await file.writeAsString(htmlContent.toString());
      LogPage.addLog('[$_currentTime] DOC: Exported to $filePath');
      try {
        await OpenFilex.open(filePath);
      } catch (e) {
        LogPage.addLog('[$_currentTime] DOC: Error opening DOC: $e');
        if (context != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to open DOC: $e', style: GoogleFonts.roboto()), backgroundColor: Colors.red),
          );
        }
      }
    } catch (e) {
      LogPage.addLog('[$_currentTime] DOC: Error saving DOC: $e');
      if (context != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save DOC: $e', style: GoogleFonts.roboto()), backgroundColor: Colors.red),
        );
      }
    }
  }

  static Future<void> exportToExcel({
    required List<dynamic> tableData,
    required String fileName,
    bool includeTable = true,
    required Map<int, String> channelNamesMap,
    Map<int, String>? channelUnitsMap, // Already present but we derive it locally for Excel
    BuildContext? context,
    String customHeaderText = '', // NEW: Custom header text parameter
    String customFooterText = '', // NEW: Custom footer text parameter
  }) async {
    LogPage.addLog('[$_currentTime] Starting Excel export with Syncfusion. TableData: ${tableData.length}, Channels: ${channelNamesMap.length}, Units: ${channelUnitsMap?.length ?? 0}');

    if (!includeTable || tableData.isEmpty) {
      LogPage.addLog('[$_currentTime] Excel: No table data.');
      if (context != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No table data to export.', style: GoogleFonts.roboto()), backgroundColor: Colors.red),
        );
      }
      return;
    }

    final xlsio.Workbook workbook = xlsio.Workbook();
    final xlsio.Worksheet sheet = workbook.worksheets[0];
    sheet.name = 'ReportData';

    // Debug tableData
    LogPage.addLog('[$_currentTime] Excel: TableData sample: ${tableData.isNotEmpty ? tableData.first : 'Empty'}');
    LogPage.addLog('[$_currentTime] Excel: ChannelNamesMap: $channelNamesMap');

    // Declare headers and units early so they are available
    List<String> headers = ['No.', 'Date', 'Time'];
    List<String> units = ['#', 'YYYY-MM-DD', 'HH:MM:SS'];

    // NEW: Add custom header text
    int currentRow = 1;
    if (customHeaderText.isNotEmpty) {
      sheet.getRangeByIndex(currentRow, 1).setText(customHeaderText);
      sheet.getRangeByIndex(currentRow, 1).cellStyle
        ..bold = true
        ..fontSize = 12
        ..fontColor = '#1565C0'; // Match header color
      // Now headers.length is safely accessible because `headers` is declared
      sheet.getRangeByIndex(currentRow, 1, currentRow, headers.length + (channelNamesMap.length)).merge(); // Merge across all columns
      currentRow++;
      sheet.getRangeByIndex(currentRow, 1).rowHeight = 10; // Empty row for spacing
      currentRow++;
    }

    List<int> sortedChannelKeys = channelNamesMap.keys.toList()..sort();

    // Fetch units
    final db = await DatabaseManager().database;
    Map<int, String> updatedUnitsMap = {};
    for (int key in sortedChannelKeys) {
      final channelName = channelNamesMap[key] ?? 'Ch $key';
      final result = await db.query(
        'ChannelSetup',
        columns: ['Unit'],
        where: 'ChannelName = ?',
        whereArgs: [channelName],
        limit: 1,
      );
      updatedUnitsMap[key] = result.isNotEmpty && result.first['Unit'] != null ? result.first['Unit'] as String : '%';
    }

    for (int key in sortedChannelKeys) {
      headers.add(channelNamesMap[key] ?? 'Ch $key');
      units.add(updatedUnitsMap[key] ?? '%');
    }

    // Write headers
    for (int i = 0; i < headers.length; i++) {
      sheet.getRangeByIndex(currentRow, i + 1).setText(headers[i]);
      sheet.getRangeByIndex(currentRow, i + 1).cellStyle
        ..bold = true
        ..backColor = '#1565C0'
        ..fontColor = '#FFFFFF';
      sheet.getRangeByIndex(currentRow + 1, i + 1).setText(units[i]);
      sheet.getRangeByIndex(currentRow + 1, i + 1).cellStyle.italic = true;
    }
    currentRow += 2; // Move past headers and units
    LogPage.addLog('[$_currentTime] Excel: Headers: $headers');
    LogPage.addLog('[$_currentTime] Excel: Units: $units');

    // Dynamic column widths based on channel count
    final baseWidth = channelNamesMap.length > 10 ? 8.0 : 12.0;
    List<double> columnWidths = [10, 15, 15, ...List.filled(headers.length - 3, baseWidth)];
    for (int i = 0; i < headers.length; i++) {
      if (columnWidths[i].isNaN || columnWidths[i].isInfinite) {
        LogPage.addLog('[$_currentTime] Excel: Invalid column width at index $i: ${columnWidths[i]}');
        columnWidths[i] = baseWidth;
      }
      final widthInPixels = (columnWidths[i] * 7).round();
      LogPage.addLog('[$_currentTime] Excel: Setting column ${i + 1} width to $widthInPixels pixels');
      sheet.setColumnWidthInPixels(i + 1, widthInPixels);
    }

    for (var dataRowMap in tableData.take(10000)) {
      if (dataRowMap is! Map<String, dynamic>) {
        LogPage.addLog('[$_currentTime] Excel: Invalid row data: $dataRowMap');
        continue;
      }
      final data = dataRowMap;
      LogPage.addLog('[$_currentTime] Excel: Processing row: $data');

      // Validate required fields
      if (!data.containsKey('SNo') || !data.containsKey('AbsTime') || !data.containsKey('AbsDate')) {
        LogPage.addLog('[$_currentTime] Excel: Missing required fields in row: $data');
        continue;
      }

      String displayDate = 'N/A';
      if (data['AbsDate'] != null && (data['AbsDate'] as String).isNotEmpty) {
        try {
          DateTime parsedDate = DateTime.parse(data['AbsDate'] as String);
          displayDate = "${parsedDate.year}-${parsedDate.month.toString().padLeft(2, '0')}-${parsedDate.day.toString().padLeft(2, '0')}";
        } catch (e) {
          String dateStr = data['AbsDate'] as String;
          if (dateStr.length >= 10) {
            displayDate = dateStr.substring(0, 10);
          }
          LogPage.addLog('[$_currentTime] Excel: Date parsing error for ${data['AbsDate']}: $e');
        }
      }

      sheet.getRangeByIndex(currentRow, 1).setText(data['SNo']?.toString() ?? '-');
      sheet.getRangeByIndex(currentRow, 2).setText(displayDate);
      sheet.getRangeByIndex(currentRow, 3).setText(data['AbsTime']?.toString() ?? '-');

      for (int i = 0; i < sortedChannelKeys.length; i++) {
        var val = data['AbsPer${sortedChannelKeys[i]}'];
        if (val is num) {
          sheet.getRangeByIndex(currentRow, i + 4).setNumber(val.toDouble());
        } else if (val is String && double.tryParse(val) != null) {
          sheet.getRangeByIndex(currentRow, i + 4).setNumber(double.parse(val));
        } else {
          sheet.getRangeByIndex(currentRow, i + 4).setText(val?.toString() ?? '-');
          LogPage.addLog('[$_currentTime] Excel: Non-numeric value for AbsPer${sortedChannelKeys[i]}: $val');
        }
      }
      currentRow++;
    }
    LogPage.addLog('[$_currentTime] Excel: Added ${currentRow - (customHeaderText.isNotEmpty ? 3 : 1)} rows.'); // Adjust for initial rows

    // Add truncation note if necessary
    if (tableData.length > 10000) {
      sheet.getRangeByIndex(currentRow, 1).setText('Warning: Data truncated to 10,000 rows.');
      sheet.getRangeByIndex(currentRow, 1).cellStyle.fontColor = '#FF0000';
      currentRow++;
    }

    // NEW: Add custom footer text
    if (customFooterText.isNotEmpty) {
      sheet.getRangeByIndex(currentRow, 1).rowHeight = 10; // Empty row for spacing
      currentRow++;
      sheet.getRangeByIndex(currentRow, 1).setText(customFooterText);
      sheet.getRangeByIndex(currentRow, 1).cellStyle.fontSize = 10;
      sheet.getRangeByIndex(currentRow, 1).cellStyle.fontColor = '#666666'; // Match a subtle color
      sheet.getRangeByIndex(currentRow, 1, currentRow, headers.length).merge(); // Merge across all columns
    }

    try {
      final directory = await getApplicationDocumentsDirectory();
      final downloadsDir = Platform.isAndroid || Platform.isIOS ? directory : (await getDownloadsDirectory() ?? directory);
      final sanitizedFileName = fileName.replaceAll(RegExp(r'[^\w\s.-]'), '_');
      final filePath = '${downloadsDir.path}/$sanitizedFileName.xlsx';
      final file = File(filePath);
      LogPage.addLog('[$_currentTime] Excel: Saving to $filePath');
      await file.writeAsBytes(workbook.saveAsStream());
      LogPage.addLog('[$_currentTime] Excel: Exported to $filePath');
      try {
        await OpenFilex.open(filePath);
      } catch (e) {
        LogPage.addLog('[$_currentTime] Excel: Error opening Excel: $e');
        if (context != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to open Excel: $e', style: GoogleFonts.roboto()), backgroundColor: Colors.red),
          );
        }
      }
    } catch (e) {
      LogPage.addLog('[$_currentTime] Excel: Error saving Excel: $e');
      if (context != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save Excel: $e', style: GoogleFonts.roboto()), backgroundColor: Colors.red),
        );
      }
    } finally {
      workbook.dispose();
    }
  }

  static Future<void> exportToCSV({
    required List<dynamic> tableData,
    required String fileName,
    bool includeTable = true,
    required Map<int, String> channelNamesMap,
    Map<int, String>? channelUnitsMap, // Already present but we derive it locally for CSV
    BuildContext? context,
    String customHeaderText = '', // NEW: Custom header text parameter
    String customFooterText = '', // NEW: Custom footer text parameter
  }) async {
    LogPage.addLog('[$_currentTime] Starting CSV export. TableData: ${tableData.length}, Channels: ${channelNamesMap.length}, Units: ${channelUnitsMap?.length ?? 0}');
    if (!includeTable || tableData.isEmpty) {
      LogPage.addLog('[$_currentTime] CSV: No table data.');
      if (context != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No table data to export.', style: GoogleFonts.roboto()), backgroundColor: Colors.red),
        );
      }
      return;
    }

    List<List<String>> csvRows = [];

    // NEW: Add custom header text
    if (customHeaderText.isNotEmpty) {
      csvRows.add([customHeaderText]);
      csvRows.add([]); // Empty row for spacing
    }

    List<String> headers = ['No.', 'Date', 'Time'];
    List<String> units = ['#', 'YYYY-MM-DD', 'HH:MM:SS'];
    List<int> sortedChannelKeys = channelNamesMap.keys.toList()..sort();

    // Fetch units
    final db = await DatabaseManager().database;
    Map<int, String> updatedUnitsMap = {};
    for (int key in sortedChannelKeys) {
      final channelName = channelNamesMap[key] ?? 'Ch $key';
      final result = await db.query(
        'ChannelSetup',
        columns: ['Unit'],
        where: 'ChannelName = ?',
        whereArgs: [channelName],
        limit: 1,
      );
      updatedUnitsMap[key] = result.isNotEmpty && result.first['Unit'] != null ? result.first['Unit'] as String : '%';
    }

    for (int key in sortedChannelKeys) {
      headers.add(channelNamesMap[key] ?? 'Ch $key');
      units.add(updatedUnitsMap[key] ?? '%');
    }
    csvRows.add(headers.map((h) => h.padRight(channelNamesMap.length > 10 ? 15 : 20)).toList());
    csvRows.add(units.map((u) => u.padRight(channelNamesMap.length > 10 ? 15 : 20)).toList());
    LogPage.addLog('[$_currentTime] CSV: Headers: $headers');
    LogPage.addLog('[$_currentTime] CSV: Units: $units');

    for (var dataRowMap in tableData.take(10000)) {
      if (dataRowMap is! Map<String, dynamic>) {
        LogPage.addLog('[$_currentTime] CSV: Invalid row data: $dataRowMap');
        continue;
      }
      final data = dataRowMap;
      LogPage.addLog('[$_currentTime] CSV: Processing row: $data');

      String displayDate = 'N/A';
      if (data['AbsDate'] != null && (data['AbsDate'] as String).isNotEmpty) {
        try {
          DateTime parsedDate = DateTime.parse(data['AbsDate'] as String);
          displayDate = "${parsedDate.year}-${parsedDate.month.toString().padLeft(2, '0')}-${parsedDate.day.toString().padLeft(2, '0')}";
        } catch (e) {
          String dateStr = data['AbsDate'] as String;
          if (dateStr.length >= 10) {
            displayDate = dateStr.substring(0, 10);
          }
          LogPage.addLog('[$_currentTime] CSV: AbsDate parsing error: $e');
        }
      }

      List<String> row = [
        (data['SNo']?.toString() ?? '-').padRight(channelNamesMap.length > 10 ? 15 : 20),
        displayDate.padRight(channelNamesMap.length > 10 ? 15 : 20),
        (data['AbsTime']?.toString() ?? '-').padRight(channelNamesMap.length > 10 ? 15 : 20),
      ];
      for (int key in sortedChannelKeys) {
        var val = data['AbsPer$key'];
        row.add((val is num ? val.toStringAsFixed(2) : (val?.toString() ?? '-')).padRight(channelNamesMap.length > 10 ? 15 : 20));
        if (!(val is num) && !(val is String && double.tryParse(val) != null)) {
          LogPage.addLog('[$_currentTime] CSV: Non-numeric value for AbsPer$key: $val');
        }
      }
      csvRows.add(row);
    }
    LogPage.addLog('[$_currentTime] CSV: Added ${csvRows.length - (customHeaderText.isNotEmpty ? 2 : 0)} rows.'); // Adjust for initial rows

    // Add truncation note
    if (tableData.length > 10000) {
      csvRows.add(['Warning: Data truncated to 10,000 rows.']);
    }

    // NEW: Add custom footer text
    if (customFooterText.isNotEmpty) {
      csvRows.add([]); // Empty row for spacing
      csvRows.add([customFooterText]);
    }

    String csvString = const ListToCsvConverter().convert(csvRows);

    try {
      final directory = await getApplicationDocumentsDirectory();
      final downloadsDir = Platform.isAndroid || Platform.isIOS ? directory : (await getDownloadsDirectory() ?? directory);
      final sanitizedFileName = fileName.replaceAll(RegExp(r'[^\w\s.-]'), '_');
      final file = File('${downloadsDir.path}/$sanitizedFileName.csv');
      LogPage.addLog('[$_currentTime] CSV: Saving to ${file.path}');
      await file.writeAsString(csvString);
      LogPage.addLog('[$_currentTime] CSV: Exported to ${file.path}');
      try {
        await OpenFilex.open(file.path);
      } catch (e) {
        LogPage.addLog('[$_currentTime] CSV: Error opening CSV: $e');
        if (context != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to open CSV: $e', style: GoogleFonts.roboto()), backgroundColor: Colors.red),
          );
        }
      }
    } catch (e) {
      LogPage.addLog('[$_currentTime] CSV: Error saving CSV: $e');
      if (context != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save CSV: $e', style: GoogleFonts.roboto()), backgroundColor: Colors.red),
        );
      }
    }
  }

  static void showExportDialog({
    required BuildContext context,
    required List<dynamic> tableData,
    required String fileName,
    Uint8List? graphImage,
    bool includeTable = true,
    bool includeGraph = true,
    required Map<String, dynamic>? authSettings,
    required Map<int, String> channelNames,
    Map<int, String>? channelUnits,
    required bool isDarkMode,
    String customHeaderText = '', // NEW: Custom header text parameter
    String customFooterText = '', // NEW: Custom footer text parameter
  }) {
    LogPage.addLog('[$_currentTime] Showing export format dialog. Table: $includeTable, Graph: $includeGraph, Items: ${tableData.length}');

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: ThemeColors.getColor('dialogBackground', isDarkMode),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: Text(
          'Export Options',
          style: GoogleFonts.roboto(
            color: ThemeColors.getColor('dialogText', isDarkMode),
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (includeTable || includeGraph) ...[
                _buildExportOption(
                  context: dialogContext,
                  title: 'Export as PDF',
                  icon: Icons.picture_as_pdf_rounded,
                  iconColor: Colors.red.shade700,
                  isDarkMode: isDarkMode,
                  onTap: () async {
                    Navigator.pop(dialogContext);
                    LogPage.addLog('[$_currentTime] PDF export selected.');
                    await exportToPDF(
                      tableData: tableData,
                      fileName: fileName,
                      graphImage: graphImage,
                      includeTable: includeTable,
                      includeGraph: includeGraph,
                      authSettings: authSettings,
                      channelNamesMap: channelNames,
                      channelUnitsMap: channelUnits,
                      context: dialogContext, // Pass dialogContext here
                      customHeaderText: customHeaderText, // Pass custom text
                      customFooterText: customFooterText, // Pass custom text
                    );
                  },
                ),
                const SizedBox(height: 10),
                _buildExportOption(
                  context: dialogContext,
                  title: 'Export as DOC',
                  icon: Icons.description_rounded,
                  iconColor: Colors.blue.shade700,
                  isDarkMode: isDarkMode,
                  onTap: () async {
                    Navigator.pop(dialogContext);
                    LogPage.addLog('[$_currentTime] DOC export selected.');
                    await exportToDOC(
                      tableData: tableData,
                      fileName: fileName,
                      graphImage: graphImage,
                      includeTable: includeTable,
                      includeGraph: includeGraph,
                      authSettings: authSettings,
                      channelNamesMap: channelNames,
                      channelUnitsMap: channelUnits,
                      context: dialogContext, // Pass dialogContext here
                      customHeaderText: customHeaderText, // Pass custom text
                      customFooterText: customFooterText, // Pass custom text
                    );
                  },
                ),
                const SizedBox(height: 10),
              ],
              if (includeTable) ...[
                _buildExportOption(
                  context: dialogContext,
                  title: 'Export as Excel (XLSX)',
                  icon: Icons.table_chart_rounded,
                  iconColor: Colors.green.shade700,
                  isDarkMode: isDarkMode,
                  onTap: () async {
                    Navigator.pop(dialogContext);
                    LogPage.addLog('[$_currentTime] Excel export selected.');
                    await exportToExcel(
                      tableData: tableData,
                      fileName: fileName,
                      includeTable: includeTable,
                      channelNamesMap: channelNames,
                      channelUnitsMap: channelUnits,
                      context: dialogContext, // Pass dialogContext here
                      customHeaderText: customHeaderText, // Pass custom text
                      customFooterText: customFooterText, // Pass custom text
                    );
                  },
                ),
                const SizedBox(height: 10),
                _buildExportOption(
                  context: dialogContext,
                  title: 'Export as CSV',
                  icon: Icons.description_rounded,
                  iconColor: Colors.blue.shade700,
                  isDarkMode: isDarkMode,
                  onTap: () async {
                    Navigator.pop(dialogContext);
                    LogPage.addLog('[$_currentTime] CSV export selected.');
                    await exportToCSV(
                      tableData: tableData,
                      fileName: fileName,
                      includeTable: includeTable,
                      channelNamesMap: channelNames,
                      channelUnitsMap: channelUnits,
                      context: dialogContext, // Pass dialogContext here
                      customHeaderText: customHeaderText, // Pass custom text
                      customFooterText: customFooterText, // Pass custom text
                    );
                  },
                ),
              ],
              if (!includeTable && !includeGraph)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 20.0),
                  child: Text(
                    'No data or graph available.',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.roboto(
                      color: ThemeColors.getColor('dialogSubText', isDarkMode),
                    ),
                  ),
                ),
            ],
          ),
        ),
        actionsPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(dialogContext);
              LogPage.addLog('[$_currentTime] Export dialog cancelled.');
            },
            child: Text(
              'Cancel',
              style: GoogleFonts.roboto(
                color: ThemeColors.getColor('dialogSubText', isDarkMode),
                fontWeight: FontWeight.w500,
                fontSize: 14,
              ),
            ),
          ),
        ],
      ),
    );
  }

  static Widget _buildExportOption({
    required BuildContext context,
    required String title,
    required IconData icon,
    required Color iconColor,
    required bool isDarkMode,
    required VoidCallback onTap,
  }) {
    return ElevatedButton(
      onPressed: onTap,
      style: ElevatedButton.styleFrom(
        foregroundColor: iconColor.withOpacity(0.2),
        backgroundColor: ThemeColors.getColor('cardBackground', isDarkMode),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(color: ThemeColors.getColor('cardBorder', isDarkMode), width: 0.8),
        ),
        elevation: (ThemeColors.getColor('cardElevation', isDarkMode) is num
            ? (ThemeColors.getColor('cardElevation', isDarkMode) as num).toDouble() * 0.5
            : 2.0),
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
      ),
      child: Row(
        children: [
          Icon(icon, color: iconColor, size: 22),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              title,
              style: GoogleFonts.roboto(
                color: ThemeColors.getColor('dialogText', isDarkMode),
                fontSize: 15,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Icon(Icons.chevron_right, color: ThemeColors.getColor('dialogSubText', isDarkMode), size: 20),
        ],
      ),
    );
  }
}