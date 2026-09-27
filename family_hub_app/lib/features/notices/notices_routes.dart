import 'package:go_router/go_router.dart';

import 'package:family_hub/core/router/app_routes.dart';
import 'package:family_hub/features/notices/domain/notice.dart';
import 'package:family_hub/features/notices/presentation/screens/notice_form_screen.dart';
import 'package:family_hub/features/notices/presentation/screens/notices_screen.dart';

/// Full-screen routes of the notice board (registered top-level by
/// `goRouterProvider`):
///
/// * `/notices` → [NoticesScreen] (also the push route of `notice` pushes)
/// * `/notices/new` → [NoticeFormScreen] (create)
/// * `/notices/:id/edit` → [NoticeFormScreen] (edit; pass the [Notice] as
///   `extra` to skip the lookup: `context.push(AppRoutes.noticeEdit(id),
///   extra: notice)`)
List<RouteBase> get noticeRoutes => [
  GoRoute(
    path: AppRoutes.notices,
    builder: (context, state) => const NoticesScreen(),
  ),
  GoRoute(
    path: AppRoutes.noticeNew,
    builder: (context, state) => const NoticeFormScreen(),
  ),
  GoRoute(
    path: AppRoutes.noticeEditPath,
    builder: (context, state) {
      final extra = state.extra;
      return NoticeFormScreen(
        noticeId: state.pathParameters[AppRoutes.idParam] ?? '',
        initial: extra is Notice ? extra : null,
      );
    },
  ),
];
