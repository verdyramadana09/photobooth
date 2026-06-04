class GridConfig {
  final int cols;
  final int rows;

  GridConfig(this.cols, this.rows);

  int get total => cols * rows;
}

GridConfig parseLayout(String layout) {
  if (layout.startsWith('grid')) {
    final parts = layout.split('_')[1].split('x');
    return GridConfig(
      int.parse(parts[0]),
      int.parse(parts[1]),
    );
  } else if (layout.startsWith('strip')) {
    final count = int.parse(layout.split('_')[1].split('x')[1]);
    return GridConfig(1, count);
  }

  return GridConfig(2, 2);
}