import 'dart:ui' as ui;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/bbcode/bbcode_widget.dart';
import 'package:kazumi/bean/card/user_comments_card.dart';
import 'package:kazumi/bean/widget/image_preview.dart';
import 'package:kazumi/bean/widget/tv_comment_reading_surface.dart';
import 'package:kazumi/bean/widget/tv_focus_navigation.dart';
import 'package:kazumi/modules/comments/comment_item.dart';
import 'package:kazumi/pages/player/episode_comments_view.dart';
import 'package:kazumi/services/platform/tv_mode.dart';

EpisodeComment _comment(int index, String content) => EpisodeComment(
      user: User(
        id: index,
        username: 'reader $index',
        nickname: 'reader $index',
        avatar: UserAvatar(small: '', medium: '', large: ''),
        sign: '',
        joinedAt: 0,
      ),
      comment: content,
      createdAt: 1700000000,
    );

EpisodeCommentItem _item(int index, String content,
        {List<EpisodeComment> replies = const []}) =>
    EpisodeCommentItem(comment: _comment(index, content), replies: replies);

Future<void> _key(WidgetTester tester, LogicalKeyboardKey key) async {
  await tester.sendKeyEvent(key);
  await tester.pumpAndSettle();
}

bool _focusedText(WidgetTester tester, String text) {
  final finder = find.text(text);
  return finder.evaluate().isNotEmpty &&
      Focus.of(tester.element(finder)).hasPrimaryFocus;
}

void _focusCard(WidgetTester tester, String author) {
  Focus.of(tester.element(find.text(author))).requestFocus();
}

Widget _app(Widget child) => MaterialApp(
      builder: (_, child) =>
          FocusTraversalGroup(policy: TvLoopTraversalPolicy(), child: child!),
      home: Scaffold(body: child),
    );

