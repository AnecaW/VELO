import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:bike_computer/core/runtime.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:bike_computer/core/storage/app_storage.dart';
import 'package:bike_computer/models/activity_profile.dart';

/// Event base class for profile cubit
abstract class ActivityProfileEvent {}

class LoadProfilesEvent extends ActivityProfileEvent {}

class SelectProfileEvent extends ActivityProfileEvent {
  final String profileId;
  SelectProfileEvent(this.profileId);
}

class AddProfileEvent extends ActivityProfileEvent {
  final ActivityProfile profile;
  AddProfileEvent(this.profile);
}

class UpdateProfileEvent extends ActivityProfileEvent {
  final ActivityProfile profile;
  UpdateProfileEvent(this.profile);
}

class DeleteProfileEvent extends ActivityProfileEvent {
  final String profileId;
  DeleteProfileEvent(this.profileId);
}

/// State for activity profile management
class ActivityProfileState {
  final List<ActivityProfile> profiles;
  final ActivityProfile? selectedProfile;
  final bool isLoading;
  final String? error;

  const ActivityProfileState({
    this.profiles = const [],
    this.selectedProfile,
    this.isLoading = false,
    this.error,
  });

  ActivityProfileState copyWith({
    List<ActivityProfile>? profiles,
    ActivityProfile? selectedProfile,
    bool? isLoading,
    String? error,
  }) {
    return ActivityProfileState(
      profiles: profiles ?? this.profiles,
      selectedProfile: selectedProfile ?? this.selectedProfile,
      isLoading: isLoading ?? this.isLoading,
      error: error,
    );
  }
}

/// Cubit for managing activity profiles
class ActivityProfileCubit extends Cubit<ActivityProfileState> {
  static final List<ActivityProfile> _defaultProfiles =
      ActivityProfileFactory.createDefaults();

  final AppStorage _storage;

  ActivityProfileCubit({AppStorage? storage})
    : _storage = storage ?? const AppStorage(),
      super(
        ActivityProfileState(
          profiles: _defaultProfiles,
          selectedProfile: _defaultProfiles.first,
        ),
      );

  /// Load profiles from the persisted app state
  Future<void> loadProfiles() async {
    emit(state.copyWith(isLoading: true));
    try {
      final lastSelectedId = await _storage.readSelectedProfileId();
      final raw = await Runtime.database.getDocument('profiles', 'all');
      final defaults = raw == null
          ? _defaultProfiles
          : (jsonDecode(raw) as List)
                .map(
                  (j) => ActivityProfile(
                    id: j['id'],
                    name: j['name'],
                    type: j['type'],
                    icon: Icons.directions_bike,
                    accentColor: Color(j['accent']),
                    autoPauseEnabled: j['autoPause'],
                    autoPauseSpeedKmh: (j['pauseSpeed'] as num).toDouble(),
                  ),
                )
                .toList();

      if (isClosed) return;
      final selectedProfile = lastSelectedId != null
          ? defaults.firstWhere(
              (profile) => profile.id == lastSelectedId,
              orElse: () => defaults.first,
            )
          : defaults.first;

      emit(
        state.copyWith(
          profiles: defaults,
          selectedProfile: selectedProfile,
          isLoading: false,
        ),
      );
    } catch (e) {
      if (isClosed) return;
      emit(
        state.copyWith(isLoading: false, error: 'Failed to load profiles: $e'),
      );
    }
  }

  /// Select an activity profile
  Future<void> selectProfile(String profileId) async {
    final profile = state.profiles.isNotEmpty
        ? state.profiles.firstWhere(
            (p) => p.id == profileId,
            orElse: () => state.selectedProfile ?? state.profiles.first,
          )
        : _defaultProfiles.first;
    emit(state.copyWith(selectedProfile: profile));

    await _storage.writeSelectedProfileId(profile.id);
  }

  /// Add a new activity profile
  Future<void> addProfile(ActivityProfile profile) async {
    final updatedProfiles = [...state.profiles, profile];
    emit(state.copyWith(profiles: updatedProfiles));
    await _persist(updatedProfiles);

    if (state.selectedProfile == null) {
      await selectProfile(profile.id);
    }
  }

  /// Update an existing activity profile
  Future<void> updateProfile(ActivityProfile profile) async {
    final updatedProfiles = state.profiles.map((p) {
      return p.id == profile.id ? profile : p;
    }).toList();

    emit(state.copyWith(profiles: updatedProfiles));
    await _persist(updatedProfiles);

    if (state.selectedProfile?.id == profile.id) {
      emit(state.copyWith(selectedProfile: profile));
    }
  }

  Future<void> _persist(List<ActivityProfile> profiles) async {
    await Runtime.database.putDocument(
      'profiles',
      'all',
      jsonEncode(
        profiles
            .map(
              (p) => {
                'id': p.id,
                'name': p.name,
                'type': p.type,
                'accent': p.accentColor.toARGB32(),
                'autoPause': p.autoPauseEnabled,
                'pauseSpeed': p.autoPauseSpeedKmh,
              },
            )
            .toList(),
      ),
    );
    await Runtime.settings.set(
      'profilesVersion',
      DateTime.now().microsecondsSinceEpoch,
    );
  }

  /// Delete an activity profile
  Future<void> deleteProfile(String profileId) async {
    if (state.profiles.length <= 1) {
      throw StateError('Behoud minstens één activiteitprofiel');
    }
    final updatedProfiles = state.profiles
        .where((p) => p.id != profileId)
        .toList();

    emit(state.copyWith(profiles: updatedProfiles));
    await _persist(updatedProfiles);

    if (state.selectedProfile?.id == profileId) {
      final nextProfile = updatedProfiles.isNotEmpty
          ? updatedProfiles.first
          : null;
      emit(state.copyWith(selectedProfile: nextProfile));
      if (nextProfile != null) {
        await _storage.writeSelectedProfileId(nextProfile.id);
      } else {
        await _storage.clearSelectedProfileId();
      }
    }
  }
}
