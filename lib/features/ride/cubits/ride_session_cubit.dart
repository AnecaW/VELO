import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:bike_computer/models/ride_session.dart';
import 'package:bike_computer/services/bluetooth/ble_sensor_manager.dart';
import 'package:bike_computer/services/ride/ride_recording_service.dart';
import 'package:bike_computer/services/gps/gps_service.dart';

/// State for ride recording
class RideSessionState {
  final RideSession session;
  final bool isLoading;
  final String? error;

  const RideSessionState({
    required this.session,
    this.isLoading = false,
    this.error,
  });

  RideSessionState copyWith({
    RideSession? session,
    bool? isLoading,
    String? error,
  }) {
    return RideSessionState(
      session: session ?? this.session,
      isLoading: isLoading ?? this.isLoading,
      error: error,
    );
  }
}

/// Cubit for managing ride recording state
class RideSessionCubit extends Cubit<RideSessionState> {
  late RideRecordingService _recordingService;
  final GPSService gpsService;
  final BleSensorManager? bleSensorManager;

  RideSessionCubit({required this.gpsService, this.bleSensorManager})
    : super(
        const RideSessionState(session: RideSession(state: RideState.idle)),
      ) {
    _recordingService = RideRecordingService(
      gpsService: gpsService,
      bleSensorManager: bleSensorManager,
    );
    _subscribeToRecording();
  }

  /// Initialize a new ride
  Future<void> initializeRide() async {
    try {
      emit(state.copyWith(isLoading: true));
      await _recordingService.initializeRide();
      // Session state will be emitted via subscription
      emit(state.copyWith(isLoading: false));
    } catch (e) {
      emit(
        state.copyWith(
          isLoading: false,
          error: 'Failed to initialize ride: $e',
        ),
      );
    }
  }

  /// Start recording a ride
  Future<void> startRecording() async {
    try {
      emit(state.copyWith(isLoading: true, error: null));
      await _recordingService.startRecording();
      // Session state will be emitted via subscription
      emit(state.copyWith(isLoading: false));
    } catch (e) {
      emit(
        state.copyWith(
          isLoading: false,
          error: 'Failed to start recording: $e',
        ),
      );
    }
  }

  /// Pause the current ride
  Future<void> pauseRecording() async {
    try {
      await _recordingService.pauseRecording();
      // Session state will be emitted via subscription
    } catch (e) {
      emit(state.copyWith(error: 'Failed to pause: $e'));
    }
  }

  /// Stop recording and finish the ride
  Future<void> stopRecording() async {
    try {
      await _recordingService.stopRecording();
      // Session state will be emitted via subscription
    } catch (e) {
      emit(state.copyWith(error: 'Failed to stop recording: $e'));
    }
  }

  /// Discard the current ride
  void discardRide() {
    _recordingService.discardRide();
    // Session state will be emitted via subscription
  }

  /// Mark ride as saved to database
  void markRideAsSaved(String rideId) {
    _recordingService.markAsSaved(rideId);
    // Session state will be emitted via subscription
  }

  /// Subscribe to recording service updates
  void _subscribeToRecording() {
    _recordingService.sessionStream.listen((session) {
      emit(state.copyWith(session: session, error: null));
    });
  }

  @override
  Future<void> close() async {
    _recordingService.dispose();
    return super.close();
  }
}
