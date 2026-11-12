/// 网页读取失败的稳定分类，供工具协议与本地化界面共同使用。
enum AiWebProblem {
  invalidUrl,
  unsupportedScheme,
  unsupportedPort,
  credentialsNotAllowed,
  blockedAddress,
  dns,
  connection,
  timeout,
  tls,
  httpStatus,
  invalidRedirect,
  redirectLoop,
  tooManyRedirects,
  contentType,
  encoding,
  tooLarge,
  emptyContent,
  cancelled,
}

class AiWebFailure extends FormatException {
  const AiWebFailure(this.problem, {this.url, this.statusCode});

  final AiWebProblem problem;
  final Uri? url;
  final int? statusCode;

  Map<String, Object?> toJson() => {
    'ok': false,
    'error_code': problem.name,
    if (url != null) 'url': url.toString(),
    if (statusCode != null) 'status_code': statusCode,
  };

  @override
  String toString() => 'Web request failed: ${problem.name}';
}
