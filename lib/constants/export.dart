import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:syncfusion_flutter_pdf/pdf.dart';
import 'package:syncfusion_flutter_xlsio/xlsio.dart' as xlsio;

import '../Pages/NavPages/channel.dart';
import '../Pages/logScreen/log.dart';
import 'database_manager.dart';
import 'message_utils.dart';

enum ExportFormat { excel, csv, pdf, docx }

/// A utility class for handling all data and graph export functionalities.
class ExportUtils {
  static const double LOGO_HEIGHT = 45.0;
  static const double LOGO_WIDTH = 140.0;
  static const double DOC_LOGO_HEIGHT = 40.0;
  static const double DOC_LOGO_WIDTH = 120.0;
  static const double EXCEL_GRAPH_HEIGHT = 300.0; // Adjusted for better print fit
  static const double EXCEL_GRAPH_WIDTH = 750.0;  // Adjusted for better print fit

  static Future<void> exportBasedOnMode({
    required BuildContext context,
    required String mode,
    required List<Map<String, dynamic>> tableData,
    required String fileName,
    required String operatorName,
    required Uint8List? graphImage,
    required Map<int, String> channelNames,
    required DateTime firstTimestamp,
    required DateTime lastTimestamp,
    required Map<String, Channel> channelSetupData,
    required List<String> headerLines,
    required List<String> footerLines,
  }) async {
    final selectedFormat = await _showExportFormatDialog(context);
    if (selectedFormat == null) return;

    _showLoadingDialog(context, 'Exporting, please wait...');

    try {
      final authData = await DatabaseManager().getAuthSettings() ?? {};
      final String companyName = authData['companyName'] as String? ?? 'Data Report';
      final String companyAddress = authData['companyAddress'] as String? ?? '';
      final String? logoPath = authData['logoPath'] as String?;
      Uint8List? logoBytes;
      if (logoPath != null && logoPath.isNotEmpty && await File(logoPath).exists()) {
        logoBytes = await File(logoPath).readAsBytes();
      }

      await _performExport(
        context: context, format: selectedFormat, mode: mode, tableData: tableData,
        graphImage: graphImage, fileName: fileName, companyName: companyName,
        operatorName: operatorName,
        companyAddress: companyAddress, logoBytes: logoBytes, channelNames: channelNames,
        firstTimestamp: firstTimestamp, lastTimestamp: lastTimestamp, channelSetupData: channelSetupData,
        headerLines: headerLines, footerLines: footerLines,
      );
    } catch (e, s) {
      LogPage.addLog('[EXPORT_ERROR] Failed to export in mode "$mode": $e\n$s');
      if (context.mounted) {
        MessageUtils.showMessage(context, 'Export failed: $e', isError: true);
      }
    } finally {
      if (context.mounted) {
        Navigator.of(context, rootNavigator: true).pop();
      }
    }
  }

  static Future<void> _performExport({
    required BuildContext context, required ExportFormat format, required String mode,
    required List<Map<String, dynamic>> tableData, required String fileName, required Uint8List? graphImage,
    required String companyName, required String companyAddress, required Uint8List? logoBytes,
    required Map<int, String> channelNames, required DateTime firstTimestamp, required DateTime lastTimestamp,
    required Map<String, Channel> channelSetupData, required List<String> headerLines, required List<String> footerLines,
    required String operatorName,
  }) async {
    if ((mode == 'Table' || mode == 'Combined') && tableData.isEmpty) { MessageUtils.showMessage(context, 'No table data to export.', isError: true); return; }
    if ((mode == 'Graph' || mode == 'Combined') && graphImage == null) { MessageUtils.showMessage(context, 'No graph image to export.', isError: true); return; }

    switch (format) {
      case ExportFormat.excel: await _exportToExcel(context: context, mode: mode, tableData: tableData, graphImage: graphImage, fileName: fileName, companyName: companyName, operatorName: operatorName, companyAddress: companyAddress, logoBytes: logoBytes, channelNames: channelNames, firstTimestamp: firstTimestamp, lastTimestamp: lastTimestamp, channelSetupData: channelSetupData, headerLines: headerLines, footerLines: footerLines); break;
      case ExportFormat.pdf: await _exportToPdf(context: context, mode: mode, tableData: tableData, graphImage: graphImage, fileName: fileName, companyName: companyName, operatorName: operatorName, companyAddress: companyAddress, logoBytes: logoBytes, channelNames: channelNames, firstTimestamp: firstTimestamp, lastTimestamp: lastTimestamp, channelSetupData: channelSetupData, headerLines: headerLines, footerLines: footerLines); break;
      case ExportFormat.csv: if (mode == 'Graph') { MessageUtils.showMessage(context, 'CSV export is not available for "Graph only" mode.', isError: true); return; } await _exportTableToCsv(context: context, tableData: tableData, fileName: fileName, channelNames: channelNames, channelSetupData: channelSetupData); break;
      case ExportFormat.docx: await _exportToHtmlForWord(context: context, mode: mode, tableData: tableData, graphImage: graphImage, fileName: fileName, companyName: companyName, operatorName: operatorName, companyAddress: companyAddress, logoBytes: logoBytes, channelNames: channelNames, firstTimestamp: firstTimestamp, lastTimestamp: lastTimestamp, channelSetupData: channelSetupData, headerLines: headerLines, footerLines: footerLines); break;
    }
  }

