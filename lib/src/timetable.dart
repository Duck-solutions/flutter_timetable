import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../flutter_timetable.dart';

class Timetable<T> extends StatefulWidget {
  final TimetableController? controller;
  final Widget Function(DateTime)? cellBuilder;
  final Widget Function(DateTime)? headerCellBuilder;
  final List<TimetableItem<T>> items;
  final Widget Function(TimetableItem<T>)? itemBuilder;
  final Widget Function(TimeOfDay time)? hourLabelBuilder;
  final Widget Function(DateTime current)? cornerBuilder;
  final bool snapToDay;
  final Color? nowIndicatorColor;

  const Timetable({
    Key? key,
    this.controller,
    this.cellBuilder,
    this.headerCellBuilder,
    this.items = const [],
    this.itemBuilder,
    this.hourLabelBuilder,
    this.nowIndicatorColor,
    this.cornerBuilder,
    this.snapToDay = true,
  }) : super(key: key);

  @override
  State<Timetable<T>> createState() => _TimetableState<T>();
}

class _TimetableState<T> extends State<Timetable<T>> {
  final _dayScrollController = ScrollController();
  final _dayHeadingScrollController = ScrollController();
  final _timeScrollController = ScrollController();
  double columnWidth = 50.0;
  TimetableController controller = TimetableController();
  final _key = GlobalKey();
  get nowIndicatorColor => widget.nowIndicatorColor ?? Theme.of(context).indicatorColor;

  @override
  void initState() {
    controller = widget.controller ?? controller;
    controller.addListener(_eventHandler);
    if (widget.items.isNotEmpty) {
      widget.items.sort((a, b) => a.start.compareTo(b.start));
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => adjustColumnWidth());

    super.initState();
  }

  _eventHandler(TimetableControllerEvent event) async {
    if (event is TimetableJumpTo) {
      _jumpTo(event.date);
    }

    if (event is TimetableColumnsChanged) {
      final previous = controller.visibleDateStart;
      final now = DateTime.now();
      await adjustColumnWidth();
      return _jumpTo(DateTime(previous.year, previous.month, previous.day, now.hour, now.minute));
    }

    if (mounted) setState(() {});
  }

  Future adjustColumnWidth() async {
    final box = _key.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return;
    if (box.hasSize) {
      final size = box.size;
      final layoutWidth = size.width;
      final width = (layoutWidth - controller.timelineWidth) / controller.columns;
      if (width != columnWidth) {
        columnWidth = width;
        await Future.microtask(() => null);
        setState(() {});
      }
    }
  }

