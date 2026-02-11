// lib/main.dart // file path comment
import 'package:flutter/material.dart'; // Flutter UI

import 'config/app_config.dart'; // AppConfig settings
import 'app/api_client.dart'; // ApiClient
import 'app/state/syllabus_vm.dart'; // SyllabusViewModel
import 'ui/syllabus_home.dart'; // UI screen

void main() => runApp(const SyllabusApp()); // app entry point

class SyllabusApp extends StatelessWidget { // root widget
  const SyllabusApp({super.key}); // const constructor

  @override
  Widget build(BuildContext context) { // build UI tree
    final api = ApiClient( // create API client
      baseUrl: AppConfig.baseUrl, // base URL from config
      timeout: AppConfig.httpTimeout, // timeout from config
    ); // end api

    final vm = SyllabusViewModel(api: api); // create ViewModel

    return MaterialApp( // app wrapper
      title: 'Syllabus Q&A', // title
      debugShowCheckedModeBanner: false, // hide debug
      theme: ThemeData(useMaterial3: true), // use Material 3
      home: SyllabusHome(vm: vm), // show home screen
    ); // end MaterialApp
  } // end build
} // end class
