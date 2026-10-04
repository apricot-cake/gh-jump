using System.Text.Json;

namespace GHJump.Core;

public sealed record RepositoryCacheEntry(DateTimeOffset SavedAt, IReadOnlyList<GitHubRepository> Repositories);

public interface IRepositoryCache
{
    Task<RepositoryCacheEntry?> ReadAsync(string account, CancellationToken cancellationToken);

    Task WriteAsync(string account, RepositoryCacheEntry entry, CancellationToken cancellationToken);
}

public sealed class RepositoryCache : IRepositoryCache
{
    private readonly string _directory;
    private readonly Dictionary<string, RepositoryCacheEntry> _memory = new(StringComparer.OrdinalIgnoreCase);

    public RepositoryCache(string? directory = null)
    {
        _directory = directory ?? Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "GHJump", "Cache");
    }

    public async Task<RepositoryCacheEntry?> ReadAsync(string account, CancellationToken cancellationToken)
    {
        if (_memory.TryGetValue(account, out var entry))
        {
            return entry;
        }

        try
        {
            await using var stream = File.OpenRead(GetPath(account));
            entry = await JsonSerializer.DeserializeAsync<RepositoryCacheEntry>(stream, cancellationToken: cancellationToken).ConfigureAwait(false);
            if (entry is null || entry.SavedAt == default || entry.Repositories is null)
            {
                return null;
            }

            foreach (var repository in entry.Repositories)
            {
                if (repository is null || repository.Id <= 0)
                {
                    return null;
                }

                _ = RepositoryUrls.Build(repository);
            }

            _memory[account] = entry;
            return entry;
        }
        catch (Exception exception) when (exception is IOException or UnauthorizedAccessException or JsonException or ArgumentException)
        {
            return null;
        }
    }

    public async Task WriteAsync(string account, RepositoryCacheEntry entry, CancellationToken cancellationToken)
    {
        _memory[account] = entry;
        var path = GetPath(account);
        var temporaryPath = path + "." + Guid.NewGuid().ToString("N") + ".tmp";
        try
        {
            Directory.CreateDirectory(_directory);
            await using (var stream = new FileStream(temporaryPath, FileMode.CreateNew, FileAccess.Write, FileShare.None))
            {
                await JsonSerializer.SerializeAsync(stream, entry, cancellationToken: cancellationToken).ConfigureAwait(false);
            }

            File.Move(temporaryPath, path, overwrite: true);
        }
        catch (Exception exception) when (exception is IOException or UnauthorizedAccessException)
        {
            // Cache failure must not prevent the freshly fetched list from being used.
        }
        finally
        {
            try
            {
                File.Delete(temporaryPath);
            }
            catch (Exception exception) when (exception is IOException or UnauthorizedAccessException)
            {
                // Best-effort removal of an incomplete cache write.
            }
        }
    }

    private string GetPath(string account)
    {
        if (string.IsNullOrEmpty(account) || !account.All(character => char.IsAsciiLetterOrDigit(character) || character == '-'))
        {
            throw new ArgumentException("Invalid GitHub account name.", nameof(account));
        }

        return Path.Combine(_directory, account.ToLowerInvariant() + ".json");
    }
}
