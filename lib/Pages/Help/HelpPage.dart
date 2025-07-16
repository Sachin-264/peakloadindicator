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
'Your guide to mastering data logging',
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
setState(() => _searchQuery = '');
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
{
'title': 'Overview',
'icon': LucideIcons.info,
'brief': 'Discover the core features of Countron Smart Logger for efficient data logging, including tables, graphs, and report exports.'
},
{
'title': 'Main Window',
'icon': LucideIcons.home,
'brief': 'Navigate the main interface to start tests, view data, configure settings, and manage backups.'
},
{
'title': 'Open Test',
'icon': LucideIcons.folderOpen,
'brief': 'Manage saved test files, generate reports, or return to the main window.'
},
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
_searchQuery = '';
_animationController.forward(from: 0);
});
},
tileColor: isSelected
? ThemeColors.getColor('submitButton', isDarkMode).withOpacity(0.15)
    : null,
shape: RoundedRectangleBorder(
borderRadius: BorderRadius.circular(12),
),
contentPadding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 10.0),
hoverColor: ThemeColors.getColor('dropdownHover', isDarkMode).withOpacity(0.25),
trailing: isSelected && _isSidebarExpanded
? Icon(
LucideIcons.chevronRight,
size: 20,
color: isDarkMode ? ThemeColors.getColor('sidebarIconSelected', isDarkMode) : const Color(0xFF0277BD),
)
    : null,
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
'brief': 'Discover the core features of Countron Smart Logger for efficient data logging, including tables, graphs, and report exports.',
'details': [
Text(
'Countron Smart Data Logger is a powerful tool for time-based data logging. Monitor and analyze data through tables or graphs, customize settings like logging rates and alarms, and export reports to Word documents.',
style: GoogleFonts.montserrat(
fontSize: 15,
color: ThemeColors.getColor('dialogSubText', isDarkMode),
),
),
const SizedBox(height: 16),
Text(
'Getting Started',
style: GoogleFonts.montserrat(
fontSize: 18,
fontWeight: FontWeight.w600,
color: ThemeColors.getColor('dialogText', isDarkMode),
),
),
const SizedBox(height: 8),
_buildOrderedList(
[
'Connect the 9-pin Serial Cable from a COM port to the Data Acquisition Unit.',
'Power on the system.',
'Launch Countron Smart Logger from the All Programs menu.',
'Create a new test in the New Test window.',
'Open a test file in the Open Test window to view or generate reports.',
],
isDarkMode,
),
const SizedBox(height: 12),
Text(
'Tip: Set your screen resolution to 800x600 and date format to DD/MM/YYYY for the best experience.',
style: GoogleFonts.montserrat(
fontSize: 13,
color: ThemeColors.getColor('errorText', isDarkMode),
fontStyle: FontStyle.italic,
),
),
],
},
{
'title': 'Main Window',
'icon': LucideIcons.home,
'brief': 'Navigate the main interface to start tests, view data, configure settings, and manage backups.',
'details': [
_buildSubSection(
title: 'New Test',
description: 'Start a new data logging session by selecting channels and setting parameters.',
isDarkMode: isDarkMode,
),
_buildSubSection(
title: 'Open File',
description: 'Access saved scans by selecting a scan file.',
isDarkMode: isDarkMode,
),
_buildSubSection(
title: 'Table Mode',
description: 'View data in a tabular format with columns for serial number, time, and values.',
isDarkMode: isDarkMode,
),
_buildSubSection(
title: 'Graph Mode',
description: 'Visualize data as a plot with blue circle markers.',
isDarkMode: isDarkMode,
),
_buildSubSection(
title: 'Combined Mode',
description: 'Display data in both table and graph formats.',
isDarkMode: isDarkMode,
),
_buildSubSection(
title: 'Setup',
description: 'Configure COM port and channel alarms, then save changes.',
isDarkMode: isDarkMode,
),
_buildSubSection(
title: 'Data Backup',
description: 'Manage and restore data backups.',
isDarkMode: isDarkMode,
),
_buildSubSection(
title: 'Exit',
description: 'Close the application.',
isDarkMode: isDarkMode,
),
_buildSubSection(
title: 'Help',
description: 'View this help guide.',
isDarkMode: isDarkMode,
),
],
},
{
'title': 'Open Test',
'icon': LucideIcons.folderOpen,
'brief': 'Manage saved test files, generate reports, or return to the main window.',
'details': [
_buildSubSection(
title: 'Delete Scan',
description: 'Remove the currently loaded scan file.',
isDarkMode: isDarkMode,
),
_buildSubSection(
title: 'Test Report',
description: 'Create a report with channel details, headers, and footers. print using the print button.',
isDarkMode: isDarkMode,
),
_buildSubSection(
title: 'Exit',
description: 'Return to the main window.',
isDarkMode: isDarkMode,
),
],
},
];

