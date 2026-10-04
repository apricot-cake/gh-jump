using System.Text.Json;

namespace GHJump.Core;

public sealed class GitHubRepositoryProvider : IDisposable
{
    private readonly IGitHubCli _cli;
    private readonly IRepositoryCache _cache;
    private readonly TimeProvider _timeProvider;
    private readonly TimeSpan _cacheLifetime;
    private readonly SemaphoreSlim _gate = new(1, 1);

    public GitHubRepositoryProvider(IGitHubCli cli, IRepositoryCache cache, TimeProvider? timeProvider = null, TimeSpan? cacheLifetime = null)
    {
        _cli = cli;
        _cache = cache;
        _timeProvider = timeProvider ?? TimeProvider.System;
        _cacheLifetime = cacheLifetime ?? TimeSpan.FromMinutes(5);
    }

    public string? Account { get; private set; }

    public void Dispose() => _gate.Dispose();

    public async Task<IReadOnlyList<GitHubRepository>> GetRepositoriesAsync(bool forceRefresh = false, CancellationToken cancellationToken = default)
    {
        await _gate.WaitAsync(cancellationToken).ConfigureAwait(false);
        try
        {
            // Validate the effective account, including GH_TOKEN overrides, before reading its cache.
            Account = null;
            var userJson = await _cli.RunAsync(["api", "user", "--hostname", "github.com"], cancellationToken).ConfigureAwait(false);
            var account = ParseAccount(userJson);
            Account = account;
            var cached = forceRefresh ? null : await _cache.ReadAsync(account, cancellationToken).ConfigureAwait(false);
            var now = _timeProvider.GetUtcNow();
            if (cached is not null && cached.SavedAt <= now && now - cached.SavedAt < _cacheLifetime)
            {
                return cached.Repositories;
            }

            var repositoriesJson = await _cli.RunAsync(
                ["api", "--hostname", "github.com", "--method", "GET", "user/repos", "-f", "affiliation=owner,collaborator,organization_member", "-f", "per_page=100", "--paginate", "--slurp"], cancellationToken).ConfigureAwait(false);
            var repositories = ParseRepositories(repositoriesJson);
            await _cache.WriteAsync(account, new RepositoryCacheEntry(now, repositories), cancellationToken).ConfigureAwait(false);
            return repositories;
        }
        finally
        {
            _gate.Release();
        }
    }

    private static string ParseAccount(string json)
    {
        try
        {
            using var document = JsonDocument.Parse(json);
            var account = document.RootElement.GetProperty("login").GetString();
            if (string.IsNullOrEmpty(account) || !account.All(character => char.IsAsciiLetterOrDigit(character) || character == '-'))
            {
                throw new GitHubCliException(FailureKind.InvalidResponse, "GitHub returned an invalid account.");
            }

            return account;
        }
        catch (Exception exception) when (exception is JsonException or KeyNotFoundException or InvalidOperationException)
        {
            throw new GitHubCliException(FailureKind.InvalidResponse, "GitHub returned an invalid account response.");
        }
    }

    public static IReadOnlyList<GitHubRepository> ParseRepositories(string json)
    {
        try
        {
            using var document = JsonDocument.Parse(json);
            var repositories = new Dictionary<long, GitHubRepository>();
            foreach (var page in document.RootElement.EnumerateArray())
            {
                foreach (var item in page.EnumerateArray())
                {
                    var repository = new GitHubRepository(item.GetProperty("id").GetInt64(), item.GetProperty("owner").GetProperty("login").GetString()!, item.GetProperty("name").GetString()!, item.GetProperty("private").GetBoolean(), item.GetProperty("fork").GetBoolean());
                    // Check external values before passing them into URL commands or disk cache.
                    _ = RepositoryUrls.Build(repository);
                    repositories[repository.Id] = repository;
                }
            }

            return repositories.Values.OrderBy(repository => repository.FullName, StringComparer.OrdinalIgnoreCase).ToArray();
        }
        catch (Exception exception) when (exception is JsonException or KeyNotFoundException or InvalidOperationException or FormatException or ArgumentException)
        {
            throw new GitHubCliException(FailureKind.InvalidResponse, "GitHub returned an invalid repository response.");
        }
    }
}
