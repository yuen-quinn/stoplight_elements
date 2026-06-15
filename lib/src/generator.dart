import 'dart:mirrors';

import 'annotations.dart';
import 'config.dart';

class OpenApiRegistry {
  OpenApiRegistry._();

  static final OpenApiRegistry instance = OpenApiRegistry._();

  final List<ApiPath> _paths = [];
  final Map<String, ApiModel> _schemas = {};
  final Map<String, ApiSecurityScheme> _securitySchemes = {};
  final Map<String, ApiTag> _tags = {};

  static final Map<Type, ApiProperty> _primitiveTypeCache = {};
  static bool _isScanned = false;

  // 预编译正则表达式
  static final RegExp _genericRegex = RegExp(r'^(\w+)<(.+)>$');

  void registerPath(ApiPath path) {
    _paths.add(path);
    if (path.tags != null) {
      for (final t in path.tags!) {
        _tags.putIfAbsent(t, () => ApiTag(name: t));
      }
    }
  }

  void registerModel(String name, ApiModel model) {
    _schemas[name] = model;
  }

  void registerSecurityScheme(String name, ApiSecurityScheme scheme) {
    _securitySchemes[name] = scheme;
  }

  void registerTag(ApiTag tag) {
    _tags[tag.name] = tag;
  }

  /// Clears registry state (for tests).
  void resetForTesting() {
    _paths.clear();
    _schemas.clear();
    _securitySchemes.clear();
    _tags.clear();
    _isScanned = false;
  }

  bool _isNullableMirror(TypeMirror mirror) {
    return mirror.toString().endsWith('?');
  }

  /// 自动扫描当前 Isolate 里所有带 OpenAPI 注解的类和方法
  /// 使用前建议在生产环境慎用或加上 URI 过滤。
  void autoScan({bool Function(Uri uri)? libraryFilter}) {
    if (_isScanned) return;

    final system = currentMirrorSystem();

    for (final lib in system.libraries.values) {
      // 可选的库过滤：例如只扫描你的应用包
      if (libraryFilter != null && !libraryFilter(lib.uri)) {
        continue;
      }

      for (final decl in lib.declarations.values) {
        if (decl is ClassMirror) {
          final classMirror = decl;

          // 1. 类上的 @ApiModel -> 自动生成 schema
          for (final meta in classMirror.metadata) {
            final obj = meta.reflectee;
            if (obj is ApiModel) {
              final className = MirrorSystem.getName(classMirror.simpleName);
              scanModelByName(className, classMirror);
              break;
            }
          }

          // 2. 类上的 @ApiTag
          for (final meta in classMirror.metadata) {
            final obj = meta.reflectee;
            if (obj is ApiTag) {
              registerTag(obj);
            }
          }

          // 3. 方法上的 @ApiPath
          bool hasApiPath = false;
          for (final m in classMirror.declarations.values) {
            if (m is MethodMirror && !m.isConstructor) {
              for (final meta in m.metadata) {
                final obj = meta.reflectee;
                if (obj is ApiPath) {
                  hasApiPath = true;
                  break;
                }
              }
            }
            if (hasApiPath) break;
          }

          // 如果类里存在 @ApiPath 方法，则尝试当作 Controller 处理
          if (hasApiPath) {
            try {
              // 需要有无参默认构造函数
              final instance = classMirror
                  .newInstance(const Symbol(''), const [])
                  .reflectee;
              scanController(instance);
            } catch (_) {
              // 没有默认构造函数就忽略
            }
          }
        }
      }
    }

    _isScanned = true;
  }

  /// 处理模型注解的通用方法
  ApiModel? _processModelAnnotations(ClassMirror classMirror) {
    ApiModel? apiModelMeta;
    for (final meta in classMirror.metadata) {
      final obj = meta.reflectee;
      if (obj is ApiModel) {
        apiModelMeta = obj;
        break;
      }
    }
    return apiModelMeta;
  }

