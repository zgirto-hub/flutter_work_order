import 'package:flutter/material.dart';

class Breakpoints {
  static const double mobile = 600;
  static const double tablet = 900;
  static const double desktop = 1200;

  static bool isMobile(BuildContext context) =>
      MediaQuery.of(context).size.width < mobile;

  static bool isTablet(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    return width >= mobile && width < desktop;
  }

  static bool isDesktop(BuildContext context) =>
      MediaQuery.of(context).size.width >= desktop;

  static double getContentWidth(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    if (screenWidth >= desktop) return desktop;
    return screenWidth;
  }

  static EdgeInsets getPagePadding(BuildContext context) {
    if (isMobile(context)) return const EdgeInsets.all(16);
    if (isTablet(context)) return const EdgeInsets.all(24);
    return const EdgeInsets.all(32);
  }

  static int getGridColumns(BuildContext context) {
    if (isMobile(context)) return 1;
    if (isTablet(context)) return 2;
    return 3;
  }
}

class TouchTargets {
  static const double minimum = 44.0;
  static const double comfortable = 48.0;
  static const double large = 56.0;
  static const double minSpacing = 8.0;

  static BoxConstraints get minimumConstraints =>
      const BoxConstraints(minWidth: minimum, minHeight: minimum);

  static BoxConstraints get comfortableConstraints =>
      const BoxConstraints(minWidth: comfortable, minHeight: comfortable);
}

class AppIcons {
  static const workOrder = Icons.assignment_outlined;
  static const workOrderFilled = Icons.assignment;
  static const createWorkOrder = Icons.add_circle_outline;

  static const fileDoc = Icons.description_outlined;
  static const fileDocFilled = Icons.description;
  static const folder = Icons.folder_outlined;
  static const upload = Icons.cloud_upload_outlined;
  static const download = Icons.cloud_download_outlined;
  static const pdf = Icons.picture_as_pdf_outlined;
  static const file = Icons.insert_drive_file_outlined;

  static const user = Icons.person_outlined;
  static const userFilled = Icons.person;
  static const users = Icons.people_outlined;

  static const pending = Icons.schedule_outlined;
  static const inProgress = Icons.autorenew_outlined;
  static const completed = Icons.check_circle_outline;
  static const cancelled = Icons.cancel_outlined;

  static const home = Icons.home_outlined;
  static const dashboard = Icons.dashboard_outlined;
  static const settings = Icons.settings_outlined;
  static const notifications = Icons.notifications_outlined;
  static const notificationsFilled = Icons.notifications;
  static const more = Icons.more_horiz;
  static const menu = Icons.menu;
  static const back = Icons.arrow_back;
  static const close = Icons.close;

  static const search = Icons.search;
  static const filter = Icons.filter_list;
  static const sort = Icons.sort;
  static const edit = Icons.edit_outlined;
  static const delete = Icons.delete_outline;
  static const share = Icons.share_outlined;
  static const save = Icons.save_outlined;
  static const send = Icons.send_outlined;
  static const attach = Icons.attach_file;
  static const refresh = Icons.refresh;
  static const visibility = Icons.visibility_outlined;

  static const calendar = Icons.calendar_today_outlined;
  static const time = Icons.access_time;
  static const dropdown = Icons.arrow_drop_down;

  static const success = Icons.check_circle_outline;
  static const error = Icons.error_outline;
  static const warning = Icons.warning_amber_outlined;
  static const info = Icons.info_outline;

  static const comment = Icons.comment_outlined;
  static const chat = Icons.chat_outlined;

  static const report = Icons.assessment_outlined;
  static const analytics = Icons.analytics_outlined;

  static const department = Icons.business_outlined;
  static const location = Icons.location_on_outlined;

  static const logout = Icons.logout;
  static const login = Icons.login;

  static const empty = Icons.inbox_outlined;
  static const noData = Icons.data_usage_outlined;
}

class AppIconSizes {
  static const double tiny = 16;
  static const double small = 20;
  static const double medium = 24;
  static const double large = 32;
  static const double huge = 48;

  static const double button = 20;
  static const double appBar = 24;
  static const double fab = 24;
  static const double listTile = 24;
  static const double avatar = 20;
}
