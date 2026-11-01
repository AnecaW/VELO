import 'package:bike_computer/core/storage/app_storage.dart';
import 'package:bike_computer/features/profiles/cubits/activity_profile_cubit.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    await const AppStorage().clearSelectedProfileId();
  });

  test('selected activity profile persists across cubit instances', () async {
    final firstCubit = ActivityProfileCubit();
    await firstCubit.selectProfile('mtb_default');

    expect(firstCubit.state.selectedProfile?.id, 'mtb_default');

    const storage = AppStorage();
    expect(await storage.readSelectedProfileId(), 'mtb_default');

    final secondCubit = ActivityProfileCubit(storage: storage);
    await secondCubit.loadProfiles();

    expect(secondCubit.state.selectedProfile?.id, 'mtb_default');

    await firstCubit.close();
    await secondCubit.close();
  });
}