final filteredSections = sections.asMap().entries.where((entry) {
final section = entry.value;
final title = section['title']!.toString().toLowerCase();
final brief = section['brief']!.toString().toLowerCase();
return _searchQuery.isEmpty || title.contains(_searchQuery) || brief.contains(_searchQuery);
}).toList();

if (filteredSections.isEmpty) {
return Padding(
padding: const EdgeInsets.all(24.0),
child: Column(
crossAxisAlignment: CrossAxisAlignment.start,
children: [
Text(
_searchQuery.isEmpty
? 'Select a topic from the sidebar to get started.'
    : 'No results found for "$_searchQuery".',
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
_searchQuery = '';
_animationController.forward(from: 0);
});
},
);
}).toList(),
),
],
),
);
}

final displaySections = _searchQuery.isEmpty
? [sections[_selectedSectionIndex]]
    : filteredSections.map((entry) => entry.value).toList();

return Column(
crossAxisAlignment: CrossAxisAlignment.start,
children: [
_buildWelcomeCard(isDarkMode),
const SizedBox(height: 20),
...displaySections.map((section) => _buildSectionCard(
isDarkMode: isDarkMode,
title: section['title']! as String,
brief: section['brief']! as String,
icon: section['icon']! as IconData,
details: section['details']! as List<Widget>,
)),
],
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
'Welcome to Help',
style: GoogleFonts.montserrat(
fontSize: 22,
fontWeight: FontWeight.w700,
color: ThemeColors.getColor('dialogText', isDarkMode),
),
),
const SizedBox(height: 12),
Text(
'Get started with Countron Smart Logger. Use the sidebar to explore topics or search for specific help.',
style: GoogleFonts.montserrat(
fontSize: 16,
color: ThemeColors.getColor('dialogSubText', isDarkMode),
),
),
const SizedBox(height: 16),
ElevatedButton.icon(
onPressed: () {
ScaffoldMessenger.of(context).showSnackBar(
SnackBar(
content: Text(
'Quick Start Guide coming soon!',
style: GoogleFonts.montserrat(color: Colors.white),
),
backgroundColor: ThemeColors.getColor('submitButton', isDarkMode),
),
);
},
icon: Icon(
LucideIcons.rocket,
size: 20,
color: ThemeColors.getColor('dialogText', isDarkMode),
),
label: Text(
'Quick Start',
style: GoogleFonts.montserrat(
fontSize: 15,
fontWeight: FontWeight.w600,
color: ThemeColors.getColor('dialogText', isDarkMode),
),
),
style: ElevatedButton.styleFrom(
backgroundColor: ThemeColors.getColor('submitButton', isDarkMode),
foregroundColor: ThemeColors.getColor('dialogText', isDarkMode),
shape: RoundedRectangleBorder(
borderRadius: BorderRadius.circular(10),
),
padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 12.0),
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
bool isHovered = false;
return StatefulBuilder(
builder: (context, setState) {
return MouseRegion(
onEnter: (_) => setState(() => isHovered = true),
onExit: (_) => setState(() => isHovered = false),
child: Container(
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
color: Colors.black.withOpacity(isHovered ? 0.25 : 0.15),
blurRadius: isHovered ? 12 : 8,
spreadRadius: isHovered ? 4 : 2,
),
],
),
child: ClipRRect(
borderRadius: BorderRadius.circular(16),
child: Theme(
data: Theme.of(context).copyWith(
dividerColor: Colors.transparent,
),
child: ExpansionTile(
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
padding: const EdgeInsets.all(20.0),
child: Column(
crossAxisAlignment: CrossAxisAlignment.start,
children: [
...details,
const SizedBox(height: 16),
Divider(
color: ThemeColors.getColor('cardBorder', isDarkMode),
thickness: 1,
),
const SizedBox(height: 16),
Text(
'Related Actions',
style: GoogleFonts.montserrat(
fontSize: 16,
fontWeight: FontWeight.w600,
color: ThemeColors.getColor('dialogText', isDarkMode),
),
),
const SizedBox(height: 12),
Wrap(
spacing: 12.0,
runSpacing: 8.0,
children: [
ActionChip(
label: Text(
'Watch Tutorial',
style: GoogleFonts.montserrat(
fontSize: 14,
color: isDarkMode ? Colors.black: Colors.black,
),
),
avatar: Icon(
LucideIcons.video,
size: 18,
color: ThemeColors.getColor('cardIcon', isDarkMode),
),
backgroundColor: ThemeColors.getColor('submitButton', isDarkMode).withOpacity(0.15),
onPressed: () {
ScaffoldMessenger.of(context).showSnackBar(
SnackBar(
content: Text(
'Tutorial video coming soon!',
style: GoogleFonts.montserrat(color: Colors.white),
),
backgroundColor: ThemeColors.getColor('submitButton', isDarkMode),
),
);
},
),
ActionChip(
label: Text(
'Contact Support',
style: GoogleFonts.montserrat(
fontSize: 14,
color: isDarkMode ? Colors.black : Colors.black,
),
),
avatar: Icon(
LucideIcons.mail,
size: 18,
color: ThemeColors.getColor('cardIcon', isDarkMode),
),
backgroundColor: ThemeColors.getColor('submitButton', isDarkMode).withOpacity(0.15),
onPressed: () {
ScaffoldMessenger.of(context).showSnackBar(
SnackBar(
content: Text(
'Contact support feature coming soon!',
style: GoogleFonts.montserrat(color: Colors.white),
),
backgroundColor: ThemeColors.getColor('submitButton', isDarkMode),
),
);
},
),
],
),
],
),
),
],
),
),
),
),
);
},
);
}

