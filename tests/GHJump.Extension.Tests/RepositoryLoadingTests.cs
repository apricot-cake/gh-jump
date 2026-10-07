using GHJump.Core;
using Microsoft.CommandPalette.Extensions;

namespace GHJump.Extension.Tests;

public sealed class RepositoryLoadingTests
{
    private const string Repositories = """
        [[{"id":123,"owner":{"login":"octocat"},"name":"hello-world","private":true,"fork":false}]]
        """;

    [Fact]
    public async Task FirstFetchReturnsLoadedItemsWithoutAnItemsChangedSubscription()
    {
        var cli = new DelayedCli();
        using var page = new RepositoriesPage(new GitHubRepositoryProvider(cli, new EmptyCache()));
        var fetch = Task.Run(page.GetItems, TestContext.Current.CancellationToken);
        await cli.Requested.Task.WaitAsync(TimeSpan.FromSeconds(10), TestContext.Current.CancellationToken);
        cli.Response.SetResult(Repositories);

        var items = await fetch.WaitAsync(TimeSpan.FromSeconds(10), TestContext.Current.CancellationToken);

        Assert.Equal("octocat/hello-world", Assert.Single(items).Subtitle);
        Assert.False(page.IsLoading);
        Assert.Equal("GH Jump · octocat", page.Title);
        Assert.Single(page.GetItems());
    }

    [Fact]
    public async Task RefreshNotificationCanFetchTheCompletedListSynchronously()
    {
        var cli = new DelayedCli();
        cli.Response.SetResult(Repositories);
        using var page = new RepositoriesPage(new GitHubRepositoryProvider(cli, new EmptyCache()));
        Assert.Single(page.GetItems());
        cli.Response = new(TaskCreationOptions.RunContinuationsAsynchronously);
        var updated = new TaskCompletionSource<IListItem[]>(TaskCreationOptions.RunContinuationsAsynchronously);
        page.ItemsChanged += (_, _) => updated.TrySetResult(page.GetItems());

        page.Refresh();
        cli.Response.SetResult("[]");

        var items = await updated.Task.WaitAsync(TimeSpan.FromSeconds(10), TestContext.Current.CancellationToken);
        Assert.Empty(items);
        Assert.False(page.IsLoading);
        Assert.NotNull(page.EmptyContent);
        Assert.Equal("No repositories", page.EmptyContent.Title);
    }

    private sealed class DelayedCli : IGitHubCli
    {
        public TaskCompletionSource Requested { get; } = new(TaskCreationOptions.RunContinuationsAsynchronously);
        public TaskCompletionSource<string> Response { get; set; } = new(TaskCreationOptions.RunContinuationsAsynchronously);

        public Task<string> RunAsync(IReadOnlyList<string> arguments, CancellationToken cancellationToken)
        {
            if (!arguments.Contains("user/repos")) { return Task.FromResult("{\"login\":\"octocat\"}"); }
            Requested.TrySetResult();
            return Response.Task.WaitAsync(cancellationToken);
        }
    }

    private sealed class EmptyCache : IRepositoryCache
    {
        public Task<RepositoryCacheEntry?> ReadAsync(string account, CancellationToken cancellationToken) => Task.FromResult<RepositoryCacheEntry?>(null);
        public Task WriteAsync(string account, RepositoryCacheEntry entry, CancellationToken cancellationToken) => Task.CompletedTask;
    }
}
