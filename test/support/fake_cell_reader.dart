import 'dart:convert';
import 'dart:io' show gzip;
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:gps_cielo/core/data/cell_source.dart';
import 'package:gps_cielo/core/utils/geohash.dart';

const cellRelease = '2026-10-21.0';

typedef CellHome = ({String id, double lat, double lng});

/// `cells/{prefix}` on a fake server, plus the device cache Firestore keeps
/// of every document it read.
class FakeCellReader implements CellReader {
  final Map<String, Map<String, dynamic>> server = {};
  final Set<String> deviceCache = {};
  final List<String> serverReads = [];
  Object? failNextServerRead;

  @override
  Future<Map<String, dynamic>?> fromCache(String prefix) async =>
      deviceCache.contains(prefix) ? server[prefix] : null;

  @override
  Future<Map<String, dynamic>?> fromServer(String prefix) async {
    final error = failNextServerRead;
    if (error != null) {
      failNextServerRead = null;
      throw error;
    }
    serverReads.add(prefix);
    final doc = server[prefix];
    if (doc != null) deviceCache.add(prefix);
    return doc;
  }

  /// Writes [homes] as cell docs, like build_cells.py + seed_firestore.js:
  /// one doc per 5-char cell, except [split] cells, which become a stub plus
  /// one doc per non-empty 6-char child.
  void seed(List<CellHome> homes, {Set<String> split = const {}}) {
    final byCell = <String, List<CellHome>>{};
    for (final h in homes) {
      final g = Geohash.encode(h.lat, h.lng, 9);
      final p5 = g.substring(0, 5);
      final key = split.contains(p5) ? g.substring(0, 6) : p5;
      (byCell[key] ??= []).add(h);
    }
    for (final p in split) {
      server[p] = {'v': cellRelease, 'n': 0, 'split': 6};
    }
    byCell.forEach((prefix, list) {
      server[prefix] = {
        'v': cellRelease,
        'n': list.length,
        'h': Blob(cellGz(prefix, list)),
      };
    });
  }
}

Uint8List cellGz(String prefix, List<CellHome> homes) {
  final body = {
    'v': cellRelease,
    'p': prefix,
    'h': [
      for (final h in homes)
        {
          'i': h.id,
          'a': h.lat,
          'o': h.lng,
          'g': Geohash.encode(h.lat, h.lng, 9),
          'l': '${h.id.toUpperCase()} HELIX ST',
          'c': 'SPRING VALLEY, CA',
          'z': '91977',
        },
    ],
  };
  return Uint8List.fromList(gzip.encode(utf8.encode(jsonEncode(body))));
}
