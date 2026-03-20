import 'package:flutter/material.dart';

class SearchOverlay extends StatefulWidget {
  final Widget child;
  final void Function(String)? onSearch;
  final VoidCallback? onClose;

  const SearchOverlay({
    super.key,
    required this.child,
    this.onSearch,
    this.onClose,
  });

  @override
  State<SearchOverlay> createState() => _SearchOverlayState();
}

class _SearchOverlayState extends State<SearchOverlay>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  bool _isExpanded = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _animation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    _searchController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _toggleSearch() {
    setState(() {
      _isExpanded = !_isExpanded;
      if (_isExpanded) {
        _controller.forward();
        _focusNode.requestFocus();
      } else {
        _controller.reverse();
        _searchController.clear();
      }
    });
  }

  void _submitSearch() {
    final query = _searchController.text.trim();
    if (query.isNotEmpty) {
      widget.onSearch?.call(query);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Stack(
      children: [
        widget.child,
        Positioned(
          top: 0,
          right: 0,
          child: SafeArea(
            child: AnimatedBuilder(
              animation: _animation,
              builder: (context, child) {
                return Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_isExpanded)
                      SizeTransition(
                        sizeFactor: _animation,
                        axis: Axis.horizontal,
                        child: Container(
                          width: 280,
                          margin: const EdgeInsets.only(right: 8),
                          child: TextField(
                            controller: _searchController,
                            focusNode: _focusNode,
                            decoration: InputDecoration(
                              hintText: 'Search work orders...',
                              filled: true,
                              fillColor: theme.colorScheme.surfaceContainerHighest,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(28),
                                borderSide: BorderSide.none,
                              ),
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 20,
                                vertical: 12,
                              ),
                              prefixIcon: Icon(
                                Icons.search,
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                              suffixIcon: IconButton(
                                icon: const Icon(Icons.close, size: 20),
                                onPressed: _toggleSearch,
                              ),
                            ),
                            onSubmitted: (_) => _submitSearch(),
                            textInputAction: TextInputAction.search,
                          ),
                        ),
                      ),
                    FloatingBubble(
                      isExpanded: _isExpanded,
                      onTap: _toggleSearch,
                      icon: Icons.search,
                      backgroundColor: theme.colorScheme.primaryContainer,
                      iconColor: theme.colorScheme.onPrimaryContainer,
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}

class FloatingBubble extends StatefulWidget {
  final VoidCallback onTap;
  final IconData icon;
  final Color backgroundColor;
  final Color iconColor;
  final bool isExpanded;

  const FloatingBubble({
    super.key,
    required this.onTap,
    required this.icon,
    this.backgroundColor = Colors.blue,
    this.iconColor = Colors.white,
    this.isExpanded = false,
  });

  @override
  State<FloatingBubble> createState() => _FloatingBubbleState();
}

class _FloatingBubbleState extends State<FloatingBubble>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _rotationAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    );
    _rotationAnimation = Tween<double>(
      begin: 0,
      end: 0.125,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.easeInOut,
    ));
  }

  @override
  void didUpdateWidget(FloatingBubble oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isExpanded != oldWidget.isExpanded) {
      if (widget.isExpanded) {
        _controller.forward();
      } else {
        _controller.reverse();
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RotationTransition(
      turns: _rotationAnimation,
      child: FloatingActionButton.small(
        onPressed: widget.onTap,
        backgroundColor: widget.backgroundColor,
        elevation: 4,
        child: Icon(
          widget.icon,
          color: widget.iconColor,
        ),
      ),
    );
  }
}
