import 'package:flutter/material.dart';
import 'package:kazumi/bbcode/bbcode_widget.dart';
import 'package:kazumi/bean/dialog/dialog_helper.dart';
import 'package:kazumi/bean/widget/bangumi_avatar.dart';
import 'package:kazumi/bean/widget/tv_comment_reading_surface.dart';
import 'package:kazumi/modules/comments/comment_item.dart';
import 'package:kazumi/services/platform/tv_mode.dart';
import 'package:kazumi/utils/date_time.dart';
import 'package:skeletonizer/skeletonizer.dart';

class UserCommentsCard extends StatefulWidget {
  UserCommentsCard.episode(EpisodeCommentItem item, {super.key})
      : _source = item,
        _comment = _fromEpisode(item.comment),
        _replies = item.replies.map(_fromEpisode).toList();

  UserCommentsCard.character(CharacterCommentItem item, {super.key})
      : _source = item,
        _comment = _fromCharacter(item.comment),
        _replies = item.replies.map(_fromCharacter).toList();

  final Object _source;
  final _CommentData _comment;
  final List<_CommentData> _replies;

  @override
  State<UserCommentsCard> createState() => _UserCommentsCardState();
}

class _UserCommentsCardState extends State<UserCommentsCard> {
  static const _previewCount = 2;
  bool _expanded = false;
  bool _menuOpen = false;
  late List<GlobalKey<BBCodeWidgetState>> _bodyKeys;

  @override
  void initState() {
    super.initState();
    _resetBodyKeys();
  }

  void _resetBodyKeys() {
    _bodyKeys = List.generate(widget._replies.length + 1,
        (_) => GlobalKey<BBCodeWidgetState>());
  }

  @override
  void didUpdateWidget(covariant UserCommentsCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget._source != widget._source) {
      _expanded = false;
      _resetBodyKeys();
    }
  }

  Future<void> _showActions() async {
    if (_menuOpen) return;
    final actions = <BBCodeAction>[
      for (var index = 0; index < _bodyKeys.length; index++)
        for (final action in _bodyKeys[index].currentState?.tvActions ??
            const <BBCodeAction>[])
          if (index == 0)
            action
          else
            BBCodeAction(
                label: '回复 $index · ${action.label}',
                onSelected: action.onSelected),
      if (widget._replies.length > _previewCount)
        BBCodeAction(
          label: _expanded ? '收起回复' : '展开其余回复',
          onSelected: () async => setState(() => _expanded = !_expanded),
        ),
    ];
    if (actions.isEmpty) return;
    _menuOpen = true;
    final origin = FocusManager.instance.primaryFocus;
    final source = widget._source;
    try {
      final selected = await KazumiDialog.show<int>(
        context: context,
        builder: (dialogContext) => SimpleDialog(
          title: const Text('评论操作'),
          children: [
            for (var index = 0; index < actions.length; index++)
              TextButton(
                autofocus: index == 0,
                style: TextButton.styleFrom(alignment: Alignment.centerLeft),
                onPressed: () => KazumiDialog.dismiss(
                    context: dialogContext, popWith: index),
                child: Text(actions[index].label),
              ),
          ],
        ),
      );
      if (!mounted || widget._source != source || selected == null) return;
      await actions[selected].onSelected();
    } finally {
      _menuOpen = false;
      if (mounted &&
          widget._source == source &&
          ModalRoute.of(context)?.isCurrent == true &&
          origin?.context != null &&
          origin!.canRequestFocus) {
        origin.requestFocus();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final type = Theme.of(context).textTheme;
    final replies = widget._replies;
    final visibleCount = _expanded || replies.length <= _previewCount
        ? replies.length
        : _previewCount;
    final disableAnimations = MediaQuery.disableAnimationsOf(context);

    final card = _CommentSurface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _CommentAuthor(comment: widget._comment),
          const SizedBox(height: 16),
          _CommentBody(
              content: widget._comment.content, bodyKey: _bodyKeys[0]),
          if (replies.isNotEmpty) ...[
            const SizedBox(height: 20),
            Padding(
              padding: const EdgeInsets.only(left: 4, bottom: 10),
              child: Row(
                children: [
                  Icon(Icons.forum_outlined, size: 16, color: colors.primary),
                  const SizedBox(width: 8),
                  Text('${replies.length} 条回复',
                      style: type.labelLarge?.copyWith(color: colors.primary)),
                ],
              ),
            ),
            AnimatedSize(
              duration: disableAnimations
                  ? Duration.zero
                  : const Duration(milliseconds: 300),
              curve: Curves.easeInOutCubicEmphasized,
              alignment: Alignment.topCenter,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var index = 0; index < visibleCount; index++)
                    Padding(
                      padding: EdgeInsets.only(top: index == 0 ? 0 : 3),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: colors.surfaceContainerHighest,
                          borderRadius: BorderRadius.vertical(
                            top: Radius.circular(index == 0 ? 16 : 4),
                            bottom: Radius.circular(
                                index == visibleCount - 1 ? 16 : 4),
                          ),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _CommentAuthor(
                                comment: replies[index],
                                compact: true,
                              ),
                              const SizedBox(height: 10),
                              _CommentBody(
                                  content: replies[index].content,
                                  bodyKey: _bodyKeys[index + 1]),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            if (replies.length > _previewCount) ...[
              const SizedBox(height: 8),
              Semantics(
                expanded: _expanded,
                child: SizedBox(
                  width: double.infinity,
                  // TV uses the card's action menu as its single action target.
                  // Keep the footer's space while showing reading state here.
                  child: TvMode.enabled
                      ? Container(
                          constraints: const BoxConstraints(minHeight: 48),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: colors.secondaryContainer,
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Text('已显示 $visibleCount / ${replies.length} 条回复',
                              textAlign: TextAlign.center,
                              style: type.labelLarge?.copyWith(
                                  color: colors.onSecondaryContainer)),
                        )
                      : TextButton.icon(
                          onPressed: () =>
                              setState(() => _expanded = !_expanded),
                          style: TextButton.styleFrom(
                            minimumSize: const Size(48, 48),
                            backgroundColor: colors.secondaryContainer,
                            foregroundColor: colors.onSecondaryContainer,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                          icon: AnimatedRotation(
                            turns: _expanded ? .5 : 0,
                            duration: disableAnimations
                                ? Duration.zero
                                : const Duration(milliseconds: 200),
                            child:
                                const Icon(Icons.expand_more_rounded, size: 20),
                          ),
                          label: Text(_expanded
                              ? '收起回复'
                              : '展开其余 ${replies.length - _previewCount} 条回复'),
                        ),
                ),
              ),
            ],
          ],
        ],
      ),
    );
    return TvCommentReadingSurface(onPressed: _showActions, child: card);
  }
}

