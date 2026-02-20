// lib/ui/workspace_detail.dart
import 'package:flutter/material.dart';
import '../app/state/workspaces_vm.dart';
import '../app/workspace_models.dart';


class WorkspaceDetailPage extends StatefulWidget {
  const WorkspaceDetailPage({super.key, required this.vm});
  final WorkspacesViewModel vm;

  @override
  State<WorkspaceDetailPage> createState() => _WorkspaceDetailPageState();
}

class _WorkspaceDetailPageState extends State<WorkspaceDetailPage> {
  final Map<String, TextEditingController> _controllers = {};

  TextEditingController _controller(String key, String value) {
    return _controllers.putIfAbsent(
      key,
      () => TextEditingController(text: value),
    );
  }

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final vm = widget.vm;
    final ws = vm.current;

    if (ws == null) {
      return const Scaffold(
        body: Center(child: Text("No workspace selected.")),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(ws.title),
      ),
      body: vm.loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _courseInfoCard(ws),
                const SizedBox(height: 16),
                _sectionsCard(ws),
                const SizedBox(height: 16),
                _studentsCard(ws),
              ],
            ),
    );
  }

  // --------------------------------------------------
  // COURSE INFO
  // --------------------------------------------------
  Widget _courseInfoCard(Workspace ws) {
    final editableKeys = <String>[
      "semester",
      "office_hours",
      "instructor_email",
      "course_code",
      "course_name",
    ];

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "Course Information",
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 12),

            ...editableKeys.map((key) {
              final value = ws.fields[key] ?? "";
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: TextField(
                  controller: _controller(key, value),
                  decoration: InputDecoration(
                    labelText: key,
                    border: const OutlineInputBorder(),
                  ),
                ),
              );
            }),

            const SizedBox(height: 10),

            ElevatedButton.icon(
              onPressed: () async {
                final updated = <String, String>{};
                for (final key in editableKeys) {
                  updated[key] =
                      _controllers[key]?.text.trim() ?? "";
                }

                await widget.vm.updateFields(updated);

                if (mounted && widget.vm.error != null) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(widget.vm.error!)),
                  );
                }
              },
              icon: const Icon(Icons.save),
              label: const Text("Save Changes"),
            ),
          ],
        ),
      ),
    );
  }

  // --------------------------------------------------
  // SECTIONS
  // --------------------------------------------------
  Widget _sectionsCard(Workspace ws) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "Sections",
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 12),

            if (ws.sections.isEmpty)
              const Text("No sections added yet."),

            ...ws.sections.map((section) {
              return ListTile(
                title: Text(section.name.isEmpty
                    ? section.id
                    : section.name),
                subtitle: Text(
                  "${section.schedule.days.join(", ")} "
                  "${section.schedule.startTime} - "
                  "${section.schedule.endTime} "
                  "(${section.schedule.timezone})",
                ),
              );
            }),

            const SizedBox(height: 10),

            ElevatedButton.icon(
              onPressed: () async {
                final draft = SectionDraft()
                  ..name = "Section 01"
                  ..days = const ["Mon", "Wed"]
                  ..startTime = "09:00"
                  ..endTime = "10:15"
                  ..timezone = "UTC"
                  ..reminderMinutes = 10;

                try {
                  final updated = await widget.vm.api
                      .createSection(ws.id, draft);

                  widget.vm.current = updated;
                  widget.vm.notifyListeners();
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(e.toString())),
                    );
                  }
                }
              },
              icon: const Icon(Icons.add),
              label: const Text("Add Section"),
            ),
          ],
        ),
      ),
    );
  }

  // --------------------------------------------------
  // STUDENTS
  // --------------------------------------------------
  Widget _studentsCard(Workspace ws) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "Students",
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 10),

            Text("Total students: ${ws.studentsCount}"),

            const SizedBox(height: 12),

            ElevatedButton.icon(
              onPressed: () async {
                await widget.vm.importStudents();
                if (mounted && widget.vm.error != null) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(widget.vm.error!)),
                  );
                }
              },
              icon: const Icon(Icons.upload_file),
              label: const Text("Import Student List (CSV)"),
            ),
          ],
        ),
      ),
    );
  }
}
