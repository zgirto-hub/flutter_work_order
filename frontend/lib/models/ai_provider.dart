class AiProvider {
  final String key;
  final String displayName;

  const AiProvider({
    required this.key,
    required this.displayName,
  });

  factory AiProvider.fromJson(Map<String, dynamic> json) {
    return AiProvider(
      key: json['key'] ?? '',
      displayName: json['display_name'] ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'key': key,
      'display_name': displayName,
    };
  }
}

class AiProvidersResponse {
  final List<AiProvider> providers;
  final String active;

  const AiProvidersResponse({
    required this.providers,
    required this.active,
  });

  factory AiProvidersResponse.fromJson(Map<String, dynamic> json) {
    final providersList = (json['providers'] as List<dynamic>?)
        ?.map((p) => AiProvider.fromJson(p as Map<String, dynamic>))
        .toList();
    return AiProvidersResponse(
      providers: providersList ?? [],
      active: json['active'] ?? 'local',
    );
  }
}