  bool _isTableScrolling = false;
  bool _isHeaderScrolling = false;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
      key: _key,
      builder: (context, contraints) {
        return Column(
          children: [
            SizedBox(
              height: controller.headerHeight,
              child: Row(
                children: [
                  SizedBox(
                    width: controller.timelineWidth,
                    height: controller.headerHeight,
                    child: _buildCorner(),
                  ),
                  Expanded(
                    child: NotificationListener<ScrollNotification>(
                      onNotification: (notification) {
                        if (_isTableScrolling) return false;
                        if (notification is ScrollEndNotification) {
                          _snapToCloset();
                          _updateVisibleDate();
                          _isHeaderScrolling = false;
                          return true;
                        }
                        _isHeaderScrolling = true;
                        _dayScrollController.jumpTo(_dayHeadingScrollController.position.pixels);
                        return false;
                      },
                      child: ListView.builder(
                        scrollDirection: Axis.horizontal,
                        controller: _dayHeadingScrollController,
                        itemExtent: columnWidth,
                        itemBuilder: (context, i) => SizedBox(
                          width: columnWidth,
                          child: _buildHeaderCell(i),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: NotificationListener<ScrollNotification>(
                onNotification: (notification) {
                  if (_isHeaderScrolling) return false;

                  if (notification is ScrollEndNotification) {
                    _snapToCloset();
                    _updateVisibleDate();
                    _isTableScrolling = false;
                    return true;
                  }
                  _isTableScrolling = true;
                  _dayHeadingScrollController.jumpTo(_dayScrollController.position.pixels);
                  return true;
                },
                child: SingleChildScrollView(
                  controller: _timeScrollController,
                  child: SizedBox(
                    height: controller.cellHeight * 24.0,
                    child: Row(
                      children: [
                        SizedBox(
                          width: controller.timelineWidth,
                          height: controller.cellHeight * 24.0,
                          child: Column(
                            children: [
                              SizedBox(height: controller.cellHeight / 2),
                              for (var i = 1; i < 24; i++) //
                                SizedBox(
                                  height: controller.cellHeight,
                                  child: Center(child: _buildHour(TimeOfDay(hour: i, minute: 0))),
                                ),
                            ],
                          ),
                        ),
                        Expanded(
                          child: ListView.builder(
                            scrollDirection: Axis.horizontal,
                            // cacheExtent: 10000.0,
                            itemExtent: columnWidth,
                            controller: _dayScrollController,
                            itemBuilder: (context, index) {
                              final date = controller.start.add(Duration(days: index));
                              final events = widget.items.where((event) => DateUtils.isSameDay(date, event.start)).toList();
                              final now = DateTime.now();
                              final isToday = DateUtils.isSameDay(date, now);
                              return Container(
                                clipBehavior: Clip.none,
                                width: columnWidth,
                                height: controller.cellHeight * 24.0,
                                child: Stack(
                                  clipBehavior: Clip.none,
                                  children: [
                                    Column(
                                      children: [
                                        for (int i = 0; i < 24; i++)
                                          SizedBox(
                                            width: columnWidth,
                                            height: controller.cellHeight,
                                            child: Center(
                                              child: _buildCell(DateUtils.dateOnly(date).add(Duration(hours: i))),
                                            ),
                                          ),
                                      ],
                                    ),
                                    for (final TimetableItem<T> event in events)
                                      Positioned(
                                        top: (event.start.hour + (event.start.minute / 60)) * controller.cellHeight,
                                        width: columnWidth,
                                        height: event.duration.inMinutes * controller.cellHeight / 60,
                                        child: _buildEvent(event),
                                      ),
                                    if (isToday)
                                      Positioned(
                                        top: ((now.hour + (now.minute / 60.0)) * controller.cellHeight) - 1,
                                        width: columnWidth,
                                        child: Stack(
                                          clipBehavior: Clip.none,
                                          children: [
                                            Container(
                                              clipBehavior: Clip.none,
                                              color: nowIndicatorColor,
                                              height: 2,
                                              width: columnWidth + 1,
                                            ),
                                            Positioned(
                                              top: -2,
                                              left: -2,
                                              child: Container(
                                                decoration: BoxDecoration(
                                                  shape: BoxShape.circle,
                                                  color: nowIndicatorColor,
                                                ),
                                                height: 6,
                                                width: 6,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                  ],
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      });

  final _dateFormatter = DateFormat('MMM\nd');

  Widget _buildHeaderCell(int i) {
    final date = controller.start.add(Duration(days: i));
    if (widget.headerCellBuilder != null) return widget.headerCellBuilder!(date);
    final weight = DateUtils.isSameDay(date, DateTime.now()) ? FontWeight.bold : FontWeight.normal;
    return Center(
      child: Text(
        _dateFormatter.format(date),
        style: TextStyle(fontSize: 12, fontWeight: weight),
        textAlign: TextAlign.center,
      ),
    );
  }

  Widget _buildCell(DateTime date) {
    if (widget.cellBuilder != null) return widget.cellBuilder!(date);

    return Container(
      decoration: BoxDecoration(
        border: Border.all(
          color: Theme.of(context).dividerColor,
          width: 0.5,
        ),
      ),
    );
  }

  Widget _buildHour(TimeOfDay time) {
    if (widget.hourLabelBuilder != null) return widget.hourLabelBuilder!(time);
    return Text(time.format(context), style: const TextStyle(fontSize: 11));
  }

  Widget _buildCorner() {
    if (widget.cornerBuilder != null) return widget.cornerBuilder!(controller.visibleDateStart);
    return Center(
      child: Text(
        "${controller.visibleDateStart.year}",
        textAlign: TextAlign.center,
      ),
    );
  }

  final _timeFormatter = DateFormat("h:mm a");
  Widget _buildEvent(TimetableItem<T> event) {
    if (widget.itemBuilder != null) return widget.itemBuilder!(event);
    return Container(
      padding: const EdgeInsets.all(5),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: Theme.of(context).dividerColor,
          width: 0.5,
        ),
      ),
      child: Text(
        "${_timeFormatter.format(event.start)} - ${_timeFormatter.format(event.end)}",
        style: TextStyle(
          fontSize: 10,
          color: Theme.of(context).colorScheme.onSurface,
        ),
      ),
    );
  }

  bool _isSnapping = false;
  final _animationDuration = const Duration(milliseconds: 300);
  final _animationCurve = Curves.bounceOut;
  Future _snapToCloset() async {
    if (_isSnapping || !widget.snapToDay) return;
    _isSnapping = true;
    await Future.microtask(() => null);
    final snapPosition = ((_dayScrollController.offset) / columnWidth).round() * columnWidth;
    _dayScrollController.animateTo(snapPosition, duration: _animationDuration, curve: _animationCurve);
    _dayHeadingScrollController.animateTo(snapPosition, duration: _animationDuration, curve: _animationCurve);
    _isSnapping = false;
  }

  _updateVisibleDate() async {
    final date = controller.start.add(Duration(days: _dayHeadingScrollController.position.pixels ~/ columnWidth));
    if (date != controller.visibleDateStart) {
      controller.updateVisibleDate(date);
      setState(() {});
    }
  }

  Future _jumpTo(DateTime date) async {
    final datePosition = (date.difference(controller.start).inDays) * columnWidth;
    final hourPosition = ((date.hour) * controller.cellHeight) - (controller.cellHeight / 2);
    await Future.wait([
      _dayScrollController.animateTo(datePosition, duration: _animationDuration, curve: _animationCurve),
      _timeScrollController.animateTo(hourPosition, duration: _animationDuration, curve: _animationCurve),
    ]);
  }
}
