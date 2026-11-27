String todayDateString([DateTime? now]) {
  final d = now ?? DateTime.now();
  return '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}

String formatTimeHm(DateTime dt) {
  final local = dt.toLocal();
  return '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
}

String formatMonthDay(DateTime dt) {
  final local = dt.toLocal();
  final today = todayDateString();
  final dateStr = todayDateString(local);
  if (dateStr == today) return '今天';
  final yesterday = todayDateString(DateTime.now().subtract(const Duration(days: 1)));
  if (dateStr == yesterday) return '昨天';
  return '${local.month}月${local.day}日';
}

String formatOrderDateLabel(String orderDate) {
  final today = todayDateString();
  if (orderDate.isEmpty || orderDate == today) return '今天';
  final tomorrow = todayDateString(DateTime.now().add(const Duration(days: 1)));
  if (orderDate == tomorrow) return '明天';
  final parts = orderDate.split('-');
  if (parts.length == 3) {
    final m = int.tryParse(parts[1]) ?? 0;
    final d = int.tryParse(parts[2]) ?? 0;
    if (m > 0 && d > 0) return '$m月$d日';
  }
  return orderDate;
}

String mealScheduleText({
  required String orderDate,
  required String mealTimeType,
  String? start,
  String? end,
}) {
  final dayLabel = formatOrderDateLabel(orderDate);
  final s = (start ?? '').trim();
  final e = (end ?? '').trim();
  if (mealTimeType == 'asap') {
    return dayLabel == '今天' ? '尽快' : '$dayLabel 尽快';
  }
  if (mealTimeType == 'point') {
    final t = s.isNotEmpty ? s : '待定';
    return dayLabel == '今天' ? t : '$dayLabel $t';
  }
  if (mealTimeType == 'range') {
    final rangeStr = e.isNotEmpty ? '$s–$e' : '$s 之后';
    return dayLabel == '今天' ? rangeStr : '$dayLabel $rangeStr';
  }
  return dayLabel;
}

int _minutesOfDay(String hhmm) {
  final parts = hhmm.split(':');
  if (parts.length != 2) return -1;
  final h = int.tryParse(parts[0]) ?? -1;
  final m = int.tryParse(parts[1]) ?? -1;
  if (h < 0 || h > 23 || m < 0 || m > 59) return -1;
  return h * 60 + m;
}

String? validateMealSchedule({
  required String orderDate,
  required String mealTimeType,
  String? start,
  String? end,
}) {
  final today = todayDateString();
  if (orderDate.compareTo(today) < 0) {
    return '就餐日期不能早于今天';
  }
  if (mealTimeType == 'asap') {
    if (orderDate != today) {
      return '「尽快」只能用在今天，预约其他日期请选择时间';
    }
    return null;
  }
  final s = (start ?? '').trim();
  final sm = _minutesOfDay(s);
  if (sm < 0) return '请选择开始时间';
  if (mealTimeType == 'range') {
    final e = (end ?? '').trim();
    if (e.isNotEmpty) {
      final em = _minutesOfDay(e);
      if (em < 0) return '结束时间格式不正确';
      if (em <= sm) return '结束时间要晚于开始时间';
    }
  }
  return null;
}

const List<String> quickMealTimes = [
  '12:00',
  '12:30',
  '18:00',
  '18:30',
  '19:00',
  '19:30',
];
