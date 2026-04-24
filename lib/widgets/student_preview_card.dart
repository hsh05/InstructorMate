import 'package:flutter/material.dart';

class StudentCard extends StatelessWidget {
  final Map<String, dynamic> row;
  final int index;
  final VoidCallback onPresent;
  final VoidCallback onAbsent;
  final VoidCallback onExcused;

  const StudentCard({
    super.key,
    required this.row,
    required this.index,
    required this.onPresent,
    required this.onAbsent,
    required this.onExcused,
  });

  Widget statusBtn(String t, bool active, Color c, VoidCallback tap) {
    return OutlinedButton(
      onPressed: tap,
      style: OutlinedButton.styleFrom(
        backgroundColor: active ? c.withOpacity(.15) : null,
        side: BorderSide(color: active ? c : Colors.grey),
      ),
      child: Text(
        t,
        style: TextStyle(
          color: active ? c : Colors.black,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final status = row['Status'] ?? '';
    final confidence = row['Confidence'];

    return Container(
      margin: const EdgeInsets.only(bottom: 5),
      padding: const EdgeInsets.all(5),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade200),
        borderRadius: BorderRadius.circular(14),
        color: Colors.white,
      ),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: Colors.grey.shade200,
            child: Text('${index + 1}'),
          ),
          const SizedBox(width: 8),

          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  row['Name'] ?? '',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                Row(
                  children: [
                    Text(
                      'ID: ${row['StudentID']}',
                      style: TextStyle(color: Colors.grey.shade600),
                    ),

                    const SizedBox(width: 6),

                    if (confidence != null && confidence != "Unknown")
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: confidence == "High confidence"
                              ? Colors.green.withOpacity(0.15)
                              : Colors.orange.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          confidence.replaceAll(" confidence", ""),
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: confidence == "High confidence"
                                ? Colors.green
                                : Colors.orange,
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),

          Row(
            children: [
              statusBtn('P', status == 'Present', Colors.green, onPresent),
              const SizedBox(width: 6),
              statusBtn('A', status == 'Absent', Colors.red, onAbsent),
              const SizedBox(width: 6),
              statusBtn('E', status == 'Excused', Colors.blue, onExcused),
            ],
          ),
        ],
      ),
    );
  }
}
