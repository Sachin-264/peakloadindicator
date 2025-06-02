import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../constants/database_manager.dart';
import '../../constants/global.dart';
import '../../constants/loader_widget.dart';
import '../../constants/message_utils.dart';
import '../../constants/theme.dart';
import 'channel.dart';

class NewTestPage extends StatefulWidget {
  final Function(List<dynamic>) onSubmit;

  const NewTestPage({super.key, required this.onSubmit});

  @override
  State<NewTestPage> createState() => _NewTestPageState();
}

class _NewTestPageState extends State<NewTestPage> with SingleTickerProviderStateMixin {
  final Set<int> _selectedRowIndices = {};
  List<Channel> _channels = [];
  bool _isLoading = true;
  String? _errorMessage;
  static const Color _accentColor = Colors.blueGrey; // Matches HomePage
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeInOut),
    );
    _scaleAnimation = Tween<double>(begin: 0.9, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeOut),
    );
    _fetchChannels();
    _animationController.forward();
  }

  Future<void> _fetchChannels() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final database = await DatabaseManager().database;

      final List<Map<String, dynamic>> data = await database.query('ChannelSetup');
      print('Fetched channels from ChannelSetup: $data');

      setState(() {
        _channels = data.map((item) => Channel.fromJson(item)).toList();
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _errorMessage = 'Error fetching channels: $e';
      });
      print('Error fetching channels: $e');
    }
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: Global.isDarkMode,
      builder: (context, isDarkMode, child) {
        return Scaffold(
          body: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  ThemeColors.getColor('appBackground', isDarkMode),
                  ThemeColors.getColor('appBackgroundSecondary', isDarkMode),
                ],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
            ),
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: FadeTransition(
                  opacity: _fadeAnimation,
                  child: ScaleTransition(
                    scale: _scaleAnimation,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Header Card
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: ThemeColors.getColor('cardBackground', isDarkMode),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: ThemeColors.getColor('cardBorder', isDarkMode),
                              width: 1.5,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(isDarkMode ? 0.1 : 0.2),
                                blurRadius: 10,
                                spreadRadius: 2,
                              ),
                            ],
                          ),
                          child: Text(
                            'Select Channel',
                            textAlign: TextAlign.center,
                            style: GoogleFonts.montserrat(
                              fontSize: 24,
                              fontWeight: FontWeight.w700,
                              color: ThemeColors.getColor('dialogText', isDarkMode),
                            ),
                          ),
                        ),
                        const SizedBox(height: 24),
                        // Table Container
                        Expanded(
                          child: Container(
                            decoration: BoxDecoration(
                              color: ThemeColors.getColor('cardBackground', isDarkMode),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: ThemeColors.getColor('cardBorder', isDarkMode),
                                width: 1.5,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(isDarkMode ? 0.1 : 0.2),
                                  blurRadius: 10,
                                  spreadRadius: 2,
                                ),
                              ],
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: _isLoading
                                  ? Center(
                                child: LoaderWidget(
                                  color: _accentColor,
                                  size: 60.0,
                                  text: 'Loading Channels...',
                                ),
                              )
                                  : _errorMessage != null
                                  ? Center(
                                child: Container(
                                  padding: const EdgeInsets.all(24),
                                  decoration: BoxDecoration(
                                    color: ThemeColors.getColor('dialogBackground', isDarkMode),
                                    borderRadius: BorderRadius.circular(12),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withOpacity(0.1),
                                        blurRadius: 10,
                                        spreadRadius: 2,
                                      ),
                                    ],
                                  ),
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons.error_outline,
                                        color: ThemeColors.getColor('errorText', isDarkMode),
                                        size: 48,
                                      ),
                                      const SizedBox(height: 16),
                                      Text(
                                        _errorMessage!,
                                        style: GoogleFonts.montserrat(
                                          fontSize: 16,
                                          color: ThemeColors.getColor('dialogText', isDarkMode),
                                          fontWeight: FontWeight.w500,
                                        ),
                                        textAlign: TextAlign.center,
                                      ),
                                      const SizedBox(height: 24),
                                      _buildButton(
                                        text: 'Retry',
                                        icon: LucideIcons.refreshCw,
                                        gradient: ThemeColors.getDialogButtonGradient(isDarkMode, 'backup'),
                                        onTap: _fetchChannels,
                                        isProminent: true,
                                      ),
                                    ],
                                  ),
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
                                      columnSpacing: 32.0,
                                      dataRowHeight: 56.0,
                                      headingRowHeight: 60.0,
                                      headingRowColor: MaterialStateProperty.all(
                                        isDarkMode
                                            ? ThemeColors.getColor('titleBarGradientStart', isDarkMode)
                                            : Colors.blue.shade100, // Blue shade for day mode
                                      ),
                                      headingTextStyle: GoogleFonts.montserrat(
                                        fontWeight: FontWeight.w600,
                                        fontSize: 14,
                                        color: ThemeColors.getColor('dialogText', isDarkMode),
                                      ),
                                      dataTextStyle: GoogleFonts.montserrat(
                                        fontSize: 14,
                                        color: ThemeColors.getColor('dialogText', isDarkMode),
                                      ),
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      columns: const [
                                        DataColumn(label: Text('SNo')),
                                        DataColumn(label: Text('Channel Name')),
                                        DataColumn(label: Text('Unit')),
                                      ],
                                      rows: _channels.isEmpty
                                          ? [
                                        DataRow(
                                          cells: [
                                            const DataCell(Text('')),
                                            DataCell(
                                              Text(
                                                'No data available',
                                                style: GoogleFonts.montserrat(
                                                  fontStyle: FontStyle.italic,
                                                  color: ThemeColors.getColor('dialogSubText', isDarkMode),
                                                ),
                                              ),
                                            ),
                                            const DataCell(Text('')),
                                          ],
                                        ),
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
                                                return ThemeColors.getColor('submitButton', isDarkMode).withOpacity(0.2);
                                              }
                                              if (index.isEven) {
                                                return ThemeColors.getColor('cardBackground', isDarkMode).withOpacity(0.8);
                                              }
                                              return ThemeColors.getColor('cardBackground', isDarkMode);
                                            },
                                          ),
                                          cells: [
                                            DataCell(Text('${_channels[index].recNo.toInt()}')),
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
                        ),
                        const SizedBox(height: 24),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            _buildButton(
                              text: 'Reset',
                              icon: LucideIcons.x,
                              gradient: LinearGradient(
                                colors: [Colors.grey[600]!, Colors.grey[400]!],
                              ),
                              onTap: () {
                                setState(() {
                                  _selectedRowIndices.clear();
                                  print('Reset button pressed, cleared selections');
                                });
                              },
                            ),
                            const SizedBox(width: 16),
                            _buildButton(
                              text: 'Submit',
                              icon: LucideIcons.check,
                              gradient: ThemeColors.getDialogButtonGradient(isDarkMode, 'backup'),
                              onTap: () {
                                if (_selectedRowIndices.isNotEmpty) {
                                  final selectedChannels = _selectedRowIndices.map((index) => _channels[index]).toList();
                                  widget.onSubmit(selectedChannels);
                                } else {
                                  MessageUtils.showMessage(
                                    context,
                                    'Please select at least one channel',
                                    isError: true,
                                  );
                                }
                              },
                              isProminent: true,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildButton({
    required String text,
    required IconData icon,
    required LinearGradient gradient,
    required VoidCallback onTap,
    bool isProminent = false,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: EdgeInsets.symmetric(
            horizontal: isProminent ? 24 : 16,
            vertical: isProminent ? 14 : 10,
          ),
          decoration: BoxDecoration(
            gradient: gradient,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(isProminent ? 0.3 : 0.2),
                blurRadius: isProminent ? 8 : 6,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                color: Colors.white,
                size: isProminent ? 22 : 18,
              ),
              const SizedBox(width: 8),
              Text(
                text,
                style: GoogleFonts.montserrat(
                  fontSize: isProminent ? 16 : 14,
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}