  static Future<void> _exportToExcel({
    required BuildContext context,
    required String mode,
    required List<Map<String, dynamic>> tableData,
    required Uint8List? graphImage,
    required String fileName,
    required String companyName,
    required String operatorName,
    required String companyAddress,
    required Uint8List? logoBytes,
    required Map<int, String> channelNames,
    required DateTime firstTimestamp,
    required DateTime lastTimestamp,
    required Map<String, Channel> channelSetupData,
    required List<String> headerLines,
    required List<String> footerLines
  }) async {
    final xlsio.Workbook workbook = xlsio.Workbook();
    final xlsio.Worksheet sheet = workbook.worksheets[0];
    sheet.name = 'Report';

    // --- PAGE SETUP ---
    sheet.pageSetup.orientation = xlsio.ExcelPageOrientation.landscape;
    sheet.pageSetup.topMargin = 0.5;
    sheet.pageSetup.bottomMargin = 0.5;
    sheet.pageSetup.leftMargin = 0.5;
    sheet.pageSetup.rightMargin = 0.5;
    sheet.pageSetup.headerMargin = 0.3;
    sheet.pageSetup.footerMargin = 0.3;

    // --- STYLES ---
    final xlsio.Style leftHeaderStyle = workbook.styles.add('LeftHeaderStyle')
      ..fontName = 'Arial'
      ..fontSize = 18
      ..bold = true
      ..hAlign = xlsio.HAlignType.left
      ..vAlign = xlsio.VAlignType.center
      ..wrapText = true;

    final xlsio.Style leftSubHeaderStyle = workbook.styles.add('LeftSubHeaderStyle')
      ..fontName = 'Arial'
      ..fontSize = 12
      ..hAlign = xlsio.HAlignType.left
      ..vAlign = xlsio.VAlignType.center
      ..wrapText = true;

    final xlsio.Style infoStyle = workbook.styles.add('InfoStyle')
      ..fontName = 'Arial'
      ..fontSize = 11
      ..bold = true;

    final xlsio.Style infoValueStyle = workbook.styles.add('InfoValueStyle')
      ..fontName = 'Arial'
      ..fontSize = 11
      ..wrapText = true;

    final xlsio.Style userHeaderStyle = workbook.styles.add('UserHeaderStyle')
      ..fontName = 'Arial'
      ..fontSize = 10
      ..bold = true
      ..wrapText = true;

    final xlsio.Style manualFooterStyle = workbook.styles.add('ManualFooterStyle')
      ..fontName = 'Arial'
      ..fontSize = 9
      ..italic = true
      ..hAlign = xlsio.HAlignType.left
      ..vAlign = xlsio.VAlignType.center
      ..wrapText = true;

    final xlsio.Style tableHeaderStyle = workbook.styles.add('TableHeaderStyle')
      ..fontName = 'Arial'
      ..fontSize = 11
      ..bold = true
      ..backColor = '#D9E1F2'
      ..hAlign = xlsio.HAlignType.center
      ..vAlign = xlsio.VAlignType.center
      ..borders.all.lineStyle = xlsio.LineStyle.thin;

    // --- ENHANCED SECTION TITLE STYLES (LEFT-ALIGNED + DECORATIVE) ---
    final xlsio.Style graphTitleStyle = workbook.styles.add('GraphTitleStyle')
      ..fontName = 'Arial'
      ..fontSize = 16
      ..bold = true
      ..hAlign = xlsio.HAlignType.left
      ..vAlign = xlsio.VAlignType.center
      ..backColor = '#E8F4FD'
      ..borders.all.lineStyle = xlsio.LineStyle.thin
      ..borders.all.color = '#4A90A4';

    final xlsio.Style tableTitleStyle = workbook.styles.add('TableTitleStyle')
      ..fontName = 'Arial'
      ..fontSize = 16
      ..bold = true
      ..hAlign = xlsio.HAlignType.left
      ..vAlign = xlsio.VAlignType.center
      ..backColor = '#FFF2CC'
      ..borders.all.lineStyle = xlsio.LineStyle.thin
      ..borders.all.color = '#D6B656';

    final Map<String, xlsio.Style> numberStyles = _createNumberStyles(workbook);
    int currentRow = 1;

    // --- COMPACT LOGO WITH VERTICAL COMPANY INFO ---
    if (logoBytes != null) {
      // Logo in minimal space - single column
      sheet.getRangeByName('A1:A2').merge();
      final xlsio.Picture picture = sheet.pictures.addStream(1, 1, logoBytes);
      picture.height = LOGO_HEIGHT.toInt();
      picture.width = LOGO_WIDTH.toInt();

      // Company name NEXT TO logo - row 1
      sheet.getRangeByName('B1:M1')
        ..merge()
        ..setText(companyName)
        ..cellStyle = leftHeaderStyle;
      sheet.setRowHeightInPixels(1, 30);

      // Company address BELOW company name - row 2
      sheet.getRangeByName('B2:M2')
        ..merge()
        ..setText(companyAddress)
        ..cellStyle = leftSubHeaderStyle;
      sheet.setRowHeightInPixels(2,  25);

      currentRow = 3; // Next available row
    } else {
      // No logo - vertical layout for company info
      final xlsio.Style centerHeaderStyle = workbook.styles.add('CenterHeaderStyle')
        ..fontName = 'Arial'
        ..fontSize = 18
        ..bold = true
        ..hAlign = xlsio.HAlignType.center
        ..vAlign = xlsio.VAlignType.center
        ..wrapText = true;

      final xlsio.Style centerSubHeaderStyle = workbook.styles.add('CenterSubHeaderStyle')
        ..fontName = 'Arial'
        ..fontSize = 12
        ..hAlign = xlsio.HAlignType.center
        ..vAlign = xlsio.VAlignType.center
        ..wrapText = true;

      // Company name - first row
      sheet.getRangeByName('A1:O1')
        ..merge()
        ..setText(companyName)
        ..cellStyle = centerHeaderStyle;
      sheet.setRowHeightInPixels(1,  30);

      // Company address - second row
      sheet.getRangeByName('A2:O2')
        ..merge()
        ..setText(companyAddress)
        ..cellStyle = centerSubHeaderStyle;
      sheet.setRowHeightInPixels(2, 25);

      currentRow = 3;
    }
    currentRow++; // Single spacing after header

    // --- METADATA SECTION ---
    final metadata = {
      'File Name:': fileName,
      'Operator:': operatorName,
      'Report Period:': '${DateFormat('dd-MMM-yyyy HH:mm').format(firstTimestamp)} to ${DateFormat('dd-MMM-yyyy HH:mm').format(lastTimestamp)}'
    };

    metadata.forEach((key, value) {
      sheet.getRangeByIndex(currentRow, 1)
        ..setText(key)
        ..cellStyle = infoStyle;

      sheet.getRangeByName('B$currentRow:H$currentRow')
        ..merge()
        ..setText(value)
        ..cellStyle = infoValueStyle;

      sheet.setRowHeightInPixels(currentRow, 20);
      currentRow++;
    });
    currentRow++;

    // --- USER DEFINED HEADER LINES ---
    headerLines.where((l) => l.isNotEmpty).forEach((line) {
      sheet.getRangeByName('A$currentRow:H$currentRow')
        ..merge()
        ..setText(line)
        ..cellStyle = userHeaderStyle;
      sheet.setRowHeightInPixels(currentRow, 25);
      currentRow++;
    });
    currentRow++;

    // --- GRAPH SECTION FIRST WITH FIXED-WIDTH LEFT-ALIGNED TITLE ---
    if ((mode == 'Graph' || mode == 'Combined') && graphImage != null) {
      // Fixed-width left-aligned title (A to H instead of A to O)
      sheet.getRangeByName('A$currentRow:H$currentRow')
        ..merge()
        ..setText('📊 GRAPHICAL REPRESENTATION')
        ..cellStyle = graphTitleStyle;
      sheet.setRowHeightInPixels(currentRow, 35);
      currentRow += 2;

      const double graphWidth = 650.0;
      const double graphHeight = 400.0;

      final xlsio.Picture picture = sheet.pictures.addStream(currentRow, 1, graphImage);
      picture.height = graphHeight.toInt();
      picture.width = graphWidth.toInt();

      const double defaultRowHeightInPixels = 20.0;
      final int rowsSpannedByGraph = (graphHeight / defaultRowHeightInPixels).ceil();
      currentRow += rowsSpannedByGraph + 3;
    }

    // --- TABLE SECTION WITH FIXED-WIDTH LEFT-ALIGNED TITLE ---
    if (mode == 'Table' || mode == 'Combined') {
      // Fixed-width left-aligned title (A to H instead of A to O)
      sheet.getRangeByName('A$currentRow:H$currentRow')
        ..merge()
        ..setText('📋 DATA TABLE')
        ..cellStyle = tableTitleStyle;
      sheet.setRowHeightInPixels(currentRow,  35);
      currentRow += 2;

      int dataTableStartRow = currentRow;

      final List<String> headers = [
        'Date',
        'Time',
        ...channelNames.values.map((name) => '$name (${channelSetupData[name]?.unit ?? ""})')
      ];
      final int totalColumns = headers.length;

      sheet.importList(headers, dataTableStartRow, 1, false);
      sheet.getRangeByIndex(dataTableStartRow, 1, dataTableStartRow, totalColumns).cellStyle = tableHeaderStyle;
      sheet.setRowHeightInPixels(dataTableStartRow, 28);

      for (var i = 0; i < tableData.length; i++) {
        _writeExcelDataRow(sheet, i, dataTableStartRow, tableData[i], channelNames, channelSetupData, numberStyles);
        sheet.setRowHeightInPixels(dataTableStartRow + 1 + i,  20);
      }

      // --- COLUMN WIDTHS WITH WIDER CHANNEL HEADERS ---
      for (int i = 2; i <= totalColumns; i++) {
        sheet.autoFitColumn(i);
        double currentWidth = sheet.getColumnWidth(i);

        if (i == 2) {
          sheet.setColumnWidthInPixels(i, 75);
        } else {
          if (currentWidth < 110) {
            sheet.setColumnWidthInPixels(i, 110);
          } else if (currentWidth > 130) {
            sheet.setColumnWidthInPixels(i, 130);
          } else {
            sheet.setColumnWidthInPixels(i, 115);
          }
        }
      }

      try {
        sheet.pageSetup.printTitleRows = '\$1:\$${dataTableStartRow}';
      } catch (e) {
        print('Warning: Could not set print title rows: $e');
      }

      currentRow += tableData.length + 2;
    }

    // --- FOOTER SECTION WITH VERTICAL LAYOUT (LIKE HEADER) ---
    final nonEmptyFooterLines = footerLines.where((l) => l.isNotEmpty).toList();

    if (nonEmptyFooterLines.isNotEmpty) {
      currentRow++; // Add spacing before footer

      if (nonEmptyFooterLines.length == 1) {
        // Single footer line - full allocated width
        sheet.getRangeByName('A$currentRow:H$currentRow')
          ..merge()
          ..setText(nonEmptyFooterLines.first)
          ..cellStyle = manualFooterStyle;
        sheet.setRowHeightInPixels(currentRow, 25);
      } else {
        // Multiple footer lines - vertical stacking like header
        for (int i = 0; i < nonEmptyFooterLines.length; i++) {
          sheet.getRangeByName('A$currentRow:H$currentRow')
            ..merge()
            ..setText(nonEmptyFooterLines[i])
            ..cellStyle = manualFooterStyle;
          sheet.setRowHeightInPixels(currentRow, 25);
          currentRow++;
        }
      }
    }

    // --- FINAL COLUMN WIDTH SETTINGS ---
    sheet.setColumnWidthInPixels(1, 200); // Wide column for metadata labels

    await _saveFile(context, workbook.saveAsStream(), fileName, 'xlsx');
    workbook.dispose();
  }