  /// 处理模型属性的通用方法。
  ///
  /// 合并顺序（后者覆盖前者）：
  /// 1. 类上 [@ApiModel] 的 `properties`
  /// 2. 字段上的 [@ApiProperty]（未写 `type` 时按 Dart 类型推断）
  /// 3. 仍未声明的字段按 Dart 类型推断
  Map<String, ApiProperty> _processModelProperties(
    ClassMirror classMirror,
    ApiModel apiModelMeta,
  ) {
    final props = <String, ApiProperty>{};
    if (apiModelMeta.properties != null) {
      props.addAll(apiModelMeta.properties!);
    }

    for (final entry in classMirror.declarations.entries) {
      final decl = entry.value;
      if (decl is! VariableMirror || decl.isStatic) {
        continue;
      }

      final fieldName = MirrorSystem.getName(entry.key);
      final inferred = _inferPropertyFromType(fieldName, decl.type);
      final annotated = _apiPropertyFromField(decl);

      if (annotated != null) {
        props[fieldName] = _mergeApiProperty(annotated, inferred);
      } else if (!props.containsKey(fieldName)) {
        props[fieldName] = inferred;
      }
    }

    return props;
  }

  ApiProperty? _apiPropertyFromField(VariableMirror decl) {
    for (final meta in decl.metadata) {
      final obj = meta.reflectee;
      if (obj is ApiProperty) {
        return obj;
      }
    }
    return null;
  }

  /// 字段 [@ApiProperty] 优先；未填写的 `type` / `format` 等从推断结果补全。
  ApiProperty _mergeApiProperty(ApiProperty annotated, ApiProperty inferred) {
    return ApiProperty(
      type: annotated.type ?? inferred.type,
      description: annotated.description ?? inferred.description,
      required: annotated.required ?? inferred.required,
      format: annotated.format ?? inferred.format,
      example: annotated.example ?? inferred.example,
      enumValues: annotated.enumValues ?? inferred.enumValues,
      properties: annotated.properties ?? inferred.properties,
      ref: _resolveRef(annotated) ?? _resolveRef(inferred),
      schema: annotated.schema ?? inferred.schema,
      items: annotated.items ?? inferred.items,
      additionalProperties:
          annotated.additionalProperties ?? inferred.additionalProperties,
    );
  }

  String? _resolveRef(ApiProperty property) {
    if (property.ref != null) {
      return property.ref;
    }
    if (property.schema != null) {
      return _schemaToRef(property.schema!);
    }
    return null;
  }

  String _schemaToRef(String schema) {
    if (schema.startsWith('#/')) {
      return schema;
    }
    return '#/components/schemas/$schema';
  }

  TypeMirror _coreTypeMirror(TypeMirror mirror) {
    if (!_isNullableMirror(mirror)) {
      return mirror;
    }
    return reflectType(mirror.reflectedType);
  }

  bool _isListType(TypeMirror mirror) {
    final core = _coreTypeMirror(mirror);
    final t = core.reflectedType;
    if (t == dynamic) {
      return false;
    }
    return t == List || MirrorSystem.getName(core.simpleName) == 'List';
  }

  bool _isMapType(TypeMirror mirror) {
    final core = _coreTypeMirror(mirror);
    final t = core.reflectedType;
    if (t == dynamic) {
      return false;
    }
    return t == Map || MirrorSystem.getName(core.simpleName) == 'Map';
  }

  bool _isEnumType(TypeMirror mirror) {
    final core = _coreTypeMirror(mirror);
    if (core is! ClassMirror) {
      return false;
    }
    return core.isSubtypeOf(reflectType(Enum));
  }

  void _ensureModelRegistered(ClassMirror classMirror) {
    final name = MirrorSystem.getName(classMirror.simpleName);
    if (_schemas.containsKey(name)) {
      return;
    }
    scanModelByName(name, classMirror);
  }

  /// 扫描带有 @ApiModel 注解的模型类，通过类名构建 schema
  void scanModelByName(String name, ClassMirror classMirror) {
    final apiModelMeta = _processModelAnnotations(classMirror);

    // 没有 @ApiModel 就不处理
    if (apiModelMeta == null) {
      return;
    }

    final props = _processModelProperties(classMirror, apiModelMeta);

    final model = ApiModel(
      description: apiModelMeta.description,
      properties: props.isEmpty ? apiModelMeta.properties : props,
    );

    registerModel(name, model);
  }

