import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../models/workorder_report.dart';

enum WorkOrderPdfTheme {
  copperNight,
  forestLedger,
  signalOrange,
}

extension WorkOrderPdfThemeX on WorkOrderPdfTheme {
  String get label {
    switch (this) {
      case WorkOrderPdfTheme.copperNight:
        return 'Claude Minimal';
      case WorkOrderPdfTheme.forestLedger:
        return 'Forest Ledger';
      case WorkOrderPdfTheme.signalOrange:
        return 'Signal Orange';
    }
  }

  String get description {
    switch (this) {
      case WorkOrderPdfTheme.copperNight:
        return 'Warm minimal cream surfaces with Claude-inspired terracotta.';
      case WorkOrderPdfTheme.forestLedger:
        return 'Calm, grounded greens with paper-ledger warmth.';
      case WorkOrderPdfTheme.signalOrange:
        return 'Industrial slate with bold orange energy.';
    }
  }
}

class WorkOrderPdfService {
  static Future<Uint8List> buildReport({
    required String employeeName,
    required DateTime startDate,
    required DateTime endDate,
    required List<WorkOrderReport> results,
    required PdfColor primaryColor,
    required WorkOrderPdfTheme theme,
  }) async {
    final pdf = pw.Document();
    final palette = _ReportPalette.fromTheme(theme, primaryColor);
    final generatedAt = DateTime.now();
    final generatedStr = _fmtLong(generatedAt);
    final startStr = _fmtLong(startDate);
    final endStr = _fmtLong(endDate);
    final locationStats = _buildLocationStats(results);
    final uniqueLocations = locationStats.length;
    final busiestLocation =
        locationStats.isEmpty ? 'No location data' : locationStats.first.name;
    final latestClosed =
        results.isEmpty ? 'No work orders' : _fmtLong(_latestClosed(results));

    final logoBytes = await rootBundle.load('assets/images/logo.png');
    final logoImage = pw.MemoryImage(logoBytes.buffer.asUint8List());

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(32, 24, 32, 28),
        footer: (context) => _footer(context, palette, generatedStr),
        build: (context) => [
          _heroSection(
            palette: palette,
            logo: logoImage,
            employeeName: employeeName,
            startStr: startStr,
            endStr: endStr,
            generatedStr: generatedStr,
            total: results.length,
            uniqueLocations: uniqueLocations,
          ),
          pw.SizedBox(height: 20),
          _metricsRow(
            palette: palette,
            employeeName: employeeName,
            uniqueLocations: uniqueLocations,
            busiestLocation: busiestLocation,
            latestClosed: latestClosed,
          ),
          pw.SizedBox(height: 20),
          _sectionTitle(
            palette: palette,
            eyebrow: 'Activity Snapshot',
            title: 'Where the closures happened',
            subtitle:
                'A ranked breakdown makes the busiest locations visible at a glance before the full ledger begins.',
          ),
          pw.SizedBox(height: 12),
          if (locationStats.isEmpty)
            _emptyCard(
              palette: palette,
              message:
                  'No closed work orders were found for this employee in the selected period.',
            )
          else
            _locationBoard(
              palette: palette,
              stats: locationStats,
              total: results.length,
            ),
          pw.SizedBox(height: 22),
          _sectionTitle(
            palette: palette,
            eyebrow: 'Detailed Ledger',
            title: 'Closed work orders',
            subtitle:
                'Each row lists the completed work order, its site, and the closure date for audit and review.',
          ),
          pw.SizedBox(height: 12),
          if (results.isEmpty)
            _emptyCard(
              palette: palette,
              message:
                  'Generate a report with matching records to populate the ledger.',
            )
          else
            _resultsTable(palette: palette, results: results),
        ],
      ),
    );

    return pdf.save();
  }

  static List<_LocationStat> _buildLocationStats(
      List<WorkOrderReport> results) {
    final counts = <String, int>{};
    for (final result in results) {
      final key = result.location.trim().isEmpty
          ? 'Unspecified'
          : result.location.trim();
      counts.update(key, (value) => value + 1, ifAbsent: () => 1);
    }

    final stats = counts.entries
        .map((entry) => _LocationStat(name: entry.key, count: entry.value))
        .toList();
    stats.sort((a, b) {
      final countCompare = b.count.compareTo(a.count);
      if (countCompare != 0) return countCompare;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return stats;
  }

  static DateTime _latestClosed(List<WorkOrderReport> results) {
    return results.map((item) => item.modifiedDate).reduce(
        (latest, current) => current.isAfter(latest) ? current : latest);
  }

  static pw.Widget _heroSection({
    required _ReportPalette palette,
    required pw.ImageProvider logo,
    required String employeeName,
    required String startStr,
    required String endStr,
    required String generatedStr,
    required int total,
    required int uniqueLocations,
  }) {
    return pw.Container(
      decoration: pw.BoxDecoration(
        color: palette.card,
        borderRadius: pw.BorderRadius.circular(26),
        border: pw.Border.all(color: palette.border, width: 0.8),
      ),
      child: pw.Stack(
        children: [
          pw.Positioned(
            top: -48,
            right: -26,
            child: pw.Container(
              width: 170,
              height: 170,
              decoration: pw.BoxDecoration(
                shape: pw.BoxShape.circle,
                color: palette.accentGlow,
              ),
            ),
          ),
          pw.Positioned(
            bottom: -60,
            left: -32,
            child: pw.Container(
              width: 190,
              height: 190,
              decoration: pw.BoxDecoration(
                shape: pw.BoxShape.circle,
                color: palette.accentMuted,
              ),
            ),
          ),
          pw.Padding(
            padding: const pw.EdgeInsets.fromLTRB(24, 22, 24, 24),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Row(
                      children: [
                        pw.Container(
                          width: 48,
                          height: 48,
                          padding: const pw.EdgeInsets.all(8),
                          decoration: pw.BoxDecoration(
                            color: PdfColors.white,
                            borderRadius: pw.BorderRadius.circular(14),
                            border: pw.Border.all(
                              color: palette.border,
                              width: 0.7,
                            ),
                          ),
                          child: pw.Image(logo, fit: pw.BoxFit.contain),
                        ),
                        pw.SizedBox(width: 12),
                        pw.Column(
                          crossAxisAlignment: pw.CrossAxisAlignment.start,
                          children: [
                            pw.Text(
                              'WORK ORDER SYSTEM',
                              style: pw.TextStyle(
                                color: palette.textSoft,
                                fontSize: 8,
                                fontWeight: pw.FontWeight.bold,
                                letterSpacing: 1.3,
                              ),
                            ),
                            pw.SizedBox(height: 4),
                            pw.Text(
                              'Field closure report',
                              style: pw.TextStyle(
                                color: palette.text,
                                fontSize: 13,
                                fontWeight: pw.FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    pw.Container(
                      padding: const pw.EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      decoration: pw.BoxDecoration(
                        color: PdfColors.white,
                        borderRadius: pw.BorderRadius.circular(20),
                        border: pw.Border.all(
                          color: palette.border,
                          width: 0.7,
                        ),
                      ),
                      child: pw.Text(
                        'Generated $generatedStr',
                        style: pw.TextStyle(
                          color: palette.textSoft,
                          fontSize: 8.5,
                        ),
                      ),
                    ),
                  ],
                ),
                pw.SizedBox(height: 26),
                pw.Row(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Expanded(
                      flex: 6,
                      child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Text(
                            total.toString().padLeft(2, '0'),
                            style: pw.TextStyle(
                              color: palette.accent,
                              fontSize: 52,
                              fontWeight: pw.FontWeight.bold,
                              letterSpacing: -1.4,
                            ),
                          ),
                          pw.SizedBox(height: 2),
                          pw.Text(
                            'closed work orders',
                            style: pw.TextStyle(
                              color: palette.text,
                              fontSize: 18,
                              fontWeight: pw.FontWeight.bold,
                            ),
                          ),
                          pw.SizedBox(height: 8),
                          pw.Text(
                            'A concise operational snapshot for $employeeName covering $startStr to $endStr across $uniqueLocations location${uniqueLocations == 1 ? '' : 's'}.',
                            style: pw.TextStyle(
                              color: palette.textSoft,
                              fontSize: 10.5,
                              height: 1.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                    pw.SizedBox(width: 18),
                    pw.Expanded(
                      flex: 5,
                      child: pw.Column(
                        children: [
                          _heroInfoCard(
                            palette: palette,
                            label: 'Employee',
                            value: employeeName,
                          ),
                          pw.SizedBox(height: 10),
                          _heroInfoCard(
                            palette: palette,
                            label: 'Reporting Window',
                            value: '$startStr - $endStr',
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static pw.Widget _heroInfoCard({
    required _ReportPalette palette,
    required String label,
    required String value,
  }) {
    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: pw.BoxDecoration(
        color: PdfColors.white,
        borderRadius: pw.BorderRadius.circular(16),
        border: pw.Border.all(color: palette.border, width: 0.7),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            label.toUpperCase(),
            style: pw.TextStyle(
              color: palette.textSoft,
              fontSize: 7.8,
              fontWeight: pw.FontWeight.bold,
              letterSpacing: 0.9,
            ),
          ),
          pw.SizedBox(height: 6),
          pw.Text(
            value,
            style: pw.TextStyle(
              color: palette.text,
              fontSize: 11.2,
              fontWeight: pw.FontWeight.bold,
              height: 1.3,
            ),
          ),
        ],
      ),
    );
  }

  static pw.Widget _metricsRow({
    required _ReportPalette palette,
    required String employeeName,
    required int uniqueLocations,
    required String busiestLocation,
    required String latestClosed,
  }) {
    return pw.Row(
      children: [
        _metricCard(
          palette: palette,
          label: 'Assigned Employee',
          value: employeeName,
          accent: false,
        ),
        pw.SizedBox(width: 10),
        _metricCard(
          palette: palette,
          label: 'Locations Covered',
          value: '$uniqueLocations',
          accent: true,
        ),
        pw.SizedBox(width: 10),
        _metricCard(
          palette: palette,
          label: 'Busiest Site',
          value: busiestLocation,
          accent: false,
        ),
        pw.SizedBox(width: 10),
        _metricCard(
          palette: palette,
          label: 'Latest Close',
          value: latestClosed,
          accent: false,
        ),
      ],
    );
  }

  static pw.Widget _metricCard({
    required _ReportPalette palette,
    required String label,
    required String value,
    required bool accent,
  }) {
    return pw.Expanded(
      child: pw.Container(
        height: 86,
        padding: const pw.EdgeInsets.fromLTRB(14, 14, 14, 12),
        decoration: pw.BoxDecoration(
          color: accent ? palette.accent : palette.card,
          borderRadius: pw.BorderRadius.circular(18),
          border: pw.Border.all(
            color: accent ? palette.accent : palette.border,
            width: 0.8,
          ),
        ),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(
              label.toUpperCase(),
              style: pw.TextStyle(
                color: accent ? palette.card : palette.textSoft,
                fontSize: 7.6,
                fontWeight: pw.FontWeight.bold,
                letterSpacing: 0.8,
              ),
            ),
            pw.Text(
              value,
              maxLines: 2,
              style: pw.TextStyle(
                color: accent ? palette.ink : palette.text,
                fontSize: 12,
                fontWeight: pw.FontWeight.bold,
                height: 1.25,
              ),
            ),
          ],
        ),
      ),
    );
  }

  static pw.Widget _sectionTitle({
    required _ReportPalette palette,
    required String eyebrow,
    required String title,
    required String subtitle,
  }) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          eyebrow.toUpperCase(),
          style: pw.TextStyle(
            color: palette.accent,
            fontSize: 8,
            fontWeight: pw.FontWeight.bold,
            letterSpacing: 1.0,
          ),
        ),
        pw.SizedBox(height: 4),
        pw.Text(
          title,
          style: pw.TextStyle(
            color: palette.text,
            fontSize: 19,
            fontWeight: pw.FontWeight.bold,
          ),
        ),
        pw.SizedBox(height: 6),
        pw.Text(
          subtitle,
          style: pw.TextStyle(
            color: palette.textSoft,
            fontSize: 10,
            height: 1.45,
          ),
        ),
      ],
    );
  }

  static pw.Widget _locationBoard({
    required _ReportPalette palette,
    required List<_LocationStat> stats,
    required int total,
  }) {
    final topStats = stats.take(5).toList();
    final maxCount = topStats.first.count;

    return pw.Container(
      padding: const pw.EdgeInsets.all(18),
      decoration: pw.BoxDecoration(
        color: palette.card,
        borderRadius: pw.BorderRadius.circular(22),
        border: pw.Border.all(color: palette.border, width: 0.8),
      ),
      child: pw.Column(
        children: [
          ...topStats.asMap().entries.map((entry) {
            final index = entry.key;
            final stat = entry.value;
            final ratio = maxCount == 0 ? 0.0 : stat.count / maxCount;
            final share = total == 0 ? 0 : ((stat.count / total) * 100).round();

            return pw.Padding(
              padding: pw.EdgeInsets.only(
                  bottom: index == topStats.length - 1 ? 0 : 12),
              child: pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.center,
                children: [
                  pw.Container(
                    width: 28,
                    height: 28,
                    alignment: pw.Alignment.center,
                    decoration: pw.BoxDecoration(
                      color: index == 0 ? palette.accent : palette.surface,
                      borderRadius: pw.BorderRadius.circular(10),
                    ),
                    child: pw.Text(
                      '${index + 1}',
                      style: pw.TextStyle(
                        color: index == 0 ? palette.ink : palette.text,
                        fontSize: 10,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                  ),
                  pw.SizedBox(width: 12),
                  pw.Expanded(
                    flex: 4,
                    child: pw.Text(
                      stat.name,
                      style: pw.TextStyle(
                        color: palette.text,
                        fontSize: 10.5,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                  ),
                  pw.SizedBox(width: 12),
                  pw.Expanded(
                    flex: 6,
                    child: pw.Stack(
                      children: [
                        pw.Container(
                          height: 10,
                          decoration: pw.BoxDecoration(
                            color: palette.surface,
                            borderRadius: pw.BorderRadius.circular(10),
                          ),
                        ),
                        pw.Container(
                          height: 10,
                          width: math.max(18, ratio * 220),
                          decoration: pw.BoxDecoration(
                            gradient: pw.LinearGradient(
                              colors: [palette.accent, palette.accentStrong],
                            ),
                            borderRadius: pw.BorderRadius.circular(10),
                          ),
                        ),
                      ],
                    ),
                  ),
                  pw.SizedBox(width: 12),
                  pw.SizedBox(
                    width: 54,
                    child: pw.Text(
                      '${stat.count}  |  $share%',
                      textAlign: pw.TextAlign.right,
                      style: pw.TextStyle(
                        color: palette.textSoft,
                        fontSize: 9,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            );
          }),
          if (stats.length > 5) ...[
            pw.SizedBox(height: 12),
            pw.Container(
              width: double.infinity,
              padding: const pw.EdgeInsets.fromLTRB(12, 10, 12, 10),
              decoration: pw.BoxDecoration(
                color: palette.surface,
                borderRadius: pw.BorderRadius.circular(14),
              ),
              child: pw.Text(
                '+${stats.length - 5} more location${stats.length - 5 == 1 ? '' : 's'} included in the detailed ledger.',
                style: pw.TextStyle(
                  color: palette.textSoft,
                  fontSize: 9.5,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  static pw.Widget _resultsTable({
    required _ReportPalette palette,
    required List<WorkOrderReport> results,
  }) {
    return pw.Container(
      decoration: pw.BoxDecoration(
        color: palette.card,
        borderRadius: pw.BorderRadius.circular(22),
        border: pw.Border.all(color: palette.border, width: 0.8),
      ),
      child: pw.Column(
        children: [
          pw.Container(
            padding: const pw.EdgeInsets.fromLTRB(16, 12, 16, 12),
            decoration: pw.BoxDecoration(
              color: palette.ink,
              borderRadius: const pw.BorderRadius.only(
                topLeft: pw.Radius.circular(21),
                topRight: pw.Radius.circular(21),
              ),
            ),
            child: pw.Row(
              children: [
                _tableHeaderCell('No.', flex: 1, alignRight: false),
                _tableHeaderCell('Work order', flex: 6, alignRight: false),
                _tableHeaderCell('Location', flex: 3, alignRight: false),
                _tableHeaderCell('Closed', flex: 2, alignRight: true),
              ],
            ),
          ),
          ...results.asMap().entries.map((entry) {
            final index = entry.key;
            final item = entry.value;
            final isLast = index == results.length - 1;

            return pw.Container(
              padding: const pw.EdgeInsets.fromLTRB(16, 12, 16, 12),
              decoration: pw.BoxDecoration(
                color: index.isEven ? palette.card : palette.surface,
                border: isLast
                    ? null
                    : pw.Border(
                        bottom:
                            pw.BorderSide(color: palette.border, width: 0.7),
                      ),
              ),
              child: pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  _tableValueCell('${index + 1}'.padLeft(2, '0'), flex: 1),
                  _tableValueCell(item.title, flex: 6, bold: true),
                  _tableValueCell(
                      item.location.trim().isEmpty
                          ? 'Unspecified'
                          : item.location,
                      flex: 3),
                  _tableValueCell(_fmtShort(item.modifiedDate),
                      flex: 2, alignRight: true),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  static pw.Widget _tableHeaderCell(String text,
      {required int flex, required bool alignRight}) {
    return pw.Expanded(
      flex: flex,
      child: pw.Text(
        text.toUpperCase(),
        textAlign: alignRight ? pw.TextAlign.right : pw.TextAlign.left,
        style: pw.TextStyle(
          color: PdfColors.white,
          fontSize: 8,
          fontWeight: pw.FontWeight.bold,
          letterSpacing: 0.8,
        ),
      ),
    );
  }

  static pw.Widget _tableValueCell(
    String text, {
    required int flex,
    bool bold = false,
    bool alignRight = false,
  }) {
    return pw.Expanded(
      flex: flex,
      child: pw.Text(
        text,
        textAlign: alignRight ? pw.TextAlign.right : pw.TextAlign.left,
        style: pw.TextStyle(
          color: const PdfColor(0.12, 0.14, 0.17),
          fontSize: 9.8,
          fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
          height: 1.35,
        ),
      ),
    );
  }

  static pw.Widget _emptyCard({
    required _ReportPalette palette,
    required String message,
  }) {
    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.fromLTRB(18, 16, 18, 16),
      decoration: pw.BoxDecoration(
        color: palette.card,
        borderRadius: pw.BorderRadius.circular(18),
        border: pw.Border.all(color: palette.border, width: 0.8),
      ),
      child: pw.Text(
        message,
        style: pw.TextStyle(
          color: palette.textSoft,
          fontSize: 10,
          height: 1.45,
        ),
      ),
    );
  }

  static pw.Widget _footer(
    pw.Context context,
    _ReportPalette palette,
    String generatedStr,
  ) {
    return pw.Container(
      padding: const pw.EdgeInsets.only(top: 10),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(
            'Work Order System · Generated $generatedStr',
            style: pw.TextStyle(
              color: palette.textSoft,
              fontSize: 8,
            ),
          ),
          pw.Text(
            'Page ${context.pageNumber} of ${context.pagesCount}',
            style: pw.TextStyle(
              color: palette.textSoft,
              fontSize: 8,
            ),
          ),
        ],
      ),
    );
  }

  static String _fmtLong(DateTime date) {
    const months = [
      '',
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${date.day} ${months[date.month]} ${date.year}';
  }

  static String _fmtShort(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }
}

class _LocationStat {
  const _LocationStat({required this.name, required this.count});

  final String name;
  final int count;
}

class _ReportPalette {
  const _ReportPalette({
    required this.accent,
    required this.accentStrong,
    required this.accentMuted,
    required this.accentGlow,
    required this.ink,
    required this.panel,
    required this.card,
    required this.surface,
    required this.border,
    required this.borderStrong,
    required this.text,
    required this.textSoft,
    required this.textOnDark,
    required this.textOnDarkSoft,
  });

  final PdfColor accent;
  final PdfColor accentStrong;
  final PdfColor accentMuted;
  final PdfColor accentGlow;
  final PdfColor ink;
  final PdfColor panel;
  final PdfColor card;
  final PdfColor surface;
  final PdfColor border;
  final PdfColor borderStrong;
  final PdfColor text;
  final PdfColor textSoft;
  final PdfColor textOnDark;
  final PdfColor textOnDarkSoft;

  factory _ReportPalette.fromTheme(
    WorkOrderPdfTheme theme,
    PdfColor primary,
  ) {
    switch (theme) {
      case WorkOrderPdfTheme.copperNight:
        return _ReportPalette._copperNight(primary);
      case WorkOrderPdfTheme.forestLedger:
        return _ReportPalette._forestLedger(primary);
      case WorkOrderPdfTheme.signalOrange:
        return _ReportPalette._signalOrange(primary);
    }
  }

  factory _ReportPalette._copperNight(PdfColor primary) {
    const white = PdfColors.white;
    const terracotta = PdfColor(0.80, 0.47, 0.36);
    const umber = PdfColor(0.38, 0.28, 0.21);
    const warmPaper = PdfColor(0.981, 0.973, 0.957);
    const warmPanel = PdfColor(0.963, 0.946, 0.918);

    final accent = _mix(terracotta, primary, 0.06);
    final accentStrong = _mix(umber, terracotta, 0.24);

    return _ReportPalette(
      accent: accent,
      accentStrong: accentStrong,
      accentMuted: _mix(accent, white, 0.90),
      accentGlow: _mix(accent, white, 0.95),
      ink: accentStrong,
      panel: warmPanel,
      card: warmPaper,
      surface: const PdfColor(0.950, 0.939, 0.916),
      border: const PdfColor(0.865, 0.835, 0.792),
      borderStrong: _mix(accent, white, 0.52),
      text: const PdfColor(0.17, 0.14, 0.12),
      textSoft: const PdfColor(0.43, 0.37, 0.32),
      textOnDark: const PdfColor(0.985, 0.967, 0.938),
      textOnDarkSoft: const PdfColor(0.84, 0.79, 0.73),
    );
  }

  factory _ReportPalette._forestLedger(PdfColor primary) {
    const white = PdfColors.white;
    const moss = PdfColor(0.34, 0.46, 0.31);
    const pine = PdfColor(0.22, 0.31, 0.22);

    final accent = _mix(moss, primary, 0.08);
    final accentStrong = _mix(pine, primary, 0.05);

    return _ReportPalette(
      accent: accent,
      accentStrong: accentStrong,
      accentMuted: _mix(accent, white, 0.84),
      accentGlow: _mix(accent, white, 0.92),
      ink: const PdfColor(0.15, 0.20, 0.16),
      panel: const PdfColor(0.24, 0.30, 0.24),
      card: const PdfColor(0.969, 0.964, 0.934),
      surface: const PdfColor(0.900, 0.914, 0.875),
      border: const PdfColor(0.742, 0.785, 0.704),
      borderStrong: _mix(accent, white, 0.36),
      text: const PdfColor(0.15, 0.17, 0.14),
      textSoft: const PdfColor(0.39, 0.43, 0.37),
      textOnDark: const PdfColor(0.952, 0.956, 0.937),
      textOnDarkSoft: const PdfColor(0.80, 0.84, 0.79),
    );
  }

  factory _ReportPalette._signalOrange(PdfColor primary) {
    const white = PdfColors.white;
    const signalOrange = PdfColor(0.90, 0.43, 0.18);
    const rustOrange = PdfColor(0.67, 0.28, 0.10);
    const slateInk = PdfColor(0.12, 0.16, 0.20);
    const steelPanel = PdfColor(0.19, 0.24, 0.29);

    final accent = _mix(signalOrange, primary, 0.10);
    final accentStrong = _mix(rustOrange, primary, 0.08);

    return _ReportPalette(
      accent: accent,
      accentStrong: accentStrong,
      accentMuted: _mix(accent, white, 0.82),
      accentGlow: _mix(accent, white, 0.90),
      ink: slateInk,
      panel: steelPanel,
      card: const PdfColor(0.984, 0.968, 0.938),
      surface: const PdfColor(0.922, 0.896, 0.852),
      border: const PdfColor(0.792, 0.754, 0.690),
      borderStrong: _mix(accent, white, 0.34),
      text: const PdfColor(0.15, 0.16, 0.18),
      textSoft: const PdfColor(0.39, 0.39, 0.40),
      textOnDark: const PdfColor(0.986, 0.975, 0.955),
      textOnDarkSoft: const PdfColor(0.84, 0.84, 0.82),
    );
  }

  static PdfColor _mix(PdfColor a, PdfColor b, double t) {
    return PdfColor(
      a.red + (b.red - a.red) * t,
      a.green + (b.green - a.green) * t,
      a.blue + (b.blue - a.blue) * t,
    );
  }
}
