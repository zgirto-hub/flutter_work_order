import 'package:flutter/material.dart';
import '../../../models/payment_certificate.dart';
import '../../../services/payment_certificate_service.dart';

class PaymentCertPicker extends StatefulWidget {
  final List<String> alreadySelectedIds;
  const PaymentCertPicker({super.key, required this.alreadySelectedIds});

  static Future<List<PaymentCertificate>?> show(
    BuildContext context, {
    required List<String> alreadySelectedIds,
  }) =>
      showModalBottomSheet<List<PaymentCertificate>>(
        context: context,
        isScrollControlled: true,
        builder: (_) =>
            PaymentCertPicker(alreadySelectedIds: alreadySelectedIds),
      );

  @override
  State<PaymentCertPicker> createState() => _PaymentCertPickerState();
}

class _PaymentCertPickerState extends State<PaymentCertPicker> {
  final _searchController = TextEditingController();
  List<PaymentCertificate> _allCerts = [];
  List<PaymentCertificate> _filteredCerts = [];
  final Set<String> _selectedIds = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadCerts();
  }

  Future<void> _loadCerts() async {
    try {
      final certs = await PaymentCertificateService().listAll();
      setState(() {
        _allCerts = certs;
        _filteredCerts = certs
            .where((c) => !widget.alreadySelectedIds.contains(c.id))
            .toList();
        _loading = false;
      });
    } catch (e) {
      setState(() => _loading = false);
    }
  }

  void _filter(String query) {
    final q = query.toLowerCase();
    setState(() {
      _filteredCerts = _allCerts.where((c) {
        final inSearch = q.isEmpty ||
            c.certificateNumber.toLowerCase().contains(q) ||
            c.subject.toLowerCase().contains(q);
        final notSelected = !widget.alreadySelectedIds.contains(c.id) &&
            !_selectedIds.contains(c.id);
        return inSearch && notSelected;
      }).toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.5,
      maxChildSize: 0.9,
      expand: false,
      builder: (context, scrollController) {
        return Container(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Select Payment Certificates',
                      style: Theme.of(context).textTheme.titleLarge),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _searchController,
                decoration: const InputDecoration(
                  hintText: 'Search by certificate number or subject',
                  prefixIcon: Icon(Icons.search),
                  border: OutlineInputBorder(),
                ),
                onChanged: _filter,
              ),
              const SizedBox(height: 12),
              Expanded(
                child: _loading
                    ? const Center(child: CircularProgressIndicator())
                    : _filteredCerts.isEmpty
                        ? const Center(child: Text('No certificates available'))
                        : ListView.builder(
                            controller: scrollController,
                            itemCount: _filteredCerts.length,
                            itemBuilder: (context, index) {
                              final cert = _filteredCerts[index];
                              return CheckboxListTile(
                                value: _selectedIds.contains(cert.id),
                                onChanged: (selected) {
                                  setState(() {
                                    if (selected == true) {
                                      _selectedIds.add(cert.id);
                                    } else {
                                      _selectedIds.remove(cert.id);
                                    }
                                  });
                                },
                                title: Text(cert.certificateNumber),
                                subtitle: Text(cert.subject,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis),
                              );
                            },
                          ),
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: () {
                      final selected = _allCerts
                          .where((c) => _selectedIds.contains(c.id))
                          .toList();
                      Navigator.pop(context, selected);
                    },
                    child: const Text('Add'),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}