void main() {
  setUp(() => TvMode.setEnabledForTesting(true));
  tearDown(() => TvMode.setEnabledForTesting(false));

  for (final scale in [1.0, 1.5]) {
    testWidgets(
        'P-10 round trip and Back/re-entry ($scale)',
        (tester) async {
      tester.view.physicalSize = const Size(960, 540);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final entry = FocusNode();
      final picker = FocusNode();
      addTearDown(entry.dispose);
      addTearDown(picker.dispose);
      final comments = List.generate(
          45,
          (index) => _item(
              index,
              index == 15
                  ? List.generate(80, (line) => 'Long comment paragraph $line.')
                      .join('\n')
                  : 'Comment $index: readable with the remote.'));
      await tester.pumpWidget(_app(Builder(builder: (context) {
        return TextButton(
          focusNode: entry,
          autofocus: true,
          onPressed: () {
            showDialog<void>(
              context: context,
              builder: (_) => Dialog(
                child: SizedBox(
                  width: 400,
                  height: 440,
                  child: MediaQuery(
                    data: MediaQuery.of(context)
                        .copyWith(textScaler: TextScaler.linear(scale)),
                    child: EpisodeCommentsView(
                      episode: 1,
                      episodeInfo: null,
                      comments: comments,
                      isLoading: false,
                      hasError: false,
                      isAscending: true,
                      onToggleSort: () {},
                      onSelectEpisode: () {},
                      onRefresh: () {},
                      selectEpisodeFocusNode: picker,
                    ),
                  ),
                ),
              ),
            );
            // Start from the existing batch-1 header control, like D-pad entry.
            WidgetsBinding.instance.addPostFrameCallback((_) {
              picker.requestFocus();
            });
          },
          child: const Text('讨论入口'),
        );
      })));
      await tester.pumpAndSettle();
      await _key(tester, LogicalKeyboardKey.select);
      expect(picker.hasPrimaryFocus, isTrue);
      final scroll = tester.state<ScrollableState>(find.descendant(
          of: find.byType(EpisodeCommentsView),
          matching: find.byType(Scrollable)));
      final viewport = tester.getRect(find.byType(EpisodeCommentsView));
      const footer = '已显示全部 45 条讨论 · 来自 Bangumi';
      final forward = <int>{};
      var tallCardSteps = 0;
      for (var step = 0; step < 240 && !_focusedText(tester, footer); step++) {
        for (var index = 0; index < comments.length; index++) {
          if (_focusedText(tester, 'reader $index')) forward.add(index);
        }
        final readingTallCard = _focusedText(tester, 'reader 15');
        final offset = scroll.position.pixels;
        await _key(tester, LogicalKeyboardKey.arrowDown);
        if (readingTallCard &&
            _focusedText(tester, 'reader 15') &&
            scroll.position.pixels > offset) {
          tallCardSteps++;
        }
      }
      expect(forward, Set.of(List.generate(45, (index) => index)));
      expect(tallCardSteps, greaterThan(1),
          reason: 'An oversized card is read in overlapping steps, not skipped');
      expect(_focusedText(tester, footer), isTrue);
      expect(scroll.position.pixels, scroll.position.maxScrollExtent);
      final footerRect = tester.getRect(find.text(footer));
      expect(footerRect.top, greaterThanOrEqualTo(viewport.top));
      expect(footerRect.bottom, lessThanOrEqualTo(viewport.bottom));
      await _key(tester, LogicalKeyboardKey.arrowDown);
      expect(_focusedText(tester, footer), isTrue,
          reason: 'The final reading stop must not wrap to the header');

      final reverse = <int>{};
      for (var step = 0; step < 240 && !picker.hasPrimaryFocus; step++) {
        await _key(tester, LogicalKeyboardKey.arrowUp);
        for (var index = 0; index < comments.length; index++) {
          if (_focusedText(tester, 'reader $index')) reverse.add(index);
        }
      }
      expect(reverse, Set.of(List.generate(45, (index) => index)));
      expect(picker.hasPrimaryFocus, isTrue);
      expect(scroll.position.pixels, 0);
      expect(tester.getRect(find.text('切换分集')).top,
          greaterThanOrEqualTo(viewport.top));
      await _key(tester, LogicalKeyboardKey.escape);
      expect(find.byType(EpisodeCommentsView), findsNothing);
      expect(entry.hasPrimaryFocus, isTrue);
      await _key(tester, LogicalKeyboardKey.select);
      expect(picker.hasPrimaryFocus, isTrue);
      for (var step = 0;
          step < 6 && !_focusedText(tester, 'reader 0');
          step++) {
        await _key(tester, LogicalKeyboardKey.arrowDown);
      }
      expect(_focusedText(tester, 'reader 0'), isTrue);
      await _key(tester, LogicalKeyboardKey.escape);
      expect(find.byType(EpisodeCommentsView), findsNothing);
      expect(entry.hasPrimaryFocus, isTrue);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets('X-6 link/spoiler menu',
      (tester) async {
    final launches = <String>[];
    const channel = MethodChannel('plugins.flutter.io/url_launcher');
    tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'launch') {
        launches.add((call.arguments as Map)['url'] as String);
      }
      return true;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null));
    await tester.pumpWidget(_app(SingleChildScrollView(
      child: UserCommentsCard.episode(_item(0,
          '[url=https://example.com/discussion]link[/url] [mask]secret[/mask]')),
    )));
    _focusCard(tester, 'reader 0');
    await tester.pumpAndSettle();
    final cardFocus = FocusManager.instance.primaryFocus;
    await _key(tester, LogicalKeyboardKey.select);
    expect(find.text('评论操作'), findsOneWidget);
    expect(find.text('打开链接 https://example.com/discussion'), findsOneWidget);
    expect(find.text('显示遮罩'), findsOneWidget);
    await _key(tester, LogicalKeyboardKey.arrowDown);
    expect(_focusedText(tester, '显示遮罩'), isTrue);
    await _key(tester, LogicalKeyboardKey.select);
    expect(find.text('评论操作'), findsNothing);
    expect(cardFocus?.hasPrimaryFocus, isTrue);
    final bbcode = tester.state<BBCodeWidgetState>(find.byType(BBCodeWidget));
    expect(bbcode.tvActions.map((action) => action.label), contains('隐藏遮罩'));
    final rich = tester.widget<RichText>(find.descendant(
        of: find.byType(BBCodeWidget), matching: find.byType(RichText)));
    final secret = (rich.text as TextSpan)
        .children!
        .whereType<TextSpan>()
        .firstWhere((span) => span.text == 'secret');
    expect(secret.style?.color, isNot(Colors.transparent));

    await _key(tester, LogicalKeyboardKey.select);
    await _key(tester, LogicalKeyboardKey.select);
    expect(launches, ['https://example.com/discussion']);
    expect(cardFocus?.hasPrimaryFocus, isTrue);
    await _key(tester, LogicalKeyboardKey.select);
    await _key(tester, LogicalKeyboardKey.escape);
    expect(find.text('评论操作'), findsNothing);
    expect(cardFocus?.hasPrimaryFocus, isTrue);
    expect(find.byType(UserCommentsCard), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('X-6 reply actions',
      (tester) async {
    await tester.pumpWidget(_app(SingleChildScrollView(
      child: UserCommentsCard.episode(_item(0, 'Plain main comment', replies: [
        _comment(1, '[mask]reply secret[/mask]'),
        _comment(2, 'Plain reply'),
        _comment(3, '[url=https://example.com/reply]hidden reply[/url]'),
      ])),
    )));
    _focusCard(tester, 'reader 0');
    await tester.pumpAndSettle();
    await _key(tester, LogicalKeyboardKey.select);
    expect(find.text('回复 1 · 显示遮罩'), findsOneWidget);
    expect(find.text('展开其余回复'), findsOneWidget);
    expect(find.text('回复 3 · 打开链接 https://example.com/reply'), findsNothing);
    await _key(tester, LogicalKeyboardKey.arrowDown);
    await _key(tester, LogicalKeyboardKey.select);
    expect(find.text('reader 3'), findsOneWidget);
    expect(find.text('已显示 3 / 3 条回复'), findsOneWidget);
    expect(
      find.descendant(
          of: find.byType(UserCommentsCard), matching: find.byType(TextButton)),
      findsNothing,
    );
    await _key(tester, LogicalKeyboardKey.select);
    expect(find.text('回复 3 · 打开链接 https://example.com/reply'), findsOneWidget);
    expect(find.text('收起回复'), findsOneWidget);
    await _key(tester, LogicalKeyboardKey.arrowDown);
    await _key(tester, LogicalKeyboardKey.arrowDown);
    expect(_focusedText(tester, '收起回复'), isTrue);
    await _key(tester, LogicalKeyboardKey.select);
    expect(find.text('评论操作'), findsNothing);
    expect(find.text('reader 3'), findsNothing);
    expect(find.text('已显示 2 / 3 条回复'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('phone reply footer still expands and collapses inline',
      (tester) async {
    TvMode.setEnabledForTesting(false);
    await tester.pumpWidget(_app(SingleChildScrollView(
      child: UserCommentsCard.episode(_item(0, 'Phone comment', replies: [
        _comment(1, 'First reply'),
        _comment(2, 'Second reply'),
        _comment(3, 'Third reply'),
      ])),
    )));
    await tester.pumpAndSettle();
    expect(find.text('reader 3'), findsNothing);
    await tester.ensureVisible(find.text('展开其余 1 条回复'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('展开其余 1 条回复'));
    await tester.pumpAndSettle();
    expect(find.text('reader 3'), findsOneWidget);
    expect(find.text('收起回复'), findsOneWidget);
    expect(find.text('评论操作'), findsNothing);
    await tester.ensureVisible(find.text('收起回复'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('收起回复'));
    await tester.pumpAndSettle();
    expect(find.text('reader 3'), findsNothing);
    expect(find.text('展开其余 1 条回复'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('X-6 image preview',
      (tester) async {
    const url = 'https://example.com/comment.png';
    final recorder = ui.PictureRecorder();
    Canvas(recorder).drawColor(Colors.green, BlendMode.src);
    final picture = recorder.endRecording();
    final image = picture.toImageSync(20, 20);
    picture.dispose();
    final provider = CachedNetworkImageProvider(url);
    final imageKey = await provider.obtainKey(ImageConfiguration.empty);
    PaintingBinding.instance.imageCache.putIfAbsent(
        imageKey,
        () => OneFrameImageStreamCompleter(
            Future.value(ImageInfo(image: image))));
    addTearDown(() => PaintingBinding.instance.imageCache.evict(imageKey));
    ImageViewerRouteArgs? preview;
    final module = createModule(register: (c) {
      c.route('/',
          child: (_, __) => Scaffold(
                body: SingleChildScrollView(
                  child: UserCommentsCard.episode(_item(0, '[img]$url[/img]')),
                ),
              ));
      c.route(ImageViewer.routePath, child: (context, state) {
        preview = state.arguments as ImageViewerRouteArgs;
        return Scaffold(
          body: CallbackShortcuts(
            bindings: {
              const SingleActivator(LogicalKeyboardKey.escape): () =>
                  context.pop(),
            },
            child: const Focus(autofocus: true, child: Text('图片预览路由')),
          ),
        );
      });
    });
    await tester.pumpWidget(ModularApp(
      module: module,
      child: Builder(
          builder: (context) => MaterialApp.router(
              routerConfig: ModularApp.routerConfigOf(context))),
    ));
    await tester.pumpAndSettle();
    final size = tester.getSize(find.byType(CachedNetworkImage));
    _focusCard(tester, 'reader 0');
    await tester.pumpAndSettle();
    await _key(tester, LogicalKeyboardKey.select);
    expect(find.text('查看图片 1'), findsOneWidget);
    await _key(tester, LogicalKeyboardKey.select);
    expect(find.text('图片预览路由'), findsOneWidget);
    expect(preview?.imageUrls, [url]);
    expect(preview?.initialIndex, 0);
    expect(preview?.heroTag, ImageViewer.heroTagFor(url, 0));
    await _key(tester, LogicalKeyboardKey.escape);
    expect(find.text('图片预览路由'), findsNothing);
    expect(_focusedText(tester, 'reader 0'), isTrue);
    expect(tester.getSize(find.byType(CachedNetworkImage)), size);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('X-6 reading offset',
      (tester) async {
    await tester.pumpWidget(_app(SingleChildScrollView(
      child: UserCommentsCard.episode(_item(
          0,
          '${List.generate(80, (line) => 'Paragraph $line.').join('\n')} '
          '[mask]secret[/mask]')),
    )));
    _focusCard(tester, 'reader 0');
    await tester.pumpAndSettle();
    final scroll = tester.state<ScrollableState>(find.byType(Scrollable));
    await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    final offset = scroll.position.pixels;
    expect(offset, greaterThan(0));
    await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(scroll.position.pixels, offset);
    await _key(tester, LogicalKeyboardKey.select);
    await _key(tester, LogicalKeyboardKey.escape);
    expect(scroll.position.pixels, offset);
    await _key(tester, LogicalKeyboardKey.select);
    await _key(tester, LogicalKeyboardKey.select);
    expect(scroll.position.pixels, offset);
    expect(_focusedText(tester, 'reader 0'), isTrue);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('P-10 plain card',
      (tester) async {
    await tester.pumpWidget(_app(SingleChildScrollView(
      child: UserCommentsCard.episode(_item(0, 'Plain readable comment')),
    )));
    _focusCard(tester, 'reader 0');
    await tester.pumpAndSettle();
    final origin = FocusManager.instance.primaryFocus;
    await _key(tester, LogicalKeyboardKey.select);
    expect(find.byType(SimpleDialog), findsNothing);
    expect(origin?.hasPrimaryFocus, isTrue);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('X-6 phone spoiler',
      (tester) async {
    TvMode.setEnabledForTesting(false);
    await tester.pumpWidget(_app(SingleChildScrollView(
      child: UserCommentsCard.episode(_item(0, '[mask]phone secret[/mask]')),
    )));
    await tester.pumpAndSettle();
    expect(
        find.descendant(
            of: find.byType(TvCommentReadingSurface),
            matching: find.byType(Focus)),
        findsNothing);
    await tester.tap(find.byType(BBCodeWidget));
    await tester.pumpAndSettle();
    expect(find.byType(SimpleDialog), findsNothing);
    final bbcode = tester.state<BBCodeWidgetState>(find.byType(BBCodeWidget));
    expect(bbcode.tvActions.map((action) => action.label), contains('隐藏遮罩'));
    await tester.pumpWidget(const SizedBox());
  });
}
