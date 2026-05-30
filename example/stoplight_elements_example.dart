import 'package:stoplight_elements/stoplight_elements.dart';

@ApiModel(description: 'Health check payload')
class HealthData {
  @ApiProperty(description: 'Service status', example: 'ok')
  final String status;

  HealthData({required this.status});
}

void main() {
  OpenApiConfig.configure(
    title: 'Example API',
    version: '1.0.0',
    serverUrl: 'http://localhost:8000/',
  );

  OpenApiRegistry.instance.autoScan(
    libraryFilter: (uri) => uri.toString().contains('stoplight_elements_example'),
  );

  OpenApiRegistry.instance.registerModel(
    'HealthData',
    const ApiModel(
      description: 'Health check payload',
      properties: {
        'status': ApiProperty(type: 'string', description: 'Service status'),
      },
    ),
  );

  final spec = OpenApiRegistry.instance.buildOpenApi();
  print(spec['info']);

  final html = buildStoplightElementsHtml(openapiUrl: '/openapi.json');
  print('Generated docs HTML (${html.length} bytes)');
}
