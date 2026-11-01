import 'package:shared_preferences/shared_preferences.dart';

import 'plans.dart';

/// Free weekly allowance for Pro tools. Weeks start on Monday (local time),
/// matching how tournaments are scheduled.
class UsageQuota {
  UsageQuota(this._prefs, {DateTime Function()? clock})
      : _clock = clock ?? DateTime.now;

  static const _kWeek = 'quota_week';
  static const _kUsed = 'quota_used';

  final SharedPreferences _prefs;
  final DateTime Function() _clock;

  static String weekKey(DateTime d) {
    final monday = DateTime(d.year, d.month, d.day - (d.weekday - 1));
    return '${monday.year}-${monday.month}-${monday.day}';
  }

  int get used {
    if (_prefs.getString(_kWeek) != weekKey(_clock())) return 0;
    return _prefs.getInt(_kUsed) ?? 0;
  }

  int get remaining => (kFreeWeeklyToolUses - used).clamp(0, kFreeWeeklyToolUses);

  DateTime get resetsAt {
    final d = _clock();
    return DateTime(d.year, d.month, d.day - (d.weekday - 1) + 7);
  }

  Future<bool> tryConsume() async {
    final key = weekKey(_clock());
    final current = used;
    if (current >= kFreeWeeklyToolUses) return false;
    await _prefs.setString(_kWeek, key);
    await _prefs.setInt(_kUsed, current + 1);
    return true;
  }
}
