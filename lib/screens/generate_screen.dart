import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import '../models/config_model.dart';
import '../models/course_model.dart';
import '../models/question_model.dart';
import '../services/api_service.dart';
import '../services/openai_service.dart';
import 'review_screen.dart';
import '../app/state/workspaces_vm.dart';

class GenerateScreen extends StatefulWidget {
  final WorkspacesViewModel vm; 

  const GenerateScreen({super.key, required this.vm});

  @override
  State<GenerateScreen> createState() => _GenerateScreenState();
}

class _GenerateScreenState extends State<GenerateScreen> {
  final List<File> _selectedFiles = [];
  final OpenAIService _aiService = OpenAIService();
  final ApiService _apiService = ApiService();

  List<Course> _courses = [];
  Course? _selectedCourse;

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
      _statusMessage = "Loading course data...";
    });
    
    try {
      // 1. Fetch EVERYTHING from the database
      var allCourses = await _apiService.fetchCourses();
      
      setState(() {
        // 2. Get the exact name of the currently open Workspace
        final workspaceName = widget.vm.current?.title.trim().toLowerCase() ?? '';

        if (workspaceName.isNotEmpty) {
          // 3. STRICT FILTER: Only keep the course that exactly matches the workspace name
          var matchedCourses = allCourses.where(
            (c) => c.title.trim().toLowerCase() == workspaceName
          ).toList();
          
          if (matchedCourses.isNotEmpty) {
            _courses = matchedCourses; // The dropdown will now ONLY have this 1 course
            _selectedCourse = _courses.first;
            
            // Auto-check the real materials!
            _selectedMaterialIds.clear();
            _selectedMaterialIds.addAll(_selectedCourse!.materials.map((m) => m.id));
            
            _statusMessage = "Locked to Workspace: ${_selectedCourse!.title}";
          } else {
            // If the names don't match, it means they haven't uploaded to DB for this specific workspace yet
            _courses = [];
            _selectedCourse = null;
            _statusMessage = "No DB files for this workspace yet. Use Local Files.";
          }
        } else {
          // Fallback just in case they open the screen without a workspace
          _courses = allCourses;
          if (_courses.isNotEmpty) _selectedCourse = _courses.first;
          _statusMessage = "Ready";
        }
      });
    } catch (e) {
      setState(() => _statusMessage = "Error fetching from DB: $e");
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
        _selectedFiles.clear(); // Clears local files so they don't get double generated
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
      // ADDED 'docx' here!
      allowedExtensions: ['pdf', 'pptx', 'docx', 'txt'],
      allowMultiple: true,
    );
    if (result != null) {
      setState(() {
        _selectedFiles.addAll(result.paths.map((path) => File(path!)).toList());
        _statusMessage = "Ready to upload or generate.";
      });
    }
  }

  void _generateQuiz() async {
    // Check if we have SOMETHING to generate from (either local files or DB files)
    bool hasLocalFiles = _selectedFiles.isNotEmpty;
    bool hasDbFiles = _selectedMaterialIds.isNotEmpty;

    if (!hasLocalFiles && !hasDbFiles) {
      setState(() => _statusMessage = "Error: Please select at least one material.");
      return;
    }

    setState(() {
      _isLoading = true;
      _statusMessage = "AI is reading selected materials...";
    });

    try {
      List<QuizQuestion> allQuestions = [];
      var activeConfigs = _configs.values.where((c) => c.isSelected && c.count > 0).toList();

      // 1. Generate from Local Files (Direct to RAM)
      if (hasLocalFiles) {
        for (var file in _selectedFiles) {
          // FIXED: Now passing activeConfigs along with the file
          var questions = await _apiService.generateDirectlyFromFile(file, activeConfigs);
          allQuestions.addAll(questions);
        }
      }

      // 2. Generate from Database Materials
      if (hasDbFiles && _selectedCourse != null) {
        var questions = await _aiService.generateQuiz(
          _selectedCourse!.id,
          activeConfigs,
          _selectedMaterialIds.toList(),
        );
        allQuestions.addAll(questions);
      }

      // 3. Navigate to Review Screen with combined questions
      if (mounted && allQuestions.isNotEmpty) {
        Navigator.push(context, MaterialPageRoute(
          builder: (context) => ReviewScreen(questions: allQuestions),
        ));
      } else if (allQuestions.isEmpty) {
        setState(() => _statusMessage = "Generation succeeded, but AI returned no questions.");
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
                            CheckboxListTile(
                              title: Text(config.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                              value: config.isSelected,
                              activeColor: Colors.indigo,
                              onChanged: (val) {
                                setDialogState(() { config.isSelected = val ?? false; });
                                setState(() {}); 
                              }
                            ),
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
                    _generateQuiz(); 
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
    
    bool hasLocalSelection = _selectedFiles.isNotEmpty;
    bool hasDbSelection = _selectedMaterialIds.isNotEmpty;
    bool isGenerateReady = hasLocalSelection || hasDbSelection;

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
              Text(_statusMessage ?? "No workspace detected.", style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold))
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
                        _selectedMaterialIds.clear(); 
                        _statusMessage = "Selected: ${val?.title}";
                      });
                    },
                  ),
                ),
              ),

            const SizedBox(height: 15),

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
            
            const Text("Local Files (Pending Upload):", style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 5),
            Expanded(
              child: _selectedFiles.isEmpty
                  ? Center(child: Text("Select local files to generate directly or upload to DB.", style: TextStyle(color: Colors.grey[600])))
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

            SizedBox(
              height: 55,
              child: ElevatedButton(
                // The button is now clickable if ANY files are selected (DB or Local)
                onPressed: (_isLoading || !isGenerateReady) ? null : _showSettings,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.indigo,
                  foregroundColor: Colors.white, 
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