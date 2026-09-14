using System.Diagnostics;
using System.Net.Http.Headers;
using System.Reflection;
using System.Security.Cryptography;
using System.Text.Json;

namespace MonitorSwitch.Windows;

public sealed record UpdateRelease(
    Version Version,
    string TagName,
    Uri DownloadUri,
    long DownloadSize,
    Uri ChecksumUri,
    Uri ReleasePageUri);

public sealed class UpdateManager : IDisposable
{
    private const string Repository = "Bugliiiiii/lumen";
    private const string AssetName = "Lumen-Windows-x64.exe";
    private static readonly Uri LatestReleaseUri = new($"https://api.github.com/repos/{Repository}/releases/latest");
    private readonly HttpClient _client;

    public UpdateRelease? LatestRelease { get; private set; }
    public event EventHandler<UpdateRelease>? UpdateAvailable;

    public UpdateManager()
    {
        _client = new HttpClient { Timeout = TimeSpan.FromSeconds(30) };
        _client.DefaultRequestHeaders.UserAgent.Add(new ProductInfoHeaderValue("Lumen", CurrentVersion.ToString(3)));
        _client.DefaultRequestHeaders.Accept.Add(new MediaTypeWithQualityHeaderValue("application/vnd.github+json"));
    }

    public static Version CurrentVersion =>
        Assembly.GetEntryAssembly()?.GetName().Version ?? new Version(0, 3, 0);

    public async Task<UpdateRelease?> CheckForUpdatesAsync(CancellationToken cancellationToken = default)
    {
        using var response = await _client.GetAsync(LatestReleaseUri, cancellationToken);
        response.EnsureSuccessStatusCode();
        await using var body = await response.Content.ReadAsStreamAsync(cancellationToken);
        var release = await JsonSerializer.DeserializeAsync<GitHubRelease>(body, cancellationToken: cancellationToken)
            ?? throw new InvalidDataException("GitHub 返回了空的版本信息");

        if (!TryParseVersion(release.TagName, out var remoteVersion) || remoteVersion <= CurrentVersion)
        {
            LatestRelease = null;
            return null;
        }

        var executable = FindAsset(release, AssetName);
        var checksums = FindAsset(release, "SHA256SUMS.txt");
        if (executable is null || checksums is null || release.HtmlUrl is null)
        {
            throw new InvalidDataException("最新版本缺少 Windows 安装包或校验文件");
        }

        var result = new UpdateRelease(
            remoteVersion,
            release.TagName,
            ValidateReleaseUri(executable.BrowserDownloadUrl),
            ValidateDownloadSize(executable.Size),
            ValidateReleaseUri(checksums.BrowserDownloadUrl),
            ValidateReleasePageUri(release.HtmlUrl));
        LatestRelease = result;
        UpdateAvailable?.Invoke(this, result);
        return result;
    }

    public async Task DownloadAndInstallAsync(UpdateRelease release, CancellationToken cancellationToken = default)
    {
        var currentExecutable = Environment.ProcessPath
            ?? throw new InvalidOperationException("无法确定当前程序路径");
        var temporaryDirectory = Path.Combine(Path.GetTempPath(), $"Lumen-Update-{Guid.NewGuid():N}");
        Directory.CreateDirectory(temporaryDirectory);
        var downloadedPath = Path.Combine(temporaryDirectory, AssetName);
        var updaterPath = Path.Combine(temporaryDirectory, "Lumen-Updater.exe");

        try
        {
            await DownloadFileAsync(release.DownloadUri, release.DownloadSize, downloadedPath, cancellationToken);
            var checksumText = await DownloadTextAsync(release.ChecksumUri, 1_000_000, cancellationToken);
            var expectedHash = ParseChecksum(checksumText, AssetName);
            await using var downloadedFile = File.OpenRead(downloadedPath);
            var actualHash = Convert.ToHexString(await SHA256.HashDataAsync(downloadedFile, cancellationToken));
            if (!actualHash.Equals(expectedHash, StringComparison.OrdinalIgnoreCase))
            {
                throw new InvalidDataException("更新包校验失败，已取消安装");
            }

            File.Copy(currentExecutable, updaterPath, true);
            var startInfo = new ProcessStartInfo(updaterPath) { UseShellExecute = false };
            startInfo.ArgumentList.Add("--apply-update");
            startInfo.ArgumentList.Add(Environment.ProcessId.ToString());
            startInfo.ArgumentList.Add(downloadedPath);
            startInfo.ArgumentList.Add(currentExecutable);
            _ = Process.Start(startInfo) ?? throw new InvalidOperationException("无法启动更新程序");
        }
        catch
        {
            TryDeleteDirectory(temporaryDirectory);
            throw;
        }
    }

