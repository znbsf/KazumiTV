import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:kazumi/bean/widget/error_widget.dart';
import 'package:kazumi/bean/widget/empty_state_widget.dart';
import 'package:kazumi/pages/info/info_comments_view.dart';
import 'package:kazumi/bean/card/character_card.dart';
import 'package:kazumi/bean/card/staff_card.dart';
import 'package:kazumi/bean/card/network_img_layer.dart';
import 'package:kazumi/bean/widget/tv_visuals.dart';
import 'package:kazumi/bean/widget/tv_focusable_surface.dart';
import 'package:kazumi/services/platform/tv_mode.dart';
import 'package:skeletonizer/skeletonizer.dart';
import 'package:kazumi/modules/bangumi/bangumi_item.dart';
import 'package:kazumi/modules/bangumi/bangumi_relation.dart';
import 'package:kazumi/modules/comments/comment_item.dart';
import 'package:kazumi/modules/characters/character_item.dart';
import 'package:kazumi/modules/staff/staff_item.dart';
import 'package:kazumi/utils/constants.dart';
import 'package:kazumi/utils/device.dart';

class InfoTabView extends StatefulWidget {
  const InfoTabView({
    super.key,
    required this.commentsQueryTimeout,
    required this.commentsHasLoaded,
    required this.charactersQueryTimeout,
    required this.charactersIsEmpty,
    required this.staffQueryTimeout,
    required this.staffIsEmpty,
    required this.relationsQueryTimeout,
    required this.relationsIsLoading,
    required this.relationsHasLoaded,
    required this.tabController,
    required this.loadMoreComments,
    required this.loadCharacters,
    required this.loadStaff,
    required this.loadRelations,
    required this.bangumiItem,
    required this.commentsList,
    required this.commentsIsLoading,
    required this.onWriteReview,
    required this.characterList,
    required this.staffList,
    required this.relationList,
    required this.isLoading,
  });

  final bool commentsQueryTimeout;
  final bool commentsHasLoaded;
  final bool commentsIsLoading;
  final VoidCallback onWriteReview;
  final bool charactersQueryTimeout;
  final bool charactersIsEmpty;
  final bool staffQueryTimeout;
  final bool staffIsEmpty;
  final bool relationsQueryTimeout;
  final bool relationsIsLoading;
  final bool relationsHasLoaded;
  final TabController tabController;
  final Future<void> Function({bool loadMore}) loadMoreComments;
  final Future<void> Function() loadCharacters;
  final Future<void> Function() loadStaff;
  final Future<void> Function() loadRelations;
  final BangumiItem bangumiItem;
  final List<CommentItem> commentsList;
  final List<CharacterItem> characterList;
  final List<StaffFullItem> staffList;
  final List<BangumiRelation> relationList;
  final bool isLoading;

  @override
  State<InfoTabView> createState() => _InfoTabViewState();
}

class _InfoTabViewState extends State<InfoTabView> {
  final maxWidth = 950.0;
  bool fullIntro = false;
  bool fullTag = false;