  /// 扫描带有 @ApiModel 注解的模型类，自动构建 schema
  void scanModel(Type type, {String? name}) {
    final cm = reflectClass(type);
    final apiModelMeta = _processModelAnnotations(cm);

    // 没有 @ApiModel 就不处理
    if (apiModelMeta == null) {
      return;
    }

    final props = _processModelProperties(cm, apiModelMeta);

    final modelName = name ?? MirrorSystem.getName(cm.simpleName);
    final model = ApiModel(
      description: apiModelMeta.description,
      properties: props.isEmpty ? apiModelMeta.properties : props,
    );

    registerModel(modelName, model);
  }

  ApiProperty _inferPropertyFromType(String fieldName, TypeMirror typeMirror) {
    _initPrimitiveCache();

    final required = !_isNullableMirror(typeMirror);
    final core = _coreTypeMirror(typeMirror);
    final t = core.reflectedType;

    if (_primitiveTypeCache.containsKey(t)) {
      final cached = _primitiveTypeCache[t]!;
      return ApiProperty(
        type: cached.type,
        format: cached.format,
        required: required,
      );
    }

    if (_isListType(typeMirror)) {
      return _inferListProperty(typeMirror, required: required);
    }

    if (_isMapType(typeMirror)) {
      return _inferMapProperty(typeMirror, required: required);
    }

    if (_isEnumType(typeMirror)) {
      return ApiProperty(type: 'string', required: required);
    }

    if (core is ClassMirror) {
      return _inferClassProperty(core, required: required);
    }

    if (t == dynamic) {
      return ApiProperty(type: 'object', required: required);
    }

    return ApiProperty(type: 'string', required: required);
  }

  ApiProperty _inferListProperty(
    TypeMirror typeMirror, {
    required bool required,
  }) {
    final core = _coreTypeMirror(typeMirror);
    final args = core.typeArguments;

    if (args.isEmpty) {
      return ApiProperty(
        type: 'array',
        required: required,
        items: const ApiProperty(type: 'string'),
      );
    }

    final itemType = args.first.reflectedType;
    if (itemType == dynamic) {
      return ApiProperty(
        type: 'array',
        required: required,
        items: const ApiProperty(type: 'object'),
      );
    }

    return ApiProperty(
      type: 'array',
      required: required,
      items: _inferPropertyFromType('item', reflectType(itemType)),
    );
  }

  ApiProperty _inferMapProperty(
    TypeMirror typeMirror, {
    required bool required,
  }) {
    final core = _coreTypeMirror(typeMirror);
    final args = core.typeArguments;
    ApiProperty? valueSchema;
    if (args.length >= 2) {
      final valueType = args[1].reflectedType;
      if (valueType != dynamic) {
        valueSchema = _inferPropertyFromType('value', reflectType(valueType));
      }
    }

    return ApiProperty(
      type: 'object',
      required: required,
      additionalProperties: valueSchema ?? const ApiProperty(type: 'string'),
    );
  }

  ApiProperty _inferClassProperty(
    ClassMirror classMirror, {
    required bool required,
  }) {
    if (_processModelAnnotations(classMirror) != null) {
      _ensureModelRegistered(classMirror);
      final name = MirrorSystem.getName(classMirror.simpleName);
      return ApiProperty(ref: _schemaToRef(name), required: required);
    }

    final nested = _processModelProperties(classMirror, const ApiModel());
    if (nested.isNotEmpty) {
      return ApiProperty(
        type: 'object',
        required: required,
        properties: nested,
      );
    }

    return ApiProperty(type: 'object', required: required);
  }

  static void _initPrimitiveCache() {
    if (_primitiveTypeCache.isNotEmpty) {
      return;
    }
    _primitiveTypeCache[int] = const ApiProperty(
      type: 'integer',
      format: 'int64',
    );
    _primitiveTypeCache[double] = const ApiProperty(
      type: 'number',
      format: 'double',
    );
    _primitiveTypeCache[bool] = const ApiProperty(type: 'boolean');
    _primitiveTypeCache[String] = const ApiProperty(type: 'string');
    _primitiveTypeCache[DateTime] = const ApiProperty(
      type: 'string',
      format: 'date-time',
    );
  }