  static Future<void> _exportToPdf({
    required BuildContext context, required String mode, required List<Map<String, dynamic>> tableData,
    required Uint8List? graphImage, required String fileName, required String companyName,
    required String operatorName, required String companyAddress, required Uint8List? logoBytes,
    required Map<int, String> channelNames, required DateTime firstTimestamp, required DateTime lastTimestamp,
    required Map<String, Channel> channelSetupData, required List<String> headerLines, required List<String> footerLines,
  }) async {
    final PdfDocument document = PdfDocument();
    document.pageSettings.orientation = PdfPageOrientation.landscape;
    document.pageSettings.margins.all = 30;
    final Size pageSize = document.pageSettings.size;
    final Rect headerBounds = Rect.fromLTWH(0, 0, pageSize.width, 170);
    document.template.top = _buildPdfHeader(headerBounds, companyName, companyAddress, logoBytes, fileName, operatorName, firstTimestamp, lastTimestamp, headerLines);
    final Rect footerBounds = Rect.fromLTWH(0, 0, pageSize.width, 80);
    document.template.bottom = _buildPdfFooter(footerBounds, footerLines);
    PdfPage currentPage = document.pages.add();
    double currentY = 0;
    if (mode == 'Table' || mode == 'Combined') {
      final PdfGrid grid = _createPdfGrid(tableData, channelNames, channelSetupData);
      final PdfLayoutResult gridResult = grid.draw(page: currentPage, bounds: Rect.fromLTWH(0, currentY, currentPage.getClientSize().width, currentPage.getClientSize().height),)!;
      currentPage = gridResult.page;
      currentY = gridResult.bounds.bottom + 10;
    }
    if ((mode == 'Graph' || mode == 'Combined') && graphImage != null) {
      final PdfBitmap pdfImage = PdfBitmap(graphImage);
      final Size clientSize = currentPage.getClientSize();
      final double availableHeight = clientSize.height - currentY;
      if(availableHeight < 200) {
        currentPage = document.pages.add();
        currentY = 0;
      }
      final double imageAspectRatio = pdfImage.width / pdfImage.height;
      double finalWidth = clientSize.width;
      double finalHeight = finalWidth / imageAspectRatio;
      if (finalHeight > (clientSize.height - currentY)) {
        finalHeight = clientSize.height - currentY;
        finalWidth = finalHeight * imageAspectRatio;
      }
      final double x = (clientSize.width - finalWidth) / 2;
      final Rect imageBounds = Rect.fromLTWH(x, currentY, finalWidth, finalHeight);
      currentPage.graphics.drawImage(pdfImage, imageBounds);
    }
    final List<int> bytes = await document.save();
    document.dispose();
    await _saveFile(context, bytes, fileName, 'pdf');
  }

