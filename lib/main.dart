import 'dart:convert'; // JSON encode/decode
import 'dart:typed_data'; // Uint8List for file bytes

import 'package:file_picker/file_picker.dart'; // pick PDF from device
import 'package:flutter/material.dart'; // Flutter UI
import 'package:http/http.dart' as http; // HTTP requests
import 'package:http_parser/http_parser.dart'; // MediaType for multipart
import 'package:url_launcher/url_launcher.dart'; // open download URLs in browser


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


class SyllabusHome extends StatefulWidget { // stateful because we hold state
  const SyllabusHome({super.key}); // constructor

  @override
  State<SyllabusHome> createState() => _SyllabusHomeState(); // create state
} // end widget


class _SyllabusHomeState extends State<SyllabusHome> { // state class

  final String baseUrl = "https://instructormate1.onrender.com";// backend URL

  final TextEditingController _questionCtrl = TextEditingController(); // controller for question input

  PlatformFile? _pickedFile; // picked file metadata
  Uint8List? _fileBytes; // picked file bytes

  String? _chunksCsvPath; // backend-generated chunks CSV path
  String? _singleRowCsvPath; // backend-generated main CSV path

  bool _loading = false; // show loading
  String? _answer; // answer output
  String? _error; // error output

  String? _csvPreviewTitle; // title for CSV preview box
  String? _csvPreviewText; // loaded CSV preview text

  @override
  void dispose() { // dispose resources
    _questionCtrl.dispose(); // dispose controller
    super.dispose(); // call parent dispose
  } // end dispose


  Future<void> pickPdf() async { // pick a pdf from device
    setState(() { // update UI
      _error = null; // clear error
      _answer = null; // clear answer
      _csvPreviewTitle = null; // clear preview title
      _csvPreviewText = null; // clear preview text
      _chunksCsvPath = null; // reset chunks path
      _singleRowCsvPath = null; // reset main csv path
    }); // end setState

    final result = await FilePicker.platform.pickFiles( // open file picker
      type: FileType.custom, // allow custom extensions
      allowedExtensions: ['pdf'], // only pdf
      withData: true, // read bytes into memory
    ); // end pickFiles

    if (result == null || result.files.isEmpty) return; // user canceled

    final file = result.files.first; // get selected file
    final bytes = file.bytes; // read bytes

    if (bytes == null) { // if bytes not available
      if (!mounted) return; // safety
      setState(() => _error = "Could not read file bytes. Try again."); // show error
      return; // stop
    } // end bytes check

    if (!mounted) return; // safety
    setState(() { // update state
      _pickedFile = file; // store file info
      _fileBytes = bytes; // store bytes
    }); // end setState
  } // end pickPdf


  Future<void> convertSelectedPdf() async { // upload pdf and convert on backend
    if (_pickedFile == null || _fileBytes == null) { // validate selection
      setState(() => _error = "Please choose a PDF first."); // error
      return; // stop
    } // end validate

    setState(() { // update UI
      _loading = true; // start loading
      _error = null; // clear error
      _answer = null; // clear answer
      _csvPreviewTitle = null; // clear preview title
      _csvPreviewText = null; // clear preview text
      _chunksCsvPath = null; // clear old chunks path
      _singleRowCsvPath = null; // clear old main csv path
    }); // end setState

    try { // protected block
      final uri = Uri.parse("$_baseUrl/convert-upload"); // endpoint URL

      final req = http.MultipartRequest('POST', uri) // create multipart request
        ..files.add( // add file
          http.MultipartFile.fromBytes( // build file part
            'pdf', // field name expected by backend
            _fileBytes!, // bytes
            filename: _pickedFile!.name, // original file name
            contentType: MediaType('application', 'pdf'), // content type
          ), // end file part
        ); // end request

      final streamed = await req.send(); // send request
      final resp = await http.Response.fromStream(streamed); // read response

      if (resp.statusCode != 200) { // handle errors
        String msg = "Convert failed: ${resp.statusCode}"; // default message
        try { // parse backend error detail
          final j = jsonDecode(resp.body); // parse json
          if (j is Map && j['detail'] != null) msg = j['detail'].toString(); // detail field
        } catch (_) {} // ignore parse errors
        if (!mounted) return; // safety
        setState(() => _error = msg); // show error
        return; // stop
      } // end status check

      final data = jsonDecode(resp.body) as Map<String, dynamic>; // parse response
      final chunksCsv = (data['chunks_csv'] ?? '').toString(); // read chunks path
      final singleRowCsv = (data['single_row_csv'] ?? '').toString(); // read main csv path

      if (!mounted) return; // safety
      setState(() { // update state
        _chunksCsvPath = chunksCsv.isEmpty ? null : chunksCsv; // store chunks path
        _singleRowCsvPath = singleRowCsv.isEmpty ? null : singleRowCsv; // store main csv path
      }); // end setState
    } catch (e) { // runtime errors
      if (!mounted) return; // safety
      setState(() => _error = "Error: $e"); // show error
    } finally { // always stop loading
      if (!mounted) return; // safety
      setState(() => _loading = false); // stop loading
    } // end finally
  } // end convertSelectedPdf


