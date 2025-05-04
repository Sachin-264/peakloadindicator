import 'dart:convert';
import 'package:http/http.dart' as http;

class ApiService {
  static const String baseUrl = 'http://localhost/Table/channel.php'; // Use localhost for Windows

  // Parse JSON response, throwing an error if invalid
  static dynamic _parseResponse(String body) {
    print('Raw response body: $body');
    try {
      return jsonDecode(body);
    } catch (e) {
      print('Failed to parse JSON: $e');
      throw Exception('Invalid response format: No valid JSON');
    }
  }

  // Fetch all channel records
  static Future<List<dynamic>> fetchChannels() async {
    try {
      print('Fetching channels from $baseUrl with action: show');
      final response = await http.post(
        Uri.parse(baseUrl),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'action': 'show'}),
      );

      print('Fetch channels response: ${response.statusCode}');
      if (response.statusCode == 200) {
        final data = _parseResponse(response.body);
        if (data['status'] == 'success') {
          print('Channels fetched: ${data['data']}');
          return data['data'];
        } else {
          throw Exception('API error: ${data['message'] ?? 'Unknown error'}');
        }
      } else {
        throw Exception('Failed to fetch channels: ${response.statusCode}');
      }
    } catch (e) {
      print('Error fetching channels: $e');
      throw Exception('Error fetching channels: $e');
    }
  }

  // Delete a channel by RecNo
  static Future<String> deleteChannel(int recNo) async {
    try {
      print('Deleting channel with RecNo: $recNo');
      final response = await http.post(
        Uri.parse(baseUrl),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'action': 'delete', 'RecNo': recNo}),
      );

      print('Delete channel response: ${response.statusCode}');
      if (response.statusCode == 200) {
        final data = _parseResponse(response.body);
        if (data['status'] == 'success') {
          final message = data['message'] ?? 'Record deleted successfully';
          print('Delete success: $message');
          return message;
        } else {
          throw Exception('API error: ${data['message'] ?? 'Unknown error'}');
        }
      } else {
        throw Exception('Failed to delete channel: ${response.statusCode}');
      }
    } catch (e) {
      print('Error deleting channel: $e');
      throw Exception('Error deleting channel: $e');
    }
  }

  // Edit a channel
  static Future<String> editChannel(Map<String, dynamic> channelData) async {
    try {
      print('Editing channel with data: $channelData');
      final response = await http.post(
        Uri.parse(baseUrl),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'action': 'edit',
          ...channelData,
        }),
      );

      print('Edit channel response: ${response.statusCode}');
      if (response.statusCode == 200) {
        final data = _parseResponse(response.body);
        if (data['status'] == 'success') {
          final message = data['message'] ?? 'Record updated successfully';
          print('Edit success: $message');
          return message;
        } else {
          throw Exception('API error: ${data['message'] ?? 'Unknown error'}');
        }
      } else {
        throw Exception('Failed to edit channel: ${response.statusCode}');
      }
    } catch (e) {
      print('Error editing channel: $e');
      throw Exception('Error editing channel: $e');
    }
  }

  // Add a new channel
  static Future<String> addChannel(Map<String, dynamic> channelData) async {
    try {
      print('Adding channel with data: $channelData');
      final response = await http.post(
        Uri.parse(baseUrl),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'action': 'add',
          ...channelData,
        }),
      );

      print('Add channel response: ${response.statusCode}');
      if (response.statusCode == 200) {
        final data = _parseResponse(response.body);
        if (data['status'] == 'success') {
          final message = data['message'] ?? 'Record added successfully';
          print('Add success: $message');
          return message;
        } else {
          throw Exception('API error: ${data['message'] ?? 'Unknown error'}');
        }
      } else {
        throw Exception('Failed to add channel: ${response.statusCode}');
      }
    } catch (e) {
      print('Error adding channel: $e');
      throw Exception('Error adding channel: $e');
    }
  }
}