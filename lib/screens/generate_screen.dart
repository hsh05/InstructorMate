import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import '../models/config_model.dart';
import '../models/course_model.dart';
import '../models/question_model.dart';
import '../services/api_service.dart';
import '../services/openai_service.dart';
import 'review_screen.dart';

class GenerateScreen extends StatefulWidget {
  const GenerateScreen({super.key});

  @override
  State<GenerateScreen> createState() => _GenerateScreenState();
}

class _GenerateScreenState extends State<GenerateScreen> {
  final List<File> _selectedFiles = [];
  final OpenAIService _aiService = OpenAIService();
  final ApiService _apiService = ApiService();

  List<Course> _courses = [];
  Course? _selectedCourse;

  // New: Track which database materials are selected for the quiz
  final Set<int> _selectedMaterialIds = {};

  String? _statusMessage;
  bool _isLoading = false;

  final Map<String, QuestionTypeConfig> _configs = {
    'MCQ': QuestionTypeConfig(name: 'Multiple Choice', isSelected: true, count: 10),
    'Essay': QuestionTypeConfig(name: 'Essay', isSelected: false, count: 2),
    'True/False': QuestionTypeConfig(name: 'True/False', isSelected: false, count: 5),
  };

  @override
  void initState() {
    super.initState();
    _loadCourses();
  }

