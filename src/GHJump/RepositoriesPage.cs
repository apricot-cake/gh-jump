using GHJump.Core;
using Microsoft.CommandPalette.Extensions;
using Microsoft.CommandPalette.Extensions.Toolkit;

namespace GHJump;

internal sealed partial class RepositoriesPage : DynamicListPage, IDisposable
{
    private readonly GitHubRepositoryProvider _provider = new(new GitHubCli(), new RepositoryCache());
    private readonly CancellationTokenSource _lifetime = new();
    private readonly object _gate = new();
    private readonly RefreshCommand _refresh;
    private RepositoryListItem[] _items = [];
    private bool _loading;
    private bool _disposed;
    private DateTimeOffset _lastLoad;

    internal RepositoriesPage()
    {
        Id = "gh-jump.repositories";
        Title = "GH Jump";
        Name = "Open";
        Icon = JumpIcons.Get("repo");
        PlaceholderText = "Search owner/repository";
        _refresh = new RefreshCommand(this);
        EmptyContent = new CommandItem(_refresh) { Title = "Load repositories", Subtitle = "Uses your GitHub CLI account" };
    }

    public override IListItem[] GetItems()
    {
        bool load;
        RepositoryListItem[] items;
        lock (_gate)
        {
            load = !_disposed && !_loading && DateTimeOffset.UtcNow - _lastLoad > TimeSpan.FromMinutes(5);
            if (load)
            {
                _loading = true;
                _items = [];
            }

            items = _items;
        }

        if (load) { BeginLoad(force: false); }
        return FilterRepositories(items, SearchText);
    }

    public override void UpdateSearchText(string oldSearch, string newSearch) => RaiseItemsChanged();

    internal static IListItem[] FilterRepositories(IEnumerable<RepositoryListItem> items, string query) =>
        ListHelpers.FilterList(items, query, (search, item) => Math.Max(
            ListHelpers.ScoreListItem(search, item),
            FuzzyStringMatcher.ScoreFuzzy(search, item.Repository.FullName))).Cast<IListItem>().ToArray();

    internal void Refresh()
    {
        bool load;
        lock (_gate)
        {
            load = !_disposed && !_loading;
            if (load)
            {
                _loading = true;
                _items = [];
            }
        }

        if (load) { BeginLoad(force: true); }
    }

    private void BeginLoad(bool force)
    {
        IsLoading = true;
        EmptyContent = new CommandItem(new NoOpCommand()) { Title = "Loading repositories…", Subtitle = "GitHub CLI · github.com" };
        _ = LoadAsync(force);
    }

    private async Task LoadAsync(bool force)
    {
        try
        {
            var repositories = await _provider.GetRepositoriesAsync(force, _lifetime.Token).ConfigureAwait(false);
            var items = repositories.Select(repository => new RepositoryListItem(repository)
            {
                MoreCommands = [new CommandContextItem(_refresh)],
            }).ToArray();
            lock (_gate)
            {
                if (_disposed)
                {
                    return;
                }

                _items = items;
            }

            Title = $"GH Jump · {_provider.Account}";
            EmptyContent = new CommandItem(_refresh) { Title = "No repositories", Subtitle = "Check your account, permissions and organization SSO; then refresh" };
        }
        catch (OperationCanceledException) when (_lifetime.IsCancellationRequested)
        {
            return;
        }
        catch (Exception exception)
        {
            lock (_gate)
            {
                if (_disposed)
                {
                    return;
                }

                _items = [];
            }

            var message = exception is GitHubCliException known ? known.Message : "Repository loading failed. Refresh to try again.";
            EmptyContent = new CommandItem(_refresh) { Title = "Could not load repositories", Subtitle = message };
        }
        finally
        {
            bool notify;
            lock (_gate)
            {
                _loading = false;
                _lastLoad = DateTimeOffset.UtcNow;
                notify = !_disposed;
                if (_disposed)
                {
                    _provider.Dispose();
                    _lifetime.Dispose();
                }
            }

            // The host can synchronously call GetItems from these COM callbacks.
            // Never hold the list lock while notifying another process.
            if (notify)
            {
                IsLoading = false;
                RaiseItemsChanged();
            }
        }
    }

    public void Dispose()
    {
        lock (_gate)
        {
            if (_disposed)
            {
                return;
            }

            _disposed = true;
            _lifetime.Cancel();
            if (!_loading)
            {
                _provider.Dispose();
                _lifetime.Dispose();
            }
        }
    }

    private sealed partial class RefreshCommand : InvokableCommand
    {
        private readonly RepositoriesPage _page;

        internal RefreshCommand(RepositoriesPage page)
        {
            _page = page;
            Id = "gh-jump.refresh";
            Name = "Refresh repositories";
            Icon = JumpIcons.Get("sync");
        }

        public override CommandResult Invoke()
        {
            _page.Refresh();
            return CommandResult.KeepOpen();
        }
    }
}
