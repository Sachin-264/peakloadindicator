import 'dart:io';
import 'dart:typed_data';
import 'package:pdf/widgets.dart' as pw;
import 'package:excel/excel.dart';
import 'package:path_provider/path_provider.dart';
import 'package:open_file/open_file.dart';
import 'package:csv/csv.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class ExportUtils {
  static Future<void> exportBasedOnMode({
    required BuildContext context,
    required String mode,
    required List<dynamic> tableData,
    required String fileName,
    Uint8List? graphImage,
  }) async {
    switch (mode) {
      case 'Table':
        showExportDialog(context, tableData, fileName, null, includeGraph: false);
        break;
      case 'Graph':
        showExportDialog(context, [], fileName, graphImage, includeTable: false);
        break;
      case 'Combined':
        showExportDialog(context, tableData, fileName, graphImage);
        break;
      default:
        print('Unknown mode: $mode');
    }
  }

  static Future<void> exportToPDF({
    required List<dynamic> tableData,
    required String fileName,
    Uint8List? graphImage,
    bool includeTable = true,
    bool includeGraph = true,
  }) async {
    final pdf = pw.Document();

    List<pw.Widget> content = [];

    if (includeTable && tableData.isNotEmpty) {
      // Dynamically determine headers based on available channels
      List<String> headers = ['No', 'Time', 'Date'];
      Map<int, String> channelNames = {};
      for (var data in tableData) {
        for (int i = 1; i <= 50; i++) {
          if (data['AbsPer$i'] != null && !channelNames.containsKey(i)) {
            channelNames[i] = 'Channel $i'; // Placeholder; ideally fetch from Test2
          }
        }
      }
      headers.addAll(channelNames.values);

      // Prepare data rows
      List<List<String>> dataRows = tableData.map((data) {
        String displayDate = 'N/A';
        try {
          if (data['AbsDate'] is String) {
            displayDate = data['AbsDate'].toString().substring(0, 10);
          } else if (data['AbsDate'] is Map) {
            displayDate = data['AbsDate']['date']?.substring(0, 10) ?? 'N/A';
          }
        } catch (e) {
          print('Error parsing AbsDate: $e');
        }

        List<String> row = [
          data['SNo'].toString(),
          data['AbsTime'].toString(),
          displayDate,
        ];
        for (int i = 1; i <= 50; i++) {
          if (channelNames.containsKey(i)) {
            row.add(data['AbsPer$i']?.toString() ?? '-');
          }
        }
        return row;
      }).toList();

      content.add(
        pw.Table.fromTextArray(
          headers: headers,
          data: dataRows,
          cellAlignment: pw.Alignment.center,
          headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
          cellStyle: const pw.TextStyle(),
        ),
      );
    }

    if (includeGraph && graphImage != null) {
      if (content.isNotEmpty) content.add(pw.SizedBox(height: 20));
      content.add(pw.Image(pw.MemoryImage(graphImage), width: 500));
    }

    pdf.addPage(pw.MultiPage(build: (context) => content));

    final directory = await getApplicationDocumentsDirectory();
    final file = File('${directory.path}/$fileName.pdf');
    await file.writeAsBytes(await pdf.save());
    await OpenFile.open(file.path);
  }

  static Future<void> exportToExcel({
    required List<dynamic> tableData,
    required String fileName,
    Uint8List? graphImage,
    bool includeTable = true,
    bool includeGraph = true,
  }) async {
    var excel = Excel.createExcel();
    Sheet sheet = excel['Sheet1'];

    if (includeTable && tableData.isNotEmpty) {
      // Dynamically determine headers
      List<String> headers = ['No', 'Time', 'Date'];
      Map<int, String> channelNames = {};
      for (var data in tableData) {
        for (int i = 1; i <= 50; i++) {
          if (data['AbsPer$i'] != null && !channelNames.containsKey(i)) {
            channelNames[i] = 'Channel $i';
          }
        }
      }
      headers.addAll(channelNames.values);

      sheet.appendRow(headers.map((h) => TextCellValue(h)).toList());

      for (var data in tableData) {
        String displayDate = 'N/A';
        try {
          if (data['AbsDate'] is String) {
            displayDate = data['AbsDate'].toString().substring(0, 10);
          } else if (data['AbsDate'] is Map) {
            displayDate = data['AbsDate']['date']?.substring(0, 10) ?? 'N/A';
          }
        } catch (e) {
          print('Error parsing AbsDate: $e');
        }

        List<TextCellValue> row = [
          TextCellValue(data['SNo'].toString()),
          TextCellValue(data['AbsTime'].toString()),
          TextCellValue(displayDate),
        ];
        for (int i = 1; i <= 50; i++) {
          if (channelNames.containsKey(i)) {
            row.add(TextCellValue(data['AbsPer$i']?.toString() ?? '-'));
          }
        }
        sheet.appendRow(row);
      }
    }

    final directory = await getApplicationDocumentsDirectory();
    final file = File('${directory.path}/$fileName.xlsx');
    await file.writeAsBytes(excel.encode()!);
    await OpenFile.open(file.path);
  }

  static Future<void> exportToCSV({
    required List<dynamic> tableData,
    required String fileName,
    Uint8List? graphImage,
    bool includeTable = true,
    bool includeGraph = true,
  }) async {
    if (includeTable && tableData.isNotEmpty) {
      // Dynamically determine headers
      List<String> headers = ['No', 'Time', 'Date'];
      Map<int, String> channelNames = {};
      for (var data in tableData) {
        for (int i = 1; i <= 50; i++) {
          if (data['AbsPer$i'] != null && !channelNames.containsKey(i)) {
            channelNames[i] = 'Channel $i';
          }
        }
      }
      headers.addAll(channelNames.values);

      List<List<String>> csvRows = [
        headers,
        for (var data in tableData)
          [
            data['SNo'].toString(),
            data['AbsTime'].toString(),
            (data['AbsDate'] is String
                ? data['AbsDate'].toString().substring(0, 10)
                : data['AbsDate']?['date']?.substring(0, 10) ?? 'N/A'),
            ...List.generate(
              channelNames.length,
                  (i) => data['AbsPer${i + 1}']?.toString() ?? '-',
            ),
          ],
      ];

      String csv = const ListToCsvConverter().convert(csvRows);
      final directory = await getApplicationDocumentsDirectory();
      final file = File('${directory.path}/$fileName.csv');
      await file.writeAsString(csv);
      await OpenFile.open(file.path);
    }
  }

  static void showExportDialog(
      BuildContext context,
      List<dynamic> tableData,
      String fileName,
      Uint8List? graphImage, {
        bool includeTable = true,
        bool includeGraph = true,
      }) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        backgroundColor: Colors.white,
        elevation: 4,
        contentPadding: const EdgeInsets.all(16),
        title: Row(
          children: [
            Icon(Icons.file_download, color: Colors.blue.shade700, size: 24),
            const SizedBox(width: 8),
            Text(
              'Export Options',
              style: GoogleFonts.roboto(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
            ),
          ],
        ),
        content: Container(
          width: 320,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(8),
            boxShadow: [
              BoxShadow(
                color: Colors.grey.withOpacity(0.1),
                spreadRadius: 1,
                blurRadius: 5,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (includeTable || includeGraph) ...[
                  _buildExportOption(
                    context: context,
                    title: 'PDF',
                    icon: Icons.picture_as_pdf,
                    color: Colors.red.shade600,
                    onTap: () async {
                      Navigator.pop(context);
                      await exportToPDF(
                        tableData: tableData,
                        fileName: fileName,
                        graphImage: graphImage,
                        includeTable: includeTable,
                        includeGraph: includeGraph,
                      );
                    },
                  ),
                  const SizedBox(height: 8),
                ],
                if (includeTable) ...[
                  _buildExportOption(
                    context: context,
                    title: 'Excel',
                    icon: Icons.table_chart,
                    color: Colors.green.shade600,
                    onTap: () async {
                      Navigator.pop(context);
                      await exportToExcel(
                        tableData: tableData,
                        fileName: fileName,
                        graphImage: graphImage,
                        includeTable: includeTable,
                        includeGraph: includeGraph,
                      );
                    },
                  ),
                  const SizedBox(height: 8),
                  _buildExportOption(
                    context: context,
                    title: 'CSV',
                    icon: Icons.description,
                    color: Colors.blue.shade600,
                    onTap: () async {
                      Navigator.pop(context);
                      await exportToCSV(
                        tableData: tableData,
                        fileName: fileName,
                        graphImage: graphImage,
                        includeTable: includeTable,
                        includeGraph: includeGraph,
                      );
                    },
                  ),
                ],
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              'Cancel',
              style: GoogleFonts.roboto(
                color: Colors.grey[600],
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
    required Color color,
    required VoidCallback onTap,
  }) {
    return ElevatedButton(
      onPressed: onTap,
      style: ElevatedButton.styleFrom(
        foregroundColor: color.withOpacity(0.1),
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        elevation: 1,
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
        shadowColor: Colors.grey.withOpacity(0.2),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(width: 12),
          Text(
            title,
            style: GoogleFonts.roboto(
              color: Colors.black87,
              fontSize: 16,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}