class AssetSystemLink {
  final String id;
  final String system;
  final String role;
  final String site;
  final String createdAt;

  AssetSystemLink({
    required this.id,
    required this.system,
    required this.role,
    required this.site,
    required this.createdAt,
  });

  factory AssetSystemLink.fromJson(Map<String, dynamic> json) {
    return AssetSystemLink(
      id: json['id'] as String,
      system: json['system'] as String,
      role: json['role'] as String,
      site: json['site'] as String? ?? 'production',
      createdAt: json['created_at'] as String,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'system': system,
      'role': role,
      'site': site,
      'created_at': createdAt,
    };
  }
}

class Asset {
  final String id;
  final String name;
  final String type;
  final String location;
  final String notes;
  final String createdAt;
  final String updatedAt;
  final List<AssetSystemLink> systemLinks;

  Asset({
    required this.id,
    required this.name,
    required this.type,
    required this.location,
    required this.notes,
    required this.createdAt,
    required this.updatedAt,
    required this.systemLinks,
  });

  static const List<String> assetTypes = [
    'workstation',
    'server',
    'camera',
    'router',
    'switch',
    'media_converter',
    'power_adapter',
  ];

  static String displayType(String type) => type.replaceAll('_', ' ');

  static const List<String> linkRoles = [
    'primary',
    'standby',
    'client',
  ];

  factory Asset.fromJson(Map<String, dynamic> json) {
    return Asset(
      id: json['id'] as String,
      name: json['name'] as String,
      type: json['type'] as String,
      location: json['location'] as String,
      notes: json['notes'] as String? ?? '',
      createdAt: json['created_at'] as String,
      updatedAt: json['updated_at'] as String,
      systemLinks: (json['system_links'] as List<dynamic>?)
              ?.map((e) => AssetSystemLink.fromJson(e))
              .toList() ??
          [],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'type': type,
      'location': location,
      'notes': notes,
      'created_at': createdAt,
      'updated_at': updatedAt,
      'system_links': systemLinks.map((e) => e.toJson()).toList(),
    };
  }

  Asset copyWith({
    String? id,
    String? name,
    String? type,
    String? location,
    String? notes,
    String? createdAt,
    String? updatedAt,
    List<AssetSystemLink>? systemLinks,
  }) {
    return Asset(
      id: id ?? this.id,
      name: name ?? this.name,
      type: type ?? this.type,
      location: location ?? this.location,
      notes: notes ?? this.notes,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      systemLinks: systemLinks ?? this.systemLinks,
    );
  }
}