  static Future<void> _exportTableToCsv({ required BuildContext context, required List<Map<String, dynamic>> tableData, required String fileName, required Map<int, String> channelNames, required Map<String, Channel> channelSetupData}) async {
    final StringBuffer csvBuffer = StringBuffer();
    final headers = ['Date', 'Time', ...channelNames.values.map((name) => '$name (${channelSetupData[name]?.unit ?? ""})')];
    csvBuffer.writeln(headers.map((h) => '"$h"').join(','));
    for (final row in tableData) {
      final List<String> rowValues = [_parseDate(row['AbsDate']), row['AbsTime'] as String? ?? ''];
      for (int channelId in channelNames.keys) { rowValues.add(row['AbsPer$channelId']?.toString() ?? ''); }
      csvBuffer.writeln(rowValues.map((v) => '"$v"').join(','));
    }
    await _saveFile(context, utf8.encode(csvBuffer.toString()), fileName, 'csv');
  }
  static Future<void> _exportToHtmlForWord({
    required BuildContext context,
    required String mode,
    required List<Map<String, dynamic>> tableData,
    required Uint8List? graphImage,
    required String fileName,
    required String operatorName,
    required String companyName,
    required String companyAddress,
    required Uint8List? logoBytes,
    required Map<int, String> channelNames,
    required DateTime firstTimestamp,
    required DateTime lastTimestamp,
    required Map<String, Channel> channelSetupData,
    required List<String> headerLines,
    required List<String> footerLines
  }) async {
    final StringBuffer html = StringBuffer();

    // Generate Word-compatible HTML structure
    html.writeln('<!DOCTYPE html>');
    html.writeln('<html xmlns:o="urn:schemas-microsoft-com:office:office" xmlns:w="urn:schemas-microsoft-com:office:word">');
    html.writeln('<head>');
    html.writeln('<meta charset="utf-8">');
    html.writeln('<title>Report</title>');
    html.writeln('<!--[if gte mso 9]>');
    html.writeln('<xml><w:WordDocument><w:View>Print</w:View><w:Zoom>90</w:Zoom></w:WordDocument></xml>');
    html.writeln('<![endif]-->');
    html.writeln(_getWordCompatibleStyles());
    html.writeln('</head>');
    html.writeln('<body>');

    // Start main content wrapper
    html.writeln('<div class="document">');

    // --- COMPACT HEADER SECTION (NO GAPS) ---
    html.writeln('<table class="header-table">');
    html.writeln('<tr>');
    if (logoBytes != null) {
      html.writeln('<td class="logo-cell">');
      // INCREASED LOGO SIZE - from 60x25 to 80x35
      final logoBase64 = base64Encode(logoBytes);
      html.writeln('<img width="80" height="35" src="data:image/png;base64,$logoBase64" alt="Logo">');
      html.writeln('</td>');
      html.writeln('<td class="company-cell">');
    } else {
      html.writeln('<td colspan="2" class="company-cell-center">');
    }

    html.writeln('<div class="company-name">$companyName</div>');
    html.writeln('<div class="company-address">$companyAddress</div>');
    html.writeln('</td>');
    html.writeln('</tr>');
    html.writeln('</table>');

    // --- METADATA SECTION ---
    html.writeln('<table class="metadata-table">');
    html.writeln('<tr>');
    html.writeln('<td class="label-cell">File Name:</td>');
    html.writeln('<td class="value-cell">$fileName</td>');
    html.writeln('</tr>');
    html.writeln('<tr>');
    html.writeln('<td class="label-cell">Operator:</td>');
    html.writeln('<td class="value-cell">$operatorName</td>');
    html.writeln('</tr>');
    html.writeln('<tr>');
    html.writeln('<td class="label-cell">Report Period:</td>');
    html.writeln('<td class="value-cell">${DateFormat('dd-MMM-yyyy HH:mm').format(firstTimestamp)} to ${DateFormat('dd-MMM-yyyy HH:mm').format(lastTimestamp)}</td>');
    html.writeln('</tr>');
    html.writeln('</table>');

    // --- USER HEADERS ---
    if (headerLines.where((l) => l.isNotEmpty).isNotEmpty) {
      headerLines.where((l) => l.isNotEmpty).forEach((line) {
        html.writeln('<div class="user-header">$line</div>');
      });
    }

    // --- GRAPH SECTION (IF PRESENT) ---
    if ((mode == 'Graph' || mode == 'Combined') && graphImage != null) {
      html.writeln('<div class="section-title graph-section">📊 GRAPHICAL REPRESENTATION</div>');
      html.writeln('<div class="graph-container">');
      // INCREASED GRAPH HEIGHT - from 300 to 400 for better visibility
      final graphBase64 = base64Encode(graphImage);
      html.writeln('<img width="480" height="400" src="data:image/png;base64,$graphBase64" alt="Graph">');
      html.writeln('</div>');
    }

    // --- TABLE SECTION (IF PRESENT) ---
    if (mode == 'Table' || mode == 'Combined') {
      html.writeln('<div class="section-title table-section">📋 DATA TABLE</div>');
      html.writeln('<table class="data-table">');

      // Table headers
      final headers = ['Date', 'Time', ...channelNames.values.map((name) => '$name (${channelSetupData[name]?.unit ?? ""})')];
      html.writeln('<thead>');
      html.writeln('<tr>');
      headers.forEach((h) => html.writeln('<th>$h</th>'));
      html.writeln('</tr>');
      html.writeln('</thead>');

      // Table data
      html.writeln('<tbody>');
      for (int i = 0; i < tableData.length; i++) {
        final row = tableData[i];
        final rowClass = i % 2 == 0 ? 'even-row' : 'odd-row';
        html.writeln('<tr class="$rowClass">');
        html.writeln('<td>${_parseDate(row['AbsDate'])}</td>');
        html.writeln('<td>${row['AbsTime'] as String? ?? ''}</td>');
        for (int channelId in channelNames.keys) {
          final value = (row['AbsPer$channelId'] as num?)?.toStringAsFixed(channelSetupData[channelNames[channelId]]?.decimalPlaces ?? 2) ?? '-';
          html.writeln('<td class="data-cell">$value</td>');
        }
        html.writeln('</tr>');
      }
      html.writeln('</tbody>');
      html.writeln('</table>');
    }

    // --- FOOTER SECTION ---
    final nonEmptyFooterLines = footerLines.where((l) => l.isNotEmpty).toList();
    if (nonEmptyFooterLines.isNotEmpty) {
      html.writeln('<div class="footer-section">');
      nonEmptyFooterLines.forEach((line) {
        html.writeln('<div class="footer-line">$line</div>');
      });
      html.writeln('</div>');
    }

    html.writeln('</div>'); // Close document wrapper
    html.writeln('</body>');
    html.writeln('</html>');

    await _saveFile(context, utf8.encode(html.toString()), fileName, 'doc');
  }

