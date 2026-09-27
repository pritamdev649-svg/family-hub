import 'package:family_hub/features/auth/data/auth_mock_handlers.dart';
import 'package:family_hub/features/dashboard/data/dashboard_mock_handlers.dart';
import 'package:family_hub/features/emergency_card/data/emergency_card_mock_handlers.dart';
import 'package:family_hub/features/family/data/family_mock_handlers.dart';
import 'package:family_hub/features/ledger/data/ledger_mock_handlers.dart';
import 'package:family_hub/features/notices/data/notices_mock_handlers.dart';
import 'package:family_hub/features/settings/data/settings_mock_handlers.dart';
import 'package:family_hub/features/sos/data/sos_mock_handlers.dart';
import 'package:family_hub/features/tasks/data/tasks_mock_handlers.dart';

import 'package:family_hub/core/network/mock/mock_backend.dart';

/// Registers every mock route of the contract on [b].
///
/// Each feature owns its handlers in
/// `lib/features/<feature>/data/<feature>_mock_handlers.dart`
/// (auth → `auth`, me + uploads → `settings`, family → `family`,
/// tasks → `tasks`, ledger + goals → `ledger`, notices → `notices`,
/// emergency cards → `emergency_card`, sos → `sos`, dashboard → `dashboard`).
void registerAllMocks(MockBackend b) {
  registerCoreMocks(b);
  registerAuthMocks(b);
  registerMeMocks(b);
  registerFamilyMocks(b);
  registerTaskMocks(b);
  registerLedgerMocks(b);
  registerNoticeMocks(b);
  registerEmergencyCardMocks(b);
  registerSosMocks(b);
  registerDashboardMocks(b);
  registerUploadMocks(b);
}

/// Routes owned by the core (not tied to a feature).
void registerCoreMocks(MockBackend b) {
  b.on(
    'GET',
    '/health',
    (_) => const MockResponse.ok({
      'status': 'ok',
      'db': 'up',
      'version': '1.0.0-mock',
    }),
  );
}
