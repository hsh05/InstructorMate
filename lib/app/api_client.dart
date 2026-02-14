// lib/app/api_client.dart // file path comment
import 'dart:convert'; // JSON encode/decode
import 'dart:typed_data'; // Uint8List for PDF bytes

import 'package:http/http.dart' as http; // HTTP client
import 'package:http_parser/http_parser.dart'; // MediaType for multipart content-type

class ApiClient { // API client class (SRP: backend communication only)
  ApiClient({required String baseUrl, required this.timeout})
      : baseUri = _normalizeBaseUri(baseUrl); // ✅ normalize base URL once (fix invalid url issues)

  final Uri baseUri; // ✅ parsed+normalized backend base URI
  final Duration timeout; // request timeout

  // ✅ Normalize BASE_URL so it always works on every platform:
  // - trims spaces
  // - adds http:// if missing
  // - removes trailing slash so URL joining is stable
  static Uri _normalizeBaseUri(String raw) {
    var s = (raw).trim(); // remove spaces/newlines
    if (s.isEmpty) {
      // clear error instead of weird "invalid uri"
      throw Exception("BASE_URL is empty. Set it to something like http://127.0.0.1:8000");
    }
  
    // If user provided "127.0.0.1:8000" (missing scheme), fix it.
    if (!s.startsWith("http://") && !s.startsWith("https://")) {
      s = "http://$s"; // add default scheme
    }

    // Remove trailing slash to avoid //path problems
    while (s.endsWith("/")) {
      s = s.substring(0, s.length - 1);
    }

    final u = Uri.parse(s); // parse to URI
    if (u.host.isEmpty) {
      // clearer error message if still wrong
      throw Exception("Invalid BASE_URL (no host): $s");
    }
    return u; // return normalized URI
  }

  // ✅ Safe URL builder:
  // - uses baseUri.resolve() (correct path joining)
  // - attaches query parameters
  Uri _u(String path, {Map<String, String>? q}) { // build endpoint URLs safely
    // ensure the path starts with a single "/"
    final cleanPath = path.startsWith("/") ? path : "/$path"; // normalize path

    // resolve() joins paths correctly even if baseUri has a path component
    var uri = baseUri.resolve(cleanPath); // join base + endpoint safely

    if (q != null && q.isNotEmpty) { // attach query params if provided
      uri = uri.replace(queryParameters: q); // add query parameters safely
    }
    return uri; // final URI
  } // end _u

  Future<String> convertUploadGetDocId({ // upload PDF and convert, returning docId
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

    final j = jsonDecode(resp.body) as Map<String, dynamic>; // parse JSON
    final docId = (j["doc_id"] ?? "").toString().trim(); // extract doc_id
    if (docId.isEmpty) { // validate
      throw Exception("Backend returned no doc_id."); // fail clearly
    } // end guard

    return docId; // return doc id
  } // end convertUploadGetDocId

  Future<String> fetchCsvTextByDocId({ // view CSV content as text by docId
    required String docId, // doc id
    String kind = "single_row", // "single_row" or "chunks"
  }) async {
    final uri = _u("/csv-text", q: { // build uri with query params
      "doc_id": docId, // doc id
      "kind": kind, // csv kind
    }); // end uri

    final resp = await http.get(uri).timeout(timeout); // GET request with timeout
    if (resp.statusCode != 200) { // check success
      throw Exception(_extractBackendDetail(resp)); // readable backend message
    } // end error check

    return resp.body; // return CSV text
  } // end fetchCsvTextByDocId

  Uri csvDownloadByDocIdUri({ // build download link for CSV by docId
    required String docId, // doc id
    String kind = "single_row", // "single_row" or "chunks"
  }) {
    return _u("/csv-download", q: { // build uri with query params
      "doc_id": docId, // doc id
      "kind": kind, // kind
    }); // end uri
  } // end csvDownloadByDocIdUri

  Future<String> ask({ // ask question using docId
    required String question, // question text
    required String docId, // doc id
  }) async {
    final uri = _u("/ask"); // endpoint URL

    final resp = await http // use http client
        .post( // POST request
          uri, // endpoint
          headers: {"Content-Type": "application/json"}, // JSON body header
          body: jsonEncode({ // encode request body
            "question": question, // question
            "doc_id": docId, // doc id
          }), // end body
        ) // end post
        .timeout(timeout); // apply timeout
        

    if (resp.statusCode != 200) { // check status
      throw Exception(_extractBackendDetail(resp)); // throw backend error details
    } // end error check

    final j = jsonDecode(resp.body) as Map<String, dynamic>; // decode JSON
    return (j["answer"] ?? "").toString(); // return answer
  } // end ask

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
