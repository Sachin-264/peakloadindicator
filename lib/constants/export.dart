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
  static const double LOGO_HEIGHT = 50.0;
  static const double LOGO_WIDTH = 150.0;

  static Future<void> exportBasedOnMode({
    required BuildContext context,
    required String mode,
    required List<Map<String, dynamic>> tableData,
    required String fileName,
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
  }) async {
    if ((mode == 'Table' || mode == 'Combined') && tableData.isEmpty) { MessageUtils.showMessage(context, 'No table data to export.', isError: true); return; }
    if ((mode == 'Graph' || mode == 'Combined') && graphImage == null) { MessageUtils.showMessage(context, 'No graph image to export.', isError: true); return; }

    switch (format) {
      case ExportFormat.excel: await _exportToExcel(context: context, mode: mode, tableData: tableData, graphImage: graphImage, fileName: fileName, companyName: companyName, companyAddress: companyAddress, logoBytes: logoBytes, channelNames: channelNames, firstTimestamp: firstTimestamp, lastTimestamp: lastTimestamp, channelSetupData: channelSetupData, headerLines: headerLines, footerLines: footerLines); break;
      case ExportFormat.pdf: await _exportToPdf(context: context, mode: mode, tableData: tableData, graphImage: graphImage, fileName: fileName, companyName: companyName, companyAddress: companyAddress, logoBytes: logoBytes, channelNames: channelNames, firstTimestamp: firstTimestamp, lastTimestamp: lastTimestamp, channelSetupData: channelSetupData, headerLines: headerLines, footerLines: footerLines); break;
      case ExportFormat.csv: if (mode == 'Graph') { MessageUtils.showMessage(context, 'CSV export is not available for "Graph only" mode.', isError: true); return; } await _exportTableToCsv(context: context, tableData: tableData, fileName: fileName, channelNames: channelNames, channelSetupData: channelSetupData); break;
      case ExportFormat.docx: await _exportToHtmlForWord(context: context, mode: mode, tableData: tableData, graphImage: graphImage, fileName: fileName, companyName: companyName, companyAddress: companyAddress, logoBytes: logoBytes, channelNames: channelNames, firstTimestamp: firstTimestamp, lastTimestamp: lastTimestamp, channelSetupData: channelSetupData, headerLines: headerLines, footerLines: footerLines); break;
    }
  }

  static Future<void> _exportToExcel({ required BuildContext context, required String mode, required List<Map<String, dynamic>> tableData, required Uint8List? graphImage, required String fileName, required String companyName, required String companyAddress, required Uint8List? logoBytes, required Map<int, String> channelNames, required DateTime firstTimestamp, required DateTime lastTimestamp, required Map<String, Channel> channelSetupData, required List<String> headerLines, required List<String> footerLines}) async {
    final xlsio.Workbook workbook = xlsio.Workbook();
    final xlsio.Worksheet sheet = workbook.worksheets[0];
    sheet.name = 'Report';
    final xlsio.Style centerHeaderStyle = workbook.styles.add('CenterHeaderStyle')..fontName='Arial'..fontSize=18..bold=true..hAlign=xlsio.HAlignType.center..vAlign=xlsio.VAlignType.center;
    final xlsio.Style centerSubHeaderStyle = workbook.styles.add('CenterSubHeaderStyle')..fontName='Arial'..fontSize=12..hAlign=xlsio.HAlignType.center..vAlign=xlsio.VAlignType.center;
    final xlsio.Style infoStyle = workbook.styles.add('InfoStyle')..fontName='Arial'..fontSize=11..bold=true;
    final xlsio.Style userHeaderStyle = workbook.styles.add('UserHeaderStyle')..fontName='Arial'..fontSize=10..bold=true;
    final xlsio.Style userFooterStyle = workbook.styles.add('UserFooterStyle')..fontName='Arial'..fontSize=10..italic=true;
    final xlsio.Style tableHeaderStyle = workbook.styles.add('TableHeaderStyle')..fontName='Arial'..fontSize=10..bold=true..backColor='#D9E1F2'..hAlign=xlsio.HAlignType.center..vAlign=xlsio.VAlignType.center..borders.all.lineStyle=xlsio.LineStyle.thin;
    final Map<String, xlsio.Style> numberStyles = _createNumberStyles(workbook);
    int currentRow = 1;
    if (logoBytes != null) {
      sheet.getRangeByName('A1:C4').merge();
      final xlsio.Picture picture = sheet.pictures.addStream(1, 1, logoBytes);
      picture.height = LOGO_HEIGHT.toInt(); picture.width = LOGO_WIDTH.toInt();
      sheet.getRangeByName('D1:J2')..merge()..setText(companyName)..cellStyle = centerHeaderStyle;
      sheet.getRangeByName('D3:J4')..merge()..setText(companyAddress)..cellStyle = centerSubHeaderStyle;
      currentRow += 5;
    } else {
      sheet.getRangeByName('A1:J2')..merge()..setText(companyName)..cellStyle = centerHeaderStyle;
      sheet.getRangeByName('A3:J4')..merge()..setText(companyAddress)..cellStyle = centerSubHeaderStyle;
      currentRow += 5;
    }
    final metadata = { 'File Name:': fileName, 'Report Period:': '${DateFormat('dd-MMM-yyyy HH:mm').format(firstTimestamp)} to ${DateFormat('dd-MMM-yyyy HH:mm').format(lastTimestamp)}' };
    metadata.forEach((key, value) { sheet.getRangeByIndex(currentRow, 1)..setText(key)..cellStyle = infoStyle; sheet.getRangeByName('B$currentRow:E$currentRow')..merge()..setText(value); currentRow++; });
    currentRow++;
    headerLines.where((l) => l.isNotEmpty).forEach((line) { sheet.getRangeByIndex(currentRow++, 1)..setText(line)..cellStyle = userHeaderStyle; });
    currentRow++;
    final List<String> headers = ['S.No', 'Date', 'Time', ...channelNames.values.map((name) => '$name (${channelSetupData[name]?.unit ?? ""})')];
    if (mode == 'Table' || mode == 'Combined') {
      final dataTableStartRow = currentRow;
      sheet.importList(headers, dataTableStartRow, 1, false);
      sheet.getRangeByIndex(dataTableStartRow, 1, dataTableStartRow, headers.length).cellStyle = tableHeaderStyle;
      sheet.setRowHeightInPixels(dataTableStartRow, 25);
      for (var i = 0; i < tableData.length; i++) { _writeExcelDataRow(sheet, i, dataTableStartRow, tableData[i], channelNames, channelSetupData, numberStyles); }
      currentRow += tableData.length + 2;
    }
    if ((mode == 'Graph' || mode == 'Combined') && graphImage != null) {
      sheet.pictures.addStream(currentRow, 2, graphImage);
      currentRow += 25;
      currentRow++;
    }
    footerLines.where((l) => l.isNotEmpty).forEach((line) { sheet.getRangeByIndex(currentRow++, 1)..setText(line)..cellStyle = userFooterStyle; });
    for (int i = 1; i <= headers.length; i++) { sheet.autoFitColumn(i); }
    await _saveFile(context, workbook.saveAsStream(), fileName, 'xlsx');
    workbook.dispose();
  }

  static Future<void> _exportToPdf({
    required BuildContext context,
    required String mode,
    required List<Map<String, dynamic>> tableData,
    required Uint8List? graphImage,
    required String fileName,
    required String companyName,
    required String companyAddress,
    required Uint8List? logoBytes,
    required Map<int, String> channelNames,
    required DateTime firstTimestamp,
    required DateTime lastTimestamp,
    required Map<String, Channel> channelSetupData,
    required List<String> headerLines,
    required List<String> footerLines,
  }) async {
    final PdfDocument document = PdfDocument();
    document.pageSettings.orientation = PdfPageOrientation.landscape;
    document.pageSettings.margins.all = 30;

    final Size pageSize = document.pageSettings.size;
    final Rect headerBounds = Rect.fromLTWH(0, 0, pageSize.width, 120);
    document.template.top = _buildPdfHeader(
      headerBounds,
      companyName,
      companyAddress,
      logoBytes,
      fileName,
      firstTimestamp,
      lastTimestamp,
      headerLines,
    );

    final Rect footerBounds = Rect.fromLTWH(0, 0, pageSize.width, 80);
    document.template.bottom = _buildPdfFooter(footerBounds, footerLines);

    PdfPage? currentPage;
    if (mode == 'Table' || mode == 'Combined') {
      currentPage = document.pages.add();
      final PdfGrid grid = _createPdfGrid(tableData, channelNames, channelSetupData);
      grid.draw(
        page: currentPage,
        bounds: Rect.fromLTWH(0, 0, currentPage.getClientSize().width, currentPage.getClientSize().height),
      );
    }
    if ((mode == 'Graph' || mode == 'Combined') && graphImage != null) {
      currentPage = document.pages.add();
      final PdfBitmap pdfImage = PdfBitmap(graphImage);
      final Size clientSize = currentPage.getClientSize();
      final double imageAspectRatio = pdfImage.width / pdfImage.height;
      double finalWidth = clientSize.width;
      double finalHeight = finalWidth / imageAspectRatio;
      if (finalHeight > clientSize.height) {
        finalHeight = clientSize.height;
        finalWidth = finalHeight * imageAspectRatio;
      }
      final double x = (clientSize.width - finalWidth) / 2;
      final double y = (clientSize.height - finalHeight) / 2;
      final Rect imageBounds = Rect.fromLTWH(x, y, finalWidth, finalHeight);
      currentPage.graphics.drawImage(pdfImage, imageBounds);
    }

    final List<int> bytes = await document.save();
    document.dispose();
    await _saveFile(context, bytes, fileName, 'pdf');
  }

  static Future<void> _exportTableToCsv({ required BuildContext context, required List<Map<String, dynamic>> tableData, required String fileName, required Map<int, String> channelNames, required Map<String, Channel> channelSetupData}) async {
    final StringBuffer csvBuffer = StringBuffer();
    final headers = ['S.No', 'Date', 'Time', ...channelNames.values.map((name) => '$name (${channelSetupData[name]?.unit ?? ""})')];
    csvBuffer.writeln(headers.map((h) => '"$h"').join(','));
    for (final row in tableData) {
      final List<String> rowValues = [(row['SNo'] ?? '').toString(), _parseDate(row['AbsDate']), row['AbsTime'] as String? ?? ''];
      for (int channelId in channelNames.keys) { rowValues.add(row['AbsPer$channelId']?.toString() ?? ''); }
      csvBuffer.writeln(rowValues.map((v) => '"$v"').join(','));
    }
    await _saveFile(context, utf8.encode(csvBuffer.toString()), fileName, 'csv');
  }

  static Future<void> _exportToHtmlForWord({ required BuildContext context, required String mode, required List<Map<String, dynamic>> tableData, required Uint8List? graphImage, required String fileName, required String companyName, required String companyAddress, required Uint8List? logoBytes, required Map<int, String> channelNames, required DateTime firstTimestamp, required DateTime lastTimestamp, required Map<String, Channel> channelSetupData, required List<String> headerLines, required List<String> footerLines}) async {
    final StringBuffer html = StringBuffer();
    html.writeln(_getHtmlBoilerplate());
    html.writeln('<body><div class="header">');
    if (logoBytes != null) { html.writeln('<img src="data:image/png;base64,${base64Encode(logoBytes)}" alt="Company Logo" style="height: ${LOGO_HEIGHT}px; max-width: ${LOGO_WIDTH}px; width: auto;"/>'); }
    html.writeln('<h1>$companyName</h1><h3>$companyAddress</h3></div><hr><p><b>File Name:</b> $fileName</p><p><b>Report Period:</b> ${DateFormat('dd-MMM-yyyy HH:mm').format(firstTimestamp)} to ${DateFormat('dd-MMM-yyyy HH:mm').format(lastTimestamp)}</p>');
    headerLines.where((l) => l.isNotEmpty).forEach((line) => html.writeln('<p><b>$line</b></p>'));
    if (mode == 'Table' || mode == 'Combined') {
      html.writeln('<h2>Data Table</h2><table>');
      final headers = ['S.No', 'Date', 'Time', ...channelNames.values.map((name) => '$name (${channelSetupData[name]?.unit ?? ""})')];
      html.writeln('<thead><tr>${headers.map((h) => '<th>$h</th>').join()}</tr></thead><tbody>');
      for (final row in tableData) {
        html.writeln('<tr><td>${row['SNo'] ?? ''}</td><td>${_parseDate(row['AbsDate'])}</td><td>${row['AbsTime'] as String? ?? ''}</td>');
        for (int channelId in channelNames.keys) { html.writeln('<td>${(row['AbsPer$channelId'] as num?)?.toStringAsFixed(channelSetupData[channelNames[channelId]]?.decimalPlaces ?? 2) ?? '-'}</td>'); }
        html.writeln('</tr>');
      }
      html.writeln('</tbody></table>');
    }
    if ((mode == 'Graph' || mode == 'Combined') && graphImage != null) {
      html.writeln('<h2>Graph</h2><img src="data:image/png;base64,${base64Encode(graphImage)}" alt="Report Graph" style="max-width: 100%; height: auto;"/>');
    }
    footerLines.where((l) => l.isNotEmpty).forEach((line) => html.writeln('<p><i>$line</i></p>'));
    html.writeln('</body></html>');
    await _saveFile(context, utf8.encode(html.toString()), fileName, 'doc');
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
    String? directoryPath = await FilePicker.platform.getDirectoryPath(dialogTitle: 'Select Folder to Save Report');
    if (directoryPath == null) return;

    File file = File(p.join(directoryPath, '$cleanFileName.$extension'));
    int i = 1;
    while (await file.exists()) {
      file = File(p.join(directoryPath, '$cleanFileName($i).$extension'));
      i++;
    }

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

  /// ---- [FULLY CORRECTED] PDF Header Builder ----
  static PdfPageTemplateElement _buildPdfHeader(
      Rect bounds,
      String companyName,
      String companyAddress,
      Uint8List? logoBytes,
      String fileName,
      DateTime firstTimestamp,
      DateTime lastTimestamp,
      List<String> headerLines,
      ) {
    final PdfPageTemplateElement headerElement = PdfPageTemplateElement(bounds);
    final PdfFont titleFont = PdfStandardFont(PdfFontFamily.helvetica, 14, style: PdfFontStyle.bold);
    final PdfFont bodyFont = PdfStandardFont(PdfFontFamily.helvetica, 10);
    final PdfFont smallBoldFont = PdfStandardFont(PdfFontFamily.helvetica, 10, style: PdfFontStyle.bold);
    final PdfPen linePen = PdfPen(PdfColor(128, 128, 128), width: 0.7);
    final DateFormat timestampFormat = DateFormat('dd-MMM-yyyy HH:mm');

    double currentY = 0;
    double leftPaneX = 0;

    // --- Section 1: Logo and Company Info ---
    if (logoBytes != null) {
      final PdfBitmap logo = PdfBitmap(logoBytes);
      final double logoHeight = 45.0;
      final double logoWidth = logo.width * (logoHeight / logo.height);
      headerElement.graphics.drawImage(
        logo,
        Rect.fromLTWH(0, currentY, logoWidth, logoHeight),
      );
      leftPaneX = logoWidth + 15;
    }

    final double textWidth = bounds.width - leftPaneX;
    // FIX: Use PdfStringFormat with drawString, not PdfTextElement
    final PdfStringFormat companyNameFormat = PdfStringFormat(
        alignment: leftPaneX > 0 ? PdfTextAlignment.left : PdfTextAlignment.center,
        lineAlignment: PdfVerticalAlignment.middle
    );

    // FIX: Draw directly to graphics, not via PdfTextElement.draw
    headerElement.graphics.drawString(
        companyName,
        titleFont,
        brush: PdfBrushes.black,
        bounds: Rect.fromLTWH(leftPaneX, currentY, textWidth, 25),
        format: companyNameFormat
    );
    currentY += 25;

    headerElement.graphics.drawString(
        companyAddress,
        bodyFont,
        brush: PdfBrushes.darkGray,
        bounds: Rect.fromLTWH(leftPaneX, currentY, textWidth, 20),
        format: companyNameFormat
    );

    currentY = 55;

    // --- Section 2: Separator Line ---
    headerElement.graphics.drawLine(linePen, Offset(0, currentY), Offset(bounds.width, currentY));
    currentY += 10;

    // --- Section 3: Report Details ---
    headerElement.graphics.drawString(
      'Report for file: $fileName',
      smallBoldFont,
      bounds: Rect.fromLTWH(0, currentY, bounds.width, 15),
    );

    final PdfStringFormat rightAlign = PdfStringFormat(alignment: PdfTextAlignment.right);
    headerElement.graphics.drawString(
      'Period: ${timestampFormat.format(firstTimestamp)} to ${timestampFormat.format(lastTimestamp)}',
      bodyFont,
      bounds: Rect.fromLTWH(0, currentY, bounds.width, 15),
      format: rightAlign,
    );
    currentY += 18;

    // --- Section 4: Custom Header Lines ---
    for (String line in headerLines.where((l) => l.isNotEmpty)) {
      headerElement.graphics.drawString(
        line,
        smallBoldFont,
        bounds: Rect.fromLTWH(0, currentY, bounds.width, 15),
      );
      currentY += 15;
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

  static PdfGrid _createPdfGrid(
      List<Map<String, dynamic>> tableData,
      Map<int, String> channelNames,
      Map<String, Channel> channelSetupData,
      ) {
    final PdfGrid grid = PdfGrid();
    final DateFormat dateFormat = DateFormat('yyyy-MM-dd');
    final DateFormat timeFormat = DateFormat('HH:mm:ss');
    final List<int> sortedChannelKeys = channelNames.keys.toList()..sort();

    grid.columns.add(count: 3 + sortedChannelKeys.length);
    final PdfGridRow header = grid.headers.add(1)[0];
    header.style = PdfGridCellStyle(
      backgroundBrush: PdfBrushes.lightSlateGray,
      textBrush: PdfBrushes.white,
      font: PdfStandardFont(PdfFontFamily.helvetica, 8, style: PdfFontStyle.bold),
    );

    header.cells[0].value = 'S.No';
    header.cells[1].value = 'Date (YYYY-MM-DD)';
    header.cells[2].value = 'Time (HH:mm:ss)';

    for (int i = 0; i < sortedChannelKeys.length; i++) {
      final int channelId = sortedChannelKeys[i];
      final String name = channelNames[channelId]!;
      final String unit = channelSetupData[name]?.unit ?? "";
      header.cells[i + 3].value = '$name ($unit)';
    }

    for (final Map<String, dynamic> rowData in tableData) {
      final PdfGridRow row = grid.rows.add();
      row.cells[0].value = (rowData['SNo'] ?? '').toString();

      final String? dateStr = rowData['AbsDate'];
      final String? timeStr = rowData['AbsTime'];
      if (dateStr != null && timeStr != null && dateStr.isNotEmpty && timeStr.isNotEmpty) {
        try {
          final DateTime timestamp = DateTime.parse('$dateStr $timeStr');
          row.cells[1].value = dateFormat.format(timestamp);
          row.cells[2].value = timeFormat.format(timestamp);
        } catch (e) {
          row.cells[1].value = dateStr;
          row.cells[2].value = timeStr;
        }
      } else {
        row.cells[1].value = dateStr ?? '';
        row.cells[2].value = timeStr ?? '';
      }

      for (int i = 0; i < sortedChannelKeys.length; i++) {
        final int channelId = sortedChannelKeys[i];
        final String channelName = channelNames[channelId]!;
        final num? value = rowData['AbsPer$channelId'] as num?;
        final int decimalPlaces = channelSetupData[channelName]?.decimalPlaces ?? 2;
        row.cells[i + 3].value = value?.toStringAsFixed(decimalPlaces) ?? '-';
      }
    }

    grid.applyBuiltInStyle(PdfGridBuiltInStyle.listTable4Accent5);
    grid.style.font = PdfStandardFont(PdfFontFamily.helvetica, 7);

    // FIX: Removed the erroneous call to grid.columns[i].autoFit().
    // The built-in style will handle column widths automatically.

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
    sheet.getRangeByIndex(excelRowIndex, 1)..setNumber((rowData['SNo'] ?? (rowIndex + 1)).toDouble())..cellStyle = baseStyle;
    sheet.getRangeByIndex(excelRowIndex, 2)..setText(_parseDate(rowData['AbsDate']))..cellStyle = baseStyle;
    sheet.getRangeByIndex(excelRowIndex, 3)..setText(rowData['AbsTime'] as String? ?? '')..cellStyle = baseStyle;
    int colIndex = 4;
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