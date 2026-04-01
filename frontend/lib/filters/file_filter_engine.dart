import '../models/file_model.dart';
import '../controllers/filter_controller.dart';

class FileFilterEngine {

  static List<FileModel> applyFilters(
    List<FileModel> documents,
    FilterController filter,
  ) {

    List<FileModel> filtered = List.from(documents);

    if (filter.searchQuery.isNotEmpty) {

      final query = filter.searchQuery.toLowerCase();

      filtered = filtered.where((doc) {

        final titleMatch =
            doc.title.toLowerCase().contains(query);

        final typeMatch =
            doc.fileType.toLowerCase().contains(query);

        final textMatch =
            doc.parsedText?.toLowerCase().contains(query) ?? false;

        return titleMatch || typeMatch || textMatch;

      }).toList();
    }
    // DOCUMENT TYPE FILTER
    if (filter.selectedFileType != null &&
        filter.selectedFileType!.isNotEmpty) {
      filtered = filtered.where((doc) {
        return doc.fileType == filter.selectedFileType;
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