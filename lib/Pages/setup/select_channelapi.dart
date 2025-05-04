import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../../constants/colors.dart';

class SelectChannelScreen extends StatefulWidget {
  const SelectChannelScreen({super.key});

  @override
  _SelectChannelScreenState createState() => _SelectChannelScreenState();
}

class _SelectChannelScreenState extends State<SelectChannelScreen> with SingleTickerProviderStateMixin {
  List<dynamic> selectedChannels = [];
  bool isLoading = true;
  String? errorMessage;
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeInOut),
    );
    fetchSelectedChannels();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  Future<void> fetchSelectedChannels() async {
    setState(() {
      isLoading = true;
      errorMessage = null;
    });
    try {
      final response = await http.post(
        Uri.parse('http://localhost/Table/SelectChannel.php'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'action': 'show'}),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() {
          selectedChannels = data;
          isLoading = false;
        });
        _animationController.forward();
      } else {
        throw Exception('Failed to fetch selected channels');
      }
    } catch (e) {
      setState(() {
        errorMessage = e.toString();
        isLoading = false;
      });
    }
  }

  Widget _buildTableHeader() {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [AppColors.headerBackground, AppColors.headerBackground.withOpacity(0.9)],
        ),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.15),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
      child: Row(
        children: [
          SizedBox(
            width: 50,
            child: Text(
              'S.No',
              style: GoogleFonts.poppins(
                fontWeight: FontWeight.w700,
                fontSize: 14,
                color: Colors.black,
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              'Channel',
              style: GoogleFonts.poppins(
                fontWeight: FontWeight.w700,
                fontSize: 14,
                color: Colors.black,
              ),
            ),
          ),
          SizedBox(
            width: 60,
            child: Text(
              'Unit',
              style: GoogleFonts.poppins(
                fontWeight: FontWeight.w700,
                fontSize: 14,
                color: Colors.black,
              ),
            ),
          ),
          Expanded(
            flex: 1,
            child: Text(
              'Start Char',
              style: GoogleFonts.poppins(
                fontWeight: FontWeight.w700,
                fontSize: 14,
                color: Colors.black,
              ),
            ),
          ),
          SizedBox(
            width: 60,
            child: Text(
              'Data Len',
              style: GoogleFonts.poppins(
                fontWeight: FontWeight.w700,
                fontSize: 14,
                color: Colors.black,
              ),
            ),
          ),
          SizedBox(
            width: 60,
            child: Text(
              'Dec Places',
              style: GoogleFonts.poppins(
                fontWeight: FontWeight.w700,
                fontSize: 14,
                color: Colors.black,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTableRow(dynamic channel, int index) {
    final recNo = channel['RecNo'] as int;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeInOut,
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        border: Border(
          bottom: BorderSide(color: Colors.grey.shade200, width: 0.5),
        ),
      ),
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
      child: Row(
        children: [
          SizedBox(
            width: 50,
            child: Text(
              '$recNo',
              style: GoogleFonts.poppins(fontSize: 12, color: AppColors.textPrimary),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              channel['ChannelName'],
              style: GoogleFonts.poppins(fontSize: 12, color: AppColors.textPrimary),
            ),
          ),
          SizedBox(
            width: 60,
            child: Text(
              channel['Unit'],
              style: GoogleFonts.poppins(fontSize: 12, color: AppColors.textPrimary),
            ),
          ),
          Expanded(
            flex: 1,
            child: Text(
              channel['StartingCharacter'],
              style: GoogleFonts.poppins(fontSize: 12, color: AppColors.textPrimary),
            ),
          ),
          SizedBox(
            width: 60,
            child: Text(
              '${channel['DataLength']}',
              style: GoogleFonts.poppins(fontSize: 12, color: AppColors.textPrimary),
            ),
          ),
          SizedBox(
            width: 60,
            child: Text(
              '${channel['DecimalPlaces']}',
              style: GoogleFonts.poppins(fontSize: 12, color: AppColors.textPrimary),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: FadeTransition(
              opacity: _fadeAnimation,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Selected Channels',
                    style: GoogleFonts.poppins(
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Card(
                    elevation: 1,
                    color: AppColors.cardBackground,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.white.withOpacity(0.15)),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.05),
                            blurRadius: 8,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      height: 400,
                      child: isLoading
                          ? const Center(
                        child: CircularProgressIndicator(
                          color: AppColors.submitButton,
                          strokeWidth: 2,
                        ),
                      )
                          : errorMessage != null
                          ? Center(
                        child: Text(
                          errorMessage!,
                          style: GoogleFonts.poppins(
                            color: AppColors.errorText,
                            fontSize: 14,
                          ),
                        ),
                      )
                          : selectedChannels.isEmpty
                          ? Center(
                        child: Text(
                          'No selected channels found',
                          style: GoogleFonts.poppins(
                            fontSize: 14,
                            color: AppColors.textPrimary,
                          ),
                        ),
                      )
                          : Scrollbar(
                        child: SingleChildScrollView(
                          scrollDirection: Axis.vertical,
                          child: SizedBox(
                            width: MediaQuery.of(context).size.width - 32,
                            child: Column(
                              children: [
                                _buildTableHeader(),
                                ...selectedChannels.asMap().entries.map((entry) {
                                  return _buildTableRow(entry.value, entry.key);
                                }),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}