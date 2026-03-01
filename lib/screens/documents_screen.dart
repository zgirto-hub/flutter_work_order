import 'package:flutter/material.dart';
import '../models/document.dart';
import '../services/document_service.dart';
import 'document_details_screen.dart';

class DocumentsScreen extends StatefulWidget {
  const DocumentsScreen({super.key});

  @override
  State<DocumentsScreen> createState() => _DocumentsScreenState();
}

class _DocumentsScreenState extends State<DocumentsScreen> {
  final DocumentService _service = DocumentService();
  late Future<List<DocumentModel>> _documentsFuture;

  @override
  void initState() {
    super.initState();
    _documentsFuture = _service.fetchDocuments();
  }
Future<void> _refreshDocuments() async {
  setState(() {
    _documentsFuture = _service.fetchDocuments();
  });
}
  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        FutureBuilder<List<DocumentModel>>(
          future: _documentsFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }

            if (snapshot.hasError) {
              return const Center(
                child: Text("Error loading documents"),
              );
            }

            final documents = snapshot.data ?? [];

            if (documents.isEmpty) {
              return const Center(
                child: Text("No documents found"),
              );
            }

            return RefreshIndicator(
  onRefresh: _refreshDocuments,
  child: ListView.builder(  physics: const AlwaysScrollableScrollPhysics(),

    padding: const EdgeInsets.all(16),
    itemCount: documents.length,
    itemBuilder: (context, index) {
      final doc = documents[index];

      return Card(
        margin: const EdgeInsets.only(bottom: 12),
        child: ListTile(
  leading: const Icon(Icons.description),
  title: Text(doc.title),
  subtitle: Text(doc.documentType),
  onTap: () {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => DocumentDetailsScreen(document: doc),
      ),
    );
  },
),
      );
    },
  ),
);
          },
        ),

        Positioned(
          bottom: 16,
          right: 16,
          child: FloatingActionButton(
            onPressed: () {
              // Next step: add document
            },
            child: const Icon(Icons.add),
          ),
        ),
      ],
    );
  }
}