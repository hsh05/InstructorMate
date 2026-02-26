// lib/utils/schedule_utils.dart
//
// Shared schedule utilities used by both NotificationScheduler (mobile)
// and WebNotificationService (web). Previously _dayMap was duplicated in both.

class ScheduleUtils {
  /// Maps 3-letter day abbreviations (lowercase) → DateTime weekday constants.
  static const Map<String, int> dayMap = {
    'mon': DateTime.monday,
    'tue': DateTime.tuesday,
    'wed': DateTime.wednesday,
    'thu': DateTime.thursday,
    'fri': DateTime.friday,
    'sat': DateTime.saturday,
    'sun': DateTime.sunday,
  };

  /// Returns the weekday int for a raw day string (e.g. "Monday", "Mon", "mon").
  /// Returns null if unrecognised.
  static int? weekdayFor(String day) {
    if (day.length < 3) return null;
    return dayMap[day.toLowerCase().substring(0, 3)];
  }

  /// Formats a 24-h HH:mm time string to a user-friendly "h:mm AM/PM" string.
  /// Falls back to the raw value if it cannot be parsed.
  static String formatTime(String hhmm) {
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
