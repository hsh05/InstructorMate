import 'dart:convert'; // JSON encode/decode
import 'dart:typed_data'; // Uint8List for file bytes

import 'package:file_picker/file_picker.dart'; // pick PDF from device
import 'package:flutter/material.dart'; // Flutter UI
import 'package:http/http.dart' as http; // HTTP client
import 'package:http_parser/http_parser.dart'; // MediaType for multipart


void main() => runApp(const SyllabusApp()); // app entry point


class SyllabusApp extends StatelessWidget { // root widget
  const SyllabusApp({super.key}); // constructor

  @override
  Widget build(BuildContext context) { // build UI
    return MaterialApp( // material app wrapper
      title: 'Syllabus Q&A', // app title
      debugShowCheckedModeBanner: false, // remove debug banner
      home: const SyllabusHome(), // home screen
    ); // end MaterialApp
  } // end build
} // end class


class SyllabusHome extends StatefulWidget { // stateful because we hold file + answer + loading
  const SyllabusHome({super.key}); // constructor

  @override
  State<SyllabusHome> createState() => _SyllabusHomeState(); // connect state
} // end widget


class _SyllabusHomeState extends State<SyllabusHome> { // state class

  static const String _baseUrl = "http://127.0.0.1:8000"; // backend URL (change if needed)

  final TextEditingController _questionCtrl = TextEditingController(); // controller for question input

  PlatformFile? _pickedFile; // picked file metadata
  Uint8List? _fileBytes; // file bytes to upload

  String? _chunksCsvPath; // backend-generated chunks CSV path (stored after convert)
  String? _singleRowCsvPath; // backend-generated single row CSV path (optional to display)

  bool _loading = false; // show loading spinner / disable buttons
  String? _answer; // store answer text
  String? _error; // store error text

  @override
  void dispose() { // cleanup controllers
    _questionCtrl.dispose(); // dispose controller
    super.dispose(); // call parent dispose
  } // end dispose


  Future<void> pickPdf() async { // pick a pdf from the device
    setState(() { // update UI
      _error = null; // clear error
      _answer = null; // clear answer
      _chunksCsvPath = null; // reset chunks path because new file chosen
      _singleRowCsvPath = null; // reset single row path
    }); // end setState

    final result = await FilePicker.platform.pickFiles( // open file picker
      type: FileType.custom, // allow custom extensions
      allowedExtensions: ['pdf'], // only pdf
      withData: true, // load bytes into memory
    ); // end pickFiles

    if (result == null || result.files.isEmpty) return; // user canceled

    final file = result.files.first; // take first selected file
    final bytes = file.bytes; // get bytes

    if (bytes == null) { // if bytes couldn't be loaded
      if (!mounted) return; // safety check
      setState(() => _error = "Could not read file bytes. Try again."); // show error
      return; // stop
    } // end bytes null check

    if (!mounted) return; // safety check
    setState(() { // update UI
      _pickedFile = file; // store file info
      _fileBytes = bytes; // store bytes
    }); // end setState
  } // end pickPdf


  Future<void> convertSelectedPdf() async { // upload pdf and convert on backend
    if (_pickedFile == null || _fileBytes == null) { // validate file selected
      setState(() => _error = "Please choose a PDF first."); // show error
      return; // stop
    } // end validate

    setState(() { // update UI
      _loading = true; // enable loading
      _error = null; // clear error
      _answer = null; // clear answer
      _chunksCsvPath = null; // clear old chunks path
      _singleRowCsvPath = null; // clear old single row path
    }); // end setState

    try { // protected request
      final uri = Uri.parse("$_baseUrl/convert-upload"); // endpoint URL

      final req = http.MultipartRequest('POST', uri) // create multipart request
        ..files.add( // add file part
          http.MultipartFile.fromBytes( // create file part from bytes
            'pdf', // field name expected by backend
            _fileBytes!, // bytes
            filename: _pickedFile!.name, // original filename
            contentType: MediaType('application', 'pdf'), // set content type
          ), // end MultipartFile
        ); // end MultipartRequest

      final streamed = await req.send(); // send request
      final resp = await http.Response.fromStream(streamed); // read response

      if (resp.statusCode != 200) { // if error
        String msg = "Convert failed: ${resp.statusCode}"; // default message
        try { // parse backend detail
          final j = jsonDecode(resp.body); // parse JSON
          if (j is Map && j['detail'] != null) msg = j['detail'].toString(); // use detail if present
        } catch (_) {} // ignore JSON parse errors
        if (!mounted) return; // safety
        setState(() => _error = msg); // show error
        return; // stop
      } // end status check

      final data = jsonDecode(resp.body) as Map<String, dynamic>; // parse response JSON
      final chunksCsv = (data['chunks_csv'] ?? '').toString(); // read chunks csv path
      final singleRowCsv = (data['single_row_csv'] ?? '').toString(); // read single row csv path

      if (!mounted) return; // safety
      setState(() { // update UI
        _chunksCsvPath = chunksCsv.isEmpty ? null : chunksCsv; // store chunks path
        _singleRowCsvPath = singleRowCsv.isEmpty ? null : singleRowCsv; // store single row path
      }); // end setState
    } catch (e) { // network / runtime errors
      if (!mounted) return; // safety
      setState(() => _error = "Error: $e"); // show error
    } finally { // always clear loading
      if (!mounted) return; // safety
      setState(() => _loading = false); // stop loading
    } // end finally
  } // end convertSelectedPdf


