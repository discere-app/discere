import 'package:discere/shared/service/notification_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FakeNotificationPermissionHandler extends NotificationPermissionHandler {
  FakeNotificationPermissionHandler({
    required this.initialStatus,
    this.requestResult = PermissionStatus.denied,
  });

  PermissionStatus initialStatus;
  PermissionStatus requestResult;
  int requestCallCount = 0;

  @override
  Future<PermissionStatus> status() async => initialStatus;

  @override
  Future<PermissionStatus> request() async {
    requestCallCount++;
    initialStatus = requestResult;
    return requestResult;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SharedPreferences prefs;
  late FakeNotificationPermissionHandler permissionHandler;
  late NotificationService service;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    permissionHandler = FakeNotificationPermissionHandler(
      initialStatus: PermissionStatus.denied,
    );

    service = NotificationService(
      preferences: prefs,
      permissionHandler: permissionHandler,
    );
  });

  group('NotificationService.requestPermissions', () {
    test(
      'requests permission once and stores that the prompt was shown',
      () async {
        await service.requestPermissions();

        expect(permissionHandler.requestCallCount, 1);
        expect(prefs.getBool('notification_permission_requested'), true);
      },
    );

    test(
      'does not request permission again after a prior denial was recorded',
      () async {
        await prefs.setBool('notification_permission_requested', true);

        await service.requestPermissions();

        expect(permissionHandler.requestCallCount, 0);
        expect(prefs.getBool('notification_permission_requested'), true);
      },
    );

    test(
      'does not store or request again when permission is already granted',
      () async {
        permissionHandler.initialStatus = PermissionStatus.granted;

        await service.requestPermissions();

        expect(permissionHandler.requestCallCount, 0);
        expect(prefs.getBool('notification_permission_requested'), isNull);
      },
    );
  });

  group('NotificationService.declinePermissionPrompt', () {
    test(
      'stores that the prompt was handled without requesting the OS permission',
      () async {
        await service.declinePermissionPrompt();

        expect(permissionHandler.requestCallCount, 0);
        expect(prefs.getBool('notification_permission_requested'), true);
      },
    );
  });
}
