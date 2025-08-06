class GemmaOutput {
  final String text;
  final double confidence;
  final List<String> tokens;
  final DateTime timestamp;
  final Map<String, dynamic>? metadata;

  GemmaOutput({
    required this.text,
    required this.confidence,
    required this.tokens,
    required this.timestamp,
    this.metadata,
  });

  factory GemmaOutput.fromJson(Map<String, dynamic> json) {
    return GemmaOutput(
      text: json['text'] as String? ?? '',
      confidence: (json['confidence'] as num?)?.toDouble() ?? 1.0,
      tokens: List<String>.from(json['tokens'] ?? []),
      timestamp: json['timestamp'] != null 
          ? DateTime.parse(json['timestamp'])
          : DateTime.now(),
      metadata: json['metadata'] as Map<String, dynamic>?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'text': text,
      'confidence': confidence,
      'tokens': tokens,
      'timestamp': timestamp.toIso8601String(),
      'metadata': metadata,
    };
  }

  // Convenience getters
  int get tokenCount => tokens.length;
  int get characterCount => text.length;
  bool get isEmpty => text.trim().isEmpty;
  bool get isNotEmpty => !isEmpty;
  
  // Performance metrics from metadata
  int? get latencyMs => metadata?['latency'] as int?;
  int? get tokensPerSecond => metadata?['tokensPerSecond'] as int?;
  String? get modelUsed => metadata?['model'] as String?;
  bool get pleUsed => metadata?['pleUsed'] as bool? ?? false;
  bool get kvCacheUsed => metadata?['kvCacheUsed'] as bool? ?? false;
  bool get gpuUsed => metadata?['gpuUsed'] as bool? ?? false;

  // Text analysis
  double get wordsPerToken => tokens.isNotEmpty ? text.split(' ').length / tokens.length : 0.0;
  
  List<String> get sentences {
    return text.split(RegExp(r'[.!?]+'))
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
  }

  String get firstSentence {
    final sentences = this.sentences;
    return sentences.isNotEmpty ? sentences.first : text;
  }

  String get summary {
    if (text.length <= 100) return text;
    return '${text.substring(0, 97).trim()}...';
  }

  // Quality assessment
  String get qualityLevel {
    if (confidence >= 0.9) return 'Excellent';
    if (confidence >= 0.7) return 'Good';
    if (confidence >= 0.5) return 'Fair';
    if (confidence >= 0.3) return 'Poor';
    return 'Very Poor';
  }

  bool get isHighQuality => confidence >= 0.7;
  bool get isMediumQuality => confidence >= 0.4 && confidence < 0.7;
  bool get isLowQuality => confidence < 0.4;

  // Performance assessment
  String? get performanceLevel {
    final tps = tokensPerSecond;
    if (tps == null) return null;
    
    if (tps >= 20) return 'Excellent';
    if (tps >= 10) return 'Good';
    if (tps >= 5) return 'Fair';
    return 'Slow';
  }

  bool get isFastGeneration => (tokensPerSecond ?? 0) >= 10;
  bool get isSlowGeneration => (tokensPerSecond ?? 0) < 5;

  // Create enhanced copy with additional metadata
  GemmaOutput copyWith({
    String? text,
    double? confidence,
    List<String>? tokens,
    DateTime? timestamp,
    Map<String, dynamic>? metadata,
  }) {
    return GemmaOutput(
      text: text ?? this.text,
      confidence: confidence ?? this.confidence,
      tokens: tokens ?? this.tokens,
      timestamp: timestamp ?? this.timestamp,
      metadata: metadata ?? this.metadata,
    );
  }

  // Create copy with additional metadata
  GemmaOutput withMetadata(Map<String, dynamic> additionalMetadata) {
    final newMetadata = <String, dynamic>{
      ...?metadata,
      ...additionalMetadata,
    };
    return copyWith(metadata: newMetadata);
  }

  // Create copy with updated text but preserve other properties
  GemmaOutput withText(String newText) {
    return copyWith(
      text: newText,
      tokens: newText.split(' '),
    );
  }

  // Statistical information
  Map<String, dynamic> getStatistics() {
    return {
      'textLength': text.length,
      'tokenCount': tokenCount,
      'confidence': confidence,
      'wordsPerToken': wordsPerToken,
      'sentenceCount': sentences.length,
      'qualityLevel': qualityLevel,
      'performanceLevel': performanceLevel,
      'latencyMs': latencyMs,
      'tokensPerSecond': tokensPerSecond,
      'modelUsed': modelUsed,
      'optimizationsUsed': {
        'ple': pleUsed,
        'kvCache': kvCacheUsed,
        'gpu': gpuUsed,
      },
    };
  }

  @override
  String toString() {
    return 'GemmaOutput(text: "${text.length > 50 ? '${text.substring(0, 50)}...' : text}", '
           'confidence: ${confidence.toStringAsFixed(2)}, '
           'tokens: ${tokens.length}, '
           'timestamp: $timestamp)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is GemmaOutput &&
        other.text == text &&
        other.confidence == confidence &&
        other.tokens.length == tokens.length &&
        other.timestamp == timestamp;
  }

  @override
  int get hashCode {
    return Object.hash(text, confidence, tokens.length, timestamp);
  }
}

