# Changelog

## 0.1.4

- Wire up `dart-lang/setup-dart` in the publish workflow so pub.dev OIDC trusted publishing is used instead of falling back to interactive OAuth.
- Bump reported `bridgeVersion` to keep the app-side compatibility metadata aligned with the released package version.

## 0.1.3

- Update install guidance to prefer `flutter pub add`, document the FVM path, and show non-release bridge startup.
- Refresh package dependencies, including `shelf_web_socket` 3.x.
- Raise the minimum Dart SDK to 3.5 and align Flutter support with the Melos 7 workspace tooling.

## 0.1.2

- Improve benchmark startup readiness for CI-driven screenshot and bridge runs.
- Prepare package metadata for the first automated pub.dev release.

## 0.1.1

- Update hosted-install guidance for pub.dev consumption.

## 0.1.0

- Initial public release of the in-app Flutter bridge server.