  Widget get infoBody {
    if (TvMode.enabled) return _tvInfoBody;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: SizedBox(
          width: MediaQuery.sizeOf(context).width > maxWidth
              ? maxWidth
              : MediaQuery.sizeOf(context).width - 32,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('简介', style: TextStyle(fontSize: 18)),
              const SizedBox(height: 8),
              LayoutBuilder(builder: (context, constraints) {
                final span = TextSpan(text: widget.bangumiItem.summary);
                final tp =
                    TextPainter(text: span, textDirection: TextDirection.ltr);
                tp.layout(maxWidth: constraints.maxWidth);
                final numLines = tp.computeLineMetrics().length;
                if (numLines > 7) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      SizedBox(
                        height: fullIntro ? null : 120,
                        width: MediaQuery.sizeOf(context).width > maxWidth
                            ? maxWidth
                            : MediaQuery.sizeOf(context).width - 32,
                        child: SelectableText(
                          widget.bangumiItem.summary,
                          textAlign: TextAlign.start,
                          scrollBehavior: const ScrollBehavior().copyWith(
                            scrollbars: false,
                          ),
                          scrollPhysics: NeverScrollableScrollPhysics(),
                          selectionHeightStyle: ui.BoxHeightStyle.max,
                        ),
                      ),
                      TextButton(
                        onPressed: () {
                          setState(() {
                            fullIntro = !fullIntro;
                          });
                        },
                        child: Text(fullIntro ? '加载更少' : '加载更多'),
                      ),
                    ],
                  );
                } else {
                  return SelectableText(
                    widget.bangumiItem.summary,
                    textAlign: TextAlign.start,
                    scrollPhysics: NeverScrollableScrollPhysics(),
                    selectionHeightStyle: ui.BoxHeightStyle.max,
                  );
                }
              }),
              const SizedBox(height: 16),
              Text('标签', style: TextStyle(fontSize: 18)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8.0,
                runSpacing: isDesktop() ? 8 : 0,
                children: List<Widget>.generate(
                    fullTag || widget.bangumiItem.tags.length < 13
                        ? widget.bangumiItem.tags.length
                        : 13, (int index) {
                  if (!fullTag && index == 12) {
                    return ActionChip(
                      label: Text(
                        '更多 +',
                        style: TextStyle(
                            color: Theme.of(context).colorScheme.primary),
                      ),
                      onPressed: () {
                        setState(() {
                          fullTag = !fullTag;
                        });
                      },
                    );
                  }
                  return ActionChip(
                    label: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('${widget.bangumiItem.tags[index].name} '),
                        Text(
                          '${widget.bangumiItem.tags[index].count}',
                          style: TextStyle(
                              color: Theme.of(context).colorScheme.primary),
                        ),
                      ],
                    ),
                    onPressed: () {
                      final tagName = Uri.encodeComponent(
                          widget.bangumiItem.tags[index].name);
                      context.pushNamed('/search/$tagName');
                    },
                  );
                }).toList(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget get _tvInfoBody => Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxWidth),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // The native-style header already previews five synopsis lines
                // beside the cover; this body retains full reading and tags.
                if (widget.bangumiItem.summary.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: () => showDialog<void>(
                      context: context,
                      builder: (_) => TvSynopsisReader(
                        title: widget.bangumiItem.nameCn.isEmpty
                            ? widget.bangumiItem.name
                            : widget.bangumiItem.nameCn,
                        summary: widget.bangumiItem.summary,
                      ),
                    ),
                    child: const Text('阅读完整简介', style: TvVisuals.control),
                  ),
                ],
                if (widget.bangumiItem.tags.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  const Text('标签', style: TvVisuals.title),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final tag in widget.bangumiItem.tags.take(
                        fullTag ? widget.bangumiItem.tags.length : 12,
                      ))
                        ActionChip(
                          label: Text(
                            '${tag.name} ${tag.count}',
                            style: TvVisuals.control,
                          ),
                          onPressed: () => context.pushNamed(
                            '/search/${Uri.encodeComponent(tag.name)}',
                          ),
                        ),
                      if (!fullTag && widget.bangumiItem.tags.length > 12)
                        ActionChip(
                          label: const Text('更多 +', style: TvVisuals.control),
                          onPressed: () => setState(() => fullTag = true),
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      );

  Widget get relationsListBody {
    return Builder(
      builder: (BuildContext context) {
        return CustomScrollView(
          scrollBehavior: const ScrollBehavior().copyWith(
            scrollbars: false,
          ),
          key: const PageStorageKey<String>('关联'),
          slivers: <Widget>[
            SliverOverlapInjector(
              handle: NestedScrollView.sliverOverlapAbsorberHandleFor(context),
            ),
            SliverLayoutBuilder(
              builder: (context, constraints) {
                if (widget.relationsQueryTimeout) {
                  return SliverFillRemaining(
                    hasScrollBody: false,
                    child: GeneralErrorWidget(
                      title: '关联条目加载失败',
                      errMsg: '请检查网络连接后重试。',
                      onRetry: widget.loadRelations,
                    ),
                  );
                }
                if (widget.relationsHasLoaded && widget.relationList.isEmpty) {
                  return const SliverFillRemaining(
                    hasScrollBody: false,
                    child: GeneralEmptyState(
                      icon: Icons.account_tree_rounded,
                      title: '暂无关联条目',
                    ),
                  );
                }

                final horizontalPadding =
                    ((constraints.crossAxisExtent - maxWidth) / 2)
                        .clamp(16.0, double.infinity)
                        .toDouble();
                final contentWidth =
                    constraints.crossAxisExtent - horizontalPadding * 2;
                final crossAxisCount = contentWidth >= 840
                    ? 3
                    : contentWidth >= 560
                        ? 2
                        : 1;
                final showSkeleton =
                    !widget.relationsHasLoaded || widget.relationsIsLoading;
                final itemCount =
                    showSkeleton ? crossAxisCount : widget.relationList.length;

                return SliverPadding(
                  padding: EdgeInsets.fromLTRB(
                    horizontalPadding,
                    16,
                    horizontalPadding,
                    16,
                  ),
                  sliver: SliverGrid(
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: crossAxisCount,
                      mainAxisSpacing: StyleString.cardSpace,
                      crossAxisSpacing: StyleString.cardSpace,
                      mainAxisExtent: _RelatedBangumiCardH.cardHeight,
                    ),
                    delegate: SliverChildBuilderDelegate(
                      (context, index) {
                        if (showSkeleton) {
                          return LayoutBuilder(
                            builder: (context, constraints) {
                              return Skeletonizer.zone(
                                child: Bone(
                                  width: constraints.maxWidth,
                                  height: _RelatedBangumiCardH.cardHeight,
                                  uniRadius: 14,
                                ),
                              );
                            },
                          );
                        }
                        return _RelatedBangumiCardH(
                          relation: widget.relationList[index],
                        );
                      },
                      childCount: itemCount,
                    ),
                  ),
                );
              },
            ),
          ],
        );
      },
    );
  }

  Widget get infoBodyBone {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: SizedBox(
          width: MediaQuery.sizeOf(context).width > maxWidth
              ? maxWidth
              : MediaQuery.sizeOf(context).width - 32,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Skeletonizer.zone(
                  child:
                      Bone.text(fontSize: TvMode.enabled ? 16 : 18, width: 50)),
              const SizedBox(height: 8),
              Skeletonizer.zone(child: Bone.multiText(lines: 7)),
              const SizedBox(height: 16),
              Skeletonizer.zone(
                  child:
                      Bone.text(fontSize: TvMode.enabled ? 16 : 18, width: 50)),
              const SizedBox(height: 8),
              if (widget.isLoading)
                Skeletonizer.zone(
                  child: Wrap(
                    spacing: 8.0,
                    runSpacing: 8.0,
                    children: List.generate(
                        4, (_) => Bone.button(uniRadius: 8, height: 32)),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget get staffListBody {
    return Builder(
      builder: (BuildContext context) {
        return CustomScrollView(
          scrollBehavior: const ScrollBehavior().copyWith(
            scrollbars: false,
          ),
          key: PageStorageKey<String>('制作人员'),
          slivers: <Widget>[
            SliverOverlapInjector(
              handle: NestedScrollView.sliverOverlapAbsorberHandleFor(context),
            ),
            SliverLayoutBuilder(builder: (context, _) {
              if (widget.staffList.isNotEmpty) {
                return SliverList.builder(
                  itemCount: widget.staffList.length,
                  itemBuilder: (context, index) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16.0),
                        child: SizedBox(
                          width: MediaQuery.sizeOf(context).width > maxWidth
                              ? maxWidth
                              : MediaQuery.sizeOf(context).width - 32,
                          child: StaffCard(
                            staffFullItem: widget.staffList[index],
                          ),
                        ),
                      ),
                    );
                  },
                );
              }
              if (widget.staffQueryTimeout) {
                return SliverFillRemaining(
                  child: GeneralErrorWidget(
                    title: '制作人员加载失败',
                    errMsg: '请检查网络连接后重试。',
                    onRetry: widget.loadStaff,
                  ),
                );
              }
              if (widget.staffIsEmpty) {
                return const SliverFillRemaining(
                  hasScrollBody: false,
                  child: GeneralEmptyState(
                    icon: Icons.groups_rounded,
                    title: '暂无制作人员信息',
                  ),
                );
              }
              return SliverList.builder(
                itemCount: 8,
                itemBuilder: (context, _) {
                  return Align(
                    alignment: Alignment.topCenter,
                    child: SizedBox(
                      width: MediaQuery.sizeOf(context).width > maxWidth
                          ? maxWidth
                          : MediaQuery.sizeOf(context).width - 32,
                      child: Skeletonizer.zone(
                        child: ListTile(
                          leading: Bone.circle(size: 36),
                          title: Bone.text(width: 100),
                          subtitle: Bone.text(width: 80),
                        ),
                      ),
                    ),
                  );
                },
              );
            }),
          ],
        );
      },
    );
  }

  Widget get charactersListBody {
    return Builder(
      builder: (BuildContext context) {
        return CustomScrollView(
          scrollBehavior: const ScrollBehavior().copyWith(
            scrollbars: false,
          ),
          key: PageStorageKey<String>('角色'),
          slivers: <Widget>[
            SliverOverlapInjector(
              handle: NestedScrollView.sliverOverlapAbsorberHandleFor(context),
            ),
            SliverLayoutBuilder(builder: (context, _) {
              if (widget.characterList.isNotEmpty) {
                return SliverList.builder(
                  itemCount: widget.characterList.length,
                  itemBuilder: (context, index) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16.0),
                        child: SizedBox(
                          width: MediaQuery.sizeOf(context).width > maxWidth
                              ? maxWidth
                              : MediaQuery.sizeOf(context).width - 32,
                          child: CharacterCard(
                            characterItem: widget.characterList[index],
                          ),
                        ),
                      ),
                    );
                  },
                );
              }
              if (widget.charactersQueryTimeout) {
                return SliverFillRemaining(
                  child: GeneralErrorWidget(
                    title: '角色列表加载失败',
                    errMsg: '请检查网络连接后重试。',
                    onRetry: widget.loadCharacters,
                  ),
                );
              }
              if (widget.charactersIsEmpty) {
                return const SliverFillRemaining(
                  hasScrollBody: false,
                  child: GeneralEmptyState(
                    icon: Icons.people_alt_rounded,
                    title: '暂无角色信息',
                  ),
                );
              }
              return SliverList.builder(
                itemCount: 4,
                itemBuilder: (context, _) {
                  return Align(
                    alignment: Alignment.topCenter,
                    child: SizedBox(
                      width: MediaQuery.sizeOf(context).width > maxWidth
                          ? maxWidth
                          : MediaQuery.sizeOf(context).width - 32,
                      child: Skeletonizer.zone(
                        child: ListTile(
                          leading: Bone.circle(size: 36),
                          title: Bone.text(width: 100),
                          subtitle: Bone.text(width: 80),
                        ),
                      ),
                    ),
                  );
                },
              );
            }),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return TabBarView(
      controller: widget.tabController,
      children: [
        Builder(
          // Resolve the overlap handle inside the NestedScrollView.
          builder: (BuildContext context) {
            return CustomScrollView(
              scrollBehavior: const ScrollBehavior().copyWith(
                scrollbars: false,
              ),
              key: PageStorageKey<String>('概览'),
              slivers: <Widget>[
                SliverOverlapInjector(
                  handle:
                      NestedScrollView.sliverOverlapAbsorberHandleFor(context),
                ),
                SliverToBoxAdapter(
                  child: SafeArea(
                    top: false,
                    bottom: false,
                    child: widget.isLoading ? infoBodyBone : infoBody,
                  ),
                ),
              ],
            );
          },
        ),
        InfoCommentsView(
          interest: widget.bangumiItem.interest,
          comments: widget.commentsList,
          isLoading: widget.commentsIsLoading,
          hasLoaded: widget.commentsHasLoaded,
          hasError: widget.commentsQueryTimeout,
          onReviewTap: widget.onWriteReview,
          onRetry: () => widget.loadMoreComments(loadMore: false),
          onLoadMore: () => widget.loadMoreComments(loadMore: true),
        ),
        charactersListBody,
        relationsListBody,
        staffListBody,
      ],
    );
  }
}

