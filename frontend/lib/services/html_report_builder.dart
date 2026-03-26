import '../models/workorder_report.dart';

enum ReportTheme {
  formal('Formal', 'Clean warm tones with refined layout'),
  forest('Forest', 'Calm grounded greens with paper-ledger warmth'),
  teal('Steel Teal', 'Industrial slate with cool teal energy'),
  burgundy('Burgundy', 'Deep burgundy with elegant serif typography');

  final String label;
  final String description;
  const ReportTheme(this.label, this.description);
}

class _ThemeColors {
  final String ink, inkMid, inkSoft, inkGhost;
  final String paper, paperWarm, rule;
  final String accent, accentPale;
  final String bg;
  final String shadow;

  const _ThemeColors({
    required this.ink, required this.inkMid, required this.inkSoft, required this.inkGhost,
    required this.paper, required this.paperWarm, required this.rule,
    required this.accent, required this.accentPale,
    required this.bg, required this.shadow,
  });

  static const formal = _ThemeColors(
    ink: '#18180F', inkMid: '#4A4A3E', inkSoft: '#8A8A7A', inkGhost: '#C4C4B4',
    paper: '#FAFAF7', paperWarm: '#F5F4EF', rule: '#E2E0D8',
    accent: '#8B6F4E', accentPale: '#F0EAE2',
    bg: '#EEECEA', shadow: 'rgba(0,0,0,.06)',
  );

  static const forest = _ThemeColors(
    ink: '#0E1D14', inkMid: '#2A4535', inkSoft: '#527A62', inkGhost: '#8CB09A',
    paper: '#F7FAF8', paperWarm: '#EEF5F0', rule: '#C8DDD0',
    accent: '#2D6A4F', accentPale: '#E0F0E8',
    bg: '#C4D9CB', shadow: 'rgba(14,29,20,.06)',
  );

  static const teal = _ThemeColors(
    ink: '#0D1E26', inkMid: '#2C4A58', inkSoft: '#5E8A9A', inkGhost: '#9BBCC8',
    paper: '#F5FAFB', paperWarm: '#EBF4F7', rule: '#C8DFE6',
    accent: '#1A7A9A', accentPale: '#DCF0F7',
    bg: '#CCDEE5', shadow: 'rgba(13,30,38,.06)',
  );

  static const burgundy = _ThemeColors(
    ink: '#1E0F14', inkMid: '#4A2832', inkSoft: '#8A5560', inkGhost: '#BF949C',
    paper: '#FAF8F8', paperWarm: '#F5EEEF', rule: '#E2D0D3',
    accent: '#8B2252', accentPale: '#F7E4EC',
    bg: '#DEC8CC', shadow: 'rgba(30,15,20,.06)',
  );
}

class HtmlReportBuilder {
  static _ThemeColors _colorsFor(ReportTheme theme) => switch (theme) {
    ReportTheme.formal => _ThemeColors.formal,
    ReportTheme.forest => _ThemeColors.forest,
    ReportTheme.teal => _ThemeColors.teal,
    ReportTheme.burgundy => _ThemeColors.burgundy,
  };

