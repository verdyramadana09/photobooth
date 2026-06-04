class FrameTemplate {
  final String path;
  final String type; // 'asset' atau 'file'
  final String layout;
  final int requiredPhotos;

  final double horizontalPadding;
  final double verticalPadding;
  final double spacing;
  final double aspectRatio;

  FrameTemplate({
    required this.path,
    required this.type,
    required this.layout,
    required this.requiredPhotos,
    double? horizontalPadding,
    double? verticalPadding,
    double? spacing,
    double? aspectRatio,
  })  : horizontalPadding = (horizontalPadding ?? 15).toDouble(),
        verticalPadding = (verticalPadding ?? 45).toDouble(),
        spacing = (spacing ?? 10).toDouble(),
        aspectRatio = (aspectRatio ?? 0.82).toDouble();
}