Widget _buildSubSection({
required String title,
required String description,
required bool isDarkMode,
}) {
return ListTile(
contentPadding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
title: Text(
title,
style: GoogleFonts.montserrat(
fontSize: 16,
fontWeight: FontWeight.w500,
color: ThemeColors.getColor('dialogText', isDarkMode),
),
),
subtitle: Text(
description,
style: GoogleFonts.montserrat(
fontSize: 14,
color: ThemeColors.getColor('dialogSubText', isDarkMode),
),
),
dense: true,
);
}

Widget _buildOrderedList(List<String> items, bool isDarkMode) {
return Column(
crossAxisAlignment: CrossAxisAlignment.start,
children: items.asMap().entries.map((entry) {
return Padding(
padding: const EdgeInsets.only(bottom: 12.0, left: 8.0, right: 8.0),
child: Row(
crossAxisAlignment: CrossAxisAlignment.start,
children: [
Text(
'${entry.key + 1}. ',
style: GoogleFonts.montserrat(
fontSize: 14,
fontWeight: FontWeight.w600,
color: ThemeColors.getColor('dialogText', isDarkMode),
),
),
Expanded(
child: Text(
entry.value,
style: GoogleFonts.montserrat(
fontSize: 14,
color: ThemeColors.getColor('dialogSubText', isDarkMode),
),
),
),
],
),
);
}).toList(),
);
}

Widget _buildFooter(bool isDarkMode) {
return Container(
padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
decoration: BoxDecoration(
gradient: LinearGradient(
colors: [
ThemeColors.getColor('cardBackground', isDarkMode).withOpacity(0.9),
ThemeColors.getColor('cardBackground', isDarkMode).withOpacity(0.7),
],
begin: Alignment.topCenter,
end: Alignment.bottomCenter,
),
),
child: Row(
mainAxisAlignment: MainAxisAlignment.spaceBetween,
children: [
Text(
'Countron Smart Logger v1.0.2',
style: GoogleFonts.montserrat(
fontSize: 14,
fontWeight: FontWeight.w500,
color: ThemeColors.getColor('dialogSubText', isDarkMode),
),
),
Row(
children: [
TextButton.icon(
onPressed: () {
ScaffoldMessenger.of(context).showSnackBar(
SnackBar(
content: Text(
'Contact support feature coming soon!',
style: GoogleFonts.montserrat(
fontSize: 14,
color: Colors.white,
),
),
backgroundColor: ThemeColors.getColor('submitButton', isDarkMode),
),
);
},
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
const SizedBox(width: 16),
TextButton.icon(
onPressed: () {
ScaffoldMessenger.of(context).showSnackBar(
SnackBar(
content: Text(
'Visit our community forums!',
style: GoogleFonts.montserrat(
fontSize: 14,
color: Colors.white,
),
),
backgroundColor: ThemeColors.getColor('submitButton', isDarkMode),
),
);
},
icon: Icon(
LucideIcons.users,
size: 20,
color: ThemeColors.getColor('submitButton', isDarkMode),
),
label: Text(
'Community',
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
