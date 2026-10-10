import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:kazumi/bean/card/network_img_layer.dart';
import 'package:kazumi/modules/bangumi/bangumi_item.dart';
import 'package:kazumi/services/platform/tv_mode.dart';
import 'package:kazumi/bean/widget/tv_focusable_surface.dart';

class BangumiTimelineCard extends StatelessWidget {
  const BangumiTimelineCard({
    super.key,
    required this.bangumiItem,
    required this.showRating,
    required this.onTap,
    this.isWatching = false,
    this.compact = false,
  });

  final BangumiItem bangumiItem;
  final bool showRating;
  final bool isWatching;
  final bool compact;
  final VoidCallback onTap;

  static final _episodePattern =
      RegExp(r'^\s*([1-9]\d*)\s*[话話集](?=\s*(?:[/／]|$))');

  static const _contentPadding = 12.0;
  static const _cornerRadius = 28.0;
  static const _titleFontSize = 16.0;
  static const _titleLineHeight = 1.5;
  static const _labelFontSize = 12.0;
  static const _labelLineHeight = 4 / 3;
  static const _metadataGap = 8.0;
  static const _footerGap = 12.0;
  static const _ratingIconSize = 16.0;
  static const _ratingPadding =
      EdgeInsets.symmetric(horizontal: 10, vertical: 6);

  // Shared by the grid and card to keep their text-scaled heights in sync.
  static double heightFor(TextScaler scaler, {bool compact = false}) {
    if (TvMode.enabled) {
      // Includes the focus frame (10), card padding (12), two title lines
      // and one metadata/rating line. Grow for accessibility text scaling.
      return 22 +
          math.max(
              72.0, scaler.scale(16) * 1.35 * 2 + 4 + scaler.scale(12) * 4 / 3);
    }
    final titleHeight = scaler.scale(_titleFontSize) * _titleLineHeight * 2;
    final labelHeight = scaler.scale(_labelFontSize) * _labelLineHeight;
    final footerHeight =
        math.max(_ratingIconSize, labelHeight) + _ratingPadding.vertical;
    final contentHeight = math.max(
      compact ? 120.0 : 136.0,
      titleHeight + _metadataGap + labelHeight + _footerGap + footerHeight,
    );
    return _contentPadding * 2 + contentHeight;
  }

  String _supportingText(String title) {
    // Calendar entries expose episode counts through info.
    final episodes = _episodePattern.firstMatch(bangumiItem.info);
    final tags = bangumiItem.metaTags.isNotEmpty
        ? bangumiItem.metaTags
        : bangumiItem.tags.map((tag) => tag.name);
    final metadata = <String>[
      if (episodes != null) '${episodes.group(1)} 话',
      ...tags
          .map((name) => name.trim())
          .where((name) => name.isNotEmpty)
          .toSet(),
    ];
    if (metadata.isNotEmpty) return metadata.take(3).join(' · ');
    final originalName = bangumiItem.name.trim();
    return originalName != title ? originalName : '';
  }