  /// 将 `ApiProperty` 转成 OpenAPI Schema 对象。
  Map<String, dynamic> _buildPropertySchema(ApiProperty property) {
    final ref = _resolveRef(property);
    if (ref != null) {
      return {
        '\$ref': ref,
        if (property.description != null) 'description': property.description,
        if (property.example != null) 'example': property.example,
      };
    }

    if (property.type == 'array') {
      return {
        'type': 'array',
        if (property.description != null) 'description': property.description,
        if (property.example != null) 'example': property.example,
        if (property.items != null)
          'items': _buildPropertySchema(property.items!),
      };
    }

    final schema = <String, dynamic>{};
    if (property.type != null) {
      schema['type'] = property.type;
    }

    if (property.description != null) {
      schema['description'] = property.description;
    }
    if (property.format != null) schema['format'] = property.format;
    if (property.enumValues != null) schema['enum'] = property.enumValues;
    if (property.example != null) schema['example'] = property.example;

    if (property.additionalProperties != null) {
      schema['additionalProperties'] = _buildPropertySchema(
        property.additionalProperties!,
      );
    }

    if (property.properties != null) {
      final properties = <String, dynamic>{};
      final requiredFields = <String>[];
      for (final entry in property.properties!.entries) {
        properties[entry.key] = _buildPropertySchema(entry.value);
        if (entry.value.required == true) {
          requiredFields.add(entry.key);
        }
      }
      schema['properties'] = properties;
      if (requiredFields.isNotEmpty) {
        schema['required'] = requiredFields;
      }
    }

    return schema;
  }

  /// 解析 schema 引用，支持泛型语法如 `Result<List<PackageVersion>>`
  Map<String, dynamic> _parseSchemaRef(String schemaRef) {
    // 检查是否包含泛型语法
    final genericMatch = _genericRegex.firstMatch(schemaRef);

    if (genericMatch != null) {
      final baseSchema = genericMatch.group(1)!;
      final genericType = genericMatch.group(2)!;

      // List<X> 特殊处理：输出 array schema
      if (baseSchema == 'List') {
        return {'type': 'array', 'items': _parseSchemaRef(genericType)};
      }

      // 检查基础模型是否在 _schemas 中（有 @ApiModel 注解）
      final baseModel = _schemas[baseSchema];
      if (baseModel != null && baseModel.properties != null) {
        // 展开基础模型的属性，但将 isGeneric 字段替换为泛型类型
        final properties = <String, dynamic>{};
        final requiredFields = <String>[];

        for (final entry in baseModel.properties!.entries) {
          if (entry.value.isGeneric) {
            // 泛型承载字段：用泛型参数的类型替换
            properties[entry.key] = _parseSchemaRef(genericType);
          } else {
            properties[entry.key] = _buildPropertySchema(entry.value);
          }
          if (entry.value.required == true) {
            requiredFields.add(entry.key);
          }
        }

        return {
          'type': 'object',
          if (baseModel.description != null)
            'description': baseModel.description,
          'properties': properties,
          if (requiredFields.isNotEmpty) 'required': requiredFields,
        };
      }

      // 基础模型未注册或无属性：穿透到内部类型
      return _parseSchemaRef(genericType);
    }

    // 如果不是泛型，使用普通的 $ref
    return {'\$ref': '#/components/schemas/$schemaRef'};
  }

