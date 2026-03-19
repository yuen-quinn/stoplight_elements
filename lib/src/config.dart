class OpenApiConfig {
  static String title = 'Stoplight Elements API Documentation';
  static String version = '1.0.0';
  static String description = 'API documentation generated automatically';
  static String serverUrl = 'http://localhost:8000/api/v1/';
  static bool enableDebug = true;
  static List<String> defaultSchemes = ['http', 'https'];

  static Map<String, dynamic> get info => {
    'title': title,
    'version': version,
    'description': description,
  };

  static List<Map<String, dynamic>> get servers => [
    {'url': serverUrl, 'description': 'Development Server'},
  ];
}
