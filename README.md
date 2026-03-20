# stoplight_elements

A Dart package for OpenAPI generation and Stoplight Elements page rendering.
Define endpoints and models with annotations, auto-scan them at runtime, and expose both OpenAPI JSON and an interactive docs UI.

## Features

- Annotation-based API documentation with `@ApiPath`, `@ApiModel`, and `@ApiTag`
- Runtime auto-scan via `OpenApiRegistry.instance.autoScan(...)`
- OpenAPI `3.0.3` generation with `buildOpenApi()`
- Security scheme registration (for example, JWT Bearer)
- Built-in HTML generator for Stoplight Elements using `buildStoplightElementsHtml(...)`
- Basic generic schema support such as `BaseResponse<HealthData>`

## Installation

Add this package to your `pubspec.yaml`:

```yaml
dependencies:
  stoplight_elements: ^0.0.3
```

Then run:

```bash
dart pub get
```

## Import

If your application re-exports OpenAPI modules from an internal package:

```dart
import 'package:your_app/openapi/stoplight_elements.dart';
import 'package:your_app/openapi/generator.dart';
```

Or import this package directly:

```dart
import 'package:stoplight_elements/stoplight_elements.dart';
```

## Vania Integration Example

### 1) OpenAPI JSON endpoint and docs page

```dart
import 'package:your_app/openapi/stoplight_elements.dart';
import 'package:your_app/openapi/generator.dart';
import 'package:vania/http/controller.dart';
import 'package:vania/http/response.dart';

class OpenApiController extends Controller {
  /// Returns OpenAPI JSON spec
  Future<Response> spec() async {
    try {
      final openApiSpec = OpenApiRegistry.instance.buildOpenApi();
      return Response.json(openApiSpec);
    } catch (e, stackTrace) {
      return Response.json({
        'error': 'Failed to generate OpenAPI spec',
        'message': e.toString(),
        'stackTrace': stackTrace.toString(),
      });
    }
  }

  /// Stoplight Elements docs page
  Future<Response> docs() async {
    final html = buildStoplightElementsHtml(
      openapiUrl: '/openapi.json',
    );
    return Response.html(html);
  }
}

final OpenApiController openApiController = OpenApiController();
```

### 2) Register security scheme and auto-scan in `ServiceProvider`

```dart
class RouteServiceProvider extends ServiceProvider {
  @override
  Future<void> boot() async {}

  @override
  Future<void> register() async {
    V1Route().register();

    OpenApiRegistry.instance.registerSecurityScheme(
      'authorization',
      ApiSecurityScheme(
        type: 'http',
        scheme: 'bearer',
        bearerFormat: 'JWT',
        description: 'JWT Bearer authentication',
      ),
    );

    OpenApiRegistry.instance.autoScan(
      libraryFilter: (uri) => uri.toString().startsWith('package:your_app/'),
    );

    OpenApiRoute().register();
  }
}
```

### 3) Define models and endpoints with annotations

```dart
@ApiModel(
  description: 'Health check response payload',
  properties: {
    'status': ApiProperty(type: 'string', description: 'Service status', example: 'ok'),
    'timestamp': ApiProperty(type: 'string', description: 'Current timestamp', example: '2023-01-01T00:00:00.000Z'),
    'service': ApiProperty(type: 'string', description: 'Service name', example: 'example_api'),
  },
)
class HealthData {
  final String status;
  final String timestamp;
  final String service;

  HealthData({
    required this.status,
    required this.timestamp,
    required this.service,
  });

  Map<String, dynamic> toJson() => {
        'status': status,
        'timestamp': timestamp,
        'service': service,
      };
}

@ApiTag(name: 'Health', description: 'Health-related APIs')
class HealthController extends Controller {
  @ApiPath(
    path: '/health',
    method: 'GET',
    tags: ['Health'],
    summary: 'Health check',
    description: 'Checks whether the API service is running normally',
    responses: {
      200: ApiResponse(
        code: 200,
        description: 'Service is healthy',
        schema: 'BaseResponse<HealthData>',
      ),
    },
  )
  Future<Response> health() async {
    final healthData = HealthData(
      status: 'ok',
      timestamp: DateTime.now().toIso8601String(),
      service: 'example_api',
    );
    return R.ok(data: healthData.toJson());
  }
}

final HealthController healthController = HealthController();
```

## Recommended Routes

- `GET /openapi.json`: returns OpenAPI JSON
- `GET /docs`: returns Stoplight Elements HTML page

## Common APIs

- `OpenApiRegistry.instance.registerSecurityScheme(name, scheme)`
- `OpenApiRegistry.instance.autoScan(...)`
- `OpenApiRegistry.instance.buildOpenApi()`
- `buildStoplightElementsHtml(...)`

## Optional Configuration

You can customize documentation metadata through `OpenApiConfig`:

- `OpenApiConfig.title`
- `OpenApiConfig.version`
- `OpenApiConfig.description`
- `OpenApiConfig.serverUrl`
- `OpenApiConfig.enableDebug`
- `OpenApiConfig.defaultSchemes`

Recommended: use the single entry point `OpenApiConfig.configure(...)` (call before `autoScan` / `buildOpenApi`):

```dart
OpenApiConfig.configure(
  title: 'Example API',
  version: '1.0.0',
  description: 'Example API documentation',
  serverUrl: 'http://localhost:8000/api/v1/',
  enableDebug: true,
  defaultSchemes: ['http', 'https'],
);
```

You can also assign fields directly:

```dart
OpenApiConfig.title = 'Example API';
OpenApiConfig.version = '1.0.0';
OpenApiConfig.description = 'Example API documentation';
OpenApiConfig.serverUrl = 'http://localhost:8000/api/v1/';
```

## Notes

- This package uses `dart:mirrors` for runtime scanning. Ensure your deployment target supports mirrors.
- For better performance, use `libraryFilter` to limit scan scope.

## License

MIT
