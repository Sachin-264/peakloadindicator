import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../constants/global.dart';
import '../../constants/theme.dart';

class HelpPage extends StatefulWidget {
  const HelpPage({super.key});

  @override
  State<HelpPage> createState() => _HelpPageState();
}

class _HelpPageState extends State<HelpPage> with TickerProviderStateMixin {
  final _searchController = TextEditingController();
  String _searchQuery = '';
  bool _isSidebarExpanded = true;
  late AnimationController _animationController;
  late Animation<double> _scaleAnimation;
  int _selectedSectionIndex = 0;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    );
    _scaleAnimation = Tween<double>(begin: 0.95, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeOutCubic),
    );
    _animationController.forward();
    _searchController.addListener(() {
      setState(() {
        _searchQuery = _searchController.text.toLowerCase().trim();
        _animationController.forward(from: 0);
      });
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: Global.isDarkMode,
      builder: (context, isDarkMode, _) {
        return Scaffold(
          backgroundColor: ThemeColors.getColor('appBackground', isDarkMode),
          body: SafeArea(
            child: Column(
              children: [
                _buildHeader(isDarkMode),
                Expanded(
                  child: Row(
                    children: [
                      _buildSidebar(isDarkMode),
                      Expanded(
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.all(20.0),
                          child: ScaleTransition(
                            scale: _scaleAnimation,
                            child: _buildContent(isDarkMode),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                _buildFooter(isDarkMode),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildHeader(bool isDarkMode) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 20.0),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isDarkMode
              ? [
            ThemeColors.getColor('submitButton', isDarkMode).withOpacity(0.85),
            ThemeColors.getColor('submitButton', isDarkMode).withOpacity(0.55),
          ]
              : [
            const Color(0xFFB3E5FC), // Light blue
            const Color(0xFF4FC3F7), // Slightly darker blue
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isDarkMode ? 0.15 : 0.3),
            blurRadius: isDarkMode ? 12 : 16,
            spreadRadius: isDarkMode ? 3 : 5,
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    LucideIcons.cpu,
                    color: ThemeColors.getColor('dialogText', isDarkMode),
                    size: 36,
                  ),
                  const SizedBox(width: 12),
                  Text(
                    'Countron Smart Logger Help',
                    style: GoogleFonts.montserrat(
                      fontSize: 26,
                      fontWeight: FontWeight.w700,
                      color: ThemeColors.getColor('dialogText', isDarkMode),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                'Your complete guide to mastering data logging',
                style: GoogleFonts.montserrat(
                  fontSize: 16,
                  fontWeight: FontWeight.w400,
                  color: ThemeColors.getColor('dialogSubText', isDarkMode),
                ),
              ),
            ],
          ),
          SizedBox(
            width: 400,
            child: TextField(
              controller: _searchController,
              style: GoogleFonts.montserrat(
                fontSize: 16,
                color: ThemeColors.getColor('dialogText', isDarkMode),
              ),
              decoration: InputDecoration(
                hintText: 'Search help topics...',
                hintStyle: GoogleFonts.montserrat(
                  fontSize: 16,
                  color: ThemeColors.getColor('dialogSubText', isDarkMode).withOpacity(0.7),
                ),
                prefixIcon: Icon(
                  LucideIcons.search,
                  color: ThemeColors.getColor('cardIcon', isDarkMode),
                  size: 24,
                ),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                  icon: Icon(
                    LucideIcons.x,
                    color: ThemeColors.getColor('cardIcon', isDarkMode),
                    size: 24,
                  ),
                  onPressed: () {
                    _searchController.clear();
                  },
                )
                    : null,
                filled: true,
                fillColor: ThemeColors.getColor('textFieldBackground', isDarkMode),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(
                    color: ThemeColors.getColor('submitButton', isDarkMode),
                    width: 2,
                  ),
                ),
                contentPadding: const EdgeInsets.symmetric(vertical: 14.0, horizontal: 16.0),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSidebar(bool isDarkMode) {
    final sections = [
      {'title': 'Overview', 'icon': LucideIcons.info},
      {'title': 'Main Window', 'icon': LucideIcons.home},
      {'title': 'New Test', 'icon': LucideIcons.plusCircle},
      {'title': 'Open Test', 'icon': LucideIcons.folderOpen},
      {'title': 'Mode', 'icon': LucideIcons.layoutGrid},
      {'title': 'Setup', 'icon': LucideIcons.settings},
      {'title': 'Backup & Restore', 'icon': LucideIcons.databaseBackup},
      {'title': 'Log', 'icon': LucideIcons.scrollText},
    ];

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      width: _isSidebarExpanded ? 260 : 80,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            ThemeColors.getColor('sidebarBackground', isDarkMode),
            ThemeColors.getColor('sidebarBackground', isDarkMode).withOpacity(0.9),
          ],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
        border: Border(
          right: BorderSide(
            color: ThemeColors.getColor('sidebarBorder', isDarkMode),
            width: 2,
          ),
        ),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(20.0),
            child: IconButton(
              icon: Icon(
                _isSidebarExpanded ? LucideIcons.chevronsLeft : LucideIcons.chevronsRight,
                color: isDarkMode ? ThemeColors.getColor('sidebarIcon', isDarkMode) : const Color(0xFF0288D1),
                size: 26,
              ),
              onPressed: () => setState(() {
                _isSidebarExpanded = !_isSidebarExpanded;
                _animationController.forward(from: 0);
              }),
              tooltip: _isSidebarExpanded ? 'Collapse Sidebar' : 'Expand Sidebar',
            ),
          ),
          Divider(
            color: ThemeColors.getColor('cardBorder', isDarkMode),
            thickness: 1,
            indent: 16,
            endIndent: 16,
          ),
          Expanded(
            child: ListView.builder(
              itemCount: sections.length,
              itemBuilder: (context, index) {
                final section = sections[index];
                final isSelected = _selectedSectionIndex == index;
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 6.0),
                  child: ListTile(
                    leading: Icon(
                      section['icon'] as IconData,
                      color: isSelected
                          ? (isDarkMode ? ThemeColors.getColor('sidebarIconSelected', isDarkMode) : const Color(0xFF0277BD))
                          : (isDarkMode ? ThemeColors.getColor('sidebarIcon', isDarkMode) : const Color(0xFF0288D1)),
                      size: 24,
                    ),
                    title: _isSidebarExpanded
                        ? Text(
                      section['title'] as String,
                      style: GoogleFonts.montserrat(
                        fontSize: 16,
                        fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                        color: isDarkMode ? ThemeColors.getColor('sidebarText', isDarkMode) : const Color(0xFF0288D1),
                      ),
                    )
                        : null,
                    onTap: () {
                      setState(() {
                        _selectedSectionIndex = index;
                        _searchController.clear();
                      });
                    },
                    tileColor: isSelected ? ThemeColors.getColor('submitButton', isDarkMode).withOpacity(0.15) : null,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 10.0),
                    hoverColor: ThemeColors.getColor('dropdownHover', isDarkMode).withOpacity(0.25),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContent(bool isDarkMode) {
    final sections = [
      {
        'title': 'Overview',
        'icon': LucideIcons.info,
        'brief': 'Discover the core features of Countron Smart Logger for efficient data logging, analysis, and reporting.',
        'details': [
          Text(
            'Countron Smart Data Logger is a comprehensive tool designed for real-time, time-based data acquisition. It allows you to monitor and analyze data through configurable tables and graphs, set alarms, and export professional reports to multiple formats.',
            style: GoogleFonts.montserrat(fontSize: 15, color: ThemeColors.getColor('dialogSubText', isDarkMode)),
          ),
          const SizedBox(height: 16),
          _buildSubSection(title: 'Key Capabilities', description: 'From live monitoring to advanced reporting, learn what you can achieve.', isDarkMode: isDarkMode),
          _buildOrderedList([
            'Live Data Monitoring: View incoming data in tables, graphs, or a combined view.',
            'Flexible Test Configuration: Select specific channels and set parameters for each test run.',
            'Advanced Reporting: Generate detailed reports in Word, PDF, or Excel with custom headers and footers.',
            'System Configuration: Customize COM ports, user authentication, and company details for reports.',
            'Data Integrity: Use the backup and restore functionality to safeguard your valuable data.',
            'Customizable Interface: Switch between a light and dark theme to suit your preference.',
          ], isDarkMode),
        ],
      },
      {
        'title': 'Main Window',
        'icon': LucideIcons.home,
        'brief': 'The central dashboard for initiating scans, viewing system status, and accessing recent activity.',
        'details': [
          _buildSubSection(title: 'Quick Actions', description: 'Get started right from the main screen.', isDarkMode: isDarkMode, icon: LucideIcons.playCircle),
          _buildOrderedList(['Start Scan: Begin a new test.', 'Open File: Load a previously saved scan.', 'Mode: Choose your preferred data view (Table, Graph, Combined).'], isDarkMode),
          const SizedBox(height: 16),
          _buildSubSection(title: 'System Status', description: 'At-a-glance information about the logger\'s state.', isDarkMode: isDarkMode, icon: LucideIcons.gauge),
          _buildOrderedList(['Active Channels: See which channels are currently being monitored.', 'Scan Times: View the configured automatic start and stop times.', 'Uptime: Monitor how long the software has been running.'], isDarkMode),
          const SizedBox(height: 16),
          _buildSubSection(title: 'Recent Log', description: 'A box displaying the most recent log entries for quick review.', isDarkMode: isDarkMode, icon: LucideIcons.history),
          const SizedBox(height: 16),
          _buildSubSection(title: 'System Info', description: 'Find details about the application version and current theme.', isDarkMode: isDarkMode, icon: LucideIcons.info),
        ],
      },
      {
        'title': 'New Test',
        'icon': LucideIcons.plusCircle,
        'brief': 'Configure and run a new data logging session with live data visualization.',
        'details': [
          _buildSubSection(title: 'Initiating a Scan', description: 'Follow these steps to start logging data.', isDarkMode: isDarkMode),
          _buildOrderedList(['Select Channels: Choose which channels to include in the scan.', 'Start Scan: A new screen will appear with live data feeds.', 'Control Buttons: Use "Start", "Stop", and "Fast" buttons for quick control.'], isDarkMode),
          const SizedBox(height: 16),
          _buildSubSection(title: 'Data Management', description: 'Manage your test data directly from the scan window.', isDarkMode: isDarkMode),
          _buildOrderedList(['Open: Open a saved file.', 'Save: Save the current session data.', 'Clear Data: Erase the current data to start fresh.', 'Exit: Close the test window.'], isDarkMode),
          const SizedBox(height: 16),
          _buildSubSection(title: 'Visualization Tools', description: 'Customize how you view your data.', isDarkMode: isDarkMode),
          _buildOrderedList(['Combined Mode: View a table on the left and a graph on the right.', 'Channel Selection: Toggle channels on or off in the view.', 'Add Window: Open multiple graph windows for comparison.', 'Peak Value: Instantly identify the highest value in a dataset.', 'Data Toggle: Switch data views easily.', 'Graph Legends: Click on a channel in the graph legend to change its color.'], isDarkMode),
        ],
      },
      {
        'title': 'Open Test',
        'icon': LucideIcons.folderOpen,
        'brief': 'View, analyze, and export reports from previously saved scan files.',
        'details': [
          _buildSubSection(title: 'Viewing Saved Scans', description: 'Load a file to see its complete data record in a table and graph format.', isDarkMode: isDarkMode),
          const SizedBox(height: 16),
          _buildSubSection(title: 'Exporting Reports', description: 'Generate professional reports with customized content.', isDarkMode: isDarkMode, icon: LucideIcons.fileOutput),
          _buildOrderedList([
            'Click the Export button.',
            'Select a Date and Time range for the report data.',
            'Customize the report with up to four lines for a header and footer.',
            'Choose your desired file format: Word (.doc), PDF (.pdf), or Excel (.xls).',
          ], isDarkMode),
        ],
      },
      {
        'title': 'Mode',
        'icon': LucideIcons.layoutGrid,
        'brief': 'Switch between different data visualization modes to best suit your analysis needs.',
        'details': [
          Text('A dialog box allows you to select your preferred viewing mode. This setting is applied to both live and saved data.', style: GoogleFonts.montserrat(fontSize: 15, color: ThemeColors.getColor('dialogSubText', isDarkMode))),
          const SizedBox(height: 16),
          _buildSubSection(title: 'Table Mode', description: 'Displays data in a structured, tabular format.', isDarkMode: isDarkMode),
          _buildSubSection(title: 'Graph Mode', description: 'Visualizes data as a time-series plot.', isDarkMode: isDarkMode),
          _buildSubSection(title: 'Combined Mode', description: 'Shows both the table and graph side-by-side for comprehensive analysis.', isDarkMode: isDarkMode),
        ],
      },
      {
        'title': 'Setup',
        'icon': LucideIcons.settings,
        'brief': 'Configure system-wide settings for hardware, security, and reporting.',
        'details': [
          _buildSubSection(title: 'Main Settings', description: 'The primary setup screen allows you to configure core hardware and automation functions.', isDarkMode: isDarkMode),
          _buildOrderedList([
            'COM Port Settings: Establish the connection with your data acquisition hardware by setting the Port and Baudrate.',
            'Auto-Start Configuration: Schedule the logger to start and stop scanning automatically at specific times.',
          ], isDarkMode),
          const SizedBox(height: 16),
          _buildSubSection(
            title: 'Advanced Configuration',
            description: 'On the Setup screen, click "Configure Authentication" to open a new window with the following settings:',
            isDarkMode: isDarkMode,
            icon: LucideIcons.shieldCheck,
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.only(left: 26.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildSubSection(title: '1. Authentication', description: 'Enable this option to require a username and password when the application starts.', isDarkMode: isDarkMode),
                _buildSubSection(title: '2. Company Details', description: 'Enter your company\'s Name, Address, and upload a Logo. These details will be automatically included in all exported reports.', isDarkMode: isDarkMode),
                _buildSubSection(title: '3. General Settings', description: 'Enable Auto-Save to automatically save reports at set intervals during scanning.', isDarkMode: isDarkMode),
              ],
            ),
          ),
        ],
      },
      {
        'title': 'Backup & Restore',
        'icon': LucideIcons.databaseBackup,
        'brief': 'Safeguard and recover your application settings and data with the backup and restore utility.',
        'details': [
          Text('Use the Backup and Restore dialog to manage your data\'s safety. It is recommended to perform regular backups to prevent data loss.', style: GoogleFonts.montserrat(fontSize: 15, color: ThemeColors.getColor('dialogSubText', isDarkMode))),
          const SizedBox(height: 16),
          _buildSubSection(title: 'Backup', description: 'Create a secure copy of your entire dataset and configuration files.', isDarkMode: isDarkMode),
          const SizedBox(height: 16),
          _buildSubSection(title: 'Restore', description: 'Recover data from a previous backup file. This will overwrite current settings and data.', isDarkMode: isDarkMode),
        ],
      },
      {
        'title': 'Log',
        'icon': LucideIcons.scrollText,
        'brief': 'Review a detailed log of system events, user actions, and potential errors.',
        'details': [
          Text('The system log is a crucial tool for troubleshooting and auditing. It provides a chronological record of all significant activities within the application.', style: GoogleFonts.montserrat(fontSize: 15, color: ThemeColors.getColor('dialogSubText', isDarkMode))),
          const SizedBox(height: 16),
          _buildSubSection(title: 'What is Logged?', description: 'Events captured include:', isDarkMode: isDarkMode),
          _buildOrderedList(['User logins (successful and failed).', 'Test start/stop events.', 'System errors or warnings.', 'Configuration changes.'], isDarkMode),
        ],
      },
    ];

    final filteredSections = sections.asMap().entries.where((entry) {
      final section = entry.value;
      final title = section['title']!.toString().toLowerCase();
      final brief = section['brief']!.toString().toLowerCase();
      final details = section['details'].toString().toLowerCase();
      return _searchQuery.isEmpty || title.contains(_searchQuery) || brief.contains(_searchQuery) || details.contains(_searchQuery);
    }).toList();

    if (filteredSections.isEmpty && _searchQuery.isNotEmpty) {
      return _buildNoResults(isDarkMode, sections);
    }

    final displaySections = _searchQuery.isEmpty
        ? [sections[_selectedSectionIndex]]
        : filteredSections.map((entry) => entry.value).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_searchQuery.isEmpty) ...[
          _buildWelcomeCard(isDarkMode),
          const SizedBox(height: 20),
        ],
        ...displaySections.map((section) => _buildSectionCard(
          isDarkMode: isDarkMode,
          title: section['title']! as String,
          brief: section['brief']! as String,
          icon: section['icon']! as IconData,
          details: section['details']! as List<Widget>,
        )),
        const SizedBox(height: 40),
        Center(
          child: Text(
            'Made with ♡ by Sachin Mishra',
            style: GoogleFonts.montserrat(
              fontSize: 11,
              fontWeight: FontWeight.w300,
              color: ThemeColors.getColor('dialogSubText', isDarkMode).withOpacity(0.4),
            ),
          ),
        )
      ],
    );
  }

  Widget _buildNoResults(bool isDarkMode, List<Map<String, Object>> sections) {
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'No results found for "$_searchQuery".',
            style: GoogleFonts.montserrat(
              fontSize: 20,
              fontWeight: FontWeight.w500,
              color: ThemeColors.getColor('dialogText', isDarkMode),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'Suggested Topics',
            style: GoogleFonts.montserrat(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: ThemeColors.getColor('dialogText', isDarkMode),
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12.0,
            runSpacing: 12.0,
            children: sections.asMap().entries.map((entry) {
              return ActionChip(
                label: Text(
                  entry.value['title']! as String,
                  style: GoogleFonts.montserrat(
                    fontSize: 15,
                    color: ThemeColors.getColor('dialogText', isDarkMode),
                  ),
                ),
                avatar: Icon(
                  entry.value['icon']! as IconData,
                  size: 20,
                  color: ThemeColors.getColor('cardIcon', isDarkMode),
                ),
                backgroundColor: ThemeColors.getColor('cardBackground', isDarkMode),
                side: BorderSide(
                  color: ThemeColors.getColor('cardBorder', isDarkMode),
                  width: 1,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                onPressed: () {
                  setState(() {
                    _selectedSectionIndex = entry.key;
                    _searchController.clear();
                  });
                },
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildWelcomeCard(bool isDarkMode) {
    return Container(
      padding: const EdgeInsets.all(24.0),
      margin: const EdgeInsets.only(bottom: 20.0),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            ThemeColors.getColor('submitButton', isDarkMode).withOpacity(0.2),
            ThemeColors.getColor('submitButton', isDarkMode).withOpacity(0.1),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: ThemeColors.getColor('cardBorder', isDarkMode),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isDarkMode ? 0.15 : 0.2),
            blurRadius: 10,
            spreadRadius: 2,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Welcome to the Help Center',
            style: GoogleFonts.montserrat(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: ThemeColors.getColor('dialogText', isDarkMode),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Use the sidebar to explore topics or search for specific help. Everything you need to know is right here.',
            style: GoogleFonts.montserrat(
              fontSize: 16,
              color: ThemeColors.getColor('dialogSubText', isDarkMode),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionCard({
    required bool isDarkMode,
    required String title,
    required String brief,
    required IconData icon,
    required List<Widget> details,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 20.0),
      decoration: BoxDecoration(
        color: ThemeColors.getColor('cardBackground', isDarkMode),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: ThemeColors.getColor('cardBorder', isDarkMode),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.15),
            blurRadius: 8,
            spreadRadius: 2,
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            initiallyExpanded: _searchQuery.isNotEmpty,
            leading: Icon(
              icon,
              color: ThemeColors.getColor('cardIcon', isDarkMode),
              size: 28,
            ),
            title: Text(
              title,
              style: GoogleFonts.montserrat(
                fontSize: 20,
                fontWeight: FontWeight.w600,
                color: ThemeColors.getColor('dialogText', isDarkMode),
              ),
            ),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 8.0),
              child: Text(
                brief,
                style: GoogleFonts.montserrat(
                  fontSize: 16,
                  color: ThemeColors.getColor('dialogSubText', isDarkMode),
                ),
              ),
            ),
            backgroundColor: ThemeColors.getColor('cardBackground', isDarkMode),
            collapsedBackgroundColor: ThemeColors.getColor('cardBackground', isDarkMode),
            iconColor: ThemeColors.getColor('submitButton', isDarkMode),
            collapsedIconColor: ThemeColors.getColor('cardIcon', isDarkMode),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Divider(
                        color: ThemeColors.getColor('cardBorder', isDarkMode),
                        thickness: 1,
                        height: 20),
                    ...details
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSubSection({
    required String title,
    required String description,
    required bool isDarkMode,
    IconData? icon,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if(icon != null) ...[
                Icon(icon, size: 18, color: ThemeColors.getColor('dialogText', isDarkMode)),
                const SizedBox(width: 8),
              ],
              Text(
                title,
                style: GoogleFonts.montserrat(
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                  color: ThemeColors.getColor('dialogText', isDarkMode),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Padding(
            padding: EdgeInsets.only(left: icon != null ? 26 : 0),
            child: Text(
              description,
              style: GoogleFonts.montserrat(
                fontSize: 15,
                color: ThemeColors.getColor('dialogSubText', isDarkMode),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOrderedList(List<String> items, bool isDarkMode) {
    return Padding(
      padding: const EdgeInsets.only(left: 26, top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: items.asMap().entries.map((entry) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 12.0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${entry.key + 1}. ',
                  style: GoogleFonts.montserrat(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: ThemeColors.getColor('submitButton', isDarkMode),
                  ),
                ),
                Expanded(
                  child: Text(
                    entry.value,
                    style: GoogleFonts.montserrat(
                      fontSize: 15,
                      height: 1.4,
                      color: ThemeColors.getColor('dialogSubText', isDarkMode),
                    ),
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildFooter(bool isDarkMode) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
      decoration: BoxDecoration(
          color: ThemeColors.getColor('cardBackground', isDarkMode),
          border: Border(top: BorderSide(color: ThemeColors.getColor('sidebarBorder', isDarkMode), width: 1.5))
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            'Countron Smart Logger v1.0.0',
            style: GoogleFonts.montserrat(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: ThemeColors.getColor('dialogSubText', isDarkMode),
            ),
          ),
          Text(
            'Powered by Moneyshine Infocom Pvt Ltd',
            style: GoogleFonts.montserrat(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: ThemeColors.getColor('dialogSubText', isDarkMode).withOpacity(0.8),
            ),
          ),
          Row(
            children: [
              TextButton.icon(
                onPressed: () {},
                icon: Icon(
                  LucideIcons.mail,
                  size: 20,
                  color: ThemeColors.getColor('submitButton', isDarkMode),
                ),
                label: Text(
                  'Contact Support',
                  style: GoogleFonts.montserrat(
                    fontSize: 14,
                    color: ThemeColors.getColor('submitButton', isDarkMode),
                  ),
                ),
              ),

            ],
          ),
        ],
      ),
    );
  }
}