/// Native main's full synopsis interaction, using the same Dart subject data.
/// The text itself owns up/down so remote navigation does not enter selection.
class TvSynopsisReader extends StatefulWidget {
  const TvSynopsisReader({
    super.key,
    required this.title,
    required this.summary,
  });
  final String title;
  final String summary;

  @override
  State<TvSynopsisReader> createState() => _TvSynopsisReaderState();
}

class _TvSynopsisReaderState extends State<TvSynopsisReader> {
  final _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final delta = switch (event.logicalKey) {
      LogicalKeyboardKey.arrowDown => 220.0,
      LogicalKeyboardKey.arrowUp => -220.0,
      _ => 0.0,
    };
    if (delta == 0 || !_scroll.hasClients) return KeyEventResult.ignored;
    final next = (_scroll.offset + delta)
        .clamp(0.0, _scroll.position.maxScrollExtent)
        .toDouble();
    if (next == _scroll.offset) return KeyEventResult.ignored;
    _scroll.jumpTo(next);
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) => Dialog(
        backgroundColor: TvVisuals.background,
        child: SizedBox(
          width: 950,
          height: MediaQuery.sizeOf(context).height * .8,
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TvVisuals.heading.copyWith(color: TvVisuals.text),
                ),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('返回详情', style: TvVisuals.control),
                ),
                const Text('方向键上下阅读，返回键回到详情。', style: TvVisuals.caption),
                const SizedBox(height: 12),
                Expanded(
                  child: Focus(
                    autofocus: true,
                    onKeyEvent: _onKey,
                    child: SingleChildScrollView(
                      controller: _scroll,
                      child: Text(
                        widget.summary,
                        style: TvVisuals.body.copyWith(color: TvVisuals.text),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
}

class _RelatedBangumiCardH extends StatelessWidget {
  const _RelatedBangumiCardH({required this.relation});

  static const double cardHeight = 108;
  static const double imageHeight = 92;
  static const double posterAspectRatio = 0.65;

  final BangumiRelation relation;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final textScaler =
        MediaQuery.textScalerOf(context).clamp(maxScaleFactor: 1.1);
    final relationLabel = relation.relation.isEmpty ? '关联' : relation.relation;
    final bangumiItem = relation.toBangumiItem();
    final title = bangumiItem.nameCn.isEmpty
        ? bangumiItem.name.trim()
        : bangumiItem.nameCn.trim();

    void openDetails() => context.pushNamed('/info/', arguments: bangumiItem);
    final visibleImageHeight = TvMode.enabled ? imageHeight - 4 : imageHeight;
    final card = Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      color: colorScheme.surfaceContainerLow,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
      ),
      child: InkWell(
        onTap: openDetails,
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final gap = constraints.maxWidth.clamp(0.0, 10.0).toDouble();
              final maxImageWidth =
                  (constraints.maxWidth - gap).clamp(0.0, 152.0);
              final imageWidth = (constraints.maxWidth * 0.42)
                  .clamp(0.0, maxImageWidth)
                  .toDouble();

              return Row(
                children: [
                  NetworkImgLayer(
                    src: TvMode.enabled
                        ? NetworkImgLayer.tvListCoverUrl(bangumiItem.images)
                        : bangumiItem.images['large'] ?? '',
                    width: imageWidth,
                    height: visibleImageHeight,
                    origAspectRatio: posterAspectRatio,
                  ),
                  SizedBox(width: gap),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.start,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Align(
                            alignment: Alignment.topLeft,
                            child: Text(
                              title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              textScaler: textScaler,
                              style: theme.textTheme.titleSmall?.copyWith(
                                color: colorScheme.onSurface,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                        Text(
                          relationLabel,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textScaler: textScaler,
                          style: theme.textTheme.titleSmall?.copyWith(
                            color: colorScheme.primary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
    return TvMode.enabled
        ? TvFocusableSurface(
            onPressed: openDetails,
            borderRadius: 14,
            focusScale: 1,
            child: card,
          )
        : card;
  }
}
