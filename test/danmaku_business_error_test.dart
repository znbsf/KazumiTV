import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/request/clients/danmaku_client.dart';
import 'package:kazumi/request/core/network_exception.dart';
import 'package:kazumi/services/danmaku/danmaku_cache_service.dart';
import 'package:kazumi/modules/danmaku/danmaku_episode_response.dart';

void main() {
  test('HTTP 200 business 429 enters cooldown before caching', () async {
    final root =
        await Directory.systemTemp.createTemp('kazumi_business_error_');
    final cache = DanmakuCacheService(
        directory: () async => root,
        enabled: () => true,
        privateMode: () => false,
        limitMiB: () => 64);
    final dio = Dio();
    var requests = 0;
    dio.interceptors.add(InterceptorsWrapper(onRequest: (request, handler) {
      requests++;
      handler.resolve(Response(requestOptions: request, statusCode: 200, data: {
        'success': false,
        'errorCode': 429,
        'errorMessage': 'limited',
        'bangumi': null
      }));
    }));
    final client = DanmakuClient.forTesting(dio: dio, cache: cache);
    final error =
        isA<NetworkException>().having((e) => e.statusCode, 'code', 429);
    try {
      await expectLater(
          client.get('https://api.dandanplay.net/api/v2/bangumi/1'),
          throwsA(error));
      await expectLater(
          client.get('https://api.dandanplay.net/api/v2/comment/2'),
          throwsA(error));
      expect(requests, 1);
      expect((await cache.stats())['entries'], 0);
      expect(
          () => DanmakuEpisodeResponse.fromJson(
              {'success': false, 'errorCode': 429}),
          throwsA(error));
    } finally {
      await cache.close();
      dio.close(force: true);
      await root.delete(recursive: true);
    }
  });
  test('episode response round trips with its anime ID', () {
    final response = DanmakuEpisodeResponse(
        bangumiId: 12,
        episodes: [DanmakuEpisode(episodeId: 3, episodeTitle: 'one')],
        errorCode: 0,
        success: true,
        errorMessage: '');
    final decoded = DanmakuEpisodeResponse.fromJson(response.toJson());
    expect(decoded.bangumiId, 12);
    expect(decoded.episodes.single.episodeId, 3);
  });
}
