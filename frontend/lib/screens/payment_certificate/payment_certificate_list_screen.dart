import 'package:flutter/material.dart';
import '../../models/payment_certificate.dart';
import '../../services/payment_certificate_service.dart';
import '../../theme/app_theme.dart';
import 'add_payment_certificate_screen.dart';

class PaymentCertificateListScreen extends StatefulWidget {
  const PaymentCertificateListScreen({super.key});

  @override
  State<PaymentCertificateListScreen> createState() =>
      _PaymentCertificateListScreenState();
}

class _PaymentCertificateListScreenState
    extends State<PaymentCertificateListScreen> {
  final _service = PaymentCertificateService();
  final _searchCtrl = TextEditingController();

  List<PaymentCertificate> _all = [];
  List<PaymentCertificate> _filtered = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
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
              _buildSearchBar(),
              Expanded(child: _buildBody()),
            ],
          ),
        ),
        floatingActionButton: FloatingActionButton(
          onPressed: _openAdd,
          backgroundColor: AppColors.accent,
          child: const Icon(Icons.add, color: Colors.white),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      color: AppColors.bgSurface,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Row(
        children: [
          if (Navigator.canPop(context)) ...[
            GestureDetector(
              onTap: () => Navigator.pop(context),
              child: Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: AppColors.bgSurface2,
                  borderRadius: BorderRadius.circular(9),
                  border: Border.all(color: AppColors.border2, width: 0.5),
                ),
                child: Icon(Icons.arrow_back_rounded,
                    size: 16, color: AppColors.textSecondary),
              ),
            ),
            const SizedBox(width: 12),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'شهادات الدفع',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                    letterSpacing: -0.3,
                  ),
                ),
                if (_all.isNotEmpty)
                  Text(
                    '${_all.length} شهادة',
                    style: TextStyle(
                        fontSize: 11, color: AppColors.textTertiary),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    return Container(
      color: AppColors.bgSurface,
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      child: TextField(
        controller: _searchCtrl,
        onChanged: (_) => setState(() => _applySearch()),
        style: TextStyle(fontSize: 13, color: AppColors.textPrimary),
        decoration: InputDecoration(
          hintText: 'بحث برقم الشهادة، الموضوع...',
          hintStyle: TextStyle(fontSize: 12, color: AppColors.textTertiary),
          prefixIcon:
              Icon(Icons.search, size: 18, color: AppColors.textTertiary),
          isDense: true,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          filled: true,
          fillColor: AppColors.bgSurface2,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide.none,
          ),
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_filtered.isEmpty) {
      return RefreshIndicator(
        onRefresh: _load,
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
                    Icon(Icons.receipt_long_outlined,
                        size: 48, color: AppColors.bgSurface3),
                    const SizedBox(height: 12),
                    Text(
                      _searchCtrl.text.isNotEmpty
                          ? 'لا توجد نتائج'
                          : 'لا توجد شهادات بعد',
                      style: TextStyle(
                          fontSize: 14, color: AppColors.textTertiary),
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
      onRefresh: _load,
      color: AppColors.accent,
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 80),
        itemCount: _filtered.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (_, i) => _buildCard(_filtered[i]),
      ),
    );
  }

  Widget _buildCard(PaymentCertificate cert) {
    return GestureDetector(
      onTap: () => _openEdit(cert),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.bgSurface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.border, width: 0.5),
        ),
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
                // Copy button
                GestureDetector(
                  onTap: () => _openCopy(cert),
                  child: Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: AppColors.bgSurface2,
                      borderRadius: BorderRadius.circular(7),
                    ),
                    child: Icon(Icons.copy_outlined,
                        size: 14, color: AppColors.textTertiary),
                  ),
                ),
                const SizedBox(width: 6),
                // Delete button
                GestureDetector(
                  onTap: () => _confirmDelete(cert),
                  child: Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: AppColors.bgSurface2,
                      borderRadius: BorderRadius.circular(7),
                    ),
                    child: Icon(Icons.delete_outline,
                        size: 14, color: AppColors.textTertiary),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            // Info chips
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
