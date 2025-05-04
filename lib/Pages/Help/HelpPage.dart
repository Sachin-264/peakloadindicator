import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';

class HelpPage extends StatelessWidget {
  const HelpPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16.0),
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Colors.white, const Color(0xFFECEFF1)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 20,
                  spreadRadius: 5,
                ),
              ],
            ),
            padding: const EdgeInsets.all(20.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(
                      LucideIcons.helpCircle,
                      color: Color(0xFF455A64),
                      size: 32,
                    ),
                    const SizedBox(width: 10),
                    Text(
                      'Countron Smart Logger - Help',
                      style: GoogleFonts.poppins(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        color: const Color(0xFF455A64),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                _buildSection(
                  context,
                  title: 'About Countron Smart Logger',
                  icon: LucideIcons.info,
                  content: [
                    Text(
                      'Countron Smart Data Logger is a state-of-the-art Data Logging System which will save your data with respect to time. The Software gives you the option of viewing data in tabular as well as graphical form. It allows you lots of options like Logging Rate, Total Running Time & alarms for satisfying your every need. You can even export the data to Word document to be saved/modified as per your requirement.',
                      style: GoogleFonts.poppins(
                        fontSize: 14,
                        color: const Color(0xFF78909C),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'Working Procedure',
                      style: GoogleFonts.poppins(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: const Color(0xFF455A64),
                      ),
                    ),
                    const SizedBox(height: 5),
                    _buildOrderedList([
                      'Connect one end of the Serial Cable (9 Pin) to any available COM port of the computer and the other to our Data Acquisition Unit.',
                      'Turn on the whole system.',
                      'Run the application Countron Smart Logger in the All Programs menu.',
                      'Go to New Test Window. Make a new test.',
                      'Go to Open Test Window. Open a test file and can view report by clicking Making Report.',
                    ]),
                    const SizedBox(height: 10),
                    Text(
                      'Note: Set screen resolution of the computer to 800 X 600 for better visibility of the application & set the Date Format of system to DD/MM/YYYY.',
                      style: GoogleFonts.poppins(
                        fontSize: 12,
                        color: const Color(0xFFEF5350),
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ],
                ),
                _buildSection(
                  context,
                  title: 'Main (Welcome) Window',
                  icon: LucideIcons.home,
                  content: [
                    _buildSubSection(
                      title: 'New Test',
                      description:
                      'This is for starting a new Data Logging session. When it is clicked, a scan window opens. First it asks for Channels to be scanned & then it asks for values of all the required parameters to be specified. It then starts acquiring data from Data Logging Unit.',
                    ),
                    _buildSubSection(
                      title: 'Open Existing File',
                      description:
                      'This is for viewing stored scans. When it is clicked, a scan window opens and asks to select a scan file to be opened.',
                    ),
                    _buildSubSection(
                      title: 'Table Mode',
                      description:
                      'Clicking this, Data processing mode is selected. In this mode, in new scan window and in open scan window, scan data is displayed in tabular form with serial number, time and the scan data in their respective columns.',
                    ),
                    _buildSubSection(
                      title: 'Graph Mode',
                      description:
                      'Clicking this, Graph processing mode is selected. In this mode, in new scan window and in open scan window, scan data is displayed as a plot with scan data points marked as blue circles.',
                    ),
                    _buildSubSection(
                      title: 'Combined Mode (Table & Graph)',
                      description:
                      'Clicking this, Combined processing mode is selected. In this mode, in new scan window and in open scan window, scan data is displayed as a plot as well as tabular form.',
                    ),
                    _buildSubSection(
                      title: 'Setup',
                      description:
                      'You can choose any COM port you are interested in to connect the instrument. By default COM1 is selected for the Application. Also you can select the maximum & minimum target alarm for all the channels, Clicking Save in setup window sets all the changes you did there.',
                    ),
                    _buildSubSection(
                      title: 'Data Backup',
                      description: 'Clicking this, you can take backup or restore Data.',
                    ),
                    _buildSubSection(
                      title: 'Exit',
                      description: 'It closes the application.',
                    ),
                    _buildSubSection(
                      title: 'Help',
                      description: 'That’s ME !.',
                    ),
                  ],
                ),
                _buildSection(
                  context,
                  title: 'Open Test Window',
                  icon: LucideIcons.folderOpen,
                  content: [
                    _buildSubSection(
                      title: 'Delete Scan',
                      description:
                      'Clicking it deletes the loaded scan file.',
                    ),
                    _buildSubSection(
                      title: 'Making Report',
                      description:
                      'First, it asks for the channel name & duration of the test to be shown in report. Then it shows Making Report window. You can write headers, footers and miscellaneous text there to come in report. Clicking Ok button shows the report window. Then printout can be taken by clicking Print.',
                    ),
                    _buildSubSection(
                      title: 'Exit',
                      description: 'Closes the window to go back to main.',
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSection(BuildContext context, {required String title, required IconData icon, required List<Widget> content}) {
    return Card(
      elevation: 5,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      margin: const EdgeInsets.only(bottom: 15),
      child: ExpansionTile(
        leading: Icon(icon, color: const Color(0xFF455A64)),
        title: Text(
          title,
          style: GoogleFonts.poppins(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: const Color(0xFF455A64),
          ),
        ),
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: content,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSubSection({required String title, required String description}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: GoogleFonts.poppins(
              fontSize: 16,
              fontWeight: FontWeight.w500,
              color: const Color(0xFF455A64),
            ),
          ),
          const SizedBox(height: 5),
          Text(
            description,
            style: GoogleFonts.poppins(
              fontSize: 14,
              color: const Color(0xFF78909C),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOrderedList(List<String> items) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: items.asMap().entries.map((entry) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 5.0),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${entry.key + 1}. ',
                style: GoogleFonts.poppins(
                  fontSize: 14,
                  color: const Color(0xFF78909C),
                ),
              ),
              Expanded(
                child: Text(
                  entry.value,
                  style: GoogleFonts.poppins(
                    fontSize: 14,
                    color: const Color(0xFF78909C),
                  ),
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }
}