import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' show Offset;

import 'package:image/image.dart' as img;

class PreparedCropImage {
  final Uint8List bytes;
  final int width;
  final int height;
  const PreparedCropImage(this.bytes, this.width, this.height);
}

PreparedCropImage prepareCropImage(Uint8List bytes) {
  final decoded = img.decodeImage(bytes);
  if (decoded == null) throw const FormatException('Unsupported image.');
  var image = img.bakeOrientation(decoded);
  if (math.max(image.width, image.height) > 3000) {
    image = image.width >= image.height
        ? img.copyResize(image, width: 3000)
        : img.copyResize(image, height: 3000);
  }
  return PreparedCropImage(
    img.encodeJpg(image, quality: 95),
    image.width,
    image.height,
  );
}

/// Normalized corners in clockwise order: top-left, top-right, bottom-right, bottom-left.
Uint8List rectifyCrop((Uint8List, List<Offset>) input) {
  final (bytes, corners) = input;
  if (corners.length != 4 ||
      corners.any(
        (p) =>
            !p.dx.isFinite ||
            !p.dy.isFinite ||
            p.dx < 0 ||
            p.dx > 1 ||
            p.dy < 0 ||
            p.dy > 1,
      )) {
    throw const FormatException('Invalid document corners.');
  }
  for (var i = 0; i < 4; i++) {
    final a = corners[(i + 1) % 4] - corners[i];
    final b = corners[(i + 2) % 4] - corners[(i + 1) % 4];
    if (a.dx * b.dy - a.dy * b.dx <= 0.001) {
      throw const FormatException(
        'Document corners must not cross or overlap.',
      );
    }
  }
  final image = img.decodeImage(bytes);
  if (image == null) throw const FormatException('Unsupported image.');
  final points = corners
      .map((p) => Offset(p.dx * (image.width - 1), p.dy * (image.height - 1)))
      .toList();
  final width =
      math
          .max(
            (points[1] - points[0]).distance,
            (points[2] - points[3]).distance,
          )
          .round() +
      1;
  final height =
      math
          .max(
            (points[3] - points[0]).distance,
            (points[2] - points[1]).distance,
          )
          .round() +
      1;
  if (width < 16 || height < 16) {
    throw const FormatException('Document area is too small.');
  }
  img.Point point(int i) => img.Point(points[i].dx, points[i].dy);
  final cropped = img.copyRectify(
    image,
    topLeft: point(0),
    topRight: point(1),
    bottomRight: point(2),
    bottomLeft: point(3),
    interpolation: img.Interpolation.linear,
    toImage: img.Image(width: width, height: height, numChannels: 3),
  );
  return img.encodeJpg(cropped, quality: 95);
}
