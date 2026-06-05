/// Leave type configuration + day calculations, ported 1:1 from the React
/// RequestLeaveDialog / useLeaveRequests logic.
library;

/// Top-level categories shown in the leave-type dropdown.
const List<String> kLeaveCategories = [
  'Annual Leave',
  'Special Leave',
  'Leave in Lieu',
  'Other Leave',
];

/// Special leave types -> fixed allocated days.
const Map<String, int> kSpecialLeaveTypes = {
  'Wedding Leave': 15,
  'Bereavement Leave': 15,
  'Maternity Leave': 98,
  'Paternity Leave': 22,
};

/// "Other Leave" sub-reasons (stored as "Other Leave - <subtype>").
const List<String> kOtherLeaveSubtypes = [
  'Sick Leave',
  'Extension Request',
  'Medical Emergency',
  'Family Emergency',
  'Travel Complications',
  'Other Emergency',
];

const int kDefaultAnnualDays = 12;

bool isLeaveInLieu(String leaveType) =>
    leaveType.startsWith('Leave in Lieu') || leaveType.startsWith('Leave on Lieu');

bool isOtherLeave(String leaveType) => leaveType.startsWith('Other Leave');

bool isSpecialLeave(String leaveType) => kSpecialLeaveTypes.containsKey(leaveType);

/// Deducts from the shared "Annual Leave" bucket: Annual Leave and
/// "Other Leave - Sick Leave".
bool deductsFromAnnual(String leaveType) =>
    leaveType == 'Annual Leave' || leaveType == 'Other Leave - Sick Leave';

/// Inclusive business days (Mon–Fri) between [start] and [end].
int businessDays(DateTime start, DateTime end) {
  final s = DateTime(start.year, start.month, start.day);
  final e = DateTime(end.year, end.month, end.day);
  if (e.isBefore(s)) return 0;
  var count = 0;
  var d = s;
  while (!d.isAfter(e)) {
    if (d.weekday != DateTime.saturday && d.weekday != DateTime.sunday) count++;
    d = d.add(const Duration(days: 1));
  }
  return count;
}

/// Days a request consumes (matches React):
///  - half day -> 0.5
///  - special  -> fixed allocation
///  - lieu     -> 1
///  - else     -> business days
double computeLeaveDays({
  required String leaveType,
  required DateTime start,
  required DateTime end,
  bool isHalfDay = false,
}) {
  if (isHalfDay) return 0.5;
  if (isSpecialLeave(leaveType)) {
    return kSpecialLeaveTypes[leaveType]!.toDouble();
  }
  if (isLeaveInLieu(leaveType)) return 1;
  return businessDays(start, end).toDouble();
}

/// YYYY-MM-DD from local date components (mirrors formatLocalDate).
String formatDateKey(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

/// Adds [days] allocation to a special-leave start date to get the end date
/// (inclusive), matching the web's auto end-date.
DateTime specialEndDate(DateTime start, int allocatedDays) =>
    start.add(Duration(days: allocatedDays - 1));
