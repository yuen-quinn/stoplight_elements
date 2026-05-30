import 'package:stoplight_elements/stoplight_elements.dart';
import 'package:test/test.dart';

class InlineAddress {
  @ApiProperty(description: 'Street')
  final String street;

  InlineAddress({required this.street});
}

@ApiModel(description: 'Address')
class Address {
  @ApiProperty(description: 'Street')
  final String street;

  Address({required this.street});
}

@ApiModel(description: 'User DTO')
class UserDto {
  @ApiProperty(description: 'User id', required: true)
  final String id;

  UserDto({required this.id});
}

@ApiModel(description: 'Profile')
class Profile {
  @ApiProperty(description: 'Display name')
  final String name;

  final InlineAddress address;

  final List<UserDto> friends;

  Profile({
    required this.name,
    required this.address,
    required this.friends,
  });
}

@ApiModel(description: 'Envelope')
class Envelope {
  final UserDto data;

  final List<UserDto> items;

  final Map<String, UserDto> byId;

  Envelope({
    required this.data,
    required this.items,
    required this.byId,
  });
}

@ApiModel(description: 'Wrap')
class Wrap {
  @ApiProperty(schema: 'UserDto', description: 'payload')
  final dynamic payload;

  Wrap({required this.payload});
}

void main() {
  setUp(() {
    OpenApiRegistry.instance.resetForTesting();
    OpenApiRegistry.instance.autoScan(
      libraryFilter: (uri) => uri.toString().contains('nested_schema_test'),
    );
  });

  test('nested object uses component ref', () {
    final spec = OpenApiRegistry.instance.buildOpenApi();
    final envelope = spec['components']['schemas']['Envelope'] as Map;
    final props = envelope['properties'] as Map<String, dynamic>;

    expect(props['data'], {'\$ref': '#/components/schemas/UserDto'});
    expect(props['items'], {
      'type': 'array',
      'items': {'\$ref': '#/components/schemas/UserDto'},
    });
    expect(
      props['byId']['additionalProperties'],
      {'\$ref': '#/components/schemas/UserDto'},
    );
  });

  test('inline nested object without ApiModel on field type', () {
    final spec = OpenApiRegistry.instance.buildOpenApi();
    final profile = spec['components']['schemas']['Profile'] as Map;
    final address = profile['properties']['address'] as Map;

    expect(address['type'], 'object');
    expect(address['properties']['street']['description'], 'Street');
  });

  test('nested ApiModel class uses ref', () {
    final spec = OpenApiRegistry.instance.buildOpenApi();
    expect(spec['components']['schemas']['Address'], isNotNull);
  });

  test('schema shorthand on ApiProperty', () {
    final spec = OpenApiRegistry.instance.buildOpenApi();
    final wrap = spec['components']['schemas']['Wrap'] as Map;
    expect(
      wrap['properties']['payload'],
      {
        '\$ref': '#/components/schemas/UserDto',
        'description': 'payload',
      },
    );
  });
}
