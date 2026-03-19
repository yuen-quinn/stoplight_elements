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
  final String type;
  final String? description;
  final bool required;
  final String? format;
  final dynamic example;
  final List<String>? enumValues;

  const ApiProperty({
    required this.type,
    this.description,
    this.required = false,
    this.format,
    this.example,
    this.enumValues,
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