    public static bool IsVersionNewer(string candidate, string current) =>
        TryParseVersion(candidate, out var candidateVersion)
        && TryParseVersion(current, out var currentVersion)
        && candidateVersion > currentVersion;

    internal static bool TryRunUpdater(string[] args)
    {
        if (args.Length != 4 || !args[0].Equals("--apply-update", StringComparison.Ordinal))
        {
            return false;
        }

        if (!int.TryParse(args[1], out var parentProcessId))
        {
            return true;
        }

        if (!IsValidUpdaterInvocation(args[2], args[3]))
        {
            MessageBox.Show("更新参数无效，已取消安装", "Lumen 更新失败", MessageBoxButtons.OK, MessageBoxIcon.Error);
            return true;
        }

        ApplyUpdate(parentProcessId, args[2], args[3]);
        return true;
    }

    internal static void ScheduleCleanup(string[] args)
    {
        if (args.Length != 4 || !args[0].Equals("--cleanup-update", StringComparison.Ordinal)
            || !int.TryParse(args[3], out var updaterProcessId))
        {
            return;
        }

        var updaterPath = args[1];
        var backupPath = args[2];
        var expectedBackupPath = (Environment.ProcessPath ?? string.Empty) + ".old";
        if (!IsUnderUpdateTemporaryDirectory(updaterPath)
            || !Path.GetFullPath(backupPath).Equals(Path.GetFullPath(expectedBackupPath), StringComparison.OrdinalIgnoreCase))
        {
            return;
        }
        _ = Task.Run(() =>
        {
            WaitForProcess(updaterProcessId, TimeSpan.FromSeconds(20));
            TryDeleteFile(updaterPath);
            TryDeleteFile(backupPath);
            var directory = Path.GetDirectoryName(updaterPath);
            if (directory is not null) TryDeleteDirectory(directory);
        });
    }

    private static void ApplyUpdate(int parentProcessId, string downloadedPath, string targetPath)
    {
        var updaterPath = Environment.ProcessPath ?? string.Empty;
        var backupPath = targetPath + ".old";
        var incomingPath = targetPath + ".new";

        try
        {
            WaitForProcess(parentProcessId, TimeSpan.FromSeconds(30));
            ValidateExecutable(downloadedPath);
            File.Copy(downloadedPath, incomingPath, true);
            File.Move(targetPath, backupPath, true);
            File.Move(incomingPath, targetPath, true);

            var startInfo = new ProcessStartInfo(targetPath) { UseShellExecute = true };
            startInfo.ArgumentList.Add("--cleanup-update");
            startInfo.ArgumentList.Add(updaterPath);
            startInfo.ArgumentList.Add(backupPath);
            startInfo.ArgumentList.Add(Environment.ProcessId.ToString());
            _ = Process.Start(startInfo) ?? throw new InvalidOperationException("无法重新启动 Lumen");
        }
        catch (Exception exception)
        {
            TryDeleteFile(incomingPath);
            if (File.Exists(backupPath))
            {
                TryDeleteFile(targetPath);
                File.Move(backupPath, targetPath, true);
            }

            MessageBox.Show(exception.Message, "Lumen 更新失败", MessageBoxButtons.OK, MessageBoxIcon.Error);
            if (File.Exists(targetPath)) Process.Start(new ProcessStartInfo(targetPath) { UseShellExecute = true });
        }
    }

