import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:antlr4/antlr4.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:kazumi/bean/widget/image_preview.dart';
import 'package:kazumi/services/platform/tv_mode.dart';
import 'package:url_launcher/url_launcher.dart';

import 'bbcode_base_listener.dart';
import 'bbcode_elements.dart';
import 'generated/BBCodeParser.dart';
import 'generated/BBCodeLexer.dart';

class BBCodeAction {
  const BBCodeAction({required this.label, required this.onSelected});

  final String label;
  final Future<void> Function() onSelected;
}

class BBCodeWidget extends StatefulWidget {
  const BBCodeWidget({
    super.key,
    required this.bbcode,
    this.textScaler = TextScaler.noScaling,
  });

  final String bbcode;
  final TextScaler textScaler;

  @override
  BBCodeWidgetState createState() => BBCodeWidgetState();
}

class BBCodeWidgetState extends State<BBCodeWidget> {
  bool _isVisible = false;
  List<dynamic> _elements = [];

  List<String> get _imageUrls =>
      _elements.whereType<BBCodeImg>().map((e) => e.imageUrl).toList();

  /// The same parsed fragments and reveal state used by pointer interaction.
  List<BBCodeAction> get tvActions {
    final actions = <BBCodeAction>[];
    final links = <String>{};
    for (final text in _elements.whereType<BBCodeText>()) {
      final link = text.link;
      if (link != null && (!text.masked || _isVisible) && links.add(link)) {
        actions.add(BBCodeAction(
          label: '打开链接 $link',
          onSelected: () async {
            await launchUrl(Uri.parse(link));
          },
        ));
      }
    }
    if (_elements.whereType<BBCodeText>().any((text) => text.masked)) {
      actions.add(BBCodeAction(
        label: _isVisible ? '隐藏遮罩' : '显示遮罩',
        onSelected: () async {
          if (mounted) setState(() => _isVisible = !_isVisible);
        },
      ));
    }
    final images = _imageUrls;
    for (var index = 0; index < images.length; index++) {
      final imageIndex = index;
      actions.add(BBCodeAction(
        label: '查看图片 ${index + 1}',
        onSelected: () async {
          if (!mounted) return;
          await ImageViewer.show(context,
              imageUrls: images,
              initialIndex: imageIndex,
              heroTag: ImageViewer.heroTagFor(images[imageIndex], imageIndex));
        },
      ));
    }
    return actions;
  }

