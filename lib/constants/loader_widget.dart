// lib/widgets/loader_widget.dart
import 'package:flutter/material.dart';
import 'package:flutter_spinkit/flutter_spinkit.dart';
import '../constants/colors.dart'; // Import colors for consistency

class LoaderWidget extends StatelessWidget {
  const LoaderWidget({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SpinKitFadingCube(
        color: AppColors.submitButton, // Use a color from AppColors (blue)
        size: 50.0, // Size of the loader
      ),
    );
  }
}