import 'package:flutter/material.dart';
import 'package:flutter_rating_bar/flutter_rating_bar.dart';
import 'package:kazumi/bean/widget/collect_button.dart';
import 'package:kazumi/utils/constants.dart';
import 'package:kazumi/modules/bangumi/bangumi_item.dart';
import 'package:kazumi/bean/card/network_img_layer.dart';
import 'package:kazumi/bean/widget/tv_visuals.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:skeletonizer/skeletonizer.dart';

// 视频卡片 - 水平布局
class BangumiInfoCardV extends StatefulWidget {
  static double tvHeaderHeight(BuildContext context) =>
      300 *
      (MediaQuery.textScalerOf(context).scale(16) / 16)
          .clamp(1.0, double.infinity);

  const BangumiInfoCardV({
    super.key,
    required this.bangumiItem,
    required this.isLoading,
    required this.showRating,
    this.tvActions,
    this.tvInitialCoverUrl,
  });

  final BangumiItem bangumiItem;
  final bool isLoading;
  final bool showRating;

  /// Supplied only by the TV detail page; mobile keeps its original layout.
  final Widget? tvActions;
  final String? tvInitialCoverUrl;

  @override
  State<BangumiInfoCardV> createState() => _BangumiInfoCardVState();
}

class _BangumiInfoCardVState extends State<BangumiInfoCardV> {
  int touchedIndex = -1;