  Future<void> _loadCourses() async {
    setState(() {
      _isLoading = true;
      _statusMessage = "Loading courses...";
    });
    try {
      var courses = await _apiService.fetchCourses();
      setState(() {
        _courses = courses;
        if (_courses.isNotEmpty && _selectedCourse == null) {
          _selectedCourse = _courses.first;
        } else if (_selectedCourse != null) {
          _selectedCourse = _courses.firstWhere(
            (c) => c.id == _selectedCourse!.id,
            orElse: () => _courses.first,
          );
        }
        _statusMessage = "Ready";
      });
    } catch (e) {
      setState(() => _statusMessage = "Could not connect to database.");
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _uploadToDatabase() async {
    if (_selectedCourse == null || _selectedFiles.isEmpty) return;
    setState(() {
      _isLoading = true;
      _statusMessage = "Uploading to Server...";
    });

    try {
      for (var file in _selectedFiles) {
        await _apiService.uploadMaterial(_selectedCourse!.id, file, 'slides');
      }
      setState(() {
        _statusMessage = "Upload complete!";
        _selectedFiles.clear();
      });
      _loadCourses();
    } catch (e) {
      setState(() => _statusMessage = "Upload Error: $e");
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  void dispose() {
    for (var config in _configs.values) {
      config.topicController.dispose();
    }
    super.dispose();
  }

  Future<void> _pickFiles() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf', 'pptx', 'txt'],
      allowMultiple: true,
    );
    if (result != null) {
      setState(() {
        _selectedFiles.addAll(result.paths.map((path) => File(path!)).toList());
        _statusMessage = "Ready to upload.";
      });
    }
  }

  void _generateQuiz() async {
    // Check if at least one material is selected from the checkboxes
    if (_selectedCourse == null || _selectedMaterialIds.isEmpty) {
      setState(() => _statusMessage = "Error: Please select at least one material.");
      return;
    }

    setState(() {
      _isLoading = true;
      _statusMessage = "AI is reading selected materials...";
    });

    try {
      var activeConfigs = _configs.values.where((c) => c.isSelected && c.count > 0).toList();

      // FIXED: Pass selected IDs to the service. 
      // The Service now returns the List<QuizQuestion> directly.
      List<QuizQuestion> questions = await _aiService.generateQuiz(
        _selectedCourse!.id,
        activeConfigs,
        _selectedMaterialIds.toList(),
      );

      if (mounted) {
        Navigator.push(context, MaterialPageRoute(
          builder: (context) => ReviewScreen(questions: questions),
        ));
      }
    } catch (e) {
      setState(() => _statusMessage = "Generation Error: $e");
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _showSettings() {
    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setDialogState) {
            return AlertDialog(
              title: const Row(
                children: [
                  Icon(Icons.tune, color: Colors.indigo), 
                  SizedBox(width: 10), 
                  Text("Configure Options")
                ],
              ),
              content: SizedBox(
                width: double.maxFinite,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: _configs.values.map((config) {
                      return Card(
                        margin: const EdgeInsets.only(bottom: 10),
                        elevation: config.isSelected ? 2 : 0,
                        shape: RoundedRectangleBorder(
                          side: BorderSide(color: config.isSelected ? Colors.indigo : Colors.grey.shade300),
                          borderRadius: BorderRadius.circular(8)
                        ),
                        child: Column(
                          children: [
                            // THE TOGGLE
                            CheckboxListTile(
                              title: Text(config.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                              value: config.isSelected,
                              activeColor: Colors.indigo,
                              onChanged: (val) {
                                setDialogState(() { config.isSelected = val ?? false; });
                                setState(() {}); // Update main screen button logic
                              }
                            ),
                            // THE EXPANDED OPTIONS
                            if (config.isSelected)
                              Padding(
                                padding: const EdgeInsets.only(left: 15, right: 15, bottom: 15),
                                child: Column(
                                  children: [
                                    Row(
                                      children: [
                                        Expanded(
                                          child: TextFormField(
                                            initialValue: config.count.toString(),
                                            keyboardType: TextInputType.number,
                                            decoration: const InputDecoration(labelText: "Count", isDense: true, border: OutlineInputBorder()),
                                            onChanged: (val) => config.count = int.tryParse(val) ?? 0,
                                          ),
                                        ),
                                        const SizedBox(width: 10),
                                        Expanded(
                                          child: DropdownButtonFormField<String>(
                                            value: config.difficulty,
                                            decoration: const InputDecoration(labelText: "Difficulty", isDense: true, border: OutlineInputBorder()),
                                            items: ['Easy', 'Medium', 'Hard'].map((d) => DropdownMenuItem(value: d, child: Text(d))).toList(),
                                            onChanged: (val) {
                                              setDialogState(() { config.difficulty = val!; });
                                            },
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 10),
                                    TextField(
                                      controller: config.topicController,
                                      decoration: const InputDecoration(
                                        labelText: "Optional Info / Focus",
                                        hintText: "e.g., Focus on Chapter 2",
                                        isDense: true,
                                        border: OutlineInputBorder()
                                      ),
                                    )
                                  ],
                                ),
                              )
                          ],
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Cancel")),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.indigo, foregroundColor: Colors.white),
                  onPressed: () {
                    Navigator.pop(ctx);
                    _generateQuiz(); // Start the generation
                  },
                  child: const Text("Confirm & Generate"),
                )
              ],
            );
          }
        );
      }
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("InstructorMate"),
        actions: [IconButton(icon: const Icon(Icons.refresh), onPressed: _loadCourses)],
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_courses.isEmpty)
              const Text("No courses found. Create one via API first.", style: TextStyle(color: Colors.red))
            else
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                decoration: BoxDecoration(border: Border.all(color: Colors.grey), borderRadius: BorderRadius.circular(8)),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<Course>(
                    value: _selectedCourse,
                    isExpanded: true,
                    hint: const Text("Select a Course"),
                    items: _courses.map((course) => DropdownMenuItem(
                      value: course,
                      child: Text("${course.title} (${course.materials.length} files in DB)"),
                    )).toList(),
                    onChanged: (val) {
                      setState(() {
                        _selectedCourse = val;
                        _selectedMaterialIds.clear(); // Reset selections when switching courses
                        _statusMessage = "Selected: ${val?.title}";
                      });
                    },
                  ),
                ),
              ),

            const SizedBox(height: 15),

            // FILE SELECTION SECTION
            if (_selectedCourse != null && _selectedCourse!.materials.isNotEmpty)
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text("Select Materials for Quiz:", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.indigo)),
                  const SizedBox(height: 5),
                  ..._selectedCourse!.materials.map((material) {
                    bool isChecked = _selectedMaterialIds.contains(material.id);
                    return Card(
                      color: isChecked ? Colors.indigo.shade50 : Colors.white,
                      margin: const EdgeInsets.only(bottom: 5),
                      child: CheckboxListTile(
                        dense: true,
                        title: Text(material.fileName, style: const TextStyle(fontWeight: FontWeight.w500)),
                        subtitle: Text("Type: ${material.materialType}"),
                        value: isChecked,
                        onChanged: (bool? val) {
                          setState(() {
                            if (val == true) {
                              _selectedMaterialIds.add(material.id);
                            } else {
                              _selectedMaterialIds.remove(material.id);
                            }
                          });
                        },
                      ),
                    );
                  }).toList(),
                ],
              ),

            const SizedBox(height: 10),
            const Divider(),
            
            // LOCAL FILES SECTION
            const Text("Local Files (Pending Upload):", style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 5),
            Expanded(
              child: _selectedFiles.isEmpty
                  ? Center(child: Text("Select local files to upload to the DB.", style: TextStyle(color: Colors.grey[600])))
                  : ListView.builder(
                      itemCount: _selectedFiles.length,
                      itemBuilder: (ctx, i) => Card(
                        child: ListTile(
                          leading: const Icon(Icons.file_upload, color: Colors.orange),
                          title: Text(_selectedFiles[i].path.split(Platform.pathSeparator).last),
                          trailing: IconButton(icon: const Icon(Icons.delete), onPressed: () => setState(() => _selectedFiles.removeAt(i))),
                        ),
                      ),
                    ),
            ),

            const SizedBox(height: 10),

            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                ElevatedButton.icon(
                  icon: const Icon(Icons.add),
                  onPressed: _pickFiles,
                  label: const Text("Add Slides"),
                ),
                ElevatedButton.icon(
                  icon: const Icon(Icons.cloud_upload),
                  onPressed: (_isLoading || _selectedFiles.isEmpty || _selectedCourse == null) ? null : _uploadToDatabase,
                  label: const Text("Upload to DB"),
                ),
              ],
            ),
            
            const SizedBox(height: 15),

            // FIXED GENERATE BUTTON
            SizedBox(
              height: 55,
              child: ElevatedButton(
                onPressed: (_isLoading || _selectedCourse == null || _selectedMaterialIds.isEmpty)
                  ? null
                  : _showSettings,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.indigo,
                  foregroundColor: Colors.white, // Ensures the text/icon is visible (White)
                  disabledBackgroundColor: Colors.grey,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: _isLoading
                    ? const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)),
                          SizedBox(width: 15),
                          Text("AI is Thinking...", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                        ],
                      )
                    : const Text("Generate Quiz from Selected", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ),
            ),

            const SizedBox(height: 10),
            Text(_statusMessage ?? "Ready", textAlign: TextAlign.center, style: const TextStyle(fontStyle: FontStyle.italic)),
          ],
        ),
      ),
    );
  }
}