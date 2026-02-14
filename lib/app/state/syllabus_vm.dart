// lib/app/state/syllabus_vm.dart // file path comment
import 'dart:typed_data'; // Uint8List type
import 'package:flutter/foundation.dart'; // ChangeNotifier

import '../api_client.dart'; // ApiClient

class SyllabusViewModel extends ChangeNotifier { // ViewModel class (state holder)
  SyllabusViewModel({required this.api}); // constructor
  final ApiClient api; // injected API dependency

  bool converting = false; // UI flag: conversion in progress
  bool asking = false; // UI flag: ask in progress
  String? error; // last error message if any

  // ✅ NEW: stable identifier from backend (no filesystem paths in UI)
  String? docId; // backend document id

  String? singleRowPreview; // preview text of single-row csv
  String? answer; // latest Q&A answer text

  bool get hasConverted => (docId ?? "").trim().isNotEmpty; // conversion done?

  void init() { // optional init hook
    // currently nothing required, but kept for scalability (best practice)
  } // end init

  void _resetForNewConversion() { // reset state before new conversion
    asking = false; // stop asking state
    error = null; // clear previous error
    answer = null; // clear previous answer
    singleRowPreview = null; // clear preview
    docId = null; // clear doc id
  } // end reset helper

  Future<void> convert({ // convert PDF upload
    required Uint8List pdfBytes, // pdf bytes
    required String fileName, // pdf file name
  }) async {
    converting = true; // set busy flag
    _resetForNewConversion(); // clear old state
    notifyListeners(); // update UI

    try { // protect API call
      final id = await api.convertUploadGetDocId( // call backend convert-upload
        pdfBytes: pdfBytes, // bytes
        fileName: fileName, // name
      ); // end call

      docId = id; // store doc id

      // ✅ fetch preview by docId
      singleRowPreview = await api.fetchCsvTextByDocId( // fetch preview text
        docId: docId!, // doc id
        kind: "single_row", // preview single row csv
      ); // end preview fetch
    } catch (e) { // catch failures
      error = e.toString(); // store error for UI
    } finally { // always end
      converting = false; // clear busy flag
      notifyListeners(); // update UI
    } // end finally
  } // end convert

  Future<void> askQuestion(String question) async { // ask question using doc id
    final q = question.trim(); // normalize question
    if (q.isEmpty) return; // ignore empty questions

    if (!hasConverted) { // if conversion not done yet
      error = "Please upload/convert a PDF first."; // show message
      notifyListeners(); // update UI
      return; // stop
    } // end guard

    asking = true; // set asking flag
    error = null; // clear error
    notifyListeners(); // update UI

    try { // protect API call
      answer = await api.ask( // call backend ask endpoint
        question: q, // question text
        docId: docId!, // doc id
      ); // end call
    } catch (e) { // catch failures
      error = e.toString(); // store error
    } finally { // always end
      asking = false; // clear asking flag
      notifyListeners(); // update UI
    } // end finally
  } // end askQuestion
} // end ViewModel
