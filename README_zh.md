# stoplight_elements

[English](README.md)

基于 Dart 注解的 OpenAPI 3.0.3 文档生成库，内置 [Stoplight Elements](https://github.com/stoplightio/elements) 交互式文档页面渲染。

用 `@ApiPath`、`@ApiModel` 等注解描述接口与数据模型，运行时自动扫描并生成 OpenAPI JSON，再通过 `buildStoplightElementsHtml()` 输出可浏览的 API 文档页。

## 特性

- 注解驱动：路径、参数、请求体、响应、标签、安全方案均可声明
- 运行时自动扫描：`OpenApiRegistry.instance.autoScan()` 基于 `dart:mirrors` 发现注解
- OpenAPI 3.0.3 规范输出：`buildOpenApi()` 生成完整 spec
- 类型推断：字段上的 `@ApiProperty` 可省略 `type`，由 Dart 类型自动推断
- 嵌套类型：`User`、`List<User>`、`Map<String, User>` 等自动映射为 `$ref` / `array` / `additionalProperties`
- 泛型响应：支持 `BaseResponse<HealthData>` 语法展开 schema
- Stoplight Elements HTML：一行代码生成文档页

## 环境要求

- Dart SDK `^3.11.1`
- 运行环境需支持 `dart:mirrors`（**不支持** Flutter Web、AOT 编译后的独立二进制等无反射场景）

## 安装

在 `pubspec.yaml` 中添加依赖：

```yaml
dependencies:
  stoplight_elements: ^0.0.6
```

然后执行：

```bash
dart pub get
```

## 导入

```dart
import 'package:stoplight_elements/stoplight_elements.dart';
```

该入口会导出以下模块：

| 模块 | 内容 |
|------|------|
| `annotations.dart` | 全部注解类 |
| `generator.dart` | `OpenApiRegistry` |
| `config.dart` | `OpenApiConfig` |
| `stoplight_elements.dart` | `buildStoplightElementsHtml()` |

---

## 快速开始

### 1. 配置文档元信息

在应用启动时（`autoScan` / `buildOpenApi` 之前）调用：

```dart
OpenApiConfig.configure(
  title: 'My API',
  version: '1.0.0',
  description: 'API 文档',
  serverUrl: 'http://localhost:8000/api/v1/',
  enableDebug: true,
  defaultSchemes: ['http', 'https'],
);
```

也可直接赋值：

```dart
OpenApiConfig.title = 'My API';
OpenApiConfig.serverUrl = 'http://localhost:8000/';
```

### 2. 定义数据模型

**方式 A：字段级 `@ApiProperty`（推荐）**

类型可省略，由 Dart 字段类型自动推断：

```dart
@ApiModel(description: '健康检查响应')
class HealthData {
  @ApiProperty(description: '服务状态', example: 'ok')
  final String status;

  @ApiProperty(description: '时间戳', example: '2023-01-01T00:00:00.000Z')
  final String timestamp;

  HealthData({required this.status, required this.timestamp});
}
```

**方式 B：类级 `properties` 映射**

```dart
@ApiModel(
  description: '通用响应包装',
  properties: {
    'code': ApiProperty(type: 'integer', description: '业务码', example: 0),
    'message': ApiProperty(type: 'string', description: '提示信息'),
    'data': ApiProperty(type: 'object', description: '业务数据'),
  },
)
class BaseResponse {}
```

> 字段级注解与类级 `properties` 会合并，**字段级优先**；未声明的字段仍按 Dart 类型推断。

### 3. 定义接口

```dart
@ApiTag(name: 'Health', description: '健康检查')
class HealthController {
  @ApiPath(
    path: '/health',
    method: 'GET',
    tags: ['Health'],
    summary: '健康检查',
    description: '检查服务是否正常运行',
    responses: {
      200: ApiResponse(
        code: 200,
        description: '服务正常',
        schema: 'BaseResponse<HealthData>',
      ),
    },
  )
  Future<Map<String, dynamic>> health() async {
    return {'code': 0, 'message': 'ok', 'data': {'status': 'ok'}};
  }
}
```

Controller 需具备**无参默认构造函数**，否则 `autoScan` 无法实例化并扫描方法注解。

### 4. 注册并扫描

```dart
// 可选：注册 JWT Bearer 等安全方案
OpenApiRegistry.instance.registerSecurityScheme(
  'authorization',
  ApiSecurityScheme(
    type: 'http',
    scheme: 'bearer',
    bearerFormat: 'JWT',
    description: 'JWT Bearer 认证',
  ),
);

// 自动扫描（建议用 libraryFilter 限定范围）
OpenApiRegistry.instance.autoScan(
  libraryFilter: (uri) => uri.toString().startsWith('package:my_app/'),
);
```

`autoScan` 在同一 Isolate 内**只执行一次**（内部有 `_isScanned` 标志）。

### 5. 暴露端点

推荐提供两个 HTTP 路由：

| 路由 | 作用 |
|------|------|
| `GET /openapi.json` | 返回 OpenAPI JSON |
| `GET /docs` | 返回 Stoplight Elements 文档页 |

**Vania 框架示例：**

```dart
import 'package:vania/http/controller.dart';
import 'package:vania/http/response.dart';
import 'package:stoplight_elements/stoplight_elements.dart';

class OpenApiController extends Controller {
  Future<Response> spec() async {
    try {
      final spec = OpenApiRegistry.instance.buildOpenApi();
      return Response.json(spec);
    } catch (e, st) {
      return Response.json({
        'error': 'Failed to generate OpenAPI spec',
        'message': e.toString(),
        'stackTrace': st.toString(),
      });
    }
  }

  Future<Response> docs() async {
    final html = buildStoplightElementsHtml(
      openapiUrl: '/openapi.json',
      title: 'My API Documentation',
    );
    return Response.html(html);
  }
}
```

**纯 Dart `shelf` 示例：**

```dart
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as io;
import 'package:stoplight_elements/stoplight_elements.dart';

Handler createHandler() {
  return (Request request) {
    if (request.url.path == 'openapi.json') {
      return Response.ok(
        jsonEncode(OpenApiRegistry.instance.buildOpenApi()),
        headers: {'content-type': 'application/json'},
      );
    }
    if (request.url.path == 'docs') {
      return Response.ok(
        buildStoplightElementsHtml(openapiUrl: '/openapi.json'),
        headers: {'content-type': 'text/html; charset=utf-8'},
      );
    }
    return Response.notFound('Not Found');
  };
}
```

启动后访问 `/docs` 即可查看交互式文档。

---

## 注解参考

### `@ApiPath` — 接口路径

```dart
@ApiPath(
  path: '/users/{id}',           // 必填：路径
  method: 'GET',                 // 必填：HTTP 方法（GET/POST/PUT/DELETE/PATCH 等）
  summary: '获取用户',            // 必填：摘要
  description: '按 ID 查询用户',   // 可选：详细描述
  tags: ['Users'],               // 可选：分组标签
  deprecated: false,             // 可选：是否废弃
  parameters: [...],             // 可选：路径/查询/Header 参数
  requestBody: ApiRequestBody(...), // 可选：请求体
  responses: {200: ApiResponse(...)}, // 可选：响应
  security: ['authorization'],   // 可选：引用的 securitySchemes 名称
)
```

### `@ApiParameter` — 请求参数

```dart
const ApiParameter(
  name: 'id',
  location: 'path',       // path | query | header | cookie
  description: '用户 ID',
  required: true,
  type: 'string',         // OpenAPI 类型：string | integer | number | boolean
  format: 'uuid',           // 可选：如 uuid、int64、date-time
  example: '550e8400-e29b-41d4-a716-446655440000',
)
```

### `@ApiRequestBody` — 请求体

```dart
const ApiRequestBody(
  description: '创建用户请求',
  required: true,
  schema: 'CreateUserRequest',  // 模型名或泛型如 BaseResponse<User>
  example: {'name': 'Alice'},
)
```

### `@ApiResponse` — 响应

```dart
const ApiResponse(
  code: 200,
  description: '成功',
  schema: 'User',                    // 模型名
  // schema: 'BaseResponse<User>',   // 泛型展开
  example: {'id': '1', 'name': 'Alice'},
)
```

### `@ApiTag` — 标签分组

加在 Controller 类上，用于 OpenAPI `tags` 区块：

```dart
@ApiTag(name: 'Users', description: '用户相关接口')
class UserController { ... }
```

若 `@ApiPath` 未指定 `tags`，扫描时会尝试使用类上 `@ApiTag` 的名称作为默认标签。

### `@ApiModel` — 数据模型

```dart
@ApiModel(
  description: '用户',
  properties: { ... },  // 可选，与字段注解合并
)
class User { ... }
```

### `@ApiProperty` — 模型字段

```dart
@ApiProperty(
  type: 'string',              // 可选，省略则推断
  description: '用户名',
  required: true,              // 可选，省略则按 Dart 可空性推断
  format: 'email',
  example: 'alice@example.com',
  enumValues: ['a', 'b'],      // 枚举值
  ref: '#/components/schemas/User',  // 完整 $ref
  schema: 'User',              // 简写：自动转为 #/components/schemas/User
  items: ApiProperty(...),     // array 元素 schema
  additionalProperties: ApiProperty(...), // Map 值类型 schema
  properties: { ... },         // 内联 object 子字段
)
```

### `@ApiSecurityScheme` — 安全方案

通过 `registerSecurityScheme` 注册，不直接用作类注解：

```dart
// HTTP Bearer (JWT)
ApiSecurityScheme(
  type: 'http',
  scheme: 'bearer',
  bearerFormat: 'JWT',
  description: 'JWT 认证',
)

// API Key
ApiSecurityScheme(
  type: 'apiKey',
  scheme: 'apiKey',
  name: 'X-API-Key',
  in_: 'header',
  description: 'API Key 认证',
)
```

在 `@ApiPath` 中引用：

```dart
@ApiPath(
  path: '/profile',
  method: 'GET',
  summary: '个人资料',
  security: ['authorization'],
  responses: { ... },
)
```

---

## 类型推断规则

扫描模型字段时，按以下规则生成 OpenAPI schema：

| Dart 类型 | OpenAPI 输出 |
|-----------|-------------|
| `String` | `{ "type": "string" }` |
| `int` | `{ "type": "integer", "format": "int64" }` |
| `double` | `{ "type": "number", "format": "double" }` |
| `bool` | `{ "type": "boolean" }` |
| `DateTime` | `{ "type": "string", "format": "date-time" }` |
| `Enum` 子类 | `{ "type": "string" }` |
| 带 `@ApiModel` 的类 `User` | `{ "$ref": "#/components/schemas/User" }` |
| 无 `@ApiModel` 的普通类 | 内联 `{ "type": "object", "properties": {...} }` |
| `List<User>` | `{ "type": "array", "items": { "$ref": "..." } }` |
| `Map<String, User>` | `{ "type": "object", "additionalProperties": { "$ref": "..." } }` |
| `User?`（可空） | 同上，但 `required: false` |
| `dynamic` + `@ApiProperty(schema: 'User')` | `{ "$ref": "#/components/schemas/User" }` |

**嵌套示例：**

```dart
@ApiModel(description: '用户')
class UserDto {
  @ApiProperty(description: 'ID', required: true)
  final String id;
  UserDto({required this.id});
}

@ApiModel(description: '分页结果')
class UserPage {
  final List<UserDto> items;   // → array + items.$ref
  final UserDto? current;        // → $ref, required: false
  UserPage({required this.items, this.current});
}

@ApiModel(description: '索引表')
class UserMap {
  final Map<String, UserDto> byId;  // → additionalProperties.$ref
  UserMap({required this.byId});
}
```

---

## 泛型响应

响应 schema 支持 `BaseSchema<ConcreteType>` 语法。生成器会将基础模型中名为 `data` 的字段替换为具体类型的 `$ref`：

```dart
@ApiModel(
  properties: {
    'code': ApiProperty(type: 'integer'),
    'message': ApiProperty(type: 'string'),
    'data': ApiProperty(type: 'object'),
  },
)
class BaseResponse {}

// 在 @ApiPath 的 responses 中使用：
schema: 'BaseResponse<HealthData>'
```

等价于展开 `BaseResponse`，并将其 `data` 字段指向 `#/components/schemas/HealthData`。

---

## OpenApiRegistry API

`OpenApiRegistry` 为单例，通过 `OpenApiRegistry.instance` 访问。

| 方法 | 说明 |
|------|------|
| `autoScan({libraryFilter})` | 扫描当前 Isolate 所有库的注解；`libraryFilter` 按 URI 过滤 |
| `scanController(Object controller)` | 手动扫描单个 Controller 实例 |
| `scanModel(Type type, {String? name})` | 手动扫描单个模型类 |
| `scanModelByName(String name, ClassMirror mirror)` | 内部使用，按类名扫描 |
| `registerPath(ApiPath path)` | 手动注册路径 |
| `registerModel(String name, ApiModel model)` | 手动注册 schema |
| `registerSecurityScheme(String name, ApiSecurityScheme scheme)` | 注册安全方案 |
| `registerTag(ApiTag tag)` | 注册标签 |
| `buildOpenApi()` | 生成完整 OpenAPI 3.0.3 JSON |
| `resetForTesting()` | 清空注册表（测试用） |

### libraryFilter 示例

```dart
// 只扫描自己的应用包
OpenApiRegistry.instance.autoScan(
  libraryFilter: (uri) => uri.toString().startsWith('package:my_app/'),
);

// 只扫描测试文件
OpenApiRegistry.instance.autoScan(
  libraryFilter: (uri) => uri.toString().contains('my_test.dart'),
);
```

---

## buildStoplightElementsHtml 参数

生成嵌入 Stoplight Elements Web Components 的完整 HTML 页面：

```dart
final html = buildStoplightElementsHtml(
  openapiUrl: '/openapi.json',        // 必填：OpenAPI JSON 地址
  title: 'API Documentation',          // 页面标题
  stoplightElementsJsUrl: 'https://unpkg.com/@stoplight/elements/web-components.min.js',
  stoplightElementsCssUrl: 'https://unpkg.com/@stoplight/elements/styles.min.css',
  stoplightElementsFaviconUrl: 'https://fastapi.tiangolo.com/img/favicon.png',
  apiDescriptionDocument: '',          // 内联 OpenAPI 文档（与 URL 二选一）
  basePath: '',                        // API 基础路径
  hideInternal: false,                 // 隐藏 x-internal 标记的接口
  hideTryIt: false,                    // 隐藏 Try It 调试面板
  tryItCorsProxy: '',                  // CORS 代理地址
  tryItCredentialPolicy: StoplightTryItCredentialPolicyOptions.omit,
  layout: StoplightLayoutOptions.sidebar,  // sidebar | stacked
  logo: '',                            // Logo URL
  router: StoplightRouterOptions.history,  // history | hash | memory | static
);
```

### 布局与路由常量

```dart
// 布局
StoplightLayoutOptions.sidebar   // 侧边栏（默认）
StoplightLayoutOptions.stacked   // 堆叠

// 路由模式
StoplightRouterOptions.history   // History API（默认）
StoplightRouterOptions.hash      // Hash 路由
StoplightRouterOptions.memory    // Memory 路由
StoplightRouterOptions.static_   // 静态路由

// Try It 凭证策略
StoplightTryItCredentialPolicyOptions.omit
StoplightTryItCredentialPolicyOptions.include
StoplightTryItCredentialPolicyOptions.sameOrigin
```

### 跨域 Try It

若 API 与文档页不同源，可配置 CORS 代理：

```dart
buildStoplightElementsHtml(
  openapiUrl: '/openapi.json',
  tryItCorsProxy: 'https://cors.example.com/',
);
```

---

## 完整集成示例（Vania）

```dart
// ── models/health.dart ──
@ApiModel(description: '健康检查数据')
class HealthData {
  @ApiProperty(description: '状态', example: 'ok')
  final String status;

  @ApiProperty(description: '服务名', example: 'my_api')
  final String service;

  HealthData({required this.status, required this.service});

  Map<String, dynamic> toJson() => {'status': status, 'service': service};
}

// ── controllers/health_controller.dart ──
@ApiTag(name: 'Health', description: '健康检查')
class HealthController extends Controller {
  @ApiPath(
    path: '/health',
    method: 'GET',
    tags: ['Health'],
    summary: '健康检查',
    responses: {
      200: ApiResponse(
        code: 200,
        description: '正常',
        schema: 'HealthData',
      ),
    },
  )
  Future<Response> health() async {
    return Response.json(
      HealthData(status: 'ok', service: 'my_api').toJson(),
    );
  }
}

// ── providers/route_service_provider.dart ──
class RouteServiceProvider extends ServiceProvider {
  @override
  Future<void> register() async {
    OpenApiConfig.configure(
      title: 'My API',
      version: '1.0.0',
      serverUrl: 'http://localhost:8000/api/v1/',
    );

    OpenApiRegistry.instance.registerSecurityScheme(
      'authorization',
      ApiSecurityScheme(
        type: 'http',
        scheme: 'bearer',
        bearerFormat: 'JWT',
        description: 'JWT Bearer',
      ),
    );

    OpenApiRegistry.instance.autoScan(
      libraryFilter: (uri) => uri.toString().startsWith('package:my_app/'),
    );

    // 注册业务路由与 OpenAPI 路由...
  }
}
```

---

## 注意事项

1. **`dart:mirrors` 限制**  
   本库依赖运行时反射。Flutter Web、Dart 编译为原生可执行文件（AOT）等环境无法使用。适用于 Dart 服务端（VM 模式）。

2. **`autoScan` 只执行一次**  
   同一 Isolate 内重复调用会被忽略。测试时可调用 `resetForTesting()` 重置。

3. **Controller 需要无参构造函数**  
   扫描时会 `newInstance` 实例化 Controller。若只有命名构造函数，该方法会被跳过。

4. **使用 `libraryFilter` 提升性能**  
   不加过滤会遍历所有已加载库，生产环境务必限定为应用包路径。

5. **schema 命名**  
   模型 schema 名称默认取 Dart 类名（如 `HealthData` → `#/components/schemas/HealthData`）。

6. **OpenAPI 版本**  
   固定输出 `openapi: 3.0.3`。

---

## 开发与测试

```bash
# 运行测试
dart test

# 分析代码
dart analyze
```

测试中使用 `resetForTesting()` + 带 `libraryFilter` 的 `autoScan` 隔离扫描范围，参见 `test/nested_schema_test.dart`。

---

## 更新日志

详见 [CHANGELOG.md](CHANGELOG.md)。

## 许可证

MIT — 详见 [LICENSE](LICENSE)。