  @override
  Widget build(BuildContext context) {
    final card = Semantics(
      button: true,
      child: Card(
        elevation: 0,
        margin: EdgeInsets.zero,
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(_cornerRadius)),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: SizedBox(
            height:
                heightFor(MediaQuery.textScalerOf(context), compact: compact),
            child: Padding(
              padding: EdgeInsets.all(TvMode.enabled ? 6 : _contentPadding),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildCover(context),
                  SizedBox(
                      width: TvMode.enabled
                          ? 12
                          : compact
                              ? 12
                              : 16),
                  Expanded(child: _buildDetails(context)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    if (!TvMode.enabled) return card;
    return TvFocusableSurface(
      onPressed: onTap,
      focusScale: 1,
      borderRadius: _cornerRadius,
      child: card,
    );
  }

  Widget _buildDetails(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final translatedName = bangumiItem.nameCn.trim();
    final title =
        translatedName.isNotEmpty ? translatedName : bangumiItem.name.trim();
    final supportingText = _supportingText(title);

    if (TvMode.enabled) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleMedium?.copyWith(
                  fontSize: 16,
                  height: 1.35,
                  fontWeight: FontWeight.w700,
                  color: colors.onSurface)),
          const SizedBox(height: 4),
          Row(children: [
            Expanded(
                child: Text(supportingText,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                        fontSize: 12,
                        height: 4 / 3,
                        color: colors.onSurfaceVariant))),
            if (showRating) ...[
              const SizedBox(width: 8),
              Icon(Icons.star_rounded, size: 14, color: colors.primary),
              const SizedBox(width: 3),
              Text(
                  bangumiItem.ratingScore > 0
                      ? bangumiItem.ratingScore.toStringAsFixed(1)
                      : '—',
                  style: theme.textTheme.labelMedium?.copyWith(
                      fontSize: 12,
                      height: 4 / 3,
                      fontWeight: FontWeight.w700)),
            ],
            if (isWatching) ...[
              const SizedBox(width: 6),
              Icon(Icons.bookmark_rounded, size: 16, color: colors.primary),
            ],
          ]),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.titleMedium?.copyWith(
            color: colors.onSurface,
            fontSize: _titleFontSize,
            fontWeight: FontWeight.w700,
            height: _titleLineHeight,
          ),
        ),
        if (supportingText.isNotEmpty) ...[
          const SizedBox(height: _metadataGap),
          Text(
            supportingText,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(
              color: colors.onSurfaceVariant,
              fontSize: _labelFontSize,
              height: _labelLineHeight,
            ),
          ),
        ],
        if (showRating || isWatching) ...[
          const Spacer(),
          const SizedBox(height: _footerGap),
          Row(
            children: [
              if (showRating)
                Expanded(
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: _buildRating(context),
                  ),
                )
              else
                const Spacer(),
              if (isWatching) ...[
                if (showRating) const SizedBox(width: 8),
                Tooltip(
                  message: '正在追',
                  child: Icon(Icons.bookmark_rounded,
                      size: 20, color: colors.primary),
                ),
              ],
            ],
          ),
        ],
      ],
    );
  }

  Widget _buildCover(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final imageUrl = TvMode.enabled
        ? NetworkImgLayer.tvListCoverUrl(bangumiItem.images, thumbnail: true)
        : bangumiItem.images['large'] ?? '';
    return ExcludeSemantics(
      child: SizedBox(
        width: TvMode.enabled
            ? 50
            : compact
                ? 80
                : 88,
        child: LayoutBuilder(
          builder: (context, constraints) => Hero(
            tag: bangumiItem.id,
            transitionOnUserGestures: true,
            child: ClipRRect(
              borderRadius: const BorderRadius.all(
                  Radius.circular(_cornerRadius - _contentPadding)),
              child: imageUrl.isEmpty
                  ? ColoredBox(
                      color: colors.surfaceContainerHighest,
                      child: Center(
                        child: Icon(Icons.movie_outlined,
                            color: colors.onSurfaceVariant),
                      ),
                    )
                  : NetworkImgLayer(
                      src: imageUrl,
                      width: constraints.maxWidth,
                      height: constraints.maxHeight,
                    ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildRating(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final labelStyle = theme.textTheme.labelMedium?.copyWith(
      fontSize: _labelFontSize,
      height: _labelLineHeight,
    );
    if (bangumiItem.ratingScore <= 0) {
      return Text('暂无评分',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: labelStyle?.copyWith(color: colors.onSurfaceVariant));
    }
    final score = bangumiItem.ratingScore.toStringAsFixed(1);
    return Semantics(
      label: '评分 $score',
      excludeSemantics: true,
      child: Container(
        padding: _ratingPadding,
        decoration: ShapeDecoration(
          color: colors.secondaryContainer,
          shape: const StadiumBorder(),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.star_rounded,
                size: _ratingIconSize, color: colors.onSecondaryContainer),
            const SizedBox(width: 4),
            Flexible(
              child: Text(score,
                  maxLines: 1,
                  style: labelStyle?.copyWith(
                    color: colors.onSecondaryContainer,
                    fontWeight: FontWeight.w700,
                  )),
            ),
          ],
        ),
      ),
    );
  }
}
