using System.ComponentModel;
using System.Diagnostics;

namespace GHJump.Core;

public enum FailureKind
{
    Authentication,
    Network,
    RateLimit,
    CliUnavailable,
    InvalidResponse,
    Unknown,
}

public sealed class GitHubCliException(FailureKind kind, string message) : Exception(message)
{
    public FailureKind Kind { get; } = kind;
}

public interface IGitHubCli
{
    Task<string> RunAsync(IReadOnlyList<string> arguments, CancellationToken cancellationToken);
}

public sealed class GitHubCli : IGitHubCli
{
    private readonly string? _executable;
    private readonly TimeSpan _timeout;

    public GitHubCli(string? executable = null, TimeSpan? timeout = null)
    {
        _executable = executable is null ? LocateExecutable() : Path.GetFullPath(executable);
        _timeout = timeout ?? TimeSpan.FromMinutes(2);
    }

    public async Task<string> RunAsync(IReadOnlyList<string> arguments, CancellationToken cancellationToken)
    {
        if (_executable is null || !File.Exists(_executable))
        {
            throw new GitHubCliException(FailureKind.CliUnavailable, "GitHub CLI was not found. Install it and run gh auth login.");
        }

        var startInfo = new ProcessStartInfo(_executable)
        {
            UseShellExecute = false,
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            CreateNoWindow = true,
        };
        foreach (var argument in arguments)
        {
            startInfo.ArgumentList.Add(argument);
        }

        startInfo.Environment.Remove("GH_DEBUG");
        startInfo.Environment["GH_PROMPT_DISABLED"] = "1";
        startInfo.Environment["GH_NO_UPDATE_NOTIFIER"] = "1";
        startInfo.Environment["NO_COLOR"] = "1";
        using var process = new Process { StartInfo = startInfo };
        using var timeout = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
        timeout.CancelAfter(_timeout);
        try
        {
            process.Start();
            var stdout = process.StandardOutput.ReadToEndAsync(timeout.Token);
            var stderr = process.StandardError.ReadToEndAsync(timeout.Token);
            await process.WaitForExitAsync(timeout.Token).ConfigureAwait(false);
            var output = await stdout.ConfigureAwait(false);
            var error = await stderr.ConfigureAwait(false);
            if (process.ExitCode != 0)
            {
                throw CategorizeFailure(error);
            }

            return output;
        }
        catch (OperationCanceledException) when (!cancellationToken.IsCancellationRequested)
        {
            throw new GitHubCliException(FailureKind.Network, "GitHub CLI timed out. Try refreshing again.");
        }
        catch (Win32Exception)
        {
            throw new GitHubCliException(FailureKind.CliUnavailable, "GitHub CLI could not be started.");
        }
        finally
        {
            try
            {
                if (!process.HasExited)
                {
                    process.Kill(entireProcessTree: true);
                }
            }
            catch (InvalidOperationException)
            {
                // Process startup may have failed.
            }
        }
    }

    public static GitHubCliException CategorizeFailure(string error)
    {
        if (error.Contains("HTTP 401", StringComparison.OrdinalIgnoreCase) || error.Contains("authentication", StringComparison.OrdinalIgnoreCase) || error.Contains("gh auth login", StringComparison.OrdinalIgnoreCase) || error.Contains("Bad credentials", StringComparison.OrdinalIgnoreCase))
        {
            return new(FailureKind.Authentication, "GitHub authentication is unavailable or expired. Run gh auth login --hostname github.com.");
        }

        if (error.Contains("rate limit", StringComparison.OrdinalIgnoreCase))
        {
            return new(FailureKind.RateLimit, "GitHub API rate limit exceeded. Try again later.");
        }

        if (error.Contains("HTTP 403", StringComparison.OrdinalIgnoreCase))
        {
            return new(FailureKind.Authentication, "GitHub access was denied. Check your account, organization SSO and token permissions.");
        }

        if (error.Contains("connect", StringComparison.OrdinalIgnoreCase) || error.Contains("timeout", StringComparison.OrdinalIgnoreCase) || error.Contains("resolve", StringComparison.OrdinalIgnoreCase) || error.Contains("HTTP 5", StringComparison.OrdinalIgnoreCase))
        {
            return new(FailureKind.Network, "GitHub could not be reached. Check your connection and refresh.");
        }

        return new(FailureKind.Unknown, "GitHub CLI failed. Check gh auth status and try refreshing.");
    }

    private static string? LocateExecutable()
    {
        var candidates = new List<string>();
        var programFiles = Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles);
        if (programFiles.Length > 0)
        {
            candidates.Add(Path.Combine(programFiles, "GitHub CLI", "gh.exe"));
        }

        foreach (var directory in (Environment.GetEnvironmentVariable("PATH") ?? "").Split(Path.PathSeparator, StringSplitOptions.RemoveEmptyEntries))
        {
            if (Path.IsPathFullyQualified(directory.Trim('"')))
            {
                candidates.Add(Path.Combine(directory.Trim('"'), OperatingSystem.IsWindows() ? "gh.exe" : "gh"));
            }
        }

        return candidates.FirstOrDefault(File.Exists);
    }
}
