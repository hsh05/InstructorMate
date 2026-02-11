// lib/ui/syllabus_home.dart // file path comment
import 'dart:typed_data'; // Uint8List

import 'package:file_picker/file_picker.dart'; // pick PDF
import 'package:flutter/material.dart'; // Flutter UI
import 'package:url_launcher/url_launcher.dart'; // open download links

import '../app/state/syllabus_vm.dart'; // VM import

class SyllabusHome extends StatefulWidget { // main screen widget
  const SyllabusHome({super.key, required this.vm}); // constructor
  final SyllabusViewModel vm; // view-model dependency

  @override
  State<SyllabusHome> createState() => _SyllabusHomeState(); // create state
} // end widget

class _SyllabusHomeState extends State<SyllabusHome> { // screen state
  final questionCtrl = TextEditingController(); // controller for question input

  @override
  void dispose() { // dispose resources
    questionCtrl.dispose(); // dispose controller
    super.dispose(); // call parent dispose
  } // end dispose

  Future<void> _pickAndConvert() async { // pick PDF then convert immediately
    final messenger = ScaffoldMessenger.of(context); // ✅ capture messenger BEFORE await to avoid context-after-await lint

    final res = await FilePicker.platform.pickFiles( // open file picker
      type: FileType.custom, // custom type
      allowedExtensions: const ["pdf"], // allow pdf only
      withData: true, // load bytes in memory
    ); // end pickFiles

    if (!mounted) return; // ✅ stop if widget disposed while picking

    if (res == null || res.files.isEmpty) return; // user cancelled

    final f = res.files.first; // first selected file
    final Uint8List? bytes = f.bytes; // bytes (null if not loaded)
    if (bytes == null) { // guard null bytes
      messenger.showSnackBar( // show snack
        const SnackBar(content: Text("Could not read file bytes.")), // message
      ); // end snack
      return; // stop
    } // end null guard

    await widget.vm.convert( // call VM convert
      pdfBytes: bytes, // ✅ no cast needed
      fileName: f.name, // file name
    ); // end convert await

    if (!mounted) return; // ✅ stop if widget disposed while converting

    if (widget.vm.error != null) { // if error occurred
      messenger.showSnackBar( // ✅ use captured messenger (no context warning)
        SnackBar(content: Text(widget.vm.error!)), // show error
      ); // end snack
    } // end error
  } // end pickAndConvert

  Future<void> _ask() async { // ask helper to centralize async + context-safe snackbar
    final messenger = ScaffoldMessenger.of(context); // ✅ capture messenger before await

    final q = questionCtrl.text.trim(); // read question
    if (q.isEmpty) return; // ignore empty

    await widget.vm.askQuestion(q); // ask via VM

    if (!mounted) return; // ✅ guard after await

    if (widget.vm.error != null) { // show error if any
      messenger.showSnackBar( // ✅ use captured messenger
        SnackBar(content: Text(widget.vm.error!)), // message
      ); // end snack
    } // end error
  } // end ask

  Future<void> _downloadSingleRowCsv() async { // download helper
    final vm = widget.vm; // local shortcut
    final path = (vm.singleRowCsvPath ?? "").trim(); // get csv path
    if (path.isEmpty) return; // guard empty

    final uri = vm.api.csvDownloadUri(csvPath: path); // build download URL
    await launchUrl(uri, mode: LaunchMode.externalApplication); // open browser
  } // end download helper

  @override
  Widget build(BuildContext context) { // build UI
    return AnimatedBuilder( // listen to VM changes
      animation: widget.vm, // VM is a ChangeNotifier
      builder: (context, _) { // rebuild callback
        final vm = widget.vm; // local shortcut
        final hasPreview = vm.singleRowPreview != null; // preview exists?
        final canDownload = (vm.singleRowCsvPath ?? "").trim().isNotEmpty; // can download?

        return Scaffold( // screen scaffold
          appBar: AppBar( // top bar
            title: const Text("Syllabus Q&A"), // title
          ), // end appbar
          body: Padding( // padding
            padding: const EdgeInsets.all(16), // padding value
            child: Column( // vertical layout
              children: [ // children
                Row( // top row
                  children: [ // row children
                    ElevatedButton.icon( // upload/convert button
                      onPressed: vm.converting ? null : _pickAndConvert, // disable while converting
                      icon: vm.converting // spinner while converting
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.upload_file),
                      label: Text(vm.converting ? "Converting..." : "Upload PDF"),
                    ), // end button
                    const SizedBox(width: 12), // spacing
                    if (vm.hasConverted) // if conversion ready
                      Text("✅ Ready", style: Theme.of(context).textTheme.bodyMedium),
                  ], // end row children
                ), // end row

                const SizedBox(height: 12), // spacing

                if (hasPreview) ...[
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      "Single-row CSV Preview",
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Expanded(
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.black12),
                      ),
                      child: SingleChildScrollView(
                        child: Text(
                          vm.singleRowPreview!,
                          style: const TextStyle(fontFamily: "monospace", fontSize: 12),
                        ),
                      ),
                    ),
                  ),
                ] else ...[
                  const Spacer(),
                ],

                const SizedBox(height: 12),

                TextField(
                  controller: questionCtrl,
                  decoration: const InputDecoration(
                    labelText: "Ask a question",
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 8),

                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton(
                        onPressed: vm.asking ? null : _ask, // ✅ uses helper that is context-safe
                        child: vm.asking
                            ? const SizedBox(
                                height: 18,
                                width: 18,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Text("Ask"),
                      ),
                    ),
                    const SizedBox(width: 10),
                    OutlinedButton.icon(
                      onPressed: canDownload ? _downloadSingleRowCsv : null, // ✅ only enable when we have path
                      icon: const Icon(Icons.download),
                      label: const Text("Download"),
                    ),
                  ],
                ),

                if (vm.answer != null) ...[
                  const SizedBox(height: 10),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      vm.answer!,
                      style: Theme.of(context).textTheme.bodyLarge,
                    ),
                  )
                ],
              ],
            ),
          ),
        );
      },
    );
  } // end build
} // end state class