  Color? _parseColor(String hex) {
    if (hex.startsWith('#')) {
      hex = hex.replaceFirst('#', '');
      if (hex.length == 6) {
        hex = "FF$hex";
      }
      if (hex.length == 8) {
        return Color(int.parse(hex, radix: 16));
      }
    }
    switch (hex) {
      case 'red':
        return Colors.red;
      case 'blue':
        return Colors.blue;
      case 'orange':
        return Colors.orange;
      case 'green':
        return Colors.green;
      case 'grey':
        return Colors.grey;
      default:
        return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    BBCodeParser.checkVersion();
    final input = InputStream.fromString(widget.bbcode);
    final lexer = BBCodeLexer(input);
    final tokens = CommonTokenStream(lexer);
    final parser = BBCodeParser(tokens);
    final tree = parser.document();
    final bbcodeBaseListener = BBCodeBaseListener();
    ParseTreeWalker.DEFAULT.walk(bbcodeBaseListener, tree);
    bbCodeTag.clear();
    _elements = bbcodeBaseListener.bbcode;

    final imageUrls = bbcodeBaseListener.bbcode
        .whereType<BBCodeImg>()
        .map((e) => e.imageUrl)
        .toList();
    var imageIndex = 0;

    return Wrap(
      children: [
        RichText(
          textScaler: widget.textScaler,
          text: TextSpan(
            style: DefaultTextStyle.of(context).style,
            children: bbcodeBaseListener.bbcode.map((e) {
              if (e is BBCodeText) {
                Color? textColor = (!_isVisible && e.masked)
                    ? Colors.transparent
                    : (e.link != null)
                        ? Colors.blue
                        : (e.quoted)
                            ? Theme.of(context).colorScheme.outline
                            : (e.color != null)
                                ? _parseColor(e.color!)
                                : null;
                return TextSpan(
                  text: e.text,
                  mouseCursor: (e.link != null || e.masked)
                      ? SystemMouseCursors.click
                      : SystemMouseCursors.text,
                  recognizer: TapGestureRecognizer()
                    ..onTap = (e.link != null || e.masked)
                        ? () {
                            if ((!e.masked || _isVisible) && e.link != null) {
                              launchUrl(Uri.parse(e.link!));
                            } else if (e.masked) {
                              setState(() {
                                _isVisible = !_isVisible;
                              });
                            }
                          }
                        : null,
                  style: TextStyle(
                    fontWeight: (e.bold) ? FontWeight.bold : null,
                    fontStyle: (e.italic) ? FontStyle.italic : null,
                    decoration: TextDecoration.combine([
                      if (e.underline || e.link != null)
                        TextDecoration.underline,
                      if (e.strikeThrough) TextDecoration.lineThrough,
                    ]),
                    decorationColor: textColor,
                    fontSize: e.size.toDouble(),
                    color: textColor,
                    backgroundColor:
                        (!_isVisible && e.masked) ? Color(0xFF555555) : null,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                );
              } else if (e is BBCodeImg) {
                final currentIndex = imageIndex++;
                final heroTag =
                    ImageViewer.heroTagFor(e.imageUrl, currentIndex);
                return WidgetSpan(
                  child: GestureDetector(
                    onTap: () => ImageViewer.show(
                      context,
                      imageUrls: imageUrls,
                      initialIndex: currentIndex,
                      heroTag: heroTag,
                    ),
                    child: Hero(
                      tag: heroTag,
                      child: CachedNetworkImage(
                        imageUrl: e.imageUrl,
                        placeholder: (context, url) => TvMode.enabled
                            ? const SizedBox(
                                width: 180,
                                height: 48,
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.image_outlined, size: 20),
                                    SizedBox(width: 8),
                                    Text('图片加载中',
                                        style: TextStyle(fontSize: 14)),
                                  ],
                                ),
                              )
                            : const SizedBox(width: 1, height: 1),
                        errorWidget: (context, error, stackTrace) {
                          return TvMode.enabled
                              ? const SizedBox(
                                  width: 180,
                                  height: 48,
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(Icons.broken_image_outlined,
                                          size: 20),
                                      SizedBox(width: 8),
                                      Text('图片无法显示',
                                          style: TextStyle(fontSize: 14)),
                                    ],
                                  ),
                                )
                              : const Text('.');
                        },
                      ),
                    ),
                  ),
                );
              } else if (e is BBCodeBgm) {
                String url;
                if (e.id == 11 || e.id == 23) {
                  url = 'https://bangumi.tv/img/smiles/bgm/${e.id}.gif';
                }
                if (e.id < 24) {
                  url = 'https://bangumi.tv/img/smiles/bgm/${e.id}.png';
                }
                if (e.id < 33) {
                  url = 'https://bangumi.tv/img/smiles/tv/0${e.id - 23}.gif';
                }
                url = 'https://bangumi.tv/img/smiles/tv/${e.id - 23}.gif';
                return WidgetSpan(
                  child: CachedNetworkImage(
                    imageUrl: url,
                    placeholder: (context, url) =>
                        const SizedBox(width: 1, height: 1),
                    errorWidget: (context, error, stackTrace) {
                      return const Text('.');
                    },
                  ),
                );
              } else if (e is BBCodeMusume) {
                return WidgetSpan(
                  child: CachedNetworkImage(
                    imageUrl:
                        'https://lain.bgm.tv/img/smiles/musume/musume_${e.id}.gif',
                    placeholder: (context, url) =>
                        const SizedBox(width: 1, height: 1),
                    errorWidget: (context, error, stackTrace) {
                      return const Text('.');
                    },
                    width: 50,
                    height: 50,
                  ),
                );
              } else if (e is BBCodeSticker) {
                return WidgetSpan(
                  child: CachedNetworkImage(
                    imageUrl: 'https://bangumi.tv/img/smiles/${e.id}.gif',
                    placeholder: (context, url) =>
                        const SizedBox(width: 1, height: 1),
                    errorWidget: (context, error, stackTrace) {
                      return const Text('.');
                    },
                  ),
                );
              } else {
                return WidgetSpan(
                  child: Icon(
                    (e as Icon).icon,
                    color: Theme.of(context).colorScheme.outline,
                  ),
                  alignment: PlaceholderAlignment.top,
                );
              }
            }).toList(),
          ),
        ),
      ],
    );
  }
}
