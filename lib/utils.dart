import 'dart:math';

class Range {
  double min;
  double max;
  Range({required this.min, required this.max});
}

// Default geohash length
const GEOHASH_PRECISION = 10;
// Characters used in location geohashes
const BASE32 = '0123456789bcdefghjkmnpqrstuvwxyz';
// The meridional circumference of the earth in meters
const EARTH_MERI_CIRCUMFERENCE = 40007860;
// Length of a degree latitude at the equator
const METERS_PER_DEGREE_LATITUDE = 110574;
// Number of bits per geohash character
const BITS_PER_CHAR = 5;
// Maximum length of a geohash in bits
const MAXIMUM_BITS_PRECISION = 22 * BITS_PER_CHAR;
// Equatorial radius of the earth in meters
const EARTH_EQ_RADIUS = 6378137.0;
// The following value assumes a polar radius of
// const EARTH_POL_RADIUS = 6356752.3;
// The formulate to calculate E2 is
// E2 == (EARTH_EQ_RADIUS^2-EARTH_POL_RADIUS^2)/(EARTH_EQ_RADIUS^2)
// The exact value is used here to avoid rounding errors
const E2 = 0.00669447819799;
// Cutoff for rounding errors on double calculations
const EPSILON = 1e-12;

/*
 * Calculates a set of queries to fully contain a given circle. A query is a [start, end] pair
 * where any geohash is guaranteed to be lexiographically larger then start and smaller than end.
 *
 * @param center The center given as [latitude, longitude] pair.
 * @param radius The radius of the circle.
 * @return An array of geohashes containing a [start, end] pair.
 */
List<List<String>> geohashQueries(List<double> center, double radius) {
  // validateLocation(center);
  var queryBits = max(1, boundingBoxBits(center, radius));
  var geohasPrecisionDouble = queryBits / BITS_PER_CHAR;
  var geohashPrecision = geohasPrecisionDouble.ceil();
  var coordinates = boundingBoxCoordinates(center, radius);

  var queries = coordinates.map(
    (coordinate) => geohashQuery(
      encodeGeohash(coordinate, geohashPrecision),
      queryBits,
    ),
  );

  // remove duplicates

  int index = -1, otherIndex = -1;

  return queries.where((query) {
    index++;
    otherIndex = -1;
    return !queries.any((other) {
      otherIndex++;
      return index > otherIndex && query[0] == other[0] && query[1] == other[1];
    });
  }).toList();
}

/*
 * Calculates the maximum number of bits of a geohash to get a bounding box that is larger than a
 * given size at the given coordinate.
 *
 * @param coordinate The coordinate as a [latitude, longitude] pair.
 * @param size The size of the bounding box.
 * @returns The number of bits necessary for the geohash.
 */
int boundingBoxBits(List<double> coordinate, size) {
  final latDeltaDegrees = size / METERS_PER_DEGREE_LATITUDE;
  final latitudeNorth = min(90, coordinate[0] + latDeltaDegrees);
  final latitudeSouth = max(-90, coordinate[0] - latDeltaDegrees);
  final bitsLat = latitudeBitsForResolution(size).floor() * 2;
  final bitsLongNorth =
      longitudeBitsForResolution(size, latitudeNorth).floor() * 2 - 1;
  final bitsLongSouth =
      longitudeBitsForResolution(size, latitudeSouth).floor() * 2 - 1;
  return min(
      min(bitsLat, bitsLongNorth), min(bitsLongSouth, MAXIMUM_BITS_PRECISION));
}

/*
 * Calculates eight points on the bounding box and the center of a given circle. At least one
 * geohash of these nine coordinates, truncated to a precision of at most radius, are guaranteed
 * to be prefixes of any geohash that lies within the circle.
 *
 * @param center The center given as [latitude, longitude].
 * @param radius The radius of the circle.
 * @returns The eight bounding box points.
 */
List<List<double>> boundingBoxCoordinates(List<double> center, double radius) {
  double latDegrees = radius / METERS_PER_DEGREE_LATITUDE;
  double latitudeNorth = min(90, center[0] + latDegrees);
  double latitudeSouth = max(-90, center[0] - latDegrees);
  double longDegsNorth = metersToLongitudeDegrees(radius, latitudeNorth);
  double longDegsSouth = metersToLongitudeDegrees(radius, latitudeSouth);
  double longDegs = max(longDegsNorth, longDegsSouth);
  return [
    [center[0], center[1]],
    [center[0], wrapLongitude(center[1] - longDegs)],
    [center[0], wrapLongitude(center[1] + longDegs)],
    [latitudeNorth, center[1]],
    [latitudeNorth, wrapLongitude(center[1] - longDegs)],
    [latitudeNorth, wrapLongitude(center[1] + longDegs)],
    [latitudeSouth, center[1]],
    [latitudeSouth, wrapLongitude(center[1] - longDegs)],
    [latitudeSouth, wrapLongitude(center[1] + longDegs)]
  ];
}

/*
 * Calculates the bounding box query for a geohash with x bits precision.
 *
 * @param geohash The geohash whose bounding box query to generate.
 * @param bits The number of bits of precision.
 * @returns A [start, end] pair of geohashes.
 */