  static String _getWordCompatibleStyles() {
    return '''
<style>
@page {
    size: A4 landscape;
    margin: 1in 0.5in 1in 0.5in;
}

body {
    font-family: Arial, sans-serif;
    font-size: 10pt;
    line-height: 1.2;
    margin: 0;
    padding: 0;
}

.document {
    max-width: 100%;
}

/* Header Section - NO GAPS */
.header-table {
    width: 100%;
    border-collapse: collapse;
    margin-bottom: 10pt; /* Reduced from 15pt */
}

.logo-cell {
    width: 100pt; /* Increased from 80pt for larger logo */
    vertical-align: top;
    padding: 0;
}

.company-cell, .company-cell-center {
    vertical-align: top;
    padding-left: 5pt; /* Reduced from 10pt - LESS GAP */
}

.company-cell-center {
    text-align: center;
    padding-left: 0;
}

.company-name {
    font-size: 14pt;
    font-weight: bold;
    margin: 0 0 1pt 0; /* Reduced bottom margin from 3pt to 1pt */
    color: #333;
}

.company-address {
    font-size: 10pt;
    color: #666;
    margin: 0; /* No margin for tight spacing */
}

/* Metadata Section */
.metadata-table {
    width: 100%;
    border-collapse: collapse;
    margin-bottom: 15pt;
}

.label-cell {
    width: 120pt;
    font-weight: bold;
    padding: 2pt 10pt 2pt 0;
    vertical-align: top;
    font-size: 9pt;
}

.value-cell {
    padding: 2pt 0;
    font-size: 9pt;
}

/* User Headers */
.user-header {
    font-weight: bold;
    font-size: 9pt;
    margin: 2pt 0;
}

/* Section Titles */
.section-title {
    font-size: 12pt;
    font-weight: bold;
    padding: 6pt 10pt;
    margin: 15pt 0 8pt 0;
    width: 50%;
    border: 1pt solid;
}

.graph-section {
    background-color: #E8F4FD;
    border-color: #4A90A4;
    color: #2C5F6F;
}

.table-section {
    background-color: #FFF2CC;
    border-color: #D6B656;
    color: #8B7315;
}

/* Graph Container */
.graph-container {
    margin: 10pt 0 20pt 0;
    text-align: left;
}

/* Data Table */
.data-table {
    width: 100%;
    border-collapse: collapse;
    font-size: 8pt;
    margin: 10pt 0 20pt 0;
}

.data-table th {
    background-color: #D9E1F2;
    border: 0.5pt solid #999;
    padding: 4pt 3pt;
    font-weight: bold;
    text-align: center;
    font-size: 8pt;
}

.data-table td {
    border: 0.5pt solid #ccc;
    padding: 3pt;
    font-size: 8pt;
}

.data-cell {
    text-align: center;
}

.even-row {
    background-color: #f9f9f9;
}

.odd-row {
    background-color: white;
}

/* Footer Section */
.footer-section {
    margin-top: 20pt;
}

.footer-line {
    font-style: italic;
    font-size: 8pt;
    margin: 2pt 0;
    color: #666;
}

/* Print Specific */
@media print {
    .data-table thead {
        display: table-header-group;
    }
    
    .data-table tbody tr {
        page-break-inside: avoid;
    }
}
</style>
''';
  }