  Future<void> ask() async { // ask question using chunks csv if available
    final question = _questionCtrl.text.trim(); // sanitize question
    if (question.isEmpty) { // validate question
      setState(() => _error = "Please type a question."); // show error
      return; // stop
    } // end validate question

    if (_chunksCsvPath == null || _chunksCsvPath!.isEmpty) { // ensure conversion happened first
      setState(() => _error = "Please convert the selected PDF first (press Convert)."); // show error
      return; // stop
    } // end validate conversion

    setState(() { // update UI
      _loading = true; // loading
      _error = null; // clear error
      _answer = null; // clear answer
    }); // end setState

    try { // protected call
      final uri = Uri.parse("$_baseUrl/ask-from-chunks-path"); // endpoint URL

      final resp = await http.post( // send POST request
        uri, // endpoint
        headers: {"Content-Type": "application/json"}, // JSON headers
        body: jsonEncode({ // encode body
          "question": question, // question
          "chunks_csv_path": _chunksCsvPath, // tell backend which chunks csv to use
        }), // end body
      ); // end http.post

      if (resp.statusCode != 200) { // handle error
        String msg = "Ask failed: ${resp.statusCode}"; // default message
        try { // parse backend detail
          final j = jsonDecode(resp.body); // parse JSON
          if (j is Map && j['detail'] != null) msg = j['detail'].toString(); // use detail
        } catch (_) {} // ignore parsing errors
        if (!mounted) return; // safety
        setState(() => _error = msg); // show error
        return; // stop
      } // end status check

      final data = jsonDecode(resp.body) as Map<String, dynamic>; // parse response
      final answer = (data['answer'] ?? '').toString(); // read answer

      if (!mounted) return; // safety
      setState(() => _answer = answer.isEmpty ? "No answer returned." : answer); // set answer
    } catch (e) { // handle runtime errors
      if (!mounted) return; // safety
      setState(() => _error = "Error: $e"); // show error
    } finally { // always clear loading
      if (!mounted) return; // safety
      setState(() => _loading = false); // stop loading
    } // end finally
  } // end ask


  @override
  Widget build(BuildContext context) { // build UI
    final fileName = _pickedFile?.name ?? ""; // show selected file name

    return Scaffold( // page scaffold
      appBar: AppBar( // app bar
        title: const Text("Syllabus Q&A (Convert + Ask)"), // title
      ), // end AppBar
      body: Padding( // page padding
        padding: const EdgeInsets.all(16), // padding value
        child: ListView( // vertical scroll list
          children: [ // list children
            const Text( // label
              "Step 1 — Choose a Syllabus PDF", // text
              style: TextStyle(fontWeight: FontWeight.bold), // style
            ), // end Text
            const SizedBox(height: 8), // spacing

            Row( // file row
              children: [ // row items
                Expanded( // expand file name area
                  child: Text(fileName.isEmpty ? "No PDF chosen" : fileName), // show name
                ), // end Expanded
                const SizedBox(width: 10), // spacing
                ElevatedButton( // choose button
                  onPressed: _loading ? null : pickPdf, // disable if loading
                  child: const Text("Choose PDF"), // label
                ), // end button
              ], // end row items
            ), // end Row

            const SizedBox(height: 12), // spacing

            ElevatedButton( // convert button
              onPressed: _loading ? null : convertSelectedPdf, // disable if loading
              child: Text(_loading ? "Working..." : "Convert PDF → CSV"), // label
            ), // end button

            const SizedBox(height: 16), // spacing

            const Text( // label
              "Conversion Output (Backend Paths)", // text
              style: TextStyle(fontWeight: FontWeight.bold), // style
            ), // end Text
            const SizedBox(height: 8), // spacing

            Container( // path display box
              padding: const EdgeInsets.all(12), // padding
              decoration: BoxDecoration( // decoration
                border: Border.all(color: Colors.black12), // border
                borderRadius: BorderRadius.circular(8), // rounded corners
              ), // end decoration
              child: Text( // inside text
                "chunks_csv: ${_chunksCsvPath ?? "—"}\n"
                "single_row_csv: ${_singleRowCsvPath ?? "—"}", // display both
              ), // end Text
            ), // end Container

            const SizedBox(height: 20), // spacing

            const Text( // label
              "Step 2 — Ask a Question", // text
              style: TextStyle(fontWeight: FontWeight.bold), // style
            ), // end Text
            const SizedBox(height: 8), // spacing

            TextField( // question input
              controller: _questionCtrl, // controller
              minLines: 2, // minimum lines
              maxLines: 5, // maximum lines
              decoration: const InputDecoration( // decoration
                border: OutlineInputBorder(), // border style
                hintText: "Example: What is the grading breakdown?", // hint
              ), // end decoration
            ), // end TextField

            const SizedBox(height: 12), // spacing

            ElevatedButton( // ask button
              onPressed: _loading ? null : ask, // disable if loading
              child: Text(_loading ? "Asking..." : "Ask"), // label
            ), // end button

            const SizedBox(height: 20), // spacing

            if (_error != null) ...[ // show error if exists
              Text("Error: $_error", style: const TextStyle(color: Colors.red)), // error text
              const SizedBox(height: 12), // spacing
            ], // end error section

            const Text( // label
              "Answer", // text
              style: TextStyle(fontWeight: FontWeight.bold), // style
            ), // end Text
            const SizedBox(height: 8), // spacing

            Container( // answer box
              padding: const EdgeInsets.all(12), // padding
              decoration: BoxDecoration( // decoration
                border: Border.all(color: Colors.black12), // border
                borderRadius: BorderRadius.circular(8), // rounded corners
              ), // end decoration
              child: Text(_answer ?? "—"), // show answer or dash
            ), // end container
          ], // end children
        ), // end ListView
      ), // end Padding
    ); // end Scaffold
  } // end build
} // end state class
