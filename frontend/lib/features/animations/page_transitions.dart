import 'package:flutter/material.dart';
import 'package:animations/animations.dart';

class FadeThroughTransition extends StatelessWidget {
  final Widget child;
  final Animation<double> animation;
  final Animation<double>? secondaryAnimation;

  const FadeThroughTransition({
    super.key,
    required this.child,
    required this.animation,
    this.secondaryAnimation,
  });

  @override
  Widget build(BuildContext context) {
    return FadeThroughTransition(
      animation: animation,
      secondaryAnimation: secondaryAnimation ?? const AlwaysStoppedAnimation(0.0),
      child: child,
    );
  }
}

class SharedAxisTransition extends StatelessWidget {
  final Widget child;
  final Animation<double> animation;
  final Animation<double>? secondaryAnimation;
  final SharedAxisTransitionType transitionType;

  const SharedAxisTransition({
    super.key,
    required this.child,
    required this.animation,
    this.secondaryAnimation,
    this.transitionType = SharedAxisTransitionType.horizontal,
  });

  @override
  Widget build(BuildContext context) {
    return SharedAxisTransition(
      animation: animation,
      secondaryAnimation: secondaryAnimation ?? const AlwaysStoppedAnimation(0.0),
      transitionType: transitionType,
      child: child,
    );
  }
}

class FadeThroughPageRoute<T> extends PageRoute<T> {
  final WidgetBuilder builder;

  FadeThroughPageRoute({required this.builder});

  @override
  Color? get barrierColor => null;

  @override
  String? get barrierLabel => null;

  @override
  bool get maintainState => true;

  @override
  Duration get transitionDuration => const Duration(milliseconds: 300);

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) {
    return builder(context);
  }

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    return FadeThroughTransition(
      animation: animation,
      secondaryAnimation: secondaryAnimation,
      child: child,
    );
  }
}

class SharedAxisPageRoute<T> extends PageRoute<T> {
  final WidgetBuilder builder;
  final SharedAxisTransitionType transitionType;

  SharedAxisPageRoute({
    required this.builder,
    this.transitionType = SharedAxisTransitionType.horizontal,
  });

  @override
  Color? get barrierColor => null;

  @override
  String? get barrierLabel => null;

  @override
  bool get maintainState => true;

  @override
  Duration get transitionDuration => const Duration(milliseconds: 400);

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) {
    return builder(context);
  }

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    return SharedAxisTransition(
      animation: animation,
      secondaryAnimation: secondaryAnimation,
      transitionType: transitionType,
      child: child,
    );
  }
}

class SlideUpPageRoute<T> extends PageRoute<T> {
  final WidgetBuilder builder;

  SlideUpPageRoute({required this.builder});

  @override
  Color? get barrierColor => null;

  @override
  String? get barrierLabel => null;

  @override
  bool get maintainState => true;

  @override
  Duration get transitionDuration => const Duration(milliseconds: 350);

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) {
    return builder(context);
  }

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    const begin = Offset(0.0, 1.0);
    const end = Offset.zero;
    const curve = Curves.easeOutCubic;

    var tween = Tween(begin: begin, end: end).chain(CurveTween(curve: curve));
    var offsetAnimation = animation.drive(tween);

    return SlideTransition(
      position: offsetAnimation,
      child: child,
    );
  }
}
