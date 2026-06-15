/// API路径注解
class ApiPath {
  final String path;
  final String method;
  final String summary;
  final String? description;
  final List<String>? tags;
  final bool deprecated;
  final List<ApiParameter>? parameters;
  final Map<int, ApiResponse>? responses;
  final List<String>? security;
  final ApiRequestBody? requestBody;

  const ApiPath({
    required this.path,
    required this.method,
    required this.summary,
    this.description,
    this.tags,
    this.deprecated = false,
    this.parameters,
    this.responses,
    this.security,
    this.requestBody,
  });
}

/// API参数注解
class ApiParameter {
  final String name;
  final String location; // path, query, header, cookie
  final String? description;
  final bool required;
  final String type;
  final String? format;
  final dynamic example;

  const ApiParameter({
    required this.name,
    required this.location,
    this.description,
    this.required = false,
    required this.type,
    this.format,
    this.example,
  });
}

/// API响应注解
class ApiResponse {
  final int code;
  final String description;
  final String? schema;
  final Map<String, dynamic>? example;

  const ApiResponse({
    required this.code,
    required this.description,
    this.schema,
    this.example,
  });
}

/// 类型安全的API响应注解
class TypedApiResponse<T> {
  final int code;
  final String description;
  final Map<String, dynamic>? example;

  const TypedApiResponse({
    required this.code,
    required this.description,
    this.example,
  });
}

/// API请求体注解
class ApiRequestBody {
  final String description;
  final bool required;
  final String schema;
  final Map<String, dynamic>? example;

  const ApiRequestBody({
    required this.description,
    this.required = true,
    required this.schema,
    this.example,
  });
}

/// API标签注解
class ApiTag {
  final String name;
  final String? description;

  const ApiTag({
    required this.name,
    this.description,
  });
}

/// API模型注解
class ApiModel {
  final String? description;
  final Map<String, ApiProperty>? properties;

  const ApiModel({
    this.description,
    this.properties,
  });
}

/// API属性注解
class ApiProperty {
  final String? type;
  final String? description;

  /// `null` 表示未指定，合并时由推断结果补全。
  final bool? required;
  final String? format;
  final dynamic example;
  final List<String>? enumValues;

  /// 内联 object 的子字段（无 [@ApiModel] 时展开为嵌套 schema）
  final Map<String, ApiProperty>? properties;

  /// 完整 `$ref`，如 `#/components/schemas/User`
  final String? ref;

  /// 模型名简写，如 `User` → `#/components/schemas/User`
  final String? schema;

  /// `type: array` 时的元素 schema
  final ApiProperty? items;

  /// `Map` 值类型 schema（输出为 `additionalProperties`）
  final ApiProperty? additionalProperties;

  /// 标记该属性为泛型承载字段。当泛型模型（如 `Result<Package>`）被解析时，
  /// 此字段的 schema 会被替换为泛型参数的类型，而非使用原始定义。
  /// 例如 `Result<Package>` 中标记了 `isGeneric: true` 的 `data` 字段
  /// 会被解析为 `Package` 的 schema。
  final bool isGeneric;

  const ApiProperty({
    this.type,
    this.description,
    this.required,
    this.format,
    this.example,
    this.enumValues,
    this.properties,
    this.ref,
    this.schema,
    this.items,
    this.additionalProperties,
    this.isGeneric = false,
  });
}

/// API安全方案注解
class ApiSecurityScheme {
  final String type;
  final String scheme;
  final String? bearerFormat;
  final String? description;
  final String? name;
  final String? in_; // for apiKey type

  const ApiSecurityScheme({
    required this.type,
    required this.scheme,
    this.bearerFormat,
    this.description,
    this.name,
    this.in_,
  });
}

