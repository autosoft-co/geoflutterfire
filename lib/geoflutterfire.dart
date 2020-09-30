import 'package:geoflutterfire/geoflutterfire_impl.dart';
import 'package:realtime_database/realtime_database.dart';

abstract class Geoflutterfire {
  Stream<dynamic> addGeoQueryListenerAt(
    String path,
    List<double> center,
    double radius,
  );
}

Geoflutterfire constructGeoflutterfire(RealtimeDatabase database) =>
    GeoflutterfireImpl(database);