  /// 使用 dart:mirrors 从 Controller 中扫描注解
  void scanController(Object controller) {
    final im = reflect(controller);
    final cm = im.type;

    // 类上的 ApiTag
    for (final meta in cm.metadata) {
      final obj = meta.reflectee;
      if (obj is ApiTag) {
        registerTag(obj);
      }
    }

    // 方法上的 ApiPath
    for (final decl in cm.declarations.values) {
      if (decl is MethodMirror && !decl.isConstructor) {
        for (final meta in decl.metadata) {
          final obj = meta.reflectee;
          if (obj is ApiPath) {
            // 如果没有显式 tags，则默认用类上的 ApiTag 名称
            if ((obj.tags == null || obj.tags!.isEmpty) && _tags.isNotEmpty) {
              final firstTag = _tags.keys.first;
              registerPath(
                ApiPath(
                  path: obj.path,
                  method: obj.method,
                  summary: obj.summary,
                  description: obj.description,
                  tags: [firstTag],
                  deprecated: obj.deprecated,
                  parameters: obj.parameters,
                  responses: obj.responses,
                  security: obj.security,
                  requestBody: obj.requestBody,
                ),
              );
            } else {
              registerPath(obj);
            }
          }
        }
      }
    }
  }

  Map<String, dynamic> buildOpenApi() {
    final paths = <String, Map<String, dynamic>>{};

    for (final p in _paths) {
      final pathItem = paths.putIfAbsent(p.path, () => <String, dynamic>{});
      pathItem[p.method.toLowerCase()] = {
        'summary': p.summary,
        if (p.description != null) 'description': p.description,
        if (p.tags != null) 'tags': p.tags,
        'deprecated': p.deprecated,
        if (p.parameters != null)
          'parameters': p.parameters!
              .map(
                (param) => <String, dynamic>{
                  'name': param.name,
                  'in': param.location,
                  if (param.description != null)
                    'description': param.description,
                  'required': param.required,
                  'schema': <String, dynamic>{
                    'type': param.type,
                    if (param.format != null) 'format': param.format,
                  },
                  if (param.example != null) 'example': param.example,
                },
              )
              .toList(),
        if (p.requestBody != null)
          'requestBody': <String, dynamic>{
            'description': p.requestBody!.description,
            'required': p.requestBody!.required,
            'content': <String, dynamic>{
              'application/json': <String, dynamic>{
                'schema': _parseSchemaRef(p.requestBody!.schema),
                if (p.requestBody!.example != null)
                  'example': p.requestBody!.example,
              },
            },
          },
        'responses': <String, dynamic>{
          if (p.responses != null)
            for (final entry in p.responses!.entries)
              '${entry.key}': <String, dynamic>{
                'description': entry.value.description,
                if (entry.value.schema != null)
                  'content': <String, dynamic>{
                    'application/json': <String, dynamic>{
                      'schema': _parseSchemaRef(entry.value.schema!),
                      if (entry.value.example != null)
                        'example': entry.value.example,
                    },
                  },
              },
        },
        if (p.security != null)
          'security': [
            for (final s in p.security!) <String, List<String>>{s: []},
          ],
      };
    }

    final componentsSchemas = <String, dynamic>{};
    _schemas.forEach((name, model) {
      componentsSchemas[name] = {
        'type': 'object',
        if (model.description != null) 'description': model.description,
        if (model.properties != null)
          'properties': {
            for (final entry in model.properties!.entries)
              entry.key: _buildPropertySchema(entry.value),
          },
        if (model.properties != null)
          'required': [
            for (final entry in model.properties!.entries)
              if (entry.value.required == true) entry.key,
          ],
      };
    });

    final componentsSecurity = <String, dynamic>{};
    _securitySchemes.forEach((name, scheme) {
      componentsSecurity[name] = {
        'type': scheme.type,
        'scheme': scheme.scheme,
        if (scheme.bearerFormat != null) 'bearerFormat': scheme.bearerFormat,
        if (scheme.description != null) 'description': scheme.description,
        if (scheme.name != null) 'name': scheme.name,
        if (scheme.in_ != null) 'in': scheme.in_,
      };
    });

    final tags = [
      for (final t in _tags.values)
        {
          'name': t.name,
          if (t.description != null) 'description': t.description,
        },
    ];

    return {
      'openapi': '3.0.3',
      'info': OpenApiConfig.info,
      'servers': OpenApiConfig.servers,
      'paths': paths,
      'components': {
        if (componentsSchemas.isNotEmpty) 'schemas': componentsSchemas,
        if (componentsSecurity.isNotEmpty)
          'securitySchemes': componentsSecurity,
      },
      if (tags.isNotEmpty) 'tags': tags,
    };
  }
}
