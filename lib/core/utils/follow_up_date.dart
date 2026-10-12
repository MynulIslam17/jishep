/// Default follow-up date: one week from today, formatted MM/dd/yyyy.
String defaultFollowUpDate([DateTime? from]) {
  final date = (from ?? DateTime.now()).add(const Duration(days: 7));
  String two(int v) => v.toString().padLeft(2, '0');
  return '${two(date.month)}/${two(date.day)}/${date.year}';
}