  static Future<ExportFormat?> _showExportFormatDialog(BuildContext context) async {
    return showDialog<ExportFormat>(
      context: context, builder: (ctx) => AlertDialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15.0)),
      title: const Text('Select Export Format', textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.bold)),
      content: SizedBox(width: 320, child: GridView.count(crossAxisCount: 2, shrinkWrap: true, mainAxisSpacing: 15, crossAxisSpacing: 15, childAspectRatio: 1.1,
        children: [
          _buildFormatOption(ctx, Icons.grid_on_rounded, 'Excel', '(.xlsx)', ExportFormat.excel, Colors.green),
          _buildFormatOption(ctx, Icons.picture_as_pdf_rounded, 'PDF', '(.pdf)', ExportFormat.pdf, Colors.red),
          _buildFormatOption(ctx, Icons.view_list_rounded, 'CSV', '(.csv)', ExportFormat.csv, Colors.orange),
          _buildFormatOption(ctx, Icons.description_rounded, 'Word', '(.doc)', ExportFormat.docx, Colors.blue),
        ],
      ),
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('CANCEL'))],
    ),
    );
  }

  static Widget _buildFormatOption(BuildContext context, IconData icon, String title, String subtitle, ExportFormat format, Color color) {
    return Material(
      color: color.withOpacity(0.05),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        splashColor: color.withOpacity(0.2),
        onTap: () => Navigator.pop(context, format),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 40, color: color), const SizedBox(height: 10),
            Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            Text(subtitle, style: const TextStyle(fontSize: 12, color: Colors.black54)),
          ],
        ),
      ),
    );
  }

  static Future<void> _saveFile(BuildContext context, List<int> bytes, String baseFileName, String extension) async {
    final cleanFileName = baseFileName.replaceAll(RegExp(r'[<>:"/\\|?*]'), '_');
    String? outputFile = await FilePicker.platform.saveFile(
      dialogTitle: 'Select location to save the report',
      fileName: '$cleanFileName.$extension',
    );

    if (outputFile == null) {
      return;
    }

    // --- ENHANCED EXTENSION HANDLING ---
    // Ensure the file always has the correct extension
    String finalPath = outputFile;

    // Check if the selected path already has the correct extension
    if (!finalPath.toLowerCase().endsWith('.$extension')) {
      // Remove any existing extension that might conflict
      final lastDotIndex = finalPath.lastIndexOf('.');
      if (lastDotIndex > finalPath.lastIndexOf(Platform.pathSeparator)) {
        // Only remove extension if the dot is after the last path separator
        finalPath = finalPath.substring(0, lastDotIndex);
      }

      // Append the correct extension
      finalPath = '$finalPath.$extension';
    }

    final file = File(finalPath);
    await file.writeAsBytes(bytes, flush: true);
    MessageUtils.showMessage(context, 'File saved successfully to ${file.path}');
  }


  static void _showLoadingDialog(BuildContext context, String message) {
    showDialog(context: context, barrierDismissible: false, builder: (ctx) => AlertDialog(content: Row(children: [const CircularProgressIndicator(), const SizedBox(width: 24), Text(message)])));
  }

  static String _parseDate(String? dateStr, [String? timeStr]) {
    if (dateStr == null) return '';
    try {
      final fullDateTimeStr = (timeStr != null) ? '$dateStr $timeStr' : dateStr;
      final dt = DateTime.parse(fullDateTimeStr);
      final format = (timeStr != null) ? DateFormat('dd-MM-yyyy HH:mm:ss') : DateFormat('dd-MM-yyyy');
      return format.format(dt);
    } catch (e) {
      return dateStr.split(' ').first;
    }
  }

  static PdfPageTemplateElement _buildPdfHeader(
      Rect bounds, String companyName, String companyAddress,
      Uint8List? logoBytes, String fileName, String operatorName,
      DateTime firstTimestamp, DateTime lastTimestamp, List<String> headerLines,
      ) {
    final PdfPageTemplateElement headerElement = PdfPageTemplateElement(bounds);
    final PdfFont titleFont = PdfStandardFont(PdfFontFamily.helvetica, 14, style: PdfFontStyle.bold);
    final PdfFont bodyFont = PdfStandardFont(PdfFontFamily.helvetica, 10);
    final PdfFont smallBoldFont = PdfStandardFont(PdfFontFamily.helvetica, 9, style: PdfFontStyle.bold);
    final PdfFont smallFont = PdfStandardFont(PdfFontFamily.helvetica, 9);
    final PdfPen linePen = PdfPen(PdfColor(128, 128, 128), width: 0.7);
    final DateFormat timestampFormat = DateFormat('dd-MMM-yyyy HH:mm');

    double currentY = 0;
    double leftPaneX = 0;

    if (logoBytes != null) {
      final PdfBitmap logo = PdfBitmap(logoBytes);
      final double logoHeight = LOGO_HEIGHT;
      final double logoWidth = logo.width * (logoHeight / logo.height);
      headerElement.graphics.drawImage(logo, Rect.fromLTWH(0, currentY, logoWidth, logoHeight));
      leftPaneX = logoWidth + 15;
    }

    final double textWidth = bounds.width - leftPaneX;
    final PdfStringFormat companyNameFormat = PdfStringFormat(alignment: leftPaneX > 0 ? PdfTextAlignment.left : PdfTextAlignment.center, lineAlignment: PdfVerticalAlignment.middle);

    headerElement.graphics.drawString(companyName, titleFont, brush: PdfBrushes.black, bounds: Rect.fromLTWH(leftPaneX, currentY, textWidth, 25), format: companyNameFormat);
    currentY += 22;
    headerElement.graphics.drawString(companyAddress, bodyFont, brush: PdfBrushes.darkGray, bounds: Rect.fromLTWH(leftPaneX, currentY, textWidth, 20), format: companyNameFormat);
    currentY = 55;
    headerElement.graphics.drawLine(linePen, Offset(0, currentY), Offset(bounds.width, currentY));
    currentY += 8;

    final double halfWidth = bounds.width / 2;
    const double labelPadding = 5;

    final Size fileLabelSize = smallBoldFont.measureString('File Name:');
    headerElement.graphics.drawString('File Name:', smallBoldFont, bounds: Rect.fromLTWH(0, currentY, fileLabelSize.width, 15));
    headerElement.graphics.drawString(fileName, smallFont, bounds: Rect.fromLTWH(fileLabelSize.width + labelPadding, currentY, halfWidth - (fileLabelSize.width + labelPadding), 15));

    final Size operatorLabelSize = smallBoldFont.measureString('Operator Name:');
    headerElement.graphics.drawString('Operator Name:', smallBoldFont, bounds: Rect.fromLTWH(halfWidth, currentY, operatorLabelSize.width, 15));
    headerElement.graphics.drawString(operatorName, smallFont, bounds: Rect.fromLTWH(halfWidth + operatorLabelSize.width + labelPadding, currentY, halfWidth - (operatorLabelSize.width + labelPadding), 15));
    currentY += 15;
    headerElement.graphics.drawString('Report Period:', smallBoldFont, bounds: Rect.fromLTWH(0, currentY, 80, 15));
    headerElement.graphics.drawString('${timestampFormat.format(firstTimestamp)} to ${timestampFormat.format(lastTimestamp)}', smallFont, bounds: Rect.fromLTWH(85, currentY, bounds.width - 85, 15));
    currentY += 20;

    for (String line in headerLines.where((l) => l.isNotEmpty)) {
      if (currentY < (bounds.height - 15)) {
        headerElement.graphics.drawString(line, smallBoldFont, bounds: Rect.fromLTWH(0, currentY, bounds.width, 15));
        currentY += 15;
      }
    }
    return headerElement;
  }

  static PdfPageTemplateElement _buildPdfFooter(Rect bounds, List<String> footerLines) {
    final PdfPageTemplateElement footer = PdfPageTemplateElement(bounds);
    double yPos = 0;
    footer.graphics.drawLine(PdfPen(PdfColor(0, 0, 0)), Offset(0, yPos), Offset(bounds.width, yPos));
    yPos += 5;
    for (final line in footerLines.where((l) => l.isNotEmpty)) {
      footer.graphics.drawString(line, PdfStandardFont(PdfFontFamily.helvetica, 9, style: PdfFontStyle.italic), bounds: Rect.fromLTWH(0, yPos, bounds.width, 15));
      yPos += 15;
    }
    yPos += 5;
    footer.graphics.drawString('Exported on: ${DateFormat('dd-MMM-yyyy HH:mm').format(DateTime.now())}', PdfStandardFont(PdfFontFamily.helvetica, 8), bounds: Rect.fromLTWH(0, yPos, 200, 15));
    final PdfCompositeField pageNumberField = PdfCompositeField(font: PdfStandardFont(PdfFontFamily.helvetica, 8), brush: PdfBrushes.black, text: 'Page {0} of {1}', fields: [PdfPageNumberField(), PdfPageCountField()]);
    pageNumberField.draw(footer.graphics, Offset(bounds.width - 60, yPos));
    return footer;
  }

  static PdfGrid _createPdfGrid(List<Map<String, dynamic>> tableData, Map<int, String> channelNames, Map<String, Channel> channelSetupData) {
    final PdfGrid grid = PdfGrid();
    final DateFormat dateFormat = DateFormat('yyyy-MM-dd');
    final DateFormat timeFormat = DateFormat('HH:mm:ss');
    final List<int> sortedChannelKeys = channelNames.keys.toList()..sort();
    grid.columns.add(count: 2 + sortedChannelKeys.length);
    final PdfGridRow header = grid.headers.add(1)[0];
    header.style = PdfGridCellStyle(backgroundBrush: PdfBrushes.lightSlateGray, textBrush: PdfBrushes.white, font: PdfStandardFont(PdfFontFamily.helvetica, 8, style: PdfFontStyle.bold));
    header.cells[0].value = 'Date (YYYY-MM-DD)';
    header.cells[1].value = 'Time (HH:mm:ss)';
    for (int i = 0; i < sortedChannelKeys.length; i++) {
      final int channelId = sortedChannelKeys[i];
      final String name = channelNames[channelId]!;
      final String unit = channelSetupData[name]?.unit ?? "";
      header.cells[i + 2].value = '$name ($unit)';
    }
    for (final Map<String, dynamic> rowData in tableData) {
      final PdfGridRow row = grid.rows.add();
      final String? dateStr = rowData['AbsDate'];
      final String? timeStr = rowData['AbsTime'];
      if (dateStr != null && timeStr != null && dateStr.isNotEmpty && timeStr.isNotEmpty) {
        try {
          final DateTime timestamp = DateTime.parse('$dateStr $timeStr');
          row.cells[0].value = dateFormat.format(timestamp);
          row.cells[1].value = timeFormat.format(timestamp);
        } catch (e) {
          row.cells[0].value = dateStr;
          row.cells[1].value = timeStr;
        }
      } else {
        row.cells[0].value = dateStr ?? '';
        row.cells[1].value = timeStr ?? '';
      }
      for (int i = 0; i < sortedChannelKeys.length; i++) {
        final int channelId = sortedChannelKeys[i];
        final String channelName = channelNames[channelId]!;
        final num? value = rowData['AbsPer$channelId'] as num?;
        final int decimalPlaces = channelSetupData[channelName]?.decimalPlaces ?? 2;
        row.cells[i + 2].value = value?.toStringAsFixed(decimalPlaces) ?? '-';
      }
    }
    grid.applyBuiltInStyle(PdfGridBuiltInStyle.listTable4Accent5);
    grid.style.font = PdfStandardFont(PdfFontFamily.helvetica, 7);
    return grid;
  }

  static Map<String, xlsio.Style> _createNumberStyles(xlsio.Workbook workbook) {
    final Map<String, xlsio.Style> styles = {};
    styles['normal_base'] = workbook.styles.add('normal_base')..fontName='Arial'..fontSize=10..borders.all.lineStyle=xlsio.LineStyle.thin;
    styles['alt_base'] = workbook.styles.add('alt_base')..fontName='Arial'..fontSize=10..backColor='#F2F2F2'..borders.all.lineStyle=xlsio.LineStyle.thin;
    for (int i = 0; i <= 10; i++) {
      final numFormat = '0${i > 0 ? '.' : ''}${'0' * i}';
      styles['normal_$numFormat'] = workbook.styles.add('normal_$numFormat')..numberFormat=numFormat..fontName='Arial'..fontSize=10..borders.all.lineStyle=xlsio.LineStyle.thin;
      styles['alt_$numFormat'] = workbook.styles.add('alt_$numFormat')..numberFormat=numFormat..fontName='Arial'..fontSize=10..backColor='#F2F2F2'..borders.all.lineStyle=xlsio.LineStyle.thin;
    }
    return styles;
  }

  static void _writeExcelDataRow(xlsio.Worksheet sheet, int rowIndex, int startRow, Map<String, dynamic> rowData, Map<int, String> channelNames, Map<String, Channel> channelSetupData, Map<String, xlsio.Style> numberStyles) {
    final excelRowIndex = startRow + 1 + rowIndex;
    final isAltRow = rowIndex % 2 != 0;
    final baseStyle = isAltRow ? numberStyles['alt_base']! : numberStyles['normal_base']!;
    sheet.getRangeByIndex(excelRowIndex, 1)..setText(_parseDate(rowData['AbsDate']))..cellStyle = baseStyle;
    sheet.getRangeByIndex(excelRowIndex, 2)..setText(rowData['AbsTime'] as String? ?? '')..cellStyle = baseStyle;
    int colIndex = 3;
    for (int channelId in channelNames.keys) {
      double? value = (rowData['AbsPer$channelId'] as num?)?.toDouble();
      final cell = sheet.getRangeByIndex(excelRowIndex, colIndex);
      if (value != null) {
        final decimalPlaces = channelSetupData[channelNames[channelId]]?.decimalPlaces ?? 2;
        final format = '0${decimalPlaces > 0 ? '.' : ''}${'0' * decimalPlaces}';
        final styleKey = isAltRow ? 'alt_$format' : 'normal_$format';
        cell..setNumber(value)..cellStyle = numberStyles[styleKey] ?? baseStyle;
      } else {
        cell..setText('-')..cellStyle = baseStyle;
      }
      colIndex++;
    }
  }

  static String _getHtmlBoilerplate() {
    return '''<!DOCTYPE html><html><head><title>Report</title><style>
    body { font-family: Arial, sans-serif; }
    .header { text-align: center; margin-bottom: 20px; }
    table { border-collapse: collapse; width: 100%; margin-bottom: 20px; }
    th, td { border: 1px solid #dddddd; text-align: left; padding: 8px; }
    thead tr { background-color: #f2f2f2; }
    tbody tr:nth-child(even) { background-color: #f9f9f9; }
    h1, h2, h3 { color: #333; }
    h1 { font-size: 24px; } h3 { font-size: 16px; }
    </style></head>''';
  }
}