// Utility class for managing multiple outputs
class GemmaOutputHistory {
  final List<GemmaOutput> _outputs = [];
  final int maxSize;

  GemmaOutputHistory({this.maxSize = 100});

  void add(GemmaOutput output) {
    _outputs.add(output);
    if (_outputs.length > maxSize) {
      _outputs.removeAt(0);
    }
  }

  List<GemmaOutput> get outputs => List.unmodifiable(_outputs);
  int get length => _outputs.length;
  bool get isEmpty => _outputs.isEmpty;
  bool get isNotEmpty => _outputs.isNotEmpty;

  GemmaOutput? get latest => _outputs.isNotEmpty ? _outputs.last : null;
  GemmaOutput? get oldest => _outputs.isNotEmpty ? _outputs.first : null;

  // Statistics across all outputs
  double get averageConfidence {
    if (_outputs.isEmpty) return 0.0;
    return _outputs.map((o) => o.confidence).reduce((a, b) => a + b) / _outputs.length;
  }

  double get averageLatency {
    final latencies = _outputs.map((o) => o.latencyMs).where((l) => l != null).cast<int>();
    if (latencies.isEmpty) return 0.0;
    return latencies.reduce((a, b) => a + b) / latencies.length;
  }

  int get totalTokens => _outputs.map((o) => o.tokenCount).fold(0, (a, b) => a + b);
  int get totalCharacters => _outputs.map((o) => o.characterCount).fold(0, (a, b) => a + b);

  List<GemmaOutput> getByQuality(String quality) {
    return _outputs.where((output) => output.qualityLevel == quality).toList();
  }

  List<GemmaOutput> getHighQuality() {
    return _outputs.where((output) => output.isHighQuality).toList();
  }

  List<GemmaOutput> getRecent(Duration duration) {
    final cutoff = DateTime.now().subtract(duration);
    return _outputs.where((output) => output.timestamp.isAfter(cutoff)).toList();
  }

  void clear() {
    _outputs.clear();
  }

  Map<String, dynamic> getStatistics() {
    return {
      'totalOutputs': length,
      'averageConfidence': averageConfidence,
      'averageLatency': averageLatency,
      'totalTokens': totalTokens,
      'totalCharacters': totalCharacters,
      'qualityDistribution': {
        'excellent': getByQuality('Excellent').length,
        'good': getByQuality('Good').length,
        'fair': getByQuality('Fair').length,
        'poor': getByQuality('Poor').length,
        'veryPoor': getByQuality('Very Poor').length,
      },
      'highQualityPercentage': isEmpty ? 0.0 : (getHighQuality().length / length) * 100,
    };
  }
}