  Future<void> ask() async { // ask question using chunks csv
    final question = _questionCtrl.text.trim(); // sanitize question
    if (question.isEmpty) { // validate question
      setState(() => _error = "Please type a question."); // error
      return; // stop
    } // end validate

    if (_chunksCsvPath == null || _chunksCsvPath!.isEmpty) { // ensure conversion done
      setState(() => _error = "Please convert the selected PDF first (press Convert)."); // error
      return; // stop
    } // end validate

    setState(() { // update UI
      _loading = true; // start loading
      _error = null; // clear error
      _answer = null; // clear answer
    }); // end setState

    try { // protected call
      final uri = Uri.parse("$_baseUrl/ask-from-chunks-path"); // endpoint URL

      final resp = await http.post( // send POST
        uri, // endpoint
        headers: {"Content-Type": "application/json"}, // json headers
        body: jsonEncode({ // request body
          "question": question, // question
          "chunks_csv_path": _chunksCsvPath, // path to chunks csv
        }), // end body
      ); // end post

      if (resp.statusCode != 200) { // handle errors
        String msg = "Ask failed: ${resp.statusCode}"; // default
        try { // parse backend detail
          final j = jsonDecode(resp.body); // parse json
          if (j is Map && j['detail'] != null) msg = j['detail'].toString(); // detail
        } catch (_) {} // ignore parse errors
        if (!mounted) return; // safety
        setState(() => _error = msg); // show error
        return; // stop
      } // end status check

      final data = jsonDecode(resp.body) as Map<String, dynamic>; // parse response
      final answer = (data['answer'] ?? '').toString(); // read answer

      if (!mounted) return; // safety
      setState(() => _answer = answer.isEmpty ? "No answer returned." : answer); // set answer
    } catch (e) { // runtime errors
      if (!mounted) return; // safety
      setState(() => _error = "Error: $e"); // show error
    } finally { // stop loading
      if (!mounted) return; // safety
      setState(() => _loading = false); // stop loading
    } // end finally
  } // end ask


  Future<void> viewCsvInUi(String title, String csvPath) async { // load CSV text and show in UI
    setState(() { // update UI
      _loading = true; // start loading
      _error = null; // clear error
      _csvPreviewTitle = title; // set preview title
      _csvPreviewText = null; // clear preview text while loading
    }); // end setState

    try { // protected request
      final encodedPath = Uri.encodeQueryComponent(csvPath); // url-encode path for query param
      final uri = Uri.parse("$_baseUrl/csv-text?path=$encodedPath"); // build URL
      final resp = await http.get(uri); // call GET

      if (resp.statusCode != 200) { // handle errors
        String msg = "View CSV failed: ${resp.statusCode}"; // default
        if (!mounted) return; // safety
        setState(() => _error = msg); // show error
        return; // stop
      } // end status check

      final text = resp.body; // CSV content as plain text
      if (!mounted) return; // safety
      setState(() => _csvPreviewText = text); // show text
    } catch (e) { // runtime errors
      if (!mounted) return; // safety
      setState(() => _error = "Error: $e"); // show error
    } finally { // stop loading
      if (!mounted) return; // safety
      setState(() => _loading = false); // stop loading
    } // end finally
  } // end viewCsvInUi


