// Passive QA diagnostics. No new requests, retries, headers or challenge solving.
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:kazumi/request/core/network_exception.dart';
import 'package:kazumi/services/logging/playback_trace.dart';
import 'package:kazumi/services/plugin/rule_engine_models.dart';

Map<String, Object?> batchFailureSnapshot(Object error) {
  final chain = <Map<String, Object?>>[];
  final result = <String, Object?>{'chain': chain};
  Object? current = error;
  for (var i = 0; current != null && i < 5; i++) {
    final entry = <String, Object?>{'type': current.runtimeType.toString()};
    chain.add(entry);
    if (current is SearchErrorException) {
      current = current.cause;
    } else if (current is ChapterErrorException) {
      current = current.cause;
    } else if (current is NetworkException) {
      entry.addAll(
          {'network_type': current.type.name, 'status': current.statusCode});
      current = current.rawError;
    } else if (current is DioException) {
      entry['dio_type'] = current.type.name;
      result['request'] = {
        'method': current.requestOptions.method,
        'resource':
            PlaybackTrace.resource(current.requestOptions.uri.toString()),
      };
      final response = current.response;
      if (response != null) {
        final headers = <String, String>{};
        for (final key in ['content-type', 'server', 'cf-mitigated']) {
          final values = response.headers[key];
          if (values != null) {
            headers[key] = PlaybackTrace.safeDetail(values.join(', '));
          }
        }
        final data = response.data;
        final bytes = data is String ? utf8.encode(data) : null;
        result['response'] = {
          'status': response.statusCode,
          'headers': headers,
          'body_type': data.runtimeType.toString(),
          'body_bytes': bytes?.length,
          'body_sha256':
              bytes == null ? null : sha256.convert(bytes).toString(),
        };
        // Positive evidence only; absence does not prove no challenge.
        result['actual_challenge_observed'] =
            headers['cf-mitigated']?.toLowerCase() == 'challenge' ||
                (data is String && data.contains('window._cf_chl_opt'));
      }
      current = current.error;
    } else {
      entry['detail'] = PlaybackTrace.safeDetail(current);
      current = null;
    }
  }
  return result;
}
