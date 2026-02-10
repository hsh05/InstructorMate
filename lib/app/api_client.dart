
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

class ApiClient {
  ApiClient({required this.baseUrl});
  final String baseUrl;

  Future<Map<String, dynamic>> convertUpload({
    required Uint8List pdfBytes,
    required String fileName,
  }) async {
    final uri = Uri.parse("$baseUrl/convert-upload");

    final req = http.MultipartRequest('POST', uri)
      ..files.add(
        http.MultipartFile.fromBytes(
          'pdf',
          pdfBytes,
          filename: fileName,
          contentType: MediaType('application', 'pdf'),
        ),
      );

    final streamed = await req.send();
    final resp = await http.Response.fromStream(streamed);

    if (resp.statusCode != 200) {
      throw Exception(_extractBackendDetail(resp));
    }

    return jsonDecode(resp.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> askFromChunksPath({
    required String question,
    required String chunksCsvPath,
  }) async {
    final uri = Uri.parse("$baseUrl/ask-from-chunks-path");

    final resp = await http.post(
      uri,
      headers: {"Content-Type": "application/json"},
      body: jsonEncode({
        "question": question,
        "chunks_csv_path": chunksCsvPath,
      }),
    );

    if (resp.statusCode != 200) {
      throw Exception(_extractBackendDetail(resp));
    }

    return jsonDecode(resp.body) as Map<String, dynamic>;
  }

  Future<String> fetchCsvText({required String csvPath}) async {
    final encodedPath = Uri.encodeQueryComponent(csvPath);
    final uri = Uri.parse("$baseUrl/csv-text?path=$encodedPath");

    final resp = await http.get(uri);
    if (resp.statusCode != 200) {
      throw Exception("View CSV failed: ${resp.statusCode}");
    }
    return resp.body;
  }

  Uri csvDownloadUri({required String csvPath}) {
    final encodedPath = Uri.encodeQueryComponent(csvPath);
    return Uri.parse("$baseUrl/csv-download?path=$encodedPath");
  }

  String _extractBackendDetail(http.Response resp) {
    var msg = "Request failed: ${resp.statusCode}";
    try {
      final j = jsonDecode(resp.body);
      if (j is Map && j['detail'] != null) msg = j['detail'].toString();
    } catch (_) {}
    return msg;
  }
}
