import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_libserialport/flutter_libserialport.dart';
import 'package:peakloadindicator/Pages/homepage.dart';
import 'Pages/Secondary_window/secondary_window.dart';

void main(List<String> args) {
  print('Main function called with args: $args');
  // Check if args has at least 3 elements and args[2] is the JSON data
  if (args.length >= 3) {
    print('Raw argument: ${args[2]}'); // Debug the JSON argument
    try {
      // Parse the JSON data from args[2]
      final argsMap = jsonDecode(args[2]) as Map<String, dynamic>;
      print('Secondary window args decoded: $argsMap');
      // Validate required fields
      if (argsMap.containsKey('channel') && argsMap.containsKey('channelData')) {
        runApp(MaterialApp(
          home: SecondaryWindowApp(
            channel: argsMap['channel'] as String,
            channelData: argsMap['channelData'] as Map<String, dynamic>,
          ),
        ));
      } else {
        print('Invalid args format: Missing required fields');
        runApp(MaterialApp(home: HomePage()));
      }
    } catch (e) {
      print('Error parsing secondary window args: $e');
      // Fallback to default app if parsing fails
      runApp(MaterialApp(home: HomePage()));
    }
  } else {
    // Run the default app for the primary window
    print('Running default app');
    runApp(MaterialApp(home: HomePage()));
  }
  }
