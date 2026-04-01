import 'package:flutter/material.dart';

class FilterController extends ChangeNotifier {

  String searchQuery = "";
  String statusFilter = "All";
  DateTime? selectedDate;
  String? selectedEmployeeId;

  String? selectedFileType;
  String? expirationFilter; // 'expired' | 'expiring_soon' | 'active' | null

  
  void setFileType(String? type) {
    selectedFileType = type;
    notifyListeners();
  }

  void setExpirationFilter(String? filter) {
    expirationFilter = filter;
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
    expirationFilter = null;
    notifyListeners();
  }
}