class _CommentAuthor extends StatelessWidget {
  const _CommentAuthor({required this.comment, this.compact = false});

  final _CommentData comment;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        ExcludeSemantics(
          child: BangumiAvatar(
            radius: compact ? 16 : 22,
            imageUrl: comment.user.avatar.large,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                comment.user.nickname.isNotEmpty
                    ? comment.user.nickname
                    : comment.user.username,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleSmall?.copyWith(
                  color: theme.colorScheme.onSurface,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                dateFormat(comment.createdAt),
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _CommentBody extends StatelessWidget {
  const _CommentBody({required this.content, this.bodyKey});

  final String content;
  final GlobalKey<BBCodeWidgetState>? bodyKey;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DefaultTextStyle.merge(
      style: theme.textTheme.bodyMedium?.copyWith(
        color: theme.colorScheme.onSurface,
        height: 1.65,
      ),
      child: content.isEmpty
          ? Text('该评论已被删除',
              style: TextStyle(color: theme.colorScheme.onSurfaceVariant))
          : BBCodeWidget(
              key: TvMode.enabled ? bodyKey : null,
              bbcode: content,
              textScaler: MediaQuery.textScalerOf(context),
            ),
    );
  }
}

class UserCommentsCardBone extends StatelessWidget {
  const UserCommentsCardBone({super.key});

  @override
  Widget build(BuildContext context) {
    return const _CommentSurface(
      child: Skeletonizer.zone(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Bone.circle(size: 44),
              SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Bone.text(width: 96),
                  SizedBox(height: 2),
                  Bone.text(width: 64, fontSize: 11),
                ],
              ),
            ]),
            SizedBox(height: 16),
            Bone.multiText(lines: 2),
          ],
        ),
      ),
    );
  }
}

class _CommentSurface extends StatelessWidget {
  const _CommentSurface({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(24),
        clipBehavior: Clip.antiAlias,
        child: Padding(padding: const EdgeInsets.all(16), child: child),
      ),
    );
  }
}

typedef _CommentData = ({User user, String content, int createdAt});

_CommentData _fromEpisode(EpisodeComment comment) => (
      user: comment.user,
      content: comment.comment,
      createdAt: comment.createdAt,
    );

_CommentData _fromCharacter(CharacterComment comment) => (
      user: comment.user,
      content: comment.comment,
      createdAt: comment.createdAt,
    );
