import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;

class ImageService {
  Future<List<String>> downloadAndSaveImages(Set<String> urls) async {
    List<Future<String?>> downloadFutures =
        urls.map((url) => _downloadAndSaveImage(url)).toList();

    List<String?> results = await Future.wait(downloadFutures);

    return results.where((path) => path != null).cast<String>().toList();
  }

  String _getFileName(String url) {
    return url.split('/').last;
  }

  Future<String?> _downloadAndSaveImage(String url) async {
    final Directory directory = await getApplicationDocumentsDirectory();
    final String fileName = _getFileName(url);
    final String domainName = _getDomainName(url);

    // Create a subdirectory based on the domain
    final String subDirectoryPath = '${directory.path}/$domainName';
    final Directory subDirectory = Directory(subDirectoryPath);
    if (!subDirectory.existsSync()) {
      subDirectory.createSync(recursive: true);
    }
    final String filePath = '$subDirectoryPath/$fileName';
    final file = File(filePath);
    if (await file.exists()) {
      return filePath;
    }
    if (kDebugMode) {
      print('ImageService: Loading image from $url');
    }

    try {
      final response = await http.get(Uri.parse(url), headers: {
        'User-Agent':
            'DiscereApp/1.1 (ch.feberle.discere; https://github.com/feberle/discere)'
      }).timeout(const Duration(seconds: 5));
      if (response.statusCode == 200) {
        await file.writeAsBytes(response.bodyBytes);
        return filePath;
      } else {
        if (kDebugMode) {
          print('ImageService: Failed to load image from $url. Status code: ${response.statusCode}');
        }
      }
    } catch (e) {
      if (kDebugMode) {
        print('ImageService: Error loading image from $url: ${e.toString()}');
      }
    }
    return null;
  }

  String _getDomainName(String url) {
    final Uri uri = Uri.parse(url);
    return uri.host.replaceAll('.', '_');
  }
}
