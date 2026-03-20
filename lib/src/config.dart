class OpenApiConfig {
  static String title = 'Stoplight Elements API Documentation';
  static String version = '1.0.0';
  static String description = 'API documentation generated automatically';
  static String serverUrl = 'http://localhost:8000/api/v1/';
  static bool enableDebug = true;
  static List<String> defaultSchemes = ['http', 'https'];

  /// Single entry point to apply settings before generating OpenAPI JSON
  /// (for example via `OpenApiRegistry.instance.buildOpenApi()`).
  ///
  /// Only non-null arguments are applied; omitted arguments keep existing values.
  static void configure({
    String? title,
    String? version,
    String? description,
    String? serverUrl,
    bool? enableDebug,
    List<String>? defaultSchemes,
  }) {
    if (title != null) OpenApiConfig.title = title;
    if (version != null) OpenApiConfig.version = version;
    if (description != null) OpenApiConfig.description = description;
    if (serverUrl != null) OpenApiConfig.serverUrl = serverUrl;
    if (enableDebug != null) OpenApiConfig.enableDebug = enableDebug;
    if (defaultSchemes != null) {
      OpenApiConfig.defaultSchemes = List<String>.from(defaultSchemes);
    }
  }

  static Map<String, dynamic> get info => {
    'title': title,
    'version': version,
    'description': description,
  };

  static List<Map<String, dynamic>> get servers => [
    {'url': serverUrl, 'description': 'Development Server'},
  ];
}
