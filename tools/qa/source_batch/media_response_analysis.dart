// Offline response analysis only. No transport, file I/O or QA runtime hook.
import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

const mediaObservationByteLimit = 64 * 1024;

Map<String, String> _resource(String value) {
  final uri = Uri.tryParse(value);
  return {
    'host': uri?.host ?? 'invalid',
    'sha256': sha256.convert(utf8.encode(value)).toString(),
  };
}

String? mediaObservationStopReason(String value) {
  final uri = Uri.tryParse(value);
  if (value.length > 8192 ||
      uri == null ||
      uri.host.isEmpty ||
      !['http', 'https'].contains(uri.scheme) ||
      uri.userInfo.isNotEmpty ||
      uri.fragment.isNotEmpty) {
    return 'invalid_or_ambiguous_url';
  }
  const sensitive = {
    'token',
    'access_token',
    'auth',
    'authorization',
    'sign',
    'signature',
    'dis_k',
    'dis_t',
    'expires',
    'expiry',
    'exp',
    'policy',
    'key-pair-id',
    'x-amz-signature'
  };
  if (RegExp(r'https?(?::|%3a|%253a)(?://|%2f%2f|%252f%252f)',
          caseSensitive: false)
      .hasMatch(uri.query)) {
    return 'nested_url_query';
  }
  try {
    for (final part in uri.query.split('&')) {
      final key = Uri.decodeComponent(part.split('=').first).toLowerCase();
      if (sensitive.contains(key)) return 'signature_signal';
    }
  } catch (_) {
    return 'invalid_or_ambiguous_url';
  }
  return null;
}

class MediaResponseAnalysis {
  MediaResponseAnalysis(this.publicRecord, this.childUrlInMemory);
  final Map<String, Object?> publicRecord;
  // Explicitly omitted from publicRecord/toString. This is not a live request.
  final String? childUrlInMemory;
  @override
  String toString() => jsonEncode(publicRecord);
}

