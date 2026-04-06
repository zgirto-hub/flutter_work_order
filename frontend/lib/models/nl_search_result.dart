import 'work_order.dart';

class ExtractedFilters {
  final String? status;
  final String? type;
  final String? department;
  final String? location;
  final String? dateFrom;
  final String? dateTo;
  final double? minResolutionDays;

  const ExtractedFilters({
    this.status,
    this.type,
    this.department,
    this.location,
    this.dateFrom,
    this.dateTo,
    this.minResolutionDays,
  });

  factory ExtractedFilters.fromJson(Map<String, dynamic> json) {
    return ExtractedFilters(
      status: json['status'] as String?,
      type: json['type'] as String?,
      department: json['department'] as String?,
      location: json['location'] as String?,
      dateFrom: json['date_from'] as String?,
      dateTo: json['date_to'] as String?,
      minResolutionDays: (json['min_resolution_days'] as num?)?.toDouble(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      if (status != null) 'status': status,
      if (type != null) 'type': type,
      if (department != null) 'department': department,
      if (location != null) 'location': location,
      if (dateFrom != null) 'date_from': dateFrom,
      if (dateTo != null) 'date_to': dateTo,
      if (minResolutionDays != null) 'min_resolution_days': minResolutionDays,
    };
  }

  ExtractedFilters copyWith({
    String? status,
    String? type,
    String? department,
    String? location,
    String? dateFrom,
    String? dateTo,
    double? minResolutionDays,
    bool clearStatus = false,
    bool clearType = false,
    bool clearDepartment = false,
    bool clearLocation = false,
    bool clearDateFrom = false,
    bool clearDateTo = false,
    bool clearMinResolutionDays = false,
  }) {
    return ExtractedFilters(
      status: clearStatus ? null : (status ?? this.status),
      type: clearType ? null : (type ?? this.type),
      department: clearDepartment ? null : (department ?? this.department),
      location: clearLocation ? null : (location ?? this.location),
      dateFrom: clearDateFrom ? null : (dateFrom ?? this.dateFrom),
      dateTo: clearDateTo ? null : (dateTo ?? this.dateTo),
      minResolutionDays: clearMinResolutionDays
          ? null
          : (minResolutionDays ?? this.minResolutionDays),
    );
  }
}

class NLSearchResult {
  final List<WorkOrder> workOrders;
  final int total;
  final ExtractedFilters? filters;
  final bool fallback;

  const NLSearchResult({
    required this.workOrders,
    required this.total,
    this.filters,
    required this.fallback,
  });

  factory NLSearchResult.fromJson(Map<String, dynamic> json) {
    final workOrdersList = json['work_orders'] as List<dynamic>? ?? [];
    return NLSearchResult(
      workOrders: workOrdersList
          .map((e) => WorkOrder.fromJson(e as Map<String, dynamic>))
          .toList(),
      total: json['total'] as int? ?? 0,
      filters: json['filters'] != null
          ? ExtractedFilters.fromJson(json['filters'] as Map<String, dynamic>)
          : null,
      fallback: json['fallback'] as bool? ?? false,
    );
  }
}
