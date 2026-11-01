// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'bike_computer_database.dart';

// ignore_for_file: type=lint
class $RideHistoryTableTable extends RideHistoryTable
    with TableInfo<$RideHistoryTableTable, RideHistoryTableData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $RideHistoryTableTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _rideIdMeta = const VerificationMeta('rideId');
  @override
  late final GeneratedColumn<String> rideId = GeneratedColumn<String>(
    'ride_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways('UNIQUE'),
  );
  static const VerificationMeta _stateMeta = const VerificationMeta('state');
  @override
  late final GeneratedColumn<String> state = GeneratedColumn<String>(
    'state',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _startTimeMeta = const VerificationMeta(
    'startTime',
  );
  @override
  late final GeneratedColumn<DateTime> startTime = GeneratedColumn<DateTime>(
    'start_time',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _endTimeMeta = const VerificationMeta(
    'endTime',
  );
  @override
  late final GeneratedColumn<DateTime> endTime = GeneratedColumn<DateTime>(
    'end_time',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _totalDistanceMeta = const VerificationMeta(
    'totalDistance',
  );
  @override
  late final GeneratedColumn<double> totalDistance = GeneratedColumn<double>(
    'total_distance',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _averageSpeedMeta = const VerificationMeta(
    'averageSpeed',
  );
  @override
  late final GeneratedColumn<double> averageSpeed = GeneratedColumn<double>(
    'average_speed',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _maxSpeedMeta = const VerificationMeta(
    'maxSpeed',
  );
  @override
  late final GeneratedColumn<double> maxSpeed = GeneratedColumn<double>(
    'max_speed',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _totalElevationGainMeta =
      const VerificationMeta('totalElevationGain');
  @override
  late final GeneratedColumn<double> totalElevationGain =
      GeneratedColumn<double>(
        'total_elevation_gain',
        aliasedName,
        false,
        type: DriftSqlType.double,
        requiredDuringInsert: true,
      );
  static const VerificationMeta _totalElevationLossMeta =
      const VerificationMeta('totalElevationLoss');
  @override
  late final GeneratedColumn<double> totalElevationLoss =
      GeneratedColumn<double>(
        'total_elevation_loss',
        aliasedName,
        false,
        type: DriftSqlType.double,
        requiredDuringInsert: true,
      );
  static const VerificationMeta _averageGradeMeta = const VerificationMeta(
    'averageGrade',
  );
  @override
  late final GeneratedColumn<double> averageGrade = GeneratedColumn<double>(
    'average_grade',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _averageHeartRateMeta = const VerificationMeta(
    'averageHeartRate',
  );
  @override
  late final GeneratedColumn<double> averageHeartRate = GeneratedColumn<double>(
    'average_heart_rate',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _maxHeartRateMeta = const VerificationMeta(
    'maxHeartRate',
  );
  @override
  late final GeneratedColumn<double> maxHeartRate = GeneratedColumn<double>(
    'max_heart_rate',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _averageCadenceMeta = const VerificationMeta(
    'averageCadence',
  );
  @override
  late final GeneratedColumn<double> averageCadence = GeneratedColumn<double>(
    'average_cadence',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _maxCadenceMeta = const VerificationMeta(
    'maxCadence',
  );
  @override
  late final GeneratedColumn<double> maxCadence = GeneratedColumn<double>(
    'max_cadence',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _averagePowerMeta = const VerificationMeta(
    'averagePower',
  );
  @override
  late final GeneratedColumn<double> averagePower = GeneratedColumn<double>(
    'average_power',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _maxPowerMeta = const VerificationMeta(
    'maxPower',
  );
  @override
  late final GeneratedColumn<double> maxPower = GeneratedColumn<double>(
    'max_power',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _elapsedSecondsMeta = const VerificationMeta(
    'elapsedSeconds',
  );
  @override
  late final GeneratedColumn<int> elapsedSeconds = GeneratedColumn<int>(
    'elapsed_seconds',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    rideId,
    state,
    startTime,
    endTime,
    totalDistance,
    averageSpeed,
    maxSpeed,
    totalElevationGain,
    totalElevationLoss,
    averageGrade,
    averageHeartRate,
    maxHeartRate,
    averageCadence,
    maxCadence,
    averagePower,
    maxPower,
    elapsedSeconds,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'ride_history_table';
  @override
  VerificationContext validateIntegrity(
    Insertable<RideHistoryTableData> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('ride_id')) {
      context.handle(
        _rideIdMeta,
        rideId.isAcceptableOrUnknown(data['ride_id']!, _rideIdMeta),
      );
    } else if (isInserting) {
      context.missing(_rideIdMeta);
    }
    if (data.containsKey('state')) {
      context.handle(
        _stateMeta,
        state.isAcceptableOrUnknown(data['state']!, _stateMeta),
      );
    } else if (isInserting) {
      context.missing(_stateMeta);
    }
    if (data.containsKey('start_time')) {
      context.handle(
        _startTimeMeta,
        startTime.isAcceptableOrUnknown(data['start_time']!, _startTimeMeta),
      );
    }
    if (data.containsKey('end_time')) {
      context.handle(
        _endTimeMeta,
        endTime.isAcceptableOrUnknown(data['end_time']!, _endTimeMeta),
      );
    }
    if (data.containsKey('total_distance')) {
      context.handle(
        _totalDistanceMeta,
        totalDistance.isAcceptableOrUnknown(
          data['total_distance']!,
          _totalDistanceMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_totalDistanceMeta);
    }
    if (data.containsKey('average_speed')) {
      context.handle(
        _averageSpeedMeta,
        averageSpeed.isAcceptableOrUnknown(
          data['average_speed']!,
          _averageSpeedMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_averageSpeedMeta);
    }
    if (data.containsKey('max_speed')) {
      context.handle(
        _maxSpeedMeta,
        maxSpeed.isAcceptableOrUnknown(data['max_speed']!, _maxSpeedMeta),
      );
    } else if (isInserting) {
      context.missing(_maxSpeedMeta);
    }
    if (data.containsKey('total_elevation_gain')) {
      context.handle(
        _totalElevationGainMeta,
        totalElevationGain.isAcceptableOrUnknown(
          data['total_elevation_gain']!,
          _totalElevationGainMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_totalElevationGainMeta);
    }
    if (data.containsKey('total_elevation_loss')) {
      context.handle(
        _totalElevationLossMeta,
        totalElevationLoss.isAcceptableOrUnknown(
          data['total_elevation_loss']!,
          _totalElevationLossMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_totalElevationLossMeta);
    }
    if (data.containsKey('average_grade')) {
      context.handle(
        _averageGradeMeta,
        averageGrade.isAcceptableOrUnknown(
          data['average_grade']!,
          _averageGradeMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_averageGradeMeta);
    }
    if (data.containsKey('average_heart_rate')) {
      context.handle(
        _averageHeartRateMeta,
        averageHeartRate.isAcceptableOrUnknown(
          data['average_heart_rate']!,
          _averageHeartRateMeta,
        ),
      );
    }
    if (data.containsKey('max_heart_rate')) {
      context.handle(
        _maxHeartRateMeta,
        maxHeartRate.isAcceptableOrUnknown(
          data['max_heart_rate']!,
          _maxHeartRateMeta,
        ),
      );
    }
    if (data.containsKey('average_cadence')) {
      context.handle(
        _averageCadenceMeta,
        averageCadence.isAcceptableOrUnknown(
          data['average_cadence']!,
          _averageCadenceMeta,
        ),
      );
    }
    if (data.containsKey('max_cadence')) {
      context.handle(
        _maxCadenceMeta,
        maxCadence.isAcceptableOrUnknown(data['max_cadence']!, _maxCadenceMeta),
      );
    }
    if (data.containsKey('average_power')) {
      context.handle(
        _averagePowerMeta,
        averagePower.isAcceptableOrUnknown(
          data['average_power']!,
          _averagePowerMeta,
        ),
      );
    }
    if (data.containsKey('max_power')) {
      context.handle(
        _maxPowerMeta,
        maxPower.isAcceptableOrUnknown(data['max_power']!, _maxPowerMeta),
      );
    }
    if (data.containsKey('elapsed_seconds')) {
      context.handle(
        _elapsedSecondsMeta,
        elapsedSeconds.isAcceptableOrUnknown(
          data['elapsed_seconds']!,
          _elapsedSecondsMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_elapsedSecondsMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  RideHistoryTableData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return RideHistoryTableData(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      rideId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}ride_id'],
      )!,
      state: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}state'],
      )!,
      startTime: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}start_time'],
      ),
      endTime: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}end_time'],
      ),
      totalDistance: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}total_distance'],
      )!,
      averageSpeed: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}average_speed'],
      )!,
      maxSpeed: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}max_speed'],
      )!,
      totalElevationGain: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}total_elevation_gain'],
      )!,
      totalElevationLoss: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}total_elevation_loss'],
      )!,
      averageGrade: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}average_grade'],
      )!,
      averageHeartRate: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}average_heart_rate'],
      ),
      maxHeartRate: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}max_heart_rate'],
      ),
      averageCadence: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}average_cadence'],
      ),
      maxCadence: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}max_cadence'],
      ),
      averagePower: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}average_power'],
      ),
      maxPower: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}max_power'],
      ),
      elapsedSeconds: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}elapsed_seconds'],
      )!,
    );
  }

  @override
  $RideHistoryTableTable createAlias(String alias) {
    return $RideHistoryTableTable(attachedDatabase, alias);
  }
}

