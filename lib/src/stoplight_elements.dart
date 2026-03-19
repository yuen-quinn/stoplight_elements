class StoplightLayoutOptions {
  static const String sidebar = "sidebar";
  static const String stacked = "stacked";
}

class StoplightRouterOptions {
  static const String history = "history";
  static const String hash = "hash";
  static const String memory = "memory";
  static const String static_ = "static";
}

class StoplightTryItCredentialPolicyOptions {
  static const String omit = "omit";
  static const String include = "include";
  static const String sameOrigin = "same-origin";
}

String buildStoplightElementsHtml({
  required String openapiUrl,
  String title = 'API Documentation',
  String stoplightElementsJsUrl = "https://unpkg.com/@stoplight/elements/web-components.min.js",
  String stoplightElementsCssUrl = "https://unpkg.com/@stoplight/elements/styles.min.css",
  String stoplightElementsFaviconUrl = "https://fastapi.tiangolo.com/img/favicon.png",
  String apiDescriptionDocument = "",
  String basePath = "",
  bool hideInternal = false,
  bool hideTryIt = false,
  String tryItCorsProxy = "",
  String tryItCredentialPolicy = StoplightTryItCredentialPolicyOptions.omit,
  String layout = StoplightLayoutOptions.sidebar,
  String logo = "",
  String router = StoplightRouterOptions.history,
}) {
  return '''
<!DOCTYPE html>
<html lang="zh-CN">
<head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1, shrink-to-fit=no">
    <title>$title</title>
    <link rel="shortcut icon" href="$stoplightElementsFaviconUrl">
    <script src="$stoplightElementsJsUrl"></script>
    <link rel="stylesheet" href="$stoplightElementsCssUrl">
    <style>
        body {
            margin: 0;
            padding: 0;
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
            background: #f8f9fa;
        }
        elements-api {
            height: 100vh;
            width: 100vw;
        }
        .custom-header {
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            color: white;
            padding: 20px;
            text-align: center;
            box-shadow: 0 2px 10px rgba(0,0,0,0.1);
        }
        .custom-header h1 {
            margin: 0;
            font-size: 2.5em;
            font-weight: 300;
        }
        .custom-header p {
            margin: 10px 0 0 0;
            opacity: 0.9;
            font-size: 1.1em;
        }
    </style>
</head>
<body>
    <div class="custom-header">
        <h1>🚀 Vania API Documentation</h1>
        <p>现代化的API文档界面，支持实时测试和交互式探索</p>
    </div>
    <elements-api
        apiDescriptionUrl="$openapiUrl"
        ${apiDescriptionDocument.isNotEmpty ? 'apiDescriptionDocument="$apiDescriptionDocument"' : ''}
        ${basePath.isNotEmpty ? 'basePath="$basePath"' : ''}
        ${hideInternal ? 'hideInternal="true"' : ''}
        ${hideTryIt ? 'hideTryIt="true"' : ''}
        ${tryItCorsProxy.isNotEmpty ? 'tryItCorsProxy="$tryItCorsProxy"' : ''}
        tryItCredentialPolicy="$tryItCredentialPolicy"
        layout="$layout"
        ${logo.isNotEmpty ? 'logo="$logo"' : ''}
        router="$router"
    />
</body>
</html>
''';
}
