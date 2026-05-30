## 0.0.6

- Restructure documentation: English `README.md` (pub.dev default), Chinese `README_zh.md`.

## 0.0.5

- Infer nested types from Dart fields: `@ApiModel` classes → `$ref`, inline objects, `List<T>`, `Map<K,V>`.
- Add `ApiProperty.schema` shorthand (`User` → `#/components/schemas/User`), `items`, `additionalProperties`.
- `ApiProperty.required` is nullable; omitted values are inferred from nullability.

## 0.0.4

- Support field-level `@ApiProperty` on model members (merged with class-level `properties` and type inference).
- `ApiProperty.type` is optional; omitted types are inferred from the Dart field type.

## 0.0.3

- Initial version.
