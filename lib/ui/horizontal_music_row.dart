import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/brasa_theme.dart';
import '../theme/slush_theme.dart';

/// A bounded music shelf. Native pointer handling keeps vertical wheel events
/// with the surrounding page; Shift + wheel and trackpad x deltas move the row.
class HorizontalMusicRow extends StatefulWidget {
  const HorizontalMusicRow({
    super.key,
    required this.title,
    this.subtitle,
    required this.itemCount,
    required this.itemBuilder,
    required this.itemHeight,
    this.itemWidth = 200,
  });
  final String title;
  final String? subtitle;
  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;
  final double itemHeight;
  final double itemWidth;

  @override
  State<HorizontalMusicRow> createState() => _HorizontalMusicRowState();
}

class _HorizontalMusicRowState extends State<HorizontalMusicRow> {
  final _scroll = ScrollController();
  bool _overflow = false, _back = false, _next = false;
  double _w = 200;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_update);
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _update() {
    if (!mounted ||
        !_scroll.hasClients ||
        !_scroll.position.hasContentDimensions) {
      return;
    }
    final position = _scroll.position;
    final overflow = position.maxScrollExtent > 1;
    final back = position.pixels > position.minScrollExtent + 1;
    final next = position.pixels < position.maxScrollExtent - 1;
    if (overflow != _overflow || back != _back || next != _next) {
      setState(() {
        _overflow = overflow;
        _back = back;
        _next = next;
      });
    }
  }

  void _move(double target) {
    if (!_scroll.hasClients) return;
    final offset = target.clamp(
      _scroll.position.minScrollExtent,
      _scroll.position.maxScrollExtent,
    );
    if (MediaQuery.disableAnimationsOf(context)) {
      _scroll.jumpTo(offset);
    } else {
      _scroll.animateTo(
        offset,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    }
  }

  KeyEventResult _key(FocusNode node, KeyEvent event) {
    if (event is KeyUpEvent || !_scroll.hasClients) {
      return KeyEventResult.ignored;
    }
    switch (event.logicalKey) {
      case LogicalKeyboardKey.arrowLeft:
        _move(_scroll.offset - _w - 16);
      case LogicalKeyboardKey.arrowRight:
        _move(_scroll.offset + _w + 16);
      case LogicalKeyboardKey.home:
        _move(0);
      case LogicalKeyboardKey.end:
        _move(_scroll.position.maxScrollExtent);
      default:
        {
          return KeyEventResult.ignored;
        }
    }
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) => _update());
    final brasa = isBrasa(context);
    _w = brasa ? 180 : widget.itemWidth;
    final height = brasa
        ? 192 + MediaQuery.textScalerOf(context).scale(110)
        : widget.itemHeight;
    return Focus(
      onKeyEvent: _key,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (brasa)
            Row(
              children: [
                Expanded(
                  child: Text(
                    widget.title,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                if (_overflow)
                  TextButton(
                    onPressed: () => _move(_scroll.position.maxScrollExtent),
                    style: TextButton.styleFrom(foregroundColor: Brasa.cloud),
                    child: const Text('Mostrar todo'),
                  ),
              ],
            )
          else
            Text(
              widget.title,
              maxLines: isSlush(context) ? 2 : null,
              overflow: isSlush(context) ? TextOverflow.ellipsis : null,
              style: isSlush(context)
                  ? const TextStyle(
                      fontFamily: 'Bagel Fat One',
                      fontSize: 22,
                      height: 1.2,
                      color: Slush.ink,
                    )
                  : Theme.of(context).textTheme.titleLarge,
            ),
          if (widget.subtitle != null) ...[
            const SizedBox(height: 6),
            Text(
              widget.subtitle!,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
          if (_overflow)
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Desliza para ver más',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
                IconButton(
                  tooltip: 'Anterior en ${widget.title}',
                  onPressed: _back
                      ? () => _move(
                          _scroll.offset -
                              _scroll.position.viewportDimension * .8,
                        )
                      : null,
                  icon: const Icon(Icons.chevron_left),
                ),
                IconButton(
                  tooltip: 'Siguiente en ${widget.title}',
                  onPressed: _next
                      ? () => _move(
                          _scroll.offset +
                              _scroll.position.viewportDimension * .8,
                        )
                      : null,
                  icon: const Icon(Icons.chevron_right),
                ),
              ],
            ),
          const SizedBox(height: 12),
          NotificationListener<ScrollMetricsNotification>(
            onNotification: (_) {
              WidgetsBinding.instance.addPostFrameCallback((_) => _update());
              return false;
            },
            child: ScrollConfiguration(
              behavior: ScrollConfiguration.of(context).copyWith(
                scrollbars: false,
                dragDevices: {
                  ...ScrollConfiguration.of(context).dragDevices,
                  PointerDeviceKind.mouse,
                },
              ),
              child: Scrollbar(
                controller: _scroll,
                thumbVisibility: _overflow,
                interactive: true,
                child: SizedBox(
                  height: height + 16,
                  child: ListView.builder(
                    controller: _scroll,
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.only(bottom: 16),
                    itemCount: widget.itemCount,
                    itemExtent: _w + 16,
                    itemBuilder: (context, index) => Padding(
                      padding: const EdgeInsets.only(right: 16),
                      child: SizedBox(
                        width: _w,
                        child: widget.itemBuilder(context, index),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Tarjeta Brasa de carril: portada, título/subtítulo y botón play ámbar que
/// aparece al pasar el ratón (siempre visible en Android, sin hover). Los
/// retratos circulares (`round`) no llevan tarjeta ni sombra.
class BrasaTile extends StatefulWidget {
  const BrasaTile({
    super.key,
    required this.cover,
    required this.title,
    required this.tooltip,
    required this.onPlay,
    this.subtitle,
    this.caption,
    this.icon = Icons.play_arrow_rounded,
    this.round = false,
    this.playing = false,
  });
  final Widget cover;
  final String title, tooltip;
  final String? subtitle, caption;
  final IconData icon;
  final VoidCallback onPlay;
  final bool round, playing;

  @override
  State<BrasaTile> createState() => _BrasaTileState();
}

class _BrasaTileState extends State<BrasaTile> {
  final _hot = ValueNotifier(false);

  @override
  void dispose() {
    _hot.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final always = Theme.of(context).platform == TargetPlatform.android;
    final play = ValueListenableBuilder<bool>(
      valueListenable: _hot,
      builder: (_, hot, child) =>
          Opacity(opacity: hot || always ? 1 : 0, child: child),
      child: Tooltip(
        message: widget.tooltip,
        child: Material(
          color: Brasa.accent,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: widget.onPlay,
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Icon(widget.icon, size: 24, color: Colors.black),
            ),
          ),
        ),
      ),
    );
    final cover = Stack(
      children: [
        widget.cover,
        Positioned(right: 8, bottom: 8, child: play),
      ],
    );
    final texts = Column(
      crossAxisAlignment: widget.round
          ? CrossAxisAlignment.center
          : CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: 12),
        Text(
          widget.title,
          maxLines: 2,
          textAlign: widget.round ? TextAlign.center : TextAlign.start,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontFamily: 'Inter',
            fontSize: 16,
            height: 1.3,
            fontWeight: FontWeight.w400,
            color: widget.playing ? Brasa.accent : Brasa.cream,
          ),
        ),
        if (widget.subtitle != null) ...[
          const SizedBox(height: 4),
          Text(
            widget.subtitle!,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontFamily: 'Inter',
              fontSize: 14,
              height: 1.4,
              color: Brasa.cloud,
            ),
          ),
        ],
        if (widget.caption != null) ...[
          const SizedBox(height: 6),
          Text(
            widget.caption!,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontFamily: 'Inter',
              fontSize: 12,
              height: 1.33,
              color: Brasa.steel,
            ),
          ),
        ],
      ],
    );
    final radius = BorderRadius.circular(widget.round ? 90 : 6);
    return RepaintBoundary(
      child: MouseRegion(
        onEnter: (_) => _hot.value = true,
        onExit: (_) => _hot.value = false,
        child: Align(
          alignment: Alignment.topLeft,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: widget.round ? null : Brasa.obsidian,
              borderRadius: BorderRadius.circular(6),
              boxShadow: widget.round ? null : Brasa.cardShadow,
            ),
            child: Material(
              type: MaterialType.transparency,
              child: InkWell(
                borderRadius: widget.round ? BorderRadius.circular(6) : radius,
                onTap: widget.onPlay,
                child: Padding(
                  padding: EdgeInsets.all(widget.round ? 0 : 12),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [cover, texts],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
