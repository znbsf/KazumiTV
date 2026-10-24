import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/request/core/network_exception.dart';
import 'package:kazumi/services/plugin/rule_engine_models.dart';

import '../tools/qa/source_batch/failure_snapshot.dart';

void main() {
  test('retains nested network cause without signed URL or credentials', () {
    final request =
        RequestOptions(path: 'https://site.test/search?token=PRIVATE');
    final snapshot = batchFailureSnapshot(SearchErrorException('source',
        cause: NetworkException(
            type: NetworkExceptionType.unknown,
            message: 'network',
            rawError: DioException(
                requestOptions: request,
                error: StateError(
                    'TLS failed 50% https://cdn.test/?sign=PRIVATE')))));
    expect((snapshot['chain'] as List).length, 4);
    final serialized = jsonEncode(snapshot);
    expect(serialized, contains('TLS failed 50%'));
    expect(serialized, contains('site.test#'));
    expect(serialized, isNot(contains('PRIVATE')));
    expect(serialized, isNot(contains('/search')));
  });

  test('records response identity and positive challenge without response body',
      () {
    final request = RequestOptions(path: 'https://site.test/search');
    final snapshot = batchFailureSnapshot(DioException(
        requestOptions: request,
        response: Response<String>(
            requestOptions: request,
            statusCode: 403,
            headers: Headers.fromMap({
              'cf-mitigated': ['challenge'],
              'set-cookie': ['PRIVATE'],
            }),
            data: '<html>PRIVATE CHALLENGE BODY</html>')));
    expect(snapshot['actual_challenge_observed'], isTrue);
    expect((snapshot['response'] as Map)['status'], 403);
    expect((snapshot['response'] as Map)['body_sha256'], isNotNull);
    expect(jsonEncode(snapshot), isNot(contains('PRIVATE')));
    expect(jsonEncode(snapshot), isNot(contains('set-cookie')));
  });
}
