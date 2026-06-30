class SystemResetResult {
  const SystemResetResult({
    required this.systemId,
    required this.resetType,
    required this.powerState,
    required this.message,
  });

  final String systemId;
  final String resetType;
  final String? powerState;
  final String? message;

  factory SystemResetResult.fromJson(Map<String, dynamic> json) {
    return SystemResetResult(
      systemId: json['systemId'] as String,
      resetType: json['resetType'] as String,
      powerState: json['powerState'] as String?,
      message: json['message'] as String?,
    );
  }
}
