import 'package:flutter/material.dart';

class DocumentsScreen extends StatelessWidget {
  const DocumentsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        const Center(
          child: Text(
            "Documents will appear here",
            style: TextStyle(fontSize: 18),
          ),
        ),
        Positioned(
          bottom: 16,
          right: 16,
          child: FloatingActionButton(
            onPressed: () {
              // Later: Add document
            },
            child: const Icon(Icons.add),
          ),
        ),
      ],
    );
  }
}