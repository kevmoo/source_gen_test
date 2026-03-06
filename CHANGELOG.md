## 1.3.5-genLib

- Add support for `BuilderOptions` via a custom `TestBuildStep` implementation (handle patterns in extensions and multiple outputs). `TestBuildStep` keeps generated code in memory.
- Implement `generateForLibrary()` to generate all outputs for the specified library (with support for generating the golden files). Clients can inspect build outputs via the returned `TestBuildResults`.
- Normalize line-endings and paths for better support of Windows/MacOS platforms.

## 1.3.4

- Allow `analyzer: '>=9.0.0 <11.0.0'`

## 1.3.3

- Update dependencies
  - `analyzer: ^9.0.0`
  - `build_test: ^3.5.4`
  - `build: ^4.0.3`
  - `dart_style: ^3.1.3`
  - `meta: ^1.16.0`
  - `source_gen: ^4.1.1`
  - `test: ^1.27.0`

## 1.3.2

- Allow `build: '>=3.0.0 <5.0.0'`.
- Allow `source_gen: '>=3.0.0 <5.0.0'`.

## 1.3.1

- Update dependencies
  - `analyzer: '>=7.4.0 <9.0.0'`
  - `build_test: ^3.3.0`
  - `dart_style: ^3.0.0`
  - `test: ^1.25.9`

## 1.3.0

- Switch to analyzer element2 model and `build: ^3.0.0`.

## 1.2.0

- Require `build: ^2.5.0`.
- Require `build_test: ^3.2.0`.
- Require `sdk: ^3.7.0`
- Fixed some doc comment references.

## 1.1.1

- Support the latest `package:analyzer` and `package:source_gen`.

## 1.1.0

- Add `ShouldGenerateFile`.
- Require `source_gen: ^1.5.0`.
- Require `sdk: ^3.4.0`

## 1.0.6

- Support the latest `package:analyzer`
- Require `sdk: ^3.0.0`

## 1.0.5

- Require `analyzer: ^5.2.0`
- Require `sdk: '>=2.19.0 <3.0.0'`
- Fix for latest `pkg:source_gen`

## 1.0.4

- Require `analyzer: '>=4.6.0 <6.0.0'`
- Require `sdk: '>=2.17.0 <3.0.0'`

## 1.0.3

- Support the latest `package:analyzer`.

## 1.0.2

- Support the latest `package:analyzer`.

## 1.0.1

- Support the latest `package:analyzer`.

## 1.0.0

- Migrate to null safety.
- Require Dart `2.12.0`.

## 0.1.1+4

- Support the latest `package:build` and `package:build_test`.

## 0.1.1+3

- Support the latest `package:analyzer`.
- Require at least Dart 2.10

## 0.1.1+2

- Support the latest `package:analyzer`.

## 0.1.1+1

- Support the latest `package:analyzer`.

## 0.1.1

- Require at least Dart 2.2
- Support the latest `package:build_test`.

## 0.1.0+6

- Support the latest `package:analyzer`.

## 0.1.0+5

- Support the latest `package:analyzer`.

## 0.1.0+4

- Support the latest `package:analyzer`.

## 0.1.0+3

- Support the latest `package:analyzer`.

## 0.1.0+2

- Fix `generateForElement` for fields.

## 0.1.0+1

- Fix and improve errors thrown when generators are not used.

## 0.1.0

- First release.