    private static bool IsValidUpdaterInvocation(string downloadedPath, string targetPath)
    {
        try
        {
            var updaterPath = Environment.ProcessPath ?? string.Empty;
            var downloadDirectory = Path.GetDirectoryName(Path.GetFullPath(downloadedPath));
            var updaterDirectory = Path.GetDirectoryName(Path.GetFullPath(updaterPath));
            var targetName = Path.GetFileName(targetPath);
            return IsUnderUpdateTemporaryDirectory(updaterPath)
                && downloadDirectory is not null
                && downloadDirectory.Equals(updaterDirectory, StringComparison.OrdinalIgnoreCase)
                && Path.GetFileName(downloadedPath).Equals(AssetName, StringComparison.Ordinal)
                && (targetName.Equals(AssetName, StringComparison.OrdinalIgnoreCase)
                    || targetName.Equals("MonitorSwitch.Windows.exe", StringComparison.OrdinalIgnoreCase));
        }
        catch (Exception exception) when (exception is ArgumentException or IOException or NotSupportedException)
        {
            return false;
        }
    }

    private static bool IsUnderUpdateTemporaryDirectory(string path)
    {
        var fullPath = Path.GetFullPath(path);
        var temporaryRoot = Path.TrimEndingDirectorySeparator(Path.GetFullPath(Path.GetTempPath()))
            + Path.DirectorySeparatorChar;
        var directory = Path.GetDirectoryName(fullPath);
        return directory is not null
            && directory.StartsWith(temporaryRoot, StringComparison.OrdinalIgnoreCase)
            && Path.GetFileName(directory).StartsWith("Lumen-Update-", StringComparison.Ordinal);
    }

    private async Task DownloadFileAsync(Uri uri, long expectedSize, string destination, CancellationToken cancellationToken)
    {
        using var response = await _client.GetAsync(uri, HttpCompletionOption.ResponseHeadersRead, cancellationToken);
        response.EnsureSuccessStatusCode();
        if (response.Content.Headers.ContentLength is { } contentLength && contentLength != expectedSize)
        {
            throw new InvalidDataException("更新包大小异常");
        }

        await using var source = await response.Content.ReadAsStreamAsync(cancellationToken);
        await using var target = new FileStream(destination, FileMode.CreateNew, FileAccess.Write, FileShare.None);
        var buffer = new byte[81_920];
        long total = 0;
        int bytesRead;
        while ((bytesRead = await source.ReadAsync(buffer, cancellationToken)) > 0)
        {
            total += bytesRead;
            if (total > expectedSize) throw new InvalidDataException("更新包大小异常");
            await target.WriteAsync(buffer.AsMemory(0, bytesRead), cancellationToken);
        }
        if (total != expectedSize) throw new InvalidDataException("更新包下载不完整");
        await target.FlushAsync(cancellationToken);
        ValidateExecutable(destination);
    }

    private async Task<string> DownloadTextAsync(Uri uri, int maximumBytes, CancellationToken cancellationToken)
    {
        using var response = await _client.GetAsync(uri, HttpCompletionOption.ResponseHeadersRead, cancellationToken);
        response.EnsureSuccessStatusCode();
        if (response.Content.Headers.ContentLength is { } contentLength && contentLength > maximumBytes)
            throw new InvalidDataException("校验文件大小异常");
        await using var source = await response.Content.ReadAsStreamAsync(cancellationToken);
        using var target = new MemoryStream();
        var buffer = new byte[16_384];
        int bytesRead;
        while ((bytesRead = await source.ReadAsync(buffer, cancellationToken)) > 0)
        {
            if (target.Length + bytesRead > maximumBytes) throw new InvalidDataException("校验文件大小异常");
            target.Write(buffer, 0, bytesRead);
        }
        return System.Text.Encoding.UTF8.GetString(target.ToArray());
    }

