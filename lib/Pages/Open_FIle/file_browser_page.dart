
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:peakloadindicator/constants/loader_widget.dart';
import '../../constants/global.dart';
import '../../constants/theme.dart';
import '../../constants/database_manager.dart';
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
Future<List<Map<String, dynamic>>> _fetchFilesFromDatabase() async {
try {
print('Fetching files from database');
final database = await DatabaseManager().database;

final files = await database.query(
'Test',
columns: [
'RecNo',
'FName',
'OperatorName',
'ScanningRate',
'ScanningRateHH',
'ScanningRateMM',
'ScanningRateSS',
'TestDurationDD',
'TestDurationHH',
'TestDurationMM',
'TestDurationSS',
'GraphVisibleArea',
'DBName'
],
orderBy: 'RecNo DESC',
);
print('Found ${files.length} files in database');
return files;
} catch (e) {
print('Error fetching files from database: $e');
throw Exception('Failed to load data from database');
}
}

void _showBrowseDialog(BuildContext context) {
print('FileSelectionDialog _showBrowseDialog: Opening browse dialog');
showDialog(
context: context,
builder: (BuildContext dialogContext) {
return ValueListenableBuilder<bool>(
valueListenable: Global.isDarkMode,
builder: (context, isDarkMode, child) {
return Dialog(
shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
backgroundColor: ThemeColors.getColor('dialogBackground', isDarkMode),
child: Container(
width: 600,
padding: const EdgeInsets.all(24),
child: Column(
mainAxisSize: MainAxisSize.min,
children: [
Text(
'Select a File',
style: GoogleFonts.poppins(
fontSize: 28,
fontWeight: FontWeight.bold,
color: ThemeColors.getColor('dialogText', isDarkMode),
),
),
const SizedBox(height: 12),
FutureBuilder<List<Map<String, dynamic>>>(
future: _fetchFilesFromDatabase(),
builder: (context, snapshot) {
if (snapshot.connectionState == ConnectionState.waiting) {
return const Padding(
padding: EdgeInsets.all(20),
child: LoaderWidget(),
);
} else if (snapshot.hasError) {
print('FileSelectionDialog FutureBuilder: Error = ${snapshot.error}');
return Text(
'Error: ${snapshot.error}',
style: GoogleFonts.poppins(
color: ThemeColors.getColor('errorText', isDarkMode),
),
);
} else if (snapshot.hasData) {
final files = snapshot.data!;
return SizedBox(
height: 300,
width: double.infinity,
child: SingleChildScrollView(
child: DataTable(
headingRowColor: MaterialStateProperty.all(
ThemeColors.getColor('tableHeaderBackground', isDarkMode),
),
dataRowColor: MaterialStateProperty.resolveWith((states) {
if (states.contains(MaterialState.selected)) {
return ThemeColors.getColor('dropdownHover', isDarkMode);
}
return ThemeColors.getColor('tableRowAlternate', isDarkMode);
}),
columns: [
DataColumn(
label: Text(
'SNo',
style: GoogleFonts.poppins(
fontWeight: FontWeight.bold,
color: ThemeColors.getColor('dialogText', isDarkMode),
),
),
),
DataColumn(
label: Text(
'FName',
style: GoogleFonts.poppins(
fontWeight: FontWeight.bold,
color: ThemeColors.getColor('dialogText', isDarkMode),
),
),
),
DataColumn(
label: Text(
'Operator Name',
style: GoogleFonts.poppins(
fontWeight: FontWeight.bold,
color: ThemeColors.getColor('dialogText', isDarkMode),
),
),
),
],
rows: files.map((file) {
return DataRow(
cells: [
DataCell(
Text(
file['RecNo'].toString(),
style: GoogleFonts.poppins(
color: ThemeColors.getColor('dialogSubText', isDarkMode),
),
),
),
DataCell(
Text(
file['FName']?.toString() ?? 'N/A',
style: GoogleFonts.poppins(
color: ThemeColors.getColor('dialogSubText', isDarkMode),
),
),
),
DataCell(
Text(
file['OperatorName']?.toString() ?? 'N/A',
style: GoogleFonts.poppins(
color: ThemeColors.getColor('dialogSubText', isDarkMode),
),
),
),
],
onSelectChanged: (selected) async {
if (selected ?? false) {
print('FileSelectionDialog DataRow: Selected file = ${file['FName']}, RecNo = ${file['RecNo']}');
try {
setState(() {
widget.controller.text = file['FName']?.toString() ?? '';

// Initialize Global ValueNotifiers if null
Global.selectedRecNo ??= ValueNotifier<int?>(null);
Global.selectedFileName ??= ValueNotifier<String?>(null);
Global.operatorName ??= ValueNotifier<String?>(null);
Global.selectedDBName ??= ValueNotifier<String?>(null);
Global.scanningRate ??= ValueNotifier<int?>(null);
Global.scanningRateHH ??= ValueNotifier<int?>(null);
Global.scanningRateMM ??= ValueNotifier<int?>(null);
Global.scanningRateSS ??= ValueNotifier<int?>(null);
Global.testDurationDD ??= ValueNotifier<int?>(null);
Global.testDurationHH ??= ValueNotifier<int?>(null);
Global.testDurationMM ??= ValueNotifier<int?>(null);
Global.testDurationSS ??= ValueNotifier<int?>(null);
Global.graphVisibleArea ??= ValueNotifier<String?>(null);

// Assign values
Global.selectedRecNo!.value = (file['RecNo'] as double?)?.toInt();
Global.selectedFileName!.value = file['FName']?.toString();
Global.operatorName!.value = file['OperatorName']?.toString();
Global.selectedDBName!.value = file['DBName']?.toString();

Global.scanningRate!.value = (file['ScanningRate'] as double?)?.toInt();
Global.scanningRateHH!.value = (file['ScanningRateHH'] as double?)?.toInt();
Global.scanningRateMM!.value = (file['ScanningRateMM'] as double?)?.toInt();
Global.scanningRateSS!.value = (file['ScanningRateSS'] as double?)?.toInt();

Global.testDurationDD!.value = (file['TestDurationDD'] as double?)?.toInt();
Global.testDurationHH!.value = (file['TestDurationHH'] as double?)?.toInt();
Global.testDurationMM!.value = (file['TestDurationMM'] as double?)?.toInt();
Global.testDurationSS!.value = (file['TestDurationSS'] as double?)?.toInt();

print('FileSelectionDialog DataRow: testduration = ${Global.testDurationSS!.value}');
Global.graphVisibleArea!.value = file['GraphVisibleArea']?.toString();

print('FileSelectionDialog DataRow: Updated Global variables successfully');
});
Navigator.of(dialogContext).pop();
} catch (e) {
print('FileSelectionDialog DataRow: Error = $e');
ScaffoldMessenger.of(context).showSnackBar(
SnackBar(
content: Text(
'Error updating file details: $e',
style: GoogleFonts.poppins(
color: ThemeColors.getColor('errorText', isDarkMode),
),
),
backgroundColor: ThemeColors.getColor('dialogBackground', isDarkMode),
),
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
return Text(
'No data available',
style: GoogleFonts.poppins(
color: ThemeColors.getColor('dialogSubText', isDarkMode),
),
);
}
},
),
const SizedBox(height: 24),
Row(
mainAxisAlignment: MainAxisAlignment.end,
children: [
TextButton(
onPressed: () => Navigator.of(dialogContext).pop(),
child: Text(
'Cancel',
style: GoogleFonts.poppins(
color: ThemeColors.getColor('resetButton', isDarkMode),
),
),
),
],
),
],
),
),
);
},
);
},
);
}

@override
Widget build(BuildContext context) {
print('FileSelectionDialog build: Building dialog');
return ValueListenableBuilder<bool>(
valueListenable: Global.isDarkMode,
builder: (context, isDarkMode, child) {
return Dialog(
shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
backgroundColor: ThemeColors.getColor('dialogBackground', isDarkMode),
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
color: ThemeColors.getColor('dialogText', isDarkMode),
),
),
const SizedBox(height: 12),
Text(
'Select a file to open or enter the file path.',
style: GoogleFonts.poppins(
fontSize: 16,
color: ThemeColors.getColor('dialogSubText', isDarkMode),
),
),
const SizedBox(height: 24),
Row(
children: [
Expanded(
child: TextField(
controller: widget.controller,
style: GoogleFonts.poppins(
color: ThemeColors.getColor('dialogText', isDarkMode),
fontSize: 14,
),
decoration: InputDecoration(
hintText: 'File path...',
hintStyle: GoogleFonts.poppins(
color: ThemeColors.getColor('dialogSubText', isDarkMode).withOpacity(0.6),
),
filled: true,
fillColor: ThemeColors.getColor('textFieldBackground', isDarkMode),
border: OutlineInputBorder(
borderRadius: BorderRadius.circular(4),
borderSide: BorderSide(
color: ThemeColors.getColor('cardBorder', isDarkMode),
),
),
enabledBorder: OutlineInputBorder(
borderRadius: BorderRadius.circular(4),
borderSide: BorderSide(
color: ThemeColors.getColor('cardBorder', isDarkMode),
),
),
focusedBorder: OutlineInputBorder(
borderRadius: BorderRadius.circular(4),
borderSide: BorderSide(
color: ThemeColors.getColor('submitButton', isDarkMode),
width: 2,
),
),
contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
),
),
),
const SizedBox(width: 12),
ElevatedButton.icon(
onPressed: () => _showBrowseDialog(context),
icon: Icon(
Icons.folder_open,
color: ThemeColors.getColor('sidebarIcon', isDarkMode),
),
label: Text(
'Browse',
style: GoogleFonts.poppins(
color: ThemeColors.getColor('sidebarText', isDarkMode),
),
),
style: ElevatedButton.styleFrom(
backgroundColor: Colors.transparent,
foregroundColor: ThemeColors.getColor('buttonHover', isDarkMode),
shadowColor: Colors.transparent,
shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
elevation: 0,
).copyWith(
backgroundBuilder: (context, states, child) {
return Container(
decoration: BoxDecoration(
gradient: ThemeColors.getButtonGradient(isDarkMode),
borderRadius: BorderRadius.circular(4),
),
child: child,
);
},
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
style: GoogleFonts.poppins(
color: ThemeColors.getColor('resetButton', isDarkMode),
),
),
),
const SizedBox(width: 12),
ElevatedButton(
onPressed: widget.onOpenPressed ??
() {
print(
'FileSelectionDialog Open button: File name = ${widget.controller.text}, RecNo = ${Global.selectedRecNo?.value}');
if (widget.controller.text.isNotEmpty) {
Navigator.of(context).push(
MaterialPageRoute(
builder: (context) => OpenFilePage(
fileName: widget.controller.text,
),
),
);
}
},
child: Text(
'Open',
style: GoogleFonts.poppins(
color: ThemeColors.getColor('sidebarText', isDarkMode),
),
),
style: ElevatedButton.styleFrom(
backgroundColor: Colors.transparent,
foregroundColor: ThemeColors.getColor('buttonHover', isDarkMode),
shadowColor: Colors.transparent,
shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
elevation: 0,
).copyWith(
backgroundBuilder: (context, states, child) {
return Container(
decoration: BoxDecoration(
gradient: ThemeColors.getButtonGradient(isDarkMode),
borderRadius: BorderRadius.circular(4),
),
child: child,
);
},
),
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
void dispose() {
// The main database is managed by DatabaseManager, so no explicit close here.
super.dispose();
}
}
