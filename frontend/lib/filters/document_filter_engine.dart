import '../models/document.dart';
import '../controllers/filter_controller.dart';

class DocumentFilterEngine {

  static List<DocumentModel> applyFilters(
    List<DocumentModel> documents,
    FilterController filter,
  ) {

    List<DocumentModel> filtered = List.from(documents);

    if (filter.searchQuery.isNotEmpty) {

      final query = filter.searchQuery.toLowerCase();

      filtered = filtered.where((doc) {

        final titleMatch =
            doc.title.toLowerCase().contains(query);

        final typeMatch =
            doc.documentType.toLowerCase().contains(query);

        final textMatch =
            doc.parsedText?.toLowerCase().contains(query) ?? false;

        return titleMatch || typeMatch || textMatch;

      }).toList();
    }
    // DOCUMENT TYPE FILTER
    if (filter.selectedDocumentType != null &&
        filter.selectedDocumentType!.isNotEmpty) {
      filtered = filtered.where((doc) {
        return doc.documentType == filter.selectedDocumentType;
      }).toList();
    }

    // EXPIRATION FILTER
    if (filter.expirationFilter != null) {
      switch (filter.expirationFilter) {
        case 'expired':
          filtered = filtered.where((doc) => doc.isExpired).toList();
          break;
        case 'expiring_soon':
          filtered = filtered.where((doc) => doc.isExpiringSoon).toList();
          break;
        case 'active':
          filtered = filtered
              .where((doc) =>
                  doc.expirationDate != null &&
                  !doc.isExpired &&
                  !doc.isExpiringSoon)
              .toList();
          break;
      }
    }

    return filtered;
  }
}