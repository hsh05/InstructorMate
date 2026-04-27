// lib/screens/workspace/statistics_screen.dart

import 'package:flutter/material.dart';
import '../../services/api_service.dart';
import '../../utils/file_saver.dart';

class StatisticsScreen extends StatefulWidget {
  final int workspaceId;
  final String sectionId;
  final String courseTitle;

  const StatisticsScreen({
    super.key,
    required this.workspaceId,
    required this.sectionId,
    required this.courseTitle,
  });

  @override
  State<StatisticsScreen> createState() => _StatisticsScreenState();
}

class StudentStats {
  int present = 0;
  int absent = 0;
  int excused = 0;
}

class _StatisticsScreenState extends State<StatisticsScreen> {
  final ApiService api = ApiService();

  bool loading = true;
  int totalLectures = 0;

  Map<String, StudentStats> stats = {};
  Map<String, String> studentNames = {};

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    loadStats();
  }

  Future<void> loadStats() async {
    setState(() => loading = true);

    try {
      final lectures = await api.getAvailableLectures(
        workspaceId: widget.workspaceId,
        sectionId: widget.sectionId,
      );

      totalLectures = lectures.length;

      final students = await api.getStudentsForSection(
        workspaceId: widget.workspaceId,
        sectionId: widget.sectionId,
      );

      stats.clear();
      studentNames.clear();

      for (var s in students) {
        stats[s['student_id']] = StudentStats();
        studentNames[s['student_id']] = s['name'];
      }

      final futures = lectures.map((lec) {
        return api.getAttendanceForLecture(
          workspaceId: widget.workspaceId,
          sectionId: widget.sectionId,
          lectureNumber: lec,
        );
      }).toList();

      final results = await Future.wait(futures);

      for (var rows in results) {
        for (var r in rows) {
          final id = r['student_id'];
          final status = r['status'];

          final st = stats[id]!;

          if (status == 'Present')
            st.present++;
          else if (status == 'Absent')
            st.absent++;
          else
            st.excused++;
        }
      }
    } catch (e) {
      print("Stats error: $e");
    }

    setState(() => loading = false);
  }

  // ======================
  // Warning logic
  // ======================
  String getWarning(int missed) {
    if (missed >= 10) return "3rd Warning ❌";
    if (missed >= 8) return "2nd Warning 🚨";
    if (missed >= 4) return "1st Warning ⚠️";
    return "Safe ✅";
  }

  Color getColor(int missed) {
    if (missed >= 10) return Colors.red;
    if (missed >= 8) return Colors.orange;
    if (missed >= 4) return Colors.amber;
    return Colors.green;
  }

  double getAttendancePercent(StudentStats s) {
    if (totalLectures == 0) return 0;
    return (s.present / totalLectures) * 100;
  }

  @override
  Widget build(BuildContext context) {
    final sortedEntries = stats.entries.toList()
      ..sort((a, b) {
        int getRiskLevel(int absent) {
          if (absent >= 10) return 3;
          if (absent >= 8) return 2;
          if (absent >= 4) return 1;
          return 0;
        }

        final aRisk = getRiskLevel(a.value.absent);
        final bRisk = getRiskLevel(b.value.absent);

        if (aRisk != bRisk) return bRisk.compareTo(aRisk);
        return b.value.absent.compareTo(a.value.absent);
      });

    return Scaffold(
      appBar: AppBar(title: Text("${widget.courseTitle} - Statistics")),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: loadStats,
              child: ListView(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      alignment: WrapAlignment.center,
                      children: [
                        summaryCard(
                          "Lectures",
                          "$totalLectures",
                          Icons.menu_book, // 📘
                          Colors.blue,
                        ),
                        summaryCard(
                          "Students",
                          "${stats.length}",
                          Icons.people, // 👥
                          Colors.purple,
                        ),
                      ],
                    ),
                  ),

                  const Center(
                    child: Text(
                      "Based on recorded lectures",
                      style: TextStyle(color: Colors.grey),
                    ),
                  ),

                  const SizedBox(height: 10),
                  buildWarningSummary(),
                  const SizedBox(height: 10),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    child: Text(
                      "Students",
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  ...sortedEntries.map((entry) {
                    final id = entry.key;
                    final s = entry.value;

                    final missed = s.absent;
                    final percent = getAttendancePercent(s);

                    return Card(
                      margin: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      elevation: 2,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: ListTile(
                        title: Text(
                          studentNames[id] ?? id,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: missed >= 10
                                ? Colors.red
                                : missed >= 8
                                ? const Color.fromARGB(255, 225, 123, 40)
                                : Colors.black87,
                          ),
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text("Attendance: ${percent.toStringAsFixed(1)}%"),
                            Text(
                              "P: ${s.present} | A: ${s.absent} | E: ${s.excused}",
                            ),
                          ],
                        ),

                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: getColor(missed).withOpacity(.15),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                getWarning(missed),
                                style: TextStyle(
                                  color: getColor(missed),
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),

                            const SizedBox(width: 6),

                            if (missed >= 4)
                              IconButton(
                                icon: const Icon(Icons.download, size: 26),
                                tooltip: "Warning Report",
                                onPressed: () async {
                                  try {
                                    final bytes = await api
                                        .downloadWarningReport(
                                          workspaceId: widget.workspaceId,
                                          sectionId: widget.sectionId,
                                          studentId: id,
                                          absences: missed,
                                        );

                                    final filename =
                                        "${widget.courseTitle}_${widget.sectionId}_Warning_$id.docx";

                                    final savedPath =
                                        await FileSaver.saveToDownloads(
                                          bytes: bytes,
                                          fileName: filename,
                                        );

                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(
                                          'Saved to Downloads:\n$savedPath',
                                        ),
                                      ),
                                    );
                                  } catch (e) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(content: Text("Error: $e")),
                                    );
                                  }
                                },
                              ),
                          ],
                        ),
                      ),
                    );
                  }),
                ],
              ),
            ),
    );
  }

  Widget summaryCard(String title, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
      decoration: BoxDecoration(
        color: color.withOpacity(.08),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Text(
            value,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 15, color: color.withOpacity(.8)),
              const SizedBox(width: 4),
              Text(
                title,
                style: TextStyle(fontSize: 12, color: color.withOpacity(.8)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget buildWarningSummary() {
    int safe = 0, w1 = 0, w2 = 0, w3 = 0;

    for (var s in stats.values) {
      if (s.absent >= 10)
        w3++;
      else if (s.absent >= 8)
        w2++;
      else if (s.absent >= 4)
        w1++;
      else
        safe++;
    }

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 8),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          warningItem("Safe", safe, Colors.green),
          warningItem("1st", w1, Colors.amber),
          warningItem("2nd", w2, Colors.orange),
          warningItem("3rd", w3, Colors.red),
        ],
      ),
    );
  }

  Widget warningItem(String label, int count, Color color) {
    return Column(
      children: [
        Text(
          count.toString(),
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        const SizedBox(height: 4),
        Text(label, style: const TextStyle(fontSize: 12)),
      ],
    );
  }
}