    private static long ValidateDownloadSize(long size)
    {
        if (size is <= 0 or > 250_000_000) throw new InvalidDataException("更新包大小异常");
        return size;
    }

    private static GitHubAsset? FindAsset(GitHubRelease release, string name) =>
        release.Assets?.FirstOrDefault(asset => asset.Name.Equals(name, StringComparison.Ordinal));

    private static Uri ValidateReleaseUri(string? value)
    {
        if (!Uri.TryCreate(value, UriKind.Absolute, out var uri)
            || uri.Scheme != Uri.UriSchemeHttps
            || !uri.Host.Equals("github.com", StringComparison.OrdinalIgnoreCase)
            || !uri.AbsolutePath.StartsWith($"/{Repository}/releases/download/", StringComparison.Ordinal))
        {
            throw new InvalidDataException("GitHub 返回了无效的下载地址");
        }
        return uri;
    }

    private static Uri ValidateReleasePageUri(string value)
    {
        if (!Uri.TryCreate(value, UriKind.Absolute, out var uri)
            || uri.Scheme != Uri.UriSchemeHttps
            || !uri.Host.Equals("github.com", StringComparison.OrdinalIgnoreCase)
            || !uri.AbsolutePath.StartsWith($"/{Repository}/releases/tag/", StringComparison.Ordinal))
        {
            throw new InvalidDataException("GitHub 返回了无效的版本页面地址");
        }
        return uri;
    }

    private static string ParseChecksum(string content, string assetName)
    {
        foreach (var line in content.Split('\n', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries))
        {
            var parts = line.Split((char[]?)null, StringSplitOptions.RemoveEmptyEntries);
            if (parts.Length >= 2 && parts[1].TrimStart('*').Equals(assetName, StringComparison.Ordinal)
                && parts[0].Length == 64 && parts[0].All(Uri.IsHexDigit))
            {
                return parts[0];
            }
        }
        throw new InvalidDataException("校验文件中没有 Windows 安装包记录");
    }

    private static bool TryParseVersion(string value, out Version version)
    {
        var normalized = value.Trim().TrimStart('v', 'V').Split('-', '+')[0];
        return Version.TryParse(normalized, out version!);
    }

    private static void ValidateExecutable(string path)
    {
        using var stream = File.OpenRead(path);
        if (stream.Length < 2 || stream.ReadByte() != 'M' || stream.ReadByte() != 'Z')
        {
            throw new InvalidDataException("下载内容不是有效的 Windows 程序");
        }
    }

    private static void WaitForProcess(int processId, TimeSpan timeout)
    {
        try { Process.GetProcessById(processId).WaitForExit((int)timeout.TotalMilliseconds); }
        catch (ArgumentException) { }
    }

    private static void TryDeleteFile(string path)
    {
        try { if (File.Exists(path)) File.Delete(path); }
        catch (IOException) { }
        catch (UnauthorizedAccessException) { }
    }

    private static void TryDeleteDirectory(string path)
    {
        try { if (Directory.Exists(path)) Directory.Delete(path, true); }
        catch (IOException) { }
        catch (UnauthorizedAccessException) { }
    }

    public void Dispose() => _client.Dispose();

    private sealed record GitHubRelease(
        [property: System.Text.Json.Serialization.JsonPropertyName("tag_name")] string TagName,
        [property: System.Text.Json.Serialization.JsonPropertyName("html_url")] string? HtmlUrl,
        [property: System.Text.Json.Serialization.JsonPropertyName("assets")] GitHubAsset[]? Assets);

    private sealed record GitHubAsset(
        [property: System.Text.Json.Serialization.JsonPropertyName("name")] string Name,
        [property: System.Text.Json.Serialization.JsonPropertyName("browser_download_url")] string? BrowserDownloadUrl,
        [property: System.Text.Json.Serialization.JsonPropertyName("size")] long Size);
}
