import 'package:flutter/material.dart';
import 'package:table_calendar/table_calendar.dart';
import '../../models/recurring_inspection.dart';
import '../../services/recurring_inspection_service.dart';
import '../../theme/app_theme.dart';
import 'add_recurring_inspection_screen.dart';

class CalendarScreen extends StatefulWidget {
  final String userRole;

  const CalendarScreen({super.key, required this.userRole});

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  final _service = RecurringInspectionService();

  DateTime _focusedDay = DateTime.now();
  DateTime _selectedDay = DateTime.now();
  CalendarFormat _calendarFormat = CalendarFormat.month;

  List<RecurringInspection> _inspections = [];

  /// Pre-computed cache: normalized DateTime (year/month/day only) → events.
  /// Built once after load, and rebuilt whenever inspections change.
  /// Only covers [_cacheStart, _cacheEnd] to avoid unbounded iteration.
  Map<DateTime, List<RecurringInspection>> _eventCache = {};

  // Cache window: 60 days back, 120 days forward from today.
  static const int _cachePastDays   = 60;
  static const int _cacheFutureDays = 120;

  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadInspections();
  }

  // ---------------------------------------------------------------------------
  // Data loading
  // ---------------------------------------------------------------------------

  Future<void> _loadInspections() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = await _service.fetchAll(isActive: true);
      if (!mounted) return;
      setState(() {
        _inspections = list;
        _loading = false;
      });
      _buildEventCache();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  // ---------------------------------------------------------------------------
  // Cache builder — runs once after load, O(days × inspections) but bounded
  // ---------------------------------------------------------------------------

  void _buildEventCache() {
    final cache = <DateTime, List<RecurringInspection>>{};

    final today      = DateTime.now();
    final rangeStart = DateTime(today.year, today.month, today.day)
        .subtract(Duration(days: _cachePastDays));
    final rangeEnd   = DateTime(today.year, today.month, today.day)
        .add(Duration(days: _cacheFutureDays));

    for (var d = rangeStart;
        !d.isAfter(rangeEnd);
        d = d.add(const Duration(days: 1))) {
      final events = _computeEventsForDay(d);
      if (events.isNotEmpty) {
        cache[DateTime(d.year, d.month, d.day)] = events;
      }
    }

    setState(() => _eventCache = cache);
  }

  // ---------------------------------------------------------------------------
  // Core matching logic — called only from _buildEventCache, not per-render
  // ---------------------------------------------------------------------------

  List<RecurringInspection> _computeEventsForDay(DateTime day) {
    final normalDay = DateTime(day.year, day.month, day.day);

    return _inspections.where((ri) {
      // Must have a valid next-due date
      final nextDue = DateTime.tryParse(ri.nextDueDate);
      if (nextDue == null) return false;

      final start = DateTime.tryParse(ri.startDate);
      if (start == null) return false;

      final normalStart = DateTime(start.year, start.month, start.day);

      // Don't show before start date
      if (normalDay.isBefore(normalStart)) return false;

      // Don't show after end date
      if (ri.endDate != null) {
        final end = DateTime.tryParse(ri.endDate!);
        if (end != null) {
          final normalEnd = DateTime(end.year, end.month, end.day);
          if (normalDay.isAfter(normalEnd)) return false;
        }
      }

      final n = ri.interval ?? 1;

      switch (ri.frequency) {
        case 'daily':
          if (n <= 1) return true;
          final diffDays = normalDay.difference(normalStart).inDays;
          return diffDays >= 0 && diffDays % n == 0;

        case 'weekly':
          // day.weekday: 1=Mon..7=Sun  |  ri.dayOfWeek: 0=Mon..6=Sun
          if (normalDay.weekday != (ri.dayOfWeek ?? 0) + 1) return false;
          if (n <= 1) return true;
          final diffWeeks = normalDay.difference(normalStart).inDays ~/ 7;
          return diffWeeks >= 0 && diffWeeks % n == 0;

        case 'monthly':
          if (normalDay.day != (ri.dayOfMonth ?? 1)) return false;
          if (n <= 1) return true;
          final diffMonths = (normalDay.year - normalStart.year) * 12 +
              (normalDay.month - normalStart.month);
          return diffMonths >= 0 && diffMonths % n == 0;

        case 'yearly':
          if (normalDay.month != normalStart.month ||
              normalDay.day   != normalStart.day) return false;
          final diffYears = normalDay.year - normalStart.year;
          return diffYears >= 0 && diffYears % n == 0;

        default:
          return false;
      }
    }).toList();
  }

  // ---------------------------------------------------------------------------
  // Fast O(1) lookup used by TableCalendar's eventLoader
  // ---------------------------------------------------------------------------

  List<RecurringInspection> _getEventsForDay(DateTime day) {
    final key = DateTime(day.year, day.month, day.day);
    return _eventCache[key] ?? [];
  }

  // ---------------------------------------------------------------------------
  // Actions
  // ---------------------------------------------------------------------------

  Future<void> _generateDue() async {
    try {
      final result = await _service.generateDue();
      final count = result['count'] ?? 0;
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(count > 0
            ? '$count inspection(s) generated'
            : 'No inspections due today'),
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.textPrimary,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ));
      _loadInspections();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Error: $e'),
        behavior: SnackBarBehavior.floating,
        backgroundColor: Colors.red,
      ));
    }
  }

  void _openAddScreen([RecurringInspection? existing]) async {
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => AddRecurringInspectionScreen(
          userRole: widget.userRole,
          existing: existing,
        ),
      ),
    );
    if (result == true) _loadInspections();
  }

  // ---------------------------------------------------------------------------
  // UI
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final eventsForSelected = _getEventsForDay(_selectedDay);

    return Scaffold(
      backgroundColor: AppColors.bgPrimary,
      body: SafeArea(
        child: Column(
          children: [
            // Header
            Container(
              color: AppColors.bgSurface,
              padding: const EdgeInsets.fromLTRB(8, 12, 8, 12),
              child: Row(
                children: [
                  IconButton(
                    icon: Icon(Icons.arrow_back_ios_new_rounded,
                        size: 18, color: AppColors.textPrimary),
                    onPressed: () => Navigator.pop(context),
                  ),
                  Expanded(
                    child: Text(
                      'Calendar',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                        letterSpacing: -0.3,
                      ),
                    ),
                  ),
                  if (widget.userRole == 'admin' || widget.userRole == 'fixer')
                    IconButton(
                      icon: Icon(Icons.play_circle_outline_rounded,
                          size: 22, color: AppColors.accent),
                      tooltip: 'Generate due inspections',
                      onPressed: _generateDue,
                    ),
                  if (widget.userRole == 'admin')
                    IconButton(
                      icon: Icon(Icons.add_rounded,
                          size: 22, color: AppColors.accent),
                      tooltip: 'Add recurring inspection',
                      onPressed: () => _openAddScreen(),
                    ),
                ],
              ),
            ),
            Divider(height: 0, thickness: 0.5, color: AppColors.border),

            // Calendar
            Container(
              color: AppColors.bgSurface,
              child: TableCalendar<RecurringInspection>(
                firstDay: DateTime.utc(2024, 1, 1),
                lastDay: DateTime.utc(2030, 12, 31),
                focusedDay: _focusedDay,
                selectedDayPredicate: (day) => isSameDay(_selectedDay, day),
                calendarFormat: _calendarFormat,
                eventLoader: _getEventsForDay, // now O(1)
                startingDayOfWeek: StartingDayOfWeek.monday,
                onDaySelected: (selectedDay, focusedDay) {
                  setState(() {
                    _selectedDay = selectedDay;
                    _focusedDay = focusedDay;
                  });
                },
                onFormatChanged: (format) {
                  setState(() => _calendarFormat = format);
                },
                onPageChanged: (focusedDay) {
                  // Rebuild cache if user navigates outside the current window
                  final today = DateTime.now();
                  final cacheStart = today.subtract(Duration(days: _cachePastDays));
                  final cacheEnd   = today.add(Duration(days: _cacheFutureDays));
                  if (focusedDay.isBefore(cacheStart) ||
                      focusedDay.isAfter(cacheEnd)) {
                    _buildEventCache();
                  }
                  _focusedDay = focusedDay;
                },
                calendarStyle: CalendarStyle(
                  markersMaxCount: 3,
                  markerDecoration: BoxDecoration(
                    color: AppColors.accent,
                    shape: BoxShape.circle,
                  ),
                  todayDecoration: BoxDecoration(
                    color: AppColors.accent.withOpacity(0.3),
                    shape: BoxShape.circle,
                  ),
                  selectedDecoration: BoxDecoration(
                    color: AppColors.accent,
                    shape: BoxShape.circle,
                  ),
                  outsideDaysVisible: false,
                  defaultTextStyle:
                      TextStyle(color: AppColors.textPrimary, fontSize: 13),
                  weekendTextStyle:
                      TextStyle(color: AppColors.textSecondary, fontSize: 13),
                  todayTextStyle: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w600),
                  selectedTextStyle: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w600),
                ),
                headerStyle: HeaderStyle(
                  formatButtonVisible: true,
                  titleCentered: true,
                  formatButtonShowsNext: false,
                  titleTextStyle: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                  formatButtonTextStyle:
                      TextStyle(fontSize: 11, color: AppColors.accent),
                  formatButtonDecoration: BoxDecoration(
                    border: Border.all(
                        color: AppColors.accent.withOpacity(0.5)),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  leftChevronIcon: Icon(Icons.chevron_left,
                      color: AppColors.textSecondary, size: 20),
                  rightChevronIcon: Icon(Icons.chevron_right,
                      color: AppColors.textSecondary, size: 20),
                ),
                daysOfWeekStyle: DaysOfWeekStyle(
                  weekdayStyle: TextStyle(
                      fontSize: 11,
                      color: AppColors.textTertiary,
                      fontWeight: FontWeight.w500),
                  weekendStyle: TextStyle(
                      fontSize: 11,
                      color: AppColors.textTertiary,
                      fontWeight: FontWeight.w500),
                ),
              ),
            ),

            Divider(height: 0, thickness: 0.5, color: AppColors.border),

            // Events list for selected day
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.error_outline,
                                  color: AppColors.textTertiary, size: 40),
                              const SizedBox(height: 8),
                              Text('Failed to load',
                                  style: TextStyle(
                                      color: AppColors.textSecondary,
                                      fontSize: 13)),
                              const SizedBox(height: 8),
                              TextButton(
                                  onPressed: _loadInspections,
                                  child: const Text('Retry')),
                            ],
                          ),
                        )
                      : eventsForSelected.isEmpty
                          ? Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.event_busy_rounded,
                                      color: AppColors.textTertiary
                                          .withOpacity(0.5),
                                      size: 44),
                                  const SizedBox(height: 8),
                                  Text(
                                    'No inspections on this day',
                                    style: TextStyle(
                                        color: AppColors.textTertiary,
                                        fontSize: 13),
                                  ),
                                ],
                              ),
                            )
                          : ListView.separated(
                              padding: const EdgeInsets.all(16),
                              itemCount: eventsForSelected.length,
                              separatorBuilder: (_, __) =>
                                  const SizedBox(height: 8),
                              itemBuilder: (context, index) {
                                return _InspectionCard(
                                  inspection: eventsForSelected[index],
                                  onTap: () =>
                                      _openAddScreen(eventsForSelected[index]),
                                );
                              },
                            ),
            ),
          ],
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Inspection card — unchanged
// -----------------------------------------------------------------------------

