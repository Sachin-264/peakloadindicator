import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:peakloadindicator/constants/loader_widget.dart';
import 'dart:convert';
import '../../constants/global.dart';
import 'open_file.dart';

class FileSelectionDialog extends StatefulWidget {
  final TextEditingController controller;
  final VoidCallback? onOpenPressed;

  const FileSelectionDialog({
    super.key,
    required this.controller,
    this.onOpenPressed,
  });

  @override
  State<FileSelectionDialog> createState() => _FileSelectionDialogState();
}

class _FileSelectionDialogState extends State<FileSelectionDialog> {
  Future<List<Map<String, dynamic>>> _fetchFilesFromApi() async {
    print('FileSelectionDialog _fetchFilesFromApi: Fetching file list');
    final url = Uri.parse('http://localhost/Table/getData.php?type=Test');
    final response = await http.get(url);
    print('FileSelectionDialog _fetchFilesFromApi: Response status = ${response.statusCode}');
    if (response.statusCode == 200) {
      final jsonData = jsonDecode(response.body);
      print('FileSelectionDialog _fetchFilesFromApi: Data fetched, length = ${jsonData['data'].length}');
      return List<Map<String, dynamic>>.from(jsonData['data']);
    } else {
      throw Exception('Failed to load data from API');
    }
  }

  void _showBrowseDialog(BuildContext context) {
    print('FileSelectionDialog _showBrowseDialog: Opening browse dialog');
    showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        return Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          backgroundColor: Colors.grey[100],
          child: Container(
            width: 600,
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Select a File',
                  style: GoogleFonts.poppins(fontSize: 28, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                FutureBuilder<List<Map<String, dynamic>>>(
                  future: _fetchFilesFromApi(),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Padding(
                        padding: EdgeInsets.all(20),
                        child: LoaderWidget(),
                      );
                    } else if (snapshot.hasError) {
                      print('FileSelectionDialog FutureBuilder: Error = ${snapshot.error}');
                      return Text('Error: ${snapshot.error}', style: GoogleFonts.poppins());
                    } else if (snapshot.hasData) {
                      final files = snapshot.data!;
                      return SizedBox(
                        height: 300,
                        width: double.infinity,
                        child: SingleChildScrollView(
                          child: DataTable(
                            columns: [
                              DataColumn(label: Text('SNo', style: GoogleFonts.poppins(fontWeight: FontWeight.bold))),
                              DataColumn(label: Text('FName', style: GoogleFonts.poppins(fontWeight: FontWeight.bold))),
                              DataColumn(label: Text('Operator Name', style: GoogleFonts.poppins(fontWeight: FontWeight.bold))),
                            ],
                            rows: files.map((file) {
                              return DataRow(
                                cells: [
                                  DataCell(Text(file['RecNo'].toString(), style: GoogleFonts.poppins())),
                                  DataCell(Text(file['FName'], style: GoogleFonts.poppins())),
                                  DataCell(Text(file['OperatorName'], style: GoogleFonts.poppins())),
                                ],
                                onSelectChanged: (selected) async {
                                  if (selected ?? false) {
                                    print('FileSelectionDialog DataRow: Selected file = ${file['FName']}, RecNo = ${file['RecNo']}');
                                    try {
                                      setState(() {
                                        widget.controller.text = file['FName'];
                                        // Ensure Global.selectedRecNo is initialized as ValueNotifier<int?>
                                        if (Global.selectedRecNo == null) {
                                          print('FileSelectionDialog DataRow: Initializing Global.selectedRecNo');
                                          Global.selectedRecNo = ValueNotifier<int?>(null);
                                        }
                                        // Update the value, ensuring type safety
                                        Global.selectedRecNo!.value = file['RecNo'] as int?;
                                        print('FileSelectionDialog DataRow: Set Global.selectedRecNo.value = ${Global.selectedRecNo!.value}');
                                        Global.selectedFileName.value = file['FName'];
                                        Global.operatorName.value = file['OperatorName'];

                                        // Update scanning rate fields
                                        Global.scanningRate.value = file['ScanningRate'] as int?;
                                        Global.scanningRateHH.value = file['ScanningRateHH'] as int?;
                                        Global.scanningRateMM.value = file['ScanningRateMM'] as int?;
                                        Global.scanningRateSS.value = file['ScanningRateSS'] as int?;

                                        // Update test duration fields
                                        Global.testDurationDD.value = file['TestDurationDD'] as int?;
                                        Global.testDurationHH.value = file['TestDurationHH'] as int?;
                                        Global.testDurationMM.value = file['TestDurationMM'] as int?;
                                        Global.testDurationSS.value = file['TestDurationSS'] as int?;

                                        // Update graph visible area
                                        print('FileSelectionDialog DataRow: testduration = ${Global.testDurationSS.value}');
                                        Global.graphVisibleArea.value = file['GraphVisibleArea']?.toString();

                                        print('FileSelectionDialog DataRow: Updated Global variables successfully');
                                      });
                                      Navigator.of(dialogContext).pop();
                                    } catch (e) {
                                      print('FileSelectionDialog DataRow: Error = $e');
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(content: Text('Error updating file details: $e')),
                                      );
                                    }
                                  }
                                },
                              );
                            }).toList(),
                          ),
                        ),
                      );
                    } else {
                      return Text('No data available', style: GoogleFonts.poppins());
                    }
                  },
                ),
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.of(dialogContext).pop(),
                      child: Text('Cancel', style: GoogleFonts.poppins(color: Colors.red[700])),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    print('FileSelectionDialog build: Building dialog');
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      backgroundColor: Colors.grey[100],
      child: Container(
        width: 450,
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Open File',
              style: GoogleFonts.poppins(
                fontSize: 28,
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Select a file to open or enter the file path.',
              style: GoogleFonts.poppins(fontSize: 16, color: Colors.black54),
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: widget.controller,
                    style: GoogleFonts.poppins(color: Colors.black87, fontSize: 14),
                    decoration: InputDecoration(
                      hintText: 'File path...',
                      filled: true,
                      fillColor: Colors.white,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(4),
                        borderSide: BorderSide(color: Colors.grey[400]!),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(4),
                        borderSide: BorderSide(color: Colors.grey[400]!),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(4),
                        borderSide: const BorderSide(color: Colors.blue, width: 2),
                      ),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                ElevatedButton.icon(
                  onPressed: () => _showBrowseDialog(context),
                  icon: const Icon(Icons.folder_open, color: Colors.white),
                  label: Text('Browse', style: GoogleFonts.poppins()),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue[600],
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(
                    'Cancel',
                    style: GoogleFonts.poppins(color: Colors.red[700]),
                  ),
                ),
                const SizedBox(width: 12),
                ElevatedButton(
                  onPressed: widget.onOpenPressed ??
                          () {
                        print('FileSelectionDialog Open button: File name = ${widget.controller.text}, RecNo = ${Global.selectedRecNo?.value}');
                        if (widget.controller.text.isNotEmpty) {
                          // Ensure selectedRecNo is initialized if null
                          if (Global.selectedRecNo == null) {
                            print('FileSelectionDialog Open button: Initializing Global.selectedRecNo');
                            Global.selectedRecNo = ValueNotifier<int?>(null);
                          }
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (context) => OpenFilePage(
                                fileName: widget.controller.text,
                              ),
                            ),
                          );
                        }
                      },
                  child: Text('Open', style: GoogleFonts.poppins()),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green[600],
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}