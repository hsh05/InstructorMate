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

  String? singleRowCsvPath; // backend output path for single-row csv
  String? chunksCsvPath; // backend output path for chunks csv

  String? singleRowPreview; // preview text of single-row csv
  String? answer; // latest Q&A answer text

  bool get hasConverted => (singleRowCsvPath ?? "").isNotEmpty && (chunksCsvPath ?? "").isNotEmpty; // conversion done?

  void init() { // optional init hook
    // currently nothing required, but kept for scalability (best practice) // comment
  } // end init

  Future<void> convert({ // convert PDF upload
    required Uint8List pdfBytes, // pdf bytes
    required String fileName, // pdf file name
  }) async {
    converting = true; // set busy flag
    asking = false; // stop asking flag if any
    error = null; // clear previous error
    answer = null; // clear previous answer
    singleRowPreview = null; // clear preview
    singleRowCsvPath = null; // clear old paths
    chunksCsvPath = null; // clear old paths
    notifyListeners(); // update UI

    try { // protect API call
      final res = await api.convertUpload(pdfBytes: pdfBytes, fileName: fileName); // call backend convert-upload
      singleRowCsvPath = (res["single_row_csv"] ?? "").toString(); // read single-row csv path
      chunksCsvPath = (res["chunks_csv"] ?? "").toString(); // read chunks csv path

      if ((singleRowCsvPath ?? "").isNotEmpty) { // if we got a valid path
        singleRowPreview = await api.fetchCsvText(csvPath: singleRowCsvPath!); // fetch preview text
      } // end preview fetch
    } catch (e) { // catch failures
      error = e.toString(); // store error for UI
    } finally { // always end
      converting = false; // clear busy flag
      notifyListeners(); // update UI
    } // end finally
  } // end convert

  Future<void> askQuestion(String question) async { // ask question using chunks file
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
      answer = await api.askFromChunksPath( // call backend ask endpoint
        question: q, // question text
        chunksCsvPath: chunksCsvPath!, // chunks csv path
      ); // end call
    } catch (e) { // catch failures
      error = e.toString(); // store error
    } finally { // always end
      asking = false; // clear asking flag
      notifyListeners(); // update UI
    } // end finally
  } // end askQuestion
} // end ViewModel
