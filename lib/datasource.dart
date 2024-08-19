class DataSource {
  final DataSourceType sourceType;
  final String? uri;

  DataSource({required this.sourceType, this.uri});
}

enum DataSourceType {
  file,
  network,
  asset,
  contentUri,
}
