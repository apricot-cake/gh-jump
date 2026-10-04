namespace GHJump.Core;

public sealed record GitHubRepository(long Id, string Owner, string Name, bool IsPrivate, bool IsFork)
{
    public string FullName => $"{Owner}/{Name}";
}

public sealed record RepositoryAction(string Id, string Title, string Path, string IconName);

public static class RepositoryActions
{
    public static IReadOnlyList<RepositoryAction> Main { get; } = Array.AsReadOnly<RepositoryAction>(
    [
        new("top", "Repository top", "", "repo"),
        new("issues", "Issues", "issues", "issue-opened"),
        new("pulls", "Pull requests", "pulls", "git-pull-request"),
        new("actions", "Actions", "actions", "workflow"),
        new("releases", "Releases", "releases", "tag"),
        new("security", "Security", "security", "shield"),
        new("settings", "Settings", "settings", "gear"),
        new("create", "Create", "", "plus"),
    ]);

    public static IReadOnlyList<RepositoryAction> Create { get; } = Array.AsReadOnly<RepositoryAction>(
    [
        new("create-issue", "Issue", "issues/new", "issue-opened"),
        new("create-pull-request", "Pull request", "compare", "git-pull-request"),
    ]);

    public static RepositoryAction Default => Main[0];

}

public static class RepositoryUrls
{
    public static Uri Build(GitHubRepository repository, string path = "")
    {
        ArgumentNullException.ThrowIfNull(repository);
        ArgumentNullException.ThrowIfNull(path);
        ValidateSegment(repository.Owner);
        ValidateSegment(repository.Name);
        if (path.Length > 0)
        {
            foreach (var segment in path.Split('/'))
            {
                ValidateSegment(segment);
            }
        }

        return new Uri($"https://github.com/{repository.Owner}/{repository.Name}{(path.Length == 0 ? "" : "/" + path)}");
    }

    private static void ValidateSegment(string segment)
    {
        if (string.IsNullOrEmpty(segment) || segment is "." or ".." || !segment.All(character => char.IsAsciiLetterOrDigit(character) || character is '-' or '_' or '.'))
        {
            throw new ArgumentException("GitHub URL segments must contain only ASCII letters, digits, '-', '_' or '.'.", nameof(segment));
        }
    }
}