  static String build({
    required String employeeName,
    required DateTime startDate,
    required DateTime endDate,
    required List<WorkOrderReport> results,
    ReportTheme theme = ReportTheme.formal,
  }) {
    final c = _colorsFor(theme);
    final now = DateTime.now();
    final generatedDate = '${now.day} ${_monthName(now.month)} ${now.year}';
    final generatedTime = '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
    final periodStart = '${_monthName(startDate.month)} ${startDate.day}';
    final periodEnd = '${_monthName(endDate.month)} ${endDate.day}, ${endDate.year}';
    final totalClosed = results.length;

    final locations = results.map((r) => r.location).where((l) => l.isNotEmpty).toSet();
    final latestClosed = results.isNotEmpty
        ? results.map((r) => r.modifiedDate).reduce((a, b) => a.isAfter(b) ? a : b)
        : null;
    final latestClosedStr = latestClosed != null
        ? '${latestClosed.day} ${_monthName(latestClosed.month)}'
        : '-';
    final latestClosedYear = latestClosed?.year.toString() ?? '';

    final rowsHtml = StringBuffer();
    for (var i = 0; i < results.length; i++) {
      final wo = results[i];
      final num = (i + 1).toString().padLeft(2, '0');
      final dateStr = '${wo.modifiedDate.year}-${wo.modifiedDate.month.toString().padLeft(2, '0')}-${wo.modifiedDate.day.toString().padLeft(2, '0')}';
      rowsHtml.writeln('''
        <tr>
          <td class="cell-num">$num</td>
          <td class="cell-title">${_esc(wo.title)}${wo.description.isNotEmpty ? '<small>${_esc(wo.description)}</small>' : ''}</td>
          <td class="cell-loc"><span class="loc-dot"></span>${_esc(wo.location)}</td>
          <td><span class="status-badge">Closed</span></td>
          <td class="cell-date">$dateStr</td>
        </tr>''');
    }

    return '''<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>Work Order Report</title>
<link rel="preconnect" href="https://fonts.googleapis.com">
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link href="https://fonts.googleapis.com/css2?family=Cormorant:ital,wght@0,300;0,400;0,500;0,600;1,300;1,400&family=DM+Sans:ital,wght@0,300;0,400;0,500;1,300&display=swap" rel="stylesheet">
<style>
  :root {
    --ink: ${c.ink}; --ink-mid: ${c.inkMid}; --ink-soft: ${c.inkSoft};
    --ink-ghost: ${c.inkGhost}; --paper: ${c.paper}; --paper-warm: ${c.paperWarm};
    --rule: ${c.rule}; --accent: ${c.accent}; --accent-pale: ${c.accentPale};
    --f-display: 'Cormorant', Georgia, serif;
    --f-text: 'DM Sans', system-ui, sans-serif;
    --page-w: 860px; --gap: 2rem;
  }
  *, *::before, *::after { box-sizing: border-box; margin: 0; padding: 0; }
  html { background: ${c.bg}; min-height: 100%; }
  body { font-family: var(--f-text); color: var(--ink); background: ${c.bg}; padding: 3rem 1.5rem; -webkit-font-smoothing: antialiased; }
  .page { max-width: var(--page-w); margin: 0 auto; background: var(--paper); box-shadow: 0 2px 4px ${c.shadow}, 0 8px 32px ${c.shadow}, 0 0 0 1px ${c.shadow}; animation: rise .6s cubic-bezier(.22,.68,0,1.1) both; }
  @keyframes rise { from { opacity:0; transform:translateY(18px); } to { opacity:1; transform:translateY(0); } }
  .top-bar { background: var(--ink); padding: 0 3rem; display: flex; align-items: center; justify-content: space-between; height: 52px; }
  .top-bar__brand { font-family: var(--f-display); font-size: 13px; font-weight: 400; letter-spacing: .18em; text-transform: uppercase; color: rgba(255,255,255,.55); }
  .top-bar__meta { font-size: 11px; font-weight: 300; letter-spacing: .08em; color: rgba(255,255,255,.38); }
  .header { padding: 3.5rem 3rem 2.5rem; border-bottom: 1px solid var(--rule); display: grid; grid-template-columns: 1fr auto; gap: 2rem; align-items: end; }
  .header__eyebrow { font-size: 10px; font-weight: 500; letter-spacing: .22em; text-transform: uppercase; color: var(--accent); margin-bottom: .75rem; }
  .header__title { font-family: var(--f-display); font-size: 48px; font-weight: 300; line-height: 1.06; color: var(--ink); letter-spacing: -.02em; }
  .header__title em { font-style: italic; font-weight: 300; }
  .header__sub { margin-top: 1rem; font-size: 13px; font-weight: 300; color: var(--ink-soft); line-height: 1.6; max-width: 38ch; }
  .header__meta { text-align: right; }
  .meta-pill { display: inline-flex; flex-direction: column; align-items: flex-end; padding: .75rem 1.1rem; background: var(--paper-warm); border: 1px solid var(--rule); }
  .meta-pill + .meta-pill { margin-top: .5rem; }
  .meta-pill__label { font-size: 9px; font-weight: 500; letter-spacing: .2em; text-transform: uppercase; color: var(--ink-ghost); margin-bottom: .25rem; }
  .meta-pill__value { font-family: var(--f-display); font-size: 14px; font-weight: 500; color: var(--ink); letter-spacing: .01em; }
  .summary { display: grid; grid-template-columns: repeat(4, 1fr); border-bottom: 1px solid var(--rule); }
  .stat { padding: 2rem 2.5rem; border-right: 1px solid var(--rule); animation: fade-up .5s both; }
  .stat:last-child { border-right: none; }
  .stat:nth-child(1) { animation-delay: .05s; } .stat:nth-child(2) { animation-delay: .10s; }
  .stat:nth-child(3) { animation-delay: .15s; } .stat:nth-child(4) { animation-delay: .20s; }
  @keyframes fade-up { from { opacity:0; transform:translateY(8px); } to { opacity:1; transform:translateY(0); } }
  .stat__label { font-size: 9px; font-weight: 500; letter-spacing: .18em; text-transform: uppercase; color: var(--ink-ghost); margin-bottom: .6rem; }
  .stat__value { font-family: var(--f-display); font-size: 36px; font-weight: 300; line-height: 1; color: var(--ink); letter-spacing: -.02em; }
  .stat__value.accent { color: var(--accent); }
  .stat__caption { margin-top: .4rem; font-size: 11px; font-weight: 300; color: var(--ink-soft); }
  .body { padding: 2.5rem 3rem; }
  .section-head { display: flex; align-items: baseline; gap: 1rem; margin-bottom: 1.25rem; }
  .section-head__title { font-size: 9.5px; font-weight: 500; letter-spacing: .22em; text-transform: uppercase; color: var(--ink-soft); }
  .section-head__rule { flex: 1; height: 1px; background: var(--rule); }
  .section-head__count { font-size: 9.5px; font-weight: 300; color: var(--ink-ghost); letter-spacing: .06em; }
  .wo-table { width: 100%; border-collapse: collapse; table-layout: fixed; }
  .wo-table thead tr { border-bottom: 1px solid var(--rule); }
  .wo-table th { font-size: 9px; font-weight: 500; letter-spacing: .22em; text-transform: uppercase; color: var(--ink-ghost); padding: .6rem 0; text-align: left; }
  .wo-table th:last-child { text-align: right; }
  .wo-table tbody tr { border-bottom: 1px solid var(--rule); transition: background .15s; }
  .wo-table tbody tr:last-child { border-bottom: none; }
  .wo-table tbody tr:hover { background: var(--paper-warm); }
  .wo-table td { padding: 1rem 0; vertical-align: middle; }
  .wo-table td:last-child { text-align: right; }
  .wo-table col.col-num { width: 3rem; }
  .wo-table col.col-title { width: auto; }
  .wo-table col.col-loc { width: 10rem; }
  .wo-table col.col-status { width: 6rem; }
  .wo-table col.col-date { width: 7rem; }
  .cell-num { font-family: var(--f-display); font-size: 12px; font-weight: 400; color: var(--ink-ghost); letter-spacing: .05em; }
  .cell-title { font-size: 13px; font-weight: 400; color: var(--ink); line-height: 1.4; overflow: hidden; }
  .cell-title small { display: block; font-size: 11px; font-weight: 300; color: var(--ink-soft); margin-top: .2rem; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
  .cell-loc { font-size: 12px; font-weight: 300; color: var(--ink-mid); white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
  .loc-dot { display: inline-block; width: 6px; height: 6px; border-radius: 50%; background: var(--accent); margin-right: .5rem; vertical-align: middle; }
  .status-badge { display: inline-block; font-size: 10px; font-weight: 500; letter-spacing: .08em; text-transform: uppercase; padding: .3rem .7rem; border-radius: 4px; background: var(--accent-pale); color: var(--accent); }
  .cell-date { font-family: var(--f-display); font-size: 12px; font-weight: 400; color: var(--ink-soft); letter-spacing: .04em; white-space: nowrap; }
  .footer { display: flex; justify-content: space-between; align-items: center; padding: 1.5rem 3rem; border-top: 1px solid var(--rule); background: var(--paper-warm); }
  .footer__left { font-size: 10px; font-weight: 300; color: var(--ink-ghost); letter-spacing: .06em; }
  .footer__left strong { font-weight: 500; color: var(--ink-soft); }
  .footer__pages { font-family: var(--f-display); font-size: 11px; font-weight: 400; color: var(--ink-ghost); letter-spacing: .06em; }
  @media print { html, body { background: white; padding: 0; } .page { box-shadow: none; } .wo-table tbody tr:hover { background: transparent; } @page { margin: 0; size: A4; } }
</style>
</head>
<body>
<article class="page">
  <div class="top-bar">
    <span class="top-bar__brand">Work Order System</span>
    <span class="top-bar__meta">Field Closure Report &nbsp;&middot;&nbsp; Confidential</span>
  </div>
  <header class="header">
    <div class="header__left">
      <p class="header__eyebrow">Operational Report</p>
      <h1 class="header__title">Field Closure<br><em>Summary</em></h1>
      <p class="header__sub">
        A concise operational snapshot for <strong>${_esc(employeeName)}</strong>
        covering $periodStart to $periodEnd across ${locations.length} location${locations.length == 1 ? '' : 's'}.
      </p>
    </div>
    <div class="header__meta">
      <div class="meta-pill">
        <span class="meta-pill__label">Employee</span>
        <span class="meta-pill__value">${_esc(employeeName)}</span>
      </div>
      <div class="meta-pill">
        <span class="meta-pill__label">Period</span>
        <span class="meta-pill__value">$periodStart &ndash; $periodEnd</span>
      </div>
      <div class="meta-pill">
        <span class="meta-pill__label">Generated</span>
        <span class="meta-pill__value">$generatedDate</span>
      </div>
    </div>
  </header>
  <section class="summary">
    <div class="stat">
      <p class="stat__label">Total Closed</p>
      <p class="stat__value">${totalClosed.toString().padLeft(2, '0')}</p>
      <p class="stat__caption">Work orders</p>
    </div>
    <div class="stat">
      <p class="stat__label">Locations</p>
      <p class="stat__value">${locations.length.toString().padLeft(2, '0')}</p>
      <p class="stat__caption">Sites covered</p>
    </div>
    <div class="stat">
      <p class="stat__label">Latest Closed</p>
      <p class="stat__value" style="font-size:22px; padding-top:.4rem;">$latestClosedStr</p>
      <p class="stat__caption">$latestClosedYear</p>
    </div>
    <div class="stat">
      <p class="stat__label">Status</p>
      <p class="stat__value accent" style="font-size:22px; padding-top:.4rem;">Complete</p>
      <p class="stat__caption">All items resolved</p>
    </div>
  </section>
  <div class="body">
    <div class="section-head">
      <span class="section-head__title">Work Orders</span>
      <span class="section-head__rule"></span>
      <span class="section-head__count">$totalClosed ${totalClosed == 1 ? 'entry' : 'entries'}</span>
    </div>
    <table class="wo-table">
      <colgroup>
        <col class="col-num">
        <col class="col-title">
        <col class="col-loc">
        <col class="col-status">
        <col class="col-date">
      </colgroup>
      <thead>
        <tr>
          <th class="cell-num">No.</th>
          <th>Work Order</th>
          <th>Location</th>
          <th>Status</th>
          <th>Closed</th>
        </tr>
      </thead>
      <tbody>
$rowsHtml
      </tbody>
    </table>
  </div>
  <footer class="footer">
    <p class="footer__left"><strong>Work Order System</strong> &nbsp;&middot;&nbsp; Generated $generatedDate at $generatedTime</p>
    <p class="footer__pages">Page 1 of 1</p>
  </footer>
</article>
</body>
</html>''';
  }

  static String _esc(String s) =>
      s.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;').replaceAll('"', '&quot;');

  static String _monthName(int m) => const [
    '', 'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December',
  ][m];
}
