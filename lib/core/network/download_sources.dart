/// 仅为 GitHub HTTPS 发布资产添加备用源，局域网和其他站点保持原地址。
List<Uri> githubDownloadSources(Uri uri) =>
    uri.scheme == 'https' &&
        uri.host == 'github.com' &&
        !uri.hasPort &&
        uri.userInfo.isEmpty
    ? [uri, Uri.parse('https://gh-proxy.com/$uri')]
    : [uri];