class RideHistoryTableData extends DataClass
    implements Insertable<RideHistoryTableData> {
  final int id;
  final String rideId;
  final String state;
  final DateTime? startTime;
  final DateTime? endTime;
  final double totalDistance;
  final double averageSpeed;
  final double maxSpeed;
  final double totalElevationGain;
  final double totalElevationLoss;
  final double averageGrade;
  final double? averageHeartRate;
  final double? maxHeartRate;
  final double? averageCadence;
  final double? maxCadence;
  final double? averagePower;
  final double? maxPower;
  final int elapsedSeconds;
  const RideHistoryTableData({
    required this.id,
    required this.rideId,
    required this.state,
    this.startTime,
    this.endTime,
    required this.totalDistance,
    required this.averageSpeed,
    required this.maxSpeed,
    required this.totalElevationGain,
    required this.totalElevationLoss,
    required this.averageGrade,
    this.averageHeartRate,
    this.maxHeartRate,
    this.averageCadence,
    this.maxCadence,
    this.averagePower,
    this.maxPower,
    required this.elapsedSeconds,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['ride_id'] = Variable<String>(rideId);
    map['state'] = Variable<String>(state);
    if (!nullToAbsent || startTime != null) {
      map['start_time'] = Variable<DateTime>(startTime);
    }
    if (!nullToAbsent || endTime != null) {
      map['end_time'] = Variable<DateTime>(endTime);
    }
    map['total_distance'] = Variable<double>(totalDistance);
    map['average_speed'] = Variable<double>(averageSpeed);
    map['max_speed'] = Variable<double>(maxSpeed);
    map['total_elevation_gain'] = Variable<double>(totalElevationGain);
    map['total_elevation_loss'] = Variable<double>(totalElevationLoss);
    map['average_grade'] = Variable<double>(averageGrade);
    if (!nullToAbsent || averageHeartRate != null) {
      map['average_heart_rate'] = Variable<double>(averageHeartRate);
    }
    if (!nullToAbsent || maxHeartRate != null) {
      map['max_heart_rate'] = Variable<double>(maxHeartRate);
    }
    if (!nullToAbsent || averageCadence != null) {
      map['average_cadence'] = Variable<double>(averageCadence);
    }
    if (!nullToAbsent || maxCadence != null) {
      map['max_cadence'] = Variable<double>(maxCadence);
    }
    if (!nullToAbsent || averagePower != null) {
      map['average_power'] = Variable<double>(averagePower);
    }
    if (!nullToAbsent || maxPower != null) {
      map['max_power'] = Variable<double>(maxPower);
    }
    map['elapsed_seconds'] = Variable<int>(elapsedSeconds);
    return map;
  }

  RideHistoryTableCompanion toCompanion(bool nullToAbsent) {
    return RideHistoryTableCompanion(
      id: Value(id),
      rideId: Value(rideId),
      state: Value(state),
      startTime: startTime == null && nullToAbsent
          ? const Value.absent()
          : Value(startTime),
      endTime: endTime == null && nullToAbsent
          ? const Value.absent()
          : Value(endTime),
      totalDistance: Value(totalDistance),
      averageSpeed: Value(averageSpeed),
      maxSpeed: Value(maxSpeed),
      totalElevationGain: Value(totalElevationGain),
      totalElevationLoss: Value(totalElevationLoss),
      averageGrade: Value(averageGrade),
      averageHeartRate: averageHeartRate == null && nullToAbsent
          ? const Value.absent()
          : Value(averageHeartRate),
      maxHeartRate: maxHeartRate == null && nullToAbsent
          ? const Value.absent()
          : Value(maxHeartRate),
      averageCadence: averageCadence == null && nullToAbsent
          ? const Value.absent()
          : Value(averageCadence),
      maxCadence: maxCadence == null && nullToAbsent
          ? const Value.absent()
          : Value(maxCadence),
      averagePower: averagePower == null && nullToAbsent
          ? const Value.absent()
          : Value(averagePower),
      maxPower: maxPower == null && nullToAbsent
          ? const Value.absent()
          : Value(maxPower),
      elapsedSeconds: Value(elapsedSeconds),
    );
  }

  factory RideHistoryTableData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return RideHistoryTableData(
      id: serializer.fromJson<int>(json['id']),
      rideId: serializer.fromJson<String>(json['rideId']),
      state: serializer.fromJson<String>(json['state']),
      startTime: serializer.fromJson<DateTime?>(json['startTime']),
      endTime: serializer.fromJson<DateTime?>(json['endTime']),
      totalDistance: serializer.fromJson<double>(json['totalDistance']),
      averageSpeed: serializer.fromJson<double>(json['averageSpeed']),
      maxSpeed: serializer.fromJson<double>(json['maxSpeed']),
      totalElevationGain: serializer.fromJson<double>(
        json['totalElevationGain'],
      ),
      totalElevationLoss: serializer.fromJson<double>(
        json['totalElevationLoss'],
      ),
      averageGrade: serializer.fromJson<double>(json['averageGrade']),
      averageHeartRate: serializer.fromJson<double?>(json['averageHeartRate']),
      maxHeartRate: serializer.fromJson<double?>(json['maxHeartRate']),
      averageCadence: serializer.fromJson<double?>(json['averageCadence']),
      maxCadence: serializer.fromJson<double?>(json['maxCadence']),
      averagePower: serializer.fromJson<double?>(json['averagePower']),
      maxPower: serializer.fromJson<double?>(json['maxPower']),
      elapsedSeconds: serializer.fromJson<int>(json['elapsedSeconds']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'rideId': serializer.toJson<String>(rideId),
      'state': serializer.toJson<String>(state),
      'startTime': serializer.toJson<DateTime?>(startTime),
      'endTime': serializer.toJson<DateTime?>(endTime),
      'totalDistance': serializer.toJson<double>(totalDistance),
      'averageSpeed': serializer.toJson<double>(averageSpeed),
      'maxSpeed': serializer.toJson<double>(maxSpeed),
      'totalElevationGain': serializer.toJson<double>(totalElevationGain),
      'totalElevationLoss': serializer.toJson<double>(totalElevationLoss),
      'averageGrade': serializer.toJson<double>(averageGrade),
      'averageHeartRate': serializer.toJson<double?>(averageHeartRate),
      'maxHeartRate': serializer.toJson<double?>(maxHeartRate),
      'averageCadence': serializer.toJson<double?>(averageCadence),
      'maxCadence': serializer.toJson<double?>(maxCadence),
      'averagePower': serializer.toJson<double?>(averagePower),
      'maxPower': serializer.toJson<double?>(maxPower),
      'elapsedSeconds': serializer.toJson<int>(elapsedSeconds),
    };
  }

  RideHistoryTableData copyWith({
    int? id,
    String? rideId,
    String? state,
    Value<DateTime?> startTime = const Value.absent(),
    Value<DateTime?> endTime = const Value.absent(),
    double? totalDistance,
    double? averageSpeed,
    double? maxSpeed,
    double? totalElevationGain,
    double? totalElevationLoss,
    double? averageGrade,
    Value<double?> averageHeartRate = const Value.absent(),
    Value<double?> maxHeartRate = const Value.absent(),
    Value<double?> averageCadence = const Value.absent(),
    Value<double?> maxCadence = const Value.absent(),
    Value<double?> averagePower = const Value.absent(),
    Value<double?> maxPower = const Value.absent(),
    int? elapsedSeconds,
  }) => RideHistoryTableData(
    id: id ?? this.id,
    rideId: rideId ?? this.rideId,
    state: state ?? this.state,
    startTime: startTime.present ? startTime.value : this.startTime,
    endTime: endTime.present ? endTime.value : this.endTime,
    totalDistance: totalDistance ?? this.totalDistance,
    averageSpeed: averageSpeed ?? this.averageSpeed,
    maxSpeed: maxSpeed ?? this.maxSpeed,
    totalElevationGain: totalElevationGain ?? this.totalElevationGain,
    totalElevationLoss: totalElevationLoss ?? this.totalElevationLoss,
    averageGrade: averageGrade ?? this.averageGrade,
    averageHeartRate: averageHeartRate.present
        ? averageHeartRate.value
        : this.averageHeartRate,
    maxHeartRate: maxHeartRate.present ? maxHeartRate.value : this.maxHeartRate,
    averageCadence: averageCadence.present
        ? averageCadence.value
        : this.averageCadence,
    maxCadence: maxCadence.present ? maxCadence.value : this.maxCadence,
    averagePower: averagePower.present ? averagePower.value : this.averagePower,
    maxPower: maxPower.present ? maxPower.value : this.maxPower,
    elapsedSeconds: elapsedSeconds ?? this.elapsedSeconds,
  );
  RideHistoryTableData copyWithCompanion(RideHistoryTableCompanion data) {
    return RideHistoryTableData(
      id: data.id.present ? data.id.value : this.id,
      rideId: data.rideId.present ? data.rideId.value : this.rideId,
      state: data.state.present ? data.state.value : this.state,
      startTime: data.startTime.present ? data.startTime.value : this.startTime,
      endTime: data.endTime.present ? data.endTime.value : this.endTime,
      totalDistance: data.totalDistance.present
          ? data.totalDistance.value
          : this.totalDistance,
      averageSpeed: data.averageSpeed.present
          ? data.averageSpeed.value
          : this.averageSpeed,
      maxSpeed: data.maxSpeed.present ? data.maxSpeed.value : this.maxSpeed,
      totalElevationGain: data.totalElevationGain.present
          ? data.totalElevationGain.value
          : this.totalElevationGain,
      totalElevationLoss: data.totalElevationLoss.present
          ? data.totalElevationLoss.value
          : this.totalElevationLoss,
      averageGrade: data.averageGrade.present
          ? data.averageGrade.value
          : this.averageGrade,
      averageHeartRate: data.averageHeartRate.present
          ? data.averageHeartRate.value
          : this.averageHeartRate,
      maxHeartRate: data.maxHeartRate.present
          ? data.maxHeartRate.value
          : this.maxHeartRate,
      averageCadence: data.averageCadence.present
          ? data.averageCadence.value
          : this.averageCadence,
      maxCadence: data.maxCadence.present
          ? data.maxCadence.value
          : this.maxCadence,
      averagePower: data.averagePower.present
          ? data.averagePower.value
          : this.averagePower,
      maxPower: data.maxPower.present ? data.maxPower.value : this.maxPower,
      elapsedSeconds: data.elapsedSeconds.present
          ? data.elapsedSeconds.value
          : this.elapsedSeconds,
    );
  }

  @override
  String toString() {
    return (StringBuffer('RideHistoryTableData(')
          ..write('id: $id, ')
          ..write('rideId: $rideId, ')
          ..write('state: $state, ')
          ..write('startTime: $startTime, ')
          ..write('endTime: $endTime, ')
          ..write('totalDistance: $totalDistance, ')
          ..write('averageSpeed: $averageSpeed, ')
          ..write('maxSpeed: $maxSpeed, ')
          ..write('totalElevationGain: $totalElevationGain, ')
          ..write('totalElevationLoss: $totalElevationLoss, ')
          ..write('averageGrade: $averageGrade, ')
          ..write('averageHeartRate: $averageHeartRate, ')
          ..write('maxHeartRate: $maxHeartRate, ')
          ..write('averageCadence: $averageCadence, ')
          ..write('maxCadence: $maxCadence, ')
          ..write('averagePower: $averagePower, ')
          ..write('maxPower: $maxPower, ')
          ..write('elapsedSeconds: $elapsedSeconds')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    rideId,
    state,
    startTime,
    endTime,
    totalDistance,
    averageSpeed,
    maxSpeed,
    totalElevationGain,
    totalElevationLoss,
    averageGrade,
    averageHeartRate,
    maxHeartRate,
    averageCadence,
    maxCadence,
    averagePower,
    maxPower,
    elapsedSeconds,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is RideHistoryTableData &&
          other.id == this.id &&
          other.rideId == this.rideId &&
          other.state == this.state &&
          other.startTime == this.startTime &&
          other.endTime == this.endTime &&
          other.totalDistance == this.totalDistance &&
          other.averageSpeed == this.averageSpeed &&
          other.maxSpeed == this.maxSpeed &&
          other.totalElevationGain == this.totalElevationGain &&
          other.totalElevationLoss == this.totalElevationLoss &&
          other.averageGrade == this.averageGrade &&
          other.averageHeartRate == this.averageHeartRate &&
          other.maxHeartRate == this.maxHeartRate &&
          other.averageCadence == this.averageCadence &&
          other.maxCadence == this.maxCadence &&
          other.averagePower == this.averagePower &&
          other.maxPower == this.maxPower &&
          other.elapsedSeconds == this.elapsedSeconds);
}

class RideHistoryTableCompanion extends UpdateCompanion<RideHistoryTableData> {
  final Value<int> id;
  final Value<String> rideId;
  final Value<String> state;
  final Value<DateTime?> startTime;
  final Value<DateTime?> endTime;
  final Value<double> totalDistance;
  final Value<double> averageSpeed;
  final Value<double> maxSpeed;
  final Value<double> totalElevationGain;
  final Value<double> totalElevationLoss;
  final Value<double> averageGrade;
  final Value<double?> averageHeartRate;
  final Value<double?> maxHeartRate;
  final Value<double?> averageCadence;
  final Value<double?> maxCadence;
  final Value<double?> averagePower;
  final Value<double?> maxPower;
  final Value<int> elapsedSeconds;
  const RideHistoryTableCompanion({
    this.id = const Value.absent(),
    this.rideId = const Value.absent(),
    this.state = const Value.absent(),
    this.startTime = const Value.absent(),
    this.endTime = const Value.absent(),
    this.totalDistance = const Value.absent(),
    this.averageSpeed = const Value.absent(),
    this.maxSpeed = const Value.absent(),
    this.totalElevationGain = const Value.absent(),
    this.totalElevationLoss = const Value.absent(),
    this.averageGrade = const Value.absent(),
    this.averageHeartRate = const Value.absent(),
    this.maxHeartRate = const Value.absent(),
    this.averageCadence = const Value.absent(),
    this.maxCadence = const Value.absent(),
    this.averagePower = const Value.absent(),
    this.maxPower = const Value.absent(),
    this.elapsedSeconds = const Value.absent(),
  });
  RideHistoryTableCompanion.insert({
    this.id = const Value.absent(),
    required String rideId,
    required String state,
    this.startTime = const Value.absent(),
    this.endTime = const Value.absent(),
    required double totalDistance,
    required double averageSpeed,
    required double maxSpeed,
    required double totalElevationGain,
    required double totalElevationLoss,
    required double averageGrade,
    this.averageHeartRate = const Value.absent(),
    this.maxHeartRate = const Value.absent(),
    this.averageCadence = const Value.absent(),
    this.maxCadence = const Value.absent(),
    this.averagePower = const Value.absent(),
    this.maxPower = const Value.absent(),
    required int elapsedSeconds,
  }) : rideId = Value(rideId),
       state = Value(state),
       totalDistance = Value(totalDistance),
       averageSpeed = Value(averageSpeed),
       maxSpeed = Value(maxSpeed),
       totalElevationGain = Value(totalElevationGain),
       totalElevationLoss = Value(totalElevationLoss),
       averageGrade = Value(averageGrade),
       elapsedSeconds = Value(elapsedSeconds);
  static Insertable<RideHistoryTableData> custom({
    Expression<int>? id,
    Expression<String>? rideId,
    Expression<String>? state,
    Expression<DateTime>? startTime,
    Expression<DateTime>? endTime,
    Expression<double>? totalDistance,
    Expression<double>? averageSpeed,
    Expression<double>? maxSpeed,
    Expression<double>? totalElevationGain,
    Expression<double>? totalElevationLoss,
    Expression<double>? averageGrade,
    Expression<double>? averageHeartRate,
    Expression<double>? maxHeartRate,
    Expression<double>? averageCadence,
    Expression<double>? maxCadence,
    Expression<double>? averagePower,
    Expression<double>? maxPower,
    Expression<int>? elapsedSeconds,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (rideId != null) 'ride_id': rideId,
      if (state != null) 'state': state,
      if (startTime != null) 'start_time': startTime,
      if (endTime != null) 'end_time': endTime,
      if (totalDistance != null) 'total_distance': totalDistance,
      if (averageSpeed != null) 'average_speed': averageSpeed,
      if (maxSpeed != null) 'max_speed': maxSpeed,
      if (totalElevationGain != null)
        'total_elevation_gain': totalElevationGain,
      if (totalElevationLoss != null)
        'total_elevation_loss': totalElevationLoss,
      if (averageGrade != null) 'average_grade': averageGrade,
      if (averageHeartRate != null) 'average_heart_rate': averageHeartRate,
      if (maxHeartRate != null) 'max_heart_rate': maxHeartRate,
      if (averageCadence != null) 'average_cadence': averageCadence,
      if (maxCadence != null) 'max_cadence': maxCadence,
      if (averagePower != null) 'average_power': averagePower,
      if (maxPower != null) 'max_power': maxPower,
      if (elapsedSeconds != null) 'elapsed_seconds': elapsedSeconds,
    });
  }

  RideHistoryTableCompanion copyWith({
    Value<int>? id,
    Value<String>? rideId,
    Value<String>? state,
    Value<DateTime?>? startTime,
    Value<DateTime?>? endTime,
    Value<double>? totalDistance,
    Value<double>? averageSpeed,
    Value<double>? maxSpeed,
    Value<double>? totalElevationGain,
    Value<double>? totalElevationLoss,
    Value<double>? averageGrade,
    Value<double?>? averageHeartRate,
    Value<double?>? maxHeartRate,
    Value<double?>? averageCadence,
    Value<double?>? maxCadence,
    Value<double?>? averagePower,
    Value<double?>? maxPower,
    Value<int>? elapsedSeconds,
  }) {
    return RideHistoryTableCompanion(
      id: id ?? this.id,
      rideId: rideId ?? this.rideId,
      state: state ?? this.state,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
      totalDistance: totalDistance ?? this.totalDistance,
      averageSpeed: averageSpeed ?? this.averageSpeed,
      maxSpeed: maxSpeed ?? this.maxSpeed,
      totalElevationGain: totalElevationGain ?? this.totalElevationGain,
      totalElevationLoss: totalElevationLoss ?? this.totalElevationLoss,
      averageGrade: averageGrade ?? this.averageGrade,
      averageHeartRate: averageHeartRate ?? this.averageHeartRate,
      maxHeartRate: maxHeartRate ?? this.maxHeartRate,
      averageCadence: averageCadence ?? this.averageCadence,
      maxCadence: maxCadence ?? this.maxCadence,
      averagePower: averagePower ?? this.averagePower,
      maxPower: maxPower ?? this.maxPower,
      elapsedSeconds: elapsedSeconds ?? this.elapsedSeconds,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (rideId.present) {
      map['ride_id'] = Variable<String>(rideId.value);
    }
    if (state.present) {
      map['state'] = Variable<String>(state.value);
    }
    if (startTime.present) {
      map['start_time'] = Variable<DateTime>(startTime.value);
    }
    if (endTime.present) {
      map['end_time'] = Variable<DateTime>(endTime.value);
    }
    if (totalDistance.present) {
      map['total_distance'] = Variable<double>(totalDistance.value);
    }
    if (averageSpeed.present) {
      map['average_speed'] = Variable<double>(averageSpeed.value);
    }
    if (maxSpeed.present) {
      map['max_speed'] = Variable<double>(maxSpeed.value);
    }
    if (totalElevationGain.present) {
      map['total_elevation_gain'] = Variable<double>(totalElevationGain.value);
    }
    if (totalElevationLoss.present) {
      map['total_elevation_loss'] = Variable<double>(totalElevationLoss.value);
    }
    if (averageGrade.present) {
      map['average_grade'] = Variable<double>(averageGrade.value);
    }
    if (averageHeartRate.present) {
      map['average_heart_rate'] = Variable<double>(averageHeartRate.value);
    }
    if (maxHeartRate.present) {
      map['max_heart_rate'] = Variable<double>(maxHeartRate.value);
    }
    if (averageCadence.present) {
      map['average_cadence'] = Variable<double>(averageCadence.value);
    }
    if (maxCadence.present) {
      map['max_cadence'] = Variable<double>(maxCadence.value);
    }
    if (averagePower.present) {
      map['average_power'] = Variable<double>(averagePower.value);
    }
    if (maxPower.present) {
      map['max_power'] = Variable<double>(maxPower.value);
    }
    if (elapsedSeconds.present) {
      map['elapsed_seconds'] = Variable<int>(elapsedSeconds.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('RideHistoryTableCompanion(')
          ..write('id: $id, ')
          ..write('rideId: $rideId, ')
          ..write('state: $state, ')
          ..write('startTime: $startTime, ')
          ..write('endTime: $endTime, ')
          ..write('totalDistance: $totalDistance, ')
          ..write('averageSpeed: $averageSpeed, ')
          ..write('maxSpeed: $maxSpeed, ')
          ..write('totalElevationGain: $totalElevationGain, ')
          ..write('totalElevationLoss: $totalElevationLoss, ')
          ..write('averageGrade: $averageGrade, ')
          ..write('averageHeartRate: $averageHeartRate, ')
          ..write('maxHeartRate: $maxHeartRate, ')
          ..write('averageCadence: $averageCadence, ')
          ..write('maxCadence: $maxCadence, ')
          ..write('averagePower: $averagePower, ')
          ..write('maxPower: $maxPower, ')
          ..write('elapsedSeconds: $elapsedSeconds')
          ..write(')'))
        .toString();
  }
}

abstract class _$BikeComputerDatabase extends GeneratedDatabase {
  _$BikeComputerDatabase(QueryExecutor e) : super(e);
  $BikeComputerDatabaseManager get managers =>
      $BikeComputerDatabaseManager(this);
  late final $RideHistoryTableTable rideHistoryTable = $RideHistoryTableTable(
    this,
  );
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [rideHistoryTable];
}

typedef $$RideHistoryTableTableCreateCompanionBuilder =
    RideHistoryTableCompanion Function({
      Value<int> id,
      required String rideId,
      required String state,
      Value<DateTime?> startTime,
      Value<DateTime?> endTime,
      required double totalDistance,
      required double averageSpeed,
      required double maxSpeed,
      required double totalElevationGain,
      required double totalElevationLoss,
      required double averageGrade,
      Value<double?> averageHeartRate,
      Value<double?> maxHeartRate,
      Value<double?> averageCadence,
      Value<double?> maxCadence,
      Value<double?> averagePower,
      Value<double?> maxPower,
      required int elapsedSeconds,
    });
typedef $$RideHistoryTableTableUpdateCompanionBuilder =
    RideHistoryTableCompanion Function({
      Value<int> id,
      Value<String> rideId,
      Value<String> state,
      Value<DateTime?> startTime,
      Value<DateTime?> endTime,
      Value<double> totalDistance,
      Value<double> averageSpeed,
      Value<double> maxSpeed,
      Value<double> totalElevationGain,
      Value<double> totalElevationLoss,
      Value<double> averageGrade,
      Value<double?> averageHeartRate,
      Value<double?> maxHeartRate,
      Value<double?> averageCadence,
      Value<double?> maxCadence,
      Value<double?> averagePower,
      Value<double?> maxPower,
      Value<int> elapsedSeconds,
    });

class $$RideHistoryTableTableFilterComposer
    extends Composer<_$BikeComputerDatabase, $RideHistoryTableTable> {
  $$RideHistoryTableTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get rideId => $composableBuilder(
    column: $table.rideId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get state => $composableBuilder(
    column: $table.state,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get startTime => $composableBuilder(
    column: $table.startTime,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get endTime => $composableBuilder(
    column: $table.endTime,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get totalDistance => $composableBuilder(
    column: $table.totalDistance,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get averageSpeed => $composableBuilder(
    column: $table.averageSpeed,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get maxSpeed => $composableBuilder(
    column: $table.maxSpeed,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get totalElevationGain => $composableBuilder(
    column: $table.totalElevationGain,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get totalElevationLoss => $composableBuilder(
    column: $table.totalElevationLoss,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get averageGrade => $composableBuilder(
    column: $table.averageGrade,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get averageHeartRate => $composableBuilder(
    column: $table.averageHeartRate,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get maxHeartRate => $composableBuilder(
    column: $table.maxHeartRate,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get averageCadence => $composableBuilder(
    column: $table.averageCadence,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get maxCadence => $composableBuilder(
    column: $table.maxCadence,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get averagePower => $composableBuilder(
    column: $table.averagePower,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get maxPower => $composableBuilder(
    column: $table.maxPower,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get elapsedSeconds => $composableBuilder(
    column: $table.elapsedSeconds,
    builder: (column) => ColumnFilters(column),
  );
}

class $$RideHistoryTableTableOrderingComposer
    extends Composer<_$BikeComputerDatabase, $RideHistoryTableTable> {
  $$RideHistoryTableTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get rideId => $composableBuilder(
    column: $table.rideId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get state => $composableBuilder(
    column: $table.state,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get startTime => $composableBuilder(
    column: $table.startTime,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get endTime => $composableBuilder(
    column: $table.endTime,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get totalDistance => $composableBuilder(
    column: $table.totalDistance,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get averageSpeed => $composableBuilder(
    column: $table.averageSpeed,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get maxSpeed => $composableBuilder(
    column: $table.maxSpeed,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get totalElevationGain => $composableBuilder(
    column: $table.totalElevationGain,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get totalElevationLoss => $composableBuilder(
    column: $table.totalElevationLoss,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get averageGrade => $composableBuilder(
    column: $table.averageGrade,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get averageHeartRate => $composableBuilder(
    column: $table.averageHeartRate,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get maxHeartRate => $composableBuilder(
    column: $table.maxHeartRate,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get averageCadence => $composableBuilder(
    column: $table.averageCadence,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get maxCadence => $composableBuilder(
    column: $table.maxCadence,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get averagePower => $composableBuilder(
    column: $table.averagePower,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get maxPower => $composableBuilder(
    column: $table.maxPower,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get elapsedSeconds => $composableBuilder(
    column: $table.elapsedSeconds,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$RideHistoryTableTableAnnotationComposer
    extends Composer<_$BikeComputerDatabase, $RideHistoryTableTable> {
  $$RideHistoryTableTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get rideId =>
      $composableBuilder(column: $table.rideId, builder: (column) => column);

  GeneratedColumn<String> get state =>
      $composableBuilder(column: $table.state, builder: (column) => column);

  GeneratedColumn<DateTime> get startTime =>
      $composableBuilder(column: $table.startTime, builder: (column) => column);

  GeneratedColumn<DateTime> get endTime =>
      $composableBuilder(column: $table.endTime, builder: (column) => column);

  GeneratedColumn<double> get totalDistance => $composableBuilder(
    column: $table.totalDistance,
    builder: (column) => column,
  );

  GeneratedColumn<double> get averageSpeed => $composableBuilder(
    column: $table.averageSpeed,
    builder: (column) => column,
  );

  GeneratedColumn<double> get maxSpeed =>
      $composableBuilder(column: $table.maxSpeed, builder: (column) => column);

  GeneratedColumn<double> get totalElevationGain => $composableBuilder(
    column: $table.totalElevationGain,
    builder: (column) => column,
  );

  GeneratedColumn<double> get totalElevationLoss => $composableBuilder(
    column: $table.totalElevationLoss,
    builder: (column) => column,
  );

  GeneratedColumn<double> get averageGrade => $composableBuilder(
    column: $table.averageGrade,
    builder: (column) => column,
  );

  GeneratedColumn<double> get averageHeartRate => $composableBuilder(
    column: $table.averageHeartRate,
    builder: (column) => column,
  );

  GeneratedColumn<double> get maxHeartRate => $composableBuilder(
    column: $table.maxHeartRate,
    builder: (column) => column,
  );

  GeneratedColumn<double> get averageCadence => $composableBuilder(
    column: $table.averageCadence,
    builder: (column) => column,
  );

  GeneratedColumn<double> get maxCadence => $composableBuilder(
    column: $table.maxCadence,
    builder: (column) => column,
  );

  GeneratedColumn<double> get averagePower => $composableBuilder(
    column: $table.averagePower,
    builder: (column) => column,
  );

  GeneratedColumn<double> get maxPower =>
      $composableBuilder(column: $table.maxPower, builder: (column) => column);

  GeneratedColumn<int> get elapsedSeconds => $composableBuilder(
    column: $table.elapsedSeconds,
    builder: (column) => column,
  );
}

class $$RideHistoryTableTableTableManager
    extends
        RootTableManager<
          _$BikeComputerDatabase,
          $RideHistoryTableTable,
          RideHistoryTableData,
          $$RideHistoryTableTableFilterComposer,
          $$RideHistoryTableTableOrderingComposer,
          $$RideHistoryTableTableAnnotationComposer,
          $$RideHistoryTableTableCreateCompanionBuilder,
          $$RideHistoryTableTableUpdateCompanionBuilder,
          (
            RideHistoryTableData,
            BaseReferences<
              _$BikeComputerDatabase,
              $RideHistoryTableTable,
              RideHistoryTableData
            >,
          ),
          RideHistoryTableData,
          PrefetchHooks Function()
        > {
  $$RideHistoryTableTableTableManager(
    _$BikeComputerDatabase db,
    $RideHistoryTableTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$RideHistoryTableTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$RideHistoryTableTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$RideHistoryTableTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> rideId = const Value.absent(),
                Value<String> state = const Value.absent(),
                Value<DateTime?> startTime = const Value.absent(),
                Value<DateTime?> endTime = const Value.absent(),
                Value<double> totalDistance = const Value.absent(),
                Value<double> averageSpeed = const Value.absent(),
                Value<double> maxSpeed = const Value.absent(),
                Value<double> totalElevationGain = const Value.absent(),
                Value<double> totalElevationLoss = const Value.absent(),
                Value<double> averageGrade = const Value.absent(),
                Value<double?> averageHeartRate = const Value.absent(),
                Value<double?> maxHeartRate = const Value.absent(),
                Value<double?> averageCadence = const Value.absent(),
                Value<double?> maxCadence = const Value.absent(),
                Value<double?> averagePower = const Value.absent(),
                Value<double?> maxPower = const Value.absent(),
                Value<int> elapsedSeconds = const Value.absent(),
              }) => RideHistoryTableCompanion(
                id: id,
                rideId: rideId,
                state: state,
                startTime: startTime,
                endTime: endTime,
                totalDistance: totalDistance,
                averageSpeed: averageSpeed,
                maxSpeed: maxSpeed,
                totalElevationGain: totalElevationGain,
                totalElevationLoss: totalElevationLoss,
                averageGrade: averageGrade,
                averageHeartRate: averageHeartRate,
                maxHeartRate: maxHeartRate,
                averageCadence: averageCadence,
                maxCadence: maxCadence,
                averagePower: averagePower,
                maxPower: maxPower,
                elapsedSeconds: elapsedSeconds,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String rideId,
                required String state,
                Value<DateTime?> startTime = const Value.absent(),
                Value<DateTime?> endTime = const Value.absent(),
                required double totalDistance,
                required double averageSpeed,
                required double maxSpeed,
                required double totalElevationGain,
                required double totalElevationLoss,
                required double averageGrade,
                Value<double?> averageHeartRate = const Value.absent(),
                Value<double?> maxHeartRate = const Value.absent(),
                Value<double?> averageCadence = const Value.absent(),
                Value<double?> maxCadence = const Value.absent(),
                Value<double?> averagePower = const Value.absent(),
                Value<double?> maxPower = const Value.absent(),
                required int elapsedSeconds,
              }) => RideHistoryTableCompanion.insert(
                id: id,
                rideId: rideId,
                state: state,
                startTime: startTime,
                endTime: endTime,
                totalDistance: totalDistance,
                averageSpeed: averageSpeed,
                maxSpeed: maxSpeed,
                totalElevationGain: totalElevationGain,
                totalElevationLoss: totalElevationLoss,
                averageGrade: averageGrade,
                averageHeartRate: averageHeartRate,
                maxHeartRate: maxHeartRate,
                averageCadence: averageCadence,
                maxCadence: maxCadence,
                averagePower: averagePower,
                maxPower: maxPower,
                elapsedSeconds: elapsedSeconds,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$RideHistoryTableTableProcessedTableManager =
    ProcessedTableManager<
      _$BikeComputerDatabase,
      $RideHistoryTableTable,
      RideHistoryTableData,
      $$RideHistoryTableTableFilterComposer,
      $$RideHistoryTableTableOrderingComposer,
      $$RideHistoryTableTableAnnotationComposer,
      $$RideHistoryTableTableCreateCompanionBuilder,
      $$RideHistoryTableTableUpdateCompanionBuilder,
      (
        RideHistoryTableData,
        BaseReferences<
          _$BikeComputerDatabase,
          $RideHistoryTableTable,
          RideHistoryTableData
        >,
      ),
      RideHistoryTableData,
      PrefetchHooks Function()
    >;

class $BikeComputerDatabaseManager {
  final _$BikeComputerDatabase _db;
  $BikeComputerDatabaseManager(this._db);
  $$RideHistoryTableTableTableManager get rideHistoryTable =>
      $$RideHistoryTableTableTableManager(_db, _db.rideHistoryTable);
}
