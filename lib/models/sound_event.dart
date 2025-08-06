enum SoundType {
  speech,
  music,
  siren,
  horn,
  alarm,
  bell,
  crash,
  explosion,
  scream,
  crying,
  gunshot,
  footsteps,
  door,
  water,
  wind,
  rain,
  unknown
}

class SoundEvent {
  final String id;
  final SoundType type;
  final double confidence;
  final String description;
  final bool isEmergency;
  final DateTime timestamp;
  final Map<String, dynamic>? metadata;

  SoundEvent({
    String? id,
    required this.type,
    required this.confidence,
    required this.description,
    required this.isEmergency,
    DateTime? timestamp,
    this.metadata,
  })  : id = id ?? DateTime.now().millisecondsSinceEpoch.toString(),
        timestamp = timestamp ?? DateTime.now();

  factory SoundEvent.fromJson(Map<String, dynamic> json) {
    return SoundEvent(
      id: json['id']?.toString() ?? DateTime.now().millisecondsSinceEpoch.toString(),
      type: _parseTypeFromString(json['type']?.toString() ?? 'unknown'),
      confidence: (json['confidence'] as num?)?.toDouble() ?? 0.0,
      description: json['description']?.toString() ?? 'Unknown sound',
      isEmergency: json['isEmergency'] as bool? ?? false,
      timestamp: json['timestamp'] != null 
          ? DateTime.fromMillisecondsSinceEpoch(json['timestamp'] as int)
          : DateTime.now(),
      metadata: json['metadata'] as Map<String, dynamic>?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'type': type.name,
      'confidence': confidence,
      'description': description,
      'isEmergency': isEmergency,
      'timestamp': timestamp.millisecondsSinceEpoch,
      'metadata': metadata,
    };
  }

  static SoundType _parseTypeFromString(String typeString) {
    switch (typeString.toLowerCase()) {
      case 'speech':
        return SoundType.speech;
      case 'music':
        return SoundType.music;
      case 'siren':
        return SoundType.siren;
      case 'horn':
        return SoundType.horn;
      case 'alarm':
        return SoundType.alarm;
      case 'bell':
        return SoundType.bell;
      case 'crash':
        return SoundType.crash;
      case 'explosion':
        return SoundType.explosion;
      case 'scream':
        return SoundType.scream;
      case 'crying':
        return SoundType.crying;
      case 'gunshot':
        return SoundType.gunshot;
      case 'footsteps':
        return SoundType.footsteps;
      case 'door':
        return SoundType.door;
      case 'water':
        return SoundType.water;
      case 'wind':
        return SoundType.wind;
      case 'rain':
        return SoundType.rain;
      default:
        return SoundType.unknown;
    }
  }

  String get categoryDescription {
    switch (type) {
      case SoundType.speech:
        return 'Human Speech';
      case SoundType.music:
        return 'Music';
      case SoundType.siren:
        return 'Emergency Siren';
      case SoundType.horn:
        return 'Vehicle Horn';
      case SoundType.alarm:
        return 'Alarm';
      case SoundType.bell:
        return 'Bell';
      case SoundType.crash:
        return 'Crash/Impact';
      case SoundType.explosion:
        return 'Explosion';
      case SoundType.scream:
        return 'Scream';
      case SoundType.crying:
        return 'Crying/Distress';
      case SoundType.gunshot:
        return 'Gunshot';
      case SoundType.footsteps:
        return 'Footsteps';
      case SoundType.door:
        return 'Door';
      case SoundType.water:
        return 'Water';
      case SoundType.wind:
        return 'Wind';
      case SoundType.rain:
        return 'Rain';
      case SoundType.unknown:
        return 'Unknown Sound';
    }
  }

  String get confidenceText {
    if (confidence >= 0.9) return 'Very High';
    if (confidence >= 0.7) return 'High';
    if (confidence >= 0.5) return 'Medium';
    if (confidence >= 0.3) return 'Low';
    return 'Very Low';
  }

  bool get isHighConfidence => confidence >= 0.7;
  bool get isMediumConfidence => confidence >= 0.4 && confidence < 0.7;
  bool get isLowConfidence => confidence < 0.4;

  String get urgencyLevel {
    if (isEmergency && confidence >= 0.8) return 'Critical';
    if (isEmergency) return 'High';
    if (type == SoundType.horn || type == SoundType.alarm) return 'Medium';
    return 'Low';
  }

  Duration get age => DateTime.now().difference(timestamp);
  
  // Compatibility properties for deaf_home.dart
  String get category => type.name;
  String get urgency => urgencyLevel.toLowerCase();
  String? get transcription => metadata?['transcription'] as String?;

