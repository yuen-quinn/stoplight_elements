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

  // 缓存机制
  static final Map<Type, ApiProperty> _typePropertyCache = {};
  static bool _isScanned = false;
  
  // 预编译正则表达式
  static final RegExp _genericRegex = RegExp(r'^(\w+)<(\w+)>$');

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

  /// 处理模型属性的通用方法
  Map<String, ApiProperty> _processModelProperties(ClassMirror classMirror, ApiModel apiModelMeta) {
    // 先以注解中的 properties 为主
    final props = <String, ApiProperty>{};
    if (apiModelMeta.properties != null) {
      props.addAll(apiModelMeta.properties!);
    }

    // 如果注解里没写 properties，尝试根据字段自动推断
    if (props.isEmpty) {
      for (final entry in classMirror.declarations.entries) {
        final decl = entry.value;
        if (decl is VariableMirror && !decl.isStatic) {
          final fieldName = MirrorSystem.getName(entry.key);
          if (props.containsKey(fieldName)) continue;

          final typeMirror = decl.type;
          final property = _inferPropertyFromType(fieldName, typeMirror);
          props[fieldName] = property;
        }
      }
    }

    return props;
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
    final t = typeMirror.reflectedType;
    
    // 使用缓存避免重复计算
    if (_typePropertyCache.containsKey(t)) {
      return _typePropertyCache[t]!;
    }

    ApiProperty property;
    if (t == int) {
      property = ApiProperty(
        type: 'integer',
        format: 'int64',
        required: false,
      );
    } else if (t == double) {
      property = ApiProperty(
        type: 'number',
        format: 'double',
        required: false,
      );
    } else if (t == bool) {
      property = ApiProperty(
        type: 'boolean',
        required: false,
      );
    } else if (t == DateTime) {
      property = ApiProperty(
        type: 'string',
        format: 'date-time',
        required: false,
      );
    } else {
      // 默认都按 string 处理
      property = ApiProperty(
        type: 'string',
        required: false,
      );
    }
    
    // 缓存结果
    _typePropertyCache[t] = property;
    return property;
  }

  
  /// 解析 schema 引用，支持泛型语法如 BaseResponse<HealthData>
  Map<String, dynamic> _parseSchemaRef(String schemaRef) {
    // 检查是否包含泛型语法
    final genericMatch = _genericRegex.firstMatch(schemaRef);
    
    if (genericMatch != null) {
      final baseSchema = genericMatch.group(1)!;
      final genericType = genericMatch.group(2)!;
      
      // 获取基础模型的定义
      final baseModel = _schemas[baseSchema];
      if (baseModel != null) {
        final properties = <String, dynamic>{};
        
        // 复制基础模型的属性
        if (baseModel.properties != null) {
          baseModel.properties!.forEach((key, value) {
            if (key == 'data') {
              // 将 data 字段替换为具体的泛型类型
              properties[key] = {
                'type': value.type,
                if (value.description != null) 'description': value.description,
                '\$ref': '#/components/schemas/$genericType',
              };
            } else {
              properties[key] = {
                'type': value.type,
                if (value.description != null) 'description': value.description,
                if (value.format != null) 'format': value.format,
                if (value.enumValues != null) 'enum': value.enumValues,
                if (value.example != null) 'example': value.example,
              };
            }
          });
        }
        
        return {
          'type': 'object',
          if (baseModel.description != null) 'description': baseModel.description,
          'properties': properties,
          if (baseModel.properties != null)
            'required': [
              for (final entry in baseModel.properties!.entries)
                if (entry.value.required) entry.key,
            ],
        };
      }
    }
    
    // 如果不是泛型或找不到基础模型，使用普通的 ref
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
              registerPath(ApiPath(
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
              ));
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
          'parameters': p.parameters!.map((param) => <String, dynamic>{
            'name': param.name,
            'in': param.location,
            if (param.description != null) 'description': param.description,
            'required': param.required,
            'schema': <String, dynamic>{
              'type': param.type,
              if (param.format != null) 'format': param.format,
            },
            if (param.example != null) 'example': param.example,
          }).toList(),
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
            for (final s in p.security!) <String, List<String>>{s: []}
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
              entry.key: {
                'type': entry.value.type,
                if (entry.value.description != null)
                  'description': entry.value.description,
                if (entry.value.format != null) 'format': entry.value.format,
                if (entry.value.enumValues != null)
                  'enum': entry.value.enumValues,
                if (entry.value.example != null)
                  'example': entry.value.example,
              },
          },
        if (model.properties != null)
          'required': [
            for (final entry in model.properties!.entries)
              if (entry.value.required) entry.key,
          ],
      };
    });

    final componentsSecurity = <String, dynamic>{};
    _securitySchemes.forEach((name, scheme) {
      componentsSecurity[name] = {
        'type': scheme.type,
        'scheme': scheme.scheme,
        if (scheme.bearerFormat != null)
          'bearerFormat': scheme.bearerFormat,
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
        }
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

