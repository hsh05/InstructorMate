// lib/utils/schedule_utils.dart

class ScheduleUtils {
  static const Map<String, int> dayMap = {
    'mon': DateTime.monday,
    'tue': DateTime.tuesday,
    'wed': DateTime.wednesday,
    'thu': DateTime.thursday,
    'fri': DateTime.friday,
    'sat': DateTime.saturday,
    'sun': DateTime.sunday,
  };

  /// Handles "Mon", "Monday", "mon", "MONDAY" — normalised to first 3 chars.
  /// Always trims whitespace first (CSV round-trips add leading spaces).
  static int? weekdayFor(String day) {
    final trimmed = day.trim();
    if (trimmed.length < 3) return null;
    return dayMap[trimmed.toLowerCase().substring(0, 3)];
  }

  /// Formats 24-h "HH:mm" → "h:mm AM/PM". Returns raw string on parse failure.
  static String formatTime(String hhmm) {
    if (hhmm.isEmpty) return '';
    final parts = hhmm.split(':');
    if (parts.length < 2) return hhmm;
    final h = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    if (h == null || m == null) return hhmm;
    final period = h >= 12 ? 'PM' : 'AM';
    final displayH = h == 0 ? 12 : (h > 12 ? h - 12 : h);
    return '$displayH:${m.toString().padLeft(2, '0')} $period';
  }
}
