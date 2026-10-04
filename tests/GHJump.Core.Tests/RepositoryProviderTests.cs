namespace GHJump.Core.Tests;

public sealed class RepositoryProviderTests
{
    private const string Pages = """
        [
          [{"id":1,"name":"private-repo","owner":{"login":"me"},"private":true,"fork":false}],
          [{"id":2,"name":"org-fork","owner":{"login":"organization"},"private":false,"fork":true}]
        ]
        """;

    [Fact]
    public async Task RequestsPaginationAndPreservesPrivateOrganizationAndForkRepositories()
    {
        var cli = new FakeCli("me", Pages);
        var cache = new FakeCache();
        var provider = new GitHubRepositoryProvider(cli, cache);

        var repositories = await provider.GetRepositoriesAsync(cancellationToken: TestContext.Current.CancellationToken);

        Assert.Collection(repositories.OrderBy(r => r.Id),
            r => { Assert.Equal("me/private-repo", r.FullName); Assert.True(r.IsPrivate); },
            r => { Assert.Equal("organization/org-fork", r.FullName); Assert.True(r.IsFork); });
        var request = Assert.Single(cli.Calls, c => c.Contains("user/repos"));
        Assert.Contains("--paginate", request);
        Assert.Contains("--slurp", request);
        Assert.Equal("me", provider.Account);
        Assert.Equal(2, Assert.Single(cache.Entries).Value.Repositories.Count);
    }

    [Fact]
    public async Task FreshCacheAvoidsRepositoryApiButStillValidatesIdentity()
    {
        var cli = new FakeCli("me", Pages);
        var cache = new FakeCache();
        cache.Entries["me"] = new(DateTimeOffset.UtcNow, [new(9, "me", "cached", true, false)]);
        var provider = new GitHubRepositoryProvider(cli, cache);

        var result = await provider.GetRepositoriesAsync(cancellationToken: TestContext.Current.CancellationToken);

        Assert.Equal("cached", Assert.Single(result).Name);
        Assert.Single(cli.Calls);
        Assert.Contains("user", cli.Calls[0]);
    }

    [Fact]
    public async Task ExpiredCacheRefreshesAndForceRefreshBypassesFreshCache()
    {
        var cli = new FakeCli("me", Pages);
        var cache = new FakeCache();
        cache.Entries["me"] = new(DateTimeOffset.UtcNow.AddDays(-1), [new(9, "me", "old", false, false)]);
        var provider = new GitHubRepositoryProvider(cli, cache);

        Assert.Equal(2, (await provider.GetRepositoriesAsync(cancellationToken: TestContext.Current.CancellationToken)).Count);
        Assert.Equal(2, (await provider.GetRepositoriesAsync(true, TestContext.Current.CancellationToken)).Count);
        Assert.Equal(2, cli.Calls.Count(c => c.Contains("user/repos")));
    }

    [Fact]
    public async Task SwitchingAccountsDoesNotReusePreviousAccountsPrivateCache()
    {
        var cli = new FakeCli("other", Pages);
        var cache = new FakeCache();
        cache.Entries["me"] = new(DateTimeOffset.UtcNow, [new(9, "me", "secret", true, false)]);
        var provider = new GitHubRepositoryProvider(cli, cache);

        var result = await provider.GetRepositoriesAsync(cancellationToken: TestContext.Current.CancellationToken);

        Assert.DoesNotContain(result, r => r.Name == "secret");
        Assert.Equal("other", provider.Account);
        Assert.Contains("other", cache.Entries.Keys);
    }

    [Theory]
    [InlineData(FailureKind.Network)]
    [InlineData(FailureKind.RateLimit)]
    public async Task ApiFailureIsReportedAndDoesNotOverwriteCache(FailureKind kind)
    {
        var cli = new FakeCli("me", Pages) { RepositoryFailure = new(kind, "API unavailable") };
        var cache = new FakeCache();
        var cached = new RepositoryCacheEntry(DateTimeOffset.UtcNow.AddDays(-1), [new(9, "me", "previous", true, false)]);
        cache.Entries["me"] = cached;
        var provider = new GitHubRepositoryProvider(cli, cache);

        var error = await Assert.ThrowsAsync<GitHubCliException>(() => provider.GetRepositoriesAsync(true, TestContext.Current.CancellationToken));

        Assert.Equal(kind, error.Kind);
        Assert.Same(cached, cache.Entries["me"]);
    }

    [Fact]
    public async Task ExpiredAuthenticationCannotRevealCachedRepositories()
    {
        var cli = new FakeCli("me", Pages) { IdentityFailure = new(FailureKind.Authentication, "Log in again") };
        var cache = new FakeCache();
        cache.Entries["me"] = new(DateTimeOffset.UtcNow, [new(9, "me", "secret", true, false)]);
        var provider = new GitHubRepositoryProvider(cli, cache);

        await Assert.ThrowsAsync<GitHubCliException>(() => provider.GetRepositoriesAsync(cancellationToken: TestContext.Current.CancellationToken));

        Assert.Null(provider.Account);
        Assert.Single(cli.Calls);
    }

    [Fact]
    public async Task MalformedApiResponseIsReportedWithoutCachingIt()
    {
        var cache = new FakeCache();
        var provider = new GitHubRepositoryProvider(new FakeCli("me", "not JSON"), cache);
        var error = await Assert.ThrowsAsync<GitHubCliException>(() => provider.GetRepositoriesAsync(cancellationToken: TestContext.Current.CancellationToken));
        Assert.Equal(FailureKind.InvalidResponse, error.Kind);
        Assert.Empty(cache.Entries);
    }

    private sealed class FakeCli(string account, string pages) : IGitHubCli
    {
        public List<string[]> Calls { get; } = [];
        public GitHubCliException? IdentityFailure { get; init; }
        public GitHubCliException? RepositoryFailure { get; init; }

        public Task<string> RunAsync(IReadOnlyList<string> arguments, CancellationToken cancellationToken)
        {
            cancellationToken.ThrowIfCancellationRequested();
            Calls.Add(arguments.ToArray());
            if (arguments.Contains("user/repos"))
            {
                return RepositoryFailure is null ? Task.FromResult(pages) : Task.FromException<string>(RepositoryFailure);
            }

            return IdentityFailure is null
                ? Task.FromResult("{\"login\":\"" + account + "\",\"id\":10}")
                : Task.FromException<string>(IdentityFailure);
        }
    }

    private sealed class FakeCache : IRepositoryCache
    {
        public Dictionary<string, RepositoryCacheEntry> Entries { get; } = [];

        public Task<RepositoryCacheEntry?> ReadAsync(string account, CancellationToken cancellationToken)
        {
            cancellationToken.ThrowIfCancellationRequested();
            return Task.FromResult(Entries.GetValueOrDefault(account));
        }

        public Task WriteAsync(string account, RepositoryCacheEntry entry, CancellationToken cancellationToken)
        {
            cancellationToken.ThrowIfCancellationRequested();
            Entries[account] = entry;
            return Task.CompletedTask;
        }
    }
}
