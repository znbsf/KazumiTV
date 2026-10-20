// Explicit QA observation only. Never persists URLs, headers or response bytes.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'media_context_summary.dart';
import 'media_response_analysis.dart';

Future<Map<String, Object?>> observeMediaRoot({
  required bool enabled,
  required bool debug,
  required String packageName,
  required String mediaUrl,
  required Map<String, String> headers,
  required bool Function() isCancelled,
  Duration budget = const Duration(seconds: 10),
}) async {
  if (!qaMediaMetadataEnabled(
      enabled: enabled, debug: debug, packageName: packageName)) {
    return {'enabled': false};
  }
  final observations = <Map<String, Object?>>[];
  final result = <String, Object?>{
    'enabled': true,
    'transport': 'QA Dart HttpClient; not native-player HTTP parity',
    'max_requests': 2,
    'max_body_bytes_per_request': mediaObservationByteLimit,
    'raw_context_saved': false,
    'observations': observations,
  };
  final clock = Stopwatch()..start();
  final limit = budget < const Duration(seconds: 10)
      ? budget
      : const Duration(seconds: 10);
  bool cancelled() {
    try {
      return isCancelled();
    } catch (_) {
      return true;
    }
  }

  Duration remaining() {
    if (cancelled()) throw const _ObservationCancelled();
    final left = limit - clock.elapsed;
    if (left <= Duration.zero) {
      throw TimeoutException('QA observation deadline');
    }
    return left;
  }

  HttpClient? activeClient;
  final cancelPoll = Timer.periodic(const Duration(milliseconds: 20), (_) {
    if (cancelled()) {
      try {
        activeClient?.close(force: true);
      } catch (error) {
        result['cancel_close_error_type'] = error.runtimeType.toString();
      }
    }
  });
  try {
    var url = mediaUrl;
    for (var index = 0; index < 2; index++) {
      remaining();
      final uri = Uri.tryParse(url);
      if (url.length > 8192 ||
          uri == null ||
          !{'http', 'https'}.contains(uri.scheme) ||
          uri.host.isEmpty ||
          uri.userInfo.isNotEmpty ||
          uri.fragment.isNotEmpty) {
        result['stop_reason'] = 'invalid_resource';
        break;
      }
      // The root is an already resolved playback URL, including short-lived
      // delivery signatures. It stays in memory; signed children are not probed.
      final record = <String, Object?>{
        'role': index == 0 ? 'root' : 'child',
        'resource': {
          'host': uri.host,
          'sha256': sha256.convert(utf8.encode(url)).toString(),
        },
      };
      observations.add(record);
      final client = HttpClient()..connectionTimeout = remaining();
      activeClient = client;
      StreamIterator<List<int>>? stream;
      MediaResponseAnalysis? analysis;
      try {
        final request = await client.getUrl(uri).timeout(remaining());
        remaining();
        request.followRedirects = false;
        for (final entry in headers.entries) {
          if (!{'user-agent', 'referer'}.contains(entry.key.toLowerCase())) {
            continue;
          }
          if (entry.value.length > 8192 ||
              entry.value.contains('\r') ||
              entry.value.contains('\n')) {
            throw const FormatException('Invalid QA request header');
          }
          request.headers.set(entry.key, entry.value);
        }
        request.headers
            .set('Range', 'bytes=0-${mediaObservationByteLimit - 1}');
        final response = await request.close().timeout(remaining());
        remaining();
        record['status'] = response.statusCode;
        final bytes = BytesBuilder(copy: false);
        stream = StreamIterator(response);
        while (await stream.moveNext().timeout(remaining())) {
          remaining();
          final chunk = stream.current;
          final available = mediaObservationByteLimit - bytes.length;
          bytes.add(chunk.length <= available
              ? chunk
              : chunk.take(available).toList(growable: false));
          if (bytes.length >= mediaObservationByteLimit) break;
        }
        remaining();
        analysis = analyzeMediaResponse(
          requestUrl: url,
          status: response.statusCode,
          contentType: response.headers.contentType?.mimeType ?? '',
          body: bytes.takeBytes(),
          observedAt: DateTime.now(),
          challengeHeader:
              response.headers.value('cf-mitigated')?.toLowerCase() ==
                  'challenge',
          redirectLocation: response.headers.value(HttpHeaders.locationHeader),
          remainingBudget: remaining(),
          requestsAlreadyObserved: index + 1,
        );
        record.addAll(analysis.publicRecord);
      } finally {
        final cleanup = <String, Object?>{
          'client_closed': false,
          'stream_cancelled': stream == null,
        };
        record['cleanup'] = cleanup;
        try {
          client.close(force: true);
          cleanup['client_closed'] = true;
        } catch (error) {
          cleanup['client_error_type'] = error.runtimeType.toString();
        }
        activeClient = null;
        // Closing transport first ensures a stalled body cannot hold cleanup.
        final cleanupRemaining = limit - clock.elapsed;
        final cleanupWait = cleanupRemaining <= Duration.zero
            ? Duration.zero
            : cleanupRemaining < const Duration(milliseconds: 250)
                ? cleanupRemaining
                : const Duration(milliseconds: 250);
        try {
          await stream?.cancel().timeout(cleanupWait);
          cleanup['stream_cancelled'] = true;
        } catch (error) {
          cleanup['stream_error_type'] = error.runtimeType.toString();
        }
        cleanup['status'] = cleanup['client_closed'] == true &&
                cleanup['stream_cancelled'] == true
            ? 'confirmed'
            : 'unconfirmed';
        if (cleanup['status'] != 'confirmed') {
          result['cleanup_unconfirmed'] = true;
        }
      }
      if (result['cleanup_unconfirmed'] == true) {
        result['outcome'] = 'cleanup_unconfirmed';
        break;
      }
      remaining();
      final child = analysis.childUrlInMemory;
      if (child == null) {
        result['stop_reason'] = analysis.publicRecord['stop_reason'];
        break;
      }
      url = child;
    }
    result['outcome'] ??= 'observed';
  } catch (error) {
    result['outcome'] = cancelled() || error is _ObservationCancelled
        ? 'cancelled'
        : error is TimeoutException
            ? 'timeout'
            : 'transport_error';
    // Never stringify exceptions: many transports include the full request URI.
    result['error_type'] = error.runtimeType.toString();
  } finally {
    cancelPoll.cancel();
    try {
      activeClient?.close(force: true);
    } catch (error) {
      result['cleanup_unconfirmed'] = true;
      result['final_close_error_type'] = error.runtimeType.toString();
    }
    result['elapsed_ms'] = clock.elapsedMilliseconds;
  }
  return result;
}

class _ObservationCancelled implements Exception {
  const _ObservationCancelled();
}