  String get timeAgo {
    final duration = age;
    if (duration.inDays > 0) {
      return '${duration.inDays}d ago';
    } else if (duration.inHours > 0) {
      return '${duration.inHours}h ago';
    } else if (duration.inMinutes > 0) {
      return '${duration.inMinutes}m ago';
    } else {
      return '${duration.inSeconds}s ago';
    }
  }

  bool get isRecent => age.inMinutes < 5;
  bool get isStale => age.inHours > 1;

  SoundEvent copyWith({
    String? id,
    SoundType? type,
    double? confidence,
    String? description,
    bool? isEmergency,
    DateTime? timestamp,
    Map<String, dynamic>? metadata,
  }) {
    return SoundEvent(
      id: id ?? this.id,
      type: type ?? this.type,
      confidence: confidence ?? this.confidence,
      description: description ?? this.description,
      isEmergency: isEmergency ?? this.isEmergency,
      timestamp: timestamp ?? this.timestamp,
      metadata: metadata ?? this.metadata,
    );
  }

  @override
  String toString() {
    return 'SoundEvent(id: $id, type: $type, confidence: ${confidence.toStringAsFixed(2)}, '
           'description: $description, isEmergency: $isEmergency, timestamp: $timestamp)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is SoundEvent &&
        other.id == id &&
        other.type == type &&
        other.confidence == confidence &&
        other.description == description &&
        other.isEmergency == isEmergency &&
        other.timestamp == timestamp;
  }

  @override
  int get hashCode {
    return Object.hash(
      id,
      type,
      confidence,
      description,
      isEmergency,
      timestamp,
    );
  }
}

class SoundEventFilter {
  final List<SoundType>? types;
  final double? minConfidence;
  final bool? emergencyOnly;
  final Duration? maxAge;

  const SoundEventFilter({
    this.types,
    this.minConfidence,
    this.emergencyOnly,
    this.maxAge,
  });

  bool matches(SoundEvent event) {
    if (types != null && !types!.contains(event.type)) {
      return false;
    }
    
    if (minConfidence != null && event.confidence < minConfidence!) {
      return false;
    }
    
    if (emergencyOnly == true && !event.isEmergency) {
      return false;
    }
    
    if (maxAge != null && event.age > maxAge!) {
      return false;
    }
    
    return true;
  }
}

class SoundEventStats {
  final int totalEvents;
  final int emergencyEvents;
  final double averageConfidence;
  final Map<SoundType, int> typeDistribution;
  final DateTime? lastEventTime;
  final Duration timespan;

  SoundEventStats({
    required this.totalEvents,
    required this.emergencyEvents,
    required this.averageConfidence,
    required this.typeDistribution,
    this.lastEventTime,
    required this.timespan,
  });

  factory SoundEventStats.fromEvents(List<SoundEvent> events) {
    if (events.isEmpty) {
      return SoundEventStats(
        totalEvents: 0,
        emergencyEvents: 0,
        averageConfidence: 0.0,
        typeDistribution: {},
        timespan: Duration.zero,
      );
    }

    final emergencyCount = events.where((e) => e.isEmergency).length;
    final totalConfidence = events.fold(0.0, (sum, e) => sum + e.confidence);
    final avgConfidence = totalConfidence / events.length;

    final typeMap = <SoundType, int>{};
    for (final event in events) {
      typeMap[event.type] = (typeMap[event.type] ?? 0) + 1;
    }

    final sortedByTime = List<SoundEvent>.from(events)
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
    
    final timespan = sortedByTime.isNotEmpty
        ? sortedByTime.last.timestamp.difference(sortedByTime.first.timestamp)
        : Duration.zero;

    return SoundEventStats(
      totalEvents: events.length,
      emergencyEvents: emergencyCount,
      averageConfidence: avgConfidence,
      typeDistribution: typeMap,
      lastEventTime: events.isNotEmpty ? events.last.timestamp : null,
      timespan: timespan,
    );
  }

  double get emergencyRate => totalEvents > 0 ? emergencyEvents / totalEvents : 0.0;
  
  SoundType? get mostCommonType {
    if (typeDistribution.isEmpty) return null;
    return typeDistribution.entries
        .reduce((a, b) => a.value > b.value ? a : b)
        .key;
  }

  Map<String, dynamic> toJson() {
    return {
      'totalEvents': totalEvents,
      'emergencyEvents': emergencyEvents,
      'averageConfidence': averageConfidence,
      'emergencyRate': emergencyRate,
      'typeDistribution': typeDistribution.map((k, v) => MapEntry(k.name, v)),
      'lastEventTime': lastEventTime?.toIso8601String(),
      'timespan': timespan.inMilliseconds,
      'mostCommonType': mostCommonType?.name,
    };
  }
}