  Future<void> downloadCsv(String csvPath) async { // open download URL in browser
    final encodedPath = Uri.encodeQueryComponent(csvPath); // encode path
    final url = Uri.parse("$_baseUrl/csv-download?path=$encodedPath"); // build download URL
    final ok = await launchUrl(url, mode: LaunchMode.externalApplication); // launch browser/app
    if (!ok) { // if launch failed
      if (!mounted) return; // safety
      setState(() => _error = "Could not open download link."); // show error
    } // end fail
  } // end downloadCsv


  @override
  Widget build(BuildContext context) { // build UI
    final fileName = _pickedFile?.name ?? ""; // selected file name

    final canViewMain = _singleRowCsvPath != null && _singleRowCsvPath!.isNotEmpty; // view main enabled
    final canViewChunks = _chunksCsvPath != null && _chunksCsvPath!.isNotEmpty; // view chunks enabled

    return Scaffold( // page scaffold
      appBar: AppBar( // top app bar
        title: const Text("Syllabus Q&A (Convert + Ask + View/Download CSV)"), // title
      ), // end AppBar
      body: Padding( // add padding
        padding: const EdgeInsets.all(16), // padding size
        child: ListView( // scroll list
          children: [ // children list
            const Text( // section label
              "Step 1 — Choose a Syllabus PDF", // text
              style: TextStyle(fontWeight: FontWeight.bold), // style
            ), // end Text
            const SizedBox(height: 8), // spacing

            Row( // file selection row
              children: [ // row children
                Expanded( // allow text to take space
                  child: Text(fileName.isEmpty ? "No PDF chosen" : fileName), // show filename
                ), // end Expanded
                const SizedBox(width: 10), // spacing
                ElevatedButton( // choose button
                  onPressed: _loading ? null : pickPdf, // disable when loading
                  child: const Text("Choose PDF"), // label
                ), // end button
              ], // end row children
            ), // end Row

            const SizedBox(height: 12), // spacing

            ElevatedButton( // convert button
              onPressed: _loading ? null : convertSelectedPdf, // disable if loading
              child: Text(_loading ? "Working..." : "Convert PDF → CSV"), // label
            ), // end button

            const SizedBox(height: 16), // spacing

            const Text( // section label
              "Conversion Output (Backend Paths)", // text
              style: TextStyle(fontWeight: FontWeight.bold), // style
            ), // end Text
            const SizedBox(height: 8), // spacing

            Container( // path box
              padding: const EdgeInsets.all(12), // padding
              decoration: BoxDecoration( // decoration
                border: Border.all(color: Colors.black12), // border
                borderRadius: BorderRadius.circular(8), // radius
              ), // end decoration
              child: Text( // display paths
                "main_csv: ${_singleRowCsvPath ?? "—"}\n"
                "chunks_csv: ${_chunksCsvPath ?? "—"}", // text
              ), // end Text
            ), // end Container

            const SizedBox(height: 16), // spacing

            const Text( // section label
              "Step 1.5 — View / Download the Generated CSV", // label
              style: TextStyle(fontWeight: FontWeight.bold), // style
            ), // end Text
            const SizedBox(height: 8), // spacing

            Row( // buttons row
              children: [ // row children
                Expanded( // expand button
                  child: ElevatedButton( // view main csv
                    onPressed: (_loading || !canViewMain)
                        ? null
                        : () => viewCsvInUi("Main CSV (Single Row)", _singleRowCsvPath!), // view main
                    child: const Text("View Main CSV"), // label
                  ), // end button
                ), // end Expanded
                const SizedBox(width: 10), // spacing
                Expanded( // expand button
                  child: ElevatedButton( // download main csv
                    onPressed: (_loading || !canViewMain)
                        ? null
                        : () => downloadCsv(_singleRowCsvPath!), // download main
                    child: const Text("Download Main CSV"), // label
                  ), // end button
                ), // end Expanded
              ], // end row children
            ), // end Row

            const SizedBox(height: 10), // spacing

            Row( // second row
              children: [ // row children
                Expanded( // expand
                  child: ElevatedButton( // view chunks csv
                    onPressed: (_loading || !canViewChunks)
                        ? null
                        : () => viewCsvInUi("Chunks CSV (For Q&A)", _chunksCsvPath!), // view chunks
                    child: const Text("View Chunks CSV"), // label
                  ), // end button
                ), // end Expanded
                const SizedBox(width: 10), // spacing
                Expanded( // expand
                  child: ElevatedButton( // download chunks csv
                    onPressed: (_loading || !canViewChunks)
                        ? null
                        : () => downloadCsv(_chunksCsvPath!), // download chunks
                    child: const Text("Download Chunks CSV"), // label
                  ), // end button
                ), // end Expanded
              ], // end row children
            ), // end Row

            const SizedBox(height: 16), // spacing

            if (_csvPreviewTitle != null) ...[ // show preview section if available
              Text( // preview title
                _csvPreviewTitle!, // title
                style: const TextStyle(fontWeight: FontWeight.bold), // style
              ), // end Text
              const SizedBox(height: 8), // spacing
              Container( // preview box
                padding: const EdgeInsets.all(12), // padding
                decoration: BoxDecoration( // decoration
                  border: Border.all(color: Colors.black12), // border
                  borderRadius: BorderRadius.circular(8), // radius
                ), // end decoration
                child: SizedBox( // fixed height scroll area
                  height: 220, // height
                  child: SingleChildScrollView( // allow scroll
                    child: Text( // show text
                      _csvPreviewText ?? (_loading ? "Loading..." : "—"), // display csv text
                      style: const TextStyle(fontFamily: "monospace"), // monospace for csv
                    ), // end Text
                  ), // end scroll
                ), // end sized box
              ), // end container
              const SizedBox(height: 20), // spacing
            ], // end preview section

            const Text( // section label
              "Step 2 — Ask a Question", // label
              style: TextStyle(fontWeight: FontWeight.bold), // style
            ), // end Text
            const SizedBox(height: 8), // spacing

            TextField( // question input
              controller: _questionCtrl, // controller
              minLines: 2, // min lines
              maxLines: 5, // max lines
              decoration: const InputDecoration( // decoration
                border: OutlineInputBorder(), // border
                hintText: "Example: What is the grading breakdown?", // hint
              ), // end decoration
            ), // end TextField

            const SizedBox(height: 12), // spacing

            ElevatedButton( // ask button
              onPressed: _loading ? null : ask, // disable if loading
              child: Text(_loading ? "Asking..." : "Ask"), // label
            ), // end button

            const SizedBox(height: 20), // spacing

            if (_error != null) ...[ // show errors
              Text("Error: $_error", style: const TextStyle(color: Colors.red)), // error text
              const SizedBox(height: 12), // spacing
            ], // end errors

            const Text( // answer label
              "Answer", // label
              style: TextStyle(fontWeight: FontWeight.bold), // style
            ), // end Text
            const SizedBox(height: 8), // spacing

            Container( // answer box
              padding: const EdgeInsets.all(12), // padding
              decoration: BoxDecoration( // decoration
                border: Border.all(color: Colors.black12), // border
                borderRadius: BorderRadius.circular(8), // radius
              ), // end decoration
              child: Text(_answer ?? "—"), // show answer
            ), // end container
          ], // end children
        ), // end ListView
      ), // end Padding
    ); // end Scaffold
  } // end build
} // end state class
