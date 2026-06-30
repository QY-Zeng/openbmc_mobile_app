class PythonScriptJob {
  const PythonScriptJob({
    required this.jobId,
    required this.scriptName,
    required this.status,
    required this.createdAt,
    required this.startedAt,
    required this.completedAt,
    required this.durationMs,
    required this.exitCode,
    required this.stdout,
    required this.stderr,
    required this.structuredOutput,
    required this.error,
    required this.workingDirectory,
    required this.inputJson,
  });

  final String jobId;
  final String scriptName;
  final String status;
  final String createdAt;
  final String? startedAt;
  final String? completedAt;
  final int? durationMs;
  final int? exitCode;
  final String? stdout;
  final String? stderr;
  final Object? structuredOutput;
  final String? error;
  final String? workingDirectory;
  final Object? inputJson;

  bool get isTerminal => switch (status) {
    'completed' || 'failed' || 'timed_out' || 'cancelled' => true,
    _ => false,
  };

  bool get isRunningLike => switch (status) {
    'queued' || 'running' => true,
    _ => false,
  };

  factory PythonScriptJob.fromJson(Map<String, dynamic> json) {
    return PythonScriptJob(
      jobId: json['jobId'] as String,
      scriptName: json['scriptName'] as String,
      status: json['status'] as String,
      createdAt: json['createdAt'] as String,
      startedAt: json['startedAt'] as String?,
      completedAt: json['completedAt'] as String?,
      durationMs: json['durationMs'] as int?,
      exitCode: json['exitCode'] as int?,
      stdout: json['stdout'] as String?,
      stderr: json['stderr'] as String?,
      structuredOutput: json['structuredOutput'],
      error: json['error'] as String?,
      workingDirectory: json['workingDirectory'] as String?,
      inputJson: json['inputJson'],
    );
  }
}
