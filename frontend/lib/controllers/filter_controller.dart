import 'package:flutter/material.dart';
import '../models/nl_search_result.dart';

class FilterController extends ChangeNotifier {
  String searchQuery = "";
  String statusFilter = "All";
  DateTime? selectedDate;
  String? selectedEmployeeId;

  String? selectedFileType;
  String? expirationFilter; // 'expired' | 'expiring_soon' | 'active' | null

  bool isNLSearchActive = false;
  NLSearchResult? nlSearchResult;
  bool isNLSearchLoading = false;
  int nlSearchOffset = 0;

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

  void setNLSearchActive(bool active) {
    isNLSearchActive = active;
    notifyListeners();
  }

  void setNLSearchResult(NLSearchResult? result) {
    nlSearchResult = result;
    notifyListeners();
  }

  void setNLSearchLoading(bool loading) {
    isNLSearchLoading = loading;
    notifyListeners();
  }

  void setNLSearchOffset(int offset) {
    nlSearchOffset = offset;
    notifyListeners();
  }

  void clearAll() {
    searchQuery = "";
    statusFilter = "All";
    selectedDate = null;
    selectedEmployeeId = null;
    expirationFilter = null;
    isNLSearchActive = false;
    nlSearchResult = null;
    isNLSearchLoading = false;
    nlSearchOffset = 0;
    notifyListeners();
  }
}
