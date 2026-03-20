import 'package:flutter/material.dart';

enum DragDropFeedbackType { card, list, kanban }

class DraggableCard<T extends Object> extends StatefulWidget {
  final T data;
  final Widget child;
  final Widget Function(BuildContext, T, DraggableDetails)? onDragStarted;
  final void Function(T)? onDragEnd;
  final void Function(T)? onDragCompleted;
  final void Function(T)? onDraggableCanceled;
  final bool isEnabled;

  const DraggableCard({
    super.key,
    required this.data,
    required this.child,
    this.onDragStarted,
    this.onDragEnd,
    this.onDragCompleted,
    this.onDraggableCanceled,
    this.isEnabled = true,
  });

  @override
  State<DraggableCard<T>> createState() => _DraggableCardState<T>();
}

class _DraggableCardState<T extends Object> extends State<DraggableCard<T>> {
  bool _isDragging = false;

  @override
  Widget build(BuildContext context) {
    if (!widget.isEnabled) {
      return widget.child;
    }

    return LongPressDraggable<T>(
      data: widget.data,
      delay: const Duration(milliseconds: 150),
      feedback: Material(
        elevation: 8,
        borderRadius: BorderRadius.circular(12),
        child: SizedBox(
          width: MediaQuery.of(context).size.width * 0.8,
          child: Opacity(
            opacity: 0.9,
            child: widget.child,
          ),
        ),
      ),
      childWhenDragging: Opacity(
        opacity: 0.3,
        child: widget.child,
      ),
      onDragStarted: () {
        setState(() => _isDragging = true);
      },
      onDragEnd: (details) {
        setState(() => _isDragging = false);
        widget.onDragEnd?.call(widget.data);
      },
      onDragCompleted: () {
        widget.onDragCompleted?.call(widget.data);
      },
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 200),
        opacity: _isDragging ? 0.5 : 1.0,
        child: widget.child,
      ),
    );
  }
}

class DropZone<T extends Object> extends StatefulWidget {
  final Widget Function(BuildContext, bool isHovering) builder;
  final void Function(T)? onAccept;
  final bool Function(T?)? onWillAccept;
  final List<T> acceptedTypes;
  final bool showHighlight;

  const DropZone({
    super.key,
    required this.builder,
    required this.onAccept,
    this.onWillAccept,
    this.acceptedTypes = const [],
    this.showHighlight = true,
  });

  @override
  State<DropZone<T>> createState() => _DropZoneState<T>();
}

class _DropZoneState<T extends Object> extends State<DropZone<T>> {
  bool _isHovering = false;

  @override
  Widget build(BuildContext context) {
    return DragTarget<T>(
      onWillAcceptWithDetails: (details) {
        final willAccept = widget.onWillAccept?.call(details.data) ?? true;
        if (willAccept && !_isHovering) {
          setState(() => _isHovering = true);
        }
        return willAccept;
      },
      onAcceptWithDetails: (details) {
        setState(() => _isHovering = false);
        widget.onAccept?.call(details.data);
      },
      onLeave: (data) {
        setState(() => _isHovering = false);
      },
      builder: (context, candidateData, rejectedData) {
        return AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          decoration: BoxDecoration(
            border: widget.showHighlight && _isHovering
                ? Border.all(
                    color: Theme.of(context).colorScheme.primary,
                    width: 2,
                  )
                : null,
            borderRadius: BorderRadius.circular(12),
          ),
          child: widget.builder(context, _isHovering),
        );
      },
    );
  }
}

class KanbanColumn<T extends Object> extends StatelessWidget {
  final String title;
  final List<T> items;
  final Widget Function(T) itemBuilder;
  final void Function(T)? onItemDropped;
  final Color? backgroundColor;
  final bool isDropTarget;

  const KanbanColumn({
    super.key,
    required this.title,
    required this.items,
    required this.itemBuilder,
    this.onItemDropped,
    this.backgroundColor,
    this.isDropTarget = true,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    Widget content = Container(
      decoration: BoxDecoration(
        color: backgroundColor ?? theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Text(
                  title,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '${items.length}',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onPrimaryContainer,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
              itemCount: items.length,
              itemBuilder: (context, index) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: itemBuilder(items[index]),
                );
              },
            ),
          ),
        ],
      ),
    );

    if (isDropTarget) {
      return DropZone<T>(
        onAccept: onItemDropped,
        builder: (context, isHovering) {
          return AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            decoration: BoxDecoration(
              color: isHovering
                  ? theme.colorScheme.primary.withValues(alpha: 0.1)
                  : null,
              borderRadius: BorderRadius.circular(12),
            ),
            child: content,
          );
        },
      );
    }

    return content;
  }
}
