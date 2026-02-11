// lib/app/api_client.dart // file path comment
import 'dart:convert'; // JSON encode/decode
import 'dart:typed_data'; // Uint8List for PDF bytes

import 'package:http/http.dart' as http; // HTTP client
import 'package:http_parser/http_parser.dart'; // MediaType for multipart content-type

class ApiClient { // API client class (SRP: backend communication only)
  ApiClient({required this.baseUrl, required this.timeout}); // constructor
  final String baseUrl; // backend base URL (Render/local)
  final Duration timeout; // request timeout

  Uri _u(String path) => Uri.parse("$baseUrl$path"); // build endpoint URLs safely

  Future<Map<String, dynamic>> convertUpload({ // upload PDF and convert
    required Uint8List pdfBytes, // PDF bytes from picker
    required String fileName, // original file name
  }) async {
    final req = http.MultipartRequest('POST', _u("/convert-upload")) // create multipart POST request
      ..files.add( // add file part
        http.MultipartFile.fromBytes( // build file part from bytes
          'pdf', // backend field name must match FastAPI param
          pdfBytes, // actual bytes
          filename: fileName, // name shown on server
          contentType: MediaType('application', 'pdf'), // set correct MIME
        ), // end file part
      ); // end request

    final streamed = await req.send().timeout(timeout); // send request with timeout
    final resp = await http.Response.fromStream(streamed); // convert streamed response to normal response

    if (resp.statusCode != 200) { // check success
      throw Exception(_extractBackendDetail(resp)); // throw readable backend message
    } // end error check

    return jsonDecode(resp.body) as Map<String, dynamic>; // return JSON as map
  } // end convertUpload

  Future<String> fetchCsvText({required String csvPath}) async { // view CSV content as text
    final encodedPath = Uri.encodeQueryComponent(csvPath); // encode path for URL query
    final uri = Uri.parse("$baseUrl/csv-text?path=$encodedPath"); // build csv-text endpoint URL

    final resp = await http.get(uri).timeout(timeout); // GET request with timeout
    if (resp.statusCode != 200) { // check success
      throw Exception("View CSV failed: ${resp.statusCode} — ${resp.body}"); // detailed error
    } // end error check
    return resp.body; // return CSV text
  } // end fetchCsvText

  Uri csvDownloadUri({required String csvPath}) { // build download link for CSV
    final encodedPath = Uri.encodeQueryComponent(csvPath); // encode path
    return Uri.parse("$baseUrl/csv-download?path=$encodedPath"); // download endpoint
  } // end csvDownloadUri

  Future<String> askFromChunksPath({ // ask question using chunks CSV path
    required String question, // question text
    required String chunksCsvPath, // chunks csv path (from convert response)
  }) async {
    final uri = _u("/ask-from-chunks-path"); // endpoint URL

    final resp = await http // use http client
        .post( // POST request
          uri, // endpoint
          headers: {"Content-Type": "application/json"}, // JSON body header
          body: jsonEncode({ // encode request body
            "question": question, // question field must match backend model
            "chunks_csv_path": chunksCsvPath, // chunks path field must match backend model
          }), // end body
        ) // end post
        .timeout(timeout); // apply timeout

    if (resp.statusCode != 200) { // check status
      throw Exception(_extractBackendDetail(resp)); // throw backend error details
    } // end error check

    final j = jsonDecode(resp.body) as Map<String, dynamic>; // decode JSON
    return (j["answer"] ?? "").toString(); // return answer string safely
  } // end askFromChunksPath

  String _extractBackendDetail(http.Response resp) { // try to extract backend detail message
    var msg = "Request failed: ${resp.statusCode}"; // default message
    try { // attempt to parse JSON
      final j = jsonDecode(resp.body); // decode JSON
      if (j is Map && j['detail'] != null) msg = j['detail'].toString(); // use FastAPI detail if present
    } catch (_) { // if not JSON
      msg = "$msg — ${resp.body}"; // attach raw body
    } // end try/catch
    return msg; // return final message
  } // end helper
} // end ApiClient
