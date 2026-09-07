import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../config.dart';

/// โมเดลร้านอาหารใกล้ตัว
class NearbyShop {
  final String name;
  final String address;
  final double rating;
  final double lat;
  final double lng;

  const NearbyShop({
    required this.name,
    required this.address,
    required this.rating,
    required this.lat,
    required this.lng,
  });
}

/// ค้นหาร้านอาหารจริงใกล้ตำแหน่งด้วย Geoapify Places API
class NearbyPlacesService {
  static const String _baseUrl = 'https://api.geoapify.com/v2/places';
  static const String _categories =
      'catering.restaurant,catering.fast_food,catering.cafe';
  static const int _radiusMeters = 3000;
  static const int _limit = 20;

  static Future<List<NearbyShop>> searchNearbyRestaurants({
    required double lat,
    required double lng,
  }) async {
    final uri = Uri.parse(_baseUrl).replace(queryParameters: {
      'apiKey': geoapifyApiKey,
      'categories': _categories,
      'filter': 'circle:$lng,$lat,$_radiusMeters',
      'bias': 'proximity:$lng,$lat',
      'limit': '$_limit',
    });

    try {
      final response = await http.get(uri).timeout(const Duration(seconds: 8));
      debugPrint('Geoapify ${response.statusCode}');

      if (response.statusCode != 200) {
        debugPrint('Geoapify error ${response.statusCode}: ${response.body}');
        return [];
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final features = data['features'] as List? ?? [];

      return features
          .map((f) => _fromFeature(f, lat, lng))
          .whereType<NearbyShop>()
          .toList();
    } catch (e) {
      debugPrint('Geoapify error: $e');
      return [];
    }
  }

  /// แปลง feature (GeoJSON) เป็น [NearbyShop] (ข้ามถ้าไม่มีชื่อ)
  static NearbyShop? _fromFeature(dynamic feature, double lat, double lng) {
    final props = feature['properties'] as Map<String, dynamic>? ?? {};
    final name = props['name'] as String?;
    if (name == null || name.isEmpty) return null;

    return NearbyShop(
      name: name,
      address: props['formatted'] ?? '',
      rating: 0,
      lat: (props['lat'] as num?)?.toDouble() ?? lat,
      lng: (props['lon'] as num?)?.toDouble() ?? lng,
    );
  }
}
