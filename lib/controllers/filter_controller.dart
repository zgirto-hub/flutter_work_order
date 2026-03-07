import 'package:flutter/material.dart';

class FilterController extends ChangeNotifier {

  String searchQuery = "";
  String statusFilter = "All";
  DateTime? selectedDate;
  String? selectedEmployeeId;

  String? selectedDocumentType;

  
  void setDocumentType(String? type) {
  selectedDocumentType = type;
  notifyListeners();
}

  void setSearchQuery(String value) {
    searchQuery = value;
    notifyListeners();
  }

  void setStatus(String status) {
    statusFilter = status;
    notifyListeners();
  }

  void setDate(DateTime? date) {
    selectedDate = date;
    notifyListeners();
  }

  void setEmployee(String? id) {
    selectedEmployeeId = id;
    notifyListeners();
  }

  void clearAll() {
    searchQuery = "";
    statusFilter = "All";
    selectedDate = null;
    selectedEmployeeId = null;
    notifyListeners();
  }
}