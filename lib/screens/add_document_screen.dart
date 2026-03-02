import 'package:flutter/material.dart';
import '../services/document_service.dart';
import 'package:file_picker/file_picker.dart';
import 'package:http/http.dart' as http;

class AddDocumentScreen extends StatefulWidget {
  const AddDocumentScreen({super.key});

  @override
  State<AddDocumentScreen> createState() => _AddDocumentScreenState();
}

class _AddDocumentScreenState extends State<AddDocumentScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _typeController = TextEditingController();
  final _contentController = TextEditingController();

  final DocumentService _service = DocumentService();
  bool _isLoading = false;
  Future<void> _pickAndUploadFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf', 'doc', 'docx', 'txt', 'jpg', 'jpeg', 'png'],
    );

    if (result == null) return;

    final file = result.files.single;

    setState(() => _isLoading = true);

    final request = http.MultipartRequest(
      'POST',
      Uri.parse('http://100.92.159.81:8000/upload'),
    );

    request.files.add(
      await http.MultipartFile.fromPath(
        'file',
        file.path!,
        filename: file.name,
      ),
    );

    request.fields['title'] = _titleController.text;
    request.fields['document_type'] = _typeController.text;

    final response = await request.send();

    setState(() => _isLoading = false);

    if (response.statusCode == 200) {
      if (mounted) Navigator.pop(context, true);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Upload failed")),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Add Document")),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              TextFormField(
                controller: _titleController,
                decoration: const InputDecoration(labelText: "Title"),
                validator: (value) =>
                    value == null || value.isEmpty ? "Required" : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _typeController,
                decoration: const InputDecoration(labelText: "Document Type"),
                validator: (value) =>
                    value == null || value.isEmpty ? "Required" : null,
              ),
              const SizedBox(height: 16),
              Expanded(
                child: TextFormField(
                  controller: _contentController,
                  maxLines: null,
                  expands: true,
                  decoration:
                      const InputDecoration(labelText: "Document Content"),
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _pickAndUploadFile,
                  child: _isLoading
                      ? const CircularProgressIndicator()
                      : const Text("Upload"),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
