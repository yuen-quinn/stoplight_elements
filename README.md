# stoplight_elements

[中文文档](README_zh.md)

A Dart package for OpenAPI 3.0.3 generation with built-in [Stoplight Elements](https://github.com/stoplightio/elements) interactive documentation rendering.

Describe endpoints and data models with annotations such as `@ApiPath` and `@ApiModel`, auto-scan them at runtime to produce OpenAPI JSON, and serve a browsable docs page via `buildStoplightElementsHtml()`.

## Features

- **Annotation-driven**: paths, parameters, request bodies, responses, tags, and security schemes
- **Runtime auto-scan**: `OpenApiRegistry.instance.autoScan()` discovers annotations via `dart:mirrors`
- **OpenAPI 3.0.3 output**: `buildOpenApi()` generates a complete spec
- **Type inference**: omit `type` on field-level `@ApiProperty`; Dart types are inferred automatically
- **Nested types**: `User`, `List<User>`, `Map<String, User>`, etc. map to `$ref` / `array` / `additionalProperties`
- **Nested generics**: fully supports `Result<PaginatedResult<Package>>` and arbitrary nesting depth
- **Generic model expansion**: mark fields with `isGeneric: true` to replace them with the concrete type argument
- **Third-party type bridging**: create standalone `@ApiModel` classes for external generic types (e.g., ORM pagination results)
- **Stoplight Elements HTML**: generate a docs page in one call

## Requirements

- Dart SDK `^3.11.1`
- A runtime that supports `dart:mirrors` (**not** Flutter Web, AOT-compiled standalone binaries, or other reflection-less environments)

## Installation

Add to your `pubspec.yaml`:

```yaml
dependencies:
  stoplight_elements: ^0.0.7
```

Then run:

```bash
dart pub get
```

## Import

```dart
import 'package:stoplight_elements/stoplight_elements.dart';
```

The library entry point exports:

| Module | Contents |
|--------|----------|
| `annotations.dart` | All annotation classes |
| `generator.dart` | `OpenApiRegistry` |
| `config.dart` | `OpenApiConfig` |
| `stoplight_elements.dart` | `buildStoplightElementsHtml()` |

---

## Quick Start

### 1. Configure documentation metadata

Call this at application startup (before `autoScan` / `buildOpenApi`):

```dart
OpenApiConfig.configure(
  title: 'My API',
  version: '1.0.0',
  description: 'API documentation',
  serverUrl: 'http://localhost:8000/api/v1/',
  enableDebug: true,
  defaultSchemes: ['http', 'https'],
);
```

Or assign fields directly:

```dart
OpenApiConfig.title = 'My API';
OpenApiConfig.serverUrl = 'http://localhost:8000/';
```

### 2. Define data models

**Option A: Field-level `@ApiProperty` (recommended)**

Types can be omitted; they are inferred from Dart field types:

```dart
@ApiModel(description: 'Health check response')
class HealthData {
  @ApiProperty(description: 'Service status', example: 'ok')
  final String status;

  @ApiProperty(description: 'Timestamp', example: '2023-01-01T00:00:00.000Z')
  final String timestamp;

  HealthData({required this.status, required this.timestamp});
}
```

**Option B: Class-level `properties` map**

```dart
@ApiModel(
  description: 'Generic response wrapper',
  properties: {
    'code': ApiProperty(type: 'integer', description: 'Business code', example: 0),
    'message': ApiProperty(type: 'string', description: 'Message'),
    'data': ApiProperty(type: 'object', description: 'Payload', isGeneric: true),
  },
)
class BaseResponse {}
```

> Field-level annotations merge with class-level `properties`; **field-level wins**. Undeclared fields are still inferred from Dart types.

### 3. Define endpoints

```dart
@ApiTag(name: 'Health', description: 'Health checks')
class HealthController {
  @ApiPath(
    path: '/health',
    method: 'GET',
    tags: ['Health'],
    summary: 'Health check',
    description: 'Check whether the service is running',
    responses: {
      200: ApiResponse(
        code: 200,
        description: 'Service is healthy',
        schema: 'BaseResponse<HealthData>',
      ),
    },
  )
  Future<Map<String, dynamic>> health() async {
    return {'code': 0, 'message': 'ok', 'data': {'status': 'ok'}};
  }
}
```

Controllers must have a **parameterless default constructor**, otherwise `autoScan` cannot instantiate them to scan method annotations.

### 4. Register and scan

```dart
// Optional: register JWT Bearer or other security schemes
OpenApiRegistry.instance.registerSecurityScheme(
  'authorization',
  ApiSecurityScheme(
    type: 'http',
    scheme: 'bearer',
    bearerFormat: 'JWT',
    description: 'JWT Bearer authentication',
  ),
);

// Auto-scan (use libraryFilter to limit scope)
OpenApiRegistry.instance.autoScan(
  libraryFilter: (uri) => uri.toString().startsWith('package:my_app/'),
);
```

`autoScan` runs **only once** per Isolate (guarded by an internal `_isScanned` flag).

### 5. Expose endpoints

Recommended HTTP routes:

| Route | Purpose |
|-------|---------|
| `GET /openapi.json` | Returns OpenAPI JSON |
| `GET /docs` | Returns the Stoplight Elements docs page |

**Serinus framework example:**

```dart
import 'package:serinus/serinus.dart';
import 'package:stoplight_elements/stoplight_elements.dart';

class OpenApiController extends Controller {
  OpenApiController() : super('/');

  Future<Response> spec(RequestContext ctx) async {
    final spec = OpenApiRegistry.instance.buildOpenApi();
    return Response.json(spec);
  }

  Future<Response> docs(RequestContext ctx) async {
    final html = buildStoplightElementsHtml(
      openapiUrl: '/openapi.json',
      title: 'My API Documentation',
    );
    return Response.html(html);
  }
}
```

Visit `/docs` after startup to view the interactive documentation.

---

## Annotation Reference

### `@ApiPath` — Endpoint path

```dart
@ApiPath(
  path: '/users/{id}',              // required: path
  method: 'GET',                    // required: HTTP method
  summary: 'Get user',              // required: summary
  description: 'Fetch user by ID', // optional: description
  tags: ['Users'],                  // optional: tag groups
  deprecated: false,                // optional: deprecated flag
  parameters: [...],                // optional: path/query/header params
  requestBody: ApiRequestBody(...), // optional: request body
  responses: {200: ApiResponse(...)}, // optional: responses
  security: ['authorization'],      // optional: securitySchemes names
)
```

### `@ApiParameter` — Request parameter

```dart
const ApiParameter(
  name: 'id',
  location: 'path',       // path | query | header | cookie
  description: 'User ID',
  required: true,
  type: 'string',         // OpenAPI type: string | integer | number | boolean
  format: 'uuid',         // optional: uuid, int64, date-time, etc.
  example: '550e8400-e29b-41d4-a716-446655440000',
)
```

### `@ApiRequestBody` — Request body

```dart
const ApiRequestBody(
  description: 'Create user request',
  required: true,
  schema: 'CreateUserRequest',  // model name or generic, e.g. BaseResponse<User>
  example: {'name': 'Alice'},
)
```

### `@ApiResponse` — Response

```dart
const ApiResponse(
  code: 200,
  description: 'Success',
  schema: 'User',                    // model name
  // schema: 'BaseResponse<User>',   // generic expansion
  example: {'id': '1', 'name': 'Alice'},
)
```

### `@ApiTag` — Tag grouping

Apply on a Controller class for the OpenAPI `tags` section:

```dart
@ApiTag(name: 'Users', description: 'User-related endpoints')
class UserController { ... }
```

If `@ApiPath` omits `tags`, the scanner uses the class-level `@ApiTag` name as the default.

### `@ApiModel` — Data model

```dart
@ApiModel(
  description: 'User',
  properties: { ... },  // optional, merged with field annotations
)
class User { ... }
```

### `@ApiProperty` — Model field

```dart
@ApiProperty(
  type: 'string',              // optional, inferred if omitted
  description: 'Username',
  required: true,              // optional, inferred from nullability
  format: 'email',
  example: 'alice@example.com',
  enumValues: ['a', 'b'],      // enum values
  ref: '#/components/schemas/User',  // full $ref
  schema: 'User',              // shorthand → #/components/schemas/User
  items: ApiProperty(...),     // array item schema
  additionalProperties: ApiProperty(...), // Map value schema
  properties: { ... },         // inline object sub-fields
  isGeneric: false,            // mark as generic carrier field (see "Nested Generics")
)
```

### `@ApiSecurityScheme` — Security scheme

Register via `registerSecurityScheme`, not as a class annotation:

```dart
// HTTP Bearer (JWT)
ApiSecurityScheme(
  type: 'http',
  scheme: 'bearer',
  bearerFormat: 'JWT',
  description: 'JWT authentication',
)

// API Key
ApiSecurityScheme(
  type: 'apiKey',
  scheme: 'apiKey',
  name: 'X-API-Key',
  in_: 'header',
  description: 'API Key authentication',
)
```

Reference in `@ApiPath`:

```dart
@ApiPath(
  path: '/profile',
  method: 'GET',
  summary: 'Profile',
  security: ['authorization'],
  responses: { ... },
)
```

---

## Type Inference Rules

When scanning model fields, schemas are generated as follows:

| Dart type | OpenAPI output |
|-----------|----------------|
| `String` | `{ "type": "string" }` |
| `int` | `{ "type": "integer", "format": "int64" }` |
| `double` | `{ "type": "number", "format": "double" }` |
| `bool` | `{ "type": "boolean" }` |
| `DateTime` | `{ "type": "string", "format": "date-time" }` |
| `Enum` subclass | `{ "type": "string" }` |
| `@ApiModel` class `User` | `{ "$ref": "#/components/schemas/User" }` |
| Plain class without `@ApiModel` | inline `{ "type": "object", "properties": {...} }` |
| `List<User>` | `{ "type": "array", "items": { "$ref": "..." } }` |
| `Map<String, User>` | `{ "type": "object", "additionalProperties": { "$ref": "..." } }` |
| `User?` (nullable) | same as above, but `required: false` |
| `dynamic` + `@ApiProperty(schema: 'User')` | `{ "$ref": "#/components/schemas/User" }` |

**Nested example:**

```dart
@ApiModel(description: 'User')
class UserDto {
  @ApiProperty(description: 'ID', required: true)
  final String id;
  UserDto({required this.id});
}

@ApiModel(description: 'Paged result')
class UserPage {
  final List<UserDto> items;   // → array + items.$ref
  final UserDto? current;      // → $ref, required: false
  UserPage({required this.items, this.current});
}

@ApiModel(description: 'Index map')
class UserMap {
  final Map<String, UserDto> byId;  // → additionalProperties.$ref
  UserMap({required this.byId});
}
```

---

## Nested Generics

stoplight_elements supports **arbitrary nesting depth** for generic types. This is achieved through the `isGeneric` flag on `ApiProperty`.

### How it works

When a schema reference contains generic syntax (e.g., `Result<Package>`), the generator:

1. Parses the base type name and generic argument(s)
2. `List<X>` always outputs `{ "type": "array", "items": ... }`
3. For other types: looks up the base model in registered schemas
4. If found, expands all properties, replacing fields marked `isGeneric: true` with the concrete type argument
5. If not found, "penetrates" through to the inner type (e.g., `UnknownWrapper<User>` → `User`)

### Example: Result<T> wrapper

```dart
@ApiModel(
  description: '通用接口响应包装',
  properties: {
    'code': ApiProperty(type: 'integer', description: '状态码', required: true),
    'message': ApiProperty(type: 'string', description: '响应消息', required: true),
    'data': ApiProperty(
      type: 'object',
      description: '响应数据',
      isGeneric: true,  // ← marks this field as the generic carrier
    ),
  },
)
class Result {}
```

Usage in endpoints:

```dart
// Simple generic
schema: 'Result<Package>'

// Nested generics — fully supported
schema: 'Result<List<PackageVersion>>'
schema: 'Result<PaginatedResult<Package>>'
```

### Expansion chain for `Result<PaginatedResult<Package>>`

```
Result
├── code    → { "type": "integer" }              // unchanged
├── message → { "type": "string" }               // unchanged
└── data    → PaginatedResult<Package>           // isGeneric → recurse
              ├── items   → Package              // isGeneric → recurse
              ├── total   → { "type": "integer" }
              ├── page    → { "type": "integer" }
              ├── pageSize → { "type": "integer" }
              └── pageCount → { "type": "integer" }
```

### Multiple generic carriers

A single model can have multiple `isGeneric: true` fields. All of them will be replaced with the same generic argument:

```dart
@ApiModel(properties: {
  'current': ApiProperty(isGeneric: true),  // both replaced
  'next': ApiProperty(isGeneric: true),     // with the same type
})
class DualWrapper {}
```

### Bridging third-party generic types

For generic types from external packages (e.g., ORM pagination results) that you cannot modify, create a standalone `@ApiModel` class in your project:

```dart
// file: lib/shared/api_doc_models.dart

@ApiModel(
  description: '分页查询结果',
  properties: {
    'items': ApiProperty(type: 'array', description: '数据列表', isGeneric: true, required: true),
    'total': ApiProperty(type: 'integer', description: '总记录数', required: true),
    'page': ApiProperty(type: 'integer', description: '当前页码', required: true),
    'pageSize': ApiProperty(type: 'integer', description: '每页大小', required: true),
    'pageCount': ApiProperty(type: 'integer', description: '总页数', required: true),
  },
)
class PaginatedResult {}
```

Ensure this file is imported somewhere reachable by `autoScan` (e.g., via your app's barrel export file), so the scanner discovers the `@ApiModel` annotation.

---

## OpenApiRegistry API

`OpenApiRegistry` is a singleton accessed via `OpenApiRegistry.instance`.

| Method | Description |
|--------|-------------|
| `autoScan({libraryFilter})` | Scan annotations in all libraries of the current Isolate; filter by URI |
| `scanController(Object controller)` | Manually scan a single Controller instance |
| `scanModel(Type type, {String? name})` | Manually scan a single model class |
| `scanModelByName(String name, ClassMirror mirror)` | Internal: scan by class name |
| `registerPath(ApiPath path)` | Manually register a path |
| `registerModel(String name, ApiModel model)` | Manually register a schema |
| `registerSecurityScheme(String name, ApiSecurityScheme scheme)` | Register a security scheme |
| `registerTag(ApiTag tag)` | Register a tag |
| `buildOpenApi()` | Generate the full OpenAPI 3.0.3 JSON |
| `resetForTesting()` | Clear the registry (for tests) |

### libraryFilter examples

```dart
// Scan only your application package
OpenApiRegistry.instance.autoScan(
  libraryFilter: (uri) => uri.toString().startsWith('package:my_app/'),
);

// Scan only a test file
OpenApiRegistry.instance.autoScan(
  libraryFilter: (uri) => uri.toString().contains('my_test.dart'),
);
```

---

## buildStoplightElementsHtml Parameters

Generates a full HTML page embedding Stoplight Elements Web Components:

```dart
final html = buildStoplightElementsHtml(
  openapiUrl: '/openapi.json',        // required: OpenAPI JSON URL
  title: 'API Documentation',       // page title
  stoplightElementsJsUrl: 'https://unpkg.com/@stoplight/elements/web-components.min.js',
  stoplightElementsCssUrl: 'https://unpkg.com/@stoplight/elements/styles.min.css',
  stoplightElementsFaviconUrl: 'https://fastapi.tiangolo.com/img/favicon.png',
  apiDescriptionDocument: '',         // inline OpenAPI doc (alternative to URL)
  basePath: '',                       // API base path
  hideInternal: false,                // hide x-internal operations
  hideTryIt: false,                   // hide Try It panel
  tryItCorsProxy: '',                 // CORS proxy URL
  tryItCredentialPolicy: StoplightTryItCredentialPolicyOptions.omit,
  layout: StoplightLayoutOptions.sidebar,  // sidebar | stacked
  logo: '',                           // logo URL
  router: StoplightRouterOptions.history,  // history | hash | memory | static
);
```

### Layout and router constants

```dart
// Layout
StoplightLayoutOptions.sidebar   // sidebar (default)
StoplightLayoutOptions.stacked   // stacked

// Router mode
StoplightRouterOptions.history   // History API (default)
StoplightRouterOptions.hash      // hash routing
StoplightRouterOptions.memory    // memory routing
StoplightRouterOptions.static_   // static routing

// Try It credential policy
StoplightTryItCredentialPolicyOptions.omit
StoplightTryItCredentialPolicyOptions.include
StoplightTryItCredentialPolicyOptions.sameOrigin
```

### Cross-origin Try It

If the API and docs page are on different origins, configure a CORS proxy:

```dart
buildStoplightElementsHtml(
  openapiUrl: '/openapi.json',
  tryItCorsProxy: 'https://cors.example.com/',
);
```

---

## Full Integration Example (Serinus)

```dart
// ── models/health.dart ──
@ApiModel(description: 'Health check data')
class HealthData {
  @ApiProperty(description: 'Status', example: 'ok')
  final String status;

  @ApiProperty(description: 'Service name', example: 'my_api')
  final String service;

  HealthData({required this.status, required this.service});

  Map<String, dynamic> toJson() => {'status': status, 'service': service};
}

// ── shared/result.dart ──
@ApiModel(
  description: '通用接口响应包装',
  properties: {
    'code': ApiProperty(type: 'integer', description: '状态码', required: true),
    'message': ApiProperty(type: 'string', description: '消息', required: true),
    'data': ApiProperty(type: 'object', description: '数据', isGeneric: true),
  },
)
class Result {
  final int code;
  final String message;
  final Object? data;
  Result({required this.code, required this.message, this.data});
  factory Result.ok({String message = 'OK', Object? data}) =>
      Result(code: 200, message: message, data: data);
}

// ── controllers/health_controller.dart ──
@ApiTag(name: 'Health', description: 'Health checks')
class HealthController extends Controller {
  HealthController() : super('/health') {
    on(Route.get('/'), health);
  }

  @ApiPath(
    path: '/health',
    method: 'GET',
    tags: ['Health'],
    summary: 'Health check',
    responses: {
      200: ApiResponse(
        code: 200,
        description: 'OK',
        schema: 'Result<HealthData>',
      ),
    },
  )
  Future<Result> health(RequestContext ctx) async {
    return Result.ok(data: HealthData(status: 'ok', service: 'my_api'));
  }
}

// ── bootstrap.dart ──
Future<void> bootstrap() async {
  OpenApiConfig.configure(
    title: 'My API',
    version: '1.0.0',
    serverUrl: 'http://localhost:8000/api/v1/',
  );

  OpenApiRegistry.instance.autoScan(
    libraryFilter: (uri) => uri.toString().startsWith('package:my_app/'),
  );

  // Start your server and register OpenAPI routes...
}
```

---

## Notes

1. **`dart:mirrors` limitation**  
   This package relies on runtime reflection. It does not work on Flutter Web, AOT-compiled native binaries, or similar environments. Use it on the Dart VM (server-side).

2. **`autoScan` runs once**  
   Repeated calls in the same Isolate are ignored. Call `resetForTesting()` in tests to reset.

3. **Controllers need a parameterless constructor**  
   Scanning instantiates controllers via `newInstance`. Named-only constructors are skipped.

4. **Use `libraryFilter` for performance**  
   Without a filter, all loaded libraries are scanned. In production, limit to your application package path.

5. **Schema naming**  
   Schema names default to the Dart class name (e.g. `HealthData` → `#/components/schemas/HealthData`).

6. **OpenAPI version**  
   Output is fixed at `openapi: 3.0.3`.

---

## Development and Testing

```bash
# Run tests
dart test

# Analyze code
dart analyze
```

Tests use `resetForTesting()` plus `autoScan` with `libraryFilter` to isolate scan scope. See `test/nested_schema_test.dart`.

---

## Changelog

See [CHANGELOG.md](CHANGELOG.md).

## License

MIT — see [LICENSE](LICENSE).
