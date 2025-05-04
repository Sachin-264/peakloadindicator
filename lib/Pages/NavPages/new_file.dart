import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:peakloadindicator/Pages/setup/setup_api.dart'; // Import ApiService
import 'package:peakloadindicator/constants/message_utils.dart';
import '../../constants/colors.dart';
import '../../constants/loader_widget.dart';
import 'channel.dart';

class NewTestPage extends StatefulWidget {
  final Function(List<dynamic>) onSubmit; // Callback to update HomePage

  const NewTestPage({super.key, required this.onSubmit});

  @override
  State<NewTestPage> createState() => _NewTestPageState();
}

class _NewTestPageState extends State<NewTestPage> {
  final Set<int> _selectedRowIndices = {};
  List<Channel> _channels = [];
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _fetchChannels();
  }

  Future<void> _fetchChannels() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final data = await ApiService.fetchChannels();
      print('Fetched channels: $data');
      setState(() {
        _channels = data.map((item) => Channel.fromJson(item)).toList();
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _errorMessage = 'Error: $e';
      });
      print('Error fetching channels: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.background,
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Select Channel',
              textAlign: TextAlign.center,
              style: GoogleFonts.roboto(
                fontSize: 32,
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 32),
            Expanded(
              child: Card(
                elevation: 8.0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12.0),
                ),
                color: AppColors.cardBackground,
                child: _isLoading
                    ? const LoaderWidget()
                    : _errorMessage != null
                    ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        _errorMessage!,
                        style: GoogleFonts.roboto(
                          fontSize: 16,
                          color: AppColors.errorText,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: _fetchChannels,
                        child: Text(
                          'Retry',
                          style: GoogleFonts.roboto(fontSize: 16),
                        ),
                      ),
                    ],
                  ),
                )
                    : SingleChildScrollView(
                  scrollDirection: Axis.vertical,
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        minWidth: MediaQuery.of(context).size.width - 48,
                      ),
                      child: DataTable(
                        columnSpacing: 40.0,
                        dataRowHeight: 60.0,
                        headingRowHeight: 64.0,
                        headingRowColor: MaterialStateProperty.all(
                          AppColors.headerBackground,
                        ),
                        headingTextStyle: GoogleFonts.roboto(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                          color: AppColors.textPrimary,
                        ),
                        dataTextStyle: GoogleFonts.roboto(
                          fontSize: 14,
                          color: AppColors.textPrimary,
                        ),
                        decoration: const BoxDecoration(
                          borderRadius: BorderRadius.vertical(
                            top: Radius.circular(12.0),
                          ),
                        ),
                        columns: const [
                          DataColumn(label: Text('SNo')),
                          DataColumn(label: Text('Channel Name')),
                          DataColumn(label: Text('Unit')),
                        ],
                        rows: _channels.isEmpty
                            ? [
                          const DataRow(cells: [
                            DataCell(Text('')),
                            DataCell(Text('No data available')),
                            DataCell(Text('')),
                          ])
                        ]
                            : List<DataRow>.generate(
                          _channels.length,
                              (index) => DataRow(
                            selected: _selectedRowIndices.contains(index),
                            onSelectChanged: (selected) {
                              setState(() {
                                if (selected == true) {
                                  _selectedRowIndices.add(index);
                                  print('Selected row: $index');
                                } else {
                                  _selectedRowIndices.remove(index);
                                  print('Deselected row: $index');
                                }
                              });
                            },
                            color: MaterialStateProperty.resolveWith<Color?>(
                                  (Set<MaterialState> states) {
                                if (states.contains(MaterialState.selected)) {
                                  return AppColors.selectedRow;
                                }
                                return null;
                              },
                            ),
                            cells: [
                              DataCell(Text('${_channels[index].recNo}')),
                              DataCell(Text(_channels[index].channelName)),
                              DataCell(Text(_channels[index].unit)),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 32),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                ElevatedButton(
                  onPressed: () {
                    setState(() {
                      _selectedRowIndices.clear();
                      print('Reset button pressed, cleared selections');
                    });
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.resetButton,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    elevation: 2,
                  ),
                  child: Text(
                    'Reset',
                    style: GoogleFonts.roboto(fontSize: 16),
                  ),
                ),
                const SizedBox(width: 16),
                ElevatedButton(
                  onPressed: () {
                    if (_selectedRowIndices.isNotEmpty) {
                      final selectedChannels = _selectedRowIndices.map((index) => _channels[index]).toList();
                      widget.onSubmit(selectedChannels); // Call callback to update HomePage
                    } else {
                      MessageUtils.showMessage(context, 'Please select at least one channel');
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.submitButton,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    elevation: 2,
                  ),
                  child: Text(
                    'Submit',
                    style: GoogleFonts.roboto(fontSize: 16),
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