MediaResponseAnalysis analyzeMediaResponse({
  required String requestUrl,
  required int status,
  required String contentType,
  required Uint8List body,
  required DateTime observedAt,
  bool challengeHeader = false,
  String? redirectLocation,
  bool cancelled = false,
  Duration remainingBudget = const Duration(seconds: 10),
  int requestsAlreadyObserved = 1,
}) {
  final bytes = body.length > mediaObservationByteLimit
      ? body.sublist(0, mediaObservationByteLimit)
      : body;
  final text = utf8.decode(bytes, allowMalformed: true).trim();
  final lower = text.toLowerCase();
  final mime = contentType.split(';').first.trim().toLowerCase();
  final challenge = challengeHeader ||
      lower.contains('window._cf_chl_opt') ||
      lower.contains('challenge-platform') ||
      lower.contains('<title>just a moment');
  final kind = challenge
      ? 'challenge'
      : RegExp(r'^\s*(?:<!doctype\s+html|<html|<body)', caseSensitive: false)
              .hasMatch(text)
          ? 'html'
          : bytes.length >= 12 &&
                  ascii.decode(bytes.sublist(4, 8), allowInvalid: true) ==
                      'ftyp'
              ? 'mp4'
              : text.startsWith('#EXTM3U')
                  ? 'hls'
                  : 'plain_text_or_unknown';
  final record = <String, Object?>{
    'resource': _resource(requestUrl),
    'status': status,
    'content_type': RegExp(r'^[a-z0-9.+-]+/[a-z0-9.+-]+$').hasMatch(mime)
        ? mime
        : 'unknown',
    'buffered_bytes': bytes.length,
    'body_limit_reached': body.length >= mediaObservationByteLimit,
    'structure': kind,
    'observed_at_utc': observedAt.toUtc().toIso8601String(),
    'hls_tags': <String>[],
    'candidate_resources': <Map<String, Object?>>[],
  };
  if (status >= 300 && status < 400 && redirectLocation != null) {
    try {
      record['redirect_resource'] =
          _resource(Uri.parse(requestUrl).resolve(redirectLocation).toString());
    } catch (_) {
      record['redirect_identity'] = 'invalid';
    }
  }
  String? stop = cancelled
      ? 'cancelled'
      : remainingBudget <= Duration.zero
          ? 'budget_exhausted'
          : requestsAlreadyObserved >= 2
              ? 'request_limit'
              : mediaObservationStopReason(requestUrl);
  stop ??= challenge
      ? 'challenge'
      : status >= 300 && status < 400
          ? 'redirect_not_followed'
          : status < 200 || status >= 300
              ? 'http_status'
              : body.length >= mediaObservationByteLimit
                  ? 'body_limit'
                  : kind == 'html' || kind == 'mp4'
                      ? 'terminal_structure'
                      : null;
  final candidates = <String, String>{};
  final tags = <String>{};
  const knownTags = {
    'EXTM3U',
    'EXTINF',
    'EXT-X-VERSION',
    'EXT-X-TARGETDURATION',
    'EXT-X-MEDIA-SEQUENCE',
    'EXT-X-ENDLIST',
    'EXT-X-STREAM-INF',
    'EXT-X-MEDIA',
    'EXT-X-I-FRAME-STREAM-INF',
    'EXT-X-DISCONTINUITY',
    'EXT-X-KEY',
    'EXT-X-MAP',
    'EXT-X-PROGRAM-DATE-TIME',
    'EXT-X-PLAYLIST-TYPE',
    'EXT-X-BYTERANGE',
    'EXT-X-INDEPENDENT-SEGMENTS',
    'EXT-X-SESSION-KEY'
  };
  var additionalUri = false, invalidLine = false;
  if (stop == null) {
    for (final line in const LineSplitter().convert(text)) {
      final value = line.trim();
      if (value.isEmpty) continue;
      if (value.startsWith('#')) {
        final tag =
            RegExp(r'^#([A-Z0-9-]+)(?::|$)').firstMatch(value)?.group(1);
        if (tag != null) {
          tags.add(knownTags.contains(tag) ? tag : 'OTHER_TAG');
        }
        if (RegExp(r'\bURI\s*=', caseSensitive: false).hasMatch(value)) {
          additionalUri = true;
        }
        continue;
      }
      if (RegExp(r'\s').hasMatch(value) ||
          (kind != 'hls' &&
              !RegExp(r'^(?:https?://|[^<>]+\.(?:m3u8|mp4|ts)(?:\?|$))',
                      caseSensitive: false)
                  .hasMatch(value))) {
        invalidLine = true;
        continue;
      }
      try {
        final resolved = Uri.parse(requestUrl).resolve(value).toString();
        if (Uri.parse(resolved) == Uri.parse(requestUrl)) {
          stop = 'cyclic_child';
          continue;
        }
        if (mediaObservationStopReason(resolved) != null) {
          stop = 'signed_or_invalid_child';
          continue;
        }
        candidates[resolved] =
            Uri.parse(value).hasScheme ? 'absolute' : 'relative';
      } catch (_) {
        invalidLine = true;
      }
    }
    record['hls_tags'] = tags.toList()..sort();
    record['candidate_resources'] = candidates.entries
        .take(8)
        .map((e) =>
            <String, Object?>{..._resource(e.key), 'relationship': e.value})
        .toList();
    record['unique_candidate_count'] = candidates.length;
    if (kind == 'plain_text_or_unknown' &&
        !invalidLine &&
        candidates.isNotEmpty) {
      record['structure'] = 'plain_text_list';
    }
    stop ??= additionalUri
        ? 'additional_uri_attributes'
        : invalidLine
            ? 'unknown_lines'
            : candidates.length != 1
                ? 'no_unique_child'
                : null;
  }
  record['stop_reason'] = stop;
  record['child_observation_eligible'] = stop == null;
  return MediaResponseAnalysis(
      record, stop == null ? candidates.keys.single : null);
}