class _InspectionCard extends StatelessWidget {
  final RecurringInspection inspection;
  final VoidCallback onTap;

  const _InspectionCard({required this.inspection, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.bgSurface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border, width: 0.5),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: const Color(0xFFDBEAFE),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.checklist_rounded,
                      size: 16, color: Color(0xFF1D4ED8)),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        inspection.title,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        inspection.scheduleDescription,
                        style: TextStyle(
                            fontSize: 11, color: AppColors.textTertiary),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: _frequencyColor(inspection.frequency)
                        .withOpacity(0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    inspection.frequencyLabel,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: _frequencyColor(inspection.frequency),
                    ),
                  ),
                ),
              ],
            ),
            if (inspection.location.isNotEmpty ||
                inspection.departmentName != null) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  if (inspection.departmentName != null) ...[
                    Icon(Icons.business_rounded,
                        size: 12, color: AppColors.textTertiary),
                    const SizedBox(width: 4),
                    Text(
                      inspection.departmentName!,
                      style: TextStyle(
                          fontSize: 11, color: AppColors.textSecondary),
                    ),
                    const SizedBox(width: 12),
                  ],
                  if (inspection.location.isNotEmpty) ...[
                    Icon(Icons.location_on_outlined,
                        size: 12, color: AppColors.textTertiary),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        inspection.location,
                        style: TextStyle(
                            fontSize: 11, color: AppColors.textSecondary),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ],
              ),
            ],
            if (inspection.assignees.isNotEmpty) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(Icons.people_outline_rounded,
                      size: 12, color: AppColors.textTertiary),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      inspection.assignees.map((a) => a.fullName).join(', '),
                      style: TextStyle(
                          fontSize: 11, color: AppColors.textSecondary),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Color _frequencyColor(String freq) {
    switch (freq) {
      case 'daily':
        return const Color(0xFFB45309);
      case 'weekly':
        return const Color(0xFF1D4ED8);
      case 'monthly':
        return const Color(0xFF7C3AED);
      default:
        return const Color(0xFF6B7280);
    }
  }
}
