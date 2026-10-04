namespace GHJump.Core.Tests;

public sealed class CacheTests : IDisposable
{
    private readonly string _directory = Path.Combine(Path.GetTempPath(), "GHJump.Tests", Guid.NewGuid().ToString("N"));

    [Fact]
    public async Task PersistentCacheRoundTripsPrivateRepositoriesAndSeparatesAccounts()
    {
        var writer = new RepositoryCache(_directory);
        var entry = new RepositoryCacheEntry(DateTimeOffset.UtcNow, [new(7, "team", "private", true, true)]);
        await writer.WriteAsync("me", entry, TestContext.Current.CancellationToken);

        var reader = new RepositoryCache(_directory);
        var restored = await reader.ReadAsync("ME", TestContext.Current.CancellationToken);

        Assert.NotNull(restored);
        Assert.Equal(entry.SavedAt, restored.SavedAt);
        Assert.Equal(entry.Repositories, restored.Repositories);
        Assert.Null(await reader.ReadAsync("other", TestContext.Current.CancellationToken));
    }

    [Theory]
    [InlineData("not JSON")]
    [InlineData("{}")]
    [InlineData("{\"SavedAt\":\"2026-10-04T00:00:00Z\",\"Repositories\":null}")]
    [InlineData("{\"SavedAt\":\"2026-10-04T00:00:00Z\",\"Repositories\":[null]}")]
    public async Task CorruptCacheIsTreatedAsMissing(string contents)
    {
        Directory.CreateDirectory(_directory);
        await File.WriteAllTextAsync(Path.Combine(_directory, "me.json"), contents, TestContext.Current.CancellationToken);
        Assert.Null(await new RepositoryCache(_directory).ReadAsync("me", TestContext.Current.CancellationToken));
    }

    [Fact]
    public async Task UnsafeAccountCannotEscapeCacheDirectory()
    {
        Assert.Null(await new RepositoryCache(_directory).ReadAsync("../other", TestContext.Current.CancellationToken));
    }

    public void Dispose()
    {
        var root = Path.GetFullPath(Path.Combine(Path.GetTempPath(), "GHJump.Tests")) + Path.DirectorySeparatorChar;
        var target = Path.GetFullPath(_directory);
        if (target.StartsWith(root, StringComparison.OrdinalIgnoreCase) && Directory.Exists(target))
        {
            Directory.Delete(target, recursive: true);
        }

        GC.SuppressFinalize(this);
    }
}
