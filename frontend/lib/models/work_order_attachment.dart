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
      id: json['id'] as String,
      workOrderId: json['work_order_id'] as String,
      fileName: json['file_name'] as String,
      fileUrl: json['file_url'] as String,
      fileType: json['file_type'] as String? ?? 'application/octet-stream',
      createdAt: DateTime.parse(json['created_at'] as String),
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