  Widget get voteBarChart {
    return Flexible(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '  评分透视:',
          ),
          SizedBox(height: 16),
          if (widget.tvActions != null)
            Expanded(child: _barChart)
          else
            AspectRatio(aspectRatio: 2, child: _barChart),
        ],
      ),
    );
  }

  Widget get _barChart => BarChart(
        duration: Duration(milliseconds: 80),
        BarChartData(
          // alignment: BarChartAlignment.spaceEvenly,
          borderData: FlBorderData(show: false),
          gridData: FlGridData(show: false),
          barTouchData: BarTouchData(
            touchCallback: (FlTouchEvent event, barTouchResponse) {
              setState(() {
                if (!event.isInterestedForInteractions ||
                    barTouchResponse == null ||
                    barTouchResponse.spot == null) {
                  touchedIndex = -1;
                  return;
                }
                touchedIndex = barTouchResponse.spot!.touchedBarGroupIndex;
              });
            },
            touchTooltipData: BarTouchTooltipData(
              getTooltipColor: (_) =>
                  Theme.of(context).colorScheme.inverseSurface,
              getTooltipItem: (group, groupIndex, rod, rodIndex) {
                var percentage = widget.bangumiItem.votesCount[groupIndex] /
                    widget.bangumiItem.votes *
                    100;
                return BarTooltipItem(
                  '${percentage.toStringAsFixed(2)}% (${widget.bangumiItem.votesCount[groupIndex]}人)',
                  TextStyle(
                      color: Theme.of(context).colorScheme.onInverseSurface),
                );
              },
            ),
          ),
          barGroups: List<BarChartGroupData>.generate(
            10,
            (i) => BarChartGroupData(
              x: i + 1,
              barRods: [
                BarChartRodData(
                  toY: widget.bangumiItem.votesCount[i].toDouble(),
                  color: touchedIndex == i
                      ? Theme.of(context).colorScheme.primary
                      : Theme.of(context).disabledColor,
                  width: 20,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(5)),
                )
              ],
              // showingTooltipIndicators: [0],
            ),
          ),
          titlesData: FlTitlesData(
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 30,
                getTitlesWidget: (value, meta) => SideTitleWidget(
                  meta: meta,
                  space: 10,
                  child: Text(value.toInt().toString()),
                ),
              ),
            ),
            topTitles: const AxisTitles(),
            leftTitles: const AxisTitles(),
            rightTitles: const AxisTitles(),
          ),
        ),
      );

  Widget _buildTvHeader(BuildContext context) {
    final theme = Theme.of(context);
    final item = widget.bangumiItem;
    final facts = <String>[
      if (item.airDate.isNotEmpty) item.airDate,
      if (widget.showRating && item.ratingScore > 0)
        '评分 ${item.ratingScore.toStringAsFixed(1)}',
      if (widget.showRating && item.votes > 0) '${item.votes} 人评价',
      if (widget.showRating && item.rank > 0) '排名 #${item.rank}',
    ];
    return SizedBox(
      height: BangumiInfoCardV.tvHeaderHeight(context),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 158,
            height: 237,
            child: Hero(
              transitionOnUserGestures: true,
              flightShuttleBuilder: NetworkImgLayer.heroFlightShuttleBuilder,
              tag: item.id,
              child: NetworkImgLayer(
                src: NetworkImgLayer.tvDetailCoverUrl(item.images),
                width: 158,
                height: 237,
                placeholderSrc: widget.tvInitialCoverUrl,
                fadeInDuration: const Duration(milliseconds: 180),
                fadeOutDuration: const Duration(milliseconds: 180),
              ),
            ),
          ),
          const SizedBox(width: 24),
          Expanded(
            child: SingleChildScrollView(
              primary: false,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.nameCn.isEmpty ? item.name : item.nameCn,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.headlineSmall,
                  ),
                  if (facts.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(facts.join(' · '),
                        style: TvVisuals.caption.copyWith(color: TvVisuals.muted)),
                  ],
                  const SizedBox(height: 12),
                  // The same Dart playback/collection actions remain available
                  // while metadata loads. Native main uses compact facts, not
                  // the legacy full-size voting chart, beside its 158x237 cover.
                  widget.tvActions!,
                  if (widget.isLoading) ...[
                    const SizedBox(height: 8),
                    const Text('正在加载完整资料…', style: TvVisuals.caption),
                  ],
                  if (item.nameCn.isNotEmpty && item.name != item.nameCn) ...[
                    const SizedBox(height: 8),
                    Text(item.name,
                        style: TvVisuals.caption.copyWith(color: TvVisuals.muted)),
                  ],
                  const SizedBox(height: 12),
                  const Text('简介', style: TvVisuals.title),
                  const SizedBox(height: 8),
                  Text(
                    item.summary.isEmpty
                        ? (widget.isLoading ? '正在加载…' : '暂无简介')
                        : item.summary,
                    maxLines: 5,
                    overflow: TextOverflow.ellipsis,
                    style: TvVisuals.body,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.tvActions != null) {
      return ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 950),
        child: _buildTvHeader(context),
      );
    }
    return Container(
      height: 300,
      constraints: BoxConstraints(maxWidth: 950),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.bangumiItem.nameCn == ''
                ? widget.bangumiItem.name
                : (widget.bangumiItem.nameCn),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          SizedBox(height: 16),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Flexible(
                  child: AspectRatio(
                    aspectRatio: 0.65,
                    child: LayoutBuilder(builder: (context, boxConstraints) {
                      final double maxWidth = boxConstraints.maxWidth;
                      final double maxHeight = boxConstraints.maxHeight;
                      return Hero(
                        transitionOnUserGestures: true,
                        flightShuttleBuilder:
                            NetworkImgLayer.heroFlightShuttleBuilder,
                        tag: widget.bangumiItem.id,
                        child: NetworkImgLayer(
                          src: widget.bangumiItem.images['large'] ?? '',
                          width: maxWidth,
                          height: maxHeight,
                          fadeInDuration: const Duration(milliseconds: 0),
                          fadeOutDuration: const Duration(milliseconds: 0),
                        ),
                      );
                    }),
                  ),
                ),
                SizedBox(width: 16),
                Flexible(
                  child: Skeletonizer(
                    enabled: widget.isLoading,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '放送开始:',
                            ),
                            Text(
                              widget.bangumiItem.airDate == ''
                                  ? '2000-11-11' // Skeleton Loader 占位符
                                  : widget.bangumiItem.airDate,
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                color: Theme.of(context).colorScheme.primary,
                              ),
                            ),
                            SizedBox(height: 8),
                            Text(
                              widget.showRating
                                  ? '${widget.bangumiItem.votes} 人评分:'
                                  : '*** 人评分:',
                            ),
                            if (widget.isLoading)
                              // Skeleton Loader 占位符
                              Text(
                                '10.0 ********',
                                style: TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                  color: Theme.of(context).colorScheme.primary,
                                ),
                              ),
                            if (!widget.isLoading)
                              Row(
                                children: [
                                  Text(
                                    widget.showRating
                                        ? '${widget.bangumiItem.ratingScore}'
                                        : '***',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                      color:
                                          Theme.of(context).colorScheme.primary,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  RatingBarIndicator(
                                    itemCount: 5,
                                    rating: widget.showRating
                                        ? widget.bangumiItem.ratingScore
                                                .toDouble() /
                                            2
                                        : 0,
                                    itemBuilder: (context, index) => Icon(
                                      Icons.star_rounded,
                                      color:
                                          Theme.of(context).colorScheme.primary,
                                    ),
                                    itemSize: 20.0,
                                  ),
                                ],
                              ),
                            SizedBox(height: 8),
                            Text(
                              'Bangumi Ranked:',
                            ),
                            Text(
                              widget.showRating
                                  ? '#${widget.bangumiItem.rank}'
                                  : '***',
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                color: Theme.of(context).colorScheme.primary,
                              ),
                            ),
                          ],
                        ),
                        SizedBox(
                          width: 120,
                          height: 40,
                          child: CollectButton.extend(
                            bangumiItem: widget.bangumiItem,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                if (widget.showRating &&
                    MediaQuery.sizeOf(context).width >=
                        LayoutBreakpoint.compact['width']! &&
                    !widget.isLoading)
                  voteBarChart,
              ],
            ),
          ),
        ],
      ),
    );
  }
}
