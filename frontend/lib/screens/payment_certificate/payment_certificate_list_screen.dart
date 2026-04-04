import 'package:flutter/material.dart';
import '../../models/payment_certificate.dart';
import '../../services/payment_certificate_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/claude_widgets.dart';
import '../../widgets/pdf_preview_screen.dart';
import 'add_payment_certificate_screen.dart';

class PaymentCertificateListScreen extends StatefulWidget {
  const PaymentCertificateListScreen({super.key});

  @override
  State<PaymentCertificateListScreen> createState() =>
      _PaymentCertificateListScreenState();
}

class _PaymentCertificateListScreenState
    extends State<PaymentCertificateListScreen>
    with WidgetsBindingObserver {
  final _service = PaymentCertificateService();
  final _searchCtrl = TextEditingController();

  List<PaymentCertificate> _all = [];
  List<PaymentCertificate> _filtered = [];
  bool _loading = true;
  bool _refreshing = false;
  bool _showSearch = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && !_loading) {
      _refresh();
    }
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final result = await _service.fetchAll();
      if (!mounted) return;
      setState(() {
        _all = result.items;
        _applySearch();
        _loading = false;
      });
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _refresh() async {
    setState(() => _refreshing = true);
    try {
      final result = await _service.fetchAll();
      if (!mounted) return;
      setState(() {
        _all = result.items;
        _applySearch();
        _refreshing = false;
      });
    } catch (e) {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  void _applySearch() {
    final q = _searchCtrl.text.trim().toLowerCase();
    if (q.isEmpty) {
      _filtered = List.of(_all);
    } else {
      _filtered = _all.where((c) {
        return c.certificateNumber.toLowerCase().contains(q) ||
            c.subject.toLowerCase().contains(q) ||
            c.contractNumber.toLowerCase().contains(q) ||
            c.invoiceNumber.toLowerCase().contains(q) ||
            c.executingEntity.toLowerCase().contains(q);
      }).toList();
    }
  }

  Future<void> _openPdf(PaymentCertificate cert) async {
    try {
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => PdfPreviewScreen(
            title: 'PC-${cert.certificateNumber} Report',
            buildPdf: () => _service.exportPdf(cert.id),
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to export PDF: $e'),
            backgroundColor: AppColors.dangerText,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _openAdd() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
          builder: (_) => const AddPaymentCertificateScreen()),
    );
    if (result == 'saved') _load();
  }

  Future<void> _openEdit(PaymentCertificate cert) async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
          builder: (_) => AddPaymentCertificateScreen(certificate: cert)),
    );
    if (result == 'saved' || result == 'deleted') _load();
  }

  Future<void> _openCopy(PaymentCertificate cert) async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
          builder: (_) => AddPaymentCertificateScreen(
                certificate: cert,
                isCopy: true,
              )),
    );
    if (result == 'saved') _load();
  }

  Future<void> _confirmDelete(PaymentCertificate cert) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text('حذف الشهادة'),
          content: Text('هل تريد حذف شهادة رقم ${cert.certificateNumber}؟'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('إلغاء')),
            TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                style: TextButton.styleFrom(foregroundColor: AppColors.dangerText),
                child: const Text('حذف')),
          ],
        ),
      ),
    );
    if (confirmed != true) return;
    try {
      await _service.delete(cert.id);
      _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Failed to delete: $e'),
          backgroundColor: AppColors.dangerText,
          behavior: SnackBarBehavior.floating,
        ));
      }
    }
  }

  String _fmtDate(DateTime? d) {
    if (d == null) return '';
    final dd = d.day.toString().padLeft(2, '0');
    final mm = d.month.toString().padLeft(2, '0');
    return '$dd/$mm/${d.year}';
  }

  void _toggleSearch() {
    setState(() {
      _showSearch = !_showSearch;
      if (!_showSearch) {
        _searchCtrl.clear();
        _applySearch();
      }
    });
  }

  // ── Build ──────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: AppColors.bgPrimary,
        body: SafeArea(
          child: Column(
            children: [
              _buildHeader(),
              Divider(height: 0, thickness: 0.5, color: AppColors.border),
              Expanded(child: _buildBody()),
            ],
          ),
        ),
        floatingActionButton: ClaudeFAB(
          onTap: _openAdd,
          tooltip: 'إضافة شهادة',
          semanticsLabel: 'إضافة شهادة دفع جديدة',
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      color: AppColors.bgSurface,
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 10),
      child: Column(
        children: [
          Row(
            children: [
              if (Navigator.canPop(context)) ...[
                ClaudeIconButton(
                  icon: Icons.arrow_back_rounded,
                  onTap: () => Navigator.pop(context),
                  semanticsLabel: 'رجوع',
                ),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: _showSearch
                    ? ClaudeSearchBar(
                        controller: _searchCtrl,
                        hintText: 'رقم الشهادة، الموضوع...',
                        onChanged: (_) => setState(() => _applySearch()),
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(right: 4),
                            child: Text(
                              'شهادات الدفع',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: AppColors.textPrimary,
                                letterSpacing: -0.3,
                              ),
                            ),
                          ),
                          if (_all.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(right: 4),
                              child: Text(
                                '${_all.length} شهادة',
                                style: TextStyle(
                                    fontSize: 11, color: AppColors.textTertiary),
                              ),
                            ),
                        ],
                      ),
              ),
              const SizedBox(width: 6),
              ClaudeIconButton(
                icon: _showSearch ? Icons.close_rounded : Icons.search_rounded,
                onTap: _toggleSearch,
                semanticsLabel: _showSearch ? 'إغلاق البحث' : 'بحث',
              ),
              const SizedBox(width: 6),
              _refreshing
                  ? Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: AppColors.bgSurface2,
                        borderRadius: BorderRadius.circular(9),
                        border: Border.all(color: AppColors.border2, width: 0.5),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(9),
                        child: CircularProgressIndicator(
                          strokeWidth: 1.5,
                          color: AppColors.accent,
                        ),
                      ),
                    )
                  : ClaudeIconButton(
                      icon: Icons.refresh_rounded,
                      onTap: _refresh,
                      semanticsLabel: 'تحديث',
                    ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return Center(
        child: CircularProgressIndicator(color: AppColors.accent, strokeWidth: 1.5),
      );
    }
    if (_filtered.isEmpty) {
      return RefreshIndicator(
        onRefresh: _refresh,
        color: AppColors.accent,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            SizedBox(
              height: MediaQuery.of(context).size.height * 0.4,
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        color: AppColors.bgSurface2,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Icon(Icons.receipt_long_outlined,
                          size: 26, color: AppColors.textTertiary),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      _searchCtrl.text.isNotEmpty
                          ? 'لا توجد نتائج'
                          : 'لا توجد شهادات بعد',
                      style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: AppColors.textTertiary),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _refresh,
      color: AppColors.accent,
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 80),
        itemCount: _filtered.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (_, i) => _buildCard(_filtered[i]),
      ),
    );
  }

  Widget _buildCard(PaymentCertificate cert) {
    return SurfaceCard(
      onTap: () => _openEdit(cert),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: const Color(0xFFFEE2E2),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.receipt_long_outlined,
                    size: 18, color: Color(0xFFB91C1C)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'شهادة رقم ${cert.certificateNumber}',
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
                      cert.subject.isNotEmpty
                          ? cert.subject
                          : cert.contractNumber.isNotEmpty
                              ? 'عقد ${cert.contractNumber}'
                              : 'بدون موضوع',
                      style: TextStyle(
                          fontSize: 11, color: AppColors.textTertiary),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              ClaudeIconButton(
                icon: Icons.picture_as_pdf_outlined,
                onTap: () => _openPdf(cert),
                semanticsLabel: 'تصدير PDF',
              ),
              const SizedBox(width: 6),
              ClaudeIconButton(
                icon: Icons.copy_outlined,
                onTap: () => _openCopy(cert),
                semanticsLabel: 'نسخ الشهادة',
              ),
              const SizedBox(width: 6),
              ClaudeIconButton(
                icon: Icons.delete_outline,
                onTap: () => _confirmDelete(cert),
                semanticsLabel: 'حذف الشهادة',
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: [
              if (cert.invoiceNumber.isNotEmpty)
                _chip('فاتورة: ${cert.invoiceNumber}'),
              if (cert.invoiceAmount > 0)
                _chip('${cert.invoiceAmount.toStringAsFixed(cert.invoiceAmount == cert.invoiceAmount.roundToDouble() ? 0 : 2)} ${cert.currency}'),
              if (cert.periodFrom != null)
                _chip('${_fmtDate(cert.periodFrom)} - ${_fmtDate(cert.periodTo)}'),
              if (cert.createdAt != null)
                _chip(_fmtDate(cert.createdAt)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _chip(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.bgSurface2,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 10, color: AppColors.textSecondary),
      ),
    );
  }
}
