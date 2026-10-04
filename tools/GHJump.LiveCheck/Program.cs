using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Text.Json;
using GHJump.Core;
using Microsoft.CommandPalette.Extensions;
using Microsoft.CommandPalette.Extensions.Toolkit;

if (args.Contains("--activate", StringComparer.Ordinal))
{
    var classId = new Guid("CD969A05-A92B-49AC-90AB-69DA0B998467");
    var interfaceId = WinRT.GuidGenerator.GetIID(typeof(IExtension));
    Marshal.ThrowExceptionForHR(NativeMethods.CoCreateInstance(ref classId, IntPtr.Zero, 4, ref interfaceId, out var pointer));
    var extension = WinRT.MarshalInterface<IExtension>.FromAbi(pointer);
    Marshal.Release(pointer);
    var provider = (ICommandProvider)extension.GetProvider(ProviderType.Commands)!;
    var commands = provider.TopLevelCommands();
    if (commands.Length != 1 || commands[0].Title != "GH Jump")
    {
        throw new InvalidOperationException("The registered COM extension returned invalid commands.");
    }

    Console.WriteLine("Packaged COM activation: passed; GH Jump command received.");
    if (args.Contains("--load", StringComparer.Ordinal))
    {
        var page = (IListPage)commands[0].Command;
        var loading = Stopwatch.StartNew();
        var items = page.GetItems();
        while (items.Length == 0 && loading.Elapsed < TimeSpan.FromSeconds(30))
        {
            await Task.Delay(200);
            items = page.GetItems();
        }

        var repositoryItem = items.Single(item => item.Title == "apricot-cake/gh-jump");
        var actionsPage = (IListPage)repositoryItem.Command;
        var actions = actionsPage.GetItems();
        if (actions[0].Title != "Repository top" || actions.Length != 8)
        {
            throw new InvalidOperationException("The repository action page returned invalid items.");
        }

        var createPage = (IListPage)actions.Single(item => item.Title == "Create").Command;
        var createItems = createPage.GetItems();
        if (createItems.Length != 2 || createItems[0].Title != "Issue" || createItems[1].Title != "Pull request")
        {
            throw new InvalidOperationException("The Create page returned invalid items.");
        }

        Console.WriteLine($"COM repository retrieval: passed; {items.Length} items; action and Create pages passed.");
    }

    (extension as IDisposable)?.Dispose();
    return;
}

var cli = new GitHubCli();
using var repositoryProvider = new GitHubRepositoryProvider(cli, new RepositoryCache(Path.Combine(Environment.CurrentDirectory, "artifacts", "live-cache")));
var timer = Stopwatch.StartNew();
var repositories = await repositoryProvider.GetRepositoriesAsync(forceRefresh: true);
Console.WriteLine($"Live account: {repositoryProvider.Account}; repositories: {repositories.Count}; private: {repositories.Count(r => r.IsPrivate)}; forks: {repositories.Count(r => r.IsFork)}; fetch: {timer.ElapsedMilliseconds} ms");
using var organizations = JsonDocument.Parse(await cli.RunAsync(["api", "user/orgs", "--hostname", "github.com", "--paginate", "--slurp"], CancellationToken.None));
var owners = organizations.RootElement.EnumerateArray().SelectMany(page => page.EnumerateArray()).Select(org => org.GetProperty("login").GetString()).ToHashSet(StringComparer.OrdinalIgnoreCase);
Console.WriteLine($"Visible organizations: {owners.Count}; repositories belonging to them: {repositories.Count(r => owners.Contains(r.Owner))}");
if (!repositories.Any(r => r.FullName.Equals("apricot-cake/gh-jump", StringComparison.OrdinalIgnoreCase) && r.IsPrivate))
{
    throw new InvalidOperationException("The private GH Jump repository was not returned.");
}

timer.Restart();
var cached = await repositoryProvider.GetRepositoriesAsync();
if (!repositories.SequenceEqual(cached))
{
    throw new InvalidOperationException("The cached list differed from the fetched list.");
}

Console.WriteLine($"Cache path: passed; account validated; {timer.ElapsedMilliseconds} ms");
var names = Enumerable.Range(0, 500).Select(index => $"organization-{index % 20}/repository-{index:D4}").ToArray();
timer.Restart();
for (var iteration = 0; iteration < 200; iteration++)
{
    _ = names.Select(name => FuzzyStringMatcher.ScoreFuzzy("org/repo", name)).ToArray();
}

Console.WriteLine($"Official fuzzy matcher: 500 repositories; mean {timer.Elapsed.TotalMilliseconds / 200:F2} ms per query");

internal static partial class NativeMethods
{
    [LibraryImport("ole32.dll")]
    internal static partial int CoCreateInstance(ref Guid classId, IntPtr outer, uint context, ref Guid interfaceId, out IntPtr pointer);
}