List<String> geohashQuery(String geohash, int bits) {
  // validateGeohash(geohash);

  double precisionDouble = bits / BITS_PER_CHAR;
  int precision = precisionDouble.ceil();
  if (geohash.length < precision) {
    return [geohash, geohash + '~'];
  }
  geohash = geohash.substring(0, precision);
  String base = geohash.substring(0, geohash.length - 1);
  int lastValue = BASE32.indexOf(geohash[geohash.length - 1]);
  int significantBits = bits - (base.length * BITS_PER_CHAR);
  int unusedBits = (BITS_PER_CHAR - significantBits);
  // delete unused bits
  int startValue = (lastValue >> unusedBits) << unusedBits;
  int endValue = startValue + (1 << unusedBits);
  if (endValue > 31) {
    return [base + BASE32[startValue], base + '~'];
  } else {
    return [base + BASE32[startValue], base + BASE32[endValue]];
  }
}

/*
 * Generates a geohash of the specified precision/string length from the  [latitude, longitude]
 * pair, specified as an array.
 *
 * @param location The [latitude, longitude] pair to encode into a geohash.
 * @param precision The length of the geohash to create. If no precision is specified, the
 * global default is used.
 * @returns The geohash of the inputted location.
 */
String encodeGeohash(location, precision) {
//  if (precision === void 0) { precision = GEOHASH_PRECISION; }
  // validateLocation(location);
//  if (typeof precision !== 'undefined') {
//    if (typeof precision !== 'number' || isNaN(precision)) {
//  throw new Error('precision must be a number');
//  }
//  else if (precision <= 0) {
//  throw new Error('precision must be greater than 0');
//  }
//  else if (precision > 22) {
//  throw new Error('precision cannot be greater than 22');
//  }
//  else if (Math.round(precision) !== precision) {
//  throw new Error('precision must be an integer');
//  }
//  }

  final latitudeRange = Range(
    min: -90,
    max: 90,
  );
  final longitudeRange = Range(
    min: -180,
    max: 180,
  );

  String hash = '';
  int hashVal = 0;
  int bits = 0;
  bool even = true;
  while (hash.length < precision) {
    double val = even ? location[1] : location[0];
    Range range = even ? longitudeRange : latitudeRange;
    double mid = (range.min + range.max) / 2;
    if (val > mid) {
      hashVal = (hashVal << 1) + 1;
      range.min = mid;
    } else {
      hashVal = (hashVal << 1) + 0;
      range.max = mid;
    }
    even = !even;
    if (bits < 4) {
      bits++;
    } else {
      bits = 0;
      hash += BASE32[hashVal];
      hashVal = 0;
    }
  }
  return hash;
}

/*
 * Calculates the bits necessary to reach a given resolution, in meters, for the latitude.
 *
 * @param resolution The bits necessary to reach a given resolution, in meters.
 * @returns Bits necessary to reach a given resolution, in meters, for the latitude.
 */
double latitudeBitsForResolution(resolution) {
  return min(log2(EARTH_MERI_CIRCUMFERENCE / 2 / resolution),
      MAXIMUM_BITS_PRECISION.toDouble());
}

/*
 * Calculates the bits necessary to reach a given resolution, in meters, for the longitude at a
 * given latitude.
 *
 * @param resolution The desired resolution.
 * @param latitude The latitude used in the conversion.
 * @return The bits necessary to reach a given resolution, in meters.
 */
double longitudeBitsForResolution(resolution, latitude) {
  final degs = metersToLongitudeDegrees(resolution, latitude);
  return (degs.abs() > 0.000001) ? max(1, log2(360 / degs)) : 1;
}

/*
 * Calculates the number of degrees a given distance is at a given latitude.
 *
 * @param distance The distance to convert.
 * @param latitude The latitude at which to calculate.
 * @returns The number of degrees the distance corresponds to.
 */
double metersToLongitudeDegrees(distance, latitude) {
  final radians = degreesToRadians(latitude);
  final num = cos(radians) * EARTH_EQ_RADIUS * pi / 180;
  final denom = 1 / sqrt(1 - E2 * sin(radians) * sin(radians));
  final deltaDeg = num * denom;
  if (deltaDeg < EPSILON) {
    return distance > 0 ? 360 : 0;
  } else {
    return min(360, distance / deltaDeg);
  }
}

double wrapLongitude(longitude) {
  if (longitude <= 180 && longitude >= -180) {
    return longitude;
  }
  final adjusted = longitude + 180;
  if (adjusted > 0) {
    return (adjusted % 360) - 180;
  } else {
    return 180 - (-adjusted % 360) as double;
  }
}

double log2(x) {
  return log(x) / log(2);
}

/*
 * Converts degrees to radians.
 *
 * @param degrees The number of degrees to be converted to radians.
 * @returns The number of radians equal to the inputted number of degrees.
 */
double degreesToRadians(degrees) {
//  if (typeof degrees !== 'number' || isNaN(degrees)) {
//  throw new Error('Error: degrees must be a number');
//  }
  return (degrees * pi / 180);
}
