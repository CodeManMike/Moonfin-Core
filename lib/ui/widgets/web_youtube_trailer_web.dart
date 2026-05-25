import 'dart:ui_web' as ui_web;

import 'package:flutter/widgets.dart';
import 'package:web/web.dart' as web;

import '../../data/services/youtube_stream_resolver.dart';

class WebYouTubeTrailer extends StatefulWidget {
  final String videoId;
  final bool muted;
  final bool showControls;
  final bool loop;
  final bool ignorePointer;
  final VoidCallback? onPlaybackStarted;
  final VoidCallback? onAutoplayFailed;
  final VoidCallback? onEmbeddedUnavailable;
  final Duration autoplayTimeout;

  const WebYouTubeTrailer({
    super.key,
    required this.videoId,
    this.muted = true,
    this.showControls = false,
    this.loop = true,
    this.ignorePointer = false,
    this.onPlaybackStarted,
    this.onAutoplayFailed,
    this.onEmbeddedUnavailable,
    this.autoplayTimeout = const Duration(seconds: 3),
  });

  @override
  State<WebYouTubeTrailer> createState() => _WebYouTubeTrailerState();
}

class _WebYouTubeTrailerState extends State<WebYouTubeTrailer> {
  static final Set<String> _registeredViewTypes = <String>{};

  late final String _viewType;

  @override
  void initState() {
    super.initState();
    _viewType =
        'moonfin-yt-trailer-${widget.videoId}-${widget.muted ? 'm' : 'u'}-${widget.showControls ? 'c1' : 'c0'}-${widget.loop ? 'l1' : 'l0'}-${widget.ignorePointer ? 'p0' : 'p1'}';
    if (_registeredViewTypes.add(_viewType)) {
      ui_web.platformViewRegistry.registerViewFactory(
        _viewType,
        (int _) => _buildIframe(),
      );
    }
  }

  web.HTMLIFrameElement _buildIframe() {
    final src = YouTubeStreamResolver.buildEmbedUrl(
      widget.videoId,
      muted: widget.muted,
      showControls: widget.showControls,
      loop: widget.loop,
    );

    final iframe = web.HTMLIFrameElement()
      ..src = src
      ..allow = 'autoplay; encrypted-media; picture-in-picture'
      ..style.border = '0'
      ..style.width = '100%'
      ..style.height = '100%'
      ..style.pointerEvents = widget.ignorePointer ? 'none' : 'auto';
    iframe.setAttribute('frameborder', '0');
    iframe.setAttribute('allowfullscreen', 'true');
    return iframe;
  }

  @override
  Widget build(BuildContext context) {
    return HtmlElementView(viewType: _viewType);
  }
}
