import 'package:flutter/material.dart';

class WorkOrderAttachment {
  final String id;
  final String workOrderId;
  final String fileName;
  final String fileUrl;
  final String fileType;
  final DateTime createdAt;

  const WorkOrderAttachment({
    required this.id,
    required this.workOrderId,
    required this.fileName,
    required this.fileUrl,
    required this.fileType,
    required this.createdAt,
  });

  factory WorkOrderAttachment.fromJson(Map<String, dynamic> json) {
    return WorkOrderAttachment(
      id: (json['id'] ?? '').toString(),
      workOrderId: (json['work_order_id'] ?? '').toString(),
      fileName: (json['file_name'] ?? '').toString(),
      fileUrl: (json['file_url'] ?? '').toString(),
      fileType: (json['file_type'] ?? 'application/octet-stream').toString(),
      createdAt: DateTime.tryParse(json['created_at']?.toString() ?? '') ??
          DateTime.now(),
    );
  }

  bool get isImage => fileType.startsWith('image/');

  String get extension {
    final parts = fileName.split('.');
    return parts.length > 1 ? parts.last.toLowerCase() : '';
  }

  IconData get icon {
    switch (extension) {
      case 'pdf':
        return Icons.picture_as_pdf;
      case 'doc':
      case 'docx':
        return Icons.description;
      case 'jpg':
      case 'jpeg':
      case 'png':
      case 'gif':
        return Icons.image;
      default:
        return Icons.insert_drive_file;
    }
  }
}
