import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../config.dart' as config;
import '../../models/work_order.dart';

class SearchResult {
  final List<WorkOrder> workOrders;
  final int totalCount;
  final Map<String, int> facets;
  final Duration searchTime;

  SearchResult({
    required this.workOrders,
    required this.totalCount,
    required this.facets,
    required this.searchTime,
  });

  factory SearchResult.empty() {
    return SearchResult(
      workOrders: [],
      totalCount: 0,
      facets: {},
      searchTime: Duration.zero,
    );
  }
}

class SearchFilters {
  final String? query;
  final List<String>? status;
  final List<String>? priority;
  final String? assignedTo;
  final DateTime? createdAfter;
  final DateTime? createdBefore;
  final List<String>? tags;
  final SortOrder sortBy;
  final SortDirection sortDirection;

  SearchFilters({
    this.query,
    this.status,
    this.priority,
    this.assignedTo,
    this.createdAfter,
    this.createdBefore,
    this.tags,
    this.sortBy = SortOrder.relevance,
    this.sortDirection = SortDirection.desc,
  });

  SearchFilters copyWith({
    String? query,
    List<String>? status,
    List<String>? priority,
    String? assignedTo,
    DateTime? createdAfter,
    DateTime? createdBefore,
    List<String>? tags,
    SortOrder? sortBy,
    SortDirection? sortDirection,
  }) {
    return SearchFilters(
      query: query ?? this.query,
      status: status ?? this.status,
      priority: priority ?? this.priority,
      assignedTo: assignedTo ?? this.assignedTo,
      createdAfter: createdAfter ?? this.createdAfter,
      createdBefore: createdBefore ?? this.createdBefore,
      tags: tags ?? this.tags,
      sortBy: sortBy ?? this.sortBy,
      sortDirection: sortDirection ?? this.sortDirection,
    );
  }

  Map<String, String> toQueryParams() {
    final params = <String, String>{};
    
    if (query != null && query!.isNotEmpty) {
      params['q'] = query!;
    }
    if (status != null && status!.isNotEmpty) {
      params['status'] = status!.join(',');
    }
    if (priority != null && priority!.isNotEmpty) {
      params['priority'] = priority!.join(',');
    }
    if (assignedTo != null) {
      params['assigned_to'] = assignedTo!;
    }
    if (createdAfter != null) {
      params['created_after'] = createdAfter!.toIso8601String();
    }
    if (createdBefore != null) {
      params['created_before'] = createdBefore!.toIso8601String();
    }
    if (tags != null && tags!.isNotEmpty) {
      params['tags'] = tags!.join(',');
    }
    
    params['sort_by'] = sortBy.value;
    params['sort_dir'] = sortDirection.value;
    
    return params;
  }
}

enum SortOrder {
  relevance('relevance'),
  createdAt('created_at'),
  updatedAt('updated_at'),
  priority('priority'),
  status('status');

  final String value;
  const SortOrder(this.value);
}

enum SortDirection {
  asc('asc'),
  desc('desc');

  final String value;
  const SortDirection(this.value);
}

class AdvancedSearchService {
  final String baseUrl;
  final http.Client _client;
  final Duration _timeout;

  AdvancedSearchService({
    String? baseUrl,
    http.Client? client,
    Duration? timeout,
  })  : baseUrl = baseUrl ?? config.AppConfig.baseUrl,
        _client = client ?? http.Client(),
        _timeout = timeout ?? const Duration(seconds: 10);

  Future<SearchResult> search({
    required String query,
    SearchFilters? filters,
    int page = 1,
    int pageSize = 20,
  }) async {
    final stopwatch = Stopwatch()..start();
    
    try {
      final params = filters?.toQueryParams() ?? {};
      params['page'] = page.toString();
      params['page_size'] = pageSize.toString();
      
      final uri = Uri.parse('$baseUrl/api/search/work-orders')
          .replace(queryParameters: params);
      
      final response = await _client.get(
        uri,
        headers: {'Content-Type': 'application/json'},
      ).timeout(_timeout);

      if (response.statusCode == 200) {
        stopwatch.stop();
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        
        return SearchResult(
          workOrders: (data['items'] as List)
              .map((json) => WorkOrder.fromJson(json as Map<String, dynamic>))
              .toList(),
          totalCount: data['total'] as int? ?? 0,
          facets: Map<String, int>.from(data['facets'] as Map? ?? {}),
          searchTime: stopwatch.elapsed,
        );
      } else {
        throw SearchException('Search failed: ${response.statusCode}');
      }
    } catch (e) {
      stopwatch.stop();
      if (e is SearchException) rethrow;
      throw SearchException('Search error: $e');
    }
  }

  Future<List<String>> getSuggestions(String prefix) async {
    try {
      final uri = Uri.parse('$baseUrl/api/search/suggestions')
          .replace(queryParameters: {'prefix': prefix});
      
      final response = await _client.get(
        uri,
        headers: {'Content-Type': 'application/json'},
      ).timeout(_timeout);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as List;
        return data.cast<String>();
      }
      return [];
    } catch (e) {
      return [];
    }
  }

  Future<Map<String, int>> getFacets(SearchFilters filters) async {
    try {
      final uri = Uri.parse('$baseUrl/api/search/facets')
          .replace(queryParameters: filters.toQueryParams());
      
      final response = await _client.get(
        uri,
        headers: {'Content-Type': 'application/json'},
      ).timeout(_timeout);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        return Map<String, int>.from(data);
      }
      return {};
    } catch (e) {
      return {};
    }
  }

  void dispose() {
    _client.close();
  }
}

class SearchException implements Exception {
  final String message;
  SearchException(this.message);
  
  @override
  String toString() => message;
}
