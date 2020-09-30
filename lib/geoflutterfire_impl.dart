import 'dart:async';
import 'dart:core';

import 'package:geoflutterfire/utils.dart';
import 'package:realtime_database/realtime_database.dart';

import 'geoflutterfire.dart';

class GeoflutterfireImpl extends Geoflutterfire {
  final RealtimeDatabase _database;

  GeoflutterfireImpl(this._database);

  @override
  Stream addGeoQueryListenerAt(
    String path,
    List<double> center,
    double radius,
  ) {
    final controller = StreamController();
    final queries = geohashQueries(center, radius);
    final map = Map();
    final subs = List<StreamSubscription>();

    final streams = queries.map(
      (query) => _database.watchValueAtPath(
        path,
        orderByChild: "g",
        startAt: query[0],
        endAt: query[1],
      ),
    );

    streams.forEach((stream) {
      subs.add(stream.listen((value) {
        map.addAll(value ?? {});
        controller.add(map);
      }));
    });

    controller.onCancel = () {
      controller.close();
      subs.forEach((it) => it.cancel());
    };

    return controller